import Foundation
import Testing

@testable import ScholiumApp

/// Opt-in native/WebKit diagnostic. Timing covers the typed Find request and
/// validated reply, not visible paint, process memory or a product gate.
@Suite("Document Find request diagnostics", .serialized)
@MainActor
struct DocumentFindPerformanceDiagnosticTests {
    @Test(
        "Dense matches preserve source and navigation through the actual WebKit bridge",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DOCUMENT_FIND"] == "1"))
    func denseMatchNavigation() async throws {
        // 1 MiB and 524,288 matches, with short logical lines so initial
        // CodeMirror measurement does not dominate the operation under test.
        let source = String(repeating: String(repeating: "x ", count: 127) + "x\n", count: 4_096)
        let total = 128 * 4_096
        let harness = MarkdownEditorWebViewIntegrationTests.EditorHarness(source: source, initialMode: .source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let initialSelection = harness.session.context?.selections
        let initialUndo = harness.session.context?.undoLabel
        for sample in 0..<4 {
            for action in [DocumentFindAction.present, .next] {
                let start = ContinuousClock.now
                let result = try await harness.session.performDocumentFind(
                    .init(query: "x", replacement: "", caseSensitive: true, wholeWord: false, action: action))
                let elapsed = start.duration(to: .now).components
                let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
                #expect(result.total == total && result.replaceable == total && result.canReplaceCurrent)
                #expect(result.current == (action == .present ? sample : sample + 1))
                #expect(harness.session.generation == 0 && !harness.session.isDirty)
                #expect(harness.session.context?.undoLabel == initialUndo)
                if sample == 0 && action == .present { #expect(harness.session.context?.selections == initialSelection) }
                print(
                    "DOCUMENT_FIND_NATIVE phase=\(sample == 0 ? "cold" : "warm") sample=\(sample) action=\(action.rawValue) "
                        + "source_bytes=\(source.utf8.count) matches=\(total) milliseconds=\(milliseconds) oracle=pass")
            }
        }
        #expect(try await harness.session.currentText().utf8.elementsEqual(source.utf8))
        #expect(harness.session.context?.selections == [.init(anchor: 6, head: 7)])
        await harness.closeAndDrain()
    }
}
