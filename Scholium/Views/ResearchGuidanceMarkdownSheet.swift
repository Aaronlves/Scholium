import SwiftUI

struct ResearchGuidanceMarkdownEditDraft: Equatable {
    let initialSource: String
    var source: String

    init(source: String) {
        self.initialSource = source
        self.source = source
    }

    var isDirty: Bool {
        source != initialSource
    }
}

struct ResearchGuidanceMarkdownCreationDraft: Equatable {
    let initialName: String
    let initialSource: String
    var name: String
    var source: String

    init(name: String, source: String) {
        self.initialName = name
        self.initialSource = source
        self.name = name
        self.source = source
    }

    var isDirty: Bool {
        name != initialName || source != initialSource
    }

    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The shared sheet lifecycle for editing one existing Research Guidance
/// Markdown source. The owning Method or Practice operation still validates
/// the expected revision and commits the exact proposed String.
struct ResearchGuidanceMarkdownEditSheet: View {
    let title: Text
    let detail: Text
    let sourceAccessibilityLabel: Text
    let save: @MainActor (String) async throws -> Void
    let restorePrevious: (@MainActor () async throws -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ResearchGuidanceMarkdownEditDraft
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmsDiscard = false
    @State private var confirmsRestore = false
    @FocusState private var isSourceFocused: Bool

    init(
        title: Text,
        detail: Text,
        sourceAccessibilityLabel: Text,
        initialSource: String,
        save: @escaping @MainActor (String) async throws -> Void,
        restorePrevious: (@MainActor () async throws -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.sourceAccessibilityLabel = sourceAccessibilityLabel
        self.save = save
        self.restorePrevious = restorePrevious
        _draft = State(initialValue: ResearchGuidanceMarkdownEditDraft(source: initialSource))
    }

    var body: some View {
        ResearchGuidanceMarkdownSheetScaffold(
            title: title,
            detail: detail,
            errorMessage: errorMessage,
            isWorking: isWorking,
            canSubmit: isDirty,
            submitTitle: "Save",
            minimumHeight: 580,
            cancel: cancel,
            submit: saveDraft,
            content: {
                TextEditor(text: $draft.source)
                    .font(ScholiumTypography.exact(.body))
                    .focused($isSourceFocused)
                    .accessibilityLabel(sourceAccessibilityLabel)
            },
            secondaryActions: {
                if restorePrevious != nil {
                    Button("Restore Previous Edit") {
                        if isDirty {
                            confirmsRestore = true
                        } else {
                            restorePreviousSource()
                        }
                    }
                    .disabled(isWorking)
                }
            }
        )
        .interactiveDismissDisabled(isDirty || isWorking)
        .accessibilityIdentifier("scholium.researchGuidance.markdownEditSheet")
        .onAppear { isSourceFocused = true }
        .alert("Discard Unsaved Changes", isPresented: $confirmsDiscard) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Draft and Close", role: .destructive) { dismiss() }
        }
        .alert("Discard Unsaved Changes", isPresented: $confirmsRestore) {
            Button("Keep Editing", role: .cancel) {}
            Button("Restore Previous Edit", role: .destructive) {
                restorePreviousSource()
            }
        }
    }

    private var isDirty: Bool {
        draft.isDirty
    }

    private func cancel() {
        if isDirty {
            confirmsDiscard = true
        } else {
            dismiss()
        }
    }

    private func saveDraft() {
        perform { try await save(draft.source) }
    }

    private func restorePreviousSource() {
        guard let restorePrevious else { return }
        perform(restorePrevious)
    }

    private func perform(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await operation()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSourceFocused = true
            }
        }
    }
}

/// The shared sheet lifecycle for creating one new Research Guidance Markdown
/// source. The owning workflow retains naming policy, file creation, revision,
/// and registration authority.
struct ResearchGuidanceMarkdownCreationSheet: View {
    let title: Text
    let detail: Text
    let nameLabel: LocalizedStringKey
    let sourceAccessibilityLabel: Text
    let create: @MainActor (String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ResearchGuidanceMarkdownCreationDraft
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var confirmsDiscard = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case source
    }

    init(
        title: Text,
        detail: Text,
        nameLabel: LocalizedStringKey,
        sourceAccessibilityLabel: Text,
        initialName: String,
        initialSource: String,
        create: @escaping @MainActor (String, String) async throws -> Void
    ) {
        self.title = title
        self.detail = detail
        self.nameLabel = nameLabel
        self.sourceAccessibilityLabel = sourceAccessibilityLabel
        self.create = create
        _draft = State(initialValue: ResearchGuidanceMarkdownCreationDraft(
            name: initialName,
            source: initialSource
        ))
    }

    var body: some View {
        ResearchGuidanceMarkdownSheetScaffold(
            title: title,
            detail: detail,
            errorMessage: errorMessage,
            isWorking: isCreating,
            canSubmit: canCreate,
            submitTitle: "Create",
            minimumHeight: 560,
            cancel: cancel,
            submit: createDraft,
            content: {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.ResearchGuidance.controlSpacing
                ) {
                    Text(nameLabel)
                        .font(ScholiumTypography.interface(.compact, emphasis: .strong))
                        .scholiumForeground(.secondaryText)
                    TextField(nameLabel, text: $draft.name)
                        .focused($focusedField, equals: .name)
                    TextEditor(text: $draft.source)
                        .font(ScholiumTypography.exact(.body))
                        .focused($focusedField, equals: .source)
                        .accessibilityLabel(sourceAccessibilityLabel)
                }
            },
            secondaryActions: { EmptyView() }
        )
        .interactiveDismissDisabled(isDirty || isCreating)
        .accessibilityIdentifier("scholium.researchGuidance.markdownCreationSheet")
        .onAppear { focusedField = .name }
        .alert("Discard Unsaved Changes", isPresented: $confirmsDiscard) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Draft and Close", role: .destructive) { dismiss() }
        }
    }

    private var isDirty: Bool {
        draft.isDirty
    }

    private var canCreate: Bool {
        draft.canCreate
    }

    private func cancel() {
        if isDirty {
            confirmsDiscard = true
        } else {
            dismiss()
        }
    }

    private func createDraft() {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        Task { @MainActor in
            defer { isCreating = false }
            do {
                try await create(draft.name, draft.source)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                focusedField = .name
            }
        }
    }
}

/// Shared presentation chrome only. It owns no Research Guidance source,
/// revision, registration, or write policy.
private struct ResearchGuidanceMarkdownSheetScaffold<Content: View, SecondaryActions: View>: View {
    let title: Text
    let detail: Text
    let errorMessage: String?
    let isWorking: Bool
    let canSubmit: Bool
    let submitTitle: LocalizedStringResource
    let minimumHeight: CGFloat
    let cancel: () -> Void
    let submit: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let secondaryActions: () -> SecondaryActions

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.ResearchGuidance.editorSectionSpacing
        ) {
            title
                .font(ScholiumTypography.interface(.primaryTitle))
                .accessibilityHeading(.h1)
            detail
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            content()
                .frame(minWidth: 700, minHeight: 410)
                .disabled(isWorking)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.attention)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                secondaryActions()
                Spacer()
                Button(action: submit) {
                    HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(submitTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || !canSubmit)
                .accessibilityLabel(Text(submitTitle))
            }
        }
        .padding(ScholiumMetrics.ResearchGuidance.editorContentInset)
        .frame(minWidth: 740, minHeight: minimumHeight)
        .scholiumSurface(.document)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
    }
}
