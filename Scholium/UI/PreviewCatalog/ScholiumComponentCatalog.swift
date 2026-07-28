import ScholiumContracts
#if DEBUG
import SwiftUI

private struct ScholiumComponentCatalog: View {
    enum Scenario: String {
        case ready = "Ready"
        case empty = "Empty"
        case loading = "Loading"
        case error = "Error"
        case conflict = "Conflict"
        case longText = "Long Text"
    }

    let scenario: Scenario

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScholiumPanelHeader("Research Inspector", subtitle: scenario.rawValue)
                scenarioContent
            }
            .padding(24)
        }
        .frame(width: 520, height: 620)
        .scholiumSurface(.document)
    }

    @ViewBuilder
    private var scenarioContent: some View {
        switch scenario {
        case .ready:
            ScholiumInlineStatus("Index Current", detail: "All projections match the committed revision.", kind: .confirmed)
            sourceAndNoteRows
        case .empty:
            ScholiumEmptyState(
                title: "No Matching Notes",
                detail: "No title, path, or alias matches this query.",
                systemImage: "doc.text.magnifyingglass"
            )
        case .loading:
            ProgressView("Preparing the Triptych catalog…")
                .frame(maxWidth: .infinity, minHeight: 180)
        case .error:
            ScholiumInlineStatus(
                "Search Unavailable",
                detail: "The existing results remain unchanged. Retry when the index is available.",
                kind: .destructive
            )
        case .conflict:
            ScholiumInlineStatus(
                "This Note Changed on Disk",
                detail: "The editor buffer is preserved for comparison or recovery.",
                kind: .attention
            )
        case .longText:
            ScholiumInlineStatus(
                "A deliberately long status that verifies wrapping without truncating the researcher-visible recovery explanation",
                detail: "This deterministic preview includes mixed-language content 关于注意与显著性 and a long path so localization, text scaling, and narrow layouts remain inspectable.",
                kind: .agentAuthorship
            )
            sourceAndNoteRows
        }
    }

    private var sourceAndNoteRows: some View {
        Group {
            ScholiumSourceAnchorRow(
                title: "Attention and perceptual salience",
                location: "Analysis.md, line 42",
                detail: "Explicit support Connection",
                action: {}
            )
            ScholiumNoteRow(
                title: "A deliberately long mixed-language note title 关于注意与显著性",
                role: "Analysis",
                location: "Sources/Attention/Example.md",
                symbol: "doc.text"
            )
        }
    }
}

private struct LifecycleDestinationCatalog: View {
    enum Scenario: Equatable {
        case populated
        case loading
        case empty
        case error
        case longTitle
        case chinese
    }

    let scenario: Scenario

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(scenario == .chinese ? "Set Aside" : "Trash")
                .font(ScholiumInterfaceTypography.editorialLabel)
                .padding(.horizontal, ScholiumMetrics.Library.contentInset)
                .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
            if scenario == .loading {
                ProgressView("Loading…")
                    .padding(ScholiumMetrics.Library.contentInset)
            } else if scenario == .error {
                Label("The lifecycle listing is temporarily unavailable.", systemImage: "exclamationmark.triangle")
                    .font(ScholiumInterfaceTypography.metadata)
                    .padding(ScholiumMetrics.Library.contentInset)
            } else if items.isEmpty {
                Text("No notes")
                    .font(ScholiumInterfaceTypography.metadata)
                    .padding(ScholiumMetrics.Library.contentInset)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 0) {
                        NoteCardRow(
                            note: item.note,
                            isActive: false,
                            vaultRole: .topicKnowledge
                        )
                        Button { } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .frame(
                                    width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                                    height: ScholiumMetrics.Accessibility.preferredCustomTarget
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Put Back…")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 300, height: 380, alignment: .topLeading)
        .scholiumSurface(.navigation)
    }

    private var items: [LifecycleLocationItem] {
        switch scenario {
        case .loading, .empty, .error:
            []
        case .populated:
            [
                item(path: "Trash/Topics/Agency.md", title: "Agency"),
                item(path: "Trash/Analyses/Attention.md", title: "Attention and Salience"),
            ]
        case .longTitle:
            [
                item(
                    path: "Trash/Topics/Long Title.md",
                    title: "A deliberately long lifecycle title that must truncate before the Put Back action"
                ),
            ]
        case .chinese:
            [
                item(path: "Set Aside/Topics/注意与显著性.md", title: "关于注意、显著性与规范理由的长标题"),
                item(path: "Set Aside/Works/第三章.md", title: "第三章：拟议论证结构"),
            ]
        }
    }

    private func item(path: String, title: String) -> LifecycleLocationItem {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let document = NoteDocument(
            relativePath: path,
            rawContent: "---\ntitle: \"\(escapedTitle)\"\n---\n"
        )
        return LifecycleLocationItem(
            note: .unclassified(document),
            revision: document.fingerprint,
            noteID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
    }
}

/// D-120 Sidebar acceptance board. This is the production `SidebarView` with
/// disposable in-memory projections, so pinned Sections, disclosure, filters,
/// Location behavior, selection, typography, and accessibility are not
/// represented by a separate mock layout.
@MainActor
private struct SidebarCutoverCatalog: View {
    enum Scenario: Equatable {
        case standard
        case filteredLongCJK
        case empty
        case loading
        case error
        case rightToLeftLargeText
    }

    let scenario: Scenario
    private let vaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000120")!
    @StateObject private var controller: DiscoveryController
    @StateObject private var bibliography: RecommendedBibliographyController

    init(scenario: Scenario) {
        self.scenario = scenario
        var library = DiscoveryLibraryState()
        if scenario == .filteredLongCJK { library.filters.needsAttention = true }
        if scenario == .loading { library.locationIsLoading = true }
        if scenario == .error { library.locationError = "The source projection is temporarily unavailable." }

        let peripheral = WindowPeripheralPresentationState()
        let vaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000120")!
        peripheral.setExpandedFolders(
            ["Conceptual architecture", "Conceptual architecture/Current chapter"],
            in: LibraryDisclosureScope(vaultID: vaultID, locationScope: .workspace)
        )
        _controller = StateObject(wrappedValue: DiscoveryController(
            initialLibraryState: library,
            peripheralPresentation: peripheral
        ))
        _bibliography = StateObject(wrappedValue: RecommendedBibliographyController())
    }

    var body: some View {
        SidebarView(controller: controller, context: context)
            .frame(width: 300, height: 680, alignment: .topLeading)
            .environment(
                \.layoutDirection,
                scenario == .rightToLeftLargeText ? .rightToLeft : .leftToRight
            )
            .environment(
                \.dynamicTypeSize,
                scenario == .rightToLeftLargeText ? .accessibility3 : .large
            )
    }

    private var context: SidebarContext {
        SidebarContext(
            triptychName: scenario == .filteredLongCJK
                ? "Dissertation · 规范理由与注意"
                : "Dissertation",
            attentionItems: attentionItems,
            filteredNotes: notes,
            allNotes: notes,
            folders: folders,
            currentVaultID: vaultID,
            disclosureScope: LibraryDisclosureScope(
                vaultID: vaultID,
                locationScope: controller.library.locationScope
            ),
            selectedDocumentPath: notes.first?.relativePath,
            libraryFocusRequestGeneration: 0,
            currentVaultRole: .sourceCorpus,
            currentWorkspaceSlot: controller.library.workspaceSlot,
            noteLifecycleRequest: nil,
            canCreateNote: true,
            lifecycleMutationGeneration: 0,
            catalogIsAvailable: true,
            graphIsAvailable: true,
            tags: ["attention", "agency"],
            authors: ["Example Author"],
            years: [2024, 2026],
            propertyKeys: [],
            propertyValues: [:],
            resolvedIdentityPaths: Set(notes.map(\.relativePath)),
            bibliographyController: bibliography,
            notesAreOrdered: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            openAttention: {},
            selectLocationScope: { location in
                controller.synchronizeLibrarySelection(
                    workspaceSlot: controller.library.workspaceSlot,
                    location: location
                )
            },
            openNote: { _, _ in },
            selectWorkspaceVault: { slot in
                controller.synchronizeLibrarySelection(
                    workspaceSlot: slot,
                    location: controller.library.locationScope
                )
            },
            prepareLifecycle: { _ in },
            clearPreparedLifecycle: { _ in },
            createUntitledNote: { _ in },
            createUntitledFolder: { _ in },
            requestFolderLifecycle: { _ in },
            moveFolderToTrash: { _ in },
            copyRelativePath: { _ in },
            revealNote: { _ in },
            setAside: { _ in },
            moveToTrash: { _ in },
            deletePermanently: { _ in },
            classify: { _, _, _ in },
            openRecommendedAnalysis: { _ in },
            openRecommendedZoteroItem: { _ in },
            copyRecommendedBibliographyText: { _ in },
            repairRecommendedBibliographyMethod: {},
            revealCurrentVault: {},
            openSettings: {},
            selectSortOrder: { controller.selectSortOrder($0) },
            showError: { _ in }
        )
    }

    private var notes: [WindowDocumentLocation] {
        guard scenario != .empty, scenario != .loading, scenario != .error else { return [] }
        return [
            note(
                "papers/Conceptual architecture/Current chapter/Objections and replies/The value-first objection under delayed confirmation — a deliberately long mixed-language title 关于规范理由与可修正判断.md",
                title: "The value-first objection under delayed confirmation — 关于规范理由与可修正判断"
            ),
            note(
                "papers/Conceptual architecture/Current chapter/QA Autosave B.md",
                title: "QA Autosave B"
            ),
            note(
                "papers/Methods and source boundaries/Evidence is not connection.md",
                title: "Evidence is not connection"
            ),
            note("papers/Loose note.md", title: "Loose note"),
        ]
    }

    private var folders: [String] {
        guard !notes.isEmpty else { return [] }
        return [
            "papers/Conceptual architecture",
            "papers/Conceptual architecture/Current chapter",
            "papers/Conceptual architecture/Current chapter/Objections and replies",
            "papers/Methods and source boundaries",
            "papers/Earlier formulations",
        ]
    }

    private var attentionItems: [AttentionQueueItem] {
        (0..<7).map { index in
            AttentionQueueItem(
                kind: index.isMultiple(of: 2) ? .possibleOrphan : .malformedMetadata,
                severity: .warning,
                note: VaultNoteReference(
                    vaultID: vaultID,
                    vaultName: "Analyses",
                    vaultRole: .sourceCorpus,
                    relativePath: "papers/Conceptual architecture/Current chapter/QA \(index).md"
                ),
                message: "Disposable Preview Catalog issue \(index + 1)."
            )
        }
    }

    private func note(_ path: String, title: String) -> WindowDocumentLocation {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        return .unclassified(NoteDocument(
            relativePath: path,
            rawContent: "---\ntitle: \"\(escapedTitle)\"\n---\n"
        ))
    }
}

/// Native Attention acceptance board using the exact production task row and
/// the same standard-window geometry. It keeps deterministic state variants
/// available without opening a research Workspace or reconstructing source.
private struct AttentionWindowCatalog: View {
    enum Scenario: Equatable {
        case ready
        case loading
        case empty
        case stale
        case error
    }

    let scenario: Scenario
    @State private var query = ""
    @State private var kind: AttentionQueueKind?
    @State private var selectedItemID: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Analyses").font(ScholiumInterfaceTypography.rowTitle)
                        Text("All Notes")
                            .font(ScholiumInterfaceTypography.metadata)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Picker("Issue Type", selection: $kind) {
                        Text("All Issues").tag(AttentionQueueKind?.none)
                        ForEach(AttentionIssueGroup.allCases) { group in
                            Section(group.title) {
                                ForEach(group.kinds, id: \.self) { issueKind in
                                    Text(issueKind.displayName).tag(Optional(issueKind))
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 190)
                    Button {} label: {
                        Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                    }
                }
                TextField("Search Attention", text: $query)
                    .textFieldStyle(.roundedBorder)
                if scenario == .stale {
                    Label(
                        "Results may be out of date. Showing the last available tasks.",
                        systemImage: "clock.badge.exclamationmark"
                    )
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.attention.color)
                }
            }
            .padding(ScholiumGrid.Spacing.sectionSeparation)
            Divider()
            content
        }
        .frame(width: 420, height: 560)
        .scholiumSurface(.denseEvidence)
    }

    @ViewBuilder
    private var content: some View {
        switch scenario {
        case .loading:
            ProgressView("Loading Attention…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView(
                "No Attention Needed",
                systemImage: "checkmark.circle",
                description: Text("Scholium found no visible derived issues in this Scope.")
            )
        case .error:
            ContentUnavailableView {
                Label("Could Not Load Attention", systemImage: "exclamationmark.triangle")
            } description: {
                Text("The last trustworthy result is unavailable.")
            } actions: {
                Button("Retry") {}
            }
        case .ready, .stale:
            List(selection: $selectedItemID) {
                ForEach(AttentionIssueGroup.allCases) { group in
                    let groupedItems = items.filter(group.contains)
                    if !groupedItems.isEmpty {
                        Section(group.title) {
                            ForEach(groupedItems) { item in
                                AttentionQueueRow(
                                    item: item,
                                    noteTitle: noteTitle(for: item),
                                    locator: item.locator.map {
                                        "\($0.file):\($0.line)"
                                    } ?? item.note.relativePath,
                                    dismissalDays: 7,
                                    inspect: {},
                                    dismiss: { _ in },
                                    resynthesize: {},
                                    leaveUnchanged: {}
                                )
                                .tag(item.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var items: [AttentionQueueItem] {
        [
            ordinaryItem(
                .malformedMetadata,
                path: "Metadata/Long unresolved identity note.md",
                message: "Required identity fields could not be projected from exact YAML.",
                line: 3
            ),
            ordinaryItem(
                .brokenConnection,
                path: "Connections/Argument map.md",
                message: "One explicit Connection no longer resolves inside this Triptych.",
                line: 18
            ),
            materialChangedItem,
        ]
    }

    private func ordinaryItem(
        _ kind: AttentionQueueKind,
        path: String,
        message: String,
        line: Int
    ) -> AttentionQueueItem {
        AttentionQueueItem(
            kind: kind,
            severity: .warning,
            note: reference(path),
            message: message,
            locator: SourceLocator(file: path, line: line, column: 1)
        )
    }

    private var materialChangedItem: AttentionQueueItem {
        let material = reference("Materials/Source fidelity checklist.md")
        let context = MaterialChangedSinceUseAttentionContext(
            triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000120")!,
            recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000121")!,
            topicNoteID: UUID(uuidString: "00000000-0000-0000-0000-000000000122")!,
            materialNoteID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            material: material,
            recordedRevision: DocumentFingerprint(content: "before"),
            currentRevision: DocumentFingerprint(content: "after")
        )
        return AttentionQueueItem(
            kind: .materialChangedSinceUse,
            severity: .warning,
            note: reference("Topics/Research agency.md"),
            message: "A Material actually used by the completed Synthesize record changed.",
            materialChangedSinceUse: context
        )
    }

    private func reference(_ path: String) -> VaultNoteReference {
        VaultNoteReference(
            vaultID: UUID(uuidString: "00000000-0000-0000-0000-000000000120")!,
            vaultName: "Analyses",
            vaultRole: .sourceCorpus,
            relativePath: path
        )
    }

    private func noteTitle(for item: AttentionQueueItem) -> String {
        URL(fileURLWithPath: item.note.relativePath)
            .deletingPathExtension().lastPathComponent
    }
}

/// Native D-114 acceptance board for the Inspector component system. It uses
/// production Apparatus components but owns no application state or routing.
private struct InspectorConvergenceCatalog: View {
    enum Scenario: Equatable {
        case standard
        case narrow
        case longEnglish
        case mixedCJKAndEmpty
        case rightToLeft
        case syntheticLargeText
    }

    let scenario: Scenario
    @State private var selectedMode: ResearchInspectorMode

    init(
        scenario: Scenario,
        initialMode: ResearchInspectorMode = .overview
    ) {
        self.scenario = scenario
        _selectedMode = State(initialValue: initialMode)
    }

    private var width: CGFloat { scenario == .narrow ? 278 : 320 }

    var body: some View {
        VStack(spacing: 0) {
            ScholiumInspectorModeIndex(
                selectedMode: selectedMode,
                select: { selectedMode = $0 }
            )
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.sectionSpacing
                ) {
                    modeContent
                }
                .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
                .padding(.top, ScholiumMetrics.Apparatus.firstSectionSpacing)
                .padding(.bottom, ScholiumMetrics.Apparatus.bottomInset)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: width, height: 680, alignment: .topLeading)
        .scholiumSurface(.apparatus)
        .environment(
            \.layoutDirection,
            scenario == .rightToLeft ? .rightToLeft : .leftToRight
        )
        .environment(
            \.dynamicTypeSize,
            scenario == .syntheticLargeText ? .accessibility3 : .large
        )
    }

    @ViewBuilder
    private var modeContent: some View {
        switch selectedMode {
        case .overview:
            overviewContent
        case .connect:
            connectContent
        case .actions:
            actionsContent
        }
    }

    private var overviewContent: some View {
        Group {
            catalogAttentionSummary

            VStack(alignment: .leading, spacing: 0) {
                ScholiumApparatusSectionHeaderButton(
                    "ABOUT THIS ANALYSIS",
                    actionLabel: "Edit Properties",
                    systemImage: "slider.horizontal.3",
                    accessibilityIdentifier: "scholium.preview.about.edit",
                    action: {}
                )
                .padding(.bottom, ScholiumMetrics.Apparatus.sectionContentSpacing)

                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.readingBlockSpacing
                ) {
                    ScholiumApparatusFactGrid(facts: facts)
                    ScholiumApparatusReadingBlock(
                        label: readingLabel,
                        text: readingText
                    )
                }
            }

            if scenario == .longEnglish {
                failureState
            }
        }
    }

    private var connectContent: some View {
        Group {
            catalogConnectionGroup(
                "NEIGHBOR ANALYSES",
                clusters: [
                    (.supports, [
                        "Attention and practical commitment",
                        "Standards of provisional acceptance",
                    ]),
                    (.opposes, ["Immediate-result models of inquiry"]),
                ]
            )
            catalogConnectionGroup(
                "RELATED TOPICS",
                clusters: [
                    (.incompatible, ["Temporal structure of inquiry"]),
                ]
            )
            catalogConnectionGroup("RELATED WORKS", clusters: [])
        }
    }

    private var actionsContent: some View {
        Group {
            ScholiumApparatusSection("RESEARCH") {
                VStack(alignment: .leading, spacing: 0) {
                    InspectorCatalogActionButton(
                        "Discuss",
                        systemImage: "bubble.left.and.bubble.right",
                        action: {}
                    )
                    InspectorCatalogActionButton(
                        "Analyze",
                        systemImage: "doc.text.magnifyingglass",
                        action: {}
                    )
                }
            }
            ScholiumApparatusSection("REVIEW") {
                InspectorCatalogActionButton(
                    "Check Fidelity",
                    systemImage: "checkmark.seal",
                    detail: disabledDetail,
                    action: {}
                )
                .disabled(disabledDetail != nil)
            }
            ScholiumApparatusSection("RESEARCHER SKILLS") {
                InspectorCatalogActionButton(
                    "Counterexample Stress Test",
                    systemImage: "scope",
                    detail: "Tests the current argument without changing the note.",
                    action: {}
                )
            }
            ScholiumApparatusSection("JUDGMENT") {
                InspectorCatalogActionButton(
                    "Settle",
                    systemImage: "checkmark.circle",
                    action: {}
                )
            }
        }
    }

    private var catalogAttentionSummary: some View {
        Button(action: {}) {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.sectionContentSpacing
            ) {
                HStack(spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                    Text("NEEDS ATTENTION")
                        .scholiumApparatusHeadingStyle()
                    Spacer(minLength: ScholiumMetrics.Apparatus.iconToTextSpacing)
                    count(scenario == .longEnglish ? "2" : "0")
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                        .accessibilityHidden(true)
                }
                if scenario == .longEnglish {
                    Text("Unsupported field · Source access needs review")
                        .font(ScholiumInterfaceTypography.apparatusResearchContent)
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(ScholiumApparatusQuietRowButtonStyle(
            isHovering: false,
            minimumHeight: ScholiumMetrics.Apparatus.actionRowMinimumHeight
        ))
        .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
        .accessibilityLabel("Needs Attention")
        .accessibilityValue(scenario == .longEnglish ? "2 items" : "0 items")
    }

    private func catalogConnectionGroup(
        _ title: LocalizedStringResource,
        clusters: [(ScholiumConnectionGlyphKind, [String])]
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Apparatus.sectionContentSpacing
        ) {
            ScholiumApparatusRow(
                leading: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .accessibilityHidden(true)
                },
                content: {
                    Text(title)
                        .scholiumApparatusHeadingStyle()
                },
                trailing: {
                    count(clusters.reduce(0) { $0 + $1.1.count }.formatted())
                }
            )

            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.relationClusterSpacing
            ) {
                ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                    catalogConnectionCluster(kind: cluster.0, titles: cluster.1)
                }
            }
        }
    }

    private func catalogConnectionCluster(
        kind: ScholiumConnectionGlyphKind,
        titles: [String]
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: ScholiumMetrics.Apparatus.relationGlyphToTextSpacing
        ) {
            ScholiumConnectionGlyph(kind: kind)
                .frame(
                    width: ScholiumMetrics.Apparatus.relationGlyphSize,
                    height: ScholiumMetrics.Apparatus.relationGlyphSize
                )
                .frame(
                    width: ScholiumMetrics.Apparatus.relationGlyphColumnWidth,
                    height: ScholiumMetrics.Apparatus.relationRowMinimumHeight
                )

            VStack(alignment: .leading, spacing: 0) {
                ForEach(titles, id: \.self) { title in
                    Button(action: {}) {
                        Text(verbatim: title)
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(ScholiumApparatusQuietRowButtonStyle(
                        isHovering: false,
                        minimumHeight: ScholiumMetrics.Apparatus.relationRowMinimumHeight,
                        verticalInset: ScholiumMetrics.Apparatus.relationRowVerticalInset
                    ))
                    .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
                }
            }
        }
    }

    private var failureState: some View {
        ScholiumApparatusStateView(
            "Refresh Failed",
            detail: "The saved source changed while the relationship projection was being rebuilt. The previous projection remains visible and no research content was modified.",
            systemImage: "exclamationmark.triangle",
            density: .block
        ) {
            Button("Retry", action: {})
                .controlSize(.small)
        }
    }

    private func count(_ value: String) -> some View {
        Text(verbatim: value)
            .font(ScholiumInterfaceTypography.apparatusMetadata.monospacedDigit())
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
    }

    private var facts: [ScholiumApparatusFact] {
        switch scenario {
        case .mixedCJKAndEmpty:
            [
                .init(id: "kind", label: "类型", value: "章节"),
                .init(id: "authors", label: "作者", value: "崔宏卿"),
                .init(id: "venue", label: "出处", value: "博士论文"),
                .init(id: "series", label: "丛书", value: ""),
            ]
        case .rightToLeft:
            [
                .init(id: "kind", label: "النوع", value: "فصل"),
                .init(id: "authors", label: "المؤلف", value: "باحث تجريبي"),
                .init(id: "year", label: "السنة", value: "2026"),
            ]
        case .longEnglish:
            [
                .init(id: "kind", label: "Kind", value: "Edited book chapter"),
                .init(
                    id: "authors",
                    label: "Authors",
                    value: "Alexandra Montgomery-Wainwright and Bernard Williams"
                ),
                .init(
                    id: "venue",
                    label: "Venue",
                    value: "Proceedings of the International Society for the Study of Practical Reason"
                ),
            ]
        case .standard, .narrow, .syntheticLargeText:
            [
                .init(id: "kind", label: "Kind", value: "Chapter"),
                .init(id: "authors", label: "Authors", value: "Hongqing Cui"),
                .init(id: "venue", label: "Venue", value: "Dissertation"),
            ]
        }
    }

    private var readingLabel: String {
        scenario == .rightToLeft ? "النطاق" : "Scope"
    }

    private var readingText: String {
        switch scenario {
        case .mixedCJKAndEmpty:
            "考察恰当性理由如何影响研究者的实践选项空间。"
        case .rightToLeft:
            "مثال اتجاهي لفحص المحاذاة والقراءة دون تغيير ترتيب التصفح."
        default:
            "Whether fittingness reasons alter a researcher's practical option-space."
        }
    }

    private var disabledDetail: String? {
        scenario == .longEnglish
            ? "Save the current edit before checking fidelity."
            : nil
    }
}

/// A catalog-only native wrapper around the production Action row recipe. The
/// real Actions surface retains its feature-owned routing and focus behavior.
private struct InspectorCatalogActionButton: View {
    let title: LocalizedStringResource
    let systemImage: String
    let detail: String?
    let action: () -> Void

    @State private var isHovering = false

    init(
        _ title: LocalizedStringResource,
        systemImage: String,
        detail: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ScholiumApparatusActionRowContent(
                title: Text(title),
                systemImage: systemImage,
                detail: detail.flatMap { $0.isEmpty ? nil : Text($0) },
                showsChevron: true
            )
        }
        .buttonStyle(ScholiumApparatusQuietRowButtonStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
    }
}

private struct ScholiumMonoComparison: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(verbatim: "Monospace A/B Proof")
                    .font(.title2.weight(.semibold))
                Text(verbatim: "Production Victor Mono beside the macOS system monospace. Review at normal and 200% document text sizes.")
                    .foregroundStyle(.secondary)

                MonoComparisonScaleSection(title: "100%", scale: 1)
                MonoComparisonScaleSection(title: "200%", scale: 2)
            }
            .padding(24)
        }
        .frame(width: 920, height: 760)
        .scholiumSurface(.document)
    }
}

private struct MonoComparisonScaleSection: View {
    let title: String
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(ScholiumInterfaceTypography.sectionTitle)
            HStack(alignment: .top, spacing: 16) {
                MonoComparisonColumn(title: "Victor Mono", scale: scale, usesVictor: true)
                MonoComparisonColumn(title: "System Mono", scale: scale, usesVictor: false)
            }
        }
    }
}

private struct MonoComparisonColumn: View {
    let title: String
    let scale: CGFloat
    let usesVictor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(ScholiumInterfaceTypography.rowTitle)
            sample("Source", text: "research_unit:\n  completion: \"6/11\"", size: 14)
            sample("Code", text: "let claim = evidence.map(\\.source)", size: 13)
            sample("Diff", text: "+ Explicit premise\n− Unsupported inference", size: 13)
            sample("Revision", text: "c7f81d9a, 1,284 bytes", size: 11)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scholiumBoundary(
            .subtleBoundary,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func sample(_ label: String, text: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(.secondary)
            Text(text)
                .font(usesVictor
                    ? ScholiumTypography.swiftUIMonospaceFont(
                        size: size * scale,
                        relativeTo: .body
                    )
                    : .system(size: size * scale, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

private struct ScholarlyEditorialWorkspaceSlice: View {
    let width: CGFloat

    private var sidebarWidth: CGFloat { width < 1_000 ? 210 : 250 }
    private var inspectorWidth: CGFloat { width < 1_080 ? 230 : 280 }

    var body: some View {
        HStack(spacing: 0) {
            editorialSidebar
                .frame(width: sidebarWidth)

            editorialDocument
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            editorialInspector
                .frame(width: inspectorWidth)
        }
        .frame(width: width, height: 760)
        .scholiumSurface(.document)
    }

    private var editorialSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Scholium")
                .font(ScholiumInterfaceTypography.identity)
            Text(verbatim: "Triptych — Immediate Results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            HStack(spacing: 0) {
                roleSegment("Analyses", selected: true)
                roleSegment("Topics", selected: false)
                roleSegment("Works", selected: false)
            }
            .padding(.top, 18)

            editorialLabel("LIBRARY")
                .padding(.top, 24)

            Label("On Immediate Results", systemImage: "folder")
                .font(ScholiumInterfaceTypography.rowTitle)
                .padding(.top, 10)

            VStack(spacing: 3) {
                previewNote("Preface", detail: "On the hunger for quick answers", selected: false)
                previewNote(
                    "I. The Seduction of Immediate Results",
                    detail: "Why we overvalue speed and mistake motion for progress.",
                    selected: true
                )
                previewNote("II. The Slow Interior", detail: "What cannot be seen cannot be hurried.", selected: false)
                previewNote("III. The Patient Practice", detail: "Discipline as a wager on unseen work.", selected: false)
            }
            .padding(.top, 8)

            Spacer()

            editorialLabel("TAGS")
            Text(verbatim: "attention, learning, uncertainty")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .scholiumSurface(.navigation)
        .overlay(alignment: .trailing) { ScholiumStructuralRule(orientation: .vertical) }
    }

    private var editorialDocument: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Analyses", systemImage: "book")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(verbatim: "/").foregroundStyle(.tertiary)
                Text(verbatim: "I. The Seduction of Immediate Results")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 24)
            .frame(height: 48)
            .overlay(alignment: .bottom) { ScholiumStructuralRule() }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        Text(verbatim: "Analysis")
                            .font(ScholiumInterfaceTypography.editorialLabel)
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Text(verbatim: "Properties")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: "6/11")
                            .font(.caption.weight(.medium).monospacedDigit())
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .scholiumEditorialSurface(
                        .apparatus,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )

                    Text(verbatim: "I. The Seduction of Immediate Results")
                        .font(ScholiumInterfaceTypography.documentTitle)
                        .fixedSize(horizontal: false, vertical: true)

                    ScholiumStructuralRule()

                    Text(verbatim: "Modern life trains us to expect visible results almost immediately. A message is delivered in seconds, but this speed quietly changes our sense of how long worthwhile work should take.")
                    Text(verbatim: "Serious learning does not obey this logic. Research advances through failed specifications, incomplete drafts, and conversations whose value becomes clear only months later.")
                    Text(verbatim: "哲学研究的进展并不总能立即显现。概念之间的张力、反例与修订，需要在缓慢而持续的阅读中逐渐成形。")
                }
                .font(ScholiumTypography.swiftUIReadingFont(size: 12, relativeTo: .body))
                .lineSpacing(5)
                .padding(.horizontal, width < 1_000 ? 28 : 52)
                .padding(.vertical, 26)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

        }
        .scholiumSurface(.document)
    }

    private var editorialInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text(verbatim: "Overview")
                    .font(ScholiumInterfaceTypography.apparatusTitle)
                Text(verbatim: "Connect")
                    .font(ScholiumInterfaceTypography.apparatusTitle)
                    .foregroundStyle(.secondary)
                Text(verbatim: "Actions")
                    .font(ScholiumInterfaceTypography.apparatusTitle)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .overlay(alignment: .bottom) { ScholiumStructuralRule() }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inspectorSection("LINKS TO THIS NOTE", count: "3")
                    inspectorLink("II. The Slow Interior")
                    inspectorLink("IV. Feedback and Delay")
                    inspectorLink("On Patience in Practice")

                    inspectorSection("ABOUT", count: nil)
                    inspectorFact("Completion", "6/11")
                    inspectorFact("Authors", "M. Example and 李明")
                    inspectorFact("Type", "Book")

                    inspectorSection("TAGS", count: "5")
                    Text(verbatim: "motivation  progress  feedback\nlearning  uncertainty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .scholiumSurface(.apparatus)
        .overlay(alignment: .leading) { ScholiumStructuralRule(orientation: .vertical) }
    }

    private func roleSegment(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(selected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                selected ? ScholiumColorRole.surfaceBackground.color : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    private func previewNote(_ title: String, detail: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(ScholiumInterfaceTypography.noteTitle)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(2)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selected ? ScholiumColorRole.raisedSurfaceBackground.color : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(ScholiumColorRole.accent.color).frame(width: 3)
            }
        }
    }

    private func editorialLabel(_ title: String) -> some View {
        Text(title)
            .font(ScholiumInterfaceTypography.editorialLabel)
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func inspectorSection(_ title: String, count: String?) -> some View {
        HStack {
            editorialLabel(title)
            Spacer()
            if let count { Text(count).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(.top, 4)
    }

    private func inspectorLink(_ title: String) -> some View {
        Label(title, systemImage: "doc.text")
            .font(ScholiumInterfaceTypography.noteTitle)
            .lineLimit(2)
    }

    private func inspectorFact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.caption)
    }
}

#Preview("Ready") {
    ScholiumComponentCatalog(scenario: .ready)
}

#Preview("Empty") {
    ScholiumComponentCatalog(scenario: .empty)
}

#Preview("Loading") {
    ScholiumComponentCatalog(scenario: .loading)
}

#Preview("Error") {
    ScholiumComponentCatalog(scenario: .error)
}

#Preview("Conflict") {
    ScholiumComponentCatalog(scenario: .conflict)
}

#Preview("Long Text - Dark") {
    ScholiumComponentCatalog(scenario: .longText)
        .preferredColorScheme(.dark)
}

#Preview("Increased Contrast") {
    ScholiumComponentCatalog(scenario: .ready)
        .environment(
            \.scholiumVisualEnvironmentOverride,
            .init(increasedContrast: true)
        )
}

#Preview("Reduced Transparency") {
    ScholiumComponentCatalog(scenario: .ready)
        .environment(
            \.scholiumVisualEnvironmentOverride,
            .init(reduceTransparency: true)
        )
}

#Preview("Reduced Motion") {
    ScholiumComponentCatalog(scenario: .ready)
        .environment(
            \.scholiumVisualEnvironmentOverride,
            .init(reduceMotion: true)
        )
}

#Preview("Lifecycle Destination — Populated") {
    LifecycleDestinationCatalog(scenario: .populated)
}

#Preview("Lifecycle Destination — Loading") {
    LifecycleDestinationCatalog(scenario: .loading)
}

#Preview("Lifecycle Destination — Empty") {
    LifecycleDestinationCatalog(scenario: .empty)
}

#Preview("Lifecycle Destination — Error") {
    LifecycleDestinationCatalog(scenario: .error)
}

#Preview("Lifecycle Destination — Long Title") {
    LifecycleDestinationCatalog(scenario: .longTitle)
}

#Preview("Lifecycle Destination — 简体中文") {
    LifecycleDestinationCatalog(scenario: .chinese)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("Sidebar D-120 — 300 pt") {
    SidebarCutoverCatalog(scenario: .standard)
}

#Preview("Sidebar D-120 — Filter + Long CJK") {
    SidebarCutoverCatalog(scenario: .filteredLongCJK)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("Sidebar D-120 — Empty") {
    SidebarCutoverCatalog(scenario: .empty)
}

#Preview("Sidebar D-120 — Loading") {
    SidebarCutoverCatalog(scenario: .loading)
}

#Preview("Sidebar D-120 — Error") {
    SidebarCutoverCatalog(scenario: .error)
}

#Preview("Sidebar D-120 — RTL + Large Text") {
    SidebarCutoverCatalog(scenario: .rightToLeftLargeText)
}

#Preview("Attention D-120 — Ready") {
    AttentionWindowCatalog(scenario: .ready)
}

#Preview("Attention D-120 — Loading") {
    AttentionWindowCatalog(scenario: .loading)
}

#Preview("Attention D-120 — Empty") {
    AttentionWindowCatalog(scenario: .empty)
}

#Preview("Attention D-120 — Stale") {
    AttentionWindowCatalog(scenario: .stale)
}

#Preview("Attention D-120 — Error") {
    AttentionWindowCatalog(scenario: .error)
}

#Preview("Inspector D-114 — 320 pt") {
    InspectorConvergenceCatalog(scenario: .standard)
}

#Preview("Inspector D-114 — 278 pt") {
    InspectorConvergenceCatalog(scenario: .narrow)
}

#Preview("Inspector D-114 — Long and Disabled") {
    InspectorConvergenceCatalog(
        scenario: .longEnglish,
        initialMode: .actions
    )
}

#Preview("Inspector D-114 — Long Refresh Failure") {
    InspectorConvergenceCatalog(scenario: .longEnglish)
}

#Preview("Inspector D-114 — 中英与空字段") {
    InspectorConvergenceCatalog(scenario: .mixedCJKAndEmpty)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("Inspector D-114 — RTL") {
    InspectorConvergenceCatalog(
        scenario: .rightToLeft,
        initialMode: .connect
    )
        .environment(\.locale, Locale(identifier: "ar"))
}

#Preview("Inspector D-114 — Synthetic Large Text Stress") {
    InspectorConvergenceCatalog(
        scenario: .syntheticLargeText,
        initialMode: .actions
    )
}

#Preview("Victor Mono vs System Mono") {
    ScholiumMonoComparison()
}

#endif
