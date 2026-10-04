import Foundation

public enum ExactFileReplacementError: LocalizedError, Sendable {
    case revisionConflict
    case commitUncertain(String)

    public var errorDescription: String? {
        switch self {
        case .revisionConflict: "The configuration file or its directory changed. Reload before trying again."
        case .commitUncertain(let reason): "The configuration replacement could not be proven: \(reason)"
        }
    }
}

public enum IndexedAttachmentAccessError: LocalizedError, Sendable {
    case damaged(String)
    case bookmarkUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .damaged(let reason):
            "The machine-local indexed-attachment access store is damaged: \(reason)"
        case .bookmarkUnavailable(let path):
            "Scholium could not retain read access to the indexed attachment at \(path)."
        }
    }
}

public enum BundledResearchSkillResourceError: LocalizedError, Sendable {
    case unavailable
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "The bundled Scholium Core Protocol is unavailable."
        case .invalid(let path):
            "The bundled Scholium Core Protocol is invalid at \(path)."
        }
    }
}
