import AppKit
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

struct DocumentFindExecutionIdentity: Hashable {
    let requestID: UInt64?
    let allowsReplacement: Bool
    let editorIsLoaded: Bool
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
    private var requestIsPending = false
    private var pendingRefresh = false
    var hasPendingRequest: Bool { requestIsPending }

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

    func resetAfterClose() {
        isPresented = false
        replacementIsPresented = false
        query = ""
        replacement = ""
        caseSensitive = false
        wholeWord = false
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
        guard !requestIsPending else {
            pendingRefresh = true
            return
        }
        // Observation refreshes the summary without navigating the researcher.
        issue(.execute(.present))
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
        var value = result
        if request?.operation == .execute(.present), value.replacement == nil {
            value.replacement = self.result.replacement
        }
        self.result = value
        isSearching = false
        errorMessage = nil
        requestIsPending = false
        if pendingRefresh { refresh() }
    }

    func fail(_ error: any Error, for requestID: UInt64) {
        guard request?.id == requestID else { return }
        isSearching = false
        errorMessage = error.localizedDescription
        requestIsPending = false
        pendingRefresh = false
    }

    private func issue(_ operation: DocumentFindPresentationOperation) {
        nextRequestID &+= 1
        errorMessage = nil
        pendingRefresh = false
        if case .execute = operation {
            requestIsPending = true
            isSearching = !query.isEmpty
        } else {
            requestIsPending = false
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
        let columns =
            usesCompactLayout
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
                    .buttonStyle(.borderless)
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
                            DocumentFindReplacementField(model: model)
                                .frame(minHeight: 28)
                        }
                    }
                    .layoutPriority(1)
                    VStack(alignment: .trailing, spacing: 8) {
                        navigationControls.frame(minHeight: 28)
                        if allowsReplacement && model.replacementIsPresented {
                            HStack(spacing: 8) {
                                Button("Replace", action: model.replaceCurrent)
                                    .accessibilityIdentifier("scholium.documentFind.replace")
                                    .disabled(!canNavigate || !model.result.canReplaceCurrent)
                                Button("Replace All", action: model.replaceAll)
                                    .accessibilityIdentifier("scholium.documentFind.replaceAll")
                                    .disabled(!canNavigate || model.result.replaceable == 0)
                            }
                            .frame(minHeight: 28)
                        }
                    }
                    .fixedSize()
                }
            }
            if model.caseSensitive || model.wholeWord {
                Text(activeOptions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if allowsReplacement && model.replacementIsPresented,
                let replacementDescription
            {
                Text(replacementDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("scholium.documentFind.replacementStatus")
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("scholium.documentFind.error")
            }
        }
        .onGeometryChange(for: Bool.self) {
            $0.size.width < 420
        } action: {
            usesCompactLayout = $0
        }
        .buttonStyle(.automatic)
        .menuStyle(.automatic)
        .tint(nil as Color?)
        .controlSize(.regular)
        .padding(12)
        .scholiumFloatingSurface(in: panelShape)
        .containerShape(panelShape)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.replacementIsPresented)
        .transaction {
            if reduceMotion {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document Find")
        .accessibilityIdentifier("scholium.documentFind")
        .onChange(of: allowsReplacement) { _, allowed in
            if !allowed { model.setReplacementPresented(false) }
        }
        .onExitCommand {
            guard !((NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false) else { return }
            model.dismiss()
        }
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ScholiumCornerRole.boundedPanel.radius, style: .continuous)
    }

    private var navigationControls: some View {
        HStack(spacing: 8) {
            if !model.query.isEmpty {
                Text(matchDescription)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
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
            .buttonStyle(.borderless)
            .help("Close Find").accessibilityLabel("Close Find")
            .accessibilityIdentifier("scholium.documentFind.close")
        }
    }

    private var activeOptions: String {
        [
            model.caseSensitive ? ScholiumL10n.string("Case Sensitive") : nil,
            model.wholeWord ? ScholiumL10n.string("Whole Word") : nil,
        ]
        .compactMap { $0 }.joined(separator: " · ")
    }
    private var replacementDescription: String? {
        guard !model.isSearching, model.errorMessage == nil else { return nil }
        if let outcome = model.result.replacement {
            return String(
                localized: "Replaced \(outcome.replaced) matches. Skipped \(outcome.skipped) matches that cannot be replaced exactly.", table: "Localizable",
                bundle: .module)
        }
        let unavailable = model.result.total - model.result.replaceable
        guard unavailable > 0 else { return nil }
        return String(
            localized: "\(unavailable) matches cannot be replaced exactly. Only \(model.result.replaceable) matches can be replaced.", table: "Localizable",
            bundle: .module)
    }
    private var matchDescription: String {
        if model.isSearching { return ScholiumL10n.string("Finding…") }
        if model.errorMessage != nil { return "" }
        if model.result.total == 0 { return ScholiumL10n.string("No matches") }
        return "\(model.result.current)/\(model.result.total)"
    }
    private var matchAccessibilityLabel: String {
        guard canNavigate else { return matchDescription }
        return String(
            localized: "Match \(model.result.current) of \(model.result.total)",
            table: "Localizable", bundle: .module)
    }
}

struct DocumentFindOverlay: View {
    @ObservedObject var model: DocumentFindPresentationModel
    let allowsReplacement: Bool
    let availableWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        Group {
            if model.isPresented {
                DocumentFindPanel(model: model, allowsReplacement: allowsReplacement)
                    .frame(width: min(560, max(0, availableWidth - 24)))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(
                        reduceMotion
                            ? .identity
                            : .offset(x: direction == .leftToRight ? 14 : -14)
                                .combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.isPresented)
        .transaction {
            if reduceMotion {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        }
    }
}
