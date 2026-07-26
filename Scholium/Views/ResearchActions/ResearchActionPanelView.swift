import Foundation
import ScholiumContracts
import SwiftUI

struct ResearchActionPanelContext {
    let chooseLocalSource: () -> URL?
    let agentApplicationHandoff: AgentApplicationHandoffController
    let copyInstructions: (String) throws -> Void
    let dismiss: () -> Void
}

/// The one native sheet shared by bundled and researcher-owned Actions.
/// Profile modules may request fields, but cannot hide the app-owned Target,
/// revision, authority, conflict, or recovery boundary.
struct ResearchActionPanelView: View {
    @ObservedObject private var controller: ResearchActionController
    @ObservedObject private var agentApplicationHandoff: AgentApplicationHandoffController
    let context: ResearchActionPanelContext

    @FocusState private var focusedTextModuleID: String?
    @State private var noteQueries: [String: String] = [:]
    @State private var pendingHandoff: PendingHandoff?

    init(
        controller: ResearchActionController,
        context: ResearchActionPanelContext
    ) {
        self.controller = controller
        self.context = context
        _agentApplicationHandoff = ObservedObject(
            wrappedValue: context.agentApplicationHandoff
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScholiumStructuralRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    appOwnedContext
                    if let profile = controller.profile {
                        modules(profile.modules)
                    }
                    status
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("scholium.researchAction.scroll")
            ScholiumStructuralRule()
            if let errorMessage = agentApplicationHandoff.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("scholium.researchAction.handoffError")
                ScholiumStructuralRule()
            }
            footer
        }
        .frame(minWidth: 520, idealWidth: 660, minHeight: 500, idealHeight: 680)
        .scholiumSurface(.denseEvidence)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchAction.sheet")
        .interactiveDismissDisabled(
            controller.phase == .preparing || controller.phase == .cancelling
        )
        .onAppear { focusFirstTextModule() }
        .onChange(of: controller.phase) { _, phase in
            switch phase {
            case .editing:
                focusFirstTextModule()
            case .prepared:
                completePendingHandoff()
            case .failed, .cancelled:
                pendingHandoff = nil
            case .idle, .loading, .preparing, .cancelling:
                break
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: controller.activeAvailability?.definition.interfaceSymbol ?? "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Group {
                    if controller.activeAvailability?.profile.origin == .applicationDefault {
                        Text(LocalizedStringKey(actionTitle))
                    } else {
                        Text(verbatim: actionTitle)
                    }
                }
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: actionOriginTitle)
                    .font(.callout)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var appOwnedContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RUN BOUNDARY")
                .scholiumApparatusHeadingStyle()
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: 18,
                    verticalSpacing: 8
                ) {
                    boundaryRows
                }
                VStack(alignment: .leading, spacing: 10) {
                    boundaryBlock("Target", value: controller.target?.title ?? "Unavailable")
                    boundaryBlock("Revision", value: revisionLabel)
                    boundaryBlock("Authority", value: authorityLabel)
                }
            }
            Text("Scholium revalidates the note identity and revision before preparation. Write-capable Actions preserve the exact bytes they replace and remain subject to conflict and recovery checks.")
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("scholium.researchAction.boundary")
    }

    @ViewBuilder
    private var boundaryRows: some View {
        GridRow(alignment: .firstTextBaseline) {
            boundaryLabel("Target")
            Text(controller.target?.title ?? "Unavailable")
        }
        GridRow(alignment: .firstTextBaseline) {
            boundaryLabel("Revision")
            Text(revisionLabel).monospacedDigit()
        }
        GridRow(alignment: .firstTextBaseline) {
            boundaryLabel("Authority")
            Text(authorityLabel)
        }
    }

    private func boundaryLabel(_ value: String) -> some View {
        Text(LocalizedStringKey(value))
            .font(.callout.weight(.semibold))
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            .frame(width: 76, alignment: .leading)
    }

    private func boundaryBlock(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label))
                .font(.callout.weight(.semibold))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Text(value)
                .padding(.leading, 10)
        }
    }

    @ViewBuilder
    private func modules(_ modules: [ResearchActionModuleDefinition]) -> some View {
        ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
            moduleView(module)
            if index < modules.count - 1 { ScholiumStructuralRule() }
        }
    }

    @ViewBuilder
    private func moduleView(_ module: ResearchActionModuleDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                profileText(module.label)
                    .font(.headline)
                if !module.isRequired {
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scholium.researchAction.moduleHeader.\(module.id.rawValue)")
            if let helpText = module.helpText {
                profileText(helpText)
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch module.kind {
            case .boundedText:
                boundedText(module)
            case .boolean:
                boolean(module)
            case .enumeration:
                enumeration(module)
            case .notePicker, .materialSelector:
                notePicker(module)
            case .passageAnchor:
                passage(module)
            case .sourceReference:
                source(module)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func boundedText(_ module: ResearchActionModuleDefinition) -> some View {
        let binding = Binding(
            get: { controller.textValues[module.id.rawValue] ?? "" },
            set: { controller.setText($0, module: module) }
        )
        return Group {
            if module.allowsMultipleLines == true {
                TextEditor(text: binding)
                    .frame(minHeight: 92, maxHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(ScholiumColorRole.documentBackground.color)
                    .overlay {
                        RoundedRectangle(cornerRadius: ScholiumShape.editorialControlCornerRadius)
                            .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
                    }
            } else {
                TextField(text: binding, prompt: profileText(module.label)) {
                    profileText(module.label)
                }
                .labelsHidden()
            }
        }
        .focused($focusedTextModuleID, equals: module.id.rawValue)
        .accessibilityLabel(profileText(module.label))
        .accessibilityIdentifier("scholium.researchAction.text.\(module.id.rawValue)")
    }

    private func boolean(_ module: ResearchActionModuleDefinition) -> some View {
        Toggle(
            isOn: Binding(
                get: { controller.booleanValues[module.id.rawValue] ?? false },
                set: { controller.setBoolean($0, module: module) }
            )
        ) {
            profileText(module.label)
        }
        .labelsHidden()
        .accessibilityLabel(profileText(module.label))
    }

    private func enumeration(_ module: ResearchActionModuleDefinition) -> some View {
        Group {
            if module.maximumSelectionCount == 1 {
                Picker(
                    selection: Binding<ResearchActionModuleChoiceValue?>(
                        get: { controller.choiceValues[module.id.rawValue]?.first },
                        set: { value in
                            if let value {
                                controller.setChoice(value, isSelected: true, module: module)
                            } else if let current = controller.choiceValues[module.id.rawValue]?.first {
                                controller.setChoice(current, isSelected: false, module: module)
                            }
                        }
                    )
                ) {
                    if !module.isRequired {
                        Text("None")
                            .tag(Optional<ResearchActionModuleChoiceValue>.none)
                    }
                    ForEach(module.choices ?? [], id: \.value) { choice in
                        profileText(choice.label).tag(Optional(choice.value))
                    }
                } label: {
                    profileText(module.label)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .accessibilityLabel(profileText(module.label))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(module.choices ?? [], id: \.value) { choice in
                        Toggle(
                            isOn: Binding(
                                get: {
                                    controller.choiceValues[module.id.rawValue]?.contains(choice.value) == true
                                },
                                set: {
                                    controller.setChoice(
                                        choice.value,
                                        isSelected: $0,
                                        module: module
                                    )
                                }
                            )
                        ) {
                            profileText(choice.label)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private func notePicker(_ module: ResearchActionModuleDefinition) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                "Search eligible notes",
                text: Binding(
                    get: { noteQueries[module.id.rawValue] ?? "" },
                    set: { noteQueries[module.id.rawValue] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(Text("Search \(module.label)"))
            .accessibilityIdentifier("scholium.researchAction.noteSearch.\(module.id.rawValue)")
            .padding(.bottom, 6)

            if controller.isLoadingMaterialCandidates {
                ProgressView("Loading eligible notes…")
                    .controlSize(.small)
                    .accessibilityIdentifier("scholium.researchAction.notes.loading")
            } else if eligibleCandidates(for: module).isEmpty {
                Text("No eligible notes are available.")
                    .font(.callout)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            } else if visibleCandidates(for: module).isEmpty {
                Text("Enter a title or path to find an eligible note.")
                    .font(.callout)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            } else {
                ForEach(visibleCandidates(for: module), id: \.noteID) { candidate in
                    Toggle(
                        isOn: Binding(
                            get: {
                                controller.noteValues[module.id.rawValue]?.contains(candidate.noteID) == true
                            },
                            set: {
                                controller.setNote(
                                    candidate.noteID,
                                    isSelected: $0,
                                    module: module
                                )
                            }
                        )
                    ) {
                        Text(verbatim: candidate.title)
                    }
                    .toggleStyle(.checkbox)
                    .help(candidate.note.relativePath)
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func passage(_ module: ResearchActionModuleDefinition) -> some View {
        Group {
            if controller.passageIsAvailable {
                Toggle("Use selected passage", isOn: $controller.usesPassage)
                    .toggleStyle(.checkbox)
                    .accessibilityValue("Passage available")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No passage selected", systemImage: "selection.pin.in.out")
                        .font(.callout)
                    Text("Select a passage in the document, then reopen this Action from the Research menu or its Inspector row.")
                        .font(.caption)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func source(_ module: ResearchActionModuleDefinition) -> some View {
        if controller.isLoadingSourceStatus {
            ProgressView("Checking source access…")
                .controlSize(.small)
                .accessibilityIdentifier("scholium.researchAction.source.loading")
        } else if controller.sourceStatus?.state == .available,
           let reference = controller.sourceStatus?.reference {
            Label {
                Text(verbatim: reference.displayName)
            } icon: {
                Image(systemName: "doc.text.magnifyingglass")
            }
                .font(.callout)
                .accessibilityIdentifier("scholium.researchAction.source.available")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Source access needs attention.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .scholiumForeground(.attention)
                Button(controller.isBindingSource ? "Binding Source…" : "Choose Source…") {
                    guard let url = context.chooseLocalSource() else { return }
                    controller.bindLocalSource(url)
                }
                .disabled(controller.isBindingSource)
                .accessibilityIdentifier("scholium.researchAction.source.choose")
                Text("Scholium retains the permission and fingerprint locally; the Research Record stores neither the path nor the source bytes.")
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let errorMessage = controller.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.octagon")
                .font(.callout)
                .scholiumForeground(.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scholium.researchAction.error")
        }
        if let preparation = controller.preparation {
            VStack(alignment: .leading, spacing: 10) {
                Text("PREPARED")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("scholium.researchAction.prepared")
                Text("The exact Action, method revision, parameters, Target revision, and authority boundary are frozen for this run.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = preparation.derivedRefreshWarning {
                    Label(warning, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .scholiumForeground(.attention)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(controller.preparation == nil ? "Cancel" : "Done") {
                context.dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(controller.phase == .preparing || controller.phase == .cancelling)
            .accessibilityIdentifier("scholium.researchAction.dismiss")
            if controller.canCancelPreparedRun {
                Button("Cancel Run", role: .destructive) {
                    controller.cancelPreparedRun()
                }
                .disabled(controller.isBusy)
                .accessibilityIdentifier("scholium.researchAction.cancelRun")
            }
            Spacer()
            if controller.preparation == nil || controller.canCancelPreparedRun {
                Button {
                    beginHandoff(.copyOnly)
                } label: {
                    handoffButtonLabel(
                        title: "Copy Only",
                        isPending: pendingHandoff == .copyOnly
                    )
                }
                .disabled(!canCopyInstructions)
                .accessibilityIdentifier("scholium.researchAction.copyOnly")
                .accessibilityHint("Validates and freezes this Action, then copies its instructions.")
                Button {
                    beginHandoff(.copyAndOpen)
                } label: {
                    handoffButtonLabel(
                        title: agentApplicationHandoff.primaryActionTitle,
                        isPending: pendingHandoff == .copyAndOpen
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    !canCopyInstructions
                        || agentApplicationHandoff.isOpening
                )
                .accessibilityIdentifier("scholium.researchAction.copyAndOpen")
                .accessibilityHint(
                    agentApplicationHandoff.primaryActionAccessibilityHint
                )
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func handoffButtonLabel(
        title: String,
        isPending: Bool
    ) -> some View {
        HStack(spacing: 6) {
            if isPending {
                ProgressView()
                    .controlSize(.small)
            }
            Text(LocalizedStringKey(isPending ? "Preparing…" : title))
                .lineLimit(1)
        }
    }

    private func beginHandoff(_ handoff: PendingHandoff) {
        if let instructions = controller.preparation?.instructions,
           controller.canCancelPreparedRun,
           !controller.isBusy {
            performHandoff(handoff, instructions: instructions)
            return
        }
        guard controller.canPrepare, pendingHandoff == nil else { return }
        pendingHandoff = handoff
        controller.prepare()
    }

    private func completePendingHandoff() {
        guard let handoff = pendingHandoff,
              let instructions = controller.preparation?.instructions else {
            pendingHandoff = nil
            return
        }
        pendingHandoff = nil
        performHandoff(handoff, instructions: instructions)
    }

    private func performHandoff(
        _ handoff: PendingHandoff,
        instructions: String
    ) {
        switch handoff {
        case .copyOnly:
            agentApplicationHandoff.copyOnly(
                instructions: instructions,
                copy: context.copyInstructions
            )
        case .copyAndOpen:
            agentApplicationHandoff.copyAndOpen(
                instructions: instructions,
                copy: context.copyInstructions
            )
        }
    }

    private var actionTitle: String {
        controller.activeAvailability?.buttonName
            ?? String(localized: "Research Action", table: "Localizable", bundle: .module)
    }

    private var actionOriginTitle: String {
        controller.activeAvailability?.profile.origin.interfaceTitle
            ?? String(localized: "Research Action", table: "Localizable", bundle: .module)
    }

    private var revisionLabel: String {
        controller.target.map { String($0.fingerprint.sha256.prefix(8)) }
            ?? String(localized: "Unavailable", table: "Localizable", bundle: .module)
    }

    private var authorityLabel: String {
        guard let profile = controller.profile else {
            return String(localized: "Checking…", table: "Localizable", bundle: .module)
        }
        let role = controller.target?.role.interfaceTitle
            ?? String(localized: "note", table: "Localizable", bundle: .module)
        return profile.capabilities.candidateWritableRoles.isEmpty
            ? String(localized: "Read-only", table: "Localizable", bundle: .module)
            : String(
                localized: "Candidate write to current \(role)",
                table: "Localizable",
                bundle: .module
            )
    }

    private var canCopyInstructions: Bool {
        guard pendingHandoff == nil, !controller.isBusy else { return false }
        return controller.canCancelPreparedRun || controller.canPrepare
    }

    private func profileText(_ value: String) -> Text {
        if controller.activeAvailability?.profile.origin == .applicationDefault {
            Text(LocalizedStringKey(value))
        } else {
            Text(verbatim: value)
        }
    }

    private enum PendingHandoff {
        case copyOnly
        case copyAndOpen
    }

    private func focusFirstTextModule() {
        focusedTextModuleID = controller.profile?.modules.first(where: {
            $0.kind == .boundedText
        })?.id.rawValue
    }

    private func eligibleCandidates(
        for module: ResearchActionModuleDefinition
    ) -> [ResearchActionNoteSnapshot] {
        let roles = Set(module.roleScope ?? ResearchActionTargetRole.allCases)
        return controller.materialCandidates.filter { roles.contains($0.role) }
    }

    private func visibleCandidates(
        for module: ResearchActionModuleDefinition
    ) -> [ResearchActionNoteSnapshot] {
        let candidates = eligibleCandidates(for: module)
        let query = (noteQueries[module.id.rawValue] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            guard candidates.count <= 20 else {
                let selected = controller.noteValues[module.id.rawValue] ?? []
                return candidates.filter { selected.contains($0.noteID) }
            }
            return candidates
        }
        let comparable = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return candidates.filter { candidate in
            [candidate.title, candidate.note.relativePath].contains { value in
                value.folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                ).contains(comparable)
            }
        }.prefix(50).map { $0 }
    }
}

extension ResearchActionDefinition {
    var interfaceSymbol: String {
        switch executionKind {
        case .discussion: "text.bubble"
        case .analysis: "doc.text.magnifyingglass"
        case .synthesis: "arrow.triangle.merge"
        case .writing: "pencil"
        case .critique: "text.magnifyingglass"
        case .checkFidelity: "checkmark.shield"
        case .manuscript: "doc.richtext"
        }
    }

    var interfaceSummary: String {
        switch executionKind {
        case .discussion:
            String(localized: "Discuss this note or a selected passage without changing Markdown.", table: "Localizable", bundle: .module)
        case .analysis:
            String(localized: "Analyze the bound source and update this Analysis when warranted.", table: "Localizable", bundle: .module)
        case .synthesis:
            String(localized: "Integrate Analyses, Sources, and reliable information into this Topic.", table: "Localizable", bundle: .module)
        case .writing:
            String(localized: "Revise this Work within its explicit write boundary.", table: "Localizable", bundle: .module)
        case .critique:
            String(localized: "Produce bounded critical feedback before any separately authorized writing.", table: "Localizable", bundle: .module)
        case .checkFidelity:
            String(localized: "Check content fidelity without modifying the note.", table: "Localizable", bundle: .module)
        case .manuscript:
            String(localized: "Run the configured manuscript method within its declared boundary.", table: "Localizable", bundle: .module)
        }
    }

    var interfaceKeyboardShortcut: KeyboardShortcut? {
        switch id {
        case .discuss:
            KeyboardShortcut("r", modifiers: [.command])
        case .analyze, .synthesize, .write:
            KeyboardShortcut("r", modifiers: [.command, .shift])
        default:
            nil
        }
    }
}

private extension ResearchActionProfileOrigin {
    var interfaceTitle: String {
        switch self {
        case .applicationDefault:
            String(localized: "Working Method", table: "Localizable", bundle: .module)
        case .researcher:
            String(localized: "Researcher Skill", table: "Localizable", bundle: .module)
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
