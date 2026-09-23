import Foundation

enum EditorPastedImageSource: Sendable {
    case file(URL)
    case data(Data, preferredFilename: String)
}

enum EditorWritingContinuationStatus: String, Equatable, Sendable {
    case preparing
    case retrieving
    case generating
}

enum EditorWritingContinuationUnavailableReason: String, Equatable, Sendable {
    case disabled
    case notConnected
    case notReady
    case modelUnavailable
    case busy
    case connectionError
    case timedOut
    case noSuggestion
    case invalidContext
    case cancelled
    case serviceError

    var localizationKey: String {
        switch self {
        case .disabled:
            "AI continuation is not enabled."
        case .notConnected:
            "AI continuation is not connected. Connect Codex in Agents & Chat."
        case .notReady:
            "AI continuation is not ready. Check Writing Assistance settings."
        case .modelUnavailable:
            "The selected AI continuation model is unavailable. Choose an available model in Writing Assistance."
        case .busy:
            "AI continuation is still stopping. Try again in a moment."
        case .connectionError:
            "AI continuation could not connect. Check Agents & Chat."
        case .timedOut:
            "AI continuation timed out. Library completion remains available."
        case .noSuggestion:
            "AI returned no usable continuation. Library completion remains available."
        case .invalidContext:
            "AI continuation could not be used for this writing context."
        case .cancelled:
            "AI continuation was cancelled."
        case .serviceError:
            "AI continuation could not be generated. Library completion remains available."
        }
    }

    var showsInEditor: Bool {
        switch self {
        case .disabled, .invalidContext, .cancelled:
            false
        case .notConnected, .notReady, .modelUnavailable, .busy, .connectionError, .timedOut,
            .noSuggestion, .serviceError:
            true
        }
    }
}

enum EditorWritingContinuationResult: Equatable, Sendable {
    case suggestion(String)
    case unavailable(EditorWritingContinuationUnavailableReason?)
}

typealias EditorWritingContinuationStatusHandler =
    @MainActor (EditorWritingContinuationStatus) -> Void
typealias EditorWritingContinuationQuery =
    @MainActor (Int, EditorWritingContinuationStatusHandler) async -> EditorWritingContinuationResult

enum EditorLinkCompletionKind: String, Codable, Hashable, Sendable {
    case wikilink
    case analysisReference
    case term
}

struct EditorLinkCompletion: Codable, Hashable, Sendable {
    let label: String
    let insertion: String
    let detail: String
    let path: String
    let displayText: String?
    let isAmbiguous: Bool
    var writingAction: String? = nil
    var replacementUTF16Count: Int? = nil
}
