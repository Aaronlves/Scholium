import AppKit
import Observation
import ScholiumContracts
import SwiftUI

struct AgentChatComposerQuery: Equatable {
    let trigger: Character
    let text: String
    let range: NSRange
    let token: String

    static func read(text: String, selection: NSRange, isComposing: Bool) -> Self? {
        let source = text as NSString
        guard !isComposing, selection.length == 0, selection.location <= source.length else { return nil }
        let prefix = source.substring(to: selection.location)
        let token = String(prefix.reversed().prefix { !$0.isWhitespace }.reversed())
        guard let trigger = token.first, "/@$".contains(trigger),
            !token.dropFirst().contains(where: { "/@$".contains($0) }), token.utf16.count <= 100
        else { return nil }
        return .init(
            trigger: trigger, text: String(token.dropFirst()),
            range: NSRange(location: selection.location - token.utf16.count, length: token.utf16.count), token: token)
    }
}

struct AgentChatComposerCandidate: Identifiable {
    enum Action {
        case file, notePicker, selection, methods, refreshMethods, manageMethods, context, usage, find, outline, changes, agents
        case webSearch(AgentChatPreferences.WebSearch)
        case note(WorkspaceCatalogNote)
        case method(AgentChatMethodSelection)
    }
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let action: Action
}

/// The native editor owns the query range and its Undo. Suggestions never replace a draft wholesale.
@MainActor @Observable final class AgentChatComposerCompletion {
    private(set) var query: AgentChatComposerQuery?
    private(set) var isComposing = false
    private var selectedCandidateID: String?
    var selectedIndex: Int {
        get { selectedCandidateID.flatMap { id in candidates.firstIndex { $0.id == id } } ?? 0 }
        set { selectedCandidateID = candidates.indices.contains(newValue) ? candidates[newValue].id : nil }
    }
    @ObservationIgnored private(set) weak var editor: AgentChatComposerTextView?
    @ObservationIgnored private(set) var conversationID: UUID?
    @ObservationIgnored var candidateQuery: AgentChatComposerQuery?
    @ObservationIgnored var candidates: [AgentChatComposerCandidate] = []
    @ObservationIgnored var canAccept: ((AgentChatComposerCandidate) -> Bool)?
    @ObservationIgnored var choose: ((AgentChatComposerCandidate) -> Void)?
    @ObservationIgnored private var dismissedQuery: AgentChatComposerQuery?

    func attach(to editor: AgentChatComposerTextView, in conversationID: UUID?) {
        if self.editor !== editor || self.conversationID != conversationID {
            dismissedQuery = nil
            query = nil
            selectedCandidateID = nil
        }
        self.editor = editor
        self.conversationID = conversationID
        let composing = editor.hasMarkedText()
        if isComposing != composing { isComposing = composing }
    }

    /// Delivery checks the attached input at activation time. Focus may already
    /// have moved to the Send button, so another window's responder is irrelevant.
    func canSubmit(in conversationID: UUID?) -> Bool {
        guard let conversationID, let editor, editor.window != nil, editor.isEditable,
            self.conversationID == conversationID, editor.completionConversationID == conversationID
        else { return false }
        return !editor.hasMarkedText()
    }

    func refresh(from editor: AgentChatComposerTextView, in conversationID: UUID?) {
        guard self.editor === editor, self.conversationID == conversationID,
            editor.completionConversationID == conversationID
        else { return }
        let composing = editor.hasMarkedText()
        if isComposing != composing { isComposing = composing }
        let current = AgentChatComposerQuery.read(text: editor.string, selection: editor.selectedRange(), isComposing: composing)
        if current != dismissedQuery { dismissedQuery = nil }
        let next = current == dismissedQuery ? nil : current
        if query != next {
            query = next
            selectedCandidateID = nil
        }
    }

    func detach(from editor: AgentChatComposerTextView) {
        guard self.editor === editor else { return }
        self.editor = nil
        conversationID = nil
        choose = nil
        canAccept = nil
        candidates = []
        candidateQuery = nil
        query = nil
        isComposing = false
    }

    /// Enter a picker without replacing selected draft prose or committing IME.
    func begin(_ trigger: Character) {
        guard "/@$".contains(trigger), let editor, editor.isEditable, !editor.hasMarkedText() else { return }
        let source = editor.string as NSString
        let insertion = NSMaxRange(editor.selectedRange())
        guard insertion <= source.length else { return }
        let prefix = source.substring(to: insertion)
        let separator = prefix.last.map { $0.isWhitespace ? "" : " " } ?? ""
        editor.window?.makeFirstResponder(editor)
        editor.breakUndoCoalescing()
        editor.insertText(separator + String(trigger), replacementRange: NSRange(location: insertion, length: 0))
        editor.setSelectedRange(NSRange(location: insertion + separator.utf16.count + 1, length: 0))
        editor.breakUndoCoalescing()
    }

    func dismiss() {
        dismissedQuery = query
        query = nil
    }

    func accept(_ candidate: AgentChatComposerCandidate) {
        guard let editor, editor.isEditable, let query, candidateQuery == query,
            canAccept?(candidate) == true, candidates.contains(where: { $0.id == candidate.id }),
            conversationID == editor.completionConversationID, !editor.hasMarkedText(),
            AgentChatComposerQuery.read(text: editor.string, selection: editor.selectedRange(), isComposing: false) == query
        else { return }
        let action = choose
        // Accepting a candidate is one text edit, including a /skills -> $
        // handoff, and must not coalesce with the command the researcher typed.
        editor.breakUndoCoalescing()
        let undo = editor.undoManager
        undo?.beginUndoGrouping()
        defer {
            undo?.endUndoGrouping()
            editor.breakUndoCoalescing()
        }
        editor.insertText("", replacementRange: query.range)
        self.query = nil
        editor.window?.makeFirstResponder(editor)
        action?(candidate)
    }

    func keyDown(_ event: NSEvent) -> Bool {
        guard query != nil, editor?.hasMarkedText() == false,
            event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        else { return false }
        if [36, 76, 125, 126].contains(event.keyCode), candidateQuery != query { return true }
        switch event.keyCode {
        case 53:
            dismiss()
            return true
        case 125, 126:
            guard !candidates.isEmpty else { return true }
            selectedIndex = (selectedIndex + (event.keyCode == 125 ? 1 : candidates.count - 1)) % candidates.count
            return true
        case 36, 76:
            guard candidates.indices.contains(selectedIndex) else { return true }
            accept(candidates[selectedIndex])
            return true
        default: return false
        }
    }
}

struct AgentChatComposerCandidates: View {
    let completion: AgentChatComposerCompletion
    let candidates: [AgentChatComposerCandidate]

    static func listHeight(for count: Int) -> CGFloat { CGFloat(min(6, max(1, count))) * 44 }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if candidates.isEmpty {
                Text("No Matches").foregroundStyle(.secondary).padding(8)
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding<Int?>(get: { completion.selectedIndex }, set: { if let value = $0 { completion.selectedIndex = value } })) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                            Button {
                                completion.accept(candidate)
                            } label: {
                                HStack(spacing: 8) {
                                    ScholiumSidebarIcon(systemImage: candidate.symbol).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.title).foregroundStyle(.primary).lineLimit(1)
                                        if !candidate.detail.isEmpty {
                                            Text(candidate.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }.frame(height: 34).contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .help([candidate.title, candidate.detail].filter { !$0.isEmpty }.joined(separator: "\n"))
                            .listRowSeparator(.hidden)
                            .tag(index).id(candidate.id)
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                    .frame(height: Self.listHeight(for: candidates.count))
                    .onChange(of: completion.selectedIndex) { _, index in
                        if candidates.indices.contains(index) { proxy.scrollTo(candidates[index].id) }
                    }
                    .onChange(of: candidates.map(\.id)) { _, _ in
                        if candidates.indices.contains(completion.selectedIndex) {
                            proxy.scrollTo(candidates[completion.selectedIndex].id)
                        }
                    }
                }
            }
        }
        .padding(6).font(.callout)
        .scholiumFloatingSurface(in: RoundedRectangle(cornerRadius: 12))
        .tint(nil as Color?)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
        .accessibilityValue(Text(verbatim: "\(candidates.count)"))
        .accessibilityIdentifier("scholium.chat.suggestions")
    }
}
