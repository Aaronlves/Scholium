import AppKit
import Observation
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat reader initial hydration", .serialized)
@MainActor
struct AgentChatReadHydrationTests {
    @Observable @MainActor final class Appearance {
        var scheme: ColorScheme = .light
    }
    @Observable @MainActor final class Hydration {
        var states: [String: Bool] = [:]
        var complete: Bool { states.count == 4 && states.values.allSatisfy { $0 } }
    }
    private struct Transcript: View {
        let appearance: Appearance
        let hydration: Hydration
        let sources = [
            "请核对这段材料。",
            "## A synthetic answer\n\n" + String(repeating: "Source-faithful discussion with **中文 and English**.\n\n", count: 12),
            "另一段问题 with a retained source.",
            "**A second answer**\n\n- Source evidence stays distinct.\n- 中文合成材料。\n\n> A quoted synthetic passage.\n\n|Claim|Status|\n|---|---|\n|Synthetic|Reported|\n\nFinal exact prose.",
        ]
        var body: some View {
            ScrollView {
                VStack {
                    ForEach(sources.indices, id: \.self) { index in
                        AgentChatReadReply(source: sources[index], readerID: String(index), quote: nil, openLink: { _ in })
                    }
                }
            }
            .onPreferenceChange(AgentChatReplyHydrationPreference.self) { hydration.states = $0 }
            .opacity(hydration.complete ? 1 : 0)
            .allowsHitTesting(hydration.complete)
            .preferredColorScheme(appearance.scheme)
        }
    }

    @Test("Preferred dark appearance and an early appearance switch preserve every reply's hydration", arguments: [false, true])
    func preferredDarkHydration(switchDuringLoad: Bool) async throws {
        _ = NSApplication.shared
        for attempt in 0..<5 {
            let appearance = Appearance()
            appearance.scheme = switchDuringLoad ? .light : .dark
            let hydration = Hydration()
            let host = NSHostingView(rootView: Transcript(appearance: appearance, hydration: hydration))
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 650),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil; window.close() }
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            var didSwitch = !switchDuringLoad
            while !hydration.complete && ContinuousClock.now < deadline {
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                if !didSwitch, !readers(host).isEmpty {
                    appearance.scheme = .dark
                    didSwitch = true
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            if !hydration.complete {
                print("CHAT_HYDRATION attempt=\(attempt) incomplete=\(hydration.states) readers=\(readers(host).count)")
                for web in readers(host) {
                    let state = try? await web.evaluateJavaScript("({state:document.readyState,height:document.querySelector('#scholium-document')?.getBoundingClientRect().height})")
                    print("CHAT_HYDRATION page=\(web.accessibilityIdentifier()) state=\(String(describing: state))")
                }
            }
            #expect(didSwitch)
            #expect(hydration.complete)
            for web in readers(host) {
                let renderedScheme = try await web.evaluateJavaScript("getComputedStyle(document.documentElement).colorScheme") as? String
                #expect(renderedScheme == "dark")
            }
        }
    }

    private func readers(_ view: NSView) -> [WKWebView] {
        (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(readers)
    }
}
