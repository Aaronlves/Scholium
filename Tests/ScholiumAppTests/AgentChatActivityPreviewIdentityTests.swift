import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Activity output preview byte identity", .serialized)
@MainActor
struct AgentChatActivityPreviewIdentityTests {
    @Test("Canonical-equivalent replacement invalidates each raw reader and copy field", arguments: ["subject", "detail", "path", "directory"])
    func exactPreviewFields(field: String) throws {
        let composed = "Café synthetic 中文😀"
        let decomposed = "Cafe\u{301} synthetic 中文😀"
        var first = Self.activity(detail: "unchanged output")
        var second = first
        switch field {
        case "subject":
            first.subject = composed
            second.subject = decomposed
        case "detail":
            first.detail = composed
            second.detail = decomposed
        case "path":
            first.files = [.init(path: composed)]
            second.files = [.init(path: decomposed)]
        case "directory":
            first.commandExecution = .init(workingDirectory: composed, exitCode: nil, durationMilliseconds: nil)
            second.commandExecution = .init(workingDirectory: decomposed, exitCode: nil, durationMilliseconds: nil)
        default: Issue.record("Unknown synthetic field")
        }
        try #require(first == second, "This fixture must reproduce the canonical-equality omission")
        #expect(AgentChatActivityPreviewIdentity(first) != AgentChatActivityPreviewIdentity(second))
        #expect(AgentChatOutputContents(activity: first) != AgentChatOutputContents(activity: second))
        #expect(
            !AgentChatActivityDetails.outputCopyText(for: first, locale: Locale(identifier: "en"))
                .utf8.elementsEqual(AgentChatActivityDetails.outputCopyText(for: second, locale: Locale(identifier: "en")).utf8))
        #expect(AgentChatActivityPreviewIdentity(second) == AgentChatActivityPreviewIdentity(second))
    }

    @Test("Ordinary status, command, retention and file changes still refresh output identity")
    func ordinaryMetadataChanges() {
        let original = Self.activity(detail: "exact output")
        let identity = AgentChatActivityPreviewIdentity(original)
        var changed = original
        changed.status = .failed
        #expect(identity != AgentChatActivityPreviewIdentity(changed))
        changed = original
        changed.kind = .command
        #expect(identity != AgentChatActivityPreviewIdentity(changed))
        changed = original
        changed.outputTruncated = true
        #expect(identity != AgentChatActivityPreviewIdentity(changed))
        changed = original
        changed.commandExecution = .init(workingDirectory: nil, exitCode: 2, durationMilliseconds: 80)
        #expect(identity != AgentChatActivityPreviewIdentity(changed))
        changed = original
        changed.files = [.init(path: "Synthetic.md", noteID: UUID(), effect: .created)]
        #expect(identity != AgentChatActivityPreviewIdentity(changed))
        changed = original
        changed.detail = String(decoding: Array(original.detail.utf8), as: UTF8.self)
        #expect(identity == AgentChatActivityPreviewIdentity(changed))
    }

    @MainActor
    private final class Model: ObservableObject {
        @Published var activity: AgentChatActivity
        let preview = ScholiumContentPreview(animates: false)
        var copyEvaluations = 0
        init(_ activity: AgentChatActivity) { self.activity = activity }
    }

    private final class OutputProbeView: NSView {
        var readerText = ""
        var copyText = ""
    }

    @MainActor
    private struct OutputProbe: NSViewRepresentable {
        let contents: AgentChatOutputContents
        let copyText: String
        func makeNSView(context: Context) -> OutputProbeView { OutputProbeView() }
        func updateNSView(_ view: OutputProbeView, context: Context) {
            view.readerText = contents.activity.detail
            view.copyText = copyText
        }
    }

    /// Exercise SwiftUI's actual identity observation and the native preview
    /// owner with the production output View's exact Equatable identity and copy
    /// projection. If that View falls back to canonical activity equality, the
    /// native probe will miss this replacement too. This does not inspect AX,
    /// touch the system pasteboard or claim full interface QA.
    @MainActor
    private struct Fixture: View {
        @ObservedObject var model: Model
        var body: some View {
            Text("Synthetic output origin")
                .onChange(of: AgentChatActivityPreviewIdentity(model.activity)) { _, value in
                    guard model.preview.panel != nil else { return }
                    model.copyEvaluations += 1
                    let copy = AgentChatActivityDetails.outputCopyText(for: value.activity, locale: Locale(identifier: "en"))
                    model.preview.update(title: "Operation Details", copyText: copy) {
                        OutputProbe(contents: AgentChatOutputContents(activity: value.activity), copyText: copy)
                    }
                }
        }
    }

    @Test("An already open native preview follows Unicode replacement and ordinary status without reopening")
    func openPreviewRefreshesExactPayloads() async throws {
        _ = NSApplication.shared
        let initial = Self.activity(detail: "Café retained synthetic output")
        let model = Model(initial)
        let host = NSHostingView(rootView: Fixture(model: model))
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            model.preview.close(restoringFocus: false)
            window.contentView = nil
            window.close()
        }
        window.makeKeyAndOrderFront(nil)
        await Self.settle(host)
        let initialCopy = AgentChatActivityDetails.outputCopyText(for: initial, locale: Locale(identifier: "en"))
        model.preview.present(title: "Operation Details", copyText: initialCopy, from: host) {
            OutputProbe(contents: AgentChatOutputContents(activity: initial), copyText: initialCopy)
        }
        let panel = try #require(model.preview.panel)
        let root = try #require(panel.contentView)
        await Self.settle(root)
        let probe = try #require(Self.probe(in: root))
        #expect(probe.readerText.utf8.elementsEqual(initial.detail.utf8))
        #expect(probe.copyText.utf8.elementsEqual(initialCopy.utf8))

        var replacement = initial
        replacement.detail = "Cafe\u{301} retained synthetic output"
        try #require(initial == replacement && !initial.detail.utf8.elementsEqual(replacement.detail.utf8))
        model.activity = replacement
        await Self.settle(host)
        await Self.settle(root)
        #expect(model.preview.panel === panel && Self.probe(in: root) === probe)
        #expect(model.copyEvaluations == 1)
        #expect(probe.readerText.utf8.elementsEqual(replacement.detail.utf8))
        #expect(probe.copyText.utf8.elementsEqual(AgentChatActivityDetails.outputCopyText(for: replacement, locale: Locale(identifier: "en")).utf8))

        replacement.status = .failed
        model.activity = replacement
        await Self.settle(host)
        await Self.settle(root)
        #expect(model.preview.panel === panel)
        #expect(model.copyEvaluations == 2)
        #expect(probe.copyText.utf8.elementsEqual(AgentChatActivityDetails.outputCopyText(for: replacement, locale: Locale(identifier: "en")).utf8))

        model.preview.close(restoringFocus: false)
        replacement.detail += " later closed output"
        model.activity = replacement
        await Self.settle(host)
        #expect(model.preview.panel == nil && model.copyEvaluations == 2, "Closed previews skip copy projection and native update")
        #expect(initial.detail.utf8.elementsEqual("Café retained synthetic output".utf8))
    }

    private static func activity(detail: String) -> AgentChatActivity {
        .init(kind: .tool, status: .running, source: .runtime, subject: "Synthetic tool", detail: detail)
    }

    private static func probe(in root: NSView) -> OutputProbeView? {
        if let probe = root as? OutputProbeView { return probe }
        return root.subviews.lazy.compactMap { probe(in: $0) }.first
    }

    private static func settle(_ view: NSView) async {
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
