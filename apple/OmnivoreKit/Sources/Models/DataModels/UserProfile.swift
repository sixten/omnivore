import CoreData
import Foundation

public extension UserProfile {
  static func lookup(byID userID: String, inContext context: NSManagedObjectContext) -> UserProfile? {
    let fetchRequest = UserProfile.fetchRequest()
    fetchRequest.predicate = NSPredicate(
      format: "%K == %@", #keyPath(UserProfile.userID), userID
    )
    fetchRequest.fetchLimit = 1
    return (try? context.fetch(fetchRequest))?.first
  }
}
