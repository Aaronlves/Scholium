import Foundation
import ScholiumContracts

public enum AgentChatPDFPageSelection {
  public static let maximumPages = 20

  /// Physical pages only; never silently clamp, truncate or interpret an expression.
  public static func parse(_ text: String, pageCount: Int) throws -> [Int] {
    let tokens = text.replacingOccurrences(of: "–", with: "-")
      .replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "、", with: ",")
      .split(separator: ",", omittingEmptySubsequences: false)
    var pages: Set<Int> = []
    for token in tokens {
      let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      guard (1...2).contains(bounds.count), let lower = Int(bounds[0]), lower >= 1,
        let upper = Int(bounds.last!), upper >= lower, upper <= pageCount else { throw AgentChatPDFPageSelectionFailure.invalidRange }
      guard upper - lower < maximumPages else { throw AgentChatPDFPageSelectionFailure.tooManyPages }
      pages.formUnion(lower...upper)
      guard pages.count <= maximumPages else { throw AgentChatPDFPageSelectionFailure.tooManyPages }
    }
    guard !pages.isEmpty else { throw AgentChatPDFPageSelectionFailure.invalidRange }
    return pages.sorted()
  }

}
