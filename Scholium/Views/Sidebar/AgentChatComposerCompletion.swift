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
      !token.dropFirst().contains(where: { "/@$".contains($0) }), token.utf16.count <= 100 else { return nil }
    return .init(trigger: trigger, text: String(token.dropFirst()),
      range: NSRange(location: selection.location - token.utf16.count, length: token.utf16.count), token: token)
  }
}

struct AgentChatComposerCandidate: Identifiable {
  enum Action {
    case file, notePicker, selection, methods, refreshMethods, manageMethods, context
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
  var selectedIndex = 0
  @ObservationIgnored weak var editor: AgentChatComposerTextView?
  @ObservationIgnored var conversationID: UUID?
  @ObservationIgnored var candidateQuery: AgentChatComposerQuery?
  @ObservationIgnored var candidates: [AgentChatComposerCandidate] = []
  @ObservationIgnored var choose: ((AgentChatComposerCandidate) -> Void)?
  @ObservationIgnored private var dismissedQuery: AgentChatComposerQuery?

  func refresh(from editor: AgentChatComposerTextView, in conversationID: UUID?) {
    self.editor = editor
    if self.conversationID != conversationID { dismissedQuery = nil }
    self.conversationID = conversationID
    let current = AgentChatComposerQuery.read(text: editor.string, selection: editor.selectedRange(), isComposing: editor.hasMarkedText())
    if current != dismissedQuery { dismissedQuery = nil }
    let next = current == dismissedQuery ? nil : current
    if query != next { query = next; selectedIndex = 0 }
  }

  func detach(from editor: AgentChatComposerTextView) {
    guard self.editor === editor else { return }
    self.editor = nil
    choose = nil
    candidates = []
    candidateQuery = nil
    query = nil
  }

  func dismiss() {
    dismissedQuery = query
    query = nil
  }

  func accept(_ candidate: AgentChatComposerCandidate) {
    guard let editor, let query, candidateQuery == query, candidates.contains(where: { $0.id == candidate.id }),
      conversationID == editor.completionConversationID, !editor.hasMarkedText(),
      AgentChatComposerQuery.read(text: editor.string, selection: editor.selectedRange(), isComposing: false) == query else { return }
    let action = choose
    editor.insertText("", replacementRange: query.range)
    self.query = nil
    editor.window?.makeFirstResponder(editor)
    action?(candidate)
  }

  func keyDown(_ event: NSEvent) -> Bool {
    guard query != nil, editor?.hasMarkedText() == false,
      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
    if [36, 76, 125, 126].contains(event.keyCode), candidateQuery != query { return true }
    switch event.keyCode {
    case 53: dismiss(); return true
    case 125, 126:
      guard !candidates.isEmpty else { return true }
      selectedIndex = (selectedIndex + (event.keyCode == 125 ? 1 : candidates.count - 1)) % candidates.count
      return true
    case 36, 76:
      guard candidates.indices.contains(selectedIndex) else { return true }
      accept(candidates[selectedIndex]); return true
    default: return false
    }
  }
}

struct AgentChatComposerCandidates: View {
  let completion: AgentChatComposerCompletion
  let candidates: [AgentChatComposerCandidate]

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if candidates.isEmpty {
        Text("No Matches").foregroundStyle(.secondary).padding(8)
      } else {
        List(selection: Binding<Int?>(get: { completion.selectedIndex }, set: { if let value = $0 { completion.selectedIndex = value } })) {
          ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
            Button { completion.accept(candidate) } label: {
              HStack(spacing: 8) {
                Image(systemName: candidate.symbol).frame(width: 18).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                  Text(candidate.title).lineLimit(1)
                  if !candidate.detail.isEmpty {
                    Text(candidate.detail).font(.caption).lineLimit(1)
                  }
                }
                Spacer(minLength: 0)
              }.frame(height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.borderless).tag(index)
          }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .frame(height: CGFloat(candidates.count) * 44)
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
