import AppKit
import Combine
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Sidebar transient content sizing", .serialized)
@MainActor
struct SidebarTransientSizingTests {
    @Test(
        "Native short file forms fit their content and retain long paths", .enabled(if: ScholiumTestEnvironment.providesDisplayEvidence),
        arguments: [false, true])
    func nativeFileForms(chineseDark: Bool) async throws {
        let state = SidebarSizingFixtureState()
        let fixture = makeSheetFixture(state, chineseDark: chineseDark)
        defer { fixture.close() }
        let parentFrame = fixture.window.frame
        for surface in [SidebarSizingSurface.move, .folder, .folderMove] {
            state.surface = surface
            state.isPresented = true
            try await wait { fixture.window.attachedSheet?.isVisible == true }
            let sheet = try #require(fixture.window.attachedSheet)
            let content = try #require(sheet.contentView)
            try await wait { content.bounds.height > 100 }
            try await settle(content)
            #expect(content.bounds.width >= ScholiumMetrics.ResearchSheet.FileOperation.minimumWidth - 1)
            #expect(
                content.bounds.width < ScholiumMetrics.ResearchSheet.FileOperation.maximumWidth - 1,
                "A short form must not reserve the maximum width intended for long paths")
            #expect(content.bounds.height < 320)
            try capture(content, name: "\(surface.rawValue)-short", chineseDark: chineseDark)
            #expect(fixture.window.frame == parentFrame)
            state.isPresented = false
            try await wait { fixture.window.attachedSheet == nil }
        }

        state.longPath = true
        for surface in [SidebarSizingSurface.move, .folderMove] {
            state.surface = surface
            state.isPresented = true
            try await wait { fixture.window.attachedSheet?.isVisible == true }
            let content = try #require(fixture.window.attachedSheet?.contentView)
            try await wait { content.bounds.height > 100 }
            try await settle(content)
            #expect(content.bounds.width <= ScholiumMetrics.ResearchSheet.FileOperation.maximumWidth + 1)
            #expect(content.bounds.height > 100 && content.bounds.height < 650)
            if surface == .move { #expect(content.bounds.height > 220) }
            try capture(content, name: "\(surface.rawValue)-long-path", chineseDark: chineseDark)
            #expect(fixture.window.frame == parentFrame)
            state.isPresented = false
            try await wait { fixture.window.attachedSheet == nil }
        }
    }

    @Test(
        "Account Usage resizes one native sheet as quota content grows and clears", .enabled(if: ScholiumTestEnvironment.providesDisplayEvidence),
        arguments: [false, true])
    func nativeAccountUsage(chineseDark: Bool) async throws {
        let state = SidebarSizingFixtureState()
        state.surface = .account
        state.count = 0
        let fixture = makeSheetFixture(state, chineseDark: chineseDark)
        var completed = false
        defer {
            if !completed, let content = fixture.window.attachedSheet?.contentView {
                print("Account sizing failure: native bounds=\(content.bounds), fitting=\(content.fittingSize)")
            }
            fixture.close()
        }
        let parentFrame = fixture.window.frame
        state.isPresented = true
        try await wait { fixture.window.attachedSheet?.isVisible == true }
        let sheet = try #require(fixture.window.attachedSheet)
        let content = try #require(sheet.contentView)
        try await wait { content.bounds.height > 80 && content.bounds.height < 240 }
        try await settle(content)
        let shortHeight = content.bounds.height
        try capture(content, name: "account-short", chineseDark: chineseDark)

        state.isRefreshing = true
        try await wait { abs(content.bounds.height - shortHeight) > 2 }
        try await settle(content)
        #expect(content.bounds.height < 240)
        #expect(fixture.window.attachedSheet === sheet)
        try capture(content, name: "account-loading", chineseDark: chineseDark)

        state.isRefreshing = false
        state.count = 20
        try await wait { content.bounds.height > shortHeight + 80 }
        try await settle(content)
        #expect(content.bounds.height < 440, "Many quotas retain a bounded scroll viewport")
        #expect(fixture.window.attachedSheet === sheet)
        try await assertLongContentScrolls(content)
        try capture(content, name: "account-long", chineseDark: chineseDark)

        state.count = 0
        state.error = String(repeating: "Quota could not be refreshed. 保留上一次信息并稍后重试。 ", count: 20)
        try await wait { content.bounds.height > shortHeight + 80 }
        try await settle(content)
        #expect(content.bounds.height < 440)
        #expect(fixture.window.attachedSheet === sheet)
        try await assertLongContentScrolls(content)
        try capture(content, name: "account-long-error", chineseDark: chineseDark)

        state.error = nil
        try await wait { abs(content.bounds.height - shortHeight) < 2 }
        #expect(fixture.window.attachedSheet === sheet)
        #expect(fixture.window.frame == parentFrame)
        try capture(content, name: "account-short-again", chineseDark: chineseDark)
        state.isPresented = false
        try await wait { fixture.window.attachedSheet == nil }
        state.isPresented = true
        try await wait { fixture.window.attachedSheet?.isVisible == true }
        try await wait { abs((fixture.window.attachedSheet?.contentView?.bounds.height ?? 0) - shortHeight) < 2 }
        #expect(fixture.window.frame == parentFrame)
        completed = true
    }

    @Test(
        "Short sidebar lists grow to bounded viewports and shrink again", .enabled(if: ScholiumTestEnvironment.providesDisplayEvidence),
        arguments: [false, true])
    func fittedSidebarContent(chineseDark: Bool) async throws {
        _ = NSApplication.shared
        for surface in [SidebarSizingSurface.account, .outline, .diagnostics, .sources, .materials, .fileList] {
            let state = SidebarSizingFixtureState()
            state.surface = surface
            let host = NSHostingView(
                rootView: SidebarSizingFixtureContent(state: state)
                    .environment(\.locale, Locale(identifier: chineseDark ? "zh-Hans" : "en"))
                    .environment(\.colorScheme, chineseDark ? .dark : .light))
            host.appearance = NSAppearance(named: chineseDark ? .accessibilityHighContrastDarkAqua : .aqua)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = host.appearance
            window.contentView = host
            window.orderFront(nil)
            defer {
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
            try await wait { host.fittingSize.width > 0 && host.fittingSize.height > 0 }
            fit(host)
            try await settle(host)
            let shortHeight = host.fittingSize.height
            #expect(shortHeight > 10 && shortHeight < (surface == .account ? 240 : 180), "A single short row must not reserve an empty list viewport")
            let captureName = surface == .account ? "account-hosted" : surface.rawValue
            try capture(host, name: "\(captureName)-short", chineseDark: chineseDark)

            state.count = 30
            try await wait { host.fittingSize.height > shortHeight + 80 }
            fit(host)
            try await settle(host)
            #expect(host.fittingSize.height < 450)
            try await assertLongContentScrolls(host)
            if surface == .fileList {
                #expect(host.fittingSize.height <= ScholiumMetrics.ResearchSheet.FileOperation.listMaximumHeight + 1)
                #expect(abs(host.fittingSize.width - 320) < 1)
            }
            try capture(host, name: "\(captureName)-long", chineseDark: chineseDark)
            state.count = 1
            try await wait { abs(host.fittingSize.height - shortHeight) < 2 }
            fit(host)
        }
    }

    private func fit(_ host: NSView) {
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
    }

    private func assertLongContentScrolls(_ content: NSView, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await wait(sourceLocation: sourceLocation) {
            content.layoutSubtreeIfNeeded()
            return descendants(content).compactMap { $0 as? NSScrollView }.contains { scroll in
                !scroll.isHiddenOrHasHiddenAncestor && scroll.contentView.bounds.height > 0
                    && (scroll.documentView?.frame.height ?? 0) > scroll.contentView.bounds.height + 80
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func capture(_ content: NSView, name: String, chineseDark: Bool) throws {
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/sidebar-sizing-evidence")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("\(name)-\(chineseDark ? "zh-dark" : "en-light").png"))
        print("Sidebar sizing \(name) \(chineseDark ? "ZH Dark" : "EN Light"): \(content.bounds.width) × \(content.bounds.height) pt")
    }

    private func settle(_ content: NSView, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        var previous = content.bounds.size
        var stableSamples = 0
        try await wait(sourceLocation: sourceLocation) {
            content.layoutSubtreeIfNeeded()
            let current = content.bounds.size
            stableSamples = abs(current.width - previous.width) < 0.5 && abs(current.height - previous.height) < 0.5 ? stableSamples + 1 : 0
            previous = current
            return stableSamples >= 4
        }
    }

    private func wait(sourceLocation: SourceLocation = #_sourceLocation, _ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !ready(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(ready(), "The transient presentation did not reach its expected content size", sourceLocation: sourceLocation)
    }

    private func makeSheetFixture(_ state: SidebarSizingFixtureState, chineseDark: Bool) -> SidebarSizingNativeFixture {
        _ = NSApplication.shared
        let host = NSHostingView(
            rootView: SidebarSizingSheetHost(state: state)
                .environment(\.locale, Locale(identifier: chineseDark ? "zh-Hans" : "en"))
                .environment(\.colorScheme, chineseDark ? .dark : .light))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: chineseDark ? 620 : 880, height: 680),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: chineseDark ? .accessibilityHighContrastDarkAqua : .aqua)
        window.contentView = host
        window.center()
        window.orderFront(nil)
        return SidebarSizingNativeFixture(window: window, state: state)
    }
}

@MainActor
private struct SidebarSizingNativeFixture {
    let window: NSWindow
    let state: SidebarSizingFixtureState
    func close() {
        state.isPresented = false
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
            sheet.orderOut(nil)
        }
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}

private enum SidebarSizingSurface: String { case move, folder, folderMove, account, outline, diagnostics, sources, materials, fileList }

@MainActor
private final class SidebarSizingFixtureState: ObservableObject {
    @Published var surface = SidebarSizingSurface.move
    @Published var isPresented = false
    @Published var count = 1
    @Published var longPath = false
    @Published var error: String?
    @Published var isRefreshing = false
    let vaultID = UUID()
    let noteID = UUID()
}

@MainActor
private struct SidebarSizingSheetHost: View {
    @ObservedObject var state: SidebarSizingFixtureState
    var body: some View {
        Color.clear.sheet(isPresented: $state.isPresented) {
            SidebarSizingFixtureContent(state: state).buttonStyle(.automatic)
        }
    }
}

@MainActor
private struct SidebarSizingFixtureContent: View {
    @ObservedObject var state: SidebarSizingFixtureState
    private var path: String {
        state.longPath ? String(repeating: "Long research folder 研究论证与异议/", count: 5) + "Reasons and objections.md" : "Short.md"
    }
    private var messages: [AgentChatMessage] {
        (0..<state.count).map { index in
            .init(
                id: "fixture-\(index)", role: .user, text: "Question \(index) 问题",
                activity: state.surface == .diagnostics ? .init(kind: .read, status: .completed, source: .scholium, subject: "Research/问题 \(index).md") : nil)
        }
    }
    private var materialContext: AgentChatReplySourceContext {
        let attachments = (0..<state.count).map { index in
            AgentChatAttachment(
                noteID: UUID(), vaultID: state.vaultID, relativePath: "研究/Note \(index).md", text: "Exact supplied passage 原文",
                fingerprint: .init(content: "Synthetic source"))
        }
        var request = AgentChatMessage(role: .user, text: "Fixture", attachments: attachments)
        var reply = AgentChatMessage(role: .assistant, text: "Fixture reply")
        request.turnID = "fixture-turn"
        reply.turnID = "fixture-turn"
        return AgentChatReplySourceContext(reply: reply, history: [request, reply])
    }
    @ViewBuilder var body: some View {
        switch state.surface {
        case .move:
            NoteFileOperationView(
                request: .move(
                    .init(
                        documentID: .init(vaultID: state.vaultID, relativePath: path), stableNoteID: state.noteID,
                        revision: .init(content: "Synthetic source"))),
                actions: .init(
                    duplicate: { _, _ in Issue.record("Rendering must not duplicate") },
                    move: { _, _ in Issue.record("Rendering must not move") }))
        case .folder:
            FolderFileOperationView(
                request: .rename(.init(vaultID: state.vaultID, relativePath: "研究")), folderRelativePaths: [],
                actions: .init(move: { _, _ in Issue.record("Rendering must not rename") }))
        case .folderMove:
            let parent = state.longPath ? String(repeating: "Long research folder 研究论证与异议/", count: 5).dropLast().description : "Research"
            FolderFileOperationView(
                request: .move(.init(vaultID: state.vaultID, relativePath: parent + "/研究")),
                folderRelativePaths: [parent, "Other"],
                actions: .init(move: { _, _ in Issue.record("Rendering must not move") }))
        case .account:
            AgentChatAccountUsageView(
                quotas: (0..<state.count).map {
                    .init(
                        id: "quota-\($0)", name: "Research quota 研究额度 \($0)", primary: .init(usedPercent: 35, durationMinutes: 300, resetsAt: nil),
                        secondary: nil)
                }, error: state.error, isRefreshing: state.isRefreshing, canRefresh: false, refresh: {}, close: { state.isPresented = false })
        case .outline:
            AgentChatConversationOutline(messages: messages, currentMessageID: nil, navigate: { _ in })
        case .diagnostics:
            AgentChatDiagnosticsView(messages: messages, selectedID: nil, error: nil, close: {})
        case .sources:
            AgentChatSourcesView(
                sources: (0..<state.count).map { .init(url: AgentChatReference.url(noteID: UUID()), title: "Source \($0) 原文") }, close: {}, open: { _ in })
        case .materials:
            AgentChatMaterialsView(
                context: materialContext, openAttachment: { _ in },
                previewMaterial: { _ in
                    throw CancellationError()
                }, close: {})
        case .fileList:
            FileOperationList {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<state.count, id: \.self) { FileOperationPath(path: "Research/问题 \($0).md") }
                }
            }.frame(width: 320)
        }
    }
}
