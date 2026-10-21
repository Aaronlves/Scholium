import Foundation
import Testing
import WebKit

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Pre-cancelled bundled runtime loads leave the current WK page untouched")
    func cancelledRuntimeLoadsHaveNoPageEffects() async throws {
        let source = "A disposable plain-text runtime cancellation fixture.\n"
        let harness = EditorHarness(source: source, initialMode: .source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let webView = try #require(harness.session.webView)
        _ = try await harness.callPageJavaScript(
            """
            window.__runtimeCancellationEffects = {mathSettled: 0, mathRefreshed: 0, mermaidNotified: 0};
            window.addEventListener('scholium-math-runtime-settled', () => window.__runtimeCancellationEffects.mathSettled++);
            window.scholiumEditor.refreshMathRuntime = () => { window.__runtimeCancellationEffects.mathRefreshed++; return true; };
            window.scholiumMermaidRuntimeDidLoad = () => window.__runtimeCancellationEffects.mermaidNotified++;
            """)

        // Cancellation is observed before entering either real loader. This
        // does not simulate a WK callback paused across a process reload.
        let math = Task { @MainActor in
            let wasCancelled = Task.isCancelled
            let installed = await ScholiumMathRuntimeLoader.installAndRefresh(in: webView, contentWorld: .page)
            return (wasCancelled, installed)
        }
        math.cancel()
        let mathResult = await math.value
        #expect(mathResult.0)
        #expect(!mathResult.1)

        let mermaid = Task { @MainActor in
            let wasCancelled = Task.isCancelled
            await ScholiumMermaidRuntimeLoader.installAndNotify(in: webView)
            return wasCancelled
        }
        mermaid.cancel()
        #expect(await mermaid.value)

        let effects = try #require(
            try await harness.callPageJavaScript(
                """
                return {...window.__runtimeCancellationEffects,
                  mathInstalled: window.scholiumMath?.version === 1,
                  mermaidInstalled: window.scholiumMermaid?.version === 3};
                """) as? [String: Any])
        for key in ["mathSettled", "mathRefreshed", "mermaidNotified"] {
            #expect(effects[key] as? Int == 0)
        }
        #expect(effects["mathInstalled"] as? Bool == false)
        #expect(effects["mermaidInstalled"] as? Bool == false)
        #expect(harness.session.webView === webView)
        #expect(!harness.session.isDirty)
        #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }
}
