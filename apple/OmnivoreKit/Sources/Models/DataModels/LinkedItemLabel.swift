import Foundation

public extension Sequence where Element == LinkedItemLabel {
  func sortedByName() -> [LinkedItemLabel] {
    sorted { lhs, rhs in
      let lstr = lhs.name?.trimmingCharacters(in: .whitespaces) ?? ""
      let rstr = rhs.name?.trimmingCharacters(in: .whitespaces) ?? ""
      return lstr.caseInsensitiveCompare(rstr) == .orderedAscending
    }
  }
}
