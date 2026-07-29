#if DEBUG
import ScholiumContracts
import SwiftUI

/// Stage 4 proof routes are Debug-only scene values. They identify synthetic
/// proof windows; they are never Workspace, Triptych, document, or route
/// authority.
struct DesignContractProofWindowRoute: Codable, Hashable {
    enum Slot: String, Codable, Hashable {
        case a = "A"
        case b = "B"
    }

    let slot: Slot
    let initialProof: DesignContractProof

    static let primary = DesignContractProofWindowRoute(
        slot: .a,
        initialProof: .library
    )

    func paired(for proof: DesignContractProof) -> Self {
        Self(slot: slot == .a ? .b : .a, initialProof: proof)
    }
}

enum DesignContractProof: String, Codable, CaseIterable, Identifiable {
    case library
    case searchAttention
    case actions
    case documentStates
    case multiwindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Library"
        case .searchAttention: "Search + Attention"
        case .actions: "Actions"
        case .documentStates: "Document States"
        case .multiwindow: "Multiwindow"
        }
    }

    var scenarios: [DesignContractProofScenario] {
        switch self {
        case .library:
            [.libraryCommitted, .libraryStaging, .libraryReplacementFailed,
             .libraryInitialLoading, .libraryConfirmedEmpty]
        case .searchAttention:
            [.searchRefreshing, .searchStale, .searchRefreshFailed,
             .searchConfirmedEmpty, .attentionReady, .attentionStale,
             .attentionFailed]
        case .actions:
            [.analysisActions, .topicActions, .workActions,
             .workActionsWithManuscript, .analyzeRunning]
        case .documentStates:
            [.autosaveFailed, .conflict, .checkpointRestored]
        case .multiwindow:
            [.windowIdle, .windowSearch, .windowSheet, .windowAnchorRemoved]
        }
    }
}

enum DesignContractProofScenario: String, CaseIterable, Identifiable {
    case libraryCommitted
    case libraryStaging
    case libraryReplacementFailed
    case libraryInitialLoading
    case libraryConfirmedEmpty
    case searchRefreshing
    case searchStale
    case searchRefreshFailed
    case searchConfirmedEmpty
    case attentionReady
    case attentionStale
    case attentionFailed
    case analysisActions
    case topicActions
    case workActions
    case workActionsWithManuscript
    case analyzeRunning
    case autosaveFailed
    case conflict
    case checkpointRestored
    case windowIdle
    case windowSearch
    case windowSheet
    case windowAnchorRemoved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .libraryCommitted: "Committed content"
        case .libraryStaging: "Staging Trash"
        case .libraryReplacementFailed: "Trash failed; Library retained"
        case .libraryInitialLoading: "Initial loading"
        case .libraryConfirmedEmpty: "Confirmed empty"
        case .searchRefreshing: "Refreshing with trusted results"
        case .searchStale: "Derived State Stale"
        case .searchRefreshFailed: "Refresh failed; trusted results retained"
        case .searchConfirmedEmpty: "Confirmed empty results"
        case .attentionReady: "Attention ready"
        case .attentionStale: "Attention stale"
        case .attentionFailed: "Attention unavailable"
        case .analysisActions: "Analysis — all Actions"
        case .topicActions: "Topic — all Actions"
        case .workActions: "Work — all default Actions"
        case .workActionsWithManuscript: "Work — optional Manuscript enabled"
        case .analyzeRunning: "Analyze running"
        case .autosaveFailed: "Autosave failed"
        case .conflict: "Conflict detected"
        case .checkpointRestored: "Checkpoint restored"
        case .windowIdle: "Window-local route idle"
        case .windowSearch: "Window-local Search"
        case .windowSheet: "Window-local sheet"
        case .windowAnchorRemoved: "Anchor removed"
        }
    }
}

private enum DesignContractProofAdaptation: String, CaseIterable, Identifiable {
    case standard
    case dark
    case increasedContrast
    case reduceTransparency
    case reduceMotion
    case inactiveWindow
    case rightToLeft
    case documentText200

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .dark: "Dark"
        case .increasedContrast: "Increase Contrast"
        case .reduceTransparency: "Reduce Transparency"
        case .reduceMotion: "Reduce Motion"
        case .inactiveWindow: "Inactive Window"
        case .rightToLeft: "RTL + Long Copy"
        case .documentText200: "200% Document Text"
        }
    }

    var visualOverride: ScholiumVisualEnvironmentOverride {
        switch self {
        case .increasedContrast:
            .init(increasedContrast: true)
        case .reduceTransparency:
            .init(reduceTransparency: true)
        case .reduceMotion:
            .init(reduceMotion: true)
        case .inactiveWindow:
            .init(appearsActive: false)
        case .standard, .dark, .rightToLeft, .documentText200:
            .init()
        }
    }

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var layoutDirection: LayoutDirection { self == .rightToLeft ? .rightToLeft : .leftToRight }
    var locale: Locale { self == .rightToLeft ? Locale(identifier: "ar") : Locale(identifier: "en") }
    var documentTextScale: CGFloat { self == .documentText200 ? 2 : 1 }
    var usesLongCopy: Bool { self == .rightToLeft }
}

/// One QA-only host for the Stage 4 complete-window proofs. The control
/// strip belongs to the proof harness; everything below it is the 1180 × 760
/// Workspace composition under review.
@MainActor
struct DesignContractCompleteWindowProofs: View {
    let route: DesignContractProofWindowRoute

    @Environment(\.openWindow) private var openWindow
    @State private var proof: DesignContractProof
    @State private var scenario: DesignContractProofScenario
    @State private var adaptation: DesignContractProofAdaptation = .standard

    init(route: DesignContractProofWindowRoute) {
        self.route = route
        _proof = State(initialValue: route.initialProof)
        _scenario = State(initialValue: route.initialProof.scenarios[0])
    }

    var body: some View {
        VStack(spacing: 0) {
            proofControls
            ScholiumStructuralRule()
            adaptedProof
        }
        .frame(minWidth: 1_180, minHeight: 808)
        .navigationTitle("Stage 4 Proof — Window \(route.slot.rawValue)")
        .onChange(of: proof) { _, value in
            scenario = value.scenarios[0]
        }
    }

    private var proofControls: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("STAGE 4")
                .font(ScholiumInterfaceTypography.editorialLabel)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .accessibilityAddTraits(.isHeader)

            ForEach(DesignContractProof.allCases) { candidate in
                Button(candidate.title) { proof = candidate }
                    .buttonStyle(.borderless)
                    .font(.callout.weight(proof == candidate ? .semibold : .regular))
                    .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
                    .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
                    .background {
                        if proof == candidate {
                            ScholiumColorRole.raisedSurfaceBackground.color
                        }
                    }
                    .accessibilityValue(proof == candidate ? "Selected" : "")
                    .accessibilityIdentifier("scholium.stage4.proof.\(candidate.rawValue)")
            }

            Spacer(minLength: 8)

            Menu {
                ForEach(proof.scenarios) { candidate in
                    Button(candidate.title) { scenario = candidate }
                }
            } label: {
                Label(scenario.title, systemImage: "square.stack.3d.up")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Proof state")
            .accessibilityValue(scenario.title)
            .accessibilityIdentifier("scholium.stage4.scenario")

            Menu {
                ForEach(DesignContractProofAdaptation.allCases) { candidate in
                    Button(candidate.title) { adaptation = candidate }
                }
            } label: {
                Label(adaptation.title, systemImage: "circle.lefthalf.filled")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Adaptation")
            .accessibilityValue(adaptation.title)
            .accessibilityIdentifier("scholium.stage4.adaptation")

            if proof == .multiwindow {
                Button("Open Paired Window") {
                    openWindow(
                        id: "scholium-stage4-design-proofs",
                        value: route.paired(for: .multiwindow)
                    )
                }
                .accessibilityIdentifier("scholium.stage4.openPair")
            }
        }
        .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
        .frame(minHeight: ScholiumGrid.Dimension.regionHeaderHeight)
        .scholiumSurface(.denseEvidence)
    }

    @ViewBuilder
    private var adaptedProof: some View {
        proofContent
            .environment(\.scholiumVisualEnvironmentOverride, adaptation.visualOverride)
            .environment(\.colorScheme, adaptation.colorScheme)
            .environment(\.layoutDirection, adaptation.layoutDirection)
            .environment(\.locale, adaptation.locale)
            .id("\(proof.rawValue)-\(scenario.rawValue)-\(adaptation.rawValue)")
    }

    @ViewBuilder
    private var proofContent: some View {
        switch proof {
        case .library:
            LibraryCompleteWindowProof(
                scenario: scenario,
                documentTextScale: adaptation.documentTextScale,
                usesLongCopy: adaptation.usesLongCopy
            )
        case .searchAttention:
            SearchAttentionCompleteWindowProof(
                scenario: $scenario,
                documentTextScale: adaptation.documentTextScale,
                usesLongCopy: adaptation.usesLongCopy
            )
        case .actions:
            ActionsCompleteWindowProof(
                scenario: scenario,
                documentTextScale: adaptation.documentTextScale,
                usesLongCopy: adaptation.usesLongCopy
            )
        case .documentStates:
            DocumentStatesCompleteWindowProof(
                scenario: scenario,
                documentTextScale: adaptation.documentTextScale,
                usesLongCopy: adaptation.usesLongCopy
            )
        case .multiwindow:
            MultiwindowCompleteWindowProof(
                windowSlot: route.slot,
                scenario: scenario,
                documentTextScale: adaptation.documentTextScale,
                usesLongCopy: adaptation.usesLongCopy
            )
        }
    }
}

// MARK: - Complete Workspace shell

private struct Stage4WorkspaceShell<Sidebar: View, Document: View, Apparatus: View>: View {
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let document: () -> Document
    @ViewBuilder let apparatus: () -> Apparatus

    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: ScholiumMetrics.Library.minimumReadableWidth)

            ScholiumStructuralRule(orientation: .vertical)

            document()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScholiumStructuralRule(orientation: .vertical)

            apparatus()
                .frame(width: ScholiumMetrics.Apparatus.firstRevealWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scholiumSurface(.document)
    }
}

private struct Stage4DocumentPane: View {
    let title: String
    let state: String
    let textScale: CGFloat
    let usesLongCopy: Bool
    let inlineStatus: (title: String, detail: String, kind: ScholiumInlineStatusKind)?
    @Binding var draft: String
    var editable = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text(title)
                    .font(ScholiumInterfaceTypography.workspaceToolbarIdentity)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .lineLimit(1)
                    .accessibilityIdentifier("scholium.stage4.documentTitle")
                Spacer(minLength: 8)
                Text(state)
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
            .frame(minHeight: ScholiumGrid.Dimension.regionHeaderHeight)

            ScholiumStructuralRule()

            if editable {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    if let inlineStatus {
                        ScholiumInlineStatus(
                            inlineStatus.title,
                            detail: inlineStatus.detail,
                            kind: inlineStatus.kind
                        )
                    }
                    TextEditor(text: $draft)
                        .font(ScholiumTypography.swiftUIReadingFont(
                            size: CGFloat(ScholiumDocumentRhythm.proseFontSizePoints) * textScale,
                            relativeTo: .body
                        ))
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Synthetic preserved editor buffer")
                        .accessibilityIdentifier("scholium.stage4.syntheticEditor")
                }
                .padding(ScholiumGrid.Spacing.regionContentInset)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                        if let inlineStatus {
                            ScholiumInlineStatus(
                                inlineStatus.title,
                                detail: inlineStatus.detail,
                                kind: inlineStatus.kind
                            )
                        }
                        Text(usesLongCopy
                            ? "الانتباه والحكم القابل للمراجعة — Attention, source fidelity, and the limits of immediate confirmation"
                            : "Attention, Source Fidelity, and Revisable Judgment")
                            .font(ScholiumInterfaceTypography.documentTitle)
                        ScholiumStructuralRule()
                        Text("A research judgment can remain useful while its supporting projection is refreshed. The source, the derived result, and the researcher’s present assessment therefore remain visibly distinct.")
                        Text("哲学研究中的判断可以保留其可修正性；检索结果、来源文本与研究者判断不能因为界面刷新而混成同一层证据。")
                        Text("The document remains readable and primary while Library, Search, Attention, Actions, conflict, and recovery report their narrower responsibilities.")
                    }
                    .font(ScholiumTypography.swiftUIReadingFont(
                        size: CGFloat(ScholiumDocumentRhythm.proseFontSizePoints) * textScale,
                        relativeTo: .body
                    ))
                    .lineSpacing(5 * textScale)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .scholiumSurface(.document)
    }
}

private struct Stage4ApparatusPane<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(ScholiumInterfaceTypography.apparatusTitle)
                    .accessibilityIdentifier("scholium.stage4.apparatusTitle")
                Spacer()
                Text("Synthetic")
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
            .frame(minHeight: ScholiumMetrics.Apparatus.headerHeight)
            ScholiumStructuralRule()
            ScrollView {
                content()
                    .padding(ScholiumMetrics.Apparatus.contentInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scholiumSurface(.apparatus)
    }
}

// MARK: - Library proof

private struct LibraryCompleteWindowProof: View {
    let scenario: DesignContractProofScenario
    let documentTextScale: CGFloat
    let usesLongCopy: Bool
    @State private var draft = ""

    var body: some View {
        Stage4WorkspaceShell {
            library
        } document: {
            Stage4DocumentPane(
                title: "The value-first objection under delayed confirmation",
                state: "Saved · Derived consumers current",
                textScale: documentTextScale,
                usesLongCopy: usesLongCopy,
                inlineStatus: nil,
                draft: $draft
            )
        } apparatus: {
            Stage4ApparatusPane(title: "Library proof") {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.sectionSpacing) {
                    ScholiumApparatusSection("BOUNDARY") {
                        ScholiumApparatusReadingBlock(
                            label: "Claim",
                            text: "Folder disclosure, Note identity, selection, inactive selection, focus, and replacement state remain distinguishable at the 300pt Library boundary."
                        )
                    }
                    ScholiumApparatusSection("CURRENT STATE") {
                        ScholiumInlineStatus(
                            scenario.title,
                            detail: libraryStateDetail,
                            kind: scenario == .libraryReplacementFailed ? .attention : .information
                        )
                    }
                }
            }
        }
    }

    private var library: some View {
        ZStack(alignment: .bottom) {
            SidebarCutoverCatalog(
                scenario: sidebarScenario,
                height: 760
            )

            if scenario == .libraryStaging || scenario == .libraryReplacementFailed {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    ScholiumInlineStatus(
                        scenario == .libraryStaging ? "Loading Trash…" : "Could Not Open Trash",
                        detail: scenario == .libraryStaging
                            ? "Library remains selected and operable until the complete target is ready."
                            : "Library remains selected. Retry Trash or cancel the replacement.",
                        kind: scenario == .libraryStaging ? .information : .attention
                    )
                    if scenario == .libraryReplacementFailed {
                        HStack {
                            Button("Retry Trash") {}
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                }
                .padding(ScholiumGrid.Spacing.nestedContentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scholiumEditorialSurface(
                    .floatingControl,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                )
                .padding(ScholiumGrid.Spacing.inlineControlGap)
                .accessibilityIdentifier("scholium.stage4.library.replacementStatus")
            }
        }
    }

    private var sidebarScenario: SidebarCutoverCatalog.Scenario {
        switch scenario {
        case .libraryInitialLoading: .loading
        case .libraryConfirmedEmpty: .empty
        default: usesLongCopy ? .filteredLongCJK : .standard
        }
    }

    private var libraryStateDetail: String {
        switch scenario {
        case .libraryCommitted:
            "One committed Scope, Location, and Source List are visible together."
        case .libraryStaging:
            "The target is named separately while the prior committed projection stays usable."
        case .libraryReplacementFailed:
            "The target failure is not displayed beneath the prior Location title."
        case .libraryInitialLoading:
            "No trustworthy committed projection exists yet."
        case .libraryConfirmedEmpty:
            "An accepted complete response contains no Notes."
        default:
            "Choose a Library state from the proof controls."
        }
    }
}

// MARK: - Search and Attention proof

private struct SearchAttentionCompleteWindowProof: View {
    @Binding var scenario: DesignContractProofScenario
    let documentTextScale: CGFloat
    let usesLongCopy: Bool
    @State private var draft = ""
    @State private var searchVisible = true

    var body: some View {
        Stage4WorkspaceShell {
            SidebarCutoverCatalog(scenario: .attentionOne, height: 760)
        } document: {
            ZStack(alignment: .top) {
                Stage4DocumentPane(
                    title: "Attention and revisable judgment",
                    state: "Saved",
                    textScale: documentTextScale,
                    usesLongCopy: usesLongCopy,
                    inlineStatus: nil,
                    draft: $draft
                )
                if isAttentionScenario {
                    AttentionPopoverCatalog(scenario: attentionScenario)
                        .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
                        .accessibilityIdentifier("scholium.stage4.attention")
                } else if searchVisible {
                    SearchPanelFixture(scenario: scenario) {
                        searchVisible = false
                    }
                    .padding(.top, ScholiumMetrics.Search.responsiveMargin)
                }
            }
        } apparatus: {
            Stage4ApparatusPane(title: "Search + Attention") {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.sectionSpacing) {
                    ScholiumApparatusSection("BOUNDARY") {
                        ScholiumApparatusReadingBlock(
                            label: "Claim",
                            text: "A derived refresh or failure does not erase trustworthy lexical results or masquerade as source-save failure. Attention retains one exact-window anchor."
                        )
                    }
                    Button(isAttentionScenario ? "Return to Search" : "Reopen Search") {
                        if isAttentionScenario {
                            scenario = .searchRefreshing
                        }
                        searchVisible = true
                    }
                    .accessibilityIdentifier("scholium.stage4.reopenSearch")
                }
            }
        }
    }

    private var isAttentionScenario: Bool {
        [.attentionReady, .attentionStale, .attentionFailed].contains(scenario)
    }

    private var attentionScenario: AttentionPopoverCatalog.Scenario {
        switch scenario {
        case .attentionStale: .stale
        case .attentionFailed: .error
        default: .ready
        }
    }
}

@MainActor
private struct SearchPanelFixture: View {
    let dismiss: () -> Void
    @StateObject private var controller: DiscoveryController

    init(scenario: DesignContractProofScenario, dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        let controller = DiscoveryController()
        let criteria = SearchWorkspaceState(query: "attention", scope: .triptych)
        let request = controller.beginSearch(criteria)
        let generation = SearchGenerationID(
            triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            sequence: 7,
            sourceManifestHash: "stage4-synthetic-manifest"
        )
        let freshness = SearchFreshnessToken.triptych(generation)
        let availability: SearchAvailability = switch scenario {
        case .searchRefreshing:
            .refreshing(lastGood: generation)
        case .searchStale:
            .stale(lastGood: generation, reason: "Two committed Notes changed after generation 7.")
        case .searchRefreshFailed:
            .failed(lastGood: generation, reason: "The replacement index could not be published.")
        default:
            .current(generation)
        }
        controller.receiveSearchResponse(
            SearchResponse(
                requestID: request.id,
                scope: .triptych,
                freshnessToken: freshness,
                availability: availability,
                results: scenario == .searchConfirmedEmpty
                    ? []
                    : Self.hits(freshness: freshness),
                hasMore: false
            ),
            for: request
        )
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        SpotlightSearchPanelView(
            controller: controller,
            context: SpotlightSearchContext(
                savedSearches: [],
                refresh: {},
                dismiss: dismiss,
                save: { _ in },
                run: { _ in },
                rename: { _, _ in },
                move: { _, _ in },
                delete: { _ in }
            ),
            maxPanelHeight: ScholiumMetrics.Search.expandedHeight
        )
        .frame(width: ScholiumMetrics.Search.preferredWidth)
        .accessibilityIdentifier("scholium.stage4.search")
    }

    private static func hits(freshness: SearchFreshnessToken) -> [SearchHit] {
        let vaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        return [
            SearchHit(
                vaultID: vaultID,
                vaultName: "Analyses",
                vaultRole: .sourceCorpus,
                relativePath: "Attention/Perceptual salience.md",
                stableNoteID: "stage4-search-1",
                title: "Attention and perceptual salience",
                matchedField: .title,
                context: "Heading",
                sourceLine: 1,
                snippet: "Attention and perceptual salience",
                highlights: [SearchHighlight(utf16LowerBound: 0, utf16UpperBound: 9)],
                freshnessToken: freshness,
                fingerprint: DocumentFingerprint(content: "# Attention and perceptual salience\n"),
                evidentialLayer: .paperAnalysis,
                classification: .retrievalLead
            ),
            SearchHit(
                vaultID: vaultID,
                vaultName: "Topics",
                vaultRole: .topicKnowledge,
                relativePath: "Normative attention/Revision and reliance.md",
                stableNoteID: "stage4-search-2",
                title: "Revision, reliance, and normative attention",
                matchedField: .body,
                context: "Objection",
                sourceLine: 42,
                snippet: "A stale projection can still guide attention without becoming evidence.",
                highlights: [SearchHighlight(utf16LowerBound: 35, utf16UpperBound: 44)],
                freshnessToken: freshness,
                fingerprint: DocumentFingerprint(content: "# Revision, reliance, and normative attention\n"),
                evidentialLayer: .topicNote,
                classification: .retrievalLead
            ),
        ]
    }
}

// MARK: - Actions and document-state proofs

private enum Stage4ActionRoute: Identifiable {
    case action(ResearchActionProofKind)
    case conflictComparison

    var id: String {
        switch self {
        case .action(let action): "action-\(action.rawValue)"
        case .conflictComparison: "conflict-comparison"
        }
    }
}

private enum Stage4ActionTarget {
    case analysis
    case topic
    case work
    case workWithManuscript

    var research: [ResearchActionProofKind] {
        switch self {
        case .analysis: [.discuss, .analyze]
        case .topic: [.discuss, .synthesize]
        case .work, .workWithManuscript: [.discuss, .write]
        }
    }

    var review: [ResearchActionProofKind] {
        switch self {
        case .analysis, .topic: [.checkFidelity]
        case .work, .workWithManuscript: [.critique, .checkFidelity]
        }
    }

    var researcherSkills: [ResearchActionProofKind] {
        self == .workWithManuscript ? [.manuscript] : []
    }
}

private struct ActionsCompleteWindowProof: View {
    let scenario: DesignContractProofScenario
    let documentTextScale: CGFloat
    let usesLongCopy: Bool
    @State private var route: Stage4ActionRoute?
    @State private var draft = """
    # Attention, Source Fidelity, and Revisable Judgment

    This synthetic buffer remains visible while the role-valid Research Actions
    are reviewed. 关于注意与规范理由的工作段落保持未提交状态。
    """

    var body: some View {
        Stage4WorkspaceShell {
            SidebarCutoverCatalog(scenario: .standard, height: 760)
        } document: {
            Stage4DocumentPane(
                title: documentTitle,
                state: "Edited",
                textScale: documentTextScale,
                usesLongCopy: usesLongCopy,
                inlineStatus: nil,
                draft: $draft,
                editable: true
            )
        } apparatus: {
            Stage4ApparatusPane(title: "Actions") {
                Stage4ActionsList(
                    target: target,
                    runningAction: scenario == .analyzeRunning ? .analyze : nil,
                    select: { route = .action($0) }
                )
            }
        }
        .sheet(item: $route) { route in
            if case .action(let action) = route {
                ResearchActionSheetProof(action: action)
                    .frame(minWidth: 720, minHeight: 620)
                    .accessibilityIdentifier("scholium.stage4.actionSheet")
            }
        }
    }

    private var target: Stage4ActionTarget {
        switch scenario {
        case .topicActions: .topic
        case .workActions: .work
        case .workActionsWithManuscript: .workWithManuscript
        default: .analysis
        }
    }

    private var documentTitle: String {
        switch target {
        case .analysis: "Attention and Salience — Analysis"
        case .topic: "Attention and Normative Reasons — Topic"
        case .work, .workWithManuscript: "Revisable Judgment — Work"
        }
    }
}

private struct DocumentStatesCompleteWindowProof: View {
    let scenario: DesignContractProofScenario
    let documentTextScale: CGFloat
    let usesLongCopy: Bool
    @State private var route: Stage4ActionRoute?
    @State private var draft = """
    # Attention, Source Fidelity, and Revisable Judgment

    This exact editor buffer remains visible while autosave, external-change,
    and checkpoint-result messages are reviewed. 关于注意与规范理由的修改仍保留在编辑器中。
    """

    var body: some View {
        Stage4WorkspaceShell {
            SidebarCutoverCatalog(scenario: .standard, height: 760)
        } document: {
            Stage4DocumentPane(
                title: "Attention and Salience — Analysis",
                state: documentState,
                textScale: documentTextScale,
                usesLongCopy: usesLongCopy,
                inlineStatus: nil,
                draft: $draft,
                editable: true
            )
            .overlay(alignment: .bottom) {
                Stage4DocumentStatusToast(
                    title: toast.title,
                    detail: toast.detail,
                    kind: toast.kind,
                    actionTitle: toast.actionTitle,
                    action: toast.actionTitle == nil ? nil : {
                        if scenario == .conflict {
                            route = .conflictComparison
                        }
                    }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        } apparatus: {
            Stage4ApparatusPane(title: "Actions") {
                Stage4ActionsList(
                    target: .analysis,
                    runningAction: nil,
                    select: { route = .action($0) }
                )
            }
        }
        .sheet(item: $route) { route in
            switch route {
            case .action(let action):
                ResearchActionSheetProof(action: action)
                    .frame(minWidth: 720, minHeight: 620)
                    .accessibilityIdentifier("scholium.stage4.actionSheet")
            case .conflictComparison:
                Stage4ConflictComparisonProof { self.route = nil }
            }
        }
    }

    private var documentState: String {
        switch scenario {
        case .autosaveFailed, .conflict: "Edited"
        case .checkpointRestored: "Saved"
        default: "Edited"
        }
    }

    private var toast: Stage4DocumentStatusToast.Value {
        switch scenario {
        case .autosaveFailed:
            .init(
                title: "Autosave Failed",
                detail: "Your edits are still available. Scholium will try again after the next change.",
                kind: .error,
                actionTitle: nil
            )
        case .conflict:
            .init(
                title: "Autosave Paused",
                detail: "This file changed outside Scholium. Your edits are still available.",
                kind: .warning,
                actionTitle: "Compare Changes"
            )
        case .checkpointRestored:
            .init(
                title: "Checkpoint Restored",
                detail: "Scholium created a Before Restore checkpoint.",
                kind: .success,
                actionTitle: nil
            )
        default:
            .init(title: "Edited", detail: "Your edits are waiting for autosave.", kind: .information, actionTitle: nil)
        }
    }
}

private struct Stage4ActionsList: View {
    let target: Stage4ActionTarget
    let runningAction: ResearchActionProofKind?
    let select: (ResearchActionProofKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.sectionSpacing) {
            ScholiumApparatusSection("RESEARCH") {
                actionRows(target.research)
            }
            ScholiumApparatusSection("REVIEW") {
                actionRows(target.review)
            }
            if !target.researcherSkills.isEmpty {
                ScholiumApparatusSection("RESEARCHER SKILLS") {
                    actionRows(target.researcherSkills)
                }
            }
            ScholiumApparatusSection("JUDGMENT") {
                actionButton("Settle", symbol: "checkmark.circle") {}
                    .accessibilityIdentifier("scholium.stage4.action.settle")
            }
        }
    }

    @ViewBuilder
    private func actionRows(_ actions: [ResearchActionProofKind]) -> some View {
        ForEach(actions) { action in
            if runningAction == action {
                Stage4RunningActionRow(action: action)
                .accessibilityIdentifier("scholium.stage4.action.running")
            } else {
                actionButton(action.title, symbol: action.systemImage) {
                    select(action)
                }
                .accessibilityIdentifier("scholium.stage4.action.\(action.rawValue)")
            }
        }
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ScholiumApparatusActionRowContent(
                title: Text(title),
                systemImage: symbol,
                detail: nil,
                showsChevron: true
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: ScholiumMetrics.Apparatus.actionRowMinimumHeight)
    }
}

private struct Stage4RunningActionRow: View {
    let action: ResearchActionProofKind

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                Text(action.title)
                    .font(ScholiumInterfaceTypography.apparatusActionTitle)
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Text("Running")
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(action.title), Running")

            Button {} label: {
                Image(systemName: "xmark")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .frame(
                minWidth: ScholiumMetrics.Accessibility.preferredCustomTarget,
                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
            )
            .accessibilityLabel("Cancel \(action.title)")
            .accessibilityIdentifier("scholium.stage4.action.cancel.\(action.rawValue)")
        }
        .frame(
            minHeight: ScholiumMetrics.Apparatus.actionRowMinimumHeight,
            alignment: .leading
        )
    }
}

private struct Stage4DocumentStatusToast: View {
    struct Value {
        let title: String
        let detail: String
        let kind: Kind
        let actionTitle: String?
    }

    enum Kind {
        case success
        case information
        case warning
        case error

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .information: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: ScholiumColorRole.confirmed.color
            case .information: ScholiumColorRole.information.color
            case .warning: ScholiumColorRole.attention.color
            case .error: ScholiumColorRole.destructive.color
            }
        }
    }

    let title: String
    let detail: String
    let kind: Kind
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.callout)
                .foregroundStyle(kind.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 520, alignment: .leading)
        .scholiumEditorialSurface(
            .floatingControl,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.stage4.documentStatusToast")
    }
}

private struct Stage4ConflictComparisonProof: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            ScholiumPanelHeader(
                "Compare Changes",
                subtitle: "Synthetic editor and disk revisions"
            )
            ScholiumStructuralRule()
            HStack(spacing: ScholiumGrid.Spacing.sectionSeparation) {
                revision("EDITOR BUFFER", text: "The judgment remains revisable while evidence is checked.\n关于注意的段落仍在编辑。")
                revision("DISK REVISION", text: "The judgment remains provisional while evidence is checked.\n关于注意的段落已在外部修改。")
            }
            Spacer(minLength: 0)
            HStack {
                Button("Return to Editing", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reload from Disk") {}
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(width: 760, height: 520)
        .scholiumSurface(.denseEvidence)
        .accessibilityIdentifier("scholium.stage4.conflictComparison")
    }

    private func revision(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(title)
                .font(ScholiumInterfaceTypography.editorialLabel)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Text(text)
                .font(ScholiumTypography.swiftUIMonospaceFont(size: 12, relativeTo: .body))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(ScholiumGrid.Spacing.nestedContentInset)
                .overlay { ScholiumStructuralRule().opacity(0.35) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Stage4RecoveryProof: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            ScholiumPanelHeader(
                "Restore from Checkpoint",
                subtitle: "Synthetic comparison; no vault access"
            )
            ScholiumInlineStatus(
                "Current buffer is preserved",
                detail: "Restoring writes a new current source revision through conflict-aware recovery.",
                kind: .information
            )
            List {
                Text("Chapter milestone · 2026-07-28 18:40")
                Text("Before source-fidelity revision · 2026-07-27 11:05")
            }
            HStack {
                Button("Cancel", role: .cancel, action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Compare Selected") {}
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(width: 620, height: 440)
        .scholiumSurface(.denseEvidence)
        .accessibilityIdentifier("scholium.stage4.recovery")
    }
}

// MARK: - Multiwindow proof

private struct MultiwindowCompleteWindowProof: View {
    let windowSlot: DesignContractProofWindowRoute.Slot
    let scenario: DesignContractProofScenario
    let documentTextScale: CGFloat
    let usesLongCopy: Bool
    @State private var draft = ""
    @State private var localSheet = false
    @State private var localSearch = true

    var body: some View {
        Stage4WorkspaceShell {
            SidebarCutoverCatalog(
                scenario: windowSlot == .a ? .attentionOne : .attentionZero,
                height: 760
            )
        } document: {
            ZStack(alignment: .top) {
                Stage4DocumentPane(
                    title: "Window \(windowSlot.rawValue) · Independent document session",
                    state: "Window-local",
                    textScale: documentTextScale,
                    usesLongCopy: usesLongCopy,
                    inlineStatus: scenario == .windowAnchorRemoved
                        ? ("Anchor Removed", "The transient route closes without being reparented to another window.", .attention)
                        : nil,
                    draft: $draft
                )
                if scenario == .windowSearch && localSearch {
                    SearchPanelFixture(scenario: .searchRefreshing) {
                        localSearch = false
                    }
                    .padding(.top, ScholiumMetrics.Search.responsiveMargin)
                }
            }
        } apparatus: {
            Stage4ApparatusPane(title: "Window \(windowSlot.rawValue)") {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.sectionSpacing) {
                    ScholiumApparatusSection("IDENTITY") {
                        ScholiumApparatusReadingBlock(
                            label: "Owner",
                            text: "Stage 4 synthetic Window \(windowSlot.rawValue). Its presentation state is not shared with the paired window."
                        )
                    }
                    Button("Open Window-local Sheet") { localSheet = true }
                        .accessibilityIdentifier("scholium.stage4.localSheet.\(windowSlot.rawValue)")
                    Button("Reopen Window-local Search") { localSearch = true }
                        .accessibilityIdentifier("scholium.stage4.localSearch.\(windowSlot.rawValue)")
                }
            }
        }
        .onAppear {
            if scenario == .windowSheet { localSheet = true }
            if scenario == .windowAnchorRemoved { localSearch = false }
        }
        .sheet(isPresented: $localSheet) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                ScholiumPanelHeader(
                    "Window \(windowSlot.rawValue) Presentation",
                    subtitle: "Only this proof window owns this sheet"
                )
                Text("Closing the owner tears down this route. The paired window remains interactive and unchanged.")
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { localSheet = false }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(width: 520, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .scholiumSurface(.denseEvidence)
            .accessibilityIdentifier("scholium.stage4.windowLocalSheet.\(windowSlot.rawValue)")
        }
    }
}

#Preview("Stage 4 — Library") {
    DesignContractCompleteWindowProofs(route: .primary)
}

#Preview("Stage 4 — Search + Attention") {
    DesignContractCompleteWindowProofs(
        route: .init(slot: .a, initialProof: .searchAttention)
    )
}

#Preview("Stage 4 — Actions") {
    DesignContractCompleteWindowProofs(
        route: .init(slot: .a, initialProof: .actions)
    )
}

#Preview("Stage 4 — Document States") {
    DesignContractCompleteWindowProofs(
        route: .init(slot: .a, initialProof: .documentStates)
    )
}

#Preview("Stage 4 — Multiwindow") {
    DesignContractCompleteWindowProofs(
        route: .init(slot: .a, initialProof: .multiwindow)
    )
}
#endif
