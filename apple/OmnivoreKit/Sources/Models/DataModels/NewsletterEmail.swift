import CoreData
import Foundation

public extension NewsletterEmail {
  var unwrappedEmailId: String { emailId ?? "" }

  var unwrappedEmail: String { email ?? "" }

  static func lookup(byID emailID: String, inContext context: NSManagedObjectContext) -> NewsletterEmail? {
    let fetchRequest = NewsletterEmail.fetchRequest()
    fetchRequest.predicate = NSPredicate(
      format: "%K == %@", #keyPath(NewsletterEmail.emailId), emailID
    )
    fetchRequest.fetchLimit = 1
    return (try? context.fetch(fetchRequest))?.first
  }
}
