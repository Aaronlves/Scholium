import ScholiumContracts
import SwiftUI

struct ResearchRecordBrowserContext {
    let setPinned: @MainActor (UUID, Bool) async throws -> PortableResearchRecord
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
    let initialNoteID: UUID?
    let context: ResearchRecordBrowserContext

    var body: some View {
        @Bindable var model = model
        ResearchRecordTwoColumnView(
            model: model,
            triptychName: triptychName,
            initialNoteID: initialNoteID,
            context: context
        )
        .frame(width: 760, height: 680)
        .scholiumSurface(.document)
        .onDisappear { model.cancelComparison() }
        .alert(
            model.isComparisonError
                ? "Comparison Unavailable"
                : "Research Record Unavailable",
            isPresented: $model.isShowingError
        ) {
            Button("Dismiss", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage)
        }
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
    let initialNoteID: UUID?
    let context: ResearchRecordBrowserContext

    var body: some View {
        HStack(spacing: 0) {
            ResearchRecordListPane(
                model: model,
                triptychName: triptychName,
                initialNoteID: initialNoteID,
                context: context,
                opensSelection: nil
            )
            .frame(
                minWidth: ResearchRecordLayout.listMinimumWidth,
                idealWidth: ResearchRecordLayout.listIdealWidth,
                maxWidth: ResearchRecordLayout.listMaximumWidth
            )
            ScholiumStructuralRule(orientation: .vertical)
            ResearchRecordSelectedDetail(model: model, context: context)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    let initialNoteID: UUID?
    let context: ResearchRecordBrowserContext
    let opensSelection: ((UUID) -> Void)?
    @State private var showsFilters = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ResearchRecordFilterControls(
                model: model,
                triptychName: triptychName,
                initialNoteID: initialNoteID,
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
                        skillID: entry.skillID,
                        skillVersion: entry.skillVersion,
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
                }
                .listStyle(.plain)
                .accessibilityLabel("Research Records")
                .accessibilityIdentifier("scholium.researchRecord.list")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scholiumSurface(.navigation)
        .navigationTitle("Research Record")
    }
}

private struct ResearchRecordFilterControls: View {
    let model: ResearchRecordBrowserModel
    let triptychName: String
    let initialNoteID: UUID?
    @Binding var showsFilters: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            TextField("Search records", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("scholium.researchRecord.search")
            Picker("Note", selection: $model.noteFilterID) {
                Text("Triptych").tag(Optional<UUID>.none)
                if let initialNoteID,
                   !model.noteOptions.contains(where: { $0.id == initialNoteID }) {
                    Text("This Note").tag(Optional(initialNoteID))
                }
                ForEach(model.noteOptions) { note in
                    if note.id == initialNoteID {
                        Text("This Note — \(note.title)").tag(Optional(note.id))
                    } else if note.isTombstone {
                        Text("Deleted Note — \(note.title)").tag(Optional(note.id))
                    } else {
                        Text(note.title).tag(Optional(note.id))
                    }
                }
            }
            .accessibilityIdentifier("scholium.researchRecord.noteFilter")
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
            HStack {
                Text(triptychName)
                    .lineLimit(1)
                Spacer()
                Text("\(model.visibleEntries.count) records")
                    .monospacedDigit()
            }
            .font(ScholiumInterfaceTypography.metadata)
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
        }
        .controlSize(.small)
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
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
        LabeledContent("Skill") {
            Picker("Skill", selection: $model.skillFilterID) {
                Text("Any Skill").tag(Optional<String>.none)
                ForEach(model.skillOptions, id: \.self) { skill in
                    Text(skill).tag(Optional(skill))
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
    let id: UUID
    let contextTitle: String
    let actionID: ResearchActionID
    let finishedAt: Date
    let skillID: String?
    let skillVersion: String?
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
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text(finishedAt, format: .dateTime.year().month().day().hour().minute())
                        Spacer(minLength: ScholiumGrid.Spacing.opticalAlignmentAdjustment)
                        if let skillID {
                            Text("\(skillID), version \(skillVersion ?? "—")")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No recorded Skill")
                                .foregroundStyle(ScholiumColorRole.mutedText.color)
                        }
                    }
                    .font(ScholiumInterfaceTypography.metadata)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    Text(noteTitles.formatted())
                        .font(ScholiumInterfaceTypography.metadata)
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                        .lineLimit(1)
                    Text(authorParticipants.map(\.interfaceTitle).formatted())
                        .font(ScholiumInterfaceTypography.metadata)
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(actionTitle(actionID)): \(contextTitle)")
            Button(action: togglePin) {
                Image(systemName: isPinned ? "pin.slash" : "pin")
                    .frame(
                        minWidth: ScholiumMetrics.Accessibility.minimumCustomTarget,
                        minHeight: ScholiumMetrics.Accessibility.minimumCustomTarget
                    )
            }
            .buttonStyle(.borderless)
            .disabled(isPinning)
            .accessibilityLabel(isPinned ? "Unpin Research Record" : "Pin Research Record")
            .accessibilityValue(isPinned ? "Pinned" : "Not Pinned")
            .accessibilityIdentifier("scholium.researchRecord.pin.\(id.uuidString)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchRecord.row.\(id.uuidString)")
    }
}

private struct ResearchRecordDetailView: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext
    @State private var confirmsPermanentDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                ResearchRecordDetailHeader(record: record)
                ResearchRecordLifecycleControls(
                    recordID: record.id,
                    model: model,
                    confirmsPermanentDeletion: $confirmsPermanentDeletion
                )
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
                    primaryParticipant: primaryParticipant,
                    openNote: context.openNote
                )
                ResearchRecordEvidenceSection(
                    materials: record.actuallyUsedMaterials,
                    fidelityCompletion: record.fidelityCompletion,
                    changes: record.confirmedChanges,
                    discrepancies: record.discrepancies,
                    participants: record.participatingNotes
                )
                ResearchRecordDetailsDisclosure(record: record)
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: ResearchRecordLayout.readingMeasure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
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
        Button("Delete Record…", systemImage: "trash", role: .destructive) {
            confirmsPermanentDeletion = true
        }
        .accessibilityHint(
            "Ask for confirmation before permanently deleting only this portable record"
        )
        .accessibilityIdentifier("scholium.researchRecord.deletePermanently")
        .disabled(
            model.mutatingRecordIDs.contains(recordID)
                || model.pinningRecordIDs.contains(recordID)
        )
        .controlSize(.small)
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
                            Button("Compare Revisions") {
                                model.compare(
                                    recordID: recordID,
                                    noteID: participant.noteID,
                                    load: context.comparison
                                )
                            }
                            .buttonStyle(.borderless)
                            .accessibilityHint(
                                "Compare only the exact retained starting and ending bytes"
                            )
                            .accessibilityIdentifier(
                                "scholium.researchRecord.compare.\(participant.noteID.uuidString)"
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
                .font(ScholiumTypography.swiftUIReadingFont(size: 13, relativeTo: .body))
                .lineSpacing(ScholiumGrid.Spacing.labelAccessoryGap)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let lineReference, let primaryParticipant, !primaryParticipant.isTombstone {
                Button("Open Lines \(lineReference.line)–\(lineReference.endLine)") {
                    openNote(
                        primaryParticipant.noteID,
                        primaryParticipant.note,
                        lineReference.line
                    )
                }
                .buttonStyle(.borderless)
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
                LabeledContent("Record identifier") {
                    Text(record.id.uuidString.lowercased())
                        .font(ScholiumTypography.swiftUIRevisionIdentity())
                        .textSelection(.enabled)
                }
                if let method = record.method {
                    LabeledContent("Skill", value: method.packageID)
                    LabeledContent("Skill version", value: method.version)
                    LabeledContent("Skill revision") {
                        Text(method.packageRevision.sha256)
                            .font(ScholiumTypography.swiftUIRevisionIdentity())
                            .textSelection(.enabled)
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
            LabeledContent("Starting revision") {
                Text(participant.startingRevision.sha256)
                    .font(ScholiumTypography.swiftUIRevisionIdentity())
                    .textSelection(.enabled)
            }
            if let endingRevision = participant.endingRevision {
                LabeledContent("Ending revision") {
                    Text(endingRevision.sha256)
                        .font(ScholiumTypography.swiftUIRevisionIdentity())
                        .textSelection(.enabled)
                }
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
                    Button("Cancel") { model.cancelComparison() }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(
                            "scholium.researchRecord.cancelComparison"
                        )
                } else {
                    Button("Close") { model.cancelComparison() }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(
                            "scholium.researchRecord.cancelComparison"
                        )
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
        .font(.system(.caption, design: .monospaced))
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
