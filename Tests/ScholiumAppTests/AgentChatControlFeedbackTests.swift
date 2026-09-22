import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat control feedback", .serialized)
@MainActor
struct AgentChatControlFeedbackTests {
    @Test("Composer menus and buttons have equal, nonoverlapping pointer regions")
    func composerPointerRegions() async throws {
        let content = HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Menu {
                Button("Choose File…", action: {})
            } label: {
                AgentChatComposerIcon(content: .add)
                    .agentChatComposerControl()
            }
            .scholiumContentActionMenu().menuIndicator(.hidden).agentChatComposerControl()
            AgentChatContextMeter(usage: nil, open: {})
            AgentChatConfigurationMenu(
                models: [], preferences: .init(), selectedModel: nil,
                permission: .ask, isEnabled: true, canSelectModel: false,
                selectModel: { _ in }, selectEffort: { _ in }, selectPermission: { _ in }, selectWebSearch: { _ in })
            AgentChatComposerActionButton(
                state: .ready, hasInput: true, canSend: true, queuesInput: false, submit: {}, stop: {})
        }.padding().frame(width: 220, height: 80)
        let host = NSHostingView(rootView: content)
        let window = makeWindow(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host, window: window)
        let trackers = descendants(host).compactMap { $0 as? ScholiumPointerTrackingView }
        try #require(trackers.count == 4)
        let frames = trackers.map { $0.convert($0.bounds, to: host) }.sorted { $0.minX < $1.minX }
        for frame in frames {
            #expect(abs(frame.width - 28) < 0.5 && abs(frame.height - 28) < 0.5)
            #expect(abs(frame.midY - frames[0].midY) < 0.5)
        }
        for (left, right) in zip(frames, frames.dropFirst()) { #expect(left.maxX < right.minX) }
        for tracker in trackers { #expect(tracker.hitTest(.zero) == nil) }
        let buttons = descendants(host).compactMap { $0 as? NSButton }
        // Button-style Menus use SwiftUI's complete label region instead of
        // the legacy 18pt NSPopUpButton; the other two remain native buttons.
        try #require(buttons.count == 2)
        for button in buttons {
            #expect(button.bounds.width >= 28 && button.bounds.height >= 28, "Native activation region: \(button.bounds)")
        }
    }

    @Test("Unavailable question delivery disables final options and Skip but leaves the answer field editable")
    func questionAdmission() async throws {
        var answers: [String: AgentChatQuestionAnswer] = ["q": .text("Retain this answer")]
        var replies = 0
        let question = AgentChatQuestion(
            id: "q", prompt: "Choose a source", options: [.init(label: "Primary text", description: "")],
            allowsOther: true, isSecret: false)
        func content(canSubmit: Bool) -> some View {
            AgentChatQuestionForm(
                questions: [question], answers: Binding(get: { answers }, set: { answers = $0 }),
                isSubmitting: false, failure: nil, canSubmit: canSubmit,
                reply: { replies += 1 }, skip: { replies += 1 }
            ).padding().frame(width: 300)
        }
        let host = NSHostingView(rootView: content(canSubmit: false))
        let window = makeWindow(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host, window: window)
        let buttons = descendants(host).compactMap { $0 as? NSButton }
        try #require(buttons.count == 3)
        #expect(buttons.allSatisfy { !$0.isEnabled })
        let fields = descendants(host).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        #expect(!fields.isEmpty && fields.allSatisfy { $0.isEnabled })
        host.rootView = content(canSubmit: true)
        try await settle(host, window: window)
        #expect(descendants(host).compactMap { $0 as? NSButton }.allSatisfy { $0.isEnabled })
        #expect(answers["q"] == .text("Retain this answer") && replies == 0)
    }

    private func makeWindow<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
        _ = NSApplication.shared
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    private func settle(_ host: NSView, window: NSWindow) async throws {
        for _ in 0..<5 {
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }

}
