import Foundation
import Testing

@Suite("Modular monolith boundaries")
struct ArchitectureBoundaryTests {
    @Test("Package graph prevents frontend access to Core")
    func packageGraphIsCompilerEnforced() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let compact = package.filter { !$0.isWhitespace }

        #expect(package.contains(#".library(name: "ScholiumContracts""#))
        #expect(!package.contains(#".library(name: "ScholiumCore""#))
        #expect(compact.contains(#"name:"ScholiumApplication",dependencies:["ScholiumContracts","ScholiumCore"]"#))
        #expect(compact.contains(#"name:"ScholiumResearchRecordsFeature",dependencies:["ScholiumContracts"]"#))
        #expect(compact.contains(#"name:"ScholiumApp",dependencies:["ScholiumContracts","ScholiumApplication","ScholiumResearchRecordsFeature",]"#))
        #expect(compact.contains(#"name:"ScholiumCLI",dependencies:["ScholiumContracts","ScholiumApplication"]"#))
    }

    @Test("Shared machine-local storage has one Core primitive owner")
    func secureRecordDirectoryOwnershipBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coreRoot = repositoryRoot.appendingPathComponent("ScholiumCore")
        let records = try String(
            contentsOf: coreRoot.appendingPathComponent("ResearchRecordV1Stores.swift"),
            encoding: .utf8
        )
        let primitive = try String(
            contentsOf: coreRoot.appendingPathComponent("SecureRecordDirectory.swift"),
            encoding: .utf8
        )

        for definition in [
            "final class AdvisoryFileLock",
            "enum SecureRecordDirectoryError",
            "struct SecureRecordDirectory",
        ] {
            #expect(!records.contains(definition))
            #expect(primitive.contains(definition))
        }
        #expect(!primitive.contains("ResearchRecordStoreV1Error"))

        for consumer in [
            "ResearchRecordV1Stores.swift",
            "ResearchRecoveryPolicyStore.swift",
            "PrewriteRecoveryLedger.swift",
        ] {
            let source = try String(
                contentsOf: coreRoot.appendingPathComponent(consumer),
                encoding: .utf8
            )
            #expect(source.contains("SecureRecordDirectory"))
        }
    }

    @Test("Core and Application imports remain confined to composition roots")
    func importBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let roots = ["Scholium", "ScholiumCLI"]
        var coreImports: [String] = []
        var applicationImports: [String] = []
        let allowedApplicationImports: Set<String> = [
            "Scholium/App/ApplicationBootstrapController.swift",
            "Scholium/App/ScholiumApp.swift",
            "Scholium/App/Window/WindowWorkspaceController.swift",
            "Scholium/Services/WindowSession.swift",
            "ScholiumCLI/CLIContext.swift",
        ]
        for relativeRoot in roots {
            for file in try swiftFiles(beneath: repositoryRoot.appendingPathComponent(relativeRoot)) {
                let source = try String(contentsOf: file, encoding: .utf8)
                let relativePath = file.path.replacingOccurrences(
                    of: repositoryRoot.path + "/",
                    with: ""
                )
                let imports = source
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if imports.contains("import ScholiumCore") { coreImports.append(relativePath) }
                if imports.contains("import ScholiumApplication"),
                   !allowedApplicationImports.contains(relativePath) {
                    applicationImports.append(relativePath)
                }
            }
        }
        for relativeRoot in ["Tests/ScholiumAppTests", "Tests/ScholiumApplicationTests"] {
            for file in try swiftFiles(beneath: repositoryRoot.appendingPathComponent(relativeRoot)) {
                let source = try String(contentsOf: file, encoding: .utf8)
                let imports = source
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if imports.contains("import ScholiumCore") {
                    coreImports.append(file.path.replacingOccurrences(
                        of: repositoryRoot.path + "/",
                        with: ""
                    ))
                }
            }
        }
        #expect(coreImports.isEmpty, Comment(rawValue: coreImports.joined(separator: "\n")))
        #expect(applicationImports.isEmpty, Comment(rawValue: applicationImports.joined(separator: "\n")))
    }

    @Test("WorkspaceStore completes event readiness before publishing capability activation")
    func workspaceActivationBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Services/WindowSession.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("private func workspaceHandle(\n        id: UUID,"))
        #expect(source.contains("openingVault: WorkspaceVaultSlot? = nil"))
        #expect(source.contains("openingVault: openingVault"))
        #expect(source.contains("private func configureTriptych("))
        #expect(!source.contains("func reloadTriptychCapabilities("))

        let installStart = try #require(source.range(of: "private func install("))
        let installEnd = try #require(source.range(
            of: "private func capabilities(from handle:",
            range: installStart.upperBound..<source.endIndex
        ))
        let install = String(source[installStart.lowerBound..<installEnd.lowerBound])
        let subscription = try #require(install.range(of: "let stream = await handle.events.events()"))
        let retainedTask = try #require(install.range(
            of: "eventTasks[handle.id] = Task",
            range: subscription.upperBound..<install.endIndex
        ))
        let publication = try #require(install.range(
            of: "workspaceActivations[handle.id] = activation",
            range: retainedTask.upperBound..<install.endIndex
        ))
        #expect(publication.lowerBound > retainedTask.lowerBound)
    }

    @Test("Frontend authoritative I/O is confined to delivery allowlists")
    func frontendIOWall() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = repositoryRoot.appendingPathComponent("Scholium")
        let allowedFiles: Set<String> = [
            "Scholium/Services/WindowSession.swift",
            "Scholium/Services/PerformanceProbe.swift",
            "Scholium/Localization/WebKitInterfaceLocalization.swift",
            "Scholium/Views/Note/MarkdownEditorWebView.swift",
            "Scholium/Styling/ScholiumWebFonts.swift",
            "Scholium/Styling/ScholiumWebFontResources.swift",
            "Scholium/Styling/ScholiumCalloutStyles.swift",
            "Scholium/Styling/ScholiumTableStyles.swift",
            "Scholium/Styling/ScholiumFootnoteStyles.swift",
            "Scholium/Styling/ScholiumMathAssets.swift",
            "Scholium/Styling/ScholiumMermaidAssets.swift",
            "Scholium/Styling/ScholiumPreviewStyles.swift",
        ]
        let prohibited = ["URLSession", "SQLite", "FSEventStream", "Data(contentsOf:", "String(contentsOf:", "FileManager"]
        let verificationScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Tools/Scripts/verify.sh"),
            encoding: .utf8
        )
        for relativePath in allowedFiles {
            let deliveryRelativePath = relativePath.dropFirst("Scholium/".count)
            #expect(
                verificationScript.contains("--glob '!**/\(deliveryRelativePath)'"),
                "verify.sh is missing the frontend I/O allowlist entry for \(relativePath)"
            )
        }
        var violations: [String] = []
        for file in try swiftFiles(beneath: appRoot) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = file.path.replacingOccurrences(
                of: repositoryRoot.path + "/",
                with: ""
            )
            guard !allowedFiles.contains(relativePath) else { continue }
            for token in prohibited where source.contains(token) {
                violations.append("\(relativePath): \(token)")
            }
        }
        #expect(violations.isEmpty, Comment(rawValue: violations.sorted().joined(separator: "\n")))
    }

    @Test("Delivery targets neither construct nor borrow Application-owned services")
    func deliveryTargetsDoNotConstructOrBorrowApplicationServices() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let deliveryRoots = [
            repositoryRoot.appendingPathComponent("Scholium", isDirectory: true),
            repositoryRoot.appendingPathComponent("ScholiumCLI", isDirectory: true),
        ]
        let prohibitedConstructions: [(label: String, pattern: String)] = [
            ("vault repository", #"\bVaultRepository\s*\("#),
            ("Triptych Search index", #"\bTriptychSearchIndex\s*\.\s*openRecovering\s*\("#),
            ("legacy vault runtime", #"\bVaultService\s*\("#),
            ("legacy search runtime", #"\bSearchEngine\s*\("#),
            ("workspace registry", #"\bWorkspaceRegistry\s*\("#),
            ("vault identity registry", #"\bVaultIdentityRegistry\s*\("#),
            ("portable-control registry", #"\bPortableControlAccessRegistry\s*\("#),
            ("portable control store", #"\bTriptychControlStore\s*\("#),
            ("research skill store", #"\bResearchSkillTransactionCoordinator\s*\("#),
            ("human review store", #"\bHumanReviewStore\s*\("#),
            ("Dialogue store", #"\bDialogueStore\s*\("#),
            ("Critique registry", #"\bCritiqueRegistry\s*\("#),
            ("checkpoint store", #"\bTriptychCheckpointStore\s*\("#),
            ("transaction recovery store", #"\bTriptychMutationRecoveryStore\s*\("#),
            ("identity recovery coordinator", #"\bNoteIdentityRecoveryCoordinator\s*\("#),
            ("move coordinator", #"\bTriptychMoveCoordinator\s*\("#),
            ("permanent-deletion coordinator", #"\bNotePermanentDeletionCoordinator\s*\("#),
            ("FSEvents watcher", #"\bFSEventStreamCreate\s*\("#),
            ("Zotero MCP server", #"\bZoteroMCPServer\s*\("#),
            ("Triptych storage path", "appendingPathComponent\\s*\\(\\s*\\\"Triptychs\\\""),
        ]
        let prohibitedAuthorityReferences: [(label: String, pattern: String)] = [
            ("compatibility SPI", #"@_spi\s*\("#),
            ("compatibility service bundle", #"\bWorkspaceCompatibilityServices\b"#),
            ("legacy shared Triptych runtime", #"\bSharedTriptychRuntime\b"#),
            ("legacy shared vault runtime", #"\bSharedVaultRuntime\b"#),
            ("vault repository authority", #"\bVaultRepository\b"#),
            ("Triptych Search index authority", #"\bTriptychSearchIndex\b"#),
            ("portable control-store authority", #"\bTriptychControlStore\b"#),
            ("research-skill store authority", #"\bResearchSkillTransactionCoordinator\b"#),
            ("legacy Review archive authority", #"\bHumanReviewStore\b"#),
            ("Dialogue store authority", #"\bDialogueStore\b"#),
            ("Critique registry authority", #"\bCritiqueRegistry\b"#),
            ("checkpoint store authority", #"\bTriptychCheckpointStore\b"#),
            ("transaction-recovery store authority", #"\bTriptychMutationRecoveryStore\b"#),
            ("identity-recovery authority", #"\bNoteIdentityRecoveryCoordinator\b"#),
            ("Zotero transport locator", #"\bZoteroMCPTransportLocator\b"#),
        ]

        var violations: [String] = []
        for root in deliveryRoots {
            for file in try swiftFiles(beneath: root) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for construction in prohibitedConstructions {
                    let expression = try NSRegularExpression(pattern: construction.pattern)
                    let range = NSRange(source.startIndex..<source.endIndex, in: source)
                    guard let match = expression.firstMatch(in: source, range: range),
                          let matchRange = Range(match.range, in: source) else {
                        continue
                    }
                    let line = source[..<matchRange.lowerBound].reduce(into: 1) { count, character in
                        if character == "\n" { count += 1 }
                    }
                    let relativePath = file.path.replacingOccurrences(
                        of: repositoryRoot.path + "/",
                        with: ""
                    )
                    violations.append("\(relativePath):\(line) constructs \(construction.label)")
                }
                for reference in prohibitedAuthorityReferences {
                    let expression = try NSRegularExpression(pattern: reference.pattern)
                    let range = NSRange(source.startIndex..<source.endIndex, in: source)
                    guard let match = expression.firstMatch(in: source, range: range),
                          let matchRange = Range(match.range, in: source) else {
                        continue
                    }
                    let line = source[..<matchRange.lowerBound].reduce(into: 1) { count, character in
                        if character == "\n" { count += 1 }
                    }
                    let relativePath = file.path.replacingOccurrences(
                        of: repositoryRoot.path + "/",
                        with: ""
                    )
                    violations.append("\(relativePath):\(line) borrows \(reference.label)")
                }
            }
        }

        #expect(
            violations.isEmpty,
            Comment(rawValue: "Application ownership violations:\n" + violations.sorted().joined(separator: "\n"))
        )
    }

    @Test("Application boundary exposes only canonical snapshot and event names")
    func applicationCompatibilityAliasesAreRemoved() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let applicationRoot = repositoryRoot.appendingPathComponent(
            "ScholiumApplication",
            isDirectory: true
        )
        let source = try swiftFiles(beneath: applicationRoot).map {
            try String(contentsOf: $0, encoding: .utf8)
        }.joined(separator: "\n")

        #expect(!source.contains("typealias WorkspaceDocumentSnapshot"))
        #expect(!source.contains("var eventSource: WorkspaceEventSource"))
    }

    @Test("Workspace source and refresh exclusion has one cancellation-aware owner")
    func workspaceSourceOperationGateBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let handle = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumApplication/WorkspaceHandle.swift"
            ),
            encoding: .utf8
        )
        let gate = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumApplication/WorkspaceSourceOperationGate.swift"
            ),
            encoding: .utf8
        )

        #expect(handle.contains(
            "var sourceOperationGate = WorkspaceSourceOperationGate()"
        ))
        #expect(handle.contains(
            "public actor WorkspaceHandle: WorkspaceSourceOperationGateOwner"
        ))
        for retiredOwner in [
            "private var activeSourceMutationID",
            "private var refreshCycleIsActive",
            "private var sourceGateWaiters",
            "func waitForSourceGateChange",
            "func signalSourceGateChange",
        ] {
            #expect(
                !handle.contains(retiredOwner),
                Comment(rawValue: "WorkspaceHandle regained \(retiredOwner)")
            )
        }
        #expect(gate.contains("protocol WorkspaceSourceOperationGateOwner: Actor"))
        #expect(gate.contains("withTaskCancellationHandler"))
        #expect(gate.contains("try Task.checkCancellation()"))
    }

    @Test("Research execution lifecycle has one Workspace coordinator")
    func researchFunctionCoordinatorBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let applicationRoot = repositoryRoot.appendingPathComponent(
            "ScholiumApplication",
            isDirectory: true
        )
        let coordinator = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "ResearchFunctionCoordinator.swift"
            ),
            encoding: .utf8
        )
        let preparation = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "ResearchFunctionPreparation.swift"
            ),
            encoding: .utf8
        )
        let delivery = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "ResearchFunctionDelivery.swift"
            ),
            encoding: .utf8
        )
        let evidence = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "ResearchFunctionEvidence.swift"
            ),
            encoding: .utf8
        )
        let guidance = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "WorkspaceResearchGuidanceOperations.swift"
            ),
            encoding: .utf8
        )
        let completion = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "ResearchFunctionCompletion.swift"
            ),
            encoding: .utf8
        )
        let handle = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "WorkspaceHandle.swift"
            ),
            encoding: .utf8
        )
        let operations = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "Operations.swift"
            ),
            encoding: .utf8
        )
        let actionResolver = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "ResearchActionResolver.swift"
            ),
            encoding: .utf8
        )
        let boundedWrites = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "ResearchBoundedWriteOperations.swift"
            ),
            encoding: .utf8
        )
        let agentResults = try String(
            contentsOf: applicationRoot.appendingPathComponent(
                "ResearchAgentResultOperations.swift"
            ),
            encoding: .utf8
        )

        #expect(coordinator.contains(
            "final class ResearchFunctionCoordinator: Sendable"
        ))
        #expect(coordinator.contains(
            "protocol ResearchFunctionCoordinatorHost: Actor"
        ))
        #expect(coordinator.contains("host: isolated Host"))
        #expect(coordinator.contains("func cancelProtectedFunction"))
        #expect(coordinator.contains("func finishProtectedDiscussion"))
        #expect(!coordinator.contains("WorkspaceServices"))
        #expect(!completion.contains("WorkspaceServices"))
        #expect(!preparation.contains("WorkspaceServices"))
        #expect(!delivery.contains("WorkspaceServices"))
        #expect(!evidence.contains("WorkspaceServices"))
        #expect(!preparation.contains("extension WorkspaceHandle"))
        #expect(!delivery.contains("extension WorkspaceHandle"))
        #expect(!evidence.contains("extension WorkspaceHandle"))
        #expect(!coordinator.contains("actor ResearchFunctionCoordinator"))
        #expect(completion.contains("func completeProtectedFunction"))
        #expect(completion.contains("func ensurePortableResearchRecord"))
        #expect(completion.contains("func validateResearchContinuation"))
        #expect(!completion.contains("func confirmWriteActivity"))
        #expect(completion.contains("func validateSnapshotResearchSourceAccess"))
        #expect(preparation.contains("func researchFunctionAvailability"))
        #expect(preparation.contains("func prepareResearchFunction"))
        #expect(preparation.contains("func prepareAutomaticFidelity"))
        #expect(preparation.contains("func researchFunctionRun"))
        #expect(preparation.contains("host: isolated Host"))
        #expect(delivery.contains("func deliveryInstructions"))
        #expect(delivery.contains("func attachingAgentActions"))
        #expect(delivery.contains("host: isolated Host"))
        #expect(evidence.contains("func requiredResearchSourceAccess"))
        #expect(evidence.contains("func researchFunctionTargetRepairReason"))
        #expect(evidence.contains("host: isolated Host"))
        #expect(handle.contains(
            "let researchFunctionCoordinator: ResearchFunctionCoordinator"
        ))
        #expect(handle.contains(
            "localExecutionStore: services.localResearchExecutionStore"
        ))
        #expect(handle.contains(
            "critiqueRegistry: services.critiqueRegistry"
        ))
        #expect(operations.contains(
            "functionCoordinator.cancelProtectedFunction("
        ))
        #expect(operations.contains("functionCoordinator.cancelAction("))
        #expect(operations.contains(
            "functionCoordinator.completeProtectedFunction("
        ))
        #expect(operations.contains(
            "functionCoordinator.prepareResearchFunction("
        ))
        #expect(operations.contains(
            "functionCoordinator.researchFunctionAvailability("
        ))
        #expect(!actionResolver.contains(".completeProtectedFunction("))
        #expect(agentResults.contains("func submitResearchAgentResult("))
        #expect(agentResults.contains(".completeProtectedFunction("))
        #expect(actionResolver.contains(
            "researchFunctionCoordinator.prepareResearchFunction("
        ))
        #expect(boundedWrites.contains("func extendResearchWriteSet("))
        #expect(boundedWrites.contains("func writeResearchDocument("))
        #expect(!boundedWrites.contains("activeResearchActivityKeys["))
        #expect(!boundedWrites.contains("raw_session_secret"))
        for retiredPath in [
            "func completeResearchFunction",
            "func cancelResearchFunction",
            "func finishResearchDiscussion",
            "func storedFunctionRecord",
            "func persistFunctionCompletion",
            "recoverableResearchRefreshWarning",
            "func ensurePortableResearchRecord",
            "func validateResearchContinuation",
            "func confirmWriteActivity",
        ] {
            #expect(
                !guidance.contains(retiredPath),
                Comment(rawValue: "WorkspaceHandle regained \(retiredPath)")
            )
        }
        for retiredPreparationOwner in [
            "func researchFunctionAvailability",
            "func researchFunctionMaterialCandidates",
            "func prepareResearchFunction",
            "func prepareAutomaticFidelity",
            "func researchFunctionRun",
            "func attachingAgentActions",
            "func researchFunctionTargetRepairReason",
        ] {
            #expect(
                !guidance.contains(retiredPreparationOwner),
                Comment(rawValue:
                    "Workspace guidance regained \(retiredPreparationOwner)"
                )
            )
        }
        #expect(guidance.contains("func researchSourceAccessStatus"))
        #expect(guidance.contains("func researchCitationMethodStatus"))
        #expect(!FileManager.default.fileExists(atPath: applicationRoot
            .appendingPathComponent("WorkspaceResearchFunctionOperations.swift")
            .path))
        #expect(!actionResolver.contains("func cancelResearchAction"))
    }

    @Test("App retains shared documents without mutable note or YAML projections")
    func appProjectionAliasesAreRemoved() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = repositoryRoot.appendingPathComponent("Scholium", isDirectory: true)
        let source = try swiftFiles(beneath: appRoot).map {
            try String(contentsOf: $0, encoding: .utf8)
        }.joined(separator: "\n")

        let mutableNote = try NSRegularExpression(pattern: #"\bstruct\s+Note\b"#)
        let duplicateYAML = try NSRegularExpression(pattern: #"\benum\s+FrontmatterValue\b"#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)

        #expect(mutableNote.firstMatch(in: source, range: range) == nil)
        #expect(duplicateYAML.firstMatch(in: source, range: range) == nil)
        #expect(!source.contains("WorkspaceVaultProjectionService"))
        #expect(source.contains("case workspace(WorkspaceNoteSnapshot)"))
        #expect(!source.localizedCaseInsensitiveContains("unclassified"))
    }

    @Test("Document and property leaves receive narrow values and actions")
    func documentPropertyLeavesDoNotReachForWindowModel() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Scholium/Views/Frontmatter/FrontmatterEditorView.swift",
            "Scholium/Views/Note/NoteLifecycleView.swift",
            "Scholium/Views/Note/TransactionRecoveryView.swift",
            "Scholium/Views/Note/NoteContentView.swift",
        ]

        for relativePath in relativePaths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(
                !source.contains("@EnvironmentObject"),
                Comment(rawValue: "\(relativePath) must receive explicit feature dependencies")
            )
            #expect(
                !source.contains("WindowModel"),
                Comment(rawValue: "\(relativePath) must not depend on the complete window shell")
            )
        }
    }

    @Test("Markdown editor composes one typed host from bounded native and web components")
    func markdownEditorBridgeBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editor = try String(
            contentsOf: repositoryRoot.appendingPathComponent("WebEditor/editor.ts"),
            encoding: .utf8
        )
        let native = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorWebView.swift"
            ),
            encoding: .utf8
        )
        let session = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorSession.swift"
            ),
            encoding: .utf8
        )
        let bridge = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorBridgeAdapter.swift"
            ),
            encoding: .utf8
        )
        let testing = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorSessionTesting.swift"
            ),
            encoding: .utf8
        )
        let testingInteractions = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/Note/MarkdownEditorSessionTestingInteractions.swift"
            ),
            encoding: .utf8
        )

        #expect(editor.contains("webkitWindow.scholiumEditor = {"))
        #expect(editor.contains("dispatch: dispatchEditorRequest,"))
        #expect(editor.contains("resolveLinkCompletionQuery,"))
        #expect(!editor.contains("bridgeVersion"))
        #expect(!editor.contains("searchKeymap"))
        #expect(!editor.contains("indentWithTab"))
        #expect(!editor.contains("aria-valuetext"))
        #expect(!editor.contains("calloutRoles"))
        #expect(native.contains("callAsyncJavaScript"))
        #expect(!native.contains("evaluateJavaScript"))
        #expect(session.contains("final class MarkdownEditorSession"))
        #expect(!native.contains("final class MarkdownEditorSession"))
        #expect(bridge.contains("final class WKWebViewMarkdownEditorBridgeDispatcher"))
        #expect(bridge.contains("callAsyncJavaScript"))
        #expect(testing.hasPrefix("#if DEBUG"))
        #expect(testingInteractions.hasPrefix("#if DEBUG"))
        #expect(!session.contains("TestingPresentationSnapshot"))
        for module in [
            "protocol.ts", "projection.ts", "semantic-projection.ts", "transformations.ts", "tables.ts",
            "table-presentation.ts",
            "interaction.ts", "clipboard.ts", "state.ts", "accessibility.ts", "bootstrap.ts", "performance.ts",
            "selection-actions.ts", "live-selection.ts", "live-projection-index.ts",
            "source-direction.ts", "preview-popover.ts", "scroll-coordinator.ts",
        ] {
            #expect(
                FileManager.default.fileExists(
                    atPath: repositoryRoot.appendingPathComponent("WebEditor/\(module)").path
                ),
                Comment(rawValue: "Missing editor module: \(module)")
            )
        }
        #expect(editor.contains("createSelectionActionsController"))
        #expect(editor.contains("createPreviewPopoverController"))
        #expect(editor.contains("createEditorScrollCoordinator"))
        #expect(!editor.contains(#"document.createElement("aside")"#))
        #expect(!editor.contains(#"scrollDOM.addEventListener("scroll""#))
    }

    @Test("Large settings and regression surfaces stay organized by responsibility")
    func largeSourceFilesRemainResponsibilitySplit() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for fileName in [
            "ResearchMethodsSettingsView.swift",
            "ProfilesPracticesSettingsView.swift",
            "ResearchPermissionSettingsView.swift",
            "ResearchSourcesSettingsView.swift",
            "ResearchRecoverySettingsView.swift",
        ] {
            #expect(FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent(
                    "Scholium/Views/\(fileName)"
                ).path
            ))
        }
        let guidanceRoot = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scholium/Views/ResearchGuidanceSettingsView.swift"
            ),
            encoding: .utf8
        )
        #expect(guidanceRoot.contains("struct ResearchGuidanceSettingsView"))
        #expect(!guidanceRoot.contains("private struct WorkingMethodEditorContext"))
        #expect(!guidanceRoot.contains("private struct ResearchActionProfileEditorView"))

        for fileName in [
            "ResearchFunctionSourceAccessTests.swift",
            "ResearchFunctionDiscussionTests.swift",
            "ResearchFunctionPreparationTests.swift",
            "ResearchFunctionActionRecordTests.swift",
            "ResearchFunctionContinuationTests.swift",
        ] {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "Tests/ScholiumApplicationTests/\(fileName)"
                ),
                encoding: .utf8
            )
            #expect(source.contains("extension ResearchFunctionOperationsTests"))
        }

        let uiTestFiles = [
            "ScholiumUITests+WorkspaceResearch.swift",
            "ScholiumUITests+PresentationRecords.swift",
            "ScholiumUITests+WindowsLifecycle.swift",
            "ScholiumUITests+EditorCoordination.swift",
            "ScholiumUITests+Support.swift",
            "ScholiumPerformanceUITests.swift",
            "ScholiumUpgradeSafetyUITests.swift",
        ]
        let uiProject = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "ScholiumUITests.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        for fileName in uiTestFiles {
            #expect(
                uiProject.contains(fileName),
                Comment(rawValue: "UI test project does not compile \(fileName)")
            )
        }
        let uiRoot = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "UITests/ScholiumUITests.swift"
            ),
            encoding: .utf8
        )
        #expect(uiRoot.contains("final class ScholiumUITests: XCTestCase"))
        #expect(uiRoot.contains("override func setUp() async throws"))
        #expect(!uiRoot.contains("func testCanonicalAcceptanceJourney"))
    }

    @Test("Literature recommendations have one Record owner and a derived window projection")
    func literatureRecommendationOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "ScholiumContracts/ResearchLiteratureRecommendationContracts.swift",
            "ScholiumContracts/PortableResearchRecordContracts.swift",
            "ScholiumResearchRecordsFeature/ResearchRecordBrowserModel.swift",
            "ScholiumResearchRecordsFeature/ResearchRecordsRoute.swift",
            "Scholium/App/Window/ResearchRecordsWindowCoordinator.swift",
            "Scholium/Views/ResearchRecord/ResearchRecordBrowserView.swift",
            "Scholium/App/ScholiumApp.swift",
            "Package.swift",
        ]
        let source = try paths.map {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent($0),
                encoding: .utf8
            )
        }.joined(separator: "\n")

        #expect(source.contains("ResearchLiteratureRecommendationSubmission"))
        #expect(source.contains("literatureRecommendations"))
        #expect(source.contains("ResearchLiteratureRecommendationDerivedIndex"))
        #expect(source.contains("ResearchRecordsWindowRequest"))
        #expect(source.contains("name: \"ScholiumResearchRecordsFeature\""))
        #expect(source.contains("triptychID"))
        #expect(source.contains("for: UUID.self"))
        #expect(source.contains("WorkspaceStore"))
        #expect(source.contains(".sourceLocators.enumerated()"))
        #expect(source.contains("id: \\.offset"))
        #expect(source.contains("if let title = recommendation.title,"))
        #expect(source.contains("title != recommendation.rawCitation"))
        #expect(source.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(!source.contains("struct ResearchRecommendation {"))
    }

    private func swiftFiles(beneath root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return try enumerator.compactMap { value -> URL? in
            guard let url = value as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                return nil
            }
            return url
        }
    }
}
