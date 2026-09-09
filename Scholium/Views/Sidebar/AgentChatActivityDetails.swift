import AppKit
import ScholiumContracts
import SwiftUI

/// The same retained evidence is available in-place and in the diagnostic overview.
struct AgentChatActivityDetails: View {
  let activity: AgentChatActivity
  var openNote: ((URL) -> Void)? = nil
  @Environment(\.locale) private var locale
  @State private var copied = false
  @State private var contentHeight: CGFloat = 180
  @State private var isHovered = false
  @FocusState private var copyIsFocused: Bool

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(activity.kind == .command ? "Command" : "Operation").foregroundStyle(.secondary)
          Spacer()
          Button(action: copyDetails) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .chatAccessory()
              .opacity(isHovered || copyIsFocused || copied ? 1 : 0)
          }
            .buttonStyle(.plain)
            .focused($copyIsFocused)
            .accessibilityLabel(copied ? "Copied" : "Copy Details")
            .help(copied ? String(localized: "Copied") : String(localized: "Copy Details"))
            .accessibilityIdentifier("scholium.chat.copyActivityDetails")
            .task(id: copied) {
              guard copied else { return }
              do { try await Task.sleep(for: .seconds(2)) } catch { return }
              copied = false
            }
        }
        ScrollView {
          content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(180, contentHeight))
        .accessibilityIdentifier("scholium.chat.activityOutput")
      }
    }
    .font(.callout)
    .padding(.vertical, 6)
    .scholiumHoverState { isHovered = $0 }
    .contextMenu { Button("Copy Details", action: copyDetails) }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !activity.subject.isEmpty {
        Text(verbatim: activity.subject).monospaced()
      }
      if activity.outputTruncated == true {
        Text("Earlier output exceeded the retention limit. The latest output is shown.")
          .foregroundStyle(.secondary)
      }
      if !activity.detail.isEmpty {
        Text(activity.status == .failed ? "Error" : "Output").foregroundStyle(.secondary)
        Text(verbatim: activity.detail).monospaced()
      } else {
        Text(activity.status.isActive ? "Waiting for output…" : "No additional output was retained.")
          .foregroundStyle(.secondary)
      }
      ForEach(Array(activity.files.enumerated()), id: \.offset) { _, file in
        if let id = file.noteID, file.effect != .trashed, let openNote {
          Button(file.path) { openNote(AgentChatReference.url(noteID: id)) }
            .buttonStyle(.link).help("Open Note")
        } else { Text(verbatim: file.path).monospaced() }
      }
    }
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var copyText: String {
    ([activity.status.label(locale: locale), activity.subject,
      activity.outputTruncated == true ? String(localized: "Earlier output exceeded the retention limit. The latest output is shown.") : "", activity.detail] + activity.files.map(\.path))
      .filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  private func copyDetails() {
    NSPasteboard.general.clearContents()
    copied = NSPasteboard.general.setString(copyText, forType: .string)
  }
}
