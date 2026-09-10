import AppKit
import ScholiumContracts
import SwiftUI

/// Ranges refer to the same native rendered reply used by quotation validation.
struct AgentChatRichSegment: Identifiable {
  let id: Int
  var range: NSRange
  var columns: Int = 0
  var code: String?
  var language: String?
  var isObject: Bool { columns > 0 || code != nil }

  static func collect(_ layout: AgentChatSelectableText.Layout) -> [Self] {
    var segments: [Self] = []
    for item in layout.blocks {
      var segment = Self(id: item.block.id, range: item.range)
      switch item.block.kind {
      case .tableRow: segment.columns = item.block.cells.count
      case .code:
        segment.code = String(item.block.text.characters)
        segment.language = item.block.language
      default: break
      }
      if let last = segments.last,
        (!last.isObject && !segment.isObject || last.columns > 0 && segment.columns > 0) {
        segments[segments.count - 1].range = NSUnionRange(last.range, segment.range)
        segments[segments.count - 1].columns = max(last.columns, segment.columns)
      } else { segments.append(segment) }
    }
    return segments
  }
}

/// Content of one expanded card; the inline reply is owned by its single reader.
struct AgentChatRichContent: View {
  let source: String
  let openLink: (URL) -> Void
  let onlySegment: Int
  var expandedDiagramSize: CGSize?

  var body: some View {
    let layout = AgentChatSelectableText.layoutReply(source)
    if let segment = AgentChatRichSegment.collect(layout).first(where: { $0.id == onlySegment }) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Spacer()
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(segment.code ?? layout.text.attributedSubstring(from: segment.range).string, forType: .string)
          } label: { Image(systemName: "doc.on.doc").chatAccessory() }
            .buttonStyle(.borderless).help("Copy").accessibilityLabel("Copy")
        }
        if segment.language?.lowercased() == "mermaid", let code = segment.code {
          AgentChatDiagram(source: "```mermaid\n" + code + "\n```")
            .frame(height: max(80, (expandedDiagramSize?.height ?? 160) + 24))
        } else {
          ScrollView(.horizontal) {
            AgentChatAttributedText(text: layout.text.attributedSubstring(from: segment.range), quote: nil, openLink: openLink)
              .frame(width: max(280, expandedDiagramSize?.width ?? 400))
          }
        }
      }
    }
  }
}

struct AgentChatAttributedText: NSViewRepresentable {
  let text: NSAttributedString
  let quote: ((NSRange, String) -> Void)?
  let openLink: (URL) -> Void
  func makeNSView(context: Context) -> AgentChatReplyTextView { AgentChatReplyTextView() }
  func updateNSView(_ view: AgentChatReplyTextView, context: Context) {
    view.quote = quote
    view.openLink = openLink
    if !view.attributedString().isEqual(to: text) { view.textStorage?.setAttributedString(text) }
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentChatReplyTextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
    return CGSize(width: width, height: nsView.measuredHeight(width: width))
  }
  static func dismantleNSView(_ view: AgentChatReplyTextView, coordinator: ()) {
    view.quote = nil; view.openLink = nil
  }
}

/// Reuses the document reader's inert HTML, local Mermaid runtime and navigation guard.
struct AgentChatDiagram: View {
  let source: String
  var onSize: ((CGSize) -> Void)? = nil
  @State private var failure: String?
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var projection: Projection?
  @State private var ready = false
  private struct Projection {
    let document: NoteDocument
    let html: String
    init(_ source: String) {
      document = NoteDocument(relativePath: "Chat.md", rawContent: source)
      html = SafeMarkdownRenderer.render(document).htmlBody
    }
  }
  var body: some View {
    Group {
      if let failure {
        VStack(alignment: .leading) {
          Text(verbatim: failure).foregroundStyle(.secondary)
          Text(verbatim: source).textSelection(.enabled)
          Button("Retry") { self.failure = nil }
        }
      } else if let projection {
        SafeMarkdownReadWebView(documentID: "chat-diagram", fingerprint: projection.document.fingerprint.sha256,
          source: source, htmlBody: projection.html,
          presentationCSS: Self.presentationCSS(dark: colorScheme == .dark, increasedContrast: contrast == .increased),
          userCSS: "", onLinkClick: { _ in }, onOpenExternalURL: { _ in }, selectionSurfaceIsActive: false,
          renderingReadinessIsAcknowledged: ready,
          onRenderingFailure: { failure = $0 }, onRenderingLoading: { ready = false },
          onRenderingReady: { ready = true }, onRenderedDiagramSize: onSize)
      } else { ProgressView("Loading…") }
    }
    .task(id: source) { failure = nil; ready = false; projection = Projection(source) }
  }
  static func presentationCSS(dark: Bool, increasedContrast: Bool) -> String {
    let colors: [(String, ScholiumColorRole)] = [
      ("document-background", .documentBackground), ("surface-background", .surfaceBackground),
      ("primary-text", .primaryText), ("secondary-text", .secondaryText),
      ("separator", .separator), ("accent", .accent)
    ]
    let declarations = colors.map { key, role in
      String(format: "--scholium-color-%@: #%06x;", key,
        role.resolvedRGBValue(isDark: dark, increasedContrast: increasedContrast))
    }.joined(separator: "\n")
    return """
      :root { color-scheme: \(dark ? "dark" : "light"); \(declarations) }
      html, body { background: transparent; color: var(--scholium-color-primary-text); }
      .scholium-document { padding: 8px; margin: 0; max-width: none; font-family: system-ui; }
      .scholium-document > .scholium-mermaid { margin-block: 0; }
      .scholium-mermaid-source, .scholium-mermaid-diagnostic { font-family: system-ui; }
      .scholium-mermaid-rendered .scholium-mermaid-diagnostic { display: none; }
      """
  }

}

@MainActor
final class AgentChatRichPreviewController: NSObject, NSPopoverDelegate {
  private(set) var popover: NSPopover?
  func present<Content: View>(content: Content, naturalSize: CGSize, anchor: NSRect, of source: NSView) {
    close()
    guard let screen = source.window?.screen else { return }
    let visibleAnchor = anchor.intersection(source.visibleRect)
    guard !visibleAnchor.isEmpty else { return }
    let size = Self.fittedSize(naturalSize, available: screen.visibleFrame.size)
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let host = NSHostingController(rootView: ScrollView {
      content.frame(maxWidth: .infinity).padding(16)
    }.frame(width: size.width, height: size.height))
    host.sizingOptions = []
    popover.contentViewController = host
    popover.contentSize = size
    popover.delegate = self
    self.popover = popover
    popover.show(relativeTo: visibleAnchor, of: source, preferredEdge: .maxY)
  }
  func close() { popover?.close(); popover = nil }
  func popoverDidClose(_ notification: Notification) {
    if let closed = notification.object as? NSPopover, closed === popover { popover = nil }
  }
  static func fittedSize(_ natural: CGSize, available: CGSize) -> CGSize {
    CGSize(width: min(max(280, natural.width + 32), available.width * 0.85),
           height: min(max(144, natural.height + 80), available.height * 0.85))
  }
}
