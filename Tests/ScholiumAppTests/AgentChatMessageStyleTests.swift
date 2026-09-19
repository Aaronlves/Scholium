import AppKit
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat message style", .serialized)
struct AgentChatMessageStyleTests {
    @Test("Streaming retains the page, selected Unicode passage and rich object identity")
    @MainActor
    func streamingSelectionSurvives() async throws {
        var interactions = 0
        func content(_ source: String) -> some View {
            AgentChatMarkdown(text: source)
                .environment(\.chatReadingInteraction, { interactions += 1 })
        }
        let original = "保留 😀 e\u{301} same same。\n\n```text\nretained code\n```\n\n继续回答"
        let host = NSHostingView(rootView: content("Starting"))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 650), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func reader(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { reader($0) }.first
        }
        func waitFor(_ text: String) async throws -> WKWebView {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while ContinuousClock.now < deadline {
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                if let web = reader(host),
                    let found = try? await web.callAsyncJavaScript(
                        "await window.scholiumReadReady; return !!window.scholiumUpdateReply && document.getElementById('scholium-document').textContent.includes(text)",
                        arguments: ["text": text], in: nil,
                        contentWorld: SafeMarkdownReadWebView.bridgeContentWorld) as? Bool,
                    found
                {
                    return web
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw CocoaError(.coderReadCorrupt)
        }
        let startupDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while reader(host) == nil {
            try #require(ContinuousClock.now < startupDeadline)
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(1))
        }
        // Deliver the first source changes as soon as the WKWebView exists,
        // before waiting for its initial navigation/runtime handshake.
        host.rootView = content("Intermediate")
        await Task.yield()
        host.rootView = content(original)
        let web = try await waitFor("继续回答")
        _ = try await web.callAsyncJavaScript(
            """
            window.retainedPage = document;
            window.retainedParagraph = document.querySelector('#scholium-document p');
            window.retainedCode = document.querySelector('.scholium-reply-object');
            const node = window.retainedParagraph.firstChild;
            window.getSelection().setBaseAndExtent(node, node.length, node, 3);
            window.retainedSelection = window.getSelection().toString();
            """, arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
        let updated =
            original + "，新增文字。\n\n| A | B |\n|---|---|\n| 中文 | test |\n\n$e^{i\\pi}+1=0$\n\n结束"
        host.rootView = content(updated)
        let current = try await waitFor("结束")
        #expect(current === web)
        let preserved =
            try await web.callAsyncJavaScript(
                """
                await window.scholiumMermaidReady;
                return document === window.retainedPage
                  && document.querySelector('#scholium-document p') === window.retainedParagraph
                  && document.querySelector('.scholium-reply-object') === window.retainedCode
                  && window.getSelection().toString() === window.retainedSelection
                  && document.querySelectorAll('.scholium-reply-controls').length === 2
                  && document.querySelectorAll('.scholium-reply-controls button').length === 0
                  && !!document.querySelector('.scholium-reply-object').dataset.replyIdentity
                  && !!document.querySelector('.scholium-math-rendered');
                """, arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
            as? Bool
        #expect(preserved == true)
        _ = try await web.callAsyncJavaScript(
            "const node = document.querySelector('#scholium-document p:last-child').firstChild; window.getSelection().setBaseAndExtent(node, 2, node, 0);",
            arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
        for suffix in [" **追加", " **追加**，完成"] {
            host.rootView = content(updated + suffix)
            _ = try await waitFor(suffix.contains("完成") ? "完成" : "追加")
            let selection =
                try await web.callAsyncJavaScript(
                    "return window.getSelection().toString()", arguments: [:], in: nil,
                    contentWorld: SafeMarkdownReadWebView.bridgeContentWorld) as? String
            #expect(selection == "结束")
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while interactions == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(interactions > 0)
        let rejected =
            try await web.callAsyncJavaScript(
                "return await window.scholiumUpdateReply({version:7, documentID:'chat-reply', loadGeneration:0, previousFingerprint:'stale', fingerprint:'bad', html:'<p>wrong</p>', presentationCSS:'', userCSS:''}) === false",
                arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld) as? Bool
        #expect(rejected == true)
    }

    private struct FollowingActivity: NSViewRepresentable {
        func makeNSView(context: Context) -> NSTextField { NSTextField(labelWithString: "Used tool 2") }
        func updateNSView(_ view: NSTextField, context: Context) {}
    }
    // Needs the bundled typefaces, so measured row heights are real.
    @Test("One reader keeps streamed prose and rich content inside its allocated row", .enabled(if: ScholiumTestEnvironment.providesDisplayEvidence))
    @MainActor
    func unifiedReplyLayout() async throws {
        var contentReady = false
        func content(_ source: String, scheme: ColorScheme = .light) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AgentChatMarkdown(text: source)
                        .modifier(AgentChatMessageArrival(enabled: true))
                        .onPreferenceChange(AgentChatReplyReadyPreference.self) { contentReady = $0 }
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
                        abs(reader.frame.height - height) <= 1, contentReady
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
                #expect(
                    !reader.convert(reader.bounds, to: host).intersects(
                        activity.convert(activity.bounds, to: host)))
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
                                "reply-\(scheme == .light ? "light" : "dark")-\(Int(width))-\(source.contains("示例") ? "table" : "prose").png"
                            ))
                }
            }
        }
    }

    @Test(
        "User paragraphs fit their rendered text and reflow; both speakers keep the same compact Markdown rhythm"
    )
    @MainActor
    func speakerTypography() async throws {
        func content(_ source: String, user: Bool) -> some View {
            ScrollView {
                AgentChatMessageSurface(isUser: user) {
                    AgentChatMarkdown(text: source, expandsToFillWidth: !user)
                }.padding(.horizontal, ScholiumSidebarLayout.textInset)
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
        let rich =
            "## 阅读方向\n\n这是一段用于检查完整讨论排版的合成回答。我们可以沿着一个问题继续追问，让解释有足够的篇幅展开，也让每段文字各自表达一个清楚的意思。\n\n- 核对 **原文**。\n- 比较 `works` 与 `topics`。\n  - 保留出处。\n\n> 这是一段引用。\n>\n> > 引用中的引文也应保持清晰。\n\n```text\n中文与 English code\n```\n\n最后区分解释与评价。"
        var narrowHeight = 0.0
        for (source, user, width, contrast) in [
            ("好的。", true, 300.0, ColorSchemeContrast.standard),
            (long, true, 240.0, .standard), (long, true, 480.0, .increased),
            (rich, false, 300.0, .standard), (rich, false, 420.0, .increased),
            (rich, true, 300.0, .increased),
        ] {
            host.rootView = content(source, user: user)
            window.appearance = NSAppearance(
                named: contrast == .increased ? .accessibilityHighContrastAqua : .aqua)
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
                          const range = document.createRange(); if (p) range.selectNodeContents(p);
                          return {text: root.innerText, height: Math.ceil(root.getBoundingClientRect().height),
                            viewportWidth: innerWidth, paragraphWidth: p?.getBoundingClientRect().width,
                            firstLineWidth: range.getClientRects()[0]?.width,
                            paragraphPadding: p ? getComputedStyle(p).paddingBottom : null,
                            headingPadding: h ? getComputedStyle(h).paddingTop : null,
                            headingFont: h ? parseFloat(getComputedStyle(h).fontSize) : 0,
                            bodyFont: parseFloat(getComputedStyle(root).fontSize),
                            bodyColor: getComputedStyle(root).color,
                            quoteColors: [...root.querySelectorAll('blockquote')].map(q => getComputedStyle(q).color),
                            codeFont: root.querySelector('pre code') ? parseFloat(getComputedStyle(root.querySelector('pre code')).fontSize) : null,
                            codeLineHeight: root.querySelector('pre code') ? getComputedStyle(root.querySelector('pre code')).lineHeight : null,
                            blockLineHeight: root.querySelector('pre') ? getComputedStyle(root.querySelector('pre')).lineHeight : null,
                            overflow: root.scrollWidth > window.innerWidth + 1};
                        })()
                        """) as? [String: Any], let height = value["height"] as? Double,
                    abs(reader.frame.height - height) <= 1,
                    (value["text"] as? String)?.contains(
                        source == "好的。" ? "好的。" : source == long ? "原始含义" : "阅读方向") == true,
                    source != "好的。" || reader.frame.width < 60,
                    source != long || width != 480 || (height < narrowHeight && reader.frame.width > 300)
                {
                    result = value
                    if source == "好的。" { #expect(reader.frame.width > 20 && reader.frame.width < 60) }
                    if source == long && width == 240 { narrowHeight = height }
                    if source == long && width == 480 {
                        #expect(height < narrowHeight && reader.frame.width > 300)
                    }
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let actual = try #require(result)
            #expect(actual["paragraphPadding"] as? String == "0px")
            #expect(actual["overflow"] as? Bool == false)
            if source == rich {
                let colors = try #require(actual["quoteColors"] as? [String])
                #expect(colors.count == 2)
                #expect(colors.allSatisfy { $0 == actual["bodyColor"] as? String })
                #expect(actual["codeFont"] as? Double == actual["bodyFont"] as? Double)
                #expect(actual["codeLineHeight"] as? String == actual["blockLineHeight"] as? String)
                if !user {
                    let expected = width - 2 * ScholiumSidebarLayout.textInset
                    let viewport = try #require(actual["viewportWidth"] as? Double)
                    let paragraph = try #require(actual["paragraphWidth"] as? Double)
                    let firstLine = try #require(actual["firstLineWidth"] as? Double)
                    let font = try #require(actual["bodyFont"] as? Double)
                    #expect(abs(viewport - expected) <= 1)
                    #expect(abs(paragraph - viewport) <= 1)
                    #expect(firstLine >= paragraph - 2 * font)
                }
                #expect(actual["headingPadding"] as? String == "0px")
                let heading = try #require(actual["headingFont"] as? Double)
                let body = try #require(actual["bodyFont"] as? Double)
                #expect(heading > body && heading < body * 1.3)
            }
        }
    }

    @Test("Code previews retain native monospace and shared semantic ink")
    @MainActor
    func sharedBodyStyle() {
        let rendered = AgentChatRichContent.codeText("let value = 1\n")
        let bodyFont = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let bodyColor = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let actualColor = bodyColor?.usingColorSpace(.sRGB)
        let expectedColor = ScholiumChatAppearance.messageNSForeground.usingColorSpace(.sRGB)

        #expect(bodyFont == .monospacedSystemFont(ofSize: ScholiumChatAppearance.messageNSFont.pointSize, weight: .regular))
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
            #expect(css.contains("--scholium-corner-document-control:"))
            #expect(css.contains("--scholium-content-hover-surface:"))
            #expect(css.contains("--scholium-content-keyboard-focus-surface:"))
            #expect(css.contains("--scholium-document-accent:"))
            for (role, key) in [(ScholiumColorRole.primaryText, "primary-text"), (.accent, "accent")] {
                let declaration = String(
                    format: "--scholium-color-%@: #%06x;", key,
                    role.resolvedRGBValue(isDark: dark, increasedContrast: increasedContrast))
                #expect(css.contains(declaration))
            }
        }
    }
}
