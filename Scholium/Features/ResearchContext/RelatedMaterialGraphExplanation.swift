import Foundation
import ScholiumContracts

/// Explains authored connection walks without implying a new relationship or
/// exposing retrieval scores. Occurrences remain distinct in the Graph owner.
enum RelatedMaterialGraphExplanation {
    static func string(for candidate: RelatedContentCandidate, locale: Locale = .current) -> String? {
        guard let context = candidate.graphContext else { return nil }
        var explanations: [String] = []
        var seen = Set<String>()
        for path in context.paths.prefix(RelatedContentContract.maximumGraphPathsPerCandidate) {
            guard path.isValid, let first = path.steps.first,
                end(of: path.steps[path.steps.count - 1]) == candidate.note
            else { continue }
            let resource: LocalizedStringResource
            if path.steps.count == 1 {
                resource =
                    first.traversal == .outgoing
                    ? ScholiumL10n.RelatedMaterialGraph.directOutgoing
                    : ScholiumL10n.RelatedMaterialGraph.directIncoming
            } else {
                let second = path.steps[1]
                let intermediate = end(of: first)
                guard start(of: second) == intermediate else { continue }
                let filename = (intermediate.relativePath as NSString).lastPathComponent
                let name = (filename as NSString).deletingPathExtension
                resource = ScholiumL10n.RelatedMaterialGraph.via(
                    name, first: first.traversal, second: second.traversal)
            }
            let explanation = ScholiumL10n.localized(resource, locale: locale)
            if seen.insert(explanation).inserted { explanations.append(explanation) }
        }
        return explanations.isEmpty ? nil : explanations.joined(separator: " ")
    }

    static func passageHint(for candidate: RelatedContentCandidate, locale: Locale = .current) -> String {
        let action = ScholiumL10n.string("Show this passage", locale: locale)
        guard let explanation = string(for: candidate, locale: locale) else { return action }
        return action + "\n" + explanation
    }

    private static func start(of step: RelatedContentGraphStep) -> VaultQualifiedNoteID {
        step.traversal == .outgoing ? step.source : step.destination
    }

    private static func end(of step: RelatedContentGraphStep) -> VaultQualifiedNoteID {
        step.traversal == .outgoing ? step.destination : step.source
    }
}
