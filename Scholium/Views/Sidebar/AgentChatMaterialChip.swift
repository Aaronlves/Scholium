import ScholiumContracts
import SwiftUI

/// Compact context attachment, with exact snapshot detail on demand. The
/// conversation and runtime continue to receive the untouched source bytes.
struct AgentChatMaterialChip: View {
    let attachment: AgentChatAttachment
    let remove: (() -> Void)?
    let open: () -> Void
    @State private var showsPreview = false

    private var title: String {
        URL(fileURLWithPath: attachment.relativePath).deletingPathExtension().lastPathComponent
    }
    private var excerpt: String { ResearchExcerptPresentation.readableText(attachment.text) }

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 8) {
                Button { showsPreview.toggle() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(title, systemImage: "text.quote").lineLimit(1).font(.subheadline)
                        Text(excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(attachment.relativePath)
                .accessibilityLabel(Text("Preview material: \(title)"))
                .accessibilityValue(String(excerpt.prefix(120)))
                if let remove {
                    Button(action: remove) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Remove Material").accessibilityLabel(Text("Remove material: \(title)"))
                }
            }
        }
        .frame(width: 200)
        .fixedSize(horizontal: false, vertical: true)
        .popover(isPresented: $showsPreview, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Button { showsPreview = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                }
                Text("Attached Passage").font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(excerpt).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 280)
                Button("Open Source") { showsPreview = false; open() }
            }
            .padding().frame(width: 320)
            .tint(nil as Color?)
        }
        .accessibilityIdentifier("scholium.chat.material.\(attachment.id)")
    }
}
