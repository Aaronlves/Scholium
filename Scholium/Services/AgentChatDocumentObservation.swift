import Foundation
import ScholiumContracts

/// The Chat boundary carries coordinates and identity, never an editor buffer.
struct AgentChatDocumentObservation: Sendable {
    enum Surface: String, Sendable {
        case none
        case triptychNote = "triptych_note"
        case externalDocument = "external_document"
        case unavailable
    }
    enum Revision: Equatable, Sendable {
        enum Unavailable: String, Sendable {
            case loading
            case composing
            case sourceSnapshotUnavailable = "source_snapshot_unavailable"
        }
        case savedSource(DocumentFingerprint)
        case editorSnapshot(DocumentFingerprint)
        case unavailable(Unavailable)
        var jsonValue: MCPJSONValue {
            switch self {
            case .savedSource(let fingerprint), .editorSnapshot(let fingerprint):
                return .object([
                    "origin": .string(
                        {
                            if case .savedSource = self { return "saved_source" }
                            return "editor_snapshot"
                        }()),
                    "fingerprint": .object(["sha256": .string(fingerprint.sha256), "byte_count": .integer(fingerprint.byteCount)]),
                ])
            case .unavailable(let reason): return .object(["origin": .string("unavailable"), "reason": .string(reason.rawValue)])
            }
        }
    }
    enum Selection: Equatable, Sendable {
        enum Unavailable: String, Sendable {
            case loading
            case composing
            case multipleSelections = "multiple_selections"
            case staleRenderer = "stale_renderer"
            case sourceMappingUnavailable = "source_mapping_unavailable"
        }
        struct Extent: Equatable, Sendable {
            let startUTF8: Int
            let endUTF8: Int
            let startLine: Int
            let endLine: Int
        }
        case none
        case range(Extent)
        case unavailable(Unavailable)
        var jsonValue: MCPJSONValue {
            switch self {
            case .none: return .object(["state": .string("none")])
            case .unavailable(let reason): return .object(["state": .string("unavailable"), "reason": .string(reason.rawValue)])
            case .range(let extent):
                return .object([
                    "state": .string("range"), "start_utf8": .integer(extent.startUTF8), "end_utf8": .integer(extent.endUTF8),
                    "byte_count": .integer(extent.endUTF8 - extent.startUTF8), "start_line": .integer(extent.startLine), "end_line": .integer(extent.endLine),
                ])
            }
        }

        static func exactSourceRange(_ offsets: Range<Int>, in source: String) -> Self {
            let utf16 = source.utf16
            guard offsets.lowerBound >= 0, offsets.upperBound <= utf16.count else { return .unavailable(.sourceMappingUnavailable) }
            let lower = utf16.index(utf16.startIndex, offsetBy: offsets.lowerBound)
            let upper = utf16.index(utf16.startIndex, offsetBy: offsets.upperBound)
            // String slicing can round an interior UTF-16 surrogate index to a
            // scalar. Exact byte coordinates must reject that range instead.
            guard let byteLower = lower.samePosition(in: source.utf8), let byteUpper = upper.samePosition(in: source.utf8)
            else { return .unavailable(.sourceMappingUnavailable) }
            guard byteLower != byteUpper else { return .none }
            let prefix = source.utf8[..<byteLower]
            let selected = source.utf8[byteLower..<byteUpper]
            let startLine = 1 + prefix.filter { $0 == 10 }.count
            return .range(
                .init(
                    startUTF8: prefix.count, endUTF8: prefix.count + selected.count,
                    startLine: startLine, endLine: startLine + selected.filter { $0 == 10 }.count))
        }

        static func editor(source: String, selections: [MarkdownEditorSelectionRange]) -> Self {
            guard selections.count == 1, let selection = selections.first else {
                return .unavailable(selections.isEmpty ? .sourceMappingUnavailable : .multipleSelections)
            }
            let map = EditorSourceOffsetMap(source: source)
            guard let lower = map.sourceUTF16Offset(forEditorUTF16Offset: min(selection.anchor, selection.head)),
                let upper = map.sourceUTF16Offset(forEditorUTF16Offset: max(selection.anchor, selection.head))
            else { return .unavailable(.sourceMappingUnavailable) }
            return exactSourceRange(lower..<upper, in: source)
        }
    }
    struct ActiveNote: Sendable {
        let vaultID: UUID
        let noteID: UUID
        let role: VaultRole
        let relativePath: String
        let mode: NotePresentationMode
        let revision: Revision
        let dirty: Bool
        let saving: Bool
        let conflict: Bool
        let selection: Selection
        var jsonValue: MCPJSONValue {
            .object([
                "vault_id": .string(vaultID.uuidString.lowercased()), "note_id": .string(noteID.uuidString.lowercased()),
                "role": .string(role == .sourceCorpus ? "analyses" : role == .topicKnowledge ? "topics" : "works"),
                "relative_path": .string(relativePath),
                "mode": .string(mode == .read ? "review" : mode == .source ? "source" : "edit"),
                "revision": revision.jsonValue, "dirty": .bool(dirty), "saving": .bool(saving), "conflict": .bool(conflict),
                "selection": selection.jsonValue,
            ])
        }
    }
    let surface: Surface
    let activeNote: ActiveNote?
    let hasSaveError: Bool

    init(surface: Surface, activeNote: ActiveNote? = nil, hasSaveError: Bool = false) {
        self.surface = surface
        self.activeNote = activeNote
        self.hasSaveError = hasSaveError
    }

    var jsonValue: MCPJSONValue { .object(["document_surface": .string(surface.rawValue), "active_note": activeNote?.jsonValue ?? .null]) }
    var errorCodes: [String] { (hasSaveError ? ["document_save"] : []) + (activeNote?.conflict == true ? ["document_conflict"] : []) }
}
