import Foundation

public enum AgentChatPDFPageSelectionFailure: LocalizedError {
    case invalidRange, tooManyPages, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalidRange: String(localized: "Enter valid PDF page numbers, such as 1–5, 8.")
        case .tooManyPages: String(localized: "Choose up to 20 pages for one image input.")
        case .unavailable: String(localized: "The retained PDF is unavailable or locked. Replace it and try again.")
        }
    }
}
