import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Research Action Method bindings and maintenance")
struct ResearchFunctionSkillTests {
    @Test("Six default Actions resolve independent Working Methods and Manuscript stays disabled")
    func defaultActionMethodBindings() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.workingMethodStore()
        let binding = try await store.installDefaultWorkingMethods()
        let expected: [(ResearchFunctionID, ResearchActionID, String)] = [
            (.discuss, .discuss, "scholium-working-discuss"),
            (.develop, .analyze, "scholium-working-analyze"),
            (.develop, .synthesize, "scholium-working-synthesize"),
            (.revise, .write, "scholium-working-write"),
            (.critique, .critique, "scholium-working-critique"),
            (.fidelity, .checkFidelity, "scholium-working-content-fidelity"),
        ]

        for (function, actionID, packageID) in expected {
            let resolution = try await store.functionBindingResolution(
                for: function,
                actionID: actionID
            )
            #expect(resolution.source == .installedDefault)
            #expect(resolution.package?.id == packageID)
            #expect(resolution.package?.supportedActions == [actionID])
            #expect(resolution.package?.supportedFunctions == [function])
            #expect(resolution.issue == nil)
            #expect(resolution.bindingRevision == binding.revision)
        }

        let manuscript = try await store.functionBindingResolution(
            for: .manuscript,
            actionID: .manuscript
        )
        #expect(manuscript.source == .disabled)
        #expect(manuscript.package == nil)
        #expect(manuscript.issue == .disabled)
        #expect(manuscript.bundledTemplateAvailable)
    }

    @Test("Working Methods edit, disable, replace, restore, and reopen without fallback")
    func workingMethodLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.workingMethodStore()
        let initial = try await store.installDefaultWorkingMethods()
        let repeated = try await store.installDefaultWorkingMethods()
        #expect(repeated == initial)

        let initialResolution = try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        let working = try #require(initialResolution.package)
        let workingRevision = try #require(working.revision)
        let marker = "RESEARCHER_EDITED_ANALYZE_METHOD_4F1B"
        let edited = try await store.saveWorkingMethod(
            for: .analyze,
            source: working.source + "\n\n\(marker)\n",
            expectedPackageRevision: workingRevision,
            expectedBindingRevision: initial.revision
        )
        #expect(edited.source.contains(marker))
        #expect(edited.revision != workingRevision)

        let reopened = fixture.workingMethodStore()
        let reopenedBinding = try #require(
            try await reopened.workingMethodBindingSnapshot()
        )
        #expect(reopenedBinding.revision == initial.revision)
        let reopenedResolution = try await reopened.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(reopenedResolution.package?.source.contains(marker) == true)

        let disabled = try await reopened.disableWorkingMethod(
            for: .analyze,
            expectedBindingRevision: reopenedBinding.revision
        )
        let unavailable = try await reopened.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(unavailable.source == .disabled)
        #expect(unavailable.issue == .disabled)
        #expect(unavailable.package == nil)

        let researcherMethod = try await reopened.duplicateBundled(
            id: "scholium-analyze",
            as: "my-analysis-method"
        )
        let replaced = try await reopened.activateResearcherSkill(
            packageID: researcherMethod.id,
            for: .analyze,
            expectedBindingRevision: disabled.revision
        )
        let researcherResolution = try await reopened.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(researcherResolution.source == .researcherSkill)
        #expect(researcherResolution.package?.id == researcherMethod.id)

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await reopened.restoreBundledWorkingMethod(
                for: .analyze,
                expectedPackageState: .present(try #require(edited.revision)),
                expectedBindingRevision: disabled.revision
            )
        }
        #expect(try await reopened.package(id: working.id).source.contains(marker))

        let outcome = try await reopened.restoreBundledWorkingMethod(
            for: .analyze,
            expectedPackageState: .present(try #require(edited.revision)),
            expectedBindingRevision: replaced.revision
        )
        #expect(outcome.package.id == "scholium-working-analyze")
        #expect(outcome.package.revision == workingRevision)
        #expect(!outcome.package.source.contains(marker))
        let restoredMethod = try await reopened.resource(
            id: outcome.package.id,
            relativePath: "references/method.md"
        )
        let bundledMethod = try await reopened.resource(
            id: "scholium-analyze",
            relativePath: "references/method.md"
        )
        #expect(restoredMethod == bundledMethod)

        // The researcher-facing delete path now refuses an active Working
        // Method. Simulate an external filesystem participant removing it so
        // this test can still exercise fail-closed missing-package recovery.
        try FileManager.default.removeItem(
            at: fixture.control.appendingPathComponent(
                "skills/\(outcome.package.id)",
                isDirectory: true
            )
        )
        let missingPackage = try await reopened.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(missingPackage.issue == .invalidPackage(outcome.package.id))
        let reinstalled = try await reopened.restoreBundledWorkingMethod(
            for: .analyze,
            expectedPackageState: .missing,
            expectedBindingRevision: outcome.binding.revision
        )
        #expect(reinstalled.package.revision == workingRevision)

        let finalStore = fixture.workingMethodStore()
        let final = try await finalStore.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(final.source == .installedDefault)
        #expect(final.package?.id == reinstalled.package.id)
        #expect(final.package?.revision == reinstalled.package.revision)
        #expect(final.bindingRevision == reinstalled.binding.revision)
    }

    @Test("Working Method edits preserve interposed package and binding changes")
    func workingMethodEditRejectsInterposedChanges() async throws {
        do {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = fixture.workingMethodStore()
            let binding = try await store.installDefaultWorkingMethods()
            let current = try #require(try await store.functionBindingResolution(
                for: .develop,
                actionID: .analyze
            ).package)
            let entryPoint = fixture.control.appendingPathComponent(
                "skills/\(current.id)/SKILL.md"
            )
            let externalSource = current.source + "\n\nINTERPOSED_PACKAGE_EDIT\n"
            let racing = fixture.workingMethodStore(hooks: .init { point in
                if case .beforePackageReplacement = point {
                    try Data(externalSource.utf8).write(to: entryPoint, options: .atomic)
                }
            })

            await #expect(throws: ResearchSkillError.self) {
                _ = try await racing.saveWorkingMethod(
                    for: .analyze,
                    source: current.source + "\n\nREQUESTED_EDIT\n",
                    expectedPackageRevision: try #require(current.revision),
                    expectedBindingRevision: binding.revision
                )
            }
            #expect(try await store.resource(
                id: current.id,
                relativePath: "SKILL.md"
            ) == externalSource)
        }

        do {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = fixture.workingMethodStore()
            let binding = try await store.installDefaultWorkingMethods()
            let current = try #require(try await store.functionBindingResolution(
                for: .develop,
                actionID: .analyze
            ).package)
            let originalBinding = try Data(contentsOf: store.workingMethodBindingsURL)
            let externalBinding: Data = {
                var data = originalBinding
                data.append(contentsOf: Data("\n".utf8))
                return data
            }()
            let racing = fixture.workingMethodStore(hooks: .init { point in
                if case .beforePackageReplacement = point {
                    try externalBinding.write(
                        to: store.workingMethodBindingsURL,
                        options: .atomic
                    )
                }
            })

            await #expect(throws: ResearchSkillBindingError.self) {
                _ = try await racing.saveWorkingMethod(
                    for: .analyze,
                    source: current.source + "\n\nREQUESTED_EDIT\n",
                    expectedPackageRevision: try #require(current.revision),
                    expectedBindingRevision: binding.revision
                )
            }
            #expect(try Data(contentsOf: store.workingMethodBindingsURL) == externalBinding)
            #expect(try await store.package(id: current.id).revision == current.revision)
        }
    }

    @Test("Working Method history uses the existing maintenance snapshot lifecycle")
    func workingMethodHistoryIsRestorable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.workingMethodStore()
        let binding = try await store.installDefaultWorkingMethods()
        let current = try #require(try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        ).package)
        let originalRevision = try #require(current.revision)
        let edited = try await store.saveWorkingMethod(
            for: .analyze,
            source: current.source + "\n\nSNAPSHOT_LIFECYCLE_EDIT\n",
            expectedPackageRevision: originalRevision,
            expectedBindingRevision: binding.revision
        )
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let listing = try await maintenance.snapshots(packageID: current.id)
        let original = try #require(listing.snapshots.first {
            $0.packageRevision == originalRevision
        })
        #expect(listing.issues.isEmpty)

        _ = try await maintenance.restore(
            snapshotID: original.id,
            expectedCurrentState: .present(try #require(edited.revision))
        )
        let restored = try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(restored.package?.revision == originalRevision)
    }

    @Test("Working Method recovery verifies the cross-volume copy fallback")
    func workingMethodCrossVolumeRecoveryFallback() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.workingMethodStore(forceCopyFallback: true)
        let binding = try await store.installDefaultWorkingMethods()
        let current = try #require(try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        ).package)
        let originalRevision = try #require(current.revision)

        _ = try await store.saveWorkingMethod(
            for: .analyze,
            source: current.source + "\n\nCROSS_VOLUME_FALLBACK\n",
            expectedPackageRevision: originalRevision,
            expectedBindingRevision: binding.revision
        )
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let listing = try await maintenance.snapshots(packageID: current.id)
        let snapshot = try #require(listing.snapshots.first {
            $0.packageRevision == originalRevision
        })
        #expect(snapshot.retainedPortablePackageRevision == originalRevision)
        let retainedStages = try FileManager.default.contentsOfDirectory(
            atPath: store.skillsURL.path
        ).filter { $0.hasPrefix(".working-edit-") }
        #expect(retainedStages.count == 1)
        let retainedURL = store.skillsURL.appendingPathComponent(
            try #require(retainedStages.first),
            isDirectory: true
        )
        try FileManager.default.removeItem(at: retainedURL)
        let external = fixture.root.appendingPathComponent(
            "Unsafe Retained Package",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: retainedURL,
            withDestinationURL: external
        )
        let damagedListing = try await maintenance.snapshots(packageID: current.id)
        #expect(damagedListing.snapshots.contains { $0.id == snapshot.id })
        #expect(damagedListing.issues.contains {
            $0.entryName.hasSuffix("/retained-portable")
        })
    }

    @Test("A post-archive fault never rolls a Working Method over external state")
    func workingMethodPostArchiveFaultDoesNotRollback() async throws {
        enum InjectedFailure: Error { case afterArchive }

        let fixture = try Fixture()
        defer { fixture.remove() }
        let initialStore = fixture.workingMethodStore(forceCopyFallback: true)
        let binding = try await initialStore.installDefaultWorkingMethods()
        let current = try #require(try await initialStore.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        ).package)
        let originalRevision = try #require(current.revision)
        let editedSource = current.source + "\n\nPOST_ARCHIVE_EDIT\n"
        let faulting = fixture.workingMethodStore(
            hooks: .init { point in
                if case .afterDisplacedPackageArchive = point {
                    throw InjectedFailure.afterArchive
                }
            },
            forceCopyFallback: true
        )

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await faulting.saveWorkingMethod(
                for: .analyze,
                source: editedSource,
                expectedPackageRevision: originalRevision,
                expectedBindingRevision: binding.revision
            )
        }

        let reopened = fixture.workingMethodStore()
        #expect(try await reopened.resource(
            id: current.id,
            relativePath: "SKILL.md"
        ) == editedSource)
        let listing = try await ResearchSkillMaintenanceStore(
            skillStore: reopened,
            snapshotRootURL: fixture.snapshotRoot
        ).snapshots(packageID: current.id)
        #expect(listing.snapshots.contains {
            $0.packageRevision == originalRevision
                && $0.retainedPortablePackageRevision == originalRevision
        })
    }

    @Test("A post-commit binding fault keeps restored package and binding coherent")
    func restorePostCommitBindingFaultIsRecoverable() async throws {
        enum InjectedFailure: Error { case afterBindingCommit }

        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.workingMethodStore()
        let initial = try await store.installDefaultWorkingMethods()
        let current = try #require(try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        ).package)
        let originalRevision = try #require(current.revision)
        let edited = try await store.saveWorkingMethod(
            for: .analyze,
            source: current.source + "\n\nRESTORE_FAULT_EDIT\n",
            expectedPackageRevision: originalRevision,
            expectedBindingRevision: initial.revision
        )
        let disabled = try await store.disableWorkingMethod(
            for: .analyze,
            expectedBindingRevision: initial.revision
        )
        let faulting = fixture.workingMethodStore(hooks: .init { point in
            if case .afterBindingCommit = point {
                throw InjectedFailure.afterBindingCommit
            }
        })

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await faulting.restoreBundledWorkingMethod(
                for: .analyze,
                expectedPackageState: .present(try #require(edited.revision)),
                expectedBindingRevision: disabled.revision
            )
        }
        let reopened = fixture.workingMethodStore()
        let resolution = try await reopened.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(resolution.source == .installedDefault)
        #expect(resolution.package?.revision == originalRevision)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: reopened,
            snapshotRootURL: fixture.snapshotRoot
        )
        let listing = try await maintenance.snapshots(packageID: current.id)
        #expect(listing.snapshots.contains { $0.packageRevision == edited.revision })
    }

    @Test("Bootstrap ignores hidden residue but never deletes a stable collision")
    func workingMethodBootstrapResiduePolicy() async throws {
        do {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let skills = fixture.control.appendingPathComponent("skills", isDirectory: true)
            try FileManager.default.createDirectory(
                at: skills,
                withIntermediateDirectories: false
            )
            let residue = skills.appendingPathComponent(
                ".working-install-sch-write-interrupted",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: residue, withIntermediateDirectories: false)
            let marker = residue.appendingPathComponent("partial.txt")
            try Data("unfinished".utf8).write(to: marker)

            _ = try await fixture.workingMethodStore().installDefaultWorkingMethods()
            #expect(try String(contentsOf: marker, encoding: .utf8) == "unfinished")
        }

        do {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let collision = fixture.control.appendingPathComponent(
                "skills/scholium-working-discuss",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: collision,
                withIntermediateDirectories: true
            )
            let marker = collision.appendingPathComponent("partial.txt")
            try Data("researcher-owned collision".utf8).write(to: marker)
            let store = fixture.workingMethodStore()

            await #expect(throws: (any Error).self) {
                _ = try await store.installDefaultWorkingMethods()
            }
            #expect(
                try String(contentsOf: marker, encoding: .utf8)
                    == "researcher-owned collision"
            )
            #expect(!FileManager.default.fileExists(
                atPath: store.workingMethodBindingsURL.path
            ))
        }
    }

    @Test("Working Method activation rejects invalid and bundled Method dependencies")
    func workingMethodDependencyBoundary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.workingMethodStore()
        let binding = try await store.installDefaultWorkingMethods()
        _ = try await store.create(
            id: "indirect-specialist-leaf",
            source: Self.analyzeSpecialistSource(
                id: "indirect-specialist-leaf",
                dependencies: ["scholium-analyze"]
            )
        )
        let candidates = [
            ("missing-dependency-method", ["missing-method"]),
            ("bundled-dependency-method", ["scholium-analyze"]),
            ("indirect-missing-leaf", ["missing-transitive-method"]),
            ("indirect-missing-root", ["indirect-missing-leaf"]),
            ("indirect-bundled-leaf", ["scholium-analyze"]),
            ("indirect-bundled-root", ["indirect-bundled-leaf"]),
            ("indirect-specialist-root", ["indirect-specialist-leaf"]),
            ("cycle-a", ["cycle-b"]),
            ("cycle-b", ["cycle-a"]),
        ]
        var packages: [String: ResearchSkillPackage] = [:]
        for (id, dependencies) in candidates {
            packages[id] = try await store.create(
                id: id,
                source: Self.analyzeMethodSource(id: id, dependencies: dependencies)
            )
        }
        for id in [
            "missing-dependency-method",
            "bundled-dependency-method",
            "indirect-missing-root",
            "indirect-bundled-root",
            "indirect-specialist-root",
            "cycle-a",
        ] {
            await #expect(throws: ResearchSkillBindingError.self) {
                _ = try await store.activateResearcherSkill(
                    packageID: try #require(packages[id]).id,
                    for: .analyze,
                    expectedBindingRevision: binding.revision
                )
            }
        }
        let resolution = try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(resolution.source == .installedDefault)
    }

    @Test("Malformed binding v2 closes the Action without bundled fallback")
    func malformedWorkingMethodBindingFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.workingMethodStore()
        try FileManager.default.createDirectory(
            at: fixture.control,
            withIntermediateDirectories: true
        )
        let future = Data(
            #"{"schema_version":3,"action_bindings":{"analyze":{"state":"disabled"}}}"#.utf8
        )
        try future.write(to: store.workingMethodBindingsURL, options: .atomic)
        let rawRevision = try #require(
            try await store.workingMethodBindingFileRevision()
        )

        let resolution = try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(resolution.source == .none)
        #expect(resolution.package == nil)
        #expect(resolution.bindingRevision == rawRevision)
        #expect(resolution.bundledTemplateAvailable)
        guard case .malformed = resolution.issue else {
            Issue.record("Expected malformed binding v2 to fail closed.")
            return
        }

        try Data(repeating: 0x20, count: 1_048_577).write(
            to: store.workingMethodBindingsURL,
            options: .atomic
        )
        let oversized = try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(oversized.package == nil)
        guard case .malformed = oversized.issue else {
            Issue.record("Expected oversized binding v2 to fail closed.")
            return
        }
    }

    @Test("A linked control directory cannot redirect Working Method bootstrap")
    func linkedControlCannotRedirectWorkingMethods() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = fixture.root.appendingPathComponent(
            "External Control",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: external,
            withIntermediateDirectories: false
        )
        try FileManager.default.removeItem(at: fixture.control)
        try FileManager.default.createSymbolicLink(
            at: fixture.control,
            withDestinationURL: external
        )
        let store = ResearchSkillStore(controlURL: fixture.control)

        await #expect(throws: (any Error).self) {
            _ = try await store.installDefaultWorkingMethods()
        }
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty
        )
    }

    @Test("A replacement Method must match both the Action and protected Function")
    func replacementMethodMustMatchExecutionBoundary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let bindings = try await store.installDefaultWorkingMethods()
        let source = """
        ---
        name: mismatched-analysis
        description: Declares Analyze over the wrong protected execution mechanism.
        scholium:
          role: method
          supported_actions: [analyze]
          supported_functions: [revise]
          capabilities: []
          citation_styles: []
          allow_evolution: false
          supported_modes: [analyze]
          required_skills: []
        ---

        Keep the mismatch explicit for this failure fixture.
        """
        let package = try await store.create(
            id: "mismatched-analysis",
            source: source
        )

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await store.activateResearcherSkill(
                packageID: package.id,
                for: .analyze,
                expectedBindingRevision: bindings.revision
            )
        }
        let protectedShadow = store.skillsURL.appendingPathComponent(
            "scholium-analyze",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: protectedShadow,
            withIntermediateDirectories: false
        )
        try Data(source.replacingOccurrences(
            of: "name: mismatched-analysis",
            with: "name: scholium-analyze"
        ).replacingOccurrences(
            of: "supported_functions: [revise]",
            with: "supported_functions: [develop]"
        ).utf8).write(
            to: protectedShadow.appendingPathComponent("SKILL.md"),
            options: .atomic
        )
        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await store.activateResearcherSkill(
                packageID: "scholium-analyze",
                for: .analyze,
                expectedBindingRevision: bindings.revision
            )
        }
        let resolution = try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(resolution.package?.id == "scholium-working-analyze")
        #expect(resolution.bindingRevision == bindings.revision)
    }

    @Test("Citation status distinguishes template, installed candidate, active binding, and style mismatch")
    func citationBindingStates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        _ = try await store.installDefaultWorkingMethods()

        let missing = try await store.citationBindingResolution()
        #expect(missing.issue == .missing)
        #expect(missing.bundledTemplateAvailable)
        #expect(missing.installedCandidateIDs.isEmpty)
        #expect(missing.bindingRevision == nil)

        let local = try await store.duplicateBundled(
            id: "scholium-citation-verification",
            as: "my-apa-citations"
        )
        let installed = try await store.citationBindingResolution()
        #expect(installed.issue == .missing)
        #expect(installed.installedCandidateIDs == [local.id])
        #expect(installed.package == nil)

        let binding = try await store.activateCitationBinding(
            packageID: local.id,
            citationStyle: "apa-7",
            expectedBindingRevision: nil
        )
        let active = try await store.citationBindingResolution(citationStyle: "apa-7")
        #expect(active.source == .triptychBinding)
        #expect(active.package?.id == local.id)
        #expect(active.citationStyle == "apa-7")
        #expect(active.bindingRevision == binding.revision)
        #expect(active.issue == nil)

        let mismatch = try await store.citationBindingResolution(
            requiredCapabilities: [.citationVerification, .citationFormatting],
            citationStyle: "chicago-author-date"
        )
        #expect(
            mismatch.issue
                == .citationStyleMismatch(
                    packageID: local.id,
                    requested: "chicago-author-date"
                )
        )

        let selections = try await store.resolvedFunctionPackages(
            for: .fidelity,
            actionID: .checkFidelity,
            fidelityChecks: [.citations],
            citationStyle: "apa-7"
        )
        let citation = try #require(selections.first { $0.id == local.id })
        #expect(citation.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/apa-7-starter.md",
            "references/verification-method.md",
        ])
    }

    @Test("Incomplete package-only citation bindings require explicit style repair")
    func incompleteCitationBindingNeedsStyleRepair() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let local = try await store.duplicateBundled(
            id: "scholium-citation-verification",
            as: "incomplete-citations"
        )
        try FileManager.default.createDirectory(
            at: fixture.control,
            withIntermediateDirectories: true
        )
        let incomplete = """
        {
          "schema_version" : 1,
          "function_bindings" : {},
          "function_skill_bindings" : {},
          "function_practice_bindings" : {},
          "citation_binding" : "\(local.id)"
        }
        """
        try Data(incomplete.utf8).write(to: store.bindingsURL, options: .atomic)

        let snapshot = try #require(try await store.bindingSnapshot())
        #expect(snapshot.document.citationStyle == nil)
        let resolution = try await store.citationBindingResolution()
        #expect(resolution.issue == .citationStyleMissing(packageID: local.id))
        #expect(!resolution.isActive)
    }

    @Test("Malformed citation bindings expose a raw repair revision")
    func malformedCitationBindingCanBeRepairedRevisionSafely() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        try FileManager.default.createDirectory(
            at: fixture.control,
            withIntermediateDirectories: true
        )
        try Data("{ malformed".utf8).write(to: store.bindingsURL)

        let rawRevision = try #require(try await store.bindingFileRevision())
        let malformed = try await store.citationBindingResolution()
        #expect(malformed.bindingRevision == rawRevision)
        guard case .malformed = malformed.issue else {
            Issue.record("Expected a typed malformed-binding status.")
            return
        }

        let adopted = try await store.adoptAPACitationStarter(
            expectedBindingRevision: rawRevision
        )
        #expect(adopted.package.origin == .triptych)
        #expect(adopted.package.citationStyles == ["apa-7"])
        #expect(
            adopted.package.citationStyleResources["apa-7"]
                == "references/apa-7-starter.md"
        )
        let repaired = try await store.citationBindingResolution(citationStyle: "apa-7")
        #expect(repaired.package?.id == adopted.package.id)
        #expect(repaired.issue == nil)
    }

    @Test("Action assembly snapshots the complete exact Method resources")
    func exactSelectiveResources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        _ = try await store.installDefaultWorkingMethods()

        let selections = try await store.resolvedFunctionPackages(
            for: .revise,
            actionID: .write,
            primaryResourcePaths: ["references/feedback.md"]
        )
        let core = try #require(selections.first {
            $0.id == "scholium-core-protocol"
        })
        #expect(core.loadedResources.map(\.relativePath) == ["SKILL.md"])
        #expect(!core.loadedResources.map(\.relativePath).contains(
            "references/agent-transport.md"
        ))
        let integration = try #require(selections.first {
            $0.id == "scholium-research-integration"
        })
        #expect(integration.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/cli-contract.md",
            "references/persistence-method.md",
        ])
        let writing = try #require(selections.first {
            $0.id == "scholium-working-write"
        })
        #expect(writing.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/feedback.md",
            "references/method.md",
        ])
        #expect(writing.loadedResources.allSatisfy {
            $0.revision == DocumentFingerprint(content: $0.source)
        })

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await store.resolvedFunctionPackages(
                for: .fidelity,
                actionID: .checkFidelity,
                fidelityChecks: [.citations],
                citationStyle: "apa-7"
            )
        }
    }

    @Test("Protected mechanism resources follow the exact Action boundary")
    func protectedMechanismResourcesAreActionBounded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        _ = try await store.installDefaultWorkingMethods()

        let discuss = try await store.resolvedFunctionPackages(
            for: .discuss,
            actionID: .discuss
        )
        let discussionProtocol = try #require(discuss.first {
            $0.id == "scholium-discussion-protocol"
        })
        #expect(discussionProtocol.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/record-contract.md",
        ])
        let discussMethod = try #require(discuss.first {
            $0.id == "scholium-working-discuss"
        })
        #expect(discussMethod.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/method.md",
            "references/response-contract.md",
        ])
        let discussIntegration = try #require(discuss.first {
            $0.id == "scholium-research-integration"
        })
        #expect(discussIntegration.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/cli-contract.md",
        ])

        let fidelity = try await store.resolvedFunctionPackages(
            for: .fidelity,
            actionID: .checkFidelity,
            fidelityChecks: [.content]
        )
        let fidelityIntegration = try #require(fidelity.first {
            $0.id == "scholium-research-integration"
        })
        #expect(fidelityIntegration.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/cli-contract.md",
        ])

        let critique = try await store.resolvedFunctionPackages(
            for: .critique,
            actionID: .critique
        )
        let critiqueIntegration = try #require(critique.first {
            $0.id == "scholium-research-integration"
        })
        #expect(critiqueIntegration.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/cli-contract.md",
            "references/persistence-method.md",
        ])
        #expect((discuss + fidelity).flatMap(\.loadedResources).allSatisfy {
            $0.revision == DocumentFingerprint(content: $0.source)
        })
    }

    @Test("Self-contained local Methods retain protected mechanism without bundled filenames")
    func selfContainedLocalMethodsAreExecutable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.workingMethodStore()
        var bindingRevision = try await store
            .installDefaultWorkingMethods().revision
        let cases: [(String, ResearchFunctionID, ResearchActionID, ResearchSkillMode)] = [
            ("local-analyze", .develop, .analyze, .analyze),
            ("local-write", .revise, .write, .write),
            ("local-fidelity", .fidelity, .checkFidelity, .audit),
        ]
        for (id, function, actionID, mode) in cases {
            let source = """
            ---
            name: \(id)
            description: A self-contained researcher Method used to prove bounded assembly.
            scholium:
              role: method
              supported_actions: [\(actionID.rawValue)]
              supported_functions: [\(function.rawValue)]
              capabilities: []
              citation_styles: []
              allow_evolution: false
              supported_modes: [\(mode.rawValue)]
              required_skills: []
            ---

            # Self-contained Method

            Follow the exact typed Action boundary and use no additional package file.
            """
            let local = try await store.create(id: id, source: source)
            let saved = try await store.activateResearcherSkill(
                packageID: local.id,
                for: actionID,
                expectedBindingRevision: bindingRevision
            )
            bindingRevision = saved.revision

            let selections = try await store.resolvedFunctionPackages(
                for: function,
                actionID: actionID,
                fidelityChecks: function == .fidelity ? [.content] : []
            )
            let primary = try #require(selections.first { $0.id == local.id })
            #expect(primary.loadedResources.map(\.relativePath) == ["SKILL.md"])
            #expect(selections.contains { $0.id == "scholium-core-protocol" })
            #expect(selections.contains { $0.id == "scholium-research-integration" })
        }
    }

    @Test("A local Fidelity copy loads only the selected check resource")
    func localFidelityResourcesRemainCheckBounded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.workingMethodStore()
        let initial = try await store.installDefaultWorkingMethods()
        let local = try await store.duplicateBundled(
            id: "scholium-content-fidelity",
            as: "my-content-fidelity"
        )
        _ = try await store.activateResearcherSkill(
            packageID: local.id,
            for: .checkFidelity,
            expectedBindingRevision: initial.revision
        )

        let selections = try await store.resolvedFunctionPackages(
            for: .fidelity,
            actionID: .checkFidelity,
            fidelityChecks: [.content]
        )
        let primary = try #require(selections.first { $0.id == local.id })
        #expect(primary.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/content.md",
        ])
        #expect(!primary.loadedResources.contains {
            $0.relativePath == "references/citations.md"
        })
    }

    @Test("An external Skill edit between routing and capture fails closed")
    func interposedLocalSkillEditCannotCreateMixedSnapshot() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let source = """
        ---
        name: snapshot-method
        description: A bounded snapshot race fixture.
        scholium:
          role: method
          supported_actions: [analyze]
          supported_functions: [develop]
          capabilities: []
          citation_styles: []
          allow_evolution: false
          supported_modes: [analyze]
          required_skills: []
        ---

        # Snapshot Method
        """
        let package = try await store.create(id: "snapshot-method", source: source)
        let expectedRevision = try #require(package.revision)
        let sourceURL = store.skillsURL
            .appendingPathComponent(package.id, isDirectory: true)
            .appendingPathComponent("SKILL.md", isDirectory: false)
        try Data((source + "\nExternal edit.\n").utf8).write(to: sourceURL, options: .atomic)

        await #expect(throws: ResearchSkillError.self) {
            _ = try await store.packageResourceSnapshot(
                id: package.id,
                expectedRevision: expectedRevision
            )
        }
    }

    @Test("Legacy Function bindings remain byte-stable and cannot authorize Action resolution")
    func legacyFunctionBindingsArePreservedAndIgnored() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let local = try await store.duplicateBundled(
            id: "scholium-analyze",
            as: "my-analysis-method"
        )

        let saved = try await store.saveFunctionSkillSelection(
            ResearchFunctionSkillSelection(
                function: .develop,
                primaryPackageID: local.id
            ),
            expectedBindingRevision: nil
        )
        let selected = try await store.functionSkillSelection(for: .develop)
        #expect(selected.primaryPackageID == local.id)
        let beforeV2 = try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(beforeV2.source == .none)
        #expect(beforeV2.issue == .missing)
        #expect(beforeV2.package == nil)
        let legacyBytes = try Data(contentsOf: store.bindingsURL)
        let legacyDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640, .modificationDate: legacyDate],
            ofItemAtPath: store.bindingsURL.path
        )
        let initial = try await store.installDefaultWorkingMethods()
        #expect(try Data(contentsOf: store.bindingsURL) == legacyBytes)
        let preservedAttributes = try FileManager.default.attributesOfItem(
            atPath: store.bindingsURL.path
        )
        #expect((preservedAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        #expect((preservedAttributes[.modificationDate] as? Date) == legacyDate)
        let active = try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(active.source == .installedDefault)
        #expect(active.package?.id == "scholium-working-analyze")
        #expect(active.bindingRevision == initial.revision)

        let wrongAction = try await store.functionBindingResolution(
            for: .develop,
            actionID: .synthesize
        )
        #expect(wrongAction.source == .installedDefault)
        #expect(wrongAction.package?.id == "scholium-working-synthesize")

        let cleared = try await store.clearFunctionSkillSelection(
            for: .develop,
            expectedBindingRevision: saved.revision
        )
        #expect(try await store.functionSkillSelection(for: .develop).isEmpty)
        let fallback = try await store.functionBindingResolution(
            for: .develop,
            actionID: .analyze
        )
        #expect(fallback.source == .installedDefault)
        #expect(fallback.package?.id == "scholium-working-analyze")
        #expect(fallback.bindingRevision == initial.revision)

        let currentLegacyRevision = try await store.bindingFileRevision()
        #expect(cleared.revision == currentLegacyRevision)

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await store.saveFunctionSkillSelection(
                ResearchFunctionSkillSelection(
                    function: .develop,
                    primaryPackageID: local.id
                ),
                expectedBindingRevision: saved.revision
            )
        }
    }

    @Test("Legacy specialist and Practice bindings do not enter Action resolution")
    func legacyResearcherGuidanceDoesNotEnrichActionContract() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        _ = try await store.installDefaultWorkingMethods()
        let prose = try await store.duplicateBundled(
            id: "scholium-prose-control",
            as: "my-prose-control"
        )
        let practices = try await store.duplicateBundled(
            id: "scholium-philosophical-practices",
            as: "my-practices"
        )
        let practice = ResearchPracticeSelection(
            packageID: practices.id,
            practiceID: "philosophical-expositor"
        )
        _ = try await store.saveFunctionSkillSelection(
            ResearchFunctionSkillSelection(
                function: .revise,
                supplementalPackageIDs: [prose.id],
                selectedPractices: [practice]
            ),
            expectedBindingRevision: nil
        )

        let target = ResearchWorkflowObjectReference(
            kind: .note,
            identifier: "Works/Argument.md"
        )
        let contract = ResearchWorkflowContract(
            mode: .write,
            taskObject: "Revise one Work",
            purpose: "Improve the expression without widening the write boundary.",
            originalReadSet: [target],
            originalWriteSet: [],
            phases: [ResearchWorkflowPhaseContract(
                phase: 1,
                mode: .write,
                purpose: "Revise one bounded passage.",
                requiredSkillIDs: [],
                readSet: [target],
                writeSet: [],
                permission: .readOnly,
                permissionBasis: "",
                output: "Return one bounded candidate revision.",
                stopCondition: "Stop rather than change a philosophical commitment.",
                durability: .handoff,
                handoff: ResearchWorkflowHandoff(
                    summary: "The candidate remains provisional.",
                    evidenceStatus: "Exact Work revision inspected."
                )
            )]
        )
        let envelope = try await ResearchWorkflowAssembler.resolveFunction(
            contract,
            function: .revise,
            actionID: .write,
            store: store
        )
        let phase = try #require(envelope.contract.phases.first)
        #expect(phase.requiredSkillIDs == ["scholium-working-write"])
        #expect(phase.selectedPractices.isEmpty)
        #expect(!envelope.phases[0].packages.contains { $0.id == prose.id })
        #expect(!envelope.phases[0].packages.contains { $0.id == practices.id })
        #expect(envelope.isExecutable)
    }

    @Test("Action assembly cannot mix a changed binding or primary package revision")
    func actionAssemblyPinsOneExactPrimaryMethod() async throws {
        do {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = fixture.workingMethodStore()
            var binding = try await store.installDefaultWorkingMethods()
            let methodA = try await store.create(
                id: "assembly-method-a",
                source: Self.analyzeMethodSource(
                    id: "assembly-method-a",
                    dependencies: []
                )
            )
            let methodB = try await store.create(
                id: "assembly-method-b",
                source: Self.analyzeMethodSource(
                    id: "assembly-method-b",
                    dependencies: []
                )
            )
            binding = try await store.activateResearcherSkill(
                packageID: methodA.id,
                for: .analyze,
                expectedBindingRevision: binding.revision
            )
            let replacementDocument = try binding.document.replacing(
                ResearchWorkingMethodBinding(
                    state: .researcherSkill,
                    packageID: methodB.id
                ),
                for: .analyze
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
            ]
            let replacementData = try encoder.encode(replacementDocument)
            let racing = fixture.workingMethodStore(hooks: .init { point in
                if case .beforeFunctionPackageResolution(actionID: .analyze) = point {
                    try replacementData.write(
                        to: store.workingMethodBindingsURL,
                        options: .atomic
                    )
                }
            })

            await #expect(throws: ResearchSkillBindingError.self) {
                _ = try await ResearchWorkflowAssembler.resolveFunction(
                    Self.analyzeWorkflowContract(),
                    function: .develop,
                    actionID: .analyze,
                    store: racing
                )
            }
            let active = try await store.functionBindingResolution(
                for: .develop,
                actionID: .analyze
            )
            #expect(active.package?.id == methodB.id)
        }

        do {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = fixture.workingMethodStore()
            _ = try await store.installDefaultWorkingMethods()
            let current = try #require(try await store.functionBindingResolution(
                for: .develop,
                actionID: .analyze
            ).package)
            let changedSource = current.source.replacingOccurrences(
                of: "supported_actions: [analyze]",
                with: "supported_actions: [synthesize]"
            )
            let entryPoint = store.skillsURL
                .appendingPathComponent(current.id, isDirectory: true)
                .appendingPathComponent("SKILL.md")
            let racing = fixture.workingMethodStore(hooks: .init { point in
                if case .beforeFunctionPackageResolution(actionID: .analyze) = point {
                    try Data(changedSource.utf8).write(
                        to: entryPoint,
                        options: .atomic
                    )
                }
            })

            await #expect(throws: (any Error).self) {
                _ = try await ResearchWorkflowAssembler.resolveFunction(
                    Self.analyzeWorkflowContract(),
                    function: .develop,
                    actionID: .analyze,
                    store: racing
                )
            }
        }

        do {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = fixture.workingMethodStore()
            _ = try await store.installDefaultWorkingMethods()
            let practices = try await store.duplicateBundled(
                id: "scholium-philosophical-practices",
                as: "assembly-race-practices"
            )
            let selection = ResearchPracticeSelection(
                packageID: practices.id,
                practiceID: "philosophical-expositor"
            )
            let entryPoint = store.skillsURL
                .appendingPathComponent(practices.id, isDirectory: true)
                .appendingPathComponent("SKILL.md")
            let changedSource = practices.source + "\n\nPRACTICE_RACE_EDIT\n"
            let racing = fixture.workingMethodStore(hooks: .init { point in
                if case .beforeFunctionPackageResolution(actionID: .analyze) = point {
                    try Data(changedSource.utf8).write(
                        to: entryPoint,
                        options: .atomic
                    )
                }
            })

            await #expect(throws: (any Error).self) {
                _ = try await ResearchWorkflowAssembler.resolveFunction(
                    Self.analyzeWorkflowContract(selectedPractices: [selection]),
                    function: .develop,
                    actionID: .analyze,
                    store: racing
                )
            }
        }
    }

    @Test("Reviewer calibrates Critique only")
    func reviewerIsCritiqueOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let practices = try await store.duplicateBundled(
            id: "scholium-philosophical-practices",
            as: "my-review-practices"
        )
        let reviewer = ResearchPracticeSelection(
            packageID: practices.id,
            practiceID: "reviewer"
        )

        #expect((try await store.compatiblePracticeIDs(for: .critique)).contains("reviewer"))
        #expect(!(try await store.compatiblePracticeIDs(for: .revise)).contains("reviewer"))
        #expect(!(try await store.compatiblePracticeIDs(for: .fidelity)).contains("reviewer"))
        #expect((try await store.compatiblePracticeIDs(for: .manuscript)).isEmpty)

        let saved = try await store.saveFunctionSkillSelection(
            ResearchFunctionSkillSelection(
                function: .critique,
                selectedPractices: [reviewer]
            ),
            expectedBindingRevision: nil
        )
        #expect(try await store.functionSkillSelection(for: .critique)
            .selectedPractices == [reviewer])

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await store.saveFunctionSkillSelection(
                ResearchFunctionSkillSelection(
                    function: .revise,
                    selectedPractices: [reviewer]
                ),
                expectedBindingRevision: saved.revision
            )
        }
    }

    @Test("Legacy Develop guidance exposes only Practices shared by Analyze and Synthesize")
    func legacyDevelopPracticeCompatibilityIsIntersection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)

        #expect(try await store.compatiblePracticeIDs(for: .develop) == [
            "argument-reconstructionist",
            "conceptual-analyst",
            "dialectical-partner",
        ])
        #expect(!(try await store.compatiblePracticeIDs(for: .develop)
            .contains("research-explorer")))
        #expect(!(try await store.compatiblePracticeIDs(for: .develop)
            .contains("systematizer")))
    }

    @Test("Whole-package revisions bind every retained resource")
    func wholePackageRevision() {
        let entry = ResearchSkillMaintenanceFile(
            relativePath: "SKILL.md",
            source: "---\nname: Test\ndescription: Test.\n---\nBody"
        )
        let first = ResearchSkillProposedPackage(files: [
            entry,
            ResearchSkillMaintenanceFile(relativePath: "evals/cases.md", source: "A"),
        ])
        let changed = ResearchSkillProposedPackage(files: [
            entry,
            ResearchSkillMaintenanceFile(relativePath: "evals/cases.md", source: "B"),
        ])
        #expect(first.packageRevision != changed.packageRevision)
        #expect(throws: ResearchSkillMaintenanceError.self) {
            try ResearchSkillProposedPackage(files: [
                entry,
                ResearchSkillMaintenanceFile(relativePath: "../escape.md", source: "x"),
            ]).validate()
        }
        #expect(throws: ResearchSkillMaintenanceError.self) {
            try ResearchSkillProposedPackage(files: [
                entry,
                ResearchSkillMaintenanceFile(relativePath: "evals/unsafe\nname.md", source: "x"),
            ]).validate()
        }
    }

    @Test("Structural validation remains incomplete without revision-bound external evidence")
    func maintenanceEvaluationGates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "Improved instructions.")

        let incomplete = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: try #require(current.revision),
            proposedPackage: proposal,
            instruction: "Adapt this method to the observed workflow."
        ))
        #expect(incomplete.evaluation.structuralStatus == .passed)
        #expect(incomplete.evaluation.externalStatus == .incomplete)
        #expect(incomplete.evaluation.status == .incomplete)
        #expect(incomplete.confirmationToken == nil)

        let mismatchedEvidence = Self.passingEvidence(
            revision: DocumentFingerprint(content: "another proposal")
        )
        let mismatch = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: try #require(current.revision),
            proposedPackage: proposal,
            instruction: "Adapt this method to the observed workflow.",
            evaluationEvidence: mismatchedEvidence
        ))
        #expect(mismatch.evaluation.externalStatus == .incomplete)
        #expect(mismatch.confirmationToken == nil)

        let invalidCases = ResearchSkillMaintenanceExternalEvaluation(
            proposedPackageRevision: proposal.packageRevision,
            evaluator: "External Research Agent",
            method: "Adversarial cases",
            status: .passed,
            cases: [
                ResearchSkillMaintenanceEvaluationCase(
                    id: "duplicate",
                    status: .passed,
                    summary: ""
                ),
                ResearchSkillMaintenanceEvaluationCase(
                    id: "duplicate",
                    status: .passed,
                    summary: "A second result."
                ),
            ]
        )
        let malformed = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: try #require(current.revision),
            proposedPackage: proposal,
            instruction: "Adapt this method to the observed workflow.",
            evaluationEvidence: invalidCases
        ))
        #expect(malformed.evaluation.externalStatus == .incomplete)
        #expect(malformed.confirmationToken == nil)
    }

    @Test("Revision-bound external evaluation permits atomic apply and snapshot restore")
    func maintenanceApplyAndRestore() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "Improved instructions.")
        let request = ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: originalRevision,
            proposedPackage: proposal,
            instruction: "Adapt this method to the observed workflow.",
            evaluationEvidence: Self.passingEvidence(revision: proposal.packageRevision)
        )
        let preparation = try await maintenance.prepare(request)
        #expect(preparation.evaluation.structuralStatus == .passed)
        #expect(preparation.evaluation.externalStatus == .passed)
        #expect(preparation.evaluation.status == .passed)
        let token = try #require(preparation.confirmationToken)

        let applied = try await maintenance.apply(
            preparation,
            confirmationToken: token
        )
        #expect(applied.packageRevision == proposal.packageRevision)
        #expect(FileManager.default.fileExists(
            atPath: fixture.snapshotRoot
                .appendingPathComponent(applied.snapshotID.uuidString)
                .path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.control
                .appendingPathComponent("skill-maintenance-snapshots")
                .path
        ))
        #expect(try await store.resource(id: current.id, relativePath: "SKILL.md")
            .contains("Improved instructions."))

        let listed = try await maintenance.snapshots(packageID: current.id)
        #expect(listed.issues.isEmpty)
        #expect(listed.snapshots.count == 1)
        #expect(listed.snapshots.first?.id == applied.snapshotID)
        #expect(listed.snapshots.first?.packageID == current.id)
        #expect(listed.snapshots.first?.packageRevision == originalRevision)

        // Recovery metadata is reconstructed from durable Core state rather
        // than an in-memory Apply outcome retained by Settings.
        let reopenedMaintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        #expect(try await reopenedMaintenance.snapshots(packageID: current.id) == listed)

        let restored = try await reopenedMaintenance.restore(
            snapshotID: applied.snapshotID,
            expectedCurrentState: .present(applied.packageRevision)
        )
        #expect(restored.restoredPackageRevision == originalRevision)
        let undo = try #require(restored.undoSnapshot)
        #expect(undo.packageRevision == applied.packageRevision)
        #expect(try await store.resource(id: current.id, relativePath: "SKILL.md")
            .contains("Original instructions."))

        let afterRestore = try await reopenedMaintenance.snapshots(packageID: current.id)
        #expect(afterRestore.issues.isEmpty)
        #expect(Set(afterRestore.snapshots.map(\.id)) == Set([applied.snapshotID, undo.id]))
        let roundTrip = try await reopenedMaintenance.restore(
            snapshotID: undo.id,
            expectedCurrentState: .present(originalRevision)
        )
        #expect(roundTrip.restoredPackageRevision == applied.packageRevision)
        #expect(roundTrip.undoSnapshot?.packageRevision == originalRevision)
        #expect(try await store.resource(id: current.id, relativePath: "SKILL.md")
            .contains("Improved instructions."))
    }

    @Test("A durable snapshot restores an explicitly missing package without bypassing absence")
    func maintenanceRestoreMissingPackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "A temporary improved package.")
        let preparation = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: originalRevision,
            proposedPackage: proposal,
            instruction: "Create a durable recovery snapshot.",
            evaluationEvidence: Self.passingEvidence(revision: proposal.packageRevision)
        ))
        let applied = try await maintenance.apply(
            preparation,
            confirmationToken: try #require(preparation.confirmationToken)
        )
        try await store.delete(id: current.id, expectedRevision: applied.packageRevision)

        let restored = try await maintenance.restore(
            snapshotID: applied.snapshotID,
            expectedCurrentState: .missing
        )
        #expect(restored.replacedPackageRevision == nil)
        #expect(restored.undoSnapshot == nil)
        #expect(try await store.package(id: current.id).revision == originalRevision)

        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.restore(
                snapshotID: applied.snapshotID,
                expectedCurrentState: .missing
            )
        }
        #expect(try await store.package(id: current.id).revision == originalRevision)
    }

    @Test("Restore snapshots and round-trips a bounded semantically malformed package")
    func maintenanceRestoreMalformedPackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "A valid replacement.")
        let preparation = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: originalRevision,
            proposedPackage: proposal,
            instruction: "Create the source recovery snapshot.",
            evaluationEvidence: Self.passingEvidence(revision: proposal.packageRevision)
        ))
        let applied = try await maintenance.apply(
            preparation,
            confirmationToken: try #require(preparation.confirmationToken)
        )
        let malformedSource = "---\nname: [unterminated\n---\nMalformed but bounded."
        let entryPoint = fixture.control.appendingPathComponent(
            "skills/\(current.id)/SKILL.md"
        )
        try Data(malformedSource.utf8).write(to: entryPoint, options: .atomic)
        let malformed = try await store.package(id: current.id)
        #expect(!malformed.isValid)
        let malformedRevision = try #require(malformed.revision)

        let restored = try await maintenance.restore(
            snapshotID: applied.snapshotID,
            expectedCurrentState: .present(malformedRevision)
        )
        let malformedUndo = try #require(restored.undoSnapshot)
        #expect(malformedUndo.packageRevision == malformedRevision)
        #expect(try await store.package(id: current.id).revision == originalRevision)

        let listing = try await maintenance.snapshots(packageID: current.id)
        #expect(listing.issues.isEmpty)
        #expect(listing.snapshots.contains { $0.id == malformedUndo.id })
        _ = try await maintenance.restore(
            snapshotID: malformedUndo.id,
            expectedCurrentState: .present(originalRevision)
        )
        #expect(try await store.resource(id: current.id, relativePath: "SKILL.md")
            == malformedSource)
    }

    @Test("A linked corrupt snapshot is reported without hiding valid recovery")
    func maintenanceSnapshotListingIsPartialAndNoFollow() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "A replacement with one valid snapshot.")
        let preparation = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: originalRevision,
            proposedPackage: proposal,
            instruction: "Exercise independent snapshot listing.",
            evaluationEvidence: Self.passingEvidence(revision: proposal.packageRevision)
        ))
        let applied = try await maintenance.apply(
            preparation,
            confirmationToken: try #require(preparation.confirmationToken)
        )

        let validRoot = fixture.snapshotRoot.appendingPathComponent(
            applied.snapshotID.uuidString,
            isDirectory: true
        )
        let corruptID = UUID()
        let corruptRoot = fixture.snapshotRoot.appendingPathComponent(
            corruptID.uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: false)
        let manifest = try String(
            contentsOf: validRoot.appendingPathComponent("manifest.json"),
            encoding: .utf8
        ).replacingOccurrences(
            of: applied.snapshotID.uuidString,
            with: corruptID.uuidString
        )
        try Data(manifest.utf8).write(
            to: corruptRoot.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try FileManager.default.createSymbolicLink(
            at: corruptRoot.appendingPathComponent("package", isDirectory: true),
            withDestinationURL: validRoot.appendingPathComponent("package", isDirectory: true)
        )

        let listing = try await maintenance.snapshots(packageID: current.id)
        #expect(listing.snapshots.map(\.id) == [applied.snapshotID])
        let issue = try #require(listing.issues.first { $0.snapshotID == corruptID })
        #expect(issue.code == .invalidPackage)
        #expect(try await store.package(id: current.id).revision == proposal.packageRevision)
    }

    @Test("Bundled and symlinked packages refuse evolution")
    func maintenanceBoundaries() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let bundled = try await store.bundledPackage(id: "scholium-analyze")
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
                packageID: bundled.id,
                expectedPackageRevision: try #require(bundled.revision),
                proposedPackage: Self.proposal(body: "No."),
                instruction: "Attempt to mutate bundled guidance."
            ))
        }

        let local = try await fixture.createEvolvablePackage(in: store, id: "linked-method")
        let outside = fixture.root.appendingPathComponent("outside.md")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: fixture.control
                .appendingPathComponent("skills/linked-method/references/linked.md"),
            withDestinationURL: outside
        )
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
                packageID: local.id,
                expectedPackageRevision: try #require(local.revision),
                proposedPackage: Self.proposal(body: "No link following."),
                instruction: "Attempt maintenance with a linked resource."
            ))
        }
    }

    @Test("A linked control ancestor cannot redirect Researcher Skill maintenance")
    func linkedControlAncestorIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumLinkedControlMaintenance-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("Container", isDirectory: true)
        let works = container.appendingPathComponent("Works", isDirectory: true)
        let outsideControl = root.appendingPathComponent("OutsideControl", isDirectory: true)
        let linkedControl = container.appendingPathComponent(".scholium", isDirectory: true)
        try FileManager.default.createDirectory(at: works, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: outsideControl,
            withIntermediateDirectories: true
        )
        let outsideStore = ResearchSkillStore(controlURL: outsideControl)
        let current = try await Self.createEvolvablePackage(
            in: outsideStore,
            controlURL: outsideControl
        )
        let originalRevision = try #require(current.revision)
        let originalSource = try await outsideStore.resource(
            id: current.id,
            relativePath: "SKILL.md"
        )
        try FileManager.default.createSymbolicLink(
            at: linkedControl,
            withDestinationURL: outsideControl
        )

        let linkedStore = ResearchSkillStore(controlURL: linkedControl)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: linkedStore,
            snapshotRootURL: root.appendingPathComponent("Snapshots", isDirectory: true)
        )
        let proposal = Self.proposal(body: "This must not reach the outside package.")
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise linked control containment.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            ))
        }
        #expect(try await outsideStore.package(id: current.id).revision == originalRevision)
        #expect(try await outsideStore.resource(
            id: current.id,
            relativePath: "SKILL.md"
        ) == originalSource)
    }

    @Test("A control-parent swap cannot redirect replacement or change external state")
    func parentSwapCannotRedirectReplacement() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let proposal = Self.proposal(body: "A replacement that must be rejected.")

        let outsideControl = fixture.root.appendingPathComponent(
            "OutsideControl",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outsideControl,
            withIntermediateDirectories: true
        )
        let outsideStore = ResearchSkillStore(controlURL: outsideControl)
        let outside = try await Self.createEvolvablePackage(
            in: outsideStore,
            controlURL: outsideControl,
            id: current.id,
            body: "External state must remain exact."
        )
        let outsideRevision = try #require(outside.revision)
        let outsideSource = try await outsideStore.resource(
            id: outside.id,
            relativePath: "SKILL.md"
        )
        let displacedControl = fixture.root.appendingPathComponent(
            "OriginalControl",
            isDirectory: true
        )
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot,
            replacementHooks: ResearchSkillMaintenanceReplacementHooks { point in
                if case .beforeReplacement = point {
                    try FileManager.default.moveItem(
                        at: fixture.control,
                        to: displacedControl
                    )
                    try FileManager.default.createSymbolicLink(
                        at: fixture.control,
                        withDestinationURL: outsideControl
                    )
                }
            }
        )
        let preparation = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise parent substitution resistance.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            )
        )
        let token = try #require(preparation.confirmationToken)

        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.apply(preparation, confirmationToken: token)
        }
        #expect(try await outsideStore.package(id: outside.id).revision == outsideRevision)
        #expect(try await outsideStore.resource(
            id: outside.id,
            relativePath: "SKILL.md"
        ) == outsideSource)
        let originalStore = ResearchSkillStore(controlURL: displacedControl)
        #expect(try await originalStore.package(id: current.id).revision == originalRevision)
        #expect(try FileManager.default.contentsOfDirectory(
            at: displacedControl.appendingPathComponent("skills", isDirectory: true),
            includingPropertiesForKeys: nil
        ).allSatisfy { !$0.lastPathComponent.hasPrefix(".replacing-") })
    }

    @Test("Maintenance applies the installed package dependency and resource rules")
    func fullInstalledPackageValidationPrecedesConfirmation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        _ = try await store.create(
            id: "cycle-peer",
            source: Self.routedMaintenanceSource(
                name: "Cycle Peer",
                role: "specialist",
                dependencies: [current.id]
            )
        )
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )

        let invalidProposals: [(String, ResearchSkillProposedPackage, String)] = [
            (
                "missing dependency",
                Self.maintenanceProposal(skillSource: Self.routedMaintenanceSource(
                    name: "Missing Dependency",
                    role: "specialist",
                    dependencies: ["missing-method"]
                )),
                "does not exist"
            ),
            (
                "dependency cycle",
                Self.maintenanceProposal(skillSource: Self.routedMaintenanceSource(
                    name: "Cycle Candidate",
                    role: "specialist",
                    dependencies: ["cycle-peer"]
                )),
                "cycle"
            ),
            (
                "undeclared citation style resource",
                Self.maintenanceProposal(
                    skillSource: Self.routedMaintenanceSource(
                        name: "Mismatched Citation Method",
                        role: "specialist",
                        dependencies: ["scholium-core-protocol"],
                        citationStyles: ["apa-7"],
                        citationStyleResources: ["chicago": "references/style.md"]
                    ),
                    resources: ["references/style.md": "# Style"]
                ),
                "not declared in citation_styles"
            ),
        ]

        for (label, proposal, expectedIssue) in invalidProposals {
            let preparation = try await maintenance.prepare(
                ResearchSkillMaintenanceRequest(
                    packageID: current.id,
                    expectedPackageRevision: originalRevision,
                    proposedPackage: proposal,
                    instruction: "Reject \(label) before confirmation.",
                    evaluationEvidence: Self.passingEvidence(
                        revision: proposal.packageRevision
                    )
                )
            )
            #expect(preparation.evaluation.structuralStatus == .failed)
            #expect(preparation.confirmationToken == nil)
            #expect(preparation.evaluation.validationIssues.contains {
                $0.localizedCaseInsensitiveContains(expectedIssue)
            })
        }

        let dependency = try await store.create(
            id: "temporary-dependency",
            source: Self.routedMaintenanceSource(
                name: "Temporary Dependency",
                role: "specialist",
                dependencies: ["scholium-core-protocol"]
            )
        )
        let validUntilApply = Self.maintenanceProposal(
            skillSource: Self.routedMaintenanceSource(
                name: "Apply Revalidation Candidate",
                role: "specialist",
                dependencies: [dependency.id]
            )
        )
        let prepared = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: validUntilApply,
                instruction: "Revalidate the dependency graph before snapshot and apply.",
                evaluationEvidence: Self.passingEvidence(
                    revision: validUntilApply.packageRevision
                )
            )
        )
        let token = try #require(prepared.confirmationToken)
        try await store.delete(
            id: dependency.id,
            expectedRevision: try #require(dependency.revision)
        )
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.apply(prepared, confirmationToken: token)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotRoot.path))
        #expect(try await store.package(id: current.id).revision == originalRevision)
    }

    @Test("Maintenance snapshots refuse a symbolic-link storage root")
    func maintenanceSnapshotRootBoundary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let outside = fixture.root.appendingPathComponent(
            "Outside Snapshots",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        let linkedRoot = fixture.root.appendingPathComponent(
            "Linked Snapshot Root",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: outside
        )
        let proposal = Self.proposal(body: "A change that must not follow the link.")
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: linkedRoot
        )
        let preparation = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise the snapshot trust boundary.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            )
        )
        let token = try #require(preparation.confirmationToken)
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.apply(preparation, confirmationToken: token)
        }

        #expect(try await store.package(id: current.id).revision == originalRevision)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test("Failed atomic replacement restores the package and preserves its durable snapshot")
    func atomicReplacementRollbackPreservesSnapshot() async throws {
        enum InjectedFailure: Error { case afterReplacement }

        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let proposal = Self.proposal(body: "A replacement that will fault.")
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot,
            replacementHooks: ResearchSkillMaintenanceReplacementHooks { point in
                if case .afterReplacement = point {
                    throw InjectedFailure.afterReplacement
                }
            }
        )
        let preparation = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise rollback.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            )
        )
        let token = try #require(preparation.confirmationToken)
        await #expect(throws: InjectedFailure.self) {
            _ = try await maintenance.apply(preparation, confirmationToken: token)
        }

        #expect(try await store.package(id: current.id).revision == originalRevision)
        let snapshots = try FileManager.default.contentsOfDirectory(
            at: fixture.snapshotRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        #expect(snapshots.count == 1)
    }

    @Test("A concurrent package edit wins over a prepared replacement")
    func concurrentMaintenanceEditIsNeverOverwritten() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let proposal = Self.proposal(body: "A replacement that must become stale.")
        let entryPoint = fixture.control
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(current.id, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let concurrentSource = Fixture.skillSource(
            body: "A concurrent researcher-authored change."
        )
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot,
            replacementHooks: ResearchSkillMaintenanceReplacementHooks { point in
                if case .beforeReplacement = point {
                    try Data(concurrentSource.utf8).write(to: entryPoint, options: .atomic)
                }
            }
        )
        let preparation = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise the package revision race.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            )
        )
        let token = try #require(preparation.confirmationToken)

        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.apply(preparation, confirmationToken: token)
        }
        #expect(try await store.resource(
            id: current.id,
            relativePath: "SKILL.md"
        ).contains("A concurrent researcher-authored change."))
        #expect(try await store.package(id: current.id).revision != proposal.packageRevision)
    }

    private static func createEvolvablePackage(
        in store: ResearchSkillStore,
        controlURL: URL,
        id: String = "evolving-method",
        body: String = "Original instructions."
    ) async throws -> ResearchSkillPackage {
        _ = try await store.create(id: id, source: Fixture.skillSource(body: body))
        let evals = controlURL.appendingPathComponent(
            "skills/\(id)/evals",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: evals,
            withIntermediateDirectories: false
        )
        try "# Cases\n\n- Preserve source fidelity.".write(
            to: evals.appendingPathComponent("cases.md"),
            atomically: true,
            encoding: .utf8
        )
        let references = controlURL.appendingPathComponent(
            "skills/\(id)/references",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: references,
            withIntermediateDirectories: false
        )
        return try await store.package(id: id)
    }

    private static func routedMaintenanceSource(
        name: String,
        role: String,
        dependencies: [String],
        citationStyles: [String] = [],
        citationStyleResources: [String: String] = [:],
        practiceResources: [String: String] = [:]
    ) -> String {
        var routing = [
            "  role: \(role)",
            "  supported_functions: [fidelity]",
            "  capabilities: []",
            "  citation_styles: [\(citationStyles.joined(separator: ", "))]",
        ]
        if !citationStyleResources.isEmpty {
            routing.append("  citation_style_resources:")
            routing.append(contentsOf: citationStyleResources.keys.sorted().map {
                "    \($0): \(citationStyleResources[$0] ?? "")"
            })
        }
        routing.append(contentsOf: [
            "  allow_evolution: true",
            "  supported_modes: [audit]",
            "  required_skills: [\(dependencies.joined(separator: ", "))]",
        ])
        if !practiceResources.isEmpty {
            routing.append("  practice_resources:")
            routing.append(contentsOf: practiceResources.keys.sorted().map {
                "    \($0): \(practiceResources[$0] ?? "")"
            })
        }
        return """
        ---
        name: \(name)
        description: A maintenance validation candidate.
        scholium:
        \(routing.joined(separator: "\n"))
        ---

        # \(name)

        Validate this package with `evals/cases.md`.
        """
    }

    private static func analyzeMethodSource(
        id: String,
        dependencies: [String]
    ) -> String {
        """
        ---
        name: \(id)
        description: A dependency-boundary fixture for Analyze.
        scholium:
          role: method
          supported_actions: [analyze]
          supported_functions: [develop]
          capabilities: []
          citation_styles: []
          allow_evolution: false
          supported_modes: [analyze]
          required_skills: [\(dependencies.joined(separator: ", "))]
        ---

        Exercise only the declared Analyze boundary.
        """
    }

    private static func analyzeWorkflowContract(
        selectedPractices: [ResearchPracticeSelection] = []
    ) -> ResearchWorkflowContract {
        let target = ResearchWorkflowObjectReference(
            kind: .note,
            identifier: "Analyses/Assembly Fixture.md"
        )
        return ResearchWorkflowContract(
            mode: .analyze,
            taskObject: "Analyze one source",
            purpose: "Prove exact primary Method assembly.",
            originalReadSet: [target],
            originalWriteSet: [],
            phases: [ResearchWorkflowPhaseContract(
                phase: 1,
                mode: .analyze,
                purpose: "Analyze without changing the research Note.",
                requiredSkillIDs: [],
                selectedPractices: selectedPractices,
                readSet: [target],
                writeSet: [],
                permission: .readOnly,
                permissionBasis: "",
                output: "Return one bounded analysis.",
                stopCondition: "Stop if exact Method identity changes.",
                durability: .handoff,
                handoff: ResearchWorkflowHandoff(
                    summary: "The analysis remains provisional.",
                    evidenceStatus: "One exact Method revision was required."
                )
            )]
        )
    }

    private static func analyzeSpecialistSource(
        id: String,
        dependencies: [String]
    ) -> String {
        """
        ---
        name: \(id)
        description: A specialist dependency-boundary fixture for Analyze.
        scholium:
          role: specialist
          supported_functions: [develop]
          capabilities: []
          citation_styles: []
          allow_evolution: false
          supported_modes: [analyze]
          required_skills: [\(dependencies.joined(separator: ", "))]
        ---

        Exercise only one bounded specialist contribution.
        """
    }

    private static func maintenanceProposal(
        skillSource: String,
        resources: [String: String] = [:]
    ) -> ResearchSkillProposedPackage {
        var files = [ResearchSkillMaintenanceFile(
            relativePath: "SKILL.md",
            source: skillSource
        )]
        files.append(ResearchSkillMaintenanceFile(
            relativePath: "evals/cases.md",
            source: "# Cases\n\n- Preserve source fidelity."
        ))
        files.append(contentsOf: resources.keys.sorted().map {
            ResearchSkillMaintenanceFile(
                relativePath: $0,
                source: resources[$0] ?? ""
            )
        })
        return ResearchSkillProposedPackage(files: files)
    }

    private static func proposal(body: String) -> ResearchSkillProposedPackage {
        ResearchSkillProposedPackage(files: [
            ResearchSkillMaintenanceFile(
                relativePath: "SKILL.md",
                source: Fixture.skillSource(body: body)
            ),
            ResearchSkillMaintenanceFile(
                relativePath: "evals/cases.md",
                source: "# Cases\n\n- Preserve source fidelity."
            ),
        ])
    }

    private static func passingEvidence(
        revision: DocumentFingerprint
    ) -> ResearchSkillMaintenanceExternalEvaluation {
        ResearchSkillMaintenanceExternalEvaluation(
            proposedPackageRevision: revision,
            evaluator: "External Research Agent",
            method: "Positive, boundary, and adversarial cases",
            status: .passed,
            cases: [ResearchSkillMaintenanceEvaluationCase(
                id: "source-fidelity-boundary",
                status: .passed,
                summary: "The proposed method preserved evidential layers in the evaluated cases."
            )]
        )
    }
}

private struct Fixture {
    let root: URL
    let control: URL
    let snapshotRoot: URL
    let workingMethodRecoveryRoot: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumFunctionSkills-\(UUID().uuidString)",
            isDirectory: true
        )
        control = root.appendingPathComponent("Works/.scholium", isDirectory: true)
        snapshotRoot = root.appendingPathComponent(
            "Application Support/Triptychs/Test/research-guidance/skill-snapshots",
            isDirectory: true
        )
        workingMethodRecoveryRoot = snapshotRoot
        try FileManager.default.createDirectory(
            at: control,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func workingMethodStore(
        hooks: ResearchWorkingMethodStoreHooks = .none,
        forceCopyFallback: Bool = false
    ) -> ResearchSkillStore {
        ResearchSkillStore(
            controlURL: control,
            workingMethodRecoveryStore: ResearchWorkingMethodRecoveryStore(
                snapshotRootURL: workingMethodRecoveryRoot,
                forceCopyFallback: forceCopyFallback
            ),
            workingMethodHooks: hooks
        )
    }

    func createEvolvablePackage(
        in store: ResearchSkillStore,
        id: String = "evolving-method"
    ) async throws -> ResearchSkillPackage {
        _ = try await store.create(
            id: id,
            source: Self.skillSource(body: "Original instructions.")
        )
        let evals = control.appendingPathComponent(
            "skills/\(id)/evals",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: evals,
            withIntermediateDirectories: false
        )
        try "# Cases\n\n- Preserve source fidelity.".write(
            to: evals.appendingPathComponent("cases.md"),
            atomically: true,
            encoding: .utf8
        )
        let references = control.appendingPathComponent(
            "skills/\(id)/references",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: references,
            withIntermediateDirectories: false
        )
        return try await store.package(id: id)
    }

    static func skillSource(body: String) -> String {
        """
        ---
        name: Evolving Method
        description: A bounded researcher-owned method used by maintenance tests.
        scholium:
          role: specialist
          supported_functions: [fidelity]
          capabilities: []
          citation_styles: []
          allow_evolution: true
          supported_modes: [audit]
          required_skills: [scholium-core-protocol]
        ---

        # Evolving Method

        \(body)

        Evaluate with `evals/cases.md` before applying a whole-package replacement.
        """
    }
}
