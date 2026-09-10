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
  private var extent: String {
    String(
      localized: attachment.extent == .wholeNote ? "Whole Note" : "Attached Passage",
      bundle: .module
    )
  }
  private var source: String {
    String(
      localized: attachment.source == .editorSnapshot ? "Editor Snapshot" : "Saved Source",
      bundle: .module
    )
  }

  var body: some View {
    GroupBox {
      HStack(alignment: .top, spacing: 8) {
        Button {
          showsPreview.toggle()
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: attachment.extent == .wholeNote ? "doc.text" : "text.quote").lineLimit(1).font(
              .subheadline)
            if attachment.extent == .wholeNote {
              Text(extent).font(.caption).foregroundStyle(.secondary)
            } else {
              Text(excerpt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(attachment.relativePath)
        .accessibilityLabel(Text("Preview material: \(title)"))
        .accessibilityValue(Text("\(extent), \(source): \(excerpt.prefix(120))"))
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
          Button {
            showsPreview = false
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain).accessibilityLabel("Close")
        }
        GroupBox {
          VStack(alignment: .leading, spacing: 6) {
            Text(extent).font(.caption).foregroundStyle(.secondary)
            Text(source).font(.caption).foregroundStyle(.secondary)
            if let role = attachment.vaultRole {
              Text(LocalizedStringKey(role.displayName)).font(.caption).foregroundStyle(.secondary)
            }
            Text(attachment.relativePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
          }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
        GroupBox {
          ScrollView { Text(attachment.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            .frame(maxHeight: 280).padding(4)
        }
        Button("Open Source") {
          showsPreview = false
          open()
        }
      }
      .padding().frame(width: 320)
      .tint(nil as Color?)
    }
    .accessibilityIdentifier("scholium.chat.material.\(attachment.id)")
  }
}
