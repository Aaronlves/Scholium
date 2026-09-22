import AppKit
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Document native environment projection", .serialized)
@MainActor
struct DocumentWebEnvironmentTests {
    @Test("Reload reapplies native values without owning document content or DOM selection")
    func reloadAndSelection() async throws {
        let web = WKWebView()
        let host = NSView()
        host.addSubview(web)
        let environment = DocumentWebEnvironment(webView: web, hostView: host)
        let navigation = Navigation()
        web.navigationDelegate = navigation
        environment.updateToolbarInset(52)
        try await navigation.load(web, text: "First document")
        environment.refreshAppearance()
        #expect(try await toolbarInset(in: web) == "52.0px")
        _ = try await web.callAsyncJavaScript(
            """
            const range = document.createRange();
            range.selectNodeContents(document.body.firstChild);
            getSelection().removeAllRanges(); getSelection().addRange(range);
            """, arguments: [:], in: nil, contentWorld: .page
        )
        environment.updateToolbarInset(36)
        #expect(try await toolbarInset(in: web) == "36.0px")
        let selection =
            try await web.callAsyncJavaScript(
                "return getSelection().toString()", arguments: [:], in: nil, contentWorld: .page
            ) as? String
        #expect(selection == "First document")

        try await navigation.load(web, text: "Second document")
        // A layout with unchanged geometry must still reach the new page.
        environment.updateToolbarInset(36)
        #expect(try await toolbarInset(in: web) == "36.0px")
        let text =
            try await web.callAsyncJavaScript(
                "return document.body.textContent", arguments: [:], in: nil, contentWorld: .page
            ) as? String
        #expect(text == "Second document")
    }

    @Test("An old host cannot project into recycled WebKit and observers do not retain the owner")
    func attachmentOwnershipAndRelease() async throws {
        let web = WKWebView()
        let oldHost = NSView()
        oldHost.addSubview(web)
        var oldEnvironment: DocumentWebEnvironment? = .init(webView: web, hostView: oldHost)
        weak let releasedEnvironment = oldEnvironment
        let navigation = Navigation()
        web.navigationDelegate = navigation
        try await navigation.load(web, text: "Synthetic document")
        oldEnvironment?.updateToolbarInset(52)
        #expect(try await toolbarInset(in: web) == "52.0px")

        let newHost = NSView()
        newHost.addSubview(web)
        let newEnvironment = DocumentWebEnvironment(webView: web, hostView: newHost)
        newEnvironment.updateToolbarInset(18)
        #expect(try await toolbarInset(in: web) == "18.0px")
        oldEnvironment?.updateToolbarInset(99)
        oldEnvironment?.refreshAppearance()
        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        #expect(try await toolbarInset(in: web) == "18.0px")

        oldEnvironment = nil
        #expect(releasedEnvironment == nil)
    }

    private func toolbarInset(in web: WKWebView) async throws -> String? {
        // Same content world as delivery: this read is queued after projection.
        try await web.callAsyncJavaScript(
            "return document.documentElement.style.getPropertyValue('--scholium-document-toolbar-inset')",
            arguments: [:], in: nil, contentWorld: .defaultClient
        ) as? String
    }

    private final class Navigation: NSObject, WKNavigationDelegate {
        private var completion: CheckedContinuation<Void, Error>?

        func load(_ web: WKWebView, text: String) async throws {
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                web.loadHTMLString("<!doctype html><html><body>\(text)</body></html>", baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            completion?.resume()
            completion = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            completion?.resume(throwing: error)
            completion = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            completion?.resume(throwing: error)
            completion = nil
        }
    }
}
