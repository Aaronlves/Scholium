import Foundation
import ScholiumContracts
import WebKit

enum EditorLinkCompletionKind: String, Codable, Hashable, Sendable {
    case wikilink
    case analysisReference
}

struct EditorLinkCompletion: Codable, Hashable, Sendable {
    let label: String
    let insertion: String
    let detail: String
    let path: String
    let displayText: String?
    let isAmbiguous: Bool
}

struct EditorBridgeChange: Codable, Equatable, Sendable {
    let from: Int
    let to: Int
    let insert: String
}

struct EditorBridgeEnvelope: Equatable, Sendable {
    let protocolVersion: Int
    let sessionID: String
    let documentID: String
    let startingFingerprint: String
    let documentVersion: Int
}

struct EditorInteractionMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let selections: [MarkdownEditorSelectionRange]
    let line: Int
    let column: Int
    let lineCount: Int
    let focusTarget: WindowDocumentFocusTarget?
    let context: MarkdownEditorContext?
}

struct EditorDocumentChangeMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let baseGeneration: Int
    let resultingGeneration: Int
    let changes: [EditorBridgeChange]
}

struct EditorPerformanceMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let metric: String
    let durationMilliseconds: Double
}

struct EditorErrorMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let message: String?
}

struct EditorFindShortcutMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let action: DocumentFindShortcut
}

struct EditorDocumentTitleRenameMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let requestID: String
    let expectedTitle: String
    let requestedTitle: String
}

struct EditorLinkCompletionQueryMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let requestID: String
    let query: String
    let completionKind: EditorLinkCompletionKind
}

struct EditorLinkActivationMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let target: String
}

struct EditorContextMenuMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let clientX: Double
    let clientY: Double
    let context: MarkdownEditorContext
    let mode: MarkdownEditorMode
}

struct EditorScrollMessage: Equatable, Sendable {
    let envelope: EditorBridgeEnvelope
    let fraction: Double
    let anchor: MarkdownEditorWireScrollAnchor?
}

enum EditorBridgeMessage: Equatable, Sendable {
    case ready
    case documentEnded(editorReady: Bool)
    case editorError(EditorErrorMessage)
    case interactionChanged(EditorInteractionMessage)
    case documentChanged(EditorDocumentChangeMessage)
    case performanceSample(EditorPerformanceMessage)
    case requestSave(EditorBridgeEnvelope)
    case requestDocumentFind(EditorFindShortcutMessage)
    case requestImportImage(EditorBridgeEnvelope)
    case requestIndexImage(EditorBridgeEnvelope)
    case requestDocumentTitleRename(EditorDocumentTitleRenameMessage)
    case requestImagePaste(EditorBridgeEnvelope)
    case requestMermaidRuntime(EditorBridgeEnvelope)
    case requestMathRuntime(EditorBridgeEnvelope)
    case linkCompletionQuery(EditorLinkCompletionQueryMessage)
    case linkActivated(EditorLinkActivationMessage)
    case contextMenuRequested(EditorContextMenuMessage)
    case scrollChanged(EditorScrollMessage)

    var envelope: EditorBridgeEnvelope? {
        switch self {
        case .ready, .documentEnded: nil
        case .editorError(let message): message.envelope
        case .interactionChanged(let message): message.envelope
        case .documentChanged(let message): message.envelope
        case .performanceSample(let message): message.envelope
        case .requestSave(let envelope),
             .requestImportImage(let envelope),
             .requestIndexImage(let envelope),
             .requestImagePaste(let envelope),
             .requestMermaidRuntime(let envelope),
             .requestMathRuntime(let envelope): envelope
        case .requestDocumentTitleRename(let message): message.envelope
        case .requestDocumentFind(let message): message.envelope
        case .linkCompletionQuery(let message): message.envelope
        case .linkActivated(let message): message.envelope
        case .contextMenuRequested(let message): message.envelope
        case .scrollChanged(let message): message.envelope
        }
    }
}

/// The only JavaScript-to-Swift editor decoder. WebKit has already converted
/// the local page object into Foundation values, so ordinary typing remains a
/// direct bounded delta path while every message still becomes one typed case
/// through the same envelope and field validators.
enum EditorBridgeMessageDecoder {
    private static let envelopeKeys: Set<String> = [
        "protocolVersion", "sessionID", "documentID",
        "startingFingerprint", "documentVersion",
    ]

    static func decode(_ body: Any) -> EditorBridgeMessage? {
        guard let object = body as? [String: Any],
              let type = boundedString(object["type"], maximumUTF8Bytes: 64) else {
            return nil
        }
        if type != "documentChanged" {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  data.count <= markdownEditorMaximumInboundBytes else { return nil }
        }

        switch type {
        case "ready":
            guard hasOnlyKeys(object, additional: ["type"]),
                  integer(object["protocolVersion"]) == markdownEditorProtocolVersion else {
                return nil
            }
            return .ready
        case "documentEnded":
            guard hasExactKeys(object, ["type", "editorReady"]),
                  let editorReady = object["editorReady"] as? Bool else { return nil }
            return .documentEnded(editorReady: editorReady)
        default:
            guard let envelope = envelope(from: object) else { return nil }
            return decodeSessionMessage(type, object: object, envelope: envelope)
        }
    }

    private static func decodeSessionMessage(
        _ type: String,
        object: [String: Any],
        envelope: EditorBridgeEnvelope
    ) -> EditorBridgeMessage? {
        switch type {
        case "editorError":
            guard hasOnlyKeys(object, additional: ["type", "message"]),
                  let message = optionalBoundedString(
                    object["message"], maximumUTF8Bytes: 16_384
                  ) else { return nil }
            return .editorError(EditorErrorMessage(
                envelope: envelope,
                message: message
            ))
        case "interactionChanged":
            guard hasOnlyKeys(object, additional: [
                "type", "selections", "line", "column", "lineCount", "focusTarget", "context",
            ]),
            let selections: [MarkdownEditorSelectionRange] = decodable(object["selections"]),
            selections.count <= markdownEditorMaximumSelectionRangeCount,
            let line = nonnegativeInteger(object["line"]),
            let column = nonnegativeInteger(object["column"]),
            let lineCount = nonnegativeInteger(object["lineCount"]),
            let focusTarget = optionalFocusTarget(object["focusTarget"]),
            let context: MarkdownEditorContext? = optionalDecodable(object["context"])
            else { return nil }
            return .interactionChanged(EditorInteractionMessage(
                envelope: envelope,
                selections: selections,
                line: line,
                column: column,
                lineCount: lineCount,
                focusTarget: focusTarget,
                context: context
            ))
        case "documentChanged":
            guard hasOnlyKeys(object, additional: [
                "type", "baseGeneration", "resultingGeneration", "changes",
            ]),
            let baseGeneration = nonnegativeInteger(object["baseGeneration"]),
            let resultingGeneration = nonnegativeInteger(object["resultingGeneration"]),
            envelope.documentVersion == resultingGeneration,
            let changes = changes(object["changes"])
            else { return nil }
            return .documentChanged(EditorDocumentChangeMessage(
                envelope: envelope,
                baseGeneration: baseGeneration,
                resultingGeneration: resultingGeneration,
                changes: changes
            ))
        case "performanceSample":
            guard hasOnlyKeys(object, additional: [
                "type", "metric", "durationMilliseconds",
            ]),
            let metric = boundedString(object["metric"], maximumUTF8Bytes: 64),
            let duration = finiteDouble(object["durationMilliseconds"])
            else { return nil }
            return .performanceSample(EditorPerformanceMessage(
                envelope: envelope,
                metric: metric,
                durationMilliseconds: duration
            ))
        case "requestSave":
            return exactEnvelopeMessage(object, envelope: envelope, case: .requestSave)
        case "requestImportImage":
            return exactEnvelopeMessage(object, envelope: envelope, case: .requestImportImage)
        case "requestIndexImage":
            return exactEnvelopeMessage(object, envelope: envelope, case: .requestIndexImage)
        case "requestDocumentTitleRename":
            guard hasOnlyKeys(object, additional: [
                "type", "requestID", "expectedTitle", "requestedTitle",
            ]),
            let requestID = boundedString(object["requestID"], maximumUTF8Bytes: 128),
            UUID(uuidString: requestID) != nil,
            let expectedTitle = boundedString(
                object["expectedTitle"], maximumUTF8Bytes: 4_096
            ),
            !expectedTitle.isEmpty,
            expectedTitle.utf16.count <= 1_024,
            let requestedTitle = boundedString(
                object["requestedTitle"], maximumUTF8Bytes: 4_096
            ),
            requestedTitle.utf16.count <= 1_024
            else { return nil }
            return .requestDocumentTitleRename(EditorDocumentTitleRenameMessage(
                envelope: envelope,
                requestID: requestID,
                expectedTitle: expectedTitle,
                requestedTitle: requestedTitle
            ))
        case "requestImagePaste":
            return exactEnvelopeMessage(object, envelope: envelope, case: .requestImagePaste)
        case "requestMermaidRuntime":
            return exactEnvelopeMessage(object, envelope: envelope, case: .requestMermaidRuntime)
        case "requestMathRuntime":
            return exactEnvelopeMessage(object, envelope: envelope, case: .requestMathRuntime)
        case "requestDocumentFind":
            guard hasOnlyKeys(object, additional: ["type", "action"]),
                  let rawAction = boundedString(object["action"], maximumUTF8Bytes: 32),
                  let action = DocumentFindShortcut(rawValue: rawAction) else { return nil }
            return .requestDocumentFind(EditorFindShortcutMessage(
                envelope: envelope,
                action: action
            ))
        case "linkCompletionQuery":
            guard hasOnlyKeys(object, additional: [
                "type", "requestID", "completionKind", "query",
            ]),
            let requestID = boundedString(object["requestID"], maximumUTF8Bytes: 128),
            UUID(uuidString: requestID) != nil,
            let rawKind = boundedString(object["completionKind"], maximumUTF8Bytes: 32),
            let completionKind = EditorLinkCompletionKind(rawValue: rawKind),
            let query = boundedString(object["query"], maximumUTF8Bytes: 2_048),
            query.utf16.count <= 512
            else { return nil }
            return .linkCompletionQuery(EditorLinkCompletionQueryMessage(
                envelope: envelope,
                requestID: requestID,
                query: query,
                completionKind: completionKind
            ))
        case "linkActivated":
            guard hasOnlyKeys(object, additional: ["type", "target"]),
                  let target = boundedString(object["target"], maximumUTF8Bytes: 8_192),
                  !target.isEmpty else { return nil }
            return .linkActivated(EditorLinkActivationMessage(
                envelope: envelope,
                target: target
            ))
        case "contextMenuRequested":
            guard hasOnlyKeys(object, additional: [
                "type", "clientX", "clientY", "context", "mode",
            ]),
            let clientX = finiteDouble(object["clientX"]),
            let clientY = finiteDouble(object["clientY"]),
            let context: MarkdownEditorContext = decodable(object["context"]),
            let rawMode = boundedString(object["mode"], maximumUTF8Bytes: 32),
            let mode = MarkdownEditorMode(rawValue: rawMode)
            else { return nil }
            return .contextMenuRequested(EditorContextMenuMessage(
                envelope: envelope,
                clientX: clientX,
                clientY: clientY,
                context: context,
                mode: mode
            ))
        case "scrollChanged":
            guard hasOnlyKeys(object, additional: ["type", "scrollFraction", "scrollAnchor"]),
                  let fraction = finiteDouble(object["scrollFraction"]),
                  let anchor: MarkdownEditorWireScrollAnchor? = optionalDecodable(
                    object["scrollAnchor"]
                  ) else { return nil }
            return .scrollChanged(EditorScrollMessage(
                envelope: envelope,
                fraction: fraction,
                anchor: anchor
            ))
        default:
            return nil
        }
    }

    private enum EnvelopeOnlyCase {
        case requestSave
        case requestImportImage
        case requestIndexImage
        case requestImagePaste
        case requestMermaidRuntime
        case requestMathRuntime
    }

    private static func exactEnvelopeMessage(
        _ object: [String: Any],
        envelope: EditorBridgeEnvelope,
        case messageCase: EnvelopeOnlyCase
    ) -> EditorBridgeMessage? {
        guard hasOnlyKeys(object, additional: ["type"]) else { return nil }
        return switch messageCase {
        case .requestSave: .requestSave(envelope)
        case .requestImportImage: .requestImportImage(envelope)
        case .requestIndexImage: .requestIndexImage(envelope)
        case .requestImagePaste: .requestImagePaste(envelope)
        case .requestMermaidRuntime: .requestMermaidRuntime(envelope)
        case .requestMathRuntime: .requestMathRuntime(envelope)
        }
    }

    private static func envelope(from object: [String: Any]) -> EditorBridgeEnvelope? {
        guard let protocolVersion = integer(object["protocolVersion"]),
              protocolVersion == markdownEditorProtocolVersion,
              let sessionID = boundedString(object["sessionID"], maximumUTF8Bytes: 128),
              !sessionID.isEmpty,
              let documentID = boundedString(object["documentID"], maximumUTF8Bytes: 4_096),
              !documentID.isEmpty,
              let fingerprint = boundedString(
                object["startingFingerprint"], maximumUTF8Bytes: 256
              ),
              !fingerprint.isEmpty,
              let documentVersion = nonnegativeInteger(object["documentVersion"])
        else { return nil }
        return EditorBridgeEnvelope(
            protocolVersion: protocolVersion,
            sessionID: sessionID,
            documentID: documentID,
            startingFingerprint: fingerprint,
            documentVersion: documentVersion
        )
    }

    private static func changes(_ value: Any?) -> [EditorBridgeChange]? {
        guard let rawChanges = value as? [Any],
              !rawChanges.isEmpty,
              rawChanges.count <= 512 else { return nil }
        var insertedUTF8Bytes = 0
        var result: [EditorBridgeChange] = []
        result.reserveCapacity(rawChanges.count)
        for raw in rawChanges {
            guard let change = raw as? [String: Any],
                  hasExactKeys(change, ["from", "to", "insert"]),
                  let from = nonnegativeInteger(change["from"]),
                  let to = nonnegativeInteger(change["to"]),
                  to >= from,
                  let insert = change["insert"] as? String else { return nil }
            insertedUTF8Bytes += insert.utf8.count
            guard insertedUTF8Bytes <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes else {
                return nil
            }
            result.append(EditorBridgeChange(from: from, to: to, insert: insert))
        }
        return result
    }

    private static func optionalFocusTarget(
        _ value: Any?
    ) -> WindowDocumentFocusTarget?? {
        guard let value else { return .some(nil) }
        guard let raw = value as? String,
              let target = WindowDocumentFocusTarget(rawValue: raw) else {
            return nil
        }
        return .some(target)
    }

    private static func hasOnlyKeys(
        _ object: [String: Any],
        additional: Set<String>
    ) -> Bool {
        Set(object.keys).isSubset(of: envelopeKeys.union(additional))
    }

    private static func hasExactKeys(
        _ object: [String: Any],
        _ keys: Set<String>
    ) -> Bool {
        Set(object.keys) == keys
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let integer = number.intValue
        guard NSNumber(value: integer) == number else { return nil }
        return integer
    }

    private static func nonnegativeInteger(_ value: Any?) -> Int? {
        guard let value = integer(value), value >= 0 else { return nil }
        return value
    }

    private static func finiteDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func boundedString(
        _ value: Any?,
        maximumUTF8Bytes: Int
    ) -> String? {
        guard let value = value as? String,
              value.utf8.count <= maximumUTF8Bytes else { return nil }
        return value
    }

    /// Distinguishes an absent optional string from an invalid present value.
    private static func optionalBoundedString(
        _ value: Any?,
        maximumUTF8Bytes: Int
    ) -> String?? {
        guard let value else { return .some(nil) }
        guard let string = boundedString(value, maximumUTF8Bytes: maximumUTF8Bytes) else {
            return nil
        }
        return .some(string)
    }

    private static func decodable<Value: Decodable>(_ value: Any?) -> Value? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    /// Distinguishes a missing optional payload from an invalid present one.
    private static func optionalDecodable<Value: Decodable>(_ value: Any?) -> Value?? {
        guard let value else { return .some(nil) }
        guard let decoded: Value = decodable(value) else { return nil }
        return .some(decoded)
    }
}

@MainActor
protocol MarkdownEditorBridgeDispatching: AnyObject {
    func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any?
}

@MainActor
final class WKWebViewMarkdownEditorBridgeDispatcher: MarkdownEditorBridgeDispatching {
    func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            "return await window.scholiumEditor.dispatch(JSON.parse(requestJSON))",
            arguments: ["requestJSON": requestJSON],
            in: nil,
            contentWorld: .page
        )
    }
}
