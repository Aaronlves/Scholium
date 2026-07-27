import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@MainActor
@Suite("Agent Note Change presentation coordination")
struct AgentNoteChangePresentationCoordinatorTests {
    private final class Availability {
        var background = false
        var key = false
    }

    @Test("One request is claimed by the key window in its exact Triptych")
    func exactTriptychKeyWindowClaim() throws {
        let coordinator = AgentNoteChangePresentationCoordinator()
        let triptychID = UUID()
        let otherTriptychID = UUID()
        let firstID = UUID()
        let keyID = UUID()
        let otherID = UUID()
        var presented: [UUID] = []

        coordinator.register(endpoint(
            id: firstID,
            triptychID: triptychID,
            isKey: false,
            onPresent: { presented.append($0) }
        ))
        coordinator.register(endpoint(
            id: otherID,
            triptychID: otherTriptychID,
            isKey: true,
            onPresent: { presented.append($0) }
        ))
        coordinator.register(endpoint(
            id: keyID,
            triptychID: triptychID,
            isKey: true,
            onPresent: { presented.append($0) }
        ))

        let record = try requestRecord(triptychID: triptychID)
        coordinator.receive(record, intent: .submit)

        #expect(coordinator.claimedWindowID(for: record.id) == keyID)
        #expect(presented == [keyID])
    }

    @Test("Replay updates one claim and show focuses without another sheet")
    func replayAndShowDoNotDuplicate() throws {
        let coordinator = AgentNoteChangePresentationCoordinator()
        let triptychID = UUID()
        let windowID = UUID()
        var presented: [UUID] = []
        var updated = 0
        var focused = 0
        coordinator.register(.init(
            id: windowID,
            triptychID: { triptychID },
            isKeyWindow: { true },
            canPresent: { true },
            present: { _ in presented.append(windowID) },
            update: { _ in updated += 1 },
            dismiss: { _ in },
            focus: { _ in focused += 1 }
        ))
        let record = try requestRecord(triptychID: triptychID)

        coordinator.receive(record, intent: .submit)
        coordinator.receive(record, intent: .submit)
        coordinator.receive(record, intent: .showExisting)

        #expect(presented == [windowID])
        #expect(updated == 2)
        #expect(focused == 2)
        #expect(coordinator.claimedWindowID(for: record.id) == windowID)
    }

    @Test("A newly available background window does not outrank the key window")
    func keyWindowOutranksPreferredAvailability() throws {
        let coordinator = AgentNoteChangePresentationCoordinator()
        let triptychID = UUID()
        let backgroundID = UUID()
        let keyID = UUID()
        let availability = Availability()
        coordinator.register(.init(
            id: backgroundID,
            triptychID: { triptychID },
            isKeyWindow: { false },
            canPresent: { availability.background },
            present: { _ in },
            update: { _ in },
            dismiss: { _ in },
            focus: { _ in }
        ))
        coordinator.register(.init(
            id: keyID,
            triptychID: { triptychID },
            isKeyWindow: { true },
            canPresent: { availability.key },
            present: { _ in },
            update: { _ in },
            dismiss: { _ in },
            focus: { _ in }
        ))
        let record = try requestRecord(triptychID: triptychID)
        coordinator.receive(record, intent: .submit)

        availability.background = true
        availability.key = true
        coordinator.presentationBecameAvailable(windowID: backgroundID)

        #expect(coordinator.claimedWindowID(for: record.id) == keyID)
    }

    @Test("Closing a claimed window reroutes an unresolved request once")
    func closingWindowReroutesPendingRequest() throws {
        let coordinator = AgentNoteChangePresentationCoordinator()
        let triptychID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        var presented: [UUID] = []
        coordinator.register(endpoint(
            id: secondID,
            triptychID: triptychID,
            isKey: false,
            onPresent: { presented.append($0) }
        ))
        coordinator.register(endpoint(
            id: firstID,
            triptychID: triptychID,
            isKey: true,
            onPresent: { presented.append($0) }
        ))
        let record = try requestRecord(triptychID: triptychID)
        coordinator.receive(record, intent: .submit)

        coordinator.unregister(windowID: firstID)

        #expect(presented == [firstID, secondID])
        #expect(coordinator.claimedWindowID(for: record.id) == secondID)
    }

    @Test("A cached request is never presented after its bounded lifetime")
    func expiredCachedRequestIsNotPresented() throws {
        let coordinator = AgentNoteChangePresentationCoordinator()
        let triptychID = UUID()
        let windowID = UUID()
        var didPresent = false
        coordinator.register(.init(
            id: windowID,
            triptychID: { triptychID },
            isKeyWindow: { true },
            canPresent: { true },
            present: { _ in didPresent = true },
            update: { _ in },
            dismiss: { _ in },
            focus: { _ in }
        ))
        let record = try requestRecord(
            triptychID: triptychID,
            receivedAt: Date().addingTimeInterval(-121)
        )

        coordinator.receive(record, intent: .submit)

        #expect(!didPresent)
        #expect(coordinator.claimedWindowID(for: record.id) == nil)
    }

    @Test("A stale claimed request stays visible while an allowed decision dismisses")
    func terminalStatePresentation() throws {
        let coordinator = AgentNoteChangePresentationCoordinator()
        let triptychID = UUID()
        let windowID = UUID()
        var updates: [AgentNoteChangeDecisionState] = []
        var dismissals: [UUID] = []
        coordinator.register(.init(
            id: windowID,
            triptychID: { triptychID },
            isKeyWindow: { true },
            canPresent: { true },
            present: { _ in },
            update: { updates.append($0.decision.state) },
            dismiss: { dismissals.append($0) },
            focus: { _ in }
        ))
        let pending = try requestRecord(triptychID: triptychID)
        coordinator.receive(pending, intent: .submit)
        let stale = try pending.resolving(
            state: .stale,
            at: pending.receivedAt.addingTimeInterval(1)
        )
        coordinator.receive(stale, intent: .refresh)

        #expect(updates == [.stale])
        #expect(dismissals.isEmpty)
        #expect(coordinator.claimedWindowID(for: pending.id) == windowID)

        let second = try requestRecord(triptychID: triptychID)
        coordinator.presentationDidDismiss(requestID: pending.id, windowID: windowID)
        coordinator.receive(second, intent: .submit)
        let allowed = try second.resolving(
            state: .allowedSubset,
            allowedNoteIDs: second.request.targets.map(\.noteID),
            continuationPlan: try AgentNoteChangeContinuationPlan(
                groupID: second.request.parentRunID,
                parentRunID: second.request.parentRunID,
                requestID: second.id,
                childPhases: second.request.targets.map {
                    AgentNoteChangeChildPhasePlan(noteID: $0.noteID)
                }
            ),
            at: second.receivedAt.addingTimeInterval(1)
        )
        coordinator.receive(allowed, intent: .decision)

        #expect(dismissals == [second.id])
        #expect(coordinator.claimedWindowID(for: second.id) == nil)
    }

    private func endpoint(
        id: UUID,
        triptychID: UUID,
        isKey: Bool,
        onPresent: @escaping @MainActor (UUID) -> Void
    ) -> AgentNoteChangePresentationCoordinator.WindowEndpoint {
        .init(
            id: id,
            triptychID: { triptychID },
            isKeyWindow: { isKey },
            canPresent: { true },
            present: { _ in onPresent(id) },
            update: { _ in },
            dismiss: { _ in },
            focus: { _ in }
        )
    }

    private func requestRecord(
        triptychID: UUID,
        receivedAt: Date = Date()
    ) throws -> AgentNoteChangeRequestRecord {
        let requested = try actionRevision(
            definition: .synthesize,
            packageID: "scholium-synthesize"
        )
        let noteID = UUID()
        let target = try AgentNoteChangeTarget(
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Topics/Attention.md"
            ),
            role: .topic,
            expectedFingerprint: fingerprint("topic")
        )
        return try AgentNoteChangeRequestRecord(
            request: AgentNoteChangeRequest(
                triptychID: triptychID,
                parentRunID: UUID(),
                parentAction: try actionRevision(
                    definition: .analyze,
                    packageID: "scholium-analyze"
                ),
                requestedAction: requested,
                targets: [target],
                operations: [.modifyMarkdown],
                agentReason: "This Topic needs the source result."
            ),
            receivedAt: receivedAt,
            validFor: 120
        )
    }

    private func actionRevision(
        definition: ResearchActionDefinition,
        packageID: String
    ) throws -> AgentNoteChangeActionRevision {
        try AgentNoteChangeActionRevision(
            definition: definition,
            packageID: packageID,
            skillRevision: fingerprint("skill-\(packageID)"),
            profileOrigin: .applicationDefault,
            profileRevision: fingerprint("profile-\(packageID)"),
            profileDocumentRevision: nil
        )
    }

    private func fingerprint(_ value: String) -> DocumentFingerprint {
        DocumentFingerprint(data: Data(value.utf8))
    }
}
