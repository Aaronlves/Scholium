import Foundation
import ScholiumContracts

enum MarkdownEditorCitationState: String, Codable, Hashable, Sendable {
    case current, stale, unresolved
}

struct MarkdownEditorCitationReference: Codable, Hashable, Sendable {
    let actionID: String
    let requestID: String
    let query: String
    let fromUTF16: Int
    let toUTF16: Int
    let caretUTF16Offset: Int
    let editorCaretUTF16Offset: Int
    let interactionRevision: Int
}

struct MarkdownEditorCitationStyle: Codable, Hashable, Sendable {
    let firstLineIndent: Double
    let indent: Double
    let lineSpacing: Double
    let entrySpacing: Double
    let tabStops: [Double]

    init(_ style: ZoteroBibliographyStyle) {
        firstLineIndent = style.firstLineIndent
        indent = style.indent
        lineSpacing = style.lineSpacing
        entrySpacing = style.entrySpacing
        tabStops = style.tabStops
    }
}

/// Closed callback values cross the existing local editor bridge. Candidate
/// source and conversion remain in CodeMirror's disposable transaction owner.
struct MarkdownEditorCitationCallback: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case canInsertField, getDocumentData, setDocumentData, cursorInField, insertField, getFields
        case setBibliographyStyle, deleteField, selectField, removeFieldCode, getFieldText, setFieldText, setFieldCode
    }
    let type: Kind
    var id: String?
    var value: String?
    var code: String?
    var html: String?
    var style: MarkdownEditorCitationStyle?

    init(_ callback: ZoteroDocumentCallback) throws {
        switch callback {
        case .canInsertField: type = .canInsertField
        case .getDocumentData: type = .getDocumentData
        case .setDocumentData(let data):
            type = .setDocumentData
            value = data
        case .cursorInField: type = .cursorInField
        case .insertField: type = .insertField
        case .getFields: type = .getFields
        case .setBibliographyStyle(let layout):
            type = .setBibliographyStyle
            style = .init(layout)
        case .deleteField(let field):
            type = .deleteField
            id = field
        case .selectField(let field):
            type = .selectField
            id = field
        case .removeFieldCode(let field):
            type = .removeFieldCode
            id = field
        case .getFieldText(let field):
            type = .getFieldText
            id = field
        case .setFieldText(let field, let text):
            type = .setFieldText
            id = field
            html = text
        case .setFieldCode(let field, let state):
            type = .setFieldCode
            id = field
            code = state
        case .activate, .displayAlert: throw MarkdownEditorSession.SessionError.invalidResult
        }
    }
}

struct MarkdownEditorCitationField: Codable, Hashable, Sendable {
    let id: String
    let code: String
    let text: String
    let noteIndex: Int
    let adjacent: Bool

    var protocolField: ZoteroDocumentField {
        .init(id: id, code: code, text: text, noteIndex: noteIndex, adjacent: adjacent)
    }
}

enum MarkdownEditorCitationReply: Codable, Hashable, Sendable {
    case none
    case boolean(Bool)
    case string(String)
    case field(MarkdownEditorCitationField?)
    case fields([MarkdownEditorCitationField])
    case selection(String)

    private enum Keys: String, CodingKey { case kind, value, fieldID }
    private enum Kind: String, Codable { case none, boolean, string, field, fields, selection }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .none: self = .none
        case .boolean: self = try .boolean(container.decode(Bool.self, forKey: .value))
        case .string: self = try .string(container.decode(String.self, forKey: .value))
        case .field: self = try .field(container.decodeIfPresent(MarkdownEditorCitationField.self, forKey: .value))
        case .fields: self = try .fields(container.decode([MarkdownEditorCitationField].self, forKey: .value))
        case .selection: self = try .selection(container.decode(String.self, forKey: .fieldID))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .none: try container.encode(Kind.none, forKey: .kind)
        case .boolean(let value):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .field(let value):
            try container.encode(Kind.field, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .fields(let value):
            try container.encode(Kind.fields, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .selection(let fieldID):
            try container.encode(Kind.selection, forKey: .kind)
            try container.encode(fieldID, forKey: .fieldID)
        }
    }

    var protocolReply: ZoteroDocumentReply {
        switch self {
        case .none, .selection: .none
        case .boolean(let value): .boolean(value)
        case .string(let value): .string(value)
        case .field(let value): .field(value?.protocolField)
        case .fields(let value): .fields(value.map(\.protocolField))
        }
    }
}
