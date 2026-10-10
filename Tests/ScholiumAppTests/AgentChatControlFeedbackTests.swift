import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat control feedback", .serialized)
@MainActor
struct AgentChatControlFeedbackTests {
    @Test(
        "Composer menus and buttons have equal, nonoverlapping pointer regions",
        arguments: [
            (AgentChatPermission.ask, "en"), (AgentChatPermission.fullAccess, "en"),
            (AgentChatPermission.ask, "zh-Hans"), (AgentChatPermission.fullAccess, "zh-Hans"),
        ])
    func composerPointerRegions(permission: AgentChatPermission, language: String) async throws {
        let geometry = ControlGeometryFixture()
        let content = HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Menu {
                Button("Choose File…", action: {})
            } label: {
                AgentChatComposerIcon(content: .add)
                    .agentChatComposerControl()
            }
            .scholiumContentActionMenu().menuIndicator(.hidden).agentChatComposerControl()
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("controls")) }) { geometry.frames[0] = $0 }
            AgentChatPermissionMenu(permission: permission, isEnabled: true, select: { _ in })
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("controls")) }) { geometry.frames[4] = $0 }
            Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
            AgentChatContextMeter(usage: .init(lastTurnTokens: 2000, totalTokens: 2000, capacity: 8000), open: {})
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("controls")) }) { geometry.frames[1] = $0 }
            AgentChatConfigurationMenu(
                models: [], preferences: .init(), selectedModel: nil,
                isEnabled: true, canSelectModel: false,
                selectModel: { _ in }, selectEffort: { _ in }, selectWebSearch: { _ in }
            )
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("controls")) }) { geometry.frames[2] = $0 }
            AgentChatComposerActionButton(
                state: .ready, hasInput: true, canSend: true, queuesInput: false, submit: {}, stop: {}
            )
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("controls")) }) { geometry.frames[3] = $0 }
        }.coordinateSpace(name: "controls")
            .padding(ScholiumSidebarLayout.edgeInset + ScholiumSidebarLayout.rowInset)
            .frame(width: ScholiumMetrics.Library.minimumReadableWidth, height: 80)
            .environment(\.locale, Locale(identifier: language))
        let host = NSHostingView(rootView: content)
        let window = makeWindow(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host, window: window)
        #expect(!descendants(host).contains { $0 is ScholiumPointerTrackingView }, "Native controls must have no competing pointer-state owner")
        try #require(geometry.frames.count == 5)
        let frames = geometry.frames.values.sorted { $0.minX < $1.minX }
        for (left, right) in zip(frames, frames.dropFirst()) { #expect(left.maxX <= right.minX) }
        for frame in frames { #expect(frame.width >= 28 && frame.height >= 28) }
        let centers = frames.map(\.midY)
        #expect((centers.max() ?? 0) - (centers.min() ?? 0) < 1)
        #expect(frames.allSatisfy { $0.maxX <= host.bounds.width })
        for index in 0..<3 { #expect(geometry.frames[index]?.width == 28) }
        #expect(geometry.frames[3]?.width == ScholiumMetrics.AgentChat.composerPrimaryControlTarget)
    }

    @Test("Unreported context has no button or empty control slot")
    func unavailableContextIsAbsent() {
        let absent = NSHostingView(rootView: AgentChatContextMeter(usage: nil, open: {}))
        #expect(absent.fittingSize == .zero)
        let unknownCapacity = NSHostingView(
            rootView: AgentChatContextMeter(
                usage: .init(lastTurnTokens: 2000, totalTokens: 2000, capacity: nil), open: {}))
        #expect(unknownCapacity.fittingSize == .zero)
        let reported = NSHostingView(
            rootView: AgentChatContextMeter(
                usage: .init(lastTurnTokens: 0, totalTokens: 0, capacity: 8000), open: {}))
        #expect(reported.fittingSize.width >= 28 && reported.fittingSize.height >= 28)
    }

    @Test("The send circle and the nearest input corner have the same center")
    func concentricSendAndInputCorner() async throws {
        let geometry = ControlGeometryFixture()
        let dock = AgentChatInputDock(
            requestID: nil, requestTitle: "", requestCount: 0, isActive: true,
            isReadingHistory: false, isEditingDraft: false, composerIsFocused: .constant(false),
            request: { EmptyView() },
            composer: {
                AgentChatComposerLayout(
                    hasPreparedContent: false, prepared: { EmptyView() },
                    input: { _ in Text("Synthetic draft").frame(height: 40) },
                    controls: {
                        HStack {
                            Spacer(minLength: 0)
                            AgentChatComposerActionButton(
                                state: .ready, hasInput: true, canSend: true, queuesInput: false,
                                submit: {}, stop: {}
                            )
                            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("dock")) }) {
                                geometry.frames[1] = $0
                            }
                        }
                    })
            }
        )
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("dock")) }) { geometry.frames[0] = $0 }
        .coordinateSpace(name: "dock")
        .frame(width: ScholiumMetrics.Library.minimumReadableWidth)
        let host = NSHostingView(rootView: dock)
        let window = makeWindow(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host, window: window)
        let shell = try #require(geometry.frames[0])
        let action = try #require(geometry.frames[1])
        let radius = ScholiumMetrics.AgentChat.composerCornerRadius
        #expect(abs(shell.maxX - radius - action.midX) < 1)
        #expect(abs(shell.maxY - radius - action.midY) < 1)
        #expect(action.width >= ScholiumMetrics.AgentChat.composerPrimaryVisualDiameter)
    }

    @Test("Unboxed content commands retain their geometry and distinguish availability")
    func commandAvailability() async throws {
        func content(enabled: Bool) -> some View {
            Button("Refresh — 刷新", action: {})
                .buttonStyle(ScholiumContentActionButtonStyle())
                .disabled(!enabled).padding()
        }
        let host = NSHostingView(rootView: content(enabled: true))
        let window = makeWindow(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host, window: window)
        let size = host.fittingSize
        let available = try rendered(host)
        host.rootView = content(enabled: false)
        try await settle(host, window: window)
        #expect(host.fittingSize == size)
        #expect(try rendered(host) != available, "Native disabled feedback must remain visible without a background plate")
    }

    @Test("Unavailable question delivery keeps the bound answer editable across availability changes")
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
        let fields = descendants(host).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        #expect(!fields.isEmpty && fields.allSatisfy { $0.isEnabled })
        host.rootView = content(canSubmit: true)
        try await settle(host, window: window)
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

    private func rendered(_ host: NSView) throws -> Data {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class ControlGeometryFixture {
    var frames: [Int: CGRect] = [:]
}
