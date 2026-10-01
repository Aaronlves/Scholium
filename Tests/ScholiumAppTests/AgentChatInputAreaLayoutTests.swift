import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat input-area viewport allocation", .serialized)
@MainActor
struct AgentChatInputAreaLayoutTests {
    @Test("A short viewport retains a reading passage and scrolls prepared input within the remaining area")
    func shortViewportAllocation() throws {
        let height: CGFloat = 420
        let limits = AgentChatInputAreaLimits.fitting(
            viewportHeight: height, hasQueue: true, hasPreparedContent: true,
            hasFooterStatus: true, lineHeight: 20)
        let maximum = try #require(limits.maximumHeight)
        let reading = try #require(limits.reservedTranscriptHeight)
        let queue = try #require(limits.queueMaximumHeight)
        let preparation = try #require(limits.preparationMaximumHeight)
        let editor = try #require(limits.editorMaximumHeight)
        #expect(reading >= 6 * 20)
        #expect(maximum + reading == height)
        #expect(queue >= ScholiumGrid.Dimension.preferredCustomTarget && queue < 144)
        #expect(preparation >= ScholiumGrid.Dimension.preferredCustomTarget)
        #expect(editor >= 40 && editor < 7 * 20 + 12)
        // The remaining height includes input/queue control rows and all of
        // their existing outer padding; none is removed to meet the budget.
        #expect(queue + preparation + editor < maximum)
    }

    @Test("An ordinary tall viewport keeps existing request and queue limits rather than expanding those surfaces")
    func tallViewportPreservesLocalCaps() throws {
        let limits = AgentChatInputAreaLimits.fitting(
            viewportHeight: 1_400, hasQueue: true, hasPreparedContent: false,
            hasFooterStatus: false, lineHeight: 20)
        #expect(limits.queueMaximumHeight == 144)
        #expect(limits.requestMaximumHeight == 240)
        let editorMaximum = try #require(limits.editorMaximumHeight)
        let sevenLineMaximum: CGFloat = 7 * 20 + 12
        #expect(editorMaximum == sevenLineMaximum)
        #expect(limits.preparationMaximumHeight == nil)
        let unmounted = AgentChatInputAreaLimits.fitting(
            viewportHeight: nil, hasQueue: true, hasPreparedContent: true,
            hasFooterStatus: false, lineHeight: 20)
        #expect(unmounted == .unconstrained)
    }

    private struct ControlProbe: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.identifier = .init("request-control")
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }

    @Test("A request-body budget preserves its separate native decision controls")
    func requestBodyScrollsAboveControls() throws {
        _ = NSApplication.shared
        let host = NSHostingView(
            rootView: VStack(spacing: 12) {
                AgentChatContentScroll {
                    Text(String(repeating: "Exact permission scope 保留完整权限说明。\n", count: 30))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Allow Once") {}
                    .frame(minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
                    .background(ControlProbe())
            }
            .environment(\.agentChatContentMaximumHeight, 80)
            .frame(width: 300))
        // Keep the tested native viewport stable. Preferred-content sizing can
        // shrink its host after layout, leaving probes in the previous frame.
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 180)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let control = try #require(descendants(host).first { $0.identifier?.rawValue == "request-control" })
        #expect(control.bounds.height >= ScholiumGrid.Dimension.preferredCustomTarget)
        #expect(host.fittingSize.height <= 80 + 12 + ScholiumGrid.Dimension.preferredCustomTarget + 1)
        let frame = control.convert(control.bounds, to: host)
        #expect(host.bounds.contains(frame))
    }
}
