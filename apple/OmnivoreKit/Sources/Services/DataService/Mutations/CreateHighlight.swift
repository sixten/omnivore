import CoreData
import Foundation
import Models
import SwiftGraphQL

extension DataService {
  // swiftlint:disable:next function_parameter_count
  public func createHighlight(
    shortId: String,
    highlightID: String,
    quote: String,
    patch: String,
    articleId: String,
    positionPercent: Double?,
    positionAnchorIndex: Int?,
    annotation: String? = nil
  ) -> [String: Any]? {
    let internalHighlight = InternalHighlight(
      id: highlightID,
      shortId: shortId,
      quote: quote,
      prefix: nil, suffix: nil,
      patch: patch,
      annotation: annotation,
      createdAt: nil,
      updatedAt: nil,
      createdByMe: true,
      createdBy: nil,
      positionPercent: positionPercent,
      positionAnchorIndex: positionAnchorIndex,
      labels: []
    )

    internalHighlight.persist(context: backgroundContext, associatedItemID: articleId)

    // Send update to server
    syncHighlightCreation(highlight: internalHighlight, articleId: articleId)

    return internalHighlight.encoded()
  }

  func syncHighlightCreation(highlight: InternalHighlight, articleId: String) {
    enum MutationResult {
      case saved(highlight: InternalHighlight)
      case error(errorCode: Enums.CreateHighlightErrorCode)
    }

    let selection = Selection<MutationResult, Unions.CreateHighlightResult> {
      try $0.on(
        createHighlightError: .init { .error(errorCode: try $0.errorCodes().first ?? .badData) },
        createHighlightSuccess: .init {
          .saved(highlight: try $0.highlight(selection: highlightSelection))
        }
      )
    }

    let mutation = Selection.Mutation {
      try $0.createHighlight(
        input: InputObjects.CreateHighlightInput(
          annotation: OptionalArgument(highlight.annotation),
          articleId: articleId,
          highlightPositionAnchorIndex: OptionalArgument(highlight.positionAnchorIndex),
          highlightPositionPercent: OptionalArgument(highlight.positionPercent), id: highlight.id,
          patch: highlight.patch,
          quote: highlight.quote,
          shortId: highlight.shortId
        ),
        selection: selection
      )
    }

    let path = appEnvironment.graphqlPath
    let headers = networker.defaultHeaders
    let context = backgroundContext

    send(mutation, to: path, headers: headers) { result in
      let data = try? result.get()
      let syncStatus: ServerSyncStatus = data == nil ? .needsCreation : .isNSync

      context.perform {
        let fetchRequest = Highlight.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", highlight.id)
        fetchRequest.fetchLimit = 1

        do {
          let highlights = try context.fetch(fetchRequest)

          guard let highlightObject = highlights.first else { return }
          highlightObject.serverSyncStatus = Int64(syncStatus.rawValue)

          try context.save()
          logger.debug("Highlight created succesfully")
        } catch {
          context.rollback()
          logger.debug("Failed to create Highlight: \(error.localizedDescription)")
        }
      }
    }
  }
}
