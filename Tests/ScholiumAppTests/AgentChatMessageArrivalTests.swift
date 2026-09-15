import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat message arrival visibility", .serialized)
@MainActor
struct AgentChatMessageArrivalTests {
    private struct RenderGenerationProbe: NSViewRepresentable {
        let generation: Int
        let record: (Int) -> Void
        func makeNSView(context: Context) -> NSView { NSView() }
        func updateNSView(_ view: NSView, context: Context) { record(generation) }
    }

    @Test("Allowing motion never hides a message already shown while its reader is loading")
    func retainsVisibleLoadingMessage() async throws {
        _ = NSApplication.shared
        var renderedGeneration = -1
        func content(generation: Int) -> some View {
            Color.black
                .frame(width: 80, height: 80)
                .preference(key: AgentChatReplyReadyPreference.self, value: false)
                .modifier(AgentChatMessageArrival(enabled: generation > 0))
                .background(Color.white)
                .background(RenderGenerationProbe(generation: generation, record: { renderedGeneration = $0 }))
                .environment(\.controlActiveState, .active)
                .transaction {
                    // Assert settled visibility, independently of animation clocks.
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
        }
        let host = NSHostingView(rootView: content(generation: 0))
        host.frame = NSRect(x: 0, y: 0, width: 80, height: 80)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }

        for generation in 0...1 {
            if generation > 0 { host.rootView = content(generation: generation) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            repeat {
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                await Task.yield()
            } while renderedGeneration != generation && ContinuousClock.now < deadline
            try #require(renderedGeneration == generation)
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            // The white backing would show through if the modifier hid the body.
            #expect(center.redComponent < 0.2 && center.greenComponent < 0.2 && center.blueComponent < 0.2)
            #expect(center.alphaComponent > 0.9)
        }
    }
}
