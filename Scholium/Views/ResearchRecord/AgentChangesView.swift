import ScholiumContracts
import SwiftUI

/// One immutable Record/Note activity borrowed by the temporary Agent Changes
/// presentation. Portable Records remain the durable provenance owner.
struct AgentChangesPresentationActivity: Hashable, Identifiable {
    let record: PortableResearchRecord
    let change: PortableResearchConfirmedChange
    let participant: PortableResearchNoteRevision

    var id: String {
        SettlementActivityReference(
            recordID: record.id,
            noteID: change.noteID
        ).id
    }

    var reference: SettlementActivityReference {
        SettlementActivityReference(
            recordID: record.id,
            noteID: change.noteID
        )
    }

    var affectedParticipants: [PortableResearchNoteRevision] {
        let changedNoteIDs = Set(record.confirmedChanges.map(\.noteID))
        return record.participatingNotes.filter {
            changedNoteIDs.contains($0.noteID)
        }
    }
}

/// Window-local routing input. Selection and navigation disappear with the
/// sheet and never become Record, Settlement, or viewed state.
struct AgentChangesPresentation: Identifiable {
    let id: UUID
    let activities: [AgentChangesPresentationActivity]
    let initialActivityID: String

    init?(
        requirement: WorkspaceSettlementRequirement,
        records: [PortableResearchRecord],
        id: UUID = UUID()
    ) {
        guard !requirement.pendingActivities.isEmpty else { return nil }
        let recordsByID = Dictionary(
            uniqueKeysWithValues: records.map { ($0.id, $0) }
        )
        let mapped = requirement.pendingActivities.compactMap { reference in
            Self.activity(reference: reference, recordsByID: recordsByID)
        }
        guard mapped.count == requirement.pendingActivities.count else {
            return nil
        }
        let ordered = mapped.sorted { lhs, rhs in
            if lhs.record.finishedAt != rhs.record.finishedAt {
                return lhs.record.finishedAt < rhs.record.finishedAt
            }
            if lhs.record.id != rhs.record.id {
                return lhs.record.id.uuidString < rhs.record.id.uuidString
            }
            return lhs.change.noteID.uuidString < rhs.change.noteID.uuidString
        }
        guard let first = ordered.first else { return nil }
        self.id = id
        activities = ordered
        initialActivityID = first.id
    }

    init?(
        record: PortableResearchRecord,
        preferredNoteID: UUID? = nil,
        id: UUID = UUID()
    ) {
        let mapped = record.confirmedChanges.compactMap {
            change -> AgentChangesPresentationActivity? in
            guard let participant = record.participatingNotes.first(where: {
                $0.noteID == change.noteID
            }) else { return nil }
            return AgentChangesPresentationActivity(
                record: record,
                change: change,
                participant: participant
            )
        }
        guard mapped.count == record.confirmedChanges.count,
              let first = mapped.first else { return nil }
        self.id = id
        activities = mapped
        initialActivityID = preferredNoteID.flatMap { noteID in
            mapped.first(where: { $0.change.noteID == noteID })?.id
        } ?? first.id
    }

    private static func activity(
        reference: SettlementActivityReference,
        recordsByID: [UUID: PortableResearchRecord]
    ) -> AgentChangesPresentationActivity? {
        guard let record = recordsByID[reference.recordID],
              let change = record.confirmedChanges.first(where: {
                  $0.noteID == reference.noteID
              }),
              let participant = record.participatingNotes.first(where: {
                  $0.noteID == reference.noteID
              }) else { return nil }
        return AgentChangesPresentationActivity(
            record: record,
            change: change,
            participant: participant
        )
    }
}

private enum AgentChangesPayload {
    case loading
    case modified(ExactSourceComparison)
    case created(NoteDocument)
    case unavailable(String)
}

/// Temporary activity-scoped inspection. It owns only the selected activity
/// while visible and exposes no Settlement, dismissal, or reviewed mutation.
struct AgentChangesView: View {
    typealias LoadComparison = @MainActor (UUID, UUID) async throws
        -> ExactSourceComparison
    typealias LoadChangeState = @MainActor (UUID) async throws
        -> ResearchRecordChangeState
    typealias LoadDocument = @MainActor (VaultQualifiedNoteID) async throws
        -> NoteDocument
    typealias OpenNote = @MainActor (UUID, VaultQualifiedNoteID) -> Void

    @Environment(\.dismiss) private var dismiss

    let presentation: AgentChangesPresentation
    let loadComparison: LoadComparison
    let loadChangeState: LoadChangeState
    let loadDocument: LoadDocument
    let openNote: OpenNote

    @State private var selectedActivityID: String
    @State private var payload: AgentChangesPayload = .loading
    @State private var currentState: ResearchRecordChangeCurrentState?
    @State private var currentStateError: String?
    @State private var hasLoadedCurrentState = false
    @State private var showsActivityDetails = false

    init(
        presentation: AgentChangesPresentation,
        loadComparison: @escaping LoadComparison,
        loadChangeState: @escaping LoadChangeState,
        loadDocument: @escaping LoadDocument,
        openNote: @escaping OpenNote
    ) {
        self.presentation = presentation
        self.loadComparison = loadComparison
        self.loadChangeState = loadChangeState
        self.loadDocument = loadDocument
        self.openNote = openNote
        _selectedActivityID = State(
            initialValue: presentation.initialActivityID
        )
    }

    var body: some View {
        ExactSourceComparisonSheetLayout(
            title: "Agent Changes",
            detail: "One Agent activity at a time. Closing does not settle the Note.",
            identifier: "scholium.agentChanges"
        ) {
            navigationControls
        } content: {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    activityHeader
                    activityContent
                }
                .padding(ScholiumGrid.Spacing.sectionSeparation)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } footer: {
            HStack {
                Button("Close", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.agentChanges.close")
                Spacer(minLength: 0)
            }
            .padding(ScholiumGrid.Spacing.sectionSeparation)
        }
        .task(id: selectedActivity.id) {
            await loadSelectedActivity()
        }
    }

    private var selectedIndex: Int {
        presentation.activities.firstIndex(where: {
            $0.id == selectedActivityID
        }) ?? 0
    }

    private var selectedActivity: AgentChangesPresentationActivity {
        presentation.activities[selectedIndex]
    }

    private var navigationControls: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button {
                selectActivity(at: selectedIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(selectedIndex == 0)
            .help("Previous Activity")
            .accessibilityLabel("Previous Activity")
            .accessibilityIdentifier("scholium.agentChanges.previous")

            Text("\(selectedIndex + 1) of \(presentation.activities.count)")
                .font(ScholiumTypography.interface(.compact))
                .scholiumForeground(.secondaryText)
                .accessibilityLabel(
                    "Activity \(selectedIndex + 1) of \(presentation.activities.count)"
                )
                .accessibilityIdentifier("scholium.agentChanges.position")

            Button {
                selectActivity(at: selectedIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(selectedIndex == presentation.activities.count - 1)
            .help("Next Activity")
            .accessibilityLabel("Next Activity")
            .accessibilityIdentifier("scholium.agentChanges.next")
        }
        .controlSize(.small)
    }

    private var activityHeader: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumGrid.Spacing.inlineControlGap
        ) {
            HStack(
                alignment: .firstTextBaseline,
                spacing: ScholiumGrid.Spacing.nestedContentInset
            ) {
                Text(verbatim: selectedActivity.participant.title)
                    .font(ScholiumTypography.scholarly(.sectionTitle))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .accessibilityHeading(.h2)
                Spacer(minLength: 0)
                currentRevisionStatus
            }

            ViewThatFits(in: .horizontal) {
                HStack(
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    activitySummary
                    Spacer(minLength: 0)
                    activityUtilities
                }
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    activitySummary
                    activityUtilities
                }
            }

            if let currentStateError {
                Text(verbatim: currentStateError)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.agentChanges.identity")
    }

    private var activitySummary: some View {
        HStack(
            spacing: ScholiumGrid.Spacing.labelAccessoryGap
        ) {
            Label(changeKindTitle, systemImage: changeKindSymbol)
            Text("·")
                .scholiumForeground(.mutedText)
                .accessibilityHidden(true)
            Text(verbatim: actionName)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("·")
                .scholiumForeground(.mutedText)
                .accessibilityHidden(true)
            Text(verbatim: "Run \(shortRunID)")
                .font(ScholiumTypography.exact(.small))
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(ScholiumTypography.interface(.compact))
        .scholiumForeground(.secondaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(changeKindText), \(actionName), Run \(fullRunID)"
        )
    }

    private var currentRevisionStatus: some View {
        Label(
            currentRevisionStatusTitle,
            systemImage: currentRevisionStatusSymbol
        )
        .font(ScholiumTypography.interface(.compact, emphasis: .medium))
        .scholiumForeground(currentRevisionStatusColor)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("scholium.agentChanges.currentStatus")
    }

    private var activityUtilities: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            if !otherAffectedParticipants.isEmpty {
                Menu {
                    ForEach(otherAffectedParticipants) { participant in
                        Button {
                            dismiss()
                            openNote(participant.noteID, participant.note)
                        } label: {
                            Label(participant.title, systemImage: "doc.text")
                        }
                    }
                } label: {
                    Label(
                        "Other Notes",
                        systemImage: "doc.on.doc"
                    )
                }
                .accessibilityIdentifier("scholium.agentChanges.otherNotes")
            }

            Button {
                showsActivityDetails.toggle()
            } label: {
                Label("Activity Details", systemImage: "info.circle")
                    .labelStyle(.iconOnly)
            }
            .help("Show Activity Details")
            .accessibilityLabel("Show Activity Details")
            .accessibilityIdentifier("scholium.agentChanges.details")
            .popover(isPresented: $showsActivityDetails) {
                activityDetails
            }
        }
        .controlSize(.small)
    }

    private var activityDetails: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumGrid.Spacing.nestedContentInset
        ) {
            Text("Activity Details")
                .font(ScholiumTypography.interface(.sectionTitle))
                .accessibilityHeading(.h2)
            LabeledContent("Action") {
                Text(verbatim: actionName)
            }
            LabeledContent("Run") {
                Text(verbatim: fullRunID)
                    .font(ScholiumTypography.exact(.small))
                    .textSelection(.enabled)
            }
            LabeledContent("Record") {
                Text(verbatim: selectedActivity.record.title.value)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            LabeledContent("Note") {
                Text(verbatim: selectedActivity.participant.note.relativePath)
                    .font(ScholiumTypography.exact(.small))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .font(ScholiumTypography.interface(.body))
        .padding(ScholiumGrid.Spacing.sectionSeparation)
        .frame(width: ScholiumMetrics.ResearchSheet.Comparison.detailPopoverWidth)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.agentChanges.activityDetails")
    }

    @ViewBuilder
    private var activityContent: some View {
        switch payload {
        case .loading:
            ScholiumContentStateView(
                "Preparing Agent Changes…",
                indicator: .progress
            )
            .frame(
                minHeight: ScholiumMetrics.ResearchSheet.Comparison
                    .documentStateMinimumHeight
            )
            .accessibilityIdentifier("scholium.agentChanges.loading")
        case .modified(let comparison):
            ExactSourceComparisonView(
                comparison: comparison,
                startingLabel: "Before Agent Work",
                endingLabel: "Agent Revision",
                startingOnlyLabel: "Before Agent Work only",
                endingOnlyLabel: "Agent revision only",
                identifierPrefix: "scholium.agentChanges.\(selectedActivity.id)"
            )
        case .created(let document):
            createdContent(document)
        case .unavailable(let message):
            ScholiumContentStateView(
                "Agent Changes Unavailable",
                detail: Text(message),
                indicator: .symbol(
                    "exclamationmark.triangle",
                    role: .attention
                )
            )
            .frame(
                minHeight: ScholiumMetrics.ResearchSheet.Comparison
                    .documentStateMinimumHeight
            )
            .accessibilityIdentifier("scholium.agentChanges.unavailable")
        }
    }

    private func createdContent(_ document: NoteDocument) -> some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumGrid.Spacing.nestedContentInset
        ) {
            Text("Created by this Run")
                .font(ScholiumTypography.interface(.sectionTitle))
                .accessibilityHeading(.h2)
            Text("Current Content")
                .font(ScholiumTypography.interface(.compact))
                .scholiumForeground(.secondaryText)
            Text(verbatim: document.rawContent)
                .font(ScholiumTypography.exact(.body))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .textSelection(.enabled)
                .padding(ScholiumGrid.Spacing.nestedContentInset)
                .background(ScholiumColorRole.documentBackground.color)
                .scholiumBoundary(
                    .subtleBoundary,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.agentChanges.created")
    }

    private var actionName: String {
        guard let actionID = selectedActivity.record.action?.actionID else {
            return String(localized: "Research Action")
        }
        return actionTitle(actionID)
    }

    private var changeKindTitle: LocalizedStringResource {
        switch selectedActivity.change.kind {
        case .modified: "Modified"
        case .created: "Created by this Run"
        }
    }

    private var changeKindText: String {
        switch selectedActivity.change.kind {
        case .modified: String(localized: "Modified")
        case .created: String(localized: "Created by this Run")
        }
    }

    private var changeKindSymbol: String {
        switch selectedActivity.change.kind {
        case .modified: "pencil.line"
        case .created: "doc.badge.plus"
        }
    }

    private var fullRunID: String {
        selectedActivity.record.id.uuidString.lowercased()
    }

    private var shortRunID: String {
        String(fullRunID.prefix(8))
    }

    private var otherAffectedParticipants: [PortableResearchNoteRevision] {
        selectedActivity.affectedParticipants.filter {
            $0.noteID != selectedActivity.participant.noteID
        }
    }

    private var currentRevisionStatusTitle: LocalizedStringResource {
        guard hasLoadedCurrentState else { return "Checking source changes" }
        guard let currentState else { return "Source unavailable" }
        switch currentState.status {
        case .agentEndingRevision:
            return selectedActivity.change.kind == .created
                ? "Created Agent revision is current"
                : "Agent revision is current"
        case .startingRevision, .superseded:
            return "Earlier revision"
        case .unavailable:
            return "Source unavailable"
        }
    }

    private var currentRevisionStatusSymbol: String {
        guard hasLoadedCurrentState else { return "arrow.triangle.2.circlepath" }
        guard let currentState else { return "exclamationmark.triangle" }
        return switch currentState.status {
        case .agentEndingRevision: "checkmark.circle"
        case .startingRevision, .superseded: "clock.arrow.circlepath"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    private var currentRevisionStatusColor: ScholiumColorRole {
        guard hasLoadedCurrentState else { return .secondaryText }
        guard let currentState else { return .attention }
        return switch currentState.status {
        case .agentEndingRevision: .secondaryText
        case .startingRevision, .superseded, .unavailable: .attention
        }
    }

    private func selectActivity(at index: Int) {
        guard presentation.activities.indices.contains(index) else { return }
        selectedActivityID = presentation.activities[index].id
        payload = .loading
        currentState = nil
        currentStateError = nil
        hasLoadedCurrentState = false
        showsActivityDetails = false
    }

    private func loadSelectedActivity() async {
        let activity = selectedActivity
        payload = .loading
        currentState = nil
        currentStateError = nil
        hasLoadedCurrentState = false

        do {
            let state = try await loadChangeState(activity.record.id)
            try Task.checkCancellation()
            guard selectedActivityID == activity.id else { return }
            currentState = state.documents.first(where: {
                $0.noteID == activity.change.noteID
            })
            hasLoadedCurrentState = true
        } catch is CancellationError {
            return
        } catch {
            guard selectedActivityID == activity.id else { return }
            hasLoadedCurrentState = true
            currentStateError = error.localizedDescription
        }

        do {
            switch activity.change.kind {
            case .modified:
                let comparison = try await loadComparison(
                    activity.record.id,
                    activity.change.noteID
                )
                try Task.checkCancellation()
                guard selectedActivityID == activity.id else { return }
                payload = .modified(comparison)
            case .created:
                let document = try await loadDocument(activity.participant.note)
                try Task.checkCancellation()
                guard selectedActivityID == activity.id else { return }
                payload = .created(document)
            }
        } catch is CancellationError {
            return
        } catch {
            guard selectedActivityID == activity.id else { return }
            payload = .unavailable(error.localizedDescription)
        }
    }
}
