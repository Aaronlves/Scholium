import AppKit
import Observation
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Document notice layout", .serialized)
@MainActor
struct DocumentNoticeLayoutTests {
    @Test("Notice arrival, growth, and dismissal preserve the retained Document viewport")
    func noticeLifecycleKeepsViewportStable() async throws {
        _ = NSApplication.shared
        let state = NoticeFixtureState()
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let host = NSHostingView(rootView: NoticeFixture(state: state, document: document))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }

        for size in [NSSize(width: 600, height: 400), NSSize(width: 320, height: 240)] {
            window.setContentSize(size)
            for count in [0, 1, 12, 1, 0] {
                state.count = count
                host.layoutSubtreeIfNeeded()
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                #expect(document.superview != nil)
                #expect(document.frame.size == size)
                #expect(document.convert(document.bounds, to: host).origin == .zero)
            }
        }
    }
}

@Observable
@MainActor
private final class NoticeFixtureState {
    var count = 0
}

private struct NoticeFixture: View {
    let state: NoticeFixtureState
    let document: NSView

    var body: some View {
        RetainedDocumentView(document: document)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        if state.count > 0 {
                            ScholiumDocumentNoticeStack(availableSize: geometry.size) {
                                ForEach(0..<state.count, id: \.self) { index in
                                    Text("Synthetic notice \(index)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
    }
}

private struct RetainedDocumentView: NSViewRepresentable {
    let document: NSView

    func makeNSView(context: Context) -> NSView { document }
    func updateNSView(_ view: NSView, context: Context) {}
}
