import AppKit
import ScholiumContracts
import SwiftUI

/// SwiftUI's ordinary String equality ignores canonical Unicode byte changes.
/// An open output reader and its copy payload must observe those replacements
/// while retaining the activity's ordinary metadata change detection.
struct AgentChatActivityPreviewIdentity: Equatable, Sendable {
    let activity: AgentChatActivity

    init(_ activity: AgentChatActivity) { self.activity = activity }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        let left = lhs.activity
        let right = rhs.activity
        guard left == right,
            ScholiumExactUTF8.equal(left.subject, right.subject),
            ScholiumExactUTF8.equal(left.detail, right.detail),
            zip(left.files, right.files).allSatisfy({ ScholiumExactUTF8.equal($0.0.path, $0.1.path) })
        else { return false }
        switch (left.commandExecution?.workingDirectory, right.commandExecution?.workingDirectory) {
        case (nil, nil): return true
        case (.some(let left), .some(let right)): return ScholiumExactUTF8.equal(left, right)
        default: return false
        }
    }
}

/// Retained execution facts and output, inspected from the activity itself.
struct AgentChatActivityDetails: View {
    let activity: AgentChatActivity
    var openNote: ((URL) -> Void)? = nil
    @Environment(\.locale) private var locale
    @State private var preview = ScholiumContentPreview()
    @State private var originView: NSView?
    @State private var copied = false
    @State private var contentHeight: CGFloat = 180

    var body: some View {
        details
            .font(.callout)
            .padding(.vertical, 6)
            .contextMenu { Button("Copy Details", action: copyDetails) }
            .onChange(of: AgentChatActivityPreviewIdentity(activity)) { _, value in
                guard preview.panel != nil else { return }
                let snapshot = value.activity
                preview.update(
                    title: Self.outputPreviewTitle(for: snapshot),
                    copyText: Self.outputCopyText(for: snapshot, locale: locale)
                ) { AgentChatOutputContents(activity: snapshot).equatable() }
            }
            .onDisappear {
                preview.close()
                originView = nil
            }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.status.label(locale: locale))
                Spacer()
                Button {
                    guard let originView else { return }
                    preview.present(title: previewTitle, copyText: copyText, from: originView) {
                        AgentChatOutputContents(activity: activity).equatable()
                    }
                } label: {
                    ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.expand.symbol, placement: .action)
                }
                .buttonStyle(ScholiumContentActionButtonStyle())
                .background(ScholiumPreviewAttachment { originView = $0 })
                .help(Text("Open Output", bundle: .module))
                .accessibilityLabel(Text("Open Output", bundle: .module))
                Button(action: copyDetails) {
                    ScholiumSidebarCopyIcon(copied: copied)
                }
                .buttonStyle(ScholiumContentActionButtonStyle())
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
            AgentChatCommandFacts(activity: activity).equatable()
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
                        Label(file.path, systemImage: ScholiumSidebarItem.note.symbol)
                            .foregroundStyle(.tint)
                            .underline()
                    }
                    .buttonStyle(.link)
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
        Self.outputPreviewTitle(for: activity)
    }

    private static func outputPreviewTitle(for activity: AgentChatActivity) -> String {
        ScholiumL10n.string(activity.kind == .command ? "Command Output" : "Operation Details")
    }

    private var copyText: String {
        Self.outputCopyText(for: activity, locale: locale)
    }

    static func outputCopyText(for activity: AgentChatActivity, locale: Locale) -> String {
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

private struct AgentChatCommandFacts: View, Equatable {
    private let identity: AgentChatActivityPreviewIdentity
    private var activity: AgentChatActivity { identity.activity }

    init(activity: AgentChatActivity) { identity = .init(activity) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }

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

struct AgentChatOutputContents: View, Equatable {
    private let identity: AgentChatActivityPreviewIdentity
    var activity: AgentChatActivity { identity.activity }

    init(activity: AgentChatActivity) { identity = .init(activity) }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(activity.status.label).font(.headline)
            AgentChatCommandFacts(activity: activity).equatable()
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
