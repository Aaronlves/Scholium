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
    var isZotero: Bool { (try? ZoteroReference(url: url)) != nil }
    var destination: String {
        if isNote { return ScholiumL10n.string("Note") }
        if isZotero { return ScholiumL10n.string("Zotero") }
        return url.host ?? ScholiumL10n.string("Reference")
    }

    /// Shared by reply links, child replies and the Sources popover.
    static func externalURL(_ url: URL) -> URL? {
        if let reference = try? ZoteroReference(url: url) { return reference.url }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil ? url : nil
    }

    static func collect(_ text: String) -> [Self] {
        guard
            let parsed = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return [] }
        var seen: Set<URL> = []
        return parsed.runs.compactMap { run in
            guard let url = run.link, seen.insert(url).inserted else { return nil }
            return .init(url: url, title: String(parsed[run.range].characters))
        }
    }
}

/// Pure availability for the reply footer. Materials are supplied context;
/// Sources are claims or links made visible by the reply. Keeping this split
/// outside the view prevents one trigger from silently carrying two meanings.
struct AgentChatReplyActionAvailability: Equatable {
    let hasSources: Bool
    let hasMaterials: Bool

    init(sources: [AgentChatReplySource], hasMaterials: Bool) {
        self.hasSources = !sources.isEmpty
        self.hasMaterials = hasMaterials
    }
}

struct AgentChatReplyActions: View {
    let text: String
    let openNote: (URL) -> Void
    let context: AgentChatReplySourceContext
    let openAttachment: (AgentChatAttachment) -> Void
    let previewMaterial: (AgentChatLocalMaterial) async throws -> URL
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSources = false
    @State private var showsMaterials = false
    @State private var copied = false

    var body: some View {
        let sources = AgentChatReplySource.collect(text)
        let availability = AgentChatReplyActionAvailability(sources: sources, hasMaterials: context.hasMaterials)
        HStack(spacing: 12) {
            Button {
                NSPasteboard.general.clearContents()
                copied = NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .chatAccessory()
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .help(copied ? String(localized: "Copied") : String(localized: "Copy Reply"))
            .accessibilityLabel(copied ? "Copied" : "Copy Reply")
            .accessibilityIdentifier("scholium.chat.copyReply")
            .task(id: copied) {
                guard copied else { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                copied = false
            }
            if availability.hasSources {
                Button {
                    showsSources = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "books.vertical").chatAccessory()
                        Text("Sources")
                    }
                }
                .accessibilityIdentifier("scholium.chat.sources")
                .popover(isPresented: $showsSources, arrowEdge: .leading) {
                    AgentChatSourcesView(sources: sources, context: context, close: { showsSources = false }) { source in
                        showsSources = false
                        if source.isNote { openNote(source.url) } else { openURL(source.url) }
                    }
                }
            }
            if availability.hasMaterials {
                Button {
                    showsMaterials = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip").chatAccessory()
                        Text("Materials", bundle: .module)
                    }
                }
                .accessibilityIdentifier("scholium.chat.materials")
                .popover(isPresented: $showsMaterials, arrowEdge: .leading) {
                    AgentChatMaterialsView(
                        context: context, openAttachment: openAttachment,
                        previewMaterial: previewMaterial, close: { showsMaterials = false })
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
    let close: () -> Void
    let open: (AgentChatReplySource) -> Void
    @State private var expandedSources: Set<String> = []

    private var contentHeight: CGFloat {
        let expandedHeight = sources.filter { expandedSources.contains($0.id) }.reduce(CGFloat.zero) { height, source in
            switch context?.evidence(for: source.url) {
            case .note: return height + 200
            case .web(let access): return height + 48 + CGFloat(access.count) * 24
            case .zotero(let reports): return height + 80 + CGFloat(reports.count) * 120
            default: return height
            }
        }
        return min(380, max(180, 64 + CGFloat(sources.count) * 100 + expandedHeight))
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
                            if source.isNote || source.isWeb || source.isZotero {
                                Button(source.title) {
                                    open(source)
                                }.buttonStyle(.link)
                            } else {
                                Text(source.title).textSelection(.enabled)
                            }
                            if let context {
                                AgentChatSourceEvidenceView(
                                    evidence: context.evidence(for: source.url),
                                    isExpanded: Binding(
                                        get: { expandedSources.contains(source.id) },
                                        set: { expanded in
                                            if expanded { expandedSources.insert(source.id) } else { expandedSources.remove(source.id) }
                                        }))
                            }
                            if !source.isNote {
                                Text(source.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2).textSelection(.enabled).help(source.url.absoluteString)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding().frame(width: 340, height: contentHeight)
        .font(.body).foregroundStyle(.primary)
        .tint(nil as Color?)
    }
}

/// A dedicated context surface for material supplied to the turn. It is kept
/// separate from Sources so a researcher can distinguish what they supplied
/// from what the reply cites or links.
struct AgentChatMaterialsView: View {
    let context: AgentChatReplySourceContext
    let openAttachment: (AgentChatAttachment) -> Void
    let previewMaterial: (AgentChatLocalMaterial) async throws -> URL
    let close: () -> Void

    private var count: Int { context.attachments.count + context.localMaterials.count }
    private var contentHeight: CGFloat { min(360, max(180, 92 + CGFloat(count) * 76)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Materials", bundle: .module).font(.headline)
                    Text("Supplied for this turn", bundle: .module).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(context.attachments) { attachment in
                        AgentChatMaterialChip(
                            attachment: attachment, remove: nil,
                            open: { openAttachment(attachment) })
                    }
                    ForEach(context.localMaterials) { material in
                        AgentChatLocalMaterialChip(
                            material: material,
                            preview: { try await previewMaterial(material) }, remove: nil, replace: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(width: 340, height: contentHeight)
        .font(.body).foregroundStyle(.primary)
        .tint(nil as Color?)
        .accessibilityIdentifier("scholium.chat.materialsView")
    }
}
