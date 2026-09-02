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
        #expect(compact.contains(#"name:"ScholiumApp",dependencies:["ScholiumContracts","ScholiumApplication",]"#))
        #expect(compact.contains(#"name:"ScholiumCLI",dependencies:["ScholiumContracts","ScholiumApplication","ScholiumCLIUpdate"]"#))
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
            "Scholium/Services/MCPAppBridgeRequestRouter.swift",
            "Scholium/Services/ScholiumAppBridgeRequestRouter.swift",
            "Scholium/Services/WindowSession.swift",
            "Scholium/Views/AgentIntegrationSettingsView.swift",
            "ScholiumCLI/CLIContext.swift",
            "ScholiumCLI/MCPCommandHandler.swift",
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
            "Scholium/Views/Note/ScholiumDocumentWebResources.swift",
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
            ("portable control store", #"\bTriptychControlStore\s*\("#),
            ("research skill store", #"\bResearchSkillTransactionCoordinator\s*\("#),
            ("human review store", #"\bHumanReviewStore\s*\("#),
            ("Dialogue store", #"\bDialogueStore\s*\("#),
            ("Critique registry", #"\bCritiqueRegistry\s*\("#),
            ("transaction recovery store", #"\bTriptychMutationRecoveryStore\s*\("#),
            ("identity recovery coordinator", #"\bNoteIdentityRecoveryCoordinator\s*\("#),
            ("move coordinator", #"\bTriptychMoveCoordinator\s*\("#),
            ("system-Trash coordinator", #"\bNoteSystemTrashDeletionCoordinator\s*\("#),
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
            "Scholium/Views/Metadata/MetadataEditorView.swift",
            "Scholium/Views/Note/NoteFileOperationView.swift",
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
