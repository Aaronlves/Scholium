import ScholiumContracts
import AppKit
import Foundation
import Testing
@testable import ScholiumApp

@Suite("Frontend architecture")
@MainActor
struct FrontendArchitectureTests {
    @Test("A window presents at most one sheet route")
    func presentationRouteExclusivity() {
        let router = WindowPresentationRouter()

        router.present(.quickOpen)
        #expect(router.sheet?.id == "quick-open")

        router.present(.frontmatter(path: "Topics/Agency.md"))
        #expect(router.sheet?.id == "frontmatter:Topics/Agency.md")
        router.dismissSheet(if: "quick-open")
        #expect(router.sheet?.id == "frontmatter:Topics/Agency.md")

        router.dismissSheet(if: "frontmatter:Topics/Agency.md")
        #expect(router.sheet == nil)

        router.fileImport = .markdown
        router.alert = .actionFailure(message: "Fixture failure")
        #expect(router.fileImport == .markdown)
        #expect(router.alert?.message == "Fixture failure")
        router.dismissAll()
        #expect(router.fileImport == nil)
        #expect(router.alert == nil)
    }

    @Test("Root setup and workspace setup sheet are mutually exclusive")
    func workspaceSetupPresentationExclusivity() {
        let router = WindowPresentationRouter()

        router.setWorkspaceSetupPresented(true, rootSetupOwnsPresentation: true)
        #expect(router.sheet == nil)

        router.setWorkspaceSetupPresented(true, rootSetupOwnsPresentation: false)
        #expect(router.sheet?.id == "workspace-setup")

        router.setWorkspaceSetupPresented(false, rootSetupOwnsPresentation: false)
        #expect(router.sheet == nil)
    }

    @Test("Independent windows do not share presentation or document sessions")
    func windowIsolation() {
        let firstRouter = WindowPresentationRouter()
        let secondRouter = WindowPresentationRouter()
        firstRouter.present(.quickOpen)
        #expect(secondRouter.sheet == nil)

        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let firstStore = DocumentSessionStore()
        let secondStore = DocumentSessionStore()
        let first = firstStore.session(for: key)
        let retained = firstStore.session(for: key)
        let second = secondStore.session(for: key)

        #expect(first === retained)
        #expect(first !== second)
        first.editingSource = "window one"
        #expect(second.editingSource.isEmpty)
    }

    @Test("Document identity is stable across path and title changes")
    func documentSessionIdentity() {
        let store = DocumentSessionStore()
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let original = store.session(for: key)
        original.presentationMode = .source
        original.editingSource = "exact markdown bytes\n"

        let afterProjectionChange = store.session(for: key)
        #expect(afterProjectionChange === original)
        #expect(afterProjectionChange.presentationMode == .source)
        #expect(afterProjectionChange.editingSource == "exact markdown bytes\n")

        let conflict = DocumentConflictSnapshot(
            relativePath: "Renamed/Note.md",
            editorSource: "local",
            diskSource: "external",
            baseRevision: DocumentFingerprint(content: "base")
        )
        original.conflict = conflict
        original.editError = "This Note Changed on Disk"
        #expect(store.session(for: key).conflict == conflict)
        #expect(store.session(for: key).editError == "This Note Changed on Disk")
    }

    @Test("Document sessions retain scheduled work across view reconstruction")
    func documentSessionRetainsScheduledWork() async {
        let store = DocumentSessionStore()
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let session = store.session(for: key)

        await confirmation("retained autosave completed") { completed in
            session.autosaveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { return }
                completed()
            }

            let reconstructed = store.session(for: key)
            #expect(reconstructed === session)
            await session.autosaveTask?.value
        }
    }

    @Test("Search rejects stale completion")
    func searchStaleResultRejection() {
        let controller = DiscoveryController()
        let first = SearchWorkspaceState(query: "first", scope: .triptych)
        let second = SearchWorkspaceState(query: "second", scope: .thisNote)
        let firstRequest = controller.beginSearch(first)
        let secondRequest = controller.beginSearch(second)

        controller.failSearch("stale", for: firstRequest)
        #expect(controller.search.errorMessage == nil)
        #expect(controller.search.criteria.query == "second")

        controller.failSearch("current", for: secondRequest)
        #expect(controller.search.errorMessage == "current")
    }

    @Test("Research context enforces one trailing context owner")
    func researchContextExclusivity() {
        let controller = ResearchController()
        controller.showResearchInspector(true)
        #expect(controller.inspector.showsResearchInspector)
        #expect(!controller.inspector.showsNoteHistory)

        controller.showNoteHistory(true)
        #expect(controller.inspector.showsNoteHistory)
        #expect(!controller.inspector.showsResearchInspector)
    }

    @Test("Research Function presentation is target-locked and resettable")
    func researchFunctionStateTransitions() {
        let controller = ResearchController()
        let vaultID = UUID()
        let target = ResearchFunctionTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: "Topics/Agency.md"
            ),
            role: .topic,
            fingerprint: DocumentFingerprint(content: "# Agency\n"),
            title: "Agency"
        )
        let firstPresentation = UUID()
        controller.functions.begin(
            target: target,
            function: .dialogue,
            selection: nil,
            presentationID: firstPresentation
        )
        #expect(controller.functions.activeFunction == .dialogue)
        #expect(controller.functions.target == target)
        #expect(controller.functions.presentationID == firstPresentation)

        let secondPresentation = UUID()
        controller.functions.begin(
            target: target,
            function: .develop,
            selection: nil,
            presentationID: secondPresentation
        )
        #expect(controller.functions.activeFunction == .develop)
        #expect(controller.functions.presentationID == secondPresentation)

        controller.functions.dismiss(presentationID: firstPresentation)
        #expect(controller.functions.presentationID == secondPresentation)

        controller.functions.dismiss(presentationID: secondPresentation)
        #expect(controller.functions.presentationID == nil)
        #expect(controller.functions.target == nil)
    }

    @Test("Quick Open rejects a superseded completion")
    func quickOpenStaleResultRejection() {
        let controller = DiscoveryController()
        let first = controller.beginQuickOpen("first")
        let second = controller.beginQuickOpen("second")
        let result = WorkspaceCatalogNote(
            reference: VaultNoteReference(
                vaultID: UUID(),
                vaultName: "Fixture Topics",
                vaultRole: .topicKnowledge,
                relativePath: "Topics/Agency.md",
                stableNoteID: UUID().uuidString.lowercased()
            ),
            title: "Agency",
            zoteroItemKey: nil,
            zoteroSourceIdentity: nil,
            fingerprint: DocumentFingerprint(content: "# Agency\n"),
            validationWarnings: []
        )

        controller.receiveQuickOpenResults([result], for: first)
        #expect(controller.quickOpen.query == "second")
        #expect(controller.quickOpen.results.isEmpty)

        controller.receiveQuickOpenResults([result], for: second)
        #expect(controller.quickOpen.results == [result])
    }

    @Test("Native and WebKit color roles use one semantic vocabulary")
    func semanticColorParity() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cssURL = repository.appendingPathComponent("Scholium/Resources/Editor/editor.css")
        let css = try String(contentsOf: cssURL, encoding: .utf8)

        let nativeNames = Set(ScholiumColorRole.allCases.map(\.cssVariableName))
        let expression = try NSRegularExpression(pattern: #"--scholium-color-[a-z-]+"#)
        let range = NSRange(css.startIndex..<css.endIndex, in: css)
        let cssNames = Set(expression.matches(in: css, range: range).compactMap { match in
            Range(match.range, in: css).map { String(css[$0]) }
        })

        #expect(cssNames == nativeNames)
        #expect(Set(ScholiumWebDesignTokens.colorVariableNames) == nativeNames)

        for declarations in [
            ScholiumWebDesignTokens.rootCSSDeclarations,
            ScholiumWebDesignTokens.darkAppearanceCSSDeclarations,
            ScholiumWebDesignTokens.increasedContrastCSSDeclarations,
            ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations,
        ] {
            for declaration in declarations.split(separator: "\n") {
                let normalized = declaration.trimmingCharacters(in: .whitespaces)
                guard normalized.hasPrefix("--scholium-color-") else { continue }
                #expect(css.contains(normalized))
            }
        }
    }

    @Test("Light and dark appearances use the reviewed Scholium palettes")
    func reviewedAppearancePalettes() throws {
        #expect(ScholiumInlineStatusKind.information.colorRole == .information)

        let expectedLight: [ScholiumLightPalette: UInt32] = [
            .primary: 0xA94C22,
            .primaryHover: 0x7A2917,
            .notificationHighlight: 0xB47617,
            .neutral: 0x706B65,
            .background: 0xFFFCF5,
            .navigation: 0xEFE9DF,
            .surface: 0xF7F1E7,
            .surfaceRaised: 0xDED3C5,
            .textPrimary: 0x17191C,
            .textSecondary: 0x514D48,
            .border: 0xC8BCAE,
            .confirmed: 0x2C7048,
            .attention: 0x976015,
            .destructive: 0xA13235,
            .information: 0x315F88,
            .agentAuthorship: 0x5D568F,
            .connectionSupport: 0x276F68,
            .connectionIncompatible: 0x6F4D83,
        ]
        #expect(Set(expectedLight.keys) == Set(ScholiumLightPalette.allCases))
        for (role, value) in expectedLight {
            #expect(role.rawValue == value)
        }

        let expectedDark: [ScholiumDarkPalette: UInt32] = [
            .primary: 0xEF8D5B,
            .primaryHover: 0xF5AA7B,
            .notificationHighlight: 0xE1B64F,
            .neutral: 0xB6A38F,
            .background: 0x302A26,
            .navigation: 0x3A2B2B,
            .surface: 0x3A322D,
            .surfaceRaised: 0x423831,
            .textPrimary: 0xF4E8D5,
            .textSecondary: 0xD4C2AD,
            .border: 0x807064,
            .confirmed: 0x7FC39A,
            .attention: 0xE0AB61,
            .destructive: 0xEA817C,
            .information: 0x84B0D4,
            .agentAuthorship: 0xB5A6DC,
            .connectionSupport: 0x79B9AB,
            .connectionIncompatible: 0xC29CCF,
        ]
        #expect(Set(expectedDark.keys) == Set(ScholiumDarkPalette.allCases))
        for (role, value) in expectedDark {
            #expect(role.rawValue == value)
        }

        let expectedLightCSS = [
            "--scholium-color-document-background: #fffcf5",
            "--scholium-color-navigation-background: #efe9df",
            "--scholium-color-surface-background: #f7f1e7",
            "--scholium-color-raised-surface-background: #ded3c5",
            "--scholium-color-primary-text: #17191c",
            "--scholium-color-secondary-text: #514d48",
            "--scholium-color-muted-text: #706b65",
            "--scholium-color-separator: #c8bcae",
            "--scholium-color-accent: #a94c22",
            "--scholium-color-accent-hover: #7a2917",
            "--scholium-color-notification-highlight: #b47617",
            "--scholium-color-information: #315f88",
            "--scholium-color-attention: #976015",
            "--scholium-color-destructive: #a13235",
            "--scholium-color-confirmed: #2c7048",
            "--scholium-color-agent-authorship: #5d568f",
            "--scholium-color-connection-support: #276f68",
            "--scholium-color-connection-incompatible: #6f4d83",
        ]
        for declaration in expectedLightCSS {
            #expect(ScholiumWebDesignTokens.rootCSSDeclarations.contains(declaration))
        }

        let expectedDarkCSS = [
            "--scholium-color-document-background: #302a26",
            "--scholium-color-navigation-background: #3a2b2b",
            "--scholium-color-surface-background: #3a322d",
            "--scholium-color-raised-surface-background: #423831",
            "--scholium-color-primary-text: #f4e8d5",
            "--scholium-color-secondary-text: #d4c2ad",
            "--scholium-color-muted-text: #b6a38f",
            "--scholium-color-separator: #807064",
            "--scholium-color-accent: #ef8d5b",
            "--scholium-color-accent-hover: #f5aa7b",
            "--scholium-color-notification-highlight: #e1b64f",
            "--scholium-color-information: #84b0d4",
            "--scholium-color-attention: #e0ab61",
            "--scholium-color-destructive: #ea817c",
            "--scholium-color-confirmed: #7fc39a",
            "--scholium-color-agent-authorship: #b5a6dc",
            "--scholium-color-connection-support: #79b9ab",
            "--scholium-color-connection-incompatible: #c29ccf",
        ]
        for declaration in expectedDarkCSS {
            #expect(ScholiumWebDesignTokens.darkAppearanceCSSDeclarations.contains(declaration))
        }

        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))
        let expectedNativeLightRoles: [ScholiumColorRole: UInt32] = [
            .documentBackground: 0xFFFCF5,
            .navigationBackground: 0xEFE9DF,
            .surfaceBackground: 0xF7F1E7,
            .raisedSurfaceBackground: 0xDED3C5,
            .primaryText: 0x17191C,
            .secondaryText: 0x514D48,
            .mutedText: 0x706B65,
            .separator: 0xC8BCAE,
            .accent: 0xA94C22,
            .accentHover: 0x7A2917,
            .notificationHighlight: 0xB47617,
            .information: 0x315F88,
            .attention: 0x976015,
            .attentionForeground: 0x976015,
            .destructive: 0xA13235,
            .destructiveForeground: 0xA13235,
            .confirmed: 0x2C7048,
            .confirmedForeground: 0x2C7048,
            .agentAuthorship: 0x5D568F,
            .connectionNeutral: 0xA94C22,
            .connectionSupport: 0x276F68,
            .connectionIncompatible: 0x6F4D83,
        ]
        for (role, expectedValue) in expectedNativeLightRoles {
            #expect(rgbValue(
                of: role.nsColor(increasedContrast: false),
                appearance: aqua
            ) == expectedValue)
        }

        let expectedNativeDarkRoles: [ScholiumColorRole: UInt32] = [
            .documentBackground: 0x302A26,
            .navigationBackground: 0x3A2B2B,
            .surfaceBackground: 0x3A322D,
            .raisedSurfaceBackground: 0x423831,
            .primaryText: 0xF4E8D5,
            .secondaryText: 0xD4C2AD,
            .mutedText: 0xB6A38F,
            .separator: 0x807064,
            .accent: 0xEF8D5B,
            .accentHover: 0xF5AA7B,
            .notificationHighlight: 0xE1B64F,
            .information: 0x84B0D4,
            .attention: 0xE0AB61,
            .attentionForeground: 0xE0AB61,
            .destructive: 0xEA817C,
            .destructiveForeground: 0xEA817C,
            .confirmed: 0x7FC39A,
            .confirmedForeground: 0x7FC39A,
            .agentAuthorship: 0xB5A6DC,
            .connectionNeutral: 0xEF8D5B,
            .connectionSupport: 0x79B9AB,
            .connectionIncompatible: 0xC29CCF,
        ]
        for (role, expectedValue) in expectedNativeDarkRoles {
            #expect(rgbValue(
                of: role.nsColor(increasedContrast: false),
                appearance: darkAqua
            ) == expectedValue)
        }

        for foreground in [
            0x17191C,
            0x514D48,
            0x706B65,
            0xA94C22,
            0x315F88,
            0x976015,
            0xA13235,
            0x2C7048,
            0x5D568F,
            0x276F68,
            0x6F4D83,
        ] as [UInt32] {
            #expect(contrastRatio(foreground, 0xF7F1E7) >= 4.5)
        }

        for foreground in [
            0xF4E8D5,
            0xD4C2AD,
            0xB6A38F,
            0xEF8D5B,
            0x84B0D4,
            0xE0AB61,
            0xEA817C,
            0x7FC39A,
            0xB5A6DC,
            0x79B9AB,
            0xC29CCF,
        ] as [UInt32] {
            #expect(contrastRatio(foreground, 0x3A322D) >= 4.5)
        }
    }

    @Test("Reduce Motion removes app-defined transitions")
    func reducedMotionRemovesTransitions() {
        #expect(ScholiumMotion.documentReveal(reduceMotion: true) == nil)
        #expect(ScholiumMotion.searchPresentation(reduceMotion: true) == nil)
        #expect(ScholiumMotion.searchExpansion(reduceMotion: true) == nil)
        #expect(ScholiumMotion.disclosure(reduceMotion: true) == nil)

        #expect(ScholiumMotion.documentReveal(reduceMotion: false) != nil)
        #expect(ScholiumMotion.searchPresentation(reduceMotion: false) != nil)
        #expect(ScholiumMotion.searchExpansion(reduceMotion: false) != nil)
        #expect(ScholiumMotion.disclosure(reduceMotion: false) != nil)
    }

    @Test("Reduce Transparency selects the opaque Research Strip fallback")
    func reducedTransparencyUsesOpaqueResearchStripSurface() {
        let reduced = ResearchStripSurfaceStyle(reduceTransparency: true)
        #expect(reduced.usesOpaqueBackground)
        #expect(reduced.separatorOpacity == 0.72)

        let standard = ResearchStripSurfaceStyle(reduceTransparency: false)
        #expect(!standard.usesOpaqueBackground)
        #expect(standard.separatorOpacity == 0.28)
    }

    @Test("Relationship colors provide increased-contrast variants")
    func increasedContrastRelationshipColors() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cssURL = repository.appendingPathComponent("Scholium/Resources/Editor/editor.css")
        let css = try String(contentsOf: cssURL, encoding: .utf8)
        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))

        #expect(ScholiumColorRole.connectionSupport.resolvedCustomRGBValue(
            for: aqua,
            increasedContrast: false
        ) == 0x276F68)
        #expect(ScholiumColorRole.connectionSupport.resolvedCustomRGBValue(
            for: darkAqua,
            increasedContrast: false
        ) == 0x79B9AB)
        #expect(ScholiumColorRole.connectionSupport.resolvedCustomRGBValue(
            for: aqua,
            increasedContrast: true
        ) == 0x195A54)
        #expect(ScholiumColorRole.connectionSupport.resolvedCustomRGBValue(
            for: darkAqua,
            increasedContrast: true
        ) == 0x9CD5CA)

        #expect(ScholiumColorRole.connectionIncompatible.resolvedCustomRGBValue(
            for: aqua,
            increasedContrast: false
        ) == 0x6F4D83)
        #expect(ScholiumColorRole.connectionIncompatible.resolvedCustomRGBValue(
            for: darkAqua,
            increasedContrast: false
        ) == 0xC29CCF)
        #expect(ScholiumColorRole.connectionIncompatible.resolvedCustomRGBValue(
            for: aqua,
            increasedContrast: true
        ) == 0x50365F)
        #expect(ScholiumColorRole.connectionIncompatible.resolvedCustomRGBValue(
            for: darkAqua,
            increasedContrast: true
        ) == 0xDDBCE5)

        #expect(ScholiumWebDesignTokens.increasedContrastCSSDeclarations.contains("#195a54"))
        #expect(ScholiumWebDesignTokens.increasedContrastCSSDeclarations.contains("#50365f"))
        #expect(ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations.contains("#9cd5ca"))
        #expect(ScholiumWebDesignTokens.darkIncreasedContrastCSSDeclarations.contains("#ddbce5"))
        for value in ["#195a54", "#50365f", "#9cd5ca", "#ddbce5"] {
            #expect(css.contains(value))
        }
    }

    private func rgbValue(of color: NSColor, appearance: NSAppearance) -> UInt32? {
        var result: UInt32?
        appearance.performAsCurrentDrawingAppearance {
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            result = (UInt32((red * 255).rounded()) << 16)
                | (UInt32((green * 255).rounded()) << 8)
                | UInt32((blue * 255).rounded())
        }
        return result
    }

    private func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ value: UInt32) -> Double {
        let red = linearized(Double((value >> 16) & 0xFF) / 255)
        let green = linearized(Double((value >> 8) & 0xFF) / 255)
        let blue = linearized(Double(value & 0xFF) / 255)
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    private func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}
