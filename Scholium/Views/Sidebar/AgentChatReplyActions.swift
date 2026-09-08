import AppKit
import ScholiumContracts
import SwiftUI

/// Only explicit reply links enter Sources. A link is not proof of source support.
struct AgentChatReplySource: Identifiable, Equatable {
  let url: URL
  let title: String
  var id: String { url.absoluteString }
  var isNote: Bool { AgentChatReference.parse(url) != nil }
  var isWeb: Bool { ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil }
  var destination: String { isNote ? ScholiumL10n.string("Note") : url.host ?? ScholiumL10n.string("Reference") }

  static func collect(_ text: String) -> [Self] {
    guard let parsed = try? AttributedString(markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return [] }
    var seen: Set<URL> = []
    return parsed.runs.compactMap { run in
      guard let url = run.link, seen.insert(url).inserted else { return nil }
      return .init(url: url, title: String(parsed[run.range].characters))
    }
  }
}

struct AgentChatReplyActions: View {
  let text: String
  let openNote: (URL) -> Void
  let context: AgentChatReplySourceContext
  let openAttachment: (AgentChatAttachment) -> Void
  let previewMaterial: (AgentChatLocalMaterial) async throws -> URL
  @Environment(\.openURL) private var openURL
  @State private var showsSources = false
  @State private var copied = false

  var body: some View {
    let sources = AgentChatReplySource.collect(text)
    HStack(spacing: 12) {
      Button {
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(text, forType: .string)
      } label: {
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
      }
      .help(copied ? String(localized: "Copied") : String(localized: "Copy Reply"))
      .accessibilityLabel(copied ? "Copied" : "Copy Reply")
      .accessibilityIdentifier("scholium.chat.copyReply")
      .task(id: copied) {
        guard copied else { return }
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        copied = false
      }
      if !sources.isEmpty || context.hasMaterials {
        Button { showsSources = true } label: {
          Label("Sources", systemImage: "books.vertical")
        }
        .accessibilityIdentifier("scholium.chat.sources")
        .popover(isPresented: $showsSources, arrowEdge: .leading) {
          AgentChatSourcesView(sources: sources, context: context, openAttachment: openAttachment,
            previewMaterial: previewMaterial, close: { showsSources = false }) { source in
            showsSources = false
            if source.isNote { openNote(source.url) } else { openURL(source.url) }
          }
        }
      }
    }
    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
    .padding(.top, 4)
  }
}


struct AgentChatSourcesView: View {
  let sources: [AgentChatReplySource]
  var context: AgentChatReplySourceContext? = nil
  var openAttachment: ((AgentChatAttachment) -> Void)? = nil
  var previewMaterial: ((AgentChatLocalMaterial) async throws -> URL)? = nil
  let close: () -> Void
  let open: (AgentChatReplySource) -> Void
  @State private var expandedSources: Set<String> = []
  @State private var showsMaterials = false

  private var contentHeight: CGFloat {
    let expandedHeight = sources.filter { expandedSources.contains($0.id) }.reduce(CGFloat.zero) { height, source in
      switch context?.evidence(for: source.url) {
      case .note: return height + 200
      case .web(let access): return height + 48 + CGFloat(access.count) * 24
      default: return height
      }
    }
    let materialHeight = showsMaterials ? CGFloat((context?.attachments.count ?? 0) + (context?.localMaterials.count ?? 0)) * 64 : 0
    return min(380, max(180, 64 + CGFloat(sources.count) * 100
      + (context?.hasMaterials == true ? 56 : 0) + expandedHeight + materialHeight))
  }

  var body: some View {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Sources").font(.headline)
              Spacer()
              Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
              VStack(alignment: .leading, spacing: 14) {
                ForEach(sources) { source in
                  VStack(alignment: .leading, spacing: 4) {
                    Label(source.destination, systemImage: source.isNote ? "doc.text" : source.isWeb ? "globe" : "doc")
                      .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if source.isNote || source.isWeb {
                      Button(source.title) {
                        open(source)
                      }.buttonStyle(.link)
                    } else { Text(source.title).textSelection(.enabled) }
                    if let context {
                      AgentChatSourceEvidenceView(evidence: context.evidence(for: source.url),
                        isExpanded: Binding(get: { expandedSources.contains(source.id) }, set: { expanded in
                          if expanded { expandedSources.insert(source.id) }
                          else { expandedSources.remove(source.id) }
                        }))
                    }
                    if !source.isNote {
                      Text(source.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).textSelection(.enabled).help(source.url.absoluteString)
                    }
                  }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let context, context.hasMaterials {
                  DisclosureGroup("Materials for This Turn", isExpanded: $showsMaterials) {
                    VStack(alignment: .leading, spacing: 8) {
                      ForEach(context.attachments) { attachment in
                        AgentChatMaterialChip(attachment: attachment, remove: nil,
                          open: { openAttachment?(attachment) })
                      }
                      ForEach(context.localMaterials) { material in
                        AgentChatLocalMaterialChip(material: material,
                          preview: {
                            guard let previewMaterial else { throw AgentChatNoteMaterialError.unavailable }
                            return try await previewMaterial(material)
                          }, remove: nil, replace: nil)
                      }
                    }.padding(.top, 6)
                  }
                  .font(.callout)
                }
              }
            }
          }.padding().frame(width: 340, height: contentHeight)
            .font(.body).foregroundStyle(.primary)
            .tint(nil as Color?)
  }
}
