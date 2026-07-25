import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Research Action Profile Settings draft")
struct ResearchActionProfileDraftTests {
    @Test("A valid draft builds a bounded custom Profile")
    func buildsProfile() throws {
        var draft = ResearchActionProfileDraft(
            actionID: "counterexample-test",
            executionKind: .critique,
            buttonName: "Counterexample Test",
            order: 4,
            applicableRoles: [.work],
            showInActions: true
        )
        let supportedKinds = ResearchActionModuleKind.allCases.filter {
            $0 != .sourceReference
        }
        for kind in supportedKinds {
            draft.addModule(kind: kind)
        }
        draft.readableRoles = [.analysis, .topic, .work]

        let binding = try draft.binding(packageID: "counterexample-method")

        #expect(binding.profile.actionID.rawValue == "counterexample-test")
        #expect(binding.profile.executionKind == .critique)
        #expect(binding.profile.modules.map(\.kind) == supportedKinds)
        #expect(binding.profile.showInActions)
    }

    @Test("Source modules remain exact to Analysis execution")
    func sourceModuleBoundary() {
        var draft = ResearchActionProfileDraft(
            actionID: "source-check",
            executionKind: .discussion,
            buttonName: "Source Check",
            order: 0,
            applicableRoles: [.analysis],
            showInActions: true
        )

        draft.addModule(kind: .sourceReference)
        #expect(!draft.modules.contains { $0.kind == .sourceReference })
        #expect(draft.sourceRequirement == .none)

        draft.selectExecutionKind(.analysis)
        #expect(draft.modules.first(where: { $0.kind == .sourceReference })?.isRequired == true)
        #expect(draft.sourceRequirement == .required)

        draft.selectExecutionKind(.discussion)
        #expect(!draft.modules.contains { $0.kind == .sourceReference })
        #expect(draft.sourceRequirement == .none)
    }

    @Test("Invalid drafts explain the contract failure before save")
    func invalidDraft() {
        let draft = ResearchActionProfileDraft(
            actionID: "develop",
            executionKind: .analysis,
            buttonName: "Analyze",
            order: 1,
            applicableRoles: [.analysis],
            showInActions: true
        )

        #expect(draft.validationMessage(packageID: "method") != nil)
    }

    @Test("Profile drafts are isolated by Triptych, Skill, and Action")
    @MainActor
    func profileDraftIsolationAndDiscard() throws {
        let store = ResearchGuidanceDraftStore()
        let triptychA = UUID()
        let triptychB = UUID()
        let actionID = try #require(
            ResearchActionID(researcherOwnedRawValue: "compare-interpretations")
        )
        let keyA = ResearchActionProfileDraftKey(
            triptychID: triptychA,
            packageID: "comparison-method",
            actionID: actionID
        )
        let keyB = ResearchActionProfileDraftKey(
            triptychID: triptychB,
            packageID: "comparison-method",
            actionID: actionID
        )
        var originalA = ResearchActionProfileDraft(
            actionID: "compare-interpretations",
            executionKind: .discussion,
            buttonName: "Compare in A",
            order: 2,
            applicableRoles: [.analysis, .topic],
            showInActions: false
        )
        originalA.addModule(kind: .passageAnchor)
        var originalB = originalA
        originalB.buttonName = "Compare in B"
        store.synchronizeProfile(key: keyA, draft: originalA)
        store.synchronizeProfile(key: keyB, draft: originalB)

        var editedA = originalA
        editedA.buttonName = "Unsaved A"
        editedA.showInActions = true
        editedA.addModule(kind: .enumeration)
        store.updateProfileDraft(editedA, for: keyA)

        #expect(store.profileDraft(for: keyA, fallback: originalA) == editedA)
        #expect(store.profileDraft(for: keyB, fallback: originalB) == originalB)

        var latestSavedA = originalA
        latestSavedA.buttonName = "Latest saved A"
        store.synchronizeProfile(key: keyA, draft: latestSavedA)
        #expect(store.profileDraft(for: keyA, fallback: latestSavedA) == editedA)

        store.discardProfileChanges(for: keyA, fallback: latestSavedA)
        #expect(store.profileDraft(for: keyA, fallback: latestSavedA) == latestSavedA)
        #expect(!store.profileHasUnsavedChanges(for: keyA, fallback: latestSavedA))
        #expect(store.profileDraft(for: keyB, fallback: originalB) == originalB)
    }

    @Test("Skill drafts survive navigation and remain isolated by Triptych")
    @MainActor
    func skillDraftPersistence() {
        let store = ResearchGuidanceDraftStore()
        let triptychA = UUID()
        let triptychB = UUID()
        let original = ResearchSkillPackage(
            id: "counterexample-method",
            name: "Counterexample Method",
            description: "",
            source: "Original method",
            origin: .triptych
        )
        let otherTriptych = ResearchSkillPackage(
            id: original.id,
            name: original.name,
            description: original.description,
            source: "Other Triptych method",
            origin: .triptych
        )
        store.synchronizeSkills(triptychID: triptychA, skills: [original])
        store.synchronizeSkills(triptychID: triptychB, skills: [otherTriptych])
        store.updateSource(
            "Unsaved researcher revision",
            triptychID: triptychA,
            packageID: original.id
        )

        // Recreating the category view synchronizes the same package again;
        // the root-owned draft store must preserve the unsaved source.
        store.synchronizeSkills(triptychID: triptychA, skills: [original])
        #expect(
            store.source(for: original, triptychID: triptychA)
                == "Unsaved researcher revision"
        )
        #expect(store.hasUnsavedChanges(for: original, triptychID: triptychA))
        #expect(
            store.source(for: otherTriptych, triptychID: triptychB)
                == "Other Triptych method"
        )
        #expect(!store.hasUnsavedChanges(for: otherTriptych, triptychID: triptychB))

        let externallyReopened = ResearchSkillPackage(
            id: original.id,
            name: original.name,
            description: original.description,
            source: "Latest saved method",
            origin: .triptych
        )
        store.synchronizeSkills(triptychID: triptychA, skills: [externallyReopened])
        #expect(
            store.source(for: externallyReopened, triptychID: triptychA)
                == "Unsaved researcher revision"
        )
        store.discardChanges(for: externallyReopened, triptychID: triptychA)
        #expect(
            store.source(for: externallyReopened, triptychID: triptychA)
                == "Latest saved method"
        )
        #expect(!store.hasUnsavedChanges(for: externallyReopened, triptychID: triptychA))
        #expect(
            store.source(for: otherTriptych, triptychID: triptychB)
                == "Other Triptych method"
        )
    }
}
