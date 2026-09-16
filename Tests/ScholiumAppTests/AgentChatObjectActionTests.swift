import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat native object actions", .serialized)
@MainActor
struct AgentChatObjectActionTests {
    @Test func controlsTrackObjectsWithoutInterceptingText() async throws {
        _ = NSApplication.shared
        let source = "Prose before.\n\n```text\nfirst 中文 😀\n```\n\nBetween.\n\n| A | B |\n|---|---|\n| one | two |\n\n```text\nlast code\n```"
        let host = NSHostingView(rootView: AgentChatMarkdown(text: source))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 650),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        func reader(_ view: NSView) -> WKWebView? {
            (view as? WKWebView) ?? view.subviews.lazy.compactMap { reader($0) }.first
        }
        func elements(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { elements($0) }
        }
        var trackers: [ScholiumPointerTrackingView] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            trackers = elements(host).compactMap { $0 as? ScholiumPointerTrackingView }
            if trackers.count == 3 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(trackers.count == 3)
        let web = try #require(reader(host))
        let geometry = try #require(
            try await web.evaluateJavaScript(
                """
                [...document.querySelectorAll('.scholium-reply-object')].map(element => {
                  const r = element.getBoundingClientRect(); return {left:r.left, top:r.top, width:r.width, height:r.height};
                })
                """) as? [[String: Double]])
        #expect(geometry.count == trackers.count)
        for (tracker, rect) in zip(trackers, geometry) {
            let slot = CGRect(
                x: try #require(rect["left"]), y: try #require(rect["top"]),
                width: try #require(rect["width"]), height: try #require(rect["height"]))
            let native = tracker.convert(tracker.bounds, to: host)
            let rendered = web.convert(slot, to: host)
            #expect(
                abs(native.minY - rendered.minY) < 2 && abs(native.height - rendered.height) < 2,
                "The pointer region and controls must follow their own rendered object")
            let textPoint = CGPoint(x: slot.minX + 30, y: slot.maxY - 15)
            let hit = host.hitTest(web.convert(textPoint, to: host))
            #expect(
                hit === web || hit?.isDescendant(of: web) == true,
                "The native action layer must leave text selection with WebKit")
        }
        func identities() async throws -> [String] {
            try #require(
                try await web.evaluateJavaScript("[...document.querySelectorAll('.scholium-reply-object')].map(e => e.dataset.replyIdentity)") as? [String])
        }
        let originalIDs = try await identities()
        host.rootView = AgentChatMarkdown(text: source + "\n\nAppended prose.")
        try await waitFor("Appended prose.", in: web)
        #expect(try await identities() == originalIDs)
        host.rootView = AgentChatMarkdown(text: source.replacingOccurrences(of: "last code", with: "replacement"))
        try await waitFor("replacement", in: web)
        let replacedIDs = try await identities()
        #expect(replacedIDs.dropLast() == originalIDs.dropLast())
        #expect(
            replacedIDs.last != originalIDs.last,
            "Replacement at the same index must not inherit the former object's copy confirmation")
    }

    @Test func diagramFitsItsPreviewAcrossAppearanceAndFailureStates() async throws {
        for (source, width, height, dark, contrast) in [
            ("flowchart LR\nA[来源 Source] --> B[解释 Interpretation] --> C[核对]", 800.0, 400.0, false, false),
            ("flowchart TD\nA --> B --> C --> D --> E --> F --> G --> H", 400.0, 700.0, true, false),
            ("flowchart LR\nA --> B --> C", 320.0, 240.0, false, true),
            ("not-a-diagram", 320.0, 240.0, true, true),
        ] {
            let rendered = SafeMarkdownRenderer.render(NoteDocument(relativePath: "Reply.md", rawContent: "```mermaid\n" + source + "\n```"))
            let object = try #require(rendered.objects.first)
            let host = NSHostingView(
                rootView: AgentChatRichContent(object: object, naturalSize: .zero, openLink: { _ in })
                    .environment(\.colorScheme, dark ? .dark : .light))
            host.appearance = NSAppearance(
                named: contrast
                    ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
                    : (dark ? .darkAqua : .aqua))
            host.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: width, height: height),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer {
                window.contentView = nil
                window.close()
            }
            func reader(_ view: NSView) -> WKWebView? {
                (view as? WKWebView) ?? view.subviews.lazy.compactMap { reader($0) }.first
            }
            var metrics: [String: Any]?
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while ContinuousClock.now < deadline {
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                if let web = reader(host),
                    let measured = try? await web.evaluateJavaScript(
                        """
                        (() => {
                          const output = document.querySelector('.scholium-mermaid-output');
                          const svg = output?.shadowRoot?.querySelector('svg');
                          const fallback = document.querySelector('.scholium-mermaid-error');
                          const code = fallback?.querySelector('code');
                          if (!svg && !fallback) return null;
                          const box = svg?.getBoundingClientRect();
                          return {fallback: !!fallback, width: box?.width || 0, height: box?.height || 0,
                            codeBackground: code ? getComputedStyle(code).backgroundColor : null,
                            fits: !box || box.left >= 0 && box.top >= 0 && box.right <= innerWidth + 1 && box.bottom <= innerHeight + 1,
                            font: getComputedStyle(document.documentElement).getPropertyValue('--scholium-document-body-font-family').trim()};
                        })()
                        """) as? [String: Any]
                {
                    metrics = measured
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let measured = try #require(metrics)
            #expect(measured["fits"] as? Bool == true)
            #expect(measured["font"] as? String == "system-ui")
            #expect(measured["fallback"] as? Bool == (source == "not-a-diagram"))
            if source == "not-a-diagram" {
                #expect(measured["codeBackground"] as? String == "rgba(0, 0, 0, 0)")
            }
            if source != "not-a-diagram" {
                #expect((measured["width"] as? Double ?? 0) > width * 0.9)
                #expect((measured["height"] as? Double ?? 0) > height * 0.9)
            }
            if ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1", let web = reader(host) {
                let image = try await web.takeSnapshot(configuration: nil)
                let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                let output = repository.appendingPathComponent(".build/chat-rich-preview")
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent("diagram-\(Int(width))-\(dark ? "dark" : "light").png"))
            }
        }
    }

    private func waitFor(_ text: String, in web: WKWebView) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let found = try? await web.callAsyncJavaScript(
                "return document.body.textContent.includes(text)",
                arguments: ["text": text], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld) as? Bool,
                found
            {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CocoaError(.coderReadCorrupt)
    }
}
