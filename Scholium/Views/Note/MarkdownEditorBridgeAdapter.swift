import Foundation
import WebKit

struct EditorLinkCompletion: Codable, Hashable, Sendable {
    let label: String
    let insertion: String
    let detail: String
    let path: String
    let isAmbiguous: Bool
}

struct EditorBridgeChange: Codable {
    let from: Int
    let to: Int
    let insert: String
}

struct EditorBridgeMessage: Codable {
    let type: String
    let protocolVersion: Int?
    let sessionID: String?
    let documentID: String?
    let startingFingerprint: String?
    let documentVersion: Int?
    let baseGeneration: Int?
    let resultingGeneration: Int?
    let changes: [EditorBridgeChange]?
    let dirty: Bool?
    let line: Int?
    let column: Int?
    let lineCount: Int?
    let selections: [MarkdownEditorSelectionRange]?
    let message: String?
    let editorReady: Bool?
    let scrollFraction: Double?
    let scrollAnchor: MarkdownEditorWireScrollAnchor?
    let target: String?
    let requestID: String?
    let query: String?
    let context: MarkdownEditorContext?
    let clientX: Double?
    let clientY: Double?
    let mode: MarkdownEditorMode?
}

@MainActor
protocol MarkdownEditorBridgeDispatching: AnyObject {
    func dispatch(
        requestJSON: String,
        in webView: WKWebView
    ) async throws -> Any?
}

@MainActor
final class WKWebViewMarkdownEditorBridgeDispatcher: MarkdownEditorBridgeDispatching {
    func dispatch(
        requestJSON: String,
        in webView: WKWebView
    ) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            "return await window.scholiumEditor.dispatch(JSON.parse(requestJSON))",
            arguments: ["requestJSON": requestJSON],
            in: nil,
            contentWorld: .page
        )
    }
}
