import CoreData
import Foundation
import OSLog

let logger = Logger(subsystem: "app.omnivore", category: "models")

/// An `NSPersistentContainer` subclass that lives in the `Models` package so that
/// the data model is looked for in the same package bundle (rather than the main bundle)
public final class PersistentContainer: NSPersistentContainer {
  public static func make() -> PersistentContainer {
    #if os(iOS)
      let appGroupID = "group.app.omnivoreapp"
    #else
      let appGroupID = "QJF2XZ86HB.app.omnivore.app"
    #endif
    guard let container = PersistentContainer(appGroupID: appGroupID) else {
      fatalError("Cannot create Core Data container")
    }
    return container
  }

  public func destroyPersistentStores() throws {
    guard !persistentStoreCoordinator.persistentStores.isEmpty else {
      try persistentStoreCoordinator.destroyPersistentStore(
        at: persistentStoreURL,
        type: .sqlite
      )
      return
    }

    for store in persistentStoreCoordinator.persistentStores {
      try persistentStoreCoordinator.remove(store)
      if let storeURL = store.url {
        try persistentStoreCoordinator.destroyPersistentStore(
          at: storeURL,
          ofType: store.type
        )
      }
    }
  }

  private let persistentStoreURL: URL

  private init?(appGroupID: String) {
    guard
      let modelURL = Bundle.module.url(forResource: "CoreDataModel", withExtension: "momd"),
      let model = NSManagedObjectModel(contentsOf: modelURL)
    else {
      logger.error("Could not load Core Data model")
      return nil
    }

    // Store the sqlite file in the app group container.
    // This allows shared access for app and app extensions.
    guard
      let appGroupContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    else {
      logger.error("Could not determine app group container URL")
      return nil
    }
    let persistentStoreURL = appGroupContainerURL.appendingPathComponent("store.sqlite")
    logger.debug("starting with sqlite container \(persistentStoreURL.absoluteString)")
    self.persistentStoreURL = persistentStoreURL

    super.init(name: "DataModel", managedObjectModel: model)

    let description = NSPersistentStoreDescription(url: persistentStoreURL)
    persistentStoreDescriptions = [description]

    viewContext.automaticallyMergesChangesFromParent = true
    viewContext.name = "viewContext"
    viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
  }
}
