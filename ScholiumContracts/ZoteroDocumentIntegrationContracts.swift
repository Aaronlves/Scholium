public enum ZoteroDocumentCommand: String, Sendable {
    case addEditCitation, addEditBibliography, refresh, setDocPrefs
}

/// Values are copied from authoritative Markdown. `text` is the currently
/// rendered plain text, not cached HTML or `properties.plainCitation`.
public struct ZoteroDocumentField: Equatable, Sendable {
    public let id: String
    public let code: String
    public let text: String
    public let noteIndex: Int
    public let adjacent: Bool

    public init(id: String, code: String, text: String, noteIndex: Int = 0, adjacent: Bool = false) {
        self.id = id
        self.code = code
        self.text = text
        self.noteIndex = noteIndex
        self.adjacent = adjacent
    }
}

public struct ZoteroBibliographyStyle: Equatable, Sendable {
    public let firstLineIndent: Double
    public let indent: Double
    public let lineSpacing: Double
    public let entrySpacing: Double
    public let tabStops: [Double]

    public init(firstLineIndent: Double, indent: Double, lineSpacing: Double, entrySpacing: Double, tabStops: [Double]) {
        self.firstLineIndent = firstLineIndent
        self.indent = indent
        self.lineSpacing = lineSpacing
        self.entrySpacing = entrySpacing
        self.tabStops = tabStops
    }
}

/// The source transaction owns all effects. The HTTP client neither edits a
/// document nor publishes a candidate when the remote transaction completes.
public enum ZoteroDocumentCallback: Equatable, Sendable {
    case activate, canInsertField, getDocumentData
    case setDocumentData(String)
    case cursorInField, insertField, getFields
    case setBibliographyStyle(ZoteroBibliographyStyle)
    case displayAlert(text: String, icon: Int, buttons: Int)
    case deleteField(String)
    case selectField(String)
    case removeFieldCode(String)
    case getFieldText(String)
    case setFieldText(id: String, html: String)
    case setFieldCode(id: String, code: String)
}

public enum ZoteroDocumentReply: Equatable, Sendable {
    case none
    case boolean(Bool)
    case string(String)
    case field(ZoteroDocumentField?)
    case fields([ZoteroDocumentField])
    case alert(Int)
}

public enum ZoteroDocumentAuthority: Equatable, Sendable {
    case current, cancelled, unavailable
}

public struct ZoteroDocumentIntegrationResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Cleanup was observed. The source owner must separately validate
        /// acceptance, current editor authority and its complete candidate.
        case cleanedUp, cancelled, unavailable, failed, busy, unknown
    }

    public let status: Status
    public let remoteCleanupConfirmed: Bool
    public let callbackCount: Int
    public let message: String?

    public init(status: Status, remoteCleanupConfirmed: Bool, callbackCount: Int, message: String?) {
        self.status = status
        self.remoteCleanupConfirmed = remoteCleanupConfirmed
        self.callbackCount = callbackCount
        self.message = message
    }
}

/// Delivery consumes this bounded callback port; Application owns its HTTP
/// transport and serialization. The source owner alone can accept a candidate.
public protocol ZoteroDocumentIntegrating: Sendable {
    func run(
        transactionID: String,
        command: ZoteroDocumentCommand,
        documentID: String,
        authority: @escaping @Sendable () async -> ZoteroDocumentAuthority,
        handler: @escaping @Sendable (ZoteroDocumentCallback) async throws -> ZoteroDocumentReply
    ) async -> ZoteroDocumentIntegrationResult

    func cancelCurrentTransaction(transactionID: String) async
}
