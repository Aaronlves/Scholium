import SwiftUI

enum DocumentFindPresentationOperation: Hashable, Sendable {
    case execute(DocumentFindAction)
    case clear
}

struct DocumentFindPresentationRequest: Hashable, Sendable {
    let id: UInt64
    let operation: DocumentFindPresentationOperation
    let query: String
    let replacement: String
    let caseSensitive: Bool
    let wholeWord: Bool

    var editorQuery: DocumentFindQuery? {
        guard case .execute(let action) = operation else { return nil }
        return DocumentFindQuery(
            query: query,
            replacement: replacement,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            action: action
        )
    }
}

@MainActor
final class DocumentFindPresentationModel: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var query = ""
    @Published private(set) var replacement = ""
    @Published private(set) var caseSensitive = false
    @Published private(set) var wholeWord = false
    @Published private(set) var result = DocumentFindResult(current: 0, total: 0)
    @Published private(set) var errorMessage: String?
    @Published private(set) var request: DocumentFindPresentationRequest?

    private var nextRequestID: UInt64 = 0

    func present() {
        isPresented = true
        issue(.execute(.update))
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        result = DocumentFindResult(current: 0, total: 0)
        errorMessage = nil
        issue(.clear)
    }

    func setQuery(_ value: String) {
        guard value != query else { return }
        query = String(value.prefix(16_384))
        issue(.execute(.update))
    }

    func setReplacement(_ value: String) {
        guard value != replacement else { return }
        replacement = String(value.prefix(1_000_000))
    }

    func setCaseSensitive(_ value: Bool) {
        guard value != caseSensitive else { return }
        caseSensitive = value
        issue(.execute(.update))
    }

    func setWholeWord(_ value: Bool) {
        guard value != wholeWord else { return }
        wholeWord = value
        issue(.execute(.update))
    }

    func next() {
        isPresented = true
        issue(.execute(.next))
    }

    func previous() {
        isPresented = true
        issue(.execute(.previous))
    }

    func refresh() {
        guard isPresented else { return }
        issue(.execute(.update))
    }

    func replaceCurrent() {
        issue(.execute(.replaceCurrent))
    }

    func replaceAll() {
        issue(.execute(.replaceAll))
    }

    func useSelection(_ value: String?) {
        guard let value, !value.isEmpty else { return }
        isPresented = true
        query = String(value.prefix(16_384))
        issue(.execute(.update))
    }

    func accept(_ result: DocumentFindResult, for requestID: UInt64) {
        guard request?.id == requestID else { return }
        self.result = result
        errorMessage = nil
    }

    func fail(_ error: any Error, for requestID: UInt64) {
        guard request?.id == requestID else { return }
        errorMessage = error.localizedDescription
    }

    private func issue(_ operation: DocumentFindPresentationOperation) {
        nextRequestID &+= 1
        errorMessage = nil
        request = DocumentFindPresentationRequest(
            id: nextRequestID,
            operation: operation,
            query: query,
            replacement: replacement,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord
        )
    }
}

struct DocumentFindBar: View {
    @ObservedObject var model: DocumentFindPresentationModel
    let allowsReplacement: Bool
    @FocusState private var findFieldIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                TextField(
                    "Find",
                    text: Binding(
                        get: { model.query },
                        set: model.setQuery
                    )
                )
                .focused($findFieldIsFocused)
                .textFieldStyle(.roundedBorder)
                .onSubmit(model.next)
                .accessibilityIdentifier("scholium.documentFind.query")

                Text(matchDescription)
                    .font(ScholiumTypography.interface(.small).monospacedDigit())
                    .scholiumForeground(.secondaryText)
                    .accessibilityLabel(matchAccessibilityLabel)

                Button(action: model.previous) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Find Previous")
                .disabled(model.query.isEmpty || model.result.total == 0)

                Button(action: model.next) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Find Next")
                .disabled(model.query.isEmpty || model.result.total == 0)

                Button(action: model.dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close Find")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    optionControls
                    if allowsReplacement { replacementControls }
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    optionControls
                    if allowsReplacement { replacementControls }
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.destructive)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
        .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
        .background(ScholiumColorRole.raisedSurfaceBackground.color)
        .overlay(alignment: .bottom) { ScholiumStructuralRule() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document Find")
        .onAppear { findFieldIsFocused = true }
        .onChange(of: model.isPresented) { _, presented in
            if presented { findFieldIsFocused = true }
        }
        .onExitCommand(perform: model.dismiss)
    }

    private var optionControls: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Toggle(
                "Case Sensitive",
                isOn: Binding(
                    get: { model.caseSensitive },
                    set: model.setCaseSensitive
                )
            )
            Toggle(
                "Whole Word",
                isOn: Binding(
                    get: { model.wholeWord },
                    set: model.setWholeWord
                )
            )
        }
        .toggleStyle(.button)
        .controlSize(.small)
    }

    private var replacementControls: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            TextField(
                "Replace",
                text: Binding(
                    get: { model.replacement },
                    set: model.setReplacement
                )
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("scholium.documentFind.replacement")
            Button("Replace", action: model.replaceCurrent)
                .disabled(model.query.isEmpty || model.result.total == 0)
            Button("Replace All", action: model.replaceAll)
                .disabled(model.query.isEmpty || model.result.total == 0)
        }
        .controlSize(.small)
    }

    private var matchDescription: String {
        matchAccessibilityLabel
    }

    private var matchAccessibilityLabel: String {
        if model.result.total == 0 {
            return String(localized: "No matches", table: "Localizable", bundle: .module)
        }
        return String(
            localized: "Match \(model.result.current) of \(model.result.total)",
            table: "Localizable",
            bundle: .module
        )
    }
}
