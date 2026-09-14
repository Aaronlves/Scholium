import AppKit
import Foundation
import Testing
import WebKit

@testable import ScholiumApp

/// Opt-in diagnostic, not a product performance gate. Times the native owner
/// independently of hover intent and document-to-native transport.
@Suite("Document preview latency", .serialized)
@MainActor
struct DocumentPreviewLatencyTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_PREVIEW_LATENCY"] == "1"))
    func repeatedDisclosure() async throws {
        _ = NSApplication.shared
        let owner = WKWebView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = DocumentWebViewContainer(webView: owner)
        window.makeKeyAndOrderFront(nil)
        let controller = DocumentFloatingSurfaceController()
        defer {
            controller.dismiss()
            owner.stopLoading()
            window.close()
        }
        for sample in 0..<8 {
            let surface = DocumentFloatingSurface(
                id: sample + 1, kind: .preview, left: 280, top: 220, bottom: 240,
                html:
                    "<h2 class='scholium-preview-title'>Synthetic \(sample)</h2><div class='scholium-preview-body scholium-document'><p>Preview latency sample 中文。</p></div>",
                css: ScholiumWebFonts.css, items: [], selected: -1)
            let start = ContinuousClock.now
            controller.present(surface, in: owner) { _, _, _ in true }
            let synchronous = start.duration(to: .now)
            let deadline = start.advanced(by: .seconds(8))
            while !controller.isPreviewShown && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(2))
            }
            let ready = start.duration(to: .now)
            #expect(controller.isPreviewShown)
            let preview = try #require(controller.previewWebView)
            #expect(try await preview.evaluateJavaScript("document.querySelector('h2').textContent") as? String == "Synthetic \(sample)")
            func ms(_ duration: Duration) -> Double {
                Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
            }
            print("PREVIEW_LATENCY sample=\(sample) present_ms=\(ms(synchronous)) ready_ms=\(ms(ready))")
            controller.dismiss()
            // Allow the native closing animation to finish before the next action.
            try await Task.sleep(for: .milliseconds(300))
        }
    }
}
