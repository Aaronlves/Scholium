import AppKit
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat message style", .serialized)
struct AgentChatMessageStyleTests {
    private struct FollowingActivity: NSViewRepresentable {
        func makeNSView(context: Context) -> NSTextField { NSTextField(labelWithString: "Used tool 2") }
        func updateNSView(_ view: NSTextField, context: Context) {}
    }
    @Test("One reader keeps streamed prose and rich content inside its allocated row")
    @MainActor
    func unifiedReplyLayout() async throws {
        func content(_ source: String, scheme: ColorScheme = .light) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AgentChatMarkdown(text: source)
                    FollowingActivity().frame(height: 20)
                }.padding(12)
            }.background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme)
        }
        let host = NSHostingView(rootView: content("你好！"))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func readers(_ view: NSView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap { readers($0) }
        }
        func activities(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { activities($0) }
        }
        let prose = "你好！我先确认一下当前会话里实际启用的 Scholium 能力，然后用中文给你一个准确的概览。\n\n`works` 跟 `topics` 有什么区别？"
        for scheme in [ColorScheme.light, .dark] {
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            var retainedReader: WKWebView?
            var previousHeight: CGFloat = 0
            var codeStyle: [String]?
            for (source, width) in [
                ("你好！", 280.0), (prose, 200.0),
                (prose + "\n\n| 名称 | 内容 |\n|---|---|\n| `works` | 示例 |", 200.0),
                (prose, 380.0),
            ] {
                host.rootView = content(source, scheme: scheme)
                window.setContentSize(NSSize(width: width, height: 600))
                let deadline = ContinuousClock.now.advanced(by: .seconds(10))
                var metrics: [String: Any]?
                while ContinuousClock.now < deadline {
                    window.layoutIfNeeded()
                    host.layoutSubtreeIfNeeded()
                    if let reader = readers(host).first,
                        let value = try? await reader.evaluateJavaScript(
                            """
                            (() => {
                              const root = document.getElementById('scholium-document');
                              if (!root) return null;
                              const code = root.querySelector('code');
                              const style = code ? getComputedStyle(code) : null;
                              return {text: root.innerText, height: Math.ceil(root.getBoundingClientRect().height),
                                code: style ? [style.fontFamily, style.fontSize, style.backgroundColor, style.padding, style.borderRadius] : []};
                            })()
                            """) as? [String: Any],
                        let height = value["height"] as? Double, height > 0,
                        (value["text"] as? String)?.contains(source == "你好！" ? "你好！" : "准确的概览") == true,
                        (value["text"] as? String)?.contains("示例") == source.contains("示例"),
                        abs(reader.frame.height - height) <= 1
                    {
                        if let retainedReader { #expect(reader === retainedReader) }
                        retainedReader = reader
                        metrics = value
                        if source == prose && width == 200 { #expect(height > previousHeight) }
                        previousHeight = height
                        break
                    }
                    try await Task.sleep(for: .milliseconds(20))
                }
                let actual = try #require(metrics, "Reply did not report its current wrapped height")
                #expect(readers(host).count == 1)
                let reader = try #require(retainedReader)
                let activity = try #require(activities(host).first)
                #expect(!reader.convert(reader.bounds, to: host).intersects(activity.convert(activity.bounds, to: host)))
                if let style = actual["code"] as? [String], !style.isEmpty {
                    if let codeStyle { #expect(style == codeStyle) }
                    codeStyle = style
                }
                if ProcessInfo.processInfo.environment["SCHOLIUM_RENDER_CHAT"] == "1" {
                    // Geometry arrives before WebKit's remote layer has committed its pixels.
                    try await Task.sleep(for: .milliseconds(100))
                    window.displayIfNeeded()
                    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                        .deletingLastPathComponent().deletingLastPathComponent()
                    let output = repository.appendingPathComponent(".build/chat-layout-fix")
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try #require(bitmap.representation(using: .png, properties: [:]))
                        .write(
                            to: output.appendingPathComponent(
                                "reply-\(scheme == .light ? "light" : "dark")-\(Int(width))-\(source.contains("示例") ? "table" : "prose").png"))
                }
            }
        }
    }

    @Test("User paragraphs fit their rendered text and reflow; both speakers keep the same compact Markdown rhythm")
    @MainActor
    func speakerTypography() async throws {
        func content(_ source: String, user: Bool) -> some View {
            ScrollView {
                AgentChatMessageSurface(isUser: user) {
                    AgentChatMarkdown(text: source, expandsToFillWidth: !user)
                }.padding(24)
            }
        }
        let host = NSHostingView(rootView: content("好的。", user: true))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func readers(_ view: NSView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap { readers($0) }
        }
        let long = "请比较 `works` 和 **topics**，保留中文、English 与引用的原始含义，不把解释混同于文献证据。"
        let rich = "## 阅读方向\n\n先澄清问题。\n\n- 核对 **原文**。\n- 比较 `works` 与 `topics`。\n  - 保留出处。\n\n> 这是一段引用。\n\n最后区分解释与评价。"
        var narrowHeight = 0.0
        for (source, user, width, contrast) in [
            ("好的。", true, 300.0, ColorSchemeContrast.standard),
            (long, true, 240.0, .standard), (long, true, 480.0, .increased),
            (rich, false, 300.0, .standard), (rich, true, 300.0, .increased),
        ] {
            host.rootView = content(source, user: user)
            window.appearance = NSAppearance(named: contrast == .increased ? .accessibilityHighContrastAqua : .aqua)
            window.setContentSize(NSSize(width: width, height: 700))
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            var result: [String: Any]?
            while ContinuousClock.now < deadline {
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                if let reader = readers(host).first,
                    let value = try? await reader.evaluateJavaScript(
                        """
                        (() => {
                          const root = document.getElementById('scholium-document');
                          if (!root) return null;
                          const p = root.querySelector('p'), h = root.querySelector('h2');
                          return {text: root.innerText, height: Math.ceil(root.getBoundingClientRect().height),
                            paragraphPadding: p ? getComputedStyle(p).paddingBottom : null,
                            headingPadding: h ? getComputedStyle(h).paddingTop : null,
                            headingFont: h ? parseFloat(getComputedStyle(h).fontSize) : 0,
                            bodyFont: parseFloat(getComputedStyle(root).fontSize),
                            overflow: root.scrollWidth > window.innerWidth + 1};
                        })()
                        """) as? [String: Any], let height = value["height"] as? Double,
                    abs(reader.frame.height - height) <= 1,
                    (value["text"] as? String)?.contains(source == "好的。" ? "好的。" : source == long ? "原始含义" : "阅读方向") == true,
                    source != "好的。" || reader.frame.width < 60
                {
                    result = value
                    if source == "好的。" { #expect(reader.frame.width > 20 && reader.frame.width < 60) }
                    if source == long && width == 240 { narrowHeight = height }
                    if source == long && width == 480 { #expect(height < narrowHeight && reader.frame.width > 300) }
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let actual = try #require(result)
            #expect(actual["paragraphPadding"] as? String == "0px")
            #expect(actual["overflow"] as? Bool == false)
            if source == rich {
                #expect(actual["headingPadding"] as? String == "0px")
                let heading = try #require(actual["headingFont"] as? Double)
                let body = try #require(actual["bodyFont"] as? Double)
                #expect(heading > body && heading < body * 1.3)
            }
        }
    }

    @Test("Native object previews retain the shared body font and semantic ink")
    @MainActor
    func sharedBodyStyle() {
        let rendered = AgentChatObjectProjection.layoutReply("同一段正文。\n\n第二段。").text
        let bodyFont = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let bodyColor = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let actualColor = bodyColor?.usingColorSpace(.sRGB)
        let expectedColor = ScholiumChatAppearance.messageNSForeground.usingColorSpace(.sRGB)

        #expect(bodyFont == ScholiumChatAppearance.messageNSFont)
        #expect(actualColor != nil && expectedColor != nil)
        #expect(abs((actualColor?.redComponent ?? 0) - (expectedColor?.redComponent ?? 0)) < 0.001)
        #expect(abs((actualColor?.greenComponent ?? 0) - (expectedColor?.greenComponent ?? 0)) < 0.001)
        #expect(abs((actualColor?.blueComponent ?? 0) - (expectedColor?.blueComponent ?? 0)) < 0.001)
        #expect(ScholiumChatAppearance.messageFont == .body)
    }

    @Test("Rich message surfaces use the same semantic ink in both appearances")
    @MainActor
    func sharedRichStyle() {
        for (dark, increasedContrast) in [(false, false), (true, false), (false, true), (true, true)] {
            let css = AgentChatDiagram.presentationCSS(dark: dark, increasedContrast: increasedContrast)
            for (role, key) in [(ScholiumColorRole.primaryText, "primary-text"), (.accent, "accent")] {
                if role == .accent {
                    #expect(
                        css.contains(
                            "--scholium-color-\(key): \(ScholiumWebDesignTokens.systemAccentCSSValue);"
                        )
                    )
                    continue
                }
                let declaration = String(
                    format: "--scholium-color-%@: #%06x;", key,
                    role.resolvedRGBValue(isDark: dark, increasedContrast: increasedContrast))
                #expect(css.contains(declaration))
            }
        }
    }
}
