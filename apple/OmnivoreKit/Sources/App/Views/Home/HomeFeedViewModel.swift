import Combine
import CoreData
import Models
import OSLog
import Services
import SwiftUI
import Utils
import Views

let logger = Logger(subsystem: "app.omnivore", category: "models")

// swiftlint:disable type_body_length
@MainActor final class HomeFeedViewModel: NSObject, ObservableObject {
  var currentDetailViewModel: LinkItemDetailViewModel?

  private var fetchedResultsController: NSFetchedResultsController<LinkedItem>?
  private var storageNotificationCancellable: AnyCancellable?

  @Published var items = [LinkedItem]()
  @Published var isLoading = false
  @Published var showPushNotificationPrimer = false
  @Published var itemUnderLabelEdit: LinkedItem?
  @Published var itemUnderTitleEdit: LinkedItem?
  @Published var itemForHighlightsView: LinkedItem?
  @Published var searchTerm = ""
  @Published var scopeSelection = 0
  @Published var selectedLabels = [LinkedItemLabel]()
  @Published var negatedLabels = [LinkedItemLabel]()
  @Published var snoozePresented = false
  @Published var itemToSnoozeID: String?
  @Published var linkRequest: LinkRequest?
  @Published var showLoadingBar = false
  @Published var appliedSort = LinkedItemSort.newest.rawValue

  @Published var selectedLinkItem: NSManagedObjectID? // used by mac app only
  @Published var selectedItem: LinkedItem?
  @Published var linkIsActive = false

  @Published var showLabelsSheet = false
  @Published var showCommunityModal = false

  var cursor: String?

  // These are used to make sure we handle search result
  // responses in the right order
  var searchIdx = 0
  var receivedIdx = 0

  var syncCursor: String?

  @AppStorage(UserDefaultKey.lastSelectedLinkedItemFilter.rawValue) var appliedFilter = LinkedItemFilter.inbox.rawValue

  func handleReaderItemNotification(objectID: NSManagedObjectID, dataService: DataService) {
    // Pop the current selected item if needed
    if selectedItem != nil, selectedItem?.objectID != objectID {
      // Temporarily disable animation to avoid excessive animations
      #if os(iOS)
        UIView.setAnimationsEnabled(false)
      #endif

      linkIsActive = false
      selectedItem = nil

      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
        self.selectedLinkItem = objectID
        self.selectedItem = dataService.viewContext.object(with: objectID) as? LinkedItem
        self.linkIsActive = true
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
        #if os(iOS)
          UIView.setAnimationsEnabled(true)
        #endif
      }
    } else {
      selectedLinkItem = objectID
      selectedItem = dataService.viewContext.object(with: objectID) as? LinkedItem
      linkIsActive = true
    }
  }

  func itemAppeared(item: LinkedItem, dataService: DataService) async {
    if isLoading { return }
    let itemIndex = items.firstIndex(where: { $0.id == item.id })
    let thresholdIndex = items.index(items.endIndex, offsetBy: -5)

    // Check if user has scrolled to the last five items in the list
    // Make sure we aren't currently loading though, as this would get triggered when the first set
    // of items are presented to the user.
    if let itemIndex = itemIndex, itemIndex > thresholdIndex {
      await loadMoreItems(dataService: dataService, isRefresh: false)
    }
  }

  func pushFeedItem(item: LinkedItem) {
    items.insert(item, at: 0)
  }

  func loadCurrentViewer(dataService: DataService) async {
    // Cache the viewer
    if dataService.currentViewer == nil {
      _ = try? await dataService.fetchViewer()
    }
  }

  func loadLabels(dataService: DataService) async {
    let fetchRequest: NSFetchRequest<Models.LinkedItemLabel> = LinkedItemLabel.fetchRequest()
    fetchRequest.fetchLimit = 1

    if (try? dataService.viewContext.count(for: fetchRequest)) == 0 {
      _ = try? await dataService.labels()
    }
  }

  func syncItems(dataService: DataService) async {
    let syncStart = Date.now
    let lastSyncDate = dataService.lastItemSyncTime

    try? await dataService.syncOfflineItemsWithServerIfNeeded()

    let syncResult = try? await dataService.syncLinkedItems(since: lastSyncDate,
                                                            cursor: nil)

    syncCursor = syncResult?.cursor
    if let syncResult = syncResult, syncResult.hasMore {
      dataService.syncLinkedItemsInBackground(since: lastSyncDate) {
        // Set isLoading to false here
        self.isLoading = false
      }
    } else {
      dataService.lastItemSyncTime = syncStart
    }

    // If possible start prefetching new pages in the background
    if
      let itemIDs = syncResult?.updatedItemIDs,
      let username = dataService.currentViewer?.username,
      !itemIDs.isEmpty
    {
      Task.detached(priority: .background) {
        await dataService.prefetchPages(itemIDs: itemIDs, username: username)
      }
    }
  }

  func loadSearchQuery(dataService: DataService, isRefresh: Bool) async {
    let thisSearchIdx = searchIdx
    searchIdx += 1

    if thisSearchIdx > 0, thisSearchIdx <= receivedIdx {
      return
    }

    let queryResult = try? await dataService.loadLinkedItems(
      limit: 10,
      searchQuery: searchQuery,
      cursor: isRefresh ? nil : cursor
    )

    guard let queryResult = queryResult else {
      updateFetchController(dataService: dataService)
      return
    }

    let newItems: [LinkedItem] = {
      var itemObjects = [LinkedItem]()
      dataService.viewContext.performAndWait {
        itemObjects = queryResult.itemIDs.compactMap { dataService.viewContext.object(with: $0) as? LinkedItem }
      }
      return itemObjects
    }()

    if searchTerm.replacingOccurrences(of: " ", with: "").isEmpty {
      updateFetchController(dataService: dataService)
    } else {
      // Don't use FRC for searching. Use server results directly.
      if fetchedResultsController != nil {
        fetchedResultsController = nil
        items = []
      }
      items = isRefresh ? newItems : items + newItems
    }

    isLoading = false
    receivedIdx = thisSearchIdx
    cursor = queryResult.cursor
    if let username = dataService.currentViewer?.username {
      await dataService.prefetchPages(itemIDs: newItems.map(\.unwrappedID), username: username)
    }
  }

  func loadItems(dataService: DataService, isRefresh: Bool) async {
    isLoading = true
    showLoadingBar = true

    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.loadCurrentViewer(dataService: dataService) }
      group.addTask { await self.loadLabels(dataService: dataService) }
      group.addTask { await self.syncItems(dataService: dataService) }
      group.addTask { await self.updateFetchController(dataService: dataService) }
      await group.waitForAll()
    }

    if items.isEmpty || isRefresh {
      await loadSearchQuery(dataService: dataService, isRefresh: isRefresh)
    }

    isLoading = false
    showLoadingBar = false
  }

  func loadMoreItems(dataService: DataService, isRefresh: Bool) async {
    isLoading = true
    showLoadingBar = true

    await loadSearchQuery(dataService: dataService, isRefresh: isRefresh)

    isLoading = false
    showLoadingBar = false
  }

  private var fetchPredicate: NSPredicate {
    let itemFilter = LinkedItemFilter(rawValue: appliedFilter) ?? .inbox
    var subPredicates = [
      itemFilter.predicate
    ]

    let selectedLabelIDs = selectedLabels.compactMap(\.id)
    if !selectedLabelIDs.isEmpty {
      let predicate = NSPredicate(format: "SUBQUERY(labels, $label, $label.id IN %@).@count > 0", selectedLabelIDs)
      subPredicates.append(predicate)
    }

    let negatedLabelIDs = negatedLabels.compactMap(\.id)
    if !negatedLabelIDs.isEmpty {
      let predicate = NSPredicate(format: "SUBQUERY(labels, $label, $label.id IN %@).@count == 0", negatedLabelIDs)
      subPredicates.append(predicate)
    }

    return NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
  }

  private func updateFetchController(dataService: DataService) {
    let itemSort = LinkedItemSort(rawValue: appliedSort) ?? .newest

    if let frc = fetchedResultsController {
      frc.fetchRequest.predicate = fetchPredicate
      frc.fetchRequest.sortDescriptors = itemSort.sortDescriptors
    } else {
      let fetchRequest = LinkedItem.fetchRequest()
      fetchRequest.predicate = fetchPredicate
      fetchRequest.sortDescriptors = itemSort.sortDescriptors
      fetchRequest.relationshipKeyPathsForPrefetching = [
        #keyPath(LinkedItem.labels),
        #keyPath(LinkedItem.highlights)
      ]

      let frc = NSFetchedResultsController(
        fetchRequest: fetchRequest,
        managedObjectContext: dataService.viewContext,
        sectionNameKeyPath: nil,
        cacheName: nil
      )

      frc.delegate = self
      fetchedResultsController = frc

      storageNotificationCancellable = NotificationCenter.default
        .publisher(for: DataService.didResetLocalStorage)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          self?.refetch()
        }
    }

    refetch()
  }

  private func refetch() {
    guard let frc = fetchedResultsController else { return }
    do {
      try frc.performFetch()
      items = frc.fetchedObjects ?? []
    } catch {
      logger.error("HomeFeedViewModel could not fetch items from Core Data: \(error.localizedDescription)")
      items = []
    }
  }

  func setLinkArchived(dataService: DataService, objectID: NSManagedObjectID, archived: Bool) {
    dataService.archiveLink(objectID: objectID, archived: archived)
    Snackbar.show(message: archived ? "Link archived" : "Link moved to Inbox")
  }

  func removeLink(dataService: DataService, objectID: NSManagedObjectID) {
    Snackbar.show(message: "Link removed")
    dataService.removeLink(objectID: objectID)
  }

  func snoozeUntil(dataService: DataService, linkId: String, until: Date, successMessage: String?) async {
    isLoading = true

    if let itemIndex = items.firstIndex(where: { $0.id == linkId }) {
      items.remove(at: itemIndex)
    }

    do {
      try await dataService.createReminder(
        reminderItemId: .link(id: linkId),
        remindAt: until
      )

      if let message = successMessage {
        Snackbar.show(message: message)
      }
    } catch {
      NSNotification.operationFailed(message: "Failed to snooze")
    }

    isLoading = false
  }

  private var queryContainsFilter: Bool {
    if searchTerm.contains("in:inbox") || searchTerm.contains("in:all") || searchTerm.contains("in:archive") {
      return true
    }

    return false
  }

  private var searchQuery: String {
    let sort = LinkedItemSort(rawValue: appliedSort) ?? .newest
    var query = sort.queryString

    if !queryContainsFilter, let filter = LinkedItemFilter(rawValue: appliedFilter) {
      query = "\(filter.queryString) \(sort.queryString)"
    }

    if !searchTerm.isEmpty {
      query.append(" \(searchTerm)")
    }

    if !selectedLabels.isEmpty {
      query.append(" label:")
      query.append(selectedLabels.map { $0.name ?? "" }.joined(separator: ","))
    }

    if !negatedLabels.isEmpty {
      query.append(" !label:")
      query.append(negatedLabels.map { $0.name ?? "" }.joined(separator: ","))
    }

    print("QUERY: `\(query)`")

    return query
  }
}

extension HomeFeedViewModel: NSFetchedResultsControllerDelegate {
  func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
    items = controller.fetchedObjects as? [LinkedItem] ?? []
  }
}
