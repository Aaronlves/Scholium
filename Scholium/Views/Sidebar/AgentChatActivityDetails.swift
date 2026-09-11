import AppKit
import ScholiumContracts
import SwiftUI

/// The same retained evidence is available in-place and in the diagnostic overview.
struct AgentChatActivityDetails: View {
  let activity: AgentChatActivity
  var openNote: ((URL) -> Void)? = nil
  @Environment(\.locale) private var locale
  @State private var outputWindow = AgentChatOutputWindow()
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
          Button { outputWindow.present(activity) } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right").chatAccessory()
          }.buttonStyle(.borderless)
            .help(Text("Open Output", bundle: .module))
            .accessibilityLabel(Text("Open Output", bundle: .module))
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
    .onChange(of: activity) { _, value in outputWindow.update(value) }
    .onDisappear { outputWindow.close() }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(activity.status.label(locale: locale)).font(.callout)
      AgentChatCommandFacts(activity: activity)
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
    ([activity.status.label(locale: locale), activity.commandExecution?.workingDirectory ?? "",
      activity.commandExecution?.exitCode.map { "exitCode: \($0)" } ?? "",
      activity.commandExecution?.durationMilliseconds.map { "durationMs: \($0)" } ?? "", activity.subject,
      activity.outputTruncated == true ? String(localized: "Earlier output exceeded the retention limit. The latest output is shown.") : "", activity.detail] + activity.files.map(\.path))
      .filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  private func copyDetails() {
    NSPasteboard.general.clearContents()
    copied = NSPasteboard.general.setString(copyText, forType: .string)
  }
}


private struct AgentChatCommandFacts: View {
  let activity: AgentChatActivity
  var body: some View {
    if let command = activity.commandExecution {
      VStack(alignment: .leading, spacing: 4) {
        if let code = command.exitCode { Text("Exit code: \(code)", bundle: .module) }
        if let duration = command.durationMilliseconds { Text("Duration: \(duration) ms", bundle: .module) }
        if let directory = command.workingDirectory {
          Text(verbatim: directory).textSelection(.enabled)
        }
      }.font(.caption).foregroundStyle(.secondary)
    }
  }
}

@MainActor
private final class AgentChatOutputWindow: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private var host: NSHostingController<AgentChatOutputContents>?
  func present(_ activity: AgentChatActivity) {
    if let window { update(activity); window.makeKeyAndOrderFront(nil); return }
    let host = NSHostingController(rootView: AgentChatOutputContents(activity: activity))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = ScholiumL10n.string(activity.kind == .command ? "Command Output" : "Operation Details")
    window.contentViewController = host
    window.setContentSize(NSSize(width: 640, height: 480))
    window.contentMinSize = NSSize(width: 420, height: 280)
    window.isReleasedWhenClosed = false; window.delegate = self
    self.window = window; self.host = host
    window.center(); window.makeKeyAndOrderFront(nil)
  }
  func update(_ activity: AgentChatActivity) { host?.rootView = AgentChatOutputContents(activity: activity) }
  func close() { window?.close(); window = nil; host = nil }
  func windowWillClose(_ notification: Notification) { window = nil; host = nil }
}

private struct AgentChatOutputContents: View {
  let activity: AgentChatActivity
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(activity.status.label).font(.headline)
      AgentChatCommandFacts(activity: activity)
      ScrollView([.horizontal, .vertical]) {
        VStack(alignment: .leading, spacing: 12) {
          Text(verbatim: activity.subject)
          ForEach(Array(activity.files.enumerated()), id: \.offset) { _, file in Text(verbatim: file.path) }
          if activity.outputTruncated == true {
            Text("Earlier output exceeded the retention limit. The latest output is shown.")
          }
          if activity.detail.isEmpty {
            Text(activity.status.isActive ? "Waiting for output…" : "No additional output was retained.")
          } else { Text(verbatim: activity.detail) }
        }.font(.body.monospaced()).textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: false)
      }.defaultScrollAnchor(.topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor)).tint(nil as Color?)
  }
}
