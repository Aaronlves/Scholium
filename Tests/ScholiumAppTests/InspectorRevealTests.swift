import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

/// Native-container diagnosis with synthetic text. It measures the controller's
/// geometry lifecycle, not rendered frame time or whole-App performance.
@Suite("Inspector reveal", .serialized)
@MainActor
struct InspectorRevealTests {
    @Test("First reveal completes its geometry in one native transaction", arguments: [false, true])
    func firstRevealHasNoDeferredWidthChange(animated: Bool) async throws {
        try await withWindow { controller, window in
            let originalFrame = window.frame
            let document = controller.splitViewItems[1].viewController.view
            controller.setResearchInspectorVisible(true, animated: animated)
            window.layoutIfNeeded()
            let inspector = controller.splitViewItems[2].viewController.view
            let committedWidth = inspector.frame.width
            #expect(committedWidth >= ScholiumMetrics.Apparatus.firstRevealWidth - controller.splitView.dividerThickness)
            try await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
            #expect(abs(inspector.frame.width - committedWidth) < 1)
            #expect(window.frame == originalFrame)
            #expect(document === controller.splitViewItems[1].viewController.view)
            #expect(inspector === controller.splitViewItems[2].viewController.view)
        }
    }

    @Test("Completed first reveal preserves subsequent native divider choices")
    func firstRevealPreservesResearcherResize() async throws {
        try await withWindow { controller, window in
            controller.setResearchInspectorVisible(true, animated: true)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
            try #require(controller.splitView.arrangedSubviews.count == 3)
            let inspector = controller.splitViewItems[2].viewController.view
            let nativeInspector = try nativeInspectorView(controller)
            controller.splitView.setPosition(
                controller.splitView.bounds.maxX - 285,
                ofDividerAt: controller.splitView.arrangedSubviews.count - 2)
            window.layoutIfNeeded()
            let chosenWidth = nativeInspector.frame.width
            #expect(chosenWidth >= ScholiumMetrics.Apparatus.minimumReadableWidth)
            #expect(chosenWidth < ScholiumMetrics.Apparatus.firstRevealWidth - 1)
            try await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
            #expect(abs(nativeInspector.frame.width - chosenWidth) < 1)
            #expect(abs(inspector.frame.width - nativeInspector.frame.width) < 1)
            controller.setResearchInspectorVisible(false, animated: false)
            controller.setResearchInspectorVisible(true, animated: false)
            window.layoutIfNeeded()
            #expect(abs(nativeInspector.frame.width - chosenWidth) < 1)
        }
    }

    @Test("Narrow first reveal keeps native minimum and cannot replay its width suggestion")
    func narrowFirstRevealDoesNotReassertWidth() async throws {
        try await withWindow(width: 600) { controller, window in
            controller.setResearchInspectorVisible(true, animated: true)
            try await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
            let nativeInspector = try nativeInspectorView(controller)
            let initialWidth = nativeInspector.frame.width
            #expect(abs(initialWidth - ScholiumMetrics.Apparatus.minimumReadableWidth) < 1)
            window.setContentSize(.init(width: 1_180, height: 760))
            window.layoutIfNeeded()
            controller.setResearchInspectorVisible(false, animated: false)
            controller.setResearchInspectorVisible(true, animated: false)
            window.layoutIfNeeded()
            #expect(abs(nativeInspector.frame.width - initialWidth) < 1)
        }
    }

    @Test(
        "First and warm native reveal geometry",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_INSPECTOR_MEASURE"] == "1")
    )
    func measureRevealGeometry() async throws {
        let controller = makeController()
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentMinSize = .init(width: 1_180, height: 760)
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            window.contentViewController = nil
            window.close()
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        for cycle in 0..<4 {
            let inspector = controller.splitViewItems[2].viewController.view
            let document = controller.splitViewItems[1].viewController.view
            let originalFrame = window.frame
            let start = ContinuousClock.now
            controller.setResearchInspectorVisible(true, animated: true)
            let callDuration = start.duration(to: .now)
            var widths: [CGFloat] = [nativeInspectorWidth(controller)]
            var times: [Double] = [milliseconds(start.duration(to: .now))]
            for _ in 0..<30 {
                try await Task.sleep(for: .milliseconds(20))
                window.layoutIfNeeded()
                times.append(milliseconds(start.duration(to: .now)))
                widths.append(nativeInspectorWidth(controller))
            }
            let changes = zip(widths, widths.dropFirst()).enumerated().compactMap { index, pair in
                abs(pair.1 - pair.0) > 0.5
                    ? "\(String(format: "%.1f", times[index + 1])):\(String(format: "%.1f", pair.0))->\(String(format: "%.1f", pair.1))" : nil
            }
            print(
                "INSPECTOR_MEASURE cycle=\(cycle) cold=\(cycle == 0) call_ms=\(String(format: "%.4f", milliseconds(callDuration))) final_width_pt=\(String(format: "%.1f", widths.last!)) geometry_changes_ms_pt=\(changes.joined(separator: ",")) samples=\(widths.count)"
            )
            #expect(window.frame == originalFrame)
            #expect(inspector === controller.splitViewItems[2].viewController.view)
            #expect(document === controller.splitViewItems[1].viewController.view)
            #expect(controller.researchInspectorIsVisible)
            #expect(inspector.frame.width >= ScholiumMetrics.Apparatus.minimumReadableWidth)
            #expect(abs(controller.splitView.convert(inspector.bounds, from: inspector).maxX - controller.splitView.bounds.maxX) < 1)
            controller.setResearchInspectorVisible(false, animated: false)
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private func withWindow(
        width: CGFloat = 1_180,
        _ body: @MainActor (ScholiumWorkspaceSplitView<Text, Text, Text, Text>.Controller, NSWindow) async throws -> Void
    ) async throws {
        let controller = makeController()
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: width, height: 760),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentMinSize = .init(width: width, height: 760)
        window.contentViewController = controller
        window.orderFront(nil)
        defer {
            window.contentViewController = nil
            window.close()
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try await body(controller, window)
    }

    private func nativeInspectorWidth(_ controller: ScholiumWorkspaceSplitView<Text, Text, Text, Text>.Controller) -> CGFloat {
        let content = controller.splitViewItems[2].viewController.view
        return controller.splitView.arrangedSubviews.first { content.isDescendant(of: $0) }?.frame.width ?? 0
    }

    private func nativeInspectorView(_ controller: ScholiumWorkspaceSplitView<Text, Text, Text, Text>.Controller) throws -> NSView {
        let content = controller.splitViewItems[2].viewController.view
        return try #require(controller.splitView.arrangedSubviews.first { content.isDescendant(of: $0) })
    }

    private func makeController() -> ScholiumWorkspaceSplitView<Text, Text, Text, Text>.Controller {
        .init(
            initialLibraryVisible: true, initialApparatusVisible: false,
            documentTabs: [], selectedDocumentTabID: nil, selectDocumentTab: { _ in },
            libraryVisibilityDidChange: { _ in }, researchInspectorVisibilityDidChange: { _ in },
            splitControllerDidAttach: { _ in }, splitControllerDidDetach: { _ in },
            library: Text("Library"), chat: Text("Chat"), sidebarContent: .library,
            document: Text("Document"), apparatus: Text("Research"))
    }
}
