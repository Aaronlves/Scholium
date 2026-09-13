import AppKit
import ScholiumContracts
import SwiftUI

/// The same retained evidence is available in-place and in the diagnostic overview.
struct AgentChatActivityDetails: View {
    let activity: AgentChatActivity
    var isInline = false
    var openNote: ((URL) -> Void)? = nil
    @Environment(\.locale) private var locale
    @State private var preview = ScholiumContentPreview()
    @State private var originView: NSView?
    @State private var copied = false
    @State private var contentHeight: CGFloat = 180
    @State private var isHovered = false
    @FocusState private var copyIsFocused: Bool

    var body: some View {
        Group {
            if isInline { details } else { GroupBox { details } }
        }
        .font(.callout)
        .padding(.vertical, 6)
        .scholiumHoverState { isHovered = $0 }
        .contextMenu { Button("Copy Details", action: copyDetails) }
        .onChange(of: activity) { _, value in
            preview.update(title: previewTitle, copyText: copyText) { AgentChatOutputContents(activity: value) }
        }
        .onDisappear {
            preview.close()
            originView = nil
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isInline {
                    Text(activity.status.label(locale: locale))
                } else {
                    Text(activity.kind == .command ? "Command" : "Operation").foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    guard let originView else { return }
                    preview.present(title: previewTitle, copyText: copyText, from: originView) {
                        AgentChatOutputContents(activity: activity)
                    }
                } label: {
                    ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.expand.symbol, placement: .action)
                }
                .buttonStyle(
                    ScholiumContentControlButtonStyle(
                        isHovering: isHovered,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                )
                .scholiumActivationPointer()
                .background(ScholiumPreviewAttachment { originView = $0 })
                .help(Text("Open Output", bundle: .module))
                .accessibilityLabel(Text("Open Output", bundle: .module))
                Button(action: copyDetails) {
                    ScholiumSidebarCopyIcon(copied: copied)
                        .opacity(isInline || isHovered || copyIsFocused || copied ? 1 : 0)
                }
                .buttonStyle(
                    ScholiumContentControlButtonStyle(
                        isFocused: copyIsFocused,
                        isHovering: isHovered,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                )
                .scholiumActivationPointer()
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
                content.onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
            }
            .frame(height: min(180, contentHeight))
            .accessibilityIdentifier("scholium.chat.activityOutput")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isInline { Text(activity.status.label(locale: locale)).font(.callout) }
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
                    Button {
                        openNote(AgentChatReference.url(noteID: id))
                    } label: {
                        Text(file.path)
                            .scholiumContentControlInk(
                                resting: .primaryText,
                                emphasized: .accent
                            )
                            .underline()
                    }
                    .buttonStyle(.link)
                    .scholiumActivationPointer()
                    .scholiumContentControlPointerFeedback(
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                    .help("Open Note")
                    .contextMenu { AgentChatNoteMenu(url: AgentChatReference.url(noteID: id)) }
                } else {
                    Text(verbatim: file.path).monospaced()
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewTitle: String {
        ScholiumL10n.string(activity.kind == .command ? "Command Output" : "Operation Details")
    }

    private var copyText: String {
        ([
            activity.status.label(locale: locale), activity.commandExecution?.workingDirectory ?? "",
            activity.commandExecution?.exitCode.map { "exitCode: \($0)" } ?? "",
            activity.commandExecution?.durationMilliseconds.map { "durationMs: \($0)" } ?? "", activity.subject,
            activity.outputTruncated == true ? String(localized: "Earlier output exceeded the retention limit. The latest output is shown.") : "",
            activity.detail,
        ] + activity.files.map(\.path))
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
                    } else {
                        Text(verbatim: activity.detail)
                    }
                }.font(.body.monospaced()).textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }.defaultScrollAnchor(.topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)).tint(nil as Color?)
    }
}
