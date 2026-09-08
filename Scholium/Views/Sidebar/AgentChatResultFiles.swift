import ScholiumContracts
import SwiftUI

/// Reply links remain references, not receipts proving that a file was read or changed.
struct AgentChatResultFile: Identifiable, Equatable {
  let url: URL
  let title: String
  var id: String { url.absoluteString }

  static func collect(_ text: String) -> [Self] {
    AgentChatReplySource.collect(text).filter(\.isNote).map { .init(url: $0.url, title: $0.title) }
  }
}

struct AgentChatResultFiles: View {
  let files: [AgentChatResultFile]
  let open: (URL) -> Void
  let showInLibrary: (URL) -> Void
  let showAll: () -> Void

  var body: some View {
    if !files.isEmpty {
      ViewThatFits(in: .horizontal) {
        row(limit: 2)
        row(limit: 1)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Referenced Files")
    }
  }

  private func row(limit: Int) -> some View {
    HStack(spacing: 6) {
      ForEach(files.prefix(limit)) { file in
        Menu {
          Button("Open Note") { open(file.url) }
          Button("Show in Library") { showInLibrary(file.url) }
        } label: {
          Label(file.title, systemImage: "doc.text")
            .lineLimit(1).truncationMode(.middle)
            .frame(minWidth: 90, maxWidth: 160, alignment: .leading)
            .padding(8)
        } primaryAction: { open(file.url) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5).allowsHitTesting(false) }
        .help(file.title)
      }
      if files.count > limit {
        Button(action: showAll) { Text(verbatim: "+\(files.count - limit)") }
          .accessibilityLabel("More Files: \(files.count - limit)")
          .buttonStyle(.borderless).foregroundStyle(.secondary).fixedSize()
      }
    }.font(.caption)
  }
}

/// Completed operation output can surface a file even when the final prose omits its link.
struct AgentChatOperationFiles: View {
  let files: [AgentChatFileSummary]
  let open: (URL) -> Void
  let showChanges: (UUID) -> Void
  let showAll: () -> Void

  var body: some View {
    if let first = files.first {
      HStack(spacing: 6) {
        Button {
          if let change = first.changeIDs.last { showChanges(change) }
          else if let note = first.file.noteID, first.file.effect != .trashed {
            open(AgentChatReference.url(noteID: note))
          } else { showAll() }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "doc.text").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text((first.file.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
              Text(first.source == .runtime ? ScholiumL10n.string("Runtime Report") : first.file.effect?.label ?? "")
                .foregroundStyle(.secondary).lineLimit(1)
            }
          }.frame(maxWidth: 180, alignment: .leading).padding(8)
        }
        .buttonStyle(.borderless)
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5).allowsHitTesting(false) }
        .help(first.file.path)
        if files.count > 1 {
          Button(action: showAll) { Text(verbatim: "+\(files.count - 1)") }
            .accessibilityLabel("More Files: \(files.count - 1)")
            .buttonStyle(.borderless)
        }
      }.font(.caption)
    }
  }
}
