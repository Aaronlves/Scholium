import ScholiumContracts
import SwiftUI

struct ResearchRecordBrowserContext {
    let setPinned: @MainActor (UUID, Bool) async throws -> PortableResearchRecord
    let setRecommendationDisposition: @MainActor (
        UUID,
        UUID,
        ResearchLiteratureRecommendationDispositionStatus
    ) async throws -> PortableResearchRecord
    let setRecommendationNote: @MainActor (
        UUID,
        UUID,
        String?
    ) async throws -> PortableResearchRecord
    let saveEvaluation: @MainActor (
        UUID,
        ResearcherEvaluationDraft,
        UUID?,
        DocumentFingerprint
    ) async throws -> PortableResearchRecord
    let clearEvaluation: @MainActor (
        UUID,
        UUID,
        DocumentFingerprint
    ) async throws -> PortableResearchRecord
    let saveMethodFeedback: @MainActor (
        UUID,
        ResearchMethodFeedbackDraft,
        UUID?,
        DocumentFingerprint
    ) async throws -> PortableResearchRecord
    let clearMethodFeedback: @MainActor (
        UUID,
        UUID,
        DocumentFingerprint
    ) async throws -> PortableResearchRecord
    let startMethodImprovement: @MainActor (UUID) async throws
        -> ResearchAgentHandoff
    let deletePermanently: @MainActor (UUID) async throws -> Void
    let comparison: @MainActor (
        UUID,
        UUID
    ) async throws -> ResearchRecordComparison
    let openNote: @MainActor (UUID, VaultQualifiedNoteID, Int?) -> Void
}

struct ResearchRecordBrowserView: View {
    let model: ResearchRecordBrowserModel
    let triptychName: String
    let loadIssues: [String]
    let context: ResearchRecordBrowserContext

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if !loadIssues.isEmpty {
                ResearchRecordsLoadIssuesBanner(issues: loadIssues)
                ScholiumStructuralRule()
            }
            ResearchRecordTwoColumnView(
                model: model,
                triptychName: triptychName,
                context: context
            )
        }
        .scholiumSurface(.document)
        .tint(ScholiumColorRole.accent.color)
        .onDisappear { model.cancelComparison() }
        .alert(
            model.isComparisonError
                ? "Comparison Unavailable"
                : "Research Records Unavailable",
            isPresented: $model.isShowingError
        ) {
            Button("Dismiss", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage)
        }
    }
}

private struct ResearchRecordsLoadIssuesBanner: View {
    let issues: [String]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                ForEach(issues, id: \.self) { issue in
                    Text(issue)
                        .textSelection(.enabled)
                }
            }
            .font(ScholiumInterfaceTypography.metadata)
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
        } label: {
            Label(
                "Some Research Records Could Not Be Loaded",
                systemImage: "exclamationmark.triangle"
            )
            .font(ScholiumInterfaceTypography.rowTitle)
        }
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
        .scholiumSurface(.denseEvidence)
        .accessibilityIdentifier("scholium.researchRecords.issues")
    }
}

private enum ResearchRecordLayout {
    static let listMinimumWidth: CGFloat = 224
    static let listIdealWidth: CGFloat = 244
    static let listMaximumWidth: CGFloat = 268
    static let readingMeasure: CGFloat = 720
}

private struct ResearchRecordTwoColumnView: View {
    let model: ResearchRecordBrowserModel
    let triptychName: String
    let context: ResearchRecordBrowserContext

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ResearchRecordsViewIndex(model: model)
                ScholiumStructuralRule()
                Group {
                    switch model.viewKind {
                    case .records:
                        ResearchRecordListPane(
                            model: model,
                            triptychName: triptychName,
                            context: context,
                            opensSelection: nil
                        )
                    case .recommendations:
                        ResearchLiteratureRecommendationListPane(
                            model: model,
                            triptychName: triptychName,
                            context: context
                        )
                    }
                }
            }
            .frame(
                minWidth: ResearchRecordLayout.listMinimumWidth,
                idealWidth: ResearchRecordLayout.listIdealWidth,
                maxWidth: ResearchRecordLayout.listMaximumWidth,
                maxHeight: .infinity
            )
            .scholiumSurface(.navigation)

            Group {
                switch model.viewKind {
                case .records:
                    ResearchRecordSelectedDetail(model: model, context: context)
                case .recommendations:
                    ResearchLiteratureRecommendationSelectedDetail(model: model, context: context)
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("scholium.researchRecords.split")
    }
}

private struct ResearchRecordsViewIndex: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var focusedView: ResearchRecordsViewKind?

    let model: ResearchRecordBrowserModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ResearchRecordsViewKind.allCases, id: \.self) { viewKind in
                ResearchRecordsViewIndexButton(
                    viewKind: viewKind,
                    unprocessedCount: model.unprocessedRecommendationCount,
                    isSelected: model.viewKind == viewKind,
                    focusedView: $focusedView,
                    select: { model.viewKind = viewKind },
                    move: { moveFocus(from: viewKind, direction: $0) }
                )
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
        .accessibilityIdentifier("scholium.researchRecords.view")
    }

    private func moveFocus(
        from viewKind: ResearchRecordsViewKind,
        direction: MoveCommandDirection
    ) {
        let views = ResearchRecordsViewKind.allCases
        guard let index = views.firstIndex(of: viewKind) else { return }
        let visualStep: Int
        switch direction {
        case .left:
            visualStep = layoutDirection == .leftToRight ? -1 : 1
        case .right:
            visualStep = layoutDirection == .leftToRight ? 1 : -1
        default:
            return
        }
        let nextIndex = (index + visualStep + views.count) % views.count
        let nextView = views[nextIndex]
        model.viewKind = nextView
        focusedView = nextView
    }
}

private struct ResearchRecordsViewIndexButton: View {
    @State private var isHovering = false

    let viewKind: ResearchRecordsViewKind
    let unprocessedCount: Int
    let isSelected: Bool
    let focusedView: FocusState<ResearchRecordsViewKind?>.Binding
    let select: () -> Void
    let move: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: select) {
            Text(title)
                .font(
                    isSelected
                        ? ScholiumInterfaceTypography.apparatusModeSelected
                        : ScholiumInterfaceTypography.apparatusMode
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ScholiumMetrics.Apparatus.headerHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable()
        .focused(focusedView, equals: viewKind)
        .foregroundStyle(
            isSelected || isHovering
                ? ScholiumColorRole.primaryText.color
                : ScholiumColorRole.secondaryText.color
        )
        .overlay(alignment: .bottom) {
            ScholiumEditorialIndexUnderline(
                isSelected: isSelected,
                isHovering: isHovering,
                width: ScholiumMetrics.Apparatus.selectedModeIndicatorWidth,
                height: ScholiumMetrics.Apparatus.selectedModeIndicatorHeight
            )
        }
        .onHover { isHovering = $0 }
        .onMoveCommand(perform: move)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier(
            "scholium.researchRecords.view.\(viewKind.rawValue)"
        )
    }

    private var title: String {
        switch viewKind {
        case .records:
            "Records"
        case .recommendations:
            "Recommendations (\(unprocessedCount))"
        }
    }
}

private struct ResearchRecordsScopeMenu: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        Menu {
            if model.canScopeToNote {
                scopeChoice("This Note", value: .thisNote)
            }
            scopeChoice("Triptych", value: .triptych)
        } label: {
            Text(scopeTitle)
                .font(ScholiumInterfaceTypography.apparatusModeSelected)
                .foregroundStyle(ScholiumColorRole.accent.color)
                .lineLimit(1)
                .frame(
                    minHeight: ScholiumMetrics.Accessibility.minimumCustomTarget,
                    alignment: .leading
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .focusable()
        .tint(ScholiumColorRole.accent.color)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Scope")
        .accessibilityValue(scopeTitle)
        .accessibilityIdentifier("scholium.researchRecords.scope")
    }

    @ViewBuilder
    private func scopeChoice(
        _ title: String,
        value: ResearchRecordsScope
    ) -> some View {
        Button {
            model.scope = value
        } label: {
            if model.scope == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var scopeTitle: String {
        switch model.scope {
        case .thisNote:
            "This Note"
        case .triptych:
            "Triptych"
        }
    }
}

private struct ResearchRecordsListContext: View {
    let model: ResearchRecordBrowserModel
    let triptychName: String
    let count: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            ResearchRecordsScopeMenu(model: model)
            Text("·")
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.mutedText.color)
                .accessibilityHidden(true)
            Text(triptychName)
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
            Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
            count
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct ResearchRecordsSearchField: View {
    let prompt: String
    @Binding var text: String
    let identifier: String

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: "magnifyingglass")
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                        .frame(
                            minWidth: ScholiumMetrics.Accessibility.minimumCustomTarget,
                            minHeight: ScholiumMetrics.Accessibility.minimumCustomTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
        .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
        .background(
            ScholiumColorRole.surfaceBackground.color,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
        .scholiumBoundary(
            .subtleBoundary,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
    }
}

/// One ink-first action treatment shared by both Research Records views. It
/// keeps native Button behavior while avoiding a second bezeled visual system
/// inside the editorial reading plane.
private struct ResearchRecordActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    let title: String
    let systemImage: String
    let role: ButtonRole?
    let identifier: String
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        identifier: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Image(systemName: systemImage)
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(actionColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(ScholiumInterfaceTypography.apparatusActionTitle)
                    .foregroundStyle(actionColor)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
            .contentShape(Rectangle())
            .background(
                isHovering || isFocused
                    ? ScholiumColorRole.raisedSurfaceBackground.color
                    : Color.clear,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    actionColor.opacity(isFocused ? 0.72 : 0),
                    lineWidth: 1
                )
            }
            .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityIdentifier(identifier)
    }

    private var actionColor: Color {
        role == .destructive
            ? ScholiumColorRole.destructive.color
            : ScholiumColorRole.primaryText.color
    }
}

private struct ResearchRecordIdentityValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumGrid.Spacing.labelAccessoryGap
        ) {
            Text(label)
                .font(ScholiumInterfaceTypography.editorialLabel)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Text(value)
                .font(ScholiumTypography.swiftUIRevisionIdentity())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, ScholiumGrid.Spacing.nestedContentInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResearchRecordSelectedDetail: View {
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    var body: some View {
        if let record = model.selectedRecord {
            ResearchRecordDetailView(record: record, model: model, context: context)
        } else {
            ContentUnavailableView(
                "Select a Research Record",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose a finished Discussion or Action from the record list.")
            )
        }
    }
}

private struct ResearchRecordListPane: View {
    let model: ResearchRecordBrowserModel
    let triptychName: String
    let context: ResearchRecordBrowserContext
    let opensSelection: ((UUID) -> Void)?
    @State private var showsFilters = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ResearchRecordFilterControls(
                model: model,
                triptychName: triptychName,
                showsFilters: $showsFilters
            )
            ScholiumStructuralRule()
            if model.visibleEntries.isEmpty {
                ResearchRecordEmptyResults(model: model)
            } else {
                List(model.visibleEntries, selection: $model.selectedRecordID) { entry in
                    ResearchRecordListRow(
                        id: entry.id,
                        contextTitle: entry.contextTitle,
                        actionID: entry.actionID,
                        finishedAt: entry.finishedAt,
                        noteTitles: entry.noteParticipants.map(\.title),
                        authorParticipants: entry.authorParticipants,
                        isPinned: entry.isPinned,
                        isPinning: model.pinningRecordIDs.contains(entry.id)
                            || model.mutatingRecordIDs.contains(entry.id),
                        select: {
                            model.select(entry.id)
                            opensSelection?(entry.id)
                        },
                        togglePin: {
                            Task {
                                await model.setPinned(
                                    recordID: entry.id,
                                    update: context.setPinned
                                )
                            }
                        }
                    )
                    .tag(entry.id)
                    .listRowInsets(
                        EdgeInsets(
                            top: ScholiumGrid.Spacing.opticalAlignmentAdjustment,
                            leading: ScholiumGrid.Spacing.inlineControlGap,
                            bottom: ScholiumGrid.Spacing.opticalAlignmentAdjustment,
                            trailing: ScholiumGrid.Spacing.inlineControlGap
                        )
                    )
                    .listRowBackground(
                        ScholiumColorRole.navigationSurfaceBackground.color
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Research Records")
                .accessibilityIdentifier("scholium.researchRecord.list")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scholiumSurface(.navigation)
    }
}

private struct ResearchRecordFilterControls: View {
    let model: ResearchRecordBrowserModel
    let triptychName: String
    @Binding var showsFilters: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            ResearchRecordsListContext(
                model: model,
                triptychName: triptychName,
                count: recordCountText
            )
            ResearchRecordsSearchField(
                prompt: "Search records",
                text: $model.searchText,
                identifier: "scholium.researchRecord.search"
            )
            DisclosureGroup("Filters", isExpanded: $showsFilters) {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    ResearchRecordDatePicker(model: model)
                    ResearchRecordSkillPicker(model: model)
                    ResearchRecordActionPicker(model: model)
                    ResearchRecordParticipantPicker(model: model)
                    Button("Clear Filters") { model.clearAllFilters() }
                        .buttonStyle(.borderless)
                }
                .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
    }

    private var recordCountText: Text {
        let count = model.visibleEntries.count
        return count == 1
            ? Text("\(count) record")
            : Text("\(count) records")
    }
}

private struct ResearchLiteratureRecommendationListPane: View {
    let model: ResearchRecordBrowserModel
    let triptychName: String
    let context: ResearchRecordBrowserContext

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ResearchLiteratureRecommendationFilterControls(
                model: model,
                triptychName: triptychName
            )
            ScholiumStructuralRule()
            if model.visibleRecommendationGroups.isEmpty {
                ResearchLiteratureRecommendationEmptyResults(model: model)
            } else {
                List(selection: $model.selectedRecommendationID) {
                    ForEach(model.visibleRecommendationGroups) { group in
                        if group.displaysSharedIdentityHeader {
                            Section {
                                recommendationRows(
                                    in: group,
                                    showsLiteratureTitle: false
                                )
                            } header: {
                                Text(group.title)
                                    .lineLimit(2)
                                    .textCase(nil)
                            }
                        } else {
                            recommendationRows(
                                in: group,
                                showsLiteratureTitle: true
                            )
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Literature Recommendations")
                .accessibilityIdentifier("scholium.researchRecommendations.list")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scholiumSurface(.navigation)
    }

    @ViewBuilder
    private func recommendationRows(
        in group: ResearchLiteratureRecommendationGroup,
        showsLiteratureTitle: Bool
    ) -> some View {
        ForEach(group.occurrences) { occurrence in
            ResearchLiteratureRecommendationListRow(
                occurrence: occurrence,
                showsLiteratureTitle: showsLiteratureTitle,
                isMutating: model.mutatingRecommendationIDs.contains(
                    occurrence.id
                ),
                select: {
                    model.selectRecommendation(occurrence.id)
                },
                setHandled: { isHandled in
                    Task {
                        await model.setRecommendationDisposition(
                            occurrenceID: occurrence.id,
                            status: isHandled ? .handled : .unprocessed,
                            update: context.setRecommendationDisposition
                        )
                    }
                }
            )
            .tag(occurrence.id)
            .listRowInsets(
                EdgeInsets(
                    top: ScholiumGrid.Spacing.labelAccessoryGap,
                    leading: ScholiumGrid.Spacing.inlineControlGap,
                    bottom: ScholiumGrid.Spacing.labelAccessoryGap,
                    trailing: ScholiumGrid.Spacing.inlineControlGap
                )
            )
            .listRowBackground(
                ScholiumColorRole.navigationSurfaceBackground.color
            )
        }
    }
}

private struct ResearchLiteratureRecommendationFilterControls: View {
    let model: ResearchRecordBrowserModel
    let triptychName: String

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            ResearchRecordsListContext(
                model: model,
                triptychName: triptychName,
                count: recommendationCountText
            )
            ResearchRecordsSearchField(
                prompt: "Search recommendations",
                text: $model.recommendationSearchText,
                identifier: "scholium.researchRecommendations.search"
            )
            Picker("Status", selection: $model.recommendationFilter) {
                Text("Unprocessed").tag(ResearchLiteratureRecommendationFilter.unprocessed)
                Text("Handled").tag(ResearchLiteratureRecommendationFilter.handled)
                Text("All").tag(ResearchLiteratureRecommendationFilter.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("scholium.researchRecommendations.status")
        }
        .controlSize(.small)
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
    }

    private var recommendationCountText: Text {
        let count = model.visibleRecommendationGroups.reduce(0) {
            $0 + $1.occurrences.count
        }
        return count == 1
            ? Text("\(count) recommendation")
            : Text("\(count) recommendations")
    }
}

private struct ResearchLiteratureRecommendationEmptyResults: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        ContentUnavailableView(
            model.recommendationFilter == .unprocessed
                ? "No Unprocessed Recommendations"
                : "No Matching Recommendations",
            systemImage: "books.vertical",
            description: Text(emptyDescription)
        )
        .overlay(alignment: .bottom) {
            if !model.recommendationSearchText.isEmpty
                || model.recommendationFilter != .unprocessed {
                Button("Clear Filters") { model.clearRecommendationFilters() }
                    .padding(.bottom, ScholiumGrid.Spacing.regionContentInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDescription: String {
        if model.recommendationFilter == .unprocessed,
           model.recommendationSearchText.isEmpty {
            return "Analyze Records in this scope contain no reading leads awaiting handling."
        }
        return "Clear the search or choose another handling status."
    }
}

private struct ResearchLiteratureRecommendationListRow: View {
    let occurrence: ResearchLiteratureRecommendationOccurrence
    let showsLiteratureTitle: Bool
    let isMutating: Bool
    let select: () -> Void
    let setHandled: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
                    Text(
                        showsLiteratureTitle
                            ? occurrence.displayTitle
                            : occurrence.contextTitle
                    )
                        .font(ScholiumInterfaceTypography.rowTitle)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsLiteratureTitle {
                        Text(occurrence.contextTitle)
                            .font(ScholiumInterfaceTypography.metadata)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                            .lineLimit(1)
                    }
                    Text(
                        occurrence.parentRecord.finishedAt,
                        format: .dateTime.year().month().day()
                    )
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle(
                "Handled",
                isOn: Binding(
                    get: {
                        occurrence.recommendation.disposition.status == .handled
                    },
                    set: setHandled
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(isMutating)
            .accessibilityIdentifier(
                "scholium.researchRecommendation.rowHandled.\(occurrence.recommendation.id.uuidString)"
            )
            .accessibilityValue(
                occurrence.recommendation.disposition.status == .handled
                    ? "Handled"
                    : "Unprocessed"
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "scholium.researchRecommendation.row.\(occurrence.recommendation.id.uuidString)"
        )
    }
}

private struct ResearchLiteratureRecommendationSelectedDetail: View {
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    var body: some View {
        if let occurrence = model.selectedRecommendationOccurrence {
            ResearchLiteratureRecommendationDetailView(
                occurrence: occurrence,
                model: model,
                context: context
            )
            .id(occurrence.id)
        } else {
            ContentUnavailableView(
                "Select a Literature Recommendation",
                systemImage: "books.vertical",
                description: Text("Choose a reading lead from an Analyze Research Record.")
            )
        }
    }
}

private struct ResearchLiteratureRecommendationDetailView: View {
    let occurrence: ResearchLiteratureRecommendationOccurrence
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext
    @State private var isEditingNote = false
    @State private var noteDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text(occurrence.displayTitle)
                        .font(ScholiumInterfaceTypography.documentTitle)
                        .accessibilityHeading(.h1)
                    if let title = occurrence.recommendation.title,
                       title != occurrence.recommendation.rawCitation {
                        Text(occurrence.recommendation.rawCitation)
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                            .textSelection(.enabled)
                    }
                }
                ScholiumStructuralRule()
                handlingControls
                recommendationIdentity
                ScholiumStructuralRule()
                recommendationReason
                ScholiumStructuralRule()
                recommendationProvenance
                ScholiumStructuralRule()
                researcherNote
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: ResearchRecordLayout.readingMeasure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scholiumSurface(.document)
        .accessibilityIdentifier("scholium.researchRecommendation.detail")
        .sheet(isPresented: $isEditingNote) {
            ResearchLiteratureRecommendationNoteSheet(
                draft: $noteDraft,
                save: { note in
                    try await model.setRecommendationNote(
                        occurrenceID: occurrence.id,
                        note: note,
                        update: context.setRecommendationNote
                    )
                },
                dismiss: { isEditingNote = false }
            )
        }
    }

    private var handlingControls: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Toggle(
                "Handled",
                isOn: Binding(
                    get: {
                        occurrence.recommendation.disposition.status == .handled
                    },
                    set: { isHandled in
                        Task {
                            await model.setRecommendationDisposition(
                                occurrenceID: occurrence.id,
                                status: isHandled ? .handled : .unprocessed,
                                update: context.setRecommendationDisposition
                            )
                        }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .disabled(model.mutatingRecommendationIDs.contains(occurrence.id))
            .accessibilityIdentifier(
                "scholium.researchRecommendation.handled.\(occurrence.recommendation.id.uuidString)"
            )
            Text(
                "Handled means only that you have processed this reading lead. It does not mean read, accepted, cited, verified, or endorsed."
            )
            .font(ScholiumInterfaceTypography.metadata)
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
        }
    }

    @ViewBuilder
    private var recommendationIdentity: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            if !occurrence.recommendation.authors.isEmpty {
                LabeledContent(
                    "Authors",
                    value: occurrence.recommendation.authors.formatted()
                )
            }
            if let year = occurrence.recommendation.year {
                LabeledContent("Year", value: String(year))
            }
            if let doi = occurrence.recommendation.doi {
                LabeledContent("DOI") {
                    Text(doi).textSelection(.enabled)
                }
            }
            if let zoteroItemKey = occurrence.recommendation.zoteroItemKey {
                LabeledContent("Zotero item key") {
                    Text(zoteroItemKey).textSelection(.enabled)
                }
            }
        }
        .font(ScholiumInterfaceTypography.apparatusBody)
    }

    private var recommendationReason: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Why It Was Recommended")
                .font(ScholiumInterfaceTypography.sectionTitle)
                .accessibilityHeading(.h2)
            Text(occurrence.recommendation.reason)
                .font(ScholiumInterfaceTypography.apparatusResearchContent)
                .textSelection(.enabled)
            if let uncertainty = occurrence.recommendation.uncertainty {
                LabeledContent("Uncertainty") {
                    Text(uncertainty).textSelection(.enabled)
                }
            }
            if !occurrence.recommendation.sourceLocators.isEmpty {
                Text("Discovery Locators")
                    .font(ScholiumInterfaceTypography.editorialLabel)
                ForEach(
                    Array(occurrence.recommendation.sourceLocators.enumerated()),
                    id: \.offset
                ) { _, locator in
                    Text(locator).textSelection(.enabled)
                }
            }
        }
    }

    private var recommendationProvenance: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Provenance")
                .font(ScholiumInterfaceTypography.sectionTitle)
                .accessibilityHeading(.h2)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    provenanceActions
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    provenanceActions
                }
            }
            if let source = occurrence.parentRecord.sourceReference {
                LabeledContent("Analyzed source", value: source.displayName)
                ResearchRecordIdentityValue(
                    label: "Exact source revision",
                    value: source.fingerprint.sha256
                )
            }
            LabeledContent("Analysis", value: occurrence.contextTitle)
            if let method = occurrence.parentRecord.method {
                LabeledContent("Method", value: method.displayName)
            }
            LabeledContent("Finished") {
                Text(
                    occurrence.parentRecord.finishedAt,
                    format: .dateTime.year().month().day().hour().minute()
                )
            }
            ResearchRecordIdentityValue(
                label: "Parent Record",
                value: occurrence.parentRecord.id.uuidString.lowercased()
            )
        }
        .font(ScholiumInterfaceTypography.apparatusBody)
    }

    @ViewBuilder
    private var provenanceActions: some View {
        ResearchRecordActionButton(
            "Open Analysis",
            systemImage: "arrow.up.forward.app",
            identifier: "scholium.researchRecommendation.openAnalysis"
        ) {
            guard let participant = analysisParticipant else { return }
            context.openNote(participant.noteID, participant.note, nil)
        }
        .disabled(analysisParticipant == nil)
        ResearchRecordActionButton(
            "Open Parent Record",
            systemImage: "doc.text.magnifyingglass",
            identifier: "scholium.researchRecommendation.openParentRecord"
        ) {
            model.openParentRecord(occurrence.parentRecord.id)
        }
    }

    private var researcherNote: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Researcher Note")
                .font(ScholiumInterfaceTypography.sectionTitle)
                .accessibilityHeading(.h2)
            if let note = occurrence.recommendation.disposition.researcherNote {
                Text(note)
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .textSelection(.enabled)
            } else {
                Text("No note")
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            ResearchRecordActionButton(
                occurrence.recommendation.disposition.researcherNote == nil
                    ? "Add Note…"
                    : "Edit Note…",
                systemImage: "square.and.pencil",
                identifier: "scholium.researchRecommendation.editNote"
            ) {
                noteDraft = occurrence.recommendation.disposition.researcherNote ?? ""
                isEditingNote = true
            }
            .disabled(model.mutatingRecommendationIDs.contains(occurrence.id))
        }
    }

    private var analysisParticipant: PortableResearchNoteRevision? {
        guard let participant = occurrence.parentRecord.researchRecordContextParticipant,
              !participant.isTombstone else { return nil }
        return participant
    }
}

private struct ResearchLiteratureRecommendationNoteSheet: View {
    @Binding var draft: String
    let save: @MainActor (String?) async throws -> Void
    let dismiss: () -> Void
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(spacing: ScholiumGrid.Spacing.sectionSeparation) {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    Text("Researcher Note")
                        .font(ScholiumInterfaceTypography.documentTitle)
                        .accessibilityHeading(.h1)
                    Text(
                        "This note records how you handled the reading lead. Saving an empty note removes it without changing the handling status."
                    )
                    .font(ScholiumInterfaceTypography.apparatusBody)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    TextEditor(text: $draft)
                        .font(ScholiumInterfaceTypography.apparatusResearchContent)
                        .scrollContentBackground(.hidden)
                        .padding(ScholiumGrid.Spacing.inlineControlGap)
                        .frame(minHeight: 120, idealHeight: 180)
                        .background(
                            ScholiumColorRole.surfaceBackground.color,
                            in: RoundedRectangle(
                                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                                style: .continuous
                            )
                        )
                        .scholiumBoundary(
                            .subtleBoundary,
                            in: RoundedRectangle(
                                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                                style: .continuous
                            )
                        )
                        .accessibilityLabel("Researcher note")
                        .accessibilityIdentifier(
                            "scholium.researchRecommendation.noteEditor"
                        )
                    if let saveErrorMessage {
                        Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(ScholiumInterfaceTypography.metadata)
                            .foregroundStyle(ScholiumColorRole.attention.color)
                            .textSelection(.enabled)
                            .accessibilityIdentifier(
                                "scholium.researchRecommendation.noteSaveError"
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving researcher note")
                }
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("Save", action: beginSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(
            minWidth: 440,
            idealWidth: 480,
            maxWidth: 620,
            minHeight: 320,
            idealHeight: 400,
            maxHeight: 640
        )
        .scholiumSurface(.document)
        .tint(ScholiumColorRole.accent.color)
    }

    private func beginSave() {
        guard !isSaving else { return }
        isSaving = true
        saveErrorMessage = nil
        let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            do {
                try await save(normalized.isEmpty ? nil : normalized)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                saveErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct ResearchRecordDatePicker: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        @Bindable var model = model
        LabeledContent("Date") {
            Picker("Date", selection: $model.dateFilter) {
                ForEach(ResearchRecordDateFilter.allCases, id: \.self) { filter in
                    Text(filter.interfaceTitle).tag(filter)
                }
            }
            .labelsHidden()
        }
    }
}

private struct ResearchRecordSkillPicker: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        @Bindable var model = model
        LabeledContent("Method") {
            Picker("Method", selection: $model.methodFilterName) {
                Text("Any Method").tag(Optional<String>.none)
                ForEach(model.methodOptions, id: \.self) { method in
                    Text(method).tag(Optional(method))
                }
            }
            .labelsHidden()
        }
    }
}

private struct ResearchRecordActionPicker: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        @Bindable var model = model
        LabeledContent("Action") {
            Picker("Action", selection: $model.actionFilterID) {
                Text("Any Action").tag(Optional<ResearchActionID>.none)
                ForEach(model.actionOptions, id: \.self) { actionID in
                    Text(actionTitle(actionID)).tag(Optional(actionID))
                }
            }
            .labelsHidden()
        }
    }
}

private struct ResearchRecordParticipantPicker: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        @Bindable var model = model
        LabeledContent("Participant") {
            Picker("Participant", selection: $model.participantFilter) {
                Text("Any Participant")
                    .tag(Optional<ResearchRecordParticipantFilter>.none)
                ForEach(model.participantOptions) { option in
                    switch option.filter {
                    case .author(let author):
                        Text(author.interfaceTitle)
                            .tag(Optional(option.filter))
                    case .note:
                        if option.isTombstone {
                            Text("Deleted Note — \(option.title)")
                                .tag(Optional(option.filter))
                        } else {
                            Text(option.title).tag(Optional(option.filter))
                        }
                    }
                }
            }
            .labelsHidden()
        }
    }
}

private struct ResearchRecordEmptyResults: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        ContentUnavailableView(
            "No Matching Research Records",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Clear a filter or search the complete Triptych.")
        )
        .overlay(alignment: .bottom) {
            Button("Clear Filters") { model.clearAllFilters() }
                .padding(.bottom, ScholiumGrid.Spacing.regionContentInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ResearchRecordListRow: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    let id: UUID
    let contextTitle: String
    let actionID: ResearchActionID
    let finishedAt: Date
    let noteTitles: [String]
    let authorParticipants: [PortableResearchStatementAuthor]
    let isPinned: Bool
    let isPinning: Bool
    let select: () -> Void
    let togglePin: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Button(action: select) {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
                ) {
                    Text("\(actionTitle(actionID)): \(contextTitle)")
                        .font(ScholiumInterfaceTypography.rowTitle)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        Text(finishedAt, format: .dateTime.year().month().day().hour().minute())
                        if !authorParticipants.isEmpty {
                            Text("·")
                                .accessibilityHidden(true)
                            Text(authorParticipants.map(\.interfaceTitle).formatted())
                                .lineLimit(1)
                        }
                    }
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    if !noteTitles.isEmpty {
                        Text(noteTitles.formatted())
                            .font(ScholiumInterfaceTypography.metadata)
                            .foregroundStyle(ScholiumColorRole.mutedText.color)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(actionTitle(actionID)): \(contextTitle)")
            Group {
                if reduceMotion {
                    pinControl
                } else {
                    pinControl
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                        .animation(
                            ScholiumMotion.symbolReplacement(reduceMotion: reduceMotion),
                            value: isPinned
                        )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchRecord.row.\(id.uuidString)")
    }

    private var pinControl: some View {
        ScholiumInkIconControl(
            title: isPinned ? "Unpin Research Record" : "Pin Research Record",
            systemImage: isPinned ? "pin.fill" : "pin",
            identifier: "scholium.researchRecord.pin.\(id.uuidString)",
            isActive: isPinned,
            action: togglePin
        )
        .disabled(isPinning)
        .accessibilityValue(isPinned ? "Pinned" : "Not Pinned")
    }
}

private struct ResearchRecordDetailView: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext
    @State private var confirmsPermanentDeletion = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                ResearchRecordDetailHeader(record: record)
                ScholiumStructuralRule()
                ResearchFinalizedResultView(record: record)
                ScholiumStructuralRule()
                ResearcherEvaluationView(
                    record: record,
                    save: { draft, expectedRevision, resultFingerprint in
                        try await context.saveEvaluation(
                            record.id,
                            draft,
                            expectedRevision,
                            resultFingerprint
                        )
                    },
                    clear: { expectedRevision, resultFingerprint in
                        try await context.clearEvaluation(
                            record.id,
                            expectedRevision,
                            resultFingerprint
                        )
                    },
                    didUpdateRecord: model.acceptUpdatedRecord
                )
                ScholiumStructuralRule()
                ResearchMethodFeedbackView(
                    record: record,
                    save: { draft, expectedRevision, resultFingerprint in
                        try await context.saveMethodFeedback(
                            record.id,
                            draft,
                            expectedRevision,
                            resultFingerprint
                        )
                    },
                    clear: { expectedRevision, resultFingerprint in
                        try await context.clearMethodFeedback(
                            record.id,
                            expectedRevision,
                            resultFingerprint
                        )
                    },
                    startImprovement: {
                        try await context.startMethodImprovement(record.id)
                    },
                    didUpdateRecord: model.acceptUpdatedRecord
                )
                ScholiumStructuralRule()
                ResearchRecordParticipantSection(
                    recordID: record.id,
                    participants: record.participatingNotes,
                    model: model,
                    context: context
                )
                if model.comparingNoteID != nil {
                    ResearchRecordComparisonSection(model: model)
                }
                ScholiumStructuralRule()
                ResearchRecordStatementSection(
                    statements: record.statements,
                    focusedStatementID: model.focusedStatementID,
                    primaryParticipant: primaryParticipant,
                    openNote: context.openNote
                )
                if !record.literatureRecommendations.isEmpty {
                    ScholiumStructuralRule()
                    ResearchRecordLiteratureRecommendationsSection(
                        record: record,
                        model: model
                    )
                }
                ResearchRecordEvidenceSection(
                    materials: record.actuallyUsedMaterials,
                    fidelityCompletion: record.fidelityCompletion,
                    changes: record.confirmedChanges,
                    discrepancies: record.discrepancies,
                    participants: record.participatingNotes
                )
                ScholiumStructuralRule()
                ResearchRecordDetailsDisclosure(record: record)
                ScholiumStructuralRule()
                ResearchRecordLifecycleControls(
                    recordID: record.id,
                    model: model,
                    confirmsPermanentDeletion: $confirmsPermanentDeletion
                )
            }
                .padding(ScholiumGrid.Spacing.regionContentInset)
                .frame(maxWidth: ResearchRecordLayout.readingMeasure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .onAppear {
                if let statementID = model.focusedStatementID {
                    proxy.scrollTo(statementID, anchor: .center)
                }
            }
            .onChange(of: model.focusedStatementID) { _, statementID in
                guard let statementID else { return }
                proxy.scrollTo(statementID, anchor: .center)
            }
        }
        .scholiumSurface(.document)
        .accessibilityIdentifier("scholium.researchRecord.detail")
        .alert("Delete This Research Record Permanently?", isPresented: $confirmsPermanentDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) {
                Task {
                    await model.deletePermanently(
                        recordID: record.id,
                        update: context.deletePermanently
                    )
                }
            }
        } message: {
            Text(
                "This removes the portable record from every derived Note view. It does not delete source Markdown, checkpoints, exact-note recovery, or unrelated records. This action cannot be undone."
            )
        }
    }

    private var primaryParticipant: PortableResearchNoteRevision? {
        record.researchRecordContextParticipant
    }
}

private struct ResearchRecordLifecycleControls: View {
    let recordID: UUID
    let model: ResearchRecordBrowserModel
    @Binding var confirmsPermanentDeletion: Bool

    var body: some View {
        ResearchRecordActionButton(
            "Delete Record…",
            systemImage: "trash",
            role: .destructive,
            identifier: "scholium.researchRecord.deletePermanently"
        ) {
            confirmsPermanentDeletion = true
        }
        .accessibilityHint(
            "Ask for confirmation before permanently deleting only this portable record"
        )
        .disabled(
            model.mutatingRecordIDs.contains(recordID)
                || model.pinningRecordIDs.contains(recordID)
        )
    }
}

private struct ResearchRecordLiteratureRecommendationsSection: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Literature Recommendations")
                .font(ScholiumInterfaceTypography.sectionTitle)
                .accessibilityHeading(.h2)
            ForEach(record.literatureRecommendations) { recommendation in
                Button {
                    model.openRecommendation(
                        recordID: record.id,
                        recommendationID: recommendation.id
                    )
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(
                            alignment: .leading,
                            spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
                        ) {
                            Text(recommendation.title ?? recommendation.rawCitation)
                                .font(ScholiumInterfaceTypography.apparatusResearchContent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let title = recommendation.title,
                               title != recommendation.rawCitation {
                                Text(recommendation.rawCitation)
                                    .font(ScholiumInterfaceTypography.metadata)
                                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                                    .lineLimit(2)
                            }
                        }
                        Text(
                            recommendation.disposition.status == .handled
                                ? "Handled"
                                : "Unprocessed"
                        )
                        .font(ScholiumInterfaceTypography.metadata)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Show this occurrence in Recommendations")
                .accessibilityIdentifier(
                    "scholium.researchRecord.recommendation.\(recommendation.id.uuidString)"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ResearchRecordDetailHeader: View {
    let record: PortableResearchRecord

    var body: some View {
        let actionID = record.kind == .discussion
            ? ResearchActionID.discuss
            : record.action?.actionID ?? .discuss
        let contextTitle = record.researchRecordContextTitle ?? actionTitle(actionID)
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(actionTitle(actionID)): \(contextTitle)")
                    .font(ScholiumInterfaceTypography.documentTitle)
                    .accessibilityHeading(.h1)
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                if record.isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(ScholiumInterfaceTypography.metadata)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
            }
            Text(record.finishedAt, format: .dateTime.year().month().day().hour().minute())
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
        }
    }
}

private struct ResearchRecordParticipantSection: View {
    let recordID: UUID
    let participants: [PortableResearchNoteRevision]
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Participating Notes")
                .font(ScholiumInterfaceTypography.sectionTitle)
                .accessibilityHeading(.h2)
            ForEach(participants) { participant in
                if participant.isTombstone {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Deleted Note", systemImage: "trash.slash")
                        Text(participant.title)
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "scholium.researchRecord.tombstone.\(participant.noteID.uuidString)"
                    )
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Button {
                            context.openNote(participant.noteID, participant.note, nil)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(participant.role.interfaceTitle)
                                    .font(ScholiumInterfaceTypography.editorialLabel)
                                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                                Text(participant.title)
                                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.forward.app")
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "scholium.researchRecord.note.\(participant.noteID.uuidString)"
                        )
                        .accessibilityHint("Open this participating Note in the focused workspace")
                        if participant.endingRevision != nil {
                            ResearchRecordActionButton(
                                "Compare",
                                systemImage: "arrow.left.and.right",
                                identifier: "scholium.researchRecord.compare.\(participant.noteID.uuidString)"
                            ) {
                                model.compare(
                                    recordID: recordID,
                                    noteID: participant.noteID,
                                    load: context.comparison
                                )
                            }
                            .accessibilityHint(
                                "Compare only the exact retained starting and ending bytes"
                            )
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ResearchRecordStatementSection: View {
    let statements: [PortableResearchStatement]
    let focusedStatementID: UUID?
    let primaryParticipant: PortableResearchNoteRevision?
    let openNote: @MainActor (UUID, VaultQualifiedNoteID, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            Text("Attributed Record")
                .font(ScholiumInterfaceTypography.sectionTitle)
                .accessibilityHeading(.h2)
            if statements.isEmpty {
                Text("No attributed prose was recorded.")
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            } else {
                ForEach(statements) { statement in
                    ResearchRecordStatementView(
                        attribution: statement.attribution,
                        author: statement.author,
                        kind: statement.kind,
                        text: statement.text,
                        createdAt: statement.createdAt,
                        lineReference: statement.lineReference,
                        primaryParticipant: primaryParticipant,
                        openNote: openNote
                    )
                    .id(statement.id)
                    .padding(.vertical, ScholiumGrid.Spacing.opticalAlignmentAdjustment)
                    .background(
                        statement.id == focusedStatementID
                            ? ScholiumColorRole.accent.color.opacity(0.10)
                            : Color.clear,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                    .accessibilityAddTraits(
                        statement.id == focusedStatementID ? .isSelected : []
                    )
                    if statement.id != statements.last?.id {
                        ScholiumStructuralRule()
                    }
                }
            }
        }
    }
}

private struct ResearchRecordStatementView: View {
    let attribution: String
    let author: PortableResearchStatementAuthor
    let kind: PortableResearchStatementKind
    let text: String
    let createdAt: Date
    let lineReference: ResearchLineReference?
    let primaryParticipant: PortableResearchNoteRevision?
    let openNote: @MainActor (UUID, VaultQualifiedNoteID, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
                    Text(attribution)
                        .font(ScholiumInterfaceTypography.sectionTitle)
                    Text(kind.interfaceTitle)
                        .font(ScholiumInterfaceTypography.metadata)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Text(createdAt, format: .dateTime.month().day().hour().minute())
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            Text(text)
                .font(ScholiumInterfaceTypography.apparatusResearchContent)
                .lineSpacing(ScholiumGrid.Spacing.labelAccessoryGap)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let lineReference, let primaryParticipant, !primaryParticipant.isTombstone {
                ResearchRecordActionButton(
                    "Open Lines \(lineReference.line)–\(lineReference.endLine)",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    identifier: "scholium.researchRecord.openLines"
                ) {
                    openNote(
                        primaryParticipant.noteID,
                        primaryParticipant.note,
                        lineReference.line
                    )
                }
                .accessibilityHint("Open the original revision-bound Comment location")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(author.interfaceTitle), \(attribution)")
    }
}

private struct ResearchRecordEvidenceSection: View {
    let materials: [PortableResearchMaterialUse]
    let fidelityCompletion: PortableResearchFidelityCompletion
    let changes: [PortableResearchConfirmedChange]
    let discrepancies: [PortableResearchDiscrepancy]
    let participants: [PortableResearchNoteRevision]

    var body: some View {
        if !materials.isEmpty
            || fidelityCompletion == .unverified
            || !changes.isEmpty
            || !discrepancies.isEmpty {
            ScholiumStructuralRule()
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Observed and Reported Evidence")
                    .font(ScholiumInterfaceTypography.sectionTitle)
                    .accessibilityHeading(.h2)
                if fidelityCompletion == .unverified {
                    Label(
                        "Fidelity could not be completed for this recorded revision.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(ScholiumInterfaceTypography.apparatusBody)
                    .accessibilityLabel(
                        "Fidelity could not be completed for this recorded revision."
                    )
                    .accessibilityIdentifier("scholium.researchRecord.fidelity.unverified")
                }
                if !materials.isEmpty {
                    Text("Agent-Reported Materials Used")
                        .font(ScholiumInterfaceTypography.editorialLabel)
                    ForEach(materials) { material in
                        Text(material.title)
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    }
                }
                if !changes.isEmpty {
                    Text("Scholium-Confirmed Changes: \(changes.count)")
                        .font(ScholiumInterfaceTypography.apparatusBody)
                        .monospacedDigit()
                }
                if !discrepancies.isEmpty {
                    Text("Recorded Discrepancies")
                        .font(ScholiumInterfaceTypography.editorialLabel)
                    ForEach(discrepancies) { discrepancy in
                        Text(discrepancy.interfaceDescription(participants: participants))
                            .font(ScholiumInterfaceTypography.apparatusBody)
                    }
                }
            }
        }
    }
}

private struct ResearchRecordDetailsDisclosure: View {
    let record: PortableResearchRecord
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Record Details", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                LabeledContent("Record kind", value: record.kind.interfaceTitle)
                ResearchRecordIdentityValue(
                    label: "Record identifier",
                    value: record.id.uuidString.lowercased()
                )
                if let method = record.method {
                    LabeledContent("Method", value: method.displayName)
                    if !method.practiceNames.isEmpty {
                        LabeledContent(
                            "Practices",
                            value: method.practiceNames.joined(separator: ", ")
                        )
                    }
                }
                if let source = record.sourceReference {
                    LabeledContent("Source", value: source.displayName)
                }
                if record.kind == .action, record.actuallyUsedMaterials.isEmpty {
                    LabeledContent("Agent-reported Materials used", value: "None")
                }
                if record.kind == .action,
                   record.fidelityCompletion != .unverified {
                    LabeledContent(
                        "Fidelity",
                        value: record.fidelityCompletion.interfaceTitle
                    )
                }
                ForEach(record.participatingNotes) { participant in
                    ResearchRecordRevisionDetails(participant: participant)
                }
            }
            .font(ScholiumInterfaceTypography.apparatusBody)
            .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
        }
    }
}

private struct ResearchRecordRevisionDetails: View {
    let participant: PortableResearchNoteRevision

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(participant.title)
                .font(ScholiumInterfaceTypography.apparatusActionTitle)
            ResearchRecordIdentityValue(
                label: "Starting revision",
                value: participant.startingRevision.sha256
            )
            if let endingRevision = participant.endingRevision {
                ResearchRecordIdentityValue(
                    label: "Ending revision",
                    value: endingRevision.sha256
                )
            } else {
                Text("Deleted Note")
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
        }
    }
}

private struct ResearchRecordComparisonSection: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        ScholiumStructuralRule()
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack {
                Text("Revision Comparison")
                    .font(ScholiumInterfaceTypography.sectionTitle)
                    .accessibilityHeading(.h2)
                Spacer()
                if model.comparison == nil {
                    ResearchRecordActionButton(
                        "Cancel",
                        systemImage: "xmark",
                        identifier: "scholium.researchRecord.cancelComparison"
                    ) { model.cancelComparison() }
                } else {
                    ResearchRecordActionButton(
                        "Close",
                        systemImage: "xmark",
                        identifier: "scholium.researchRecord.cancelComparison"
                    ) { model.cancelComparison() }
                }
            }
            if let comparison = model.comparison {
                ResearchRecordComparisonMetadata(comparison: comparison)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(comparison.lines) { line in
                        ResearchRecordComparisonLineView(line: line)
                    }
                }
                .accessibilityIdentifier("scholium.researchRecord.comparison")
            } else {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Comparing exact retained revisions…")
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Comparing exact retained revisions")
                .accessibilityIdentifier("scholium.researchRecord.comparisonProgress")
            }
        }
    }
}

private struct ResearchRecordComparisonMetadata: View {
    let comparison: ResearchRecordComparison

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            LabeledContent("Starting bytes") {
                Text("\(comparison.startingRevision.byteCount), \(bomDescription(comparison.startingHasUTF8BOM))")
            }
            LabeledContent("Ending bytes") {
                Text("\(comparison.endingRevision.byteCount), \(bomDescription(comparison.endingHasUTF8BOM))")
            }
        }
        .font(ScholiumInterfaceTypography.metadata)
        .foregroundStyle(ScholiumColorRole.secondaryText.color)
    }

    private func bomDescription(_ hasBOM: Bool) -> String {
        if hasBOM {
            return String(localized: "UTF-8 BOM", table: "Localizable", bundle: .module)
        }
        return String(localized: "No BOM", table: "Localizable", bundle: .module)
    }
}

private struct ResearchRecordComparisonLineView: View {
    let line: ResearchRecordComparisonLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(marker)
                .frame(width: 12, alignment: .center)
                .accessibilityHidden(true)
            Text(lineNumber)
                .frame(width: 72, alignment: .trailing)
                .foregroundStyle(ScholiumColorRole.mutedText.color)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(line.lineEnding.interfaceTitle)
                .foregroundStyle(ScholiumColorRole.mutedText.color)
        }
        .font(ScholiumTypography.swiftUIDiff())
        .textSelection(.enabled)
        .padding(.vertical, ScholiumGrid.Spacing.opticalAlignmentAdjustment)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var marker: String {
        switch line.kind {
        case .unchanged: " "
        case .startingOnly: "−"
        case .endingOnly: "+"
        }
    }

    private var lineNumber: String {
        let starting = line.startingLineNumber.map(String.init) ?? "–"
        let ending = line.endingLineNumber.map(String.init) ?? "–"
        return "\(starting)  \(ending)"
    }

    private var accessibilityDescription: String {
        switch line.kind {
        case .unchanged:
            String(
                localized: "Unchanged line \(line.endingLineNumber ?? 0), \(line.lineEnding.interfaceTitle) line ending: \(line.text)",
                table: "Localizable",
                bundle: .module
            )
        case .startingOnly:
            String(
                localized: "Starting revision only, line \(line.startingLineNumber ?? 0), \(line.lineEnding.interfaceTitle) line ending: \(line.text)",
                table: "Localizable",
                bundle: .module
            )
        case .endingOnly:
            String(
                localized: "Ending revision only, line \(line.endingLineNumber ?? 0), \(line.lineEnding.interfaceTitle) line ending: \(line.text)",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}

private extension ResearchRecordComparisonLineEnding {
    var interfaceTitle: String {
        switch self {
        case .lf: "LF"
        case .crlf: "CRLF"
        case .none:
            String(localized: "None", table: "Localizable", bundle: .module)
        }
    }
}

private extension ResearchRecordDateFilter {
    var interfaceTitle: LocalizedStringResource {
        switch self {
        case .any: "Any Date"
        case .today: "Today"
        case .pastSevenDays: "Past 7 Days"
        case .pastThirtyDays: "Past 30 Days"
        }
    }
}

private extension PortableResearchStatementAuthor {
    var interfaceTitle: String {
        switch self {
        case .researcher:
            String(localized: "Researcher", table: "Localizable", bundle: .module)
        case .agent:
            String(localized: "Agent", table: "Localizable", bundle: .module)
        }
    }
}

private extension PortableResearchStatementKind {
    var interfaceTitle: LocalizedStringResource {
        switch self {
        case .discussionTurn: "Discussion Turn"
        case .agentFeedback: "Agent Feedback"
        case .researcherResponse: "Researcher Response"
        }
    }
}

private extension PortableResearchRecordKind {
    var interfaceTitle: String {
        switch self {
        case .action:
            String(localized: "Action", table: "Localizable", bundle: .module)
        case .discussion:
            String(localized: "Discussion", table: "Localizable", bundle: .module)
        }
    }
}

private extension PortableResearchFidelityCompletion {
    var interfaceTitle: String {
        switch self {
        case .notRequired:
            String(localized: "Not required", table: "Localizable", bundle: .module)
        case .completed:
            String(localized: "Completed", table: "Localizable", bundle: .module)
        case .unverified:
            String(localized: "Unverified", table: "Localizable", bundle: .module)
        case .notApplicable:
            String(localized: "Not applicable", table: "Localizable", bundle: .module)
        }
    }
}

private extension ResearchActionTargetRole {
    var interfaceTitle: String {
        switch self {
        case .analysis:
            String(localized: "Analysis", table: "Localizable", bundle: .module)
        case .topic:
            String(localized: "Topic", table: "Localizable", bundle: .module)
        case .work:
            String(localized: "Work", table: "Localizable", bundle: .module)
        }
    }
}

private extension PortableResearchDiscrepancy {
    func interfaceDescription(
        participants: [PortableResearchNoteRevision]
    ) -> String {
        let title = participants.first { $0.noteID == noteID }?.title
            ?? String(localized: "Unknown Note", table: "Localizable", bundle: .module)
        switch kind {
        case .changedButNotReported:
            return String(
                localized: "\(title) changed without an Agent report.",
                table: "Localizable",
                bundle: .module
            )
        case .reportedButUnmodified:
            return String(
                localized: "\(title) was reported as changed without a confirmed revision change.",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}
