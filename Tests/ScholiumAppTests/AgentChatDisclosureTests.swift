import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat activity disclosure", .serialized)
@MainActor
struct AgentChatDisclosureTests {
    private final class Model: ObservableObject {
        @Published var expanded = true
        var renderedExpanded: Bool?
    }

    private struct RenderedStateProbe: NSViewRepresentable {
        let expanded: Bool
        let record: (Bool) -> Void
        func makeNSView(context: Context) -> NSView { NSView() }
        func updateNSView(_ view: NSView, context: Context) { record(expanded) }
    }

    private struct Fixture: View {
        @ObservedObject var model: Model
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup("Activity fixture", isExpanded: $model.expanded) {
                    AgentChatMarkdown(text: "Retained process commentary.")
                }
                .disclosureGroupStyle(AgentChatDisclosureStyle())
                AgentChatMarkdown(text: "The following answer stays selected.")
                RenderedStateProbe(expanded: model.expanded, record: { model.renderedExpanded = $0 }).frame(height: 1)
                Spacer()
            }.padding(24)
        }
    }

    @Test("Restored child details reopen a completed process unless its parent was explicitly collapsed")
    func restoresInspectedProcess() async throws {
        let message = AgentChatMessage(id: "retained-operation", role: .operation, text: "Read selected material")
        for savedExpansion in [Optional<Bool>.none, false, true] {
            var contentMounted = false
            var parentMounted = false
            let host = NSHostingView(
                rootView: AgentChatProcessView(
                    messages: [message], isActive: false, forceExpanded: false,
                    status: .init(state: .completed), preservesReading: true,
                    hasInspectedActivity: true, animates: false,
                    userExpansion: .constant(savedExpansion)
                ) { _ in
                    RenderedStateProbe(expanded: true, record: { contentMounted = $0 })
                        .frame(height: 60)
                }
                .background(RenderedStateProbe(expanded: true, record: { parentMounted = $0 })))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer {
                window.contentView = nil
                window.close()
            }

            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            repeat {
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                await Task.yield()
            } while (!parentMounted || (savedExpansion != false && !contentMounted)) && ContinuousClock.now < deadline
            try #require(parentMounted)
            #expect(contentMounted == (savedExpansion != false))
        }
    }

    @Test("Disclosure retains its measured reader and the following reply selection", arguments: [false, true])
    func retainedReadersAndSelection(adapted: Bool) async throws {
        let model = Model()
        let host = NSHostingView(
            rootView: Fixture(model: model)
                .environment(\.colorScheme, adapted ? .light : .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: adapted ? 260 : 340, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: adapted ? .accessibilityHighContrastAqua : .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }

        func readers(_ view: NSView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(readers)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var ready = false
        while ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            let views = readers(host)
            if views.count == 2 {
                ready = true
                for web in views {
                    let value =
                        try? await web.callAsyncJavaScript(
                            "await window.scholiumReadReady; return !!window.scholiumUpdateReply", arguments: [:], in: nil,
                            contentWorld: SafeMarkdownReadWebView.bridgeContentWorld) as? Bool
                    if value != true { ready = false }
                }
                if ready { break }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(ready)
        let initialReaders = readers(host)
        for web in initialReaders {
            _ = try await web.evaluateJavaScript(
                "window.retainedDocument = document; window.getSelection().selectAllChildren(document.getElementById('scholium-document')); window.retainedText = window.getSelection().toString();"
            )
            try #require(try await web.evaluateJavaScript("window.retainedText.length > 0") as? Bool == true)
        }
        for expected in [false, true, false, true] {
            model.expanded = expected
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while model.renderedExpanded != expected && ContinuousClock.now < deadline {
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.renderedExpanded == expected)
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            // Allow the layout transaction to be delivered, without waiting for
            // an animation duration or accepting a recreated page as equivalent.
            await Task.yield()
            let current = readers(host)
            try #require(current.count == 2)
            #expect(zip(current, initialReaders).allSatisfy { $0 === $1 })
            for web in current {
                #expect(try await web.evaluateJavaScript("document === window.retainedDocument") as? Bool == true)
            }
            let following = try #require(current.last)
            #expect(try await following.evaluateJavaScript("window.getSelection().toString() === window.retainedText") as? Bool == true)
        }
    }
}
