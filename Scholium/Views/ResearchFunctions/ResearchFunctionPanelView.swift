import ScholiumContracts
import SwiftUI

struct ResearchFunctionPanelContext {
    let repairCitationMethod: () -> Void
    let repairDiscussResponseDefaults: () -> Void
    let agentApplicationHandoff: AgentApplicationHandoffController
    let copyInstructions: (String) throws -> Void
    let dismiss: () -> Void

    init(
        repairCitationMethod: @escaping () -> Void,
        repairDiscussResponseDefaults: @escaping () -> Void,
        agentApplicationHandoff: AgentApplicationHandoffController,
        copyInstructions: @escaping (String) throws -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.repairCitationMethod = repairCitationMethod
        self.repairDiscussResponseDefaults = repairDiscussResponseDefaults
        self.agentApplicationHandoff = agentApplicationHandoff
        self.copyInstructions = copyInstructions
        self.dismiss = dismiss
    }
}

/// Shared presentation root for Research Function entry points. Human
/// settlement is recorded from the activity HUD rather than rendered as a
/// separate function panel.
struct ResearchFunctionPanelView: View {
    @ObservedObject private var controller: ResearchFunctionController
    let context: ResearchFunctionPanelContext

    init(
        controller: ResearchFunctionController,
        context: ResearchFunctionPanelContext
    ) {
        self.controller = controller
        self.context = context
    }

    var body: some View {
        agentPanel
        .frame(minWidth: 560, idealWidth: 680, minHeight: 520, idealHeight: 700)
        .scholiumSurface(.denseEvidence)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(panelAccessibilityLabel)
        .accessibilityIdentifier("scholium.researchFunctionPanel")
    }

    private var panelAccessibilityLabel: String {
        guard let function = controller.activeFunction else {
            return "Research function"
        }
        return "\(function.interfaceTitle) function"
    }

    private var agentPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let target = controller.target {
                            ResearchFunctionTargetSection(target: target)
                        }

                        if controller.isWriteFunction,
                           let target = controller.target {
                            ResearchFunctionWriteScopeSection(target: target)
                        }

                        if controller.phase == .loading {
                            ProgressView("Preparing function…")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            availabilityNotice
                            ResearchFunctionMaterialsSection(
                                state: controller.materialsViewState,
                                send: controller.sendMaterials
                            )
                            ResearchFunctionScopeSection(
                                selection: controller.scopeKind,
                                passageIsAvailable: controller.passageIsAvailable,
                                select: controller.setScope
                            )

                            if controller.activeFunction == .discuss {
                                instructionSection
                            }

                            if controller.activeFunction == .fidelity {
                                ResearchFunctionFidelitySection(
                                    checks: controller.fidelityChecks,
                                    availability: Dictionary(
                                        uniqueKeysWithValues: FidelityCheck.allCases.compactMap {
                                            guard let availability = controller.fidelityCheckAvailability($0) else {
                                                return nil
                                            }
                                            return ($0, availability)
                                        }
                                    ),
                                    setSelected: controller.setFidelityCheck,
                                    repairCitationMethod: context.repairCitationMethod
                                )
                            }

                            if controller.activeFunction == .discuss {
                                ResearchFunctionDiscussResponseSection(
                                    selection: controller.discussResponseModules,
                                    defaultsLoaded: controller.discussResponseDefaultsLoaded,
                                    errorMessage: controller.errorMessage,
                                    setSelected: controller.setDiscussResponseModule,
                                    repair: context.repairDiscussResponseDefaults
                                )
                            } else {
                                instructionSection
                            }
                            preparationStatus
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("scholium.researchFunctionPanel.scroll")
            }
            .frame(minHeight: 180)

            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let function = controller.activeFunction {
                Image(systemName: function.interfaceSymbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(function.interfaceTitle)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(controller.target?.title ?? "Research Function")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(18)
    }

    @ViewBuilder
    private var availabilityNotice: some View {
        if let function = controller.activeFunction,
           let availability = controller.availability[function],
           !availability.isEnabled {
            Label(
                availability.repairReasons.first?.interfaceDescription
                    ?? "This function is unavailable.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout)
            .scholiumForeground(.attention)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("scholium.researchFunctionUnavailable")
        }
    }

    private var instructionSection: some View {
        ResearchFunctionSection(title: instructionTitle, symbol: "text.alignleft") {
            TextEditor(text: $controller.instruction)
                .font(.body)
                .frame(minHeight: 92, maxHeight: 150)
                .padding(5)
                .background(
                    ScholiumColorRole.documentBackground.color,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
                }
                .accessibilityLabel(instructionTitle)
                .accessibilityIdentifier("scholium.researchFunctionInstruction")
        }
    }

    private var instructionTitle: String {
        controller.activeFunction == .discuss ? "Question" : "Focus (Optional)"
    }

    @ViewBuilder
    private var preparationStatus: some View {
        if let error = controller.errorMessage {
            Label(error, systemImage: "exclamationmark.octagon")
                .font(.callout)
                .scholiumForeground(.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scholium.researchFunctionError")
        }

        if let preparation = controller.preparation {
            let record = controller.presentedRun
                ?? ResearchFunctionRecordProjection(
                    snapshot: preparation.snapshot,
                    completion: preparation.reusedCompletion
                )
            ResearchFunctionSection(
                title: "Run Status",
                symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ResearchFunctionRunStatusView(record: record, showsFunction: false)
                    if let warning = preparation.derivedRefreshWarning {
                        Label(warning, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .scholiumForeground(.attention)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(
                                "scholium.researchFunctionDerivedRefreshWarning"
                            )
                    }
                    ResearchFunctionAgentHandoffView(
                        controller: context.agentApplicationHandoff,
                        instructions: preparation.instructions,
                        copyInstructions: context.copyInstructions
                    )
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
            .accessibilityIdentifier("scholium.dismissResearchFunction")
            Spacer()
            if controller.canCancelPreparedRun {
                Button("Cancel Run", role: .destructive) {
                    controller.cancelPreparedRun()
                }
                .disabled(controller.isBusy)
            } else if controller.preparation == nil {
                Button("Prepare") {
                    controller.prepare()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.canPrepare)
                .accessibilityIdentifier("scholium.prepareResearchFunction")
            }
        }
        .padding(16)
    }

}

private struct ResearchFunctionAgentHandoffView: View {
    @ObservedObject var controller: AgentApplicationHandoffController
    let instructions: String
    let copyInstructions: (String) throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(controller.primaryActionTitle) {
                    controller.copyAndOpen(
                        instructions: instructions,
                        copy: copyInstructions
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isOpening)
                .lineLimit(1)
                .accessibilityHint(controller.primaryActionAccessibilityHint)
                .accessibilityIdentifier("scholium.copyAndOpenAgentApplication")

                Menu {
                    Button("Copy Only") {
                        controller.copyOnly(
                            instructions: instructions,
                            copy: copyInstructions
                        )
                    }
                    .accessibilityIdentifier("scholium.copyResearchFunctionInstructions")

                    if controller.rememberedApplication == nil {
                        Button("Choose Agent App…") {
                            controller.chooseApplication()
                        }
                    } else {
                        Button("Choose Another Agent App…") {
                            controller.chooseApplication()
                        }
                        Divider()
                        Button("Forget Agent App") {
                            controller.forgetApplication()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(
                            width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                            height: ScholiumMetrics.Accessibility.preferredCustomTarget
                        )
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .disabled(controller.isOpening)
                .help("Agent application handoff options")
                .accessibilityLabel("Agent Application Handoff Options")
                .accessibilityIdentifier("scholium.agentApplicationHandoffOptions")

                if controller.isOpening {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Opening agent application")
                }
            }

            Text("Scholium copies the prepared instructions and opens the application only. Paste and submit them yourself.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.agentApplicationHandoffError")
            }
        }
    }
}

/// Read-only status projection for a Function-run envelope. It deliberately
/// does not render an agent exchange, critique prose, settlement, or source content.
struct ResearchFunctionRunStatusView: View {
    let record: ResearchFunctionRecordProjection
    let showsFunction: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if showsFunction {
                    Text(record.snapshot.request.function.interfaceTitle)
                        .font(.callout.weight(.semibold))
                }
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(record.snapshot.preparedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let completion = record.completion, !completion.summary.isEmpty {
                LabeledContent(
                    record.snapshot.request.function == .discuss
                        ? "Agent response"
                        : "Agent-reported completion"
                ) {
                    Text(completion.summary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }

            if let completion = record.completion,
               !completion.fidelityOutcomes.isEmpty {
                DisclosureGroup("Fidelity Outcomes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("These are attributed Function-run outcomes, separate from Critique and settlement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(completion.fidelityOutcomes, id: \.check) { outcome in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(
                                    "\(checkTitle(outcome.check)): \(outcomeTitle(outcome.state))",
                                    systemImage: outcomeSymbol(outcome.state)
                                )
                                .font(.caption.weight(.semibold))
                                Text(outcome.summary)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                ForEach(outcome.findings, id: \.self) { finding in
                                    Text("— \(finding)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(.top, 5)
                }
            }

            if let results = record.completion?.fidelityTargetResults,
               results.count > 1 {
                DisclosureGroup("Fidelity Results (\(results.count))") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(results, id: \.target.noteID) { result in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(result.target.title)
                                    .font(.caption.weight(.semibold))
                                Text(result.target.note.relativePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                ForEach(result.outcomes, id: \.check) { outcome in
                                    Label(
                                        "\(checkTitle(outcome.check)): \(outcomeTitle(outcome.state))",
                                        systemImage: outcomeSymbol(outcome.state)
                                    )
                                    .font(.caption)
                                    Text(outcome.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(.top, 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("scholium.researchFunction.runStatus")
    }

    private var state: ResearchFunctionRunState { record.runState }

    private var statusTitle: String {
        switch state {
        case .prepared: "Prepared"
        case .awaitingFidelity: "Awaiting Fidelity"
        case .complete: "Complete"
        case .unverified: "Unverified"
        case .stale: "Stale"
        case .cancelled: "Cancelled"
        }
    }

    private var statusDescription: String {
        switch state {
        case .prepared:
            "Instructions are prepared for an external agent; no completion has been reported."
        case .awaitingFidelity:
            "Substantive work was reported, but the required final Fidelity phase is still pending."
        case .complete:
            "Required completion evidence is recorded for the reported final revision."
        case .unverified:
            "The reported work does not include all required Fidelity evidence."
        case .stale:
            "Later Target or evidence changes made this recorded outcome stale."
        case .cancelled:
            "This Function run was cancelled."
        }
    }

    private var statusSymbol: String {
        switch state {
        case .prepared: "doc.badge.clock"
        case .awaitingFidelity: "checkmark.shield.badge.questionmark"
        case .complete: "checkmark.circle.fill"
        case .unverified: "questionmark.diamond.fill"
        case .stale: "exclamationmark.arrow.trianglehead.counterclockwise.rotate.90"
        case .cancelled: "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch state {
        case .complete: ScholiumColorRole.confirmed.color
        case .awaitingFidelity, .unverified, .stale: ScholiumColorRole.attention.color
        case .cancelled: ScholiumColorRole.destructive.color
        case .prepared: ScholiumColorRole.secondaryText.color
        }
    }

    private func checkTitle(_ check: FidelityCheck) -> String {
        switch check {
        case .content: "Content"
        case .citations: "Citations"
        }
    }

    private func outcomeTitle(_ state: FidelityCheckOutcomeState) -> String {
        switch state {
        case .passed: "Passed"
        case .issuesFound: "Issues Found"
        case .unavailable: "Unavailable"
        }
    }

    private func outcomeSymbol(_ state: FidelityCheckOutcomeState) -> String {
        switch state {
        case .passed: "checkmark.circle.fill"
        case .issuesFound: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle"
        }
    }
}

struct ResearchFunctionTargetSection: View {
    let target: ResearchFunctionTarget

    var body: some View {
        ResearchFunctionSection(title: "Target", symbol: "scope") {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.title)
                    .font(.body.weight(.medium))
                Text(target.note.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("scholium.researchFunctionTarget")
    }
}

struct ResearchFunctionWriteScopeSection: View {
    let target: ResearchFunctionTarget

    var body: some View {
        ResearchFunctionSection(title: "Write", symbol: "pencil.line") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Note")
                    .font(.body.weight(.medium))

                Text("Only \(target.title) may be changed in this phase. Additional Note changes require a separately authorized phase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Writable target")
            .accessibilityValue(target.title)
            .accessibilityHint(
                "Only the current Note may be changed in this phase."
            )
            .accessibilityIdentifier("scholium.researchFunction.writeScope")
        }
    }
}

struct ResearchFunctionMaterialsSection: View {
    let state: ResearchFunctionMaterialsViewState
    let send: (ResearchFunctionMaterialsAction) -> Void

    var body: some View {
        ResearchFunctionSection(title: "Materials", symbol: "doc.on.doc") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField(
                        "Search Materials",
                        text: Binding(
                            get: { state.query },
                            set: { send(.setQuery($0)) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(state.isFrozen || state.phase == .loading)
                    .accessibilityIdentifier("scholium.researchFunctionMaterials.search")

                    Toggle(
                        "Suggested Only",
                        isOn: Binding(
                            get: { state.showsSuggestedOnly },
                            set: { send(.setSuggestedOnly($0)) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .disabled(state.isFrozen || state.phase != .ready)
                    .accessibilityIdentifier(
                        "scholium.researchFunctionMaterials.suggestedOnly"
                    )
                }

                selectedTray

                switch state.phase {
                case .idle, .loading:
                    ProgressView("Loading Materials…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(
                            "scholium.researchFunctionMaterials.loading"
                        )
                case .empty:
                    ContentUnavailableView(
                        "No Materials Available",
                        systemImage: "folder",
                        description: Text(
                            "No additional notes are available. The Target remains the only writable note."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityIdentifier(
                        "scholium.researchFunctionMaterials.empty"
                    )
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .scholiumForeground(.attention)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry Materials") { send(.retry) }
                            .disabled(state.isFrozen)
                            .accessibilityIdentifier(
                                "scholium.researchFunctionMaterials.retry"
                            )
                    }
                    .accessibilityIdentifier(
                        "scholium.researchFunctionMaterials.failure"
                    )
                case .ready:
                    if state.roots.isEmpty {
                        ContentUnavailableView(
                            "No Matching Materials",
                            systemImage: "magnifyingglass",
                            description: Text(
                                "Change the search or turn off Suggested Only."
                            )
                        )
                        .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ResearchFunctionMaterialTree(
                                    nodes: state.roots,
                                    selection: state.selectedMaterialIDs,
                                    isFrozen: state.isFrozen,
                                    send: send
                                )
                            }
                            .padding(.trailing, 6)
                        }
                        .frame(minHeight: 100, maxHeight: 260)
                        .accessibilityLabel("Available Materials")
                        .accessibilityIdentifier(
                            "scholium.researchFunctionMaterialsList"
                        )
                    }
                }

                if state.isFrozen {
                    Label(
                        "Materials are fixed for the prepared instructions.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(
                        "scholium.researchFunctionMaterials.frozen"
                    )
                }
            }
        }
        .accessibilityIdentifier("scholium.researchFunctionMaterials")
    }

    @ViewBuilder
    private var selectedTray: some View {
        if !state.selectedCandidates.isEmpty {
            GroupBox("Selected Materials (\(state.selectedCandidates.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.selectedCandidates) { candidate in
                        HStack(spacing: 8) {
                            Text(candidate.material.title)
                                .lineLimit(1)
                            Spacer()
                            Button("Remove") { send(.remove(candidate.id)) }
                                .buttonStyle(.borderless)
                                .disabled(state.isFrozen)
                                .accessibilityLabel(
                                    "Remove \(candidate.material.title) from Materials"
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier(
                "scholium.researchFunctionMaterials.selectedTray"
            )
        }
    }
}

private struct ResearchFunctionMaterialTree: View {
    let nodes: [ResearchFunctionMaterialTreeNode]
    let selection: Set<UUID>
    let isFrozen: Bool
    let send: (ResearchFunctionMaterialsAction) -> Void

    var body: some View {
        ForEach(nodes) { node in
            switch node.kind {
            case .role, .folder:
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { node.isExpanded },
                        set: { _ in send(.toggleFolder(node.id)) }
                    )
                ) {
                    ResearchFunctionMaterialTree(
                        nodes: node.children,
                        selection: selection,
                        isFrozen: isFrozen,
                        send: send
                    )
                    .padding(.leading, 14)
                } label: {
                    Label(
                        node.title,
                        systemImage: nodeRoleSymbol(node)
                    )
                    .font(nodeIsRole(node) ? .callout.weight(.semibold) : .callout)
                    .accessibilityIdentifier(
                        "scholium.researchFunctionMaterials.node.\(node.id)"
                    )
                }
            case .material(let id):
                if let candidate = node.candidate {
                    materialRow(candidate, id: id)
                }
            }
        }
    }

    private func materialRow(
        _ candidate: ResearchFunctionMaterialCandidate,
        id: UUID
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { selection.contains(id) },
                set: { send(.setSelected(id, $0)) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.material.title)
                Text(candidate.material.note.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reason = candidate.suggestionReasons.first {
                    Text(suggestionTitle(reason))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isFrozen || !candidate.isSelectable)
        .help(
            candidate.repairReasons.first?.interfaceDescription
                ?? "Use as read-only Material"
        )
        .accessibilityLabel(candidate.material.title)
        .accessibilityHint(materialAccessibilityHint(for: candidate))
        .accessibilityIdentifier(
            "scholium.researchFunctionMaterial.\(candidate.material.role.rawValue).\(candidate.material.note.relativePath)"
        )
    }

    private func suggestionTitle(
        _ reason: ResearchFunctionMaterialSuggestionReason
    ) -> String {
        let relation = switch reason.kind {
        case .linkedFromSelectedPassage:
            "Suggested — Linked from Selected Passage"
        case .linkedFromTarget:
            "Suggested — Linked from Target"
        case .linksDirectlyToTarget:
            "Suggested — Links Directly to Target"
        }
        let line = reason.sourceSpan.start.line
        return "\(relation), \(reason.sourceNote.relativePath), line \(line)"
    }

    private func materialAccessibilityHint(
        for candidate: ResearchFunctionMaterialCandidate
    ) -> String {
        candidate.repairReasons.first?.interfaceDescription
            ?? candidate.suggestionReasons.first.map(suggestionTitle)
            ?? "Read-only Material at \(candidate.material.note.relativePath)"
    }

    private func nodeIsRole(_ node: ResearchFunctionMaterialTreeNode) -> Bool {
        if case .role = node.kind { return true }
        return false
    }

    private func nodeRoleSymbol(_ node: ResearchFunctionMaterialTreeNode) -> String {
        switch node.kind {
        case .role(.analysis): "doc.text.magnifyingglass"
        case .role(.topic): "point.3.connected.trianglepath.dotted"
        case .role(.work): "doc.richtext"
        case .folder: "folder"
        case .material: "doc.text"
        }
    }
}

struct ResearchFunctionScopeSection: View {
    let selection: ResearchFunctionScopeKind
    let passageIsAvailable: Bool
    let select: (ResearchFunctionScopeKind) -> Void

    var body: some View {
        ResearchFunctionSection(title: "Scope", symbol: "selection.pin.in.out") {
            Picker("Scope", selection: Binding(
                get: { selection },
                set: { newValue in select(newValue) }
            )) {
                Text("Whole").tag(ResearchFunctionScopeKind.whole)
                Text("Passage").tag(ResearchFunctionScopeKind.passage)
                    .disabled(!passageIsAvailable)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("scholium.researchFunctionScope")
        }
    }
}

struct ResearchFunctionFidelitySection: View {
    let checks: Set<FidelityCheck>
    let availability: [FidelityCheck: ResearchFunctionCheckAvailability]
    let setSelected: (FidelityCheck, Bool) -> Void
    let repairCitationMethod: () -> Void

    var body: some View {
        ResearchFunctionSection(title: "Checks", symbol: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 8) {
                fidelityToggle(.content, title: "Content")
                fidelityToggle(.citations, title: "Citations")
                if availability[.citations]?.isEnabled == false {
                    Button("Open Research Guidance…", action: repairCitationMethod)
                        .buttonStyle(.link)
                        .accessibilityIdentifier(
                            "scholium.researchFunction.repairCitationMethod"
                        )
                }
            }
        }
        .accessibilityIdentifier("scholium.researchFunctionFidelity")
    }

    private func fidelityToggle(_ check: FidelityCheck, title: String) -> some View {
        let checkAvailability = availability[check]
        return Toggle(isOn: Binding(
            get: { checks.contains(check) },
            set: { setSelected(check, $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let reason = checkAvailability?.repairReasons.first?.interfaceDescription,
                   checkAvailability?.isEnabled == false {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(checkAvailability?.isEnabled == false)
    }
}

struct ResearchFunctionDiscussResponseSection: View {
    let selection: Set<DialogueResponseModule>
    let defaultsLoaded: Bool
    let errorMessage: String?
    let setSelected: (DialogueResponseModule, Bool) -> Void
    let repair: () -> Void

    var body: some View {
        ResearchFunctionSection(title: "Response Modules", symbol: "text.badge.checkmark") {
            VStack(alignment: .leading, spacing: 9) {
                LabeledContent("Academic Outcome") {
                    Text("Always Included")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Academic Outcome, always included")
                .accessibilityHint("The required base of every Discuss response")
                .accessibilityIdentifier("scholium.researchFunctionAcademicOutcome")

                ForEach(DialogueResponseModule.allCases, id: \.self) { module in
                    Toggle(isOn: Binding(
                        get: { selection.contains(module) },
                        set: { setSelected(module, $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.displayName)
                            Text(module.promptQuestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!defaultsLoaded)
                    .accessibilityLabel(module.displayName)
                    .accessibilityHint(
                        "Optional response presentation. Does not change Materials, workflow routing, checkpoints, or write permissions."
                    )
                    .accessibilityIdentifier(
                        "scholium.researchFunctionResponseModule.\(module.rawValue)"
                    )
                }

                if !defaultsLoaded, errorMessage != nil {
                    Button("Open Research Guidance…", action: repair)
                        .buttonStyle(.link)
                        .accessibilityHint("Repair the Triptych Discuss Defaults in Settings")
                        .accessibilityIdentifier(
                            "scholium.researchFunction.repairDiscussResponseDefaults"
                        )
                }
            }
        }
        .accessibilityIdentifier("scholium.researchFunctionResponseModules")
    }
}

struct ResearchFunctionSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(ScholiumL10n.dynamicString(title), systemImage: symbol)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
