import Foundation
import ScholiumContracts

/// Conservatively identifies repeated or ambiguous reading leads without
/// merging records or changing agent-supplied recommendation evidence.
public enum BibliographyCandidateDiscriminator {
    public static func classify(
        _ candidates: [RecommendedBibliographyCandidate],
        against existingCandidates: [RecommendedBibliographyCandidate] = []
    ) -> [RecommendedBibliographyCandidate] {
        var classified: [RecommendedBibliographyCandidate] = []
        classified.reserveCapacity(candidates.count)
        var references = existingCandidates.filter { $0.duplicateOfCandidateID == nil }

        for candidate in candidates {
            var duplicate: RecommendedBibliographyCandidate?
            var isAmbiguous = false
            for prior in references {
                switch relationship(candidate, prior) {
                case .duplicate:
                    duplicate = prior
                case .ambiguous:
                    isAmbiguous = true
                case .distinct:
                    break
                }
                if duplicate != nil { break }
            }

            if let duplicate {
                classified.append(candidate.deriving(
                    matchState: .duplicate,
                    matchedAnalysis: candidate.matchedAnalysis,
                    matchedZoteroItemKey: candidate.matchedZoteroItemKey,
                    duplicateOfCandidateID: duplicate.id,
                    isDismissed: duplicate.isDismissed
                ))
            } else if isAmbiguous {
                let derived = candidate.deriving(
                    matchState: .ambiguous,
                    matchedAnalysis: candidate.matchedAnalysis,
                    matchedZoteroItemKey: candidate.matchedZoteroItemKey
                )
                classified.append(derived)
                references.append(derived)
            } else {
                classified.append(candidate)
                references.append(candidate)
            }
        }
        return classified
    }

    private enum Relationship {
        case duplicate
        case ambiguous
        case distinct
    }

    private static func relationship(
        _ lhs: RecommendedBibliographyCandidate,
        _ rhs: RecommendedBibliographyCandidate
    ) -> Relationship {
        let left = lhs.identity
        let right = rhs.identity
        let sameTitle = normalizedTitle(left.title) != nil
            && normalizedTitle(left.title) == normalizedTitle(right.title)
        let possibleTitleCollision = sameTitle
            && (left.year == nil || right.year == nil || left.year == right.year)

        if conflicts(left, right) {
            return possibleTitleCollision ? .ambiguous : .distinct
        }

        if lhs.evidence.metadataVerified,
           rhs.evidence.metadataVerified,
           same(left.zoteroItemKey, right.zoteroItemKey) {
            return .duplicate
        }
        if lhs.evidence.metadataVerified,
           rhs.evidence.metadataVerified,
           same(normalizedDOI(left.doi), normalizedDOI(right.doi)) {
            return .duplicate
        }
        if let leftISBN = normalizedISBN(left.isbn),
           let rightISBN = normalizedISBN(right.isbn),
           leftISBN == rightISBN,
           [10, 13].contains(leftISBN.count) {
            return .duplicate
        }
        if same(left.citationKey, right.citationKey) {
            return .duplicate
        }
        if completeBibliographicIdentityMatches(left, right) {
            return .duplicate
        }
        return possibleTitleCollision ? .ambiguous : .distinct
    }

    private static func conflicts(
        _ lhs: BibliographyCandidateIdentity,
        _ rhs: BibliographyCandidateIdentity
    ) -> Bool {
        if let left = lhs.isChapter, let right = rhs.isChapter, left != right {
            return true
        }
        if !lhs.authors.isEmpty, !rhs.authors.isEmpty,
           normalizedPeople(lhs.authors) != normalizedPeople(rhs.authors) {
            return true
        }
        if let left = normalizedIdentity(lhs.edition),
           let right = normalizedIdentity(rhs.edition), left != right {
            return true
        }
        if !lhs.translators.isEmpty, !rhs.translators.isEmpty,
           normalizedPeople(lhs.translators) != normalizedPeople(rhs.translators) {
            return true
        }
        return false
    }

    private static func completeBibliographicIdentityMatches(
        _ lhs: BibliographyCandidateIdentity,
        _ rhs: BibliographyCandidateIdentity
    ) -> Bool {
        guard normalizedTitle(lhs.title) != nil,
              normalizedTitle(lhs.title) == normalizedTitle(rhs.title),
              let leftYear = lhs.year,
              leftYear == rhs.year,
              !lhs.authors.isEmpty,
              normalizedPeople(lhs.authors) == normalizedPeople(rhs.authors),
              let leftIsChapter = lhs.isChapter,
              leftIsChapter == rhs.isChapter,
              normalizedIdentity(lhs.edition) == normalizedIdentity(rhs.edition),
              normalizedPeople(lhs.translators) == normalizedPeople(rhs.translators)
        else { return false }

        if leftIsChapter {
            guard normalizedTitle(lhs.containerTitle) != nil,
                  normalizedTitle(lhs.containerTitle) == normalizedTitle(rhs.containerTitle),
                  normalizedPeople(lhs.editors) == normalizedPeople(rhs.editors) else {
                return false
            }
        }
        return true
    }

    private static func same(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalizedIdentity(lhs),
              let rhs = normalizedIdentity(rhs) else { return false }
        return lhs == rhs
    }

    private static func normalizedPeople(_ values: [String]) -> [String] {
        values.compactMap(normalizedTitle)
    }

    private static func normalizedIdentity(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value?.isEmpty == false ? value : nil
    }

    private static func normalizedDOI(_ value: String?) -> String? {
        normalizedIdentity(value)?
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "doi:", with: "")
    }

    private static func normalizedISBN(_ value: String?) -> String? {
        normalizedIdentity(value)?.filter { $0.isNumber || $0 == "x" }
    }

    private static func normalizedTitle(_ value: String?) -> String? {
        normalizedIdentity(value)?.filter { $0.isLetter || $0.isNumber }
    }
}
