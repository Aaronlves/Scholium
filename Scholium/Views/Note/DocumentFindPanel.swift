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
    @Published private(set) var replacementIsPresented = false
    @Published private(set) var focusRequestID: UInt64 = 0
    @Published private(set) var isSearching = false
    @Published private(set) var query = ""
    @Published private(set) var replacement = ""
    @Published private(set) var caseSensitive = false
    @Published private(set) var wholeWord = false
    @Published private(set) var result = DocumentFindResult(current: 0, total: 0)
    @Published private(set) var errorMessage: String?
    @Published private(set) var request: DocumentFindPresentationRequest?

    private var nextRequestID: UInt64 = 0

    func present() {
        replacementIsPresented = false
        presentAndFocus()
    }

    func presentReplacement() {
        replacementIsPresented = true
        presentAndFocus()
    }

    func setReplacementPresented(_ presented: Bool) {
        guard presented != replacementIsPresented else { return }
        replacementIsPresented = presented
        if !presented { focusRequestID &+= 1 }
    }

    private func presentAndFocus() {
        isPresented = true
        focusRequestID &+= 1
        issue(.execute(.present))
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        replacementIsPresented = false
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
        focusRequestID &+= 1
        issue(.execute(.update))
    }

    func accept(_ result: DocumentFindResult, for requestID: UInt64) {
        guard request?.id == requestID else { return }
        self.result = result
        isSearching = false
        errorMessage = nil
    }

    func fail(_ error: any Error, for requestID: UInt64) {
        guard request?.id == requestID else { return }
        isSearching = false
        errorMessage = error.localizedDescription
    }

    private func issue(_ operation: DocumentFindPresentationOperation) {
        nextRequestID &+= 1
        errorMessage = nil
        if case .execute = operation {
            isSearching = !query.isEmpty
        } else {
            isSearching = false
        }
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

struct DocumentFindPanel: View {
    @ObservedObject var model: DocumentFindPresentationModel
    let allowsReplacement: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var usesCompactLayout = false

    private var canNavigate: Bool {
        !model.query.isEmpty && !model.isSearching
            && model.errorMessage == nil && model.result.total > 0
    }

    var body: some View {
        let columns = usesCompactLayout
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if allowsReplacement {
                    Button {
                        model.setReplacementPresented(!model.replacementIsPresented)
                    } label: {
                        Image(systemName: model.replacementIsPresented ? "chevron.down" : "chevron.right")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .scholiumButtonStyle(.borderless)
                    .help(model.replacementIsPresented ? "Hide Replace" : "Show Replace")
                    .accessibilityLabel("Replace")
                    .accessibilityValue(model.replacementIsPresented ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("scholium.documentFind.disclosure")
                }
                columns {
                    VStack(spacing: 8) {
                        DocumentFindSearchField(model: model)
                            .frame(minWidth: 120, minHeight: 28)
                        if allowsReplacement && model.replacementIsPresented {
                            TextField("Replace with", text: Binding(
                                get: { model.replacement }, set: model.setReplacement
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(minHeight: 28)
                            .accessibilityLabel("Replace with")
                            .accessibilityIdentifier("scholium.documentFind.replacement")
                        }
                    }
                    .layoutPriority(1)
                    VStack(alignment: .trailing, spacing: 8) {
                        navigationControls.frame(minHeight: 28)
                        if allowsReplacement && model.replacementIsPresented {
                            HStack(spacing: 8) {
                                Button("Replace", action: model.replaceCurrent)
                                    .accessibilityIdentifier("scholium.documentFind.replace")
                                Button("Replace All", action: model.replaceAll)
                                    .accessibilityIdentifier("scholium.documentFind.replaceAll")
                            }
                            .disabled(!canNavigate)
                            .frame(minHeight: 28)
                        }
                    }
                    .fixedSize()
                }
            }
            if model.caseSensitive || model.wholeWord {
                Text(activeOptions)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.destructive)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("scholium.documentFind.error")
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 420 } action: { usesCompactLayout = $0 }
        .scholiumButtonStyle(.automatic)
        .controlSize(.regular)
        .padding(12)
        .scholiumFloatingSurface(in: panelShape)
        .containerShape(panelShape)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.replacementIsPresented)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document Find")
        .accessibilityIdentifier("scholium.documentFind")
        .onChange(of: allowsReplacement) { _, allowed in
            if !allowed { model.setReplacementPresented(false) }
        }
        .onExitCommand(perform: model.dismiss)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ScholiumCornerRole.boundedPanel.radius, style: .continuous)
    }

    private var navigationControls: some View {
        HStack(spacing: 8) {
            if !model.query.isEmpty {
                Text(matchDescription)
                    .font(ScholiumTypography.interface(.small).monospacedDigit())
                    .scholiumForeground(.secondaryText)
                    .lineLimit(1)
                    .accessibilityLabel(matchAccessibilityLabel)
                    .accessibilityIdentifier("scholium.documentFind.matches")
            }
            ControlGroup {
                Button(action: model.previous) { Image(systemName: "chevron.up") }
                    .help("Find Previous").accessibilityLabel("Find Previous")
                    .accessibilityIdentifier("scholium.documentFind.previous")
                Button(action: model.next) { Image(systemName: "chevron.down") }
                    .help("Find Next").accessibilityLabel("Find Next")
                    .accessibilityIdentifier("scholium.documentFind.next")
            }
            .disabled(!canNavigate)
            Button(action: model.dismiss) {
                Image(systemName: "xmark").frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .scholiumButtonStyle(.borderless)
            .help("Close Find").accessibilityLabel("Close Find")
            .accessibilityIdentifier("scholium.documentFind.close")
        }
    }

    private var activeOptions: String {
        [model.caseSensitive ? ScholiumL10n.string("Case Sensitive") : nil,
         model.wholeWord ? ScholiumL10n.string("Whole Word") : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
    private var matchDescription: String {
        if model.isSearching { return ScholiumL10n.string("Finding…") }
        if model.errorMessage != nil { return "" }
        if model.result.total == 0 { return ScholiumL10n.string("No matches") }
        return "\(model.result.current)/\(model.result.total)"
    }
    private var matchAccessibilityLabel: String {
        guard canNavigate else { return matchDescription }
        return String(localized: "Match \(model.result.current) of \(model.result.total)",
                      table: "Localizable", bundle: .module)
    }
}

struct DocumentFindOverlay: View {
    @ObservedObject var model: DocumentFindPresentationModel
    let allowsReplacement: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        GeometryReader { geometry in
            if model.isPresented {
                DocumentFindPanel(model: model, allowsReplacement: allowsReplacement)
                    .frame(width: min(560, max(0, geometry.size.width - 24)))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(reduceMotion ? .identity : .offset(x: direction == .leftToRight ? 14 : -14)
                        .combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.isPresented)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
    }
}
