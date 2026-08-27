import Foundation
import ScholiumContracts

/// Application policy for Agent Recommended Reading. Search owns candidate
/// retrieval and ordering; this coordinator owns Action eligibility and the
/// delivery-neutral Agent directory shape.
struct RecommendedReadingCoordinator: Sendable {
    typealias Retrieve = @Sendable (
        RelatedContentRequest
    ) async throws -> RelatedContentResponse

    private let retrieve: Retrieve

    init(retrieve: @escaping Retrieve) {
        self.retrieve = retrieve
    }

    func directory(
        for action: ResearchActionSnapshot,
        source: NoteDocument,
        requestID: UUID
    ) async throws -> ResearchRecommendedReadingDirectory? {
        guard action.target.role == .work,
              action.actionID == .write || action.actionID == .critique else {
            return nil
        }
        let seed = RelatedContentSeedSnapshot(
            noteID: action.target.note,
            source: source.rawContent
        )
        do {
            let response = try await retrieve(RelatedContentRequest(
                id: requestID,
                seed: seed
            ))
            let candidates: [ResearchRecommendedReadingCandidate]
            if response.state == .current {
                candidates = try response.candidates.map { candidate in
                    guard let role = ResearchActionTargetRole(
                        vaultRole: candidate.vaultRole
                    ),
                    role == .analysis || role == .topic else {
                        throw ResearchAgentConnectionContractError.invalidHandoff
                    }
                    return try ResearchRecommendedReadingCandidate(
                        note: candidate.note,
                        role: role,
                        title: candidate.title,
                        fingerprint: candidate.fingerprint,
                        matchedFields: candidate.lexicalReason.matchedFields,
                        matchedSeedTerms: candidate.lexicalReason.matchedSeedTerms
                    )
                }
            } else {
                candidates = []
            }
            return try ResearchRecommendedReadingDirectory(
                retrievalContractVersion: response.contractVersion,
                rankingPolicyVersion: response.rankingPolicyVersion,
                seedFingerprint: response.seedFingerprint,
                freshnessToken: response.freshnessToken,
                state: response.state,
                candidates: candidates,
                hasMore: response.hasMore && !candidates.isEmpty,
                limitation: Self.limitation(for: response.state)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try ResearchRecommendedReadingDirectory(
                seedFingerprint: seed.fingerprint,
                freshnessToken: SearchFreshnessToken(
                    "related-content:unavailable"
                ),
                state: .unavailable,
                candidates: [],
                hasMore: false,
                limitation: "Recommended Reading is unavailable. The Agent can still use the current bounded Search action."
            )
        }
    }

    private static func limitation(
        for state: RelatedContentResultState
    ) -> String? {
        switch state {
        case .current, .empty:
            nil
        case .stale:
            "Recommended Reading has no current Search generation. Reload this Run or use bounded Search."
        case .unavailable:
            "Recommended Reading is unavailable. The Agent can still use the current bounded Search action."
        case .invalidSeed:
            "The frozen Work does not provide a valid bounded reading seed. The Agent can still use bounded Search."
        }
    }
}
