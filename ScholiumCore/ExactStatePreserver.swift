import Darwin
import Foundation

enum ExactStatePreservationError: LocalizedError {
    case missing(String)
    case unsafe(String)
    case preservationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missing(let path):
            "The state to preserve no longer exists at \(path)."
        case .unsafe(let reason), .preservationFailed(let reason):
            reason
        }
    }
}

/// Moves one directly owned file or directory to a unique sibling recovery
/// name, then proves that the same filesystem object arrived at the
/// destination. Files additionally receive an exact-byte readback check.
///
/// The caller owns the semantic decision that the source is unsupported or
/// damaged. This primitive never decodes, migrates, or replaces its contents.
enum ExactStatePreserver {
    enum Kind {
        case regularFile
        case directory
    }

    static func preserve(
        _ sourceURL: URL,
        kind: Kind,
        recoveryStem: String,
        recoveryExtension: String? = nil,
        fileEligibility: ((Data) throws -> Bool)? = nil,
        directoryEligibility: ((URL) throws -> Bool)? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let source = sourceURL.standardizedFileURL
        guard entryExists(at: source) else {
            throw ExactStatePreservationError.missing(source.path)
        }
        let values = try source.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileResourceIdentifierKey,
        ])
        guard values.isSymbolicLink != true,
              (kind == .regularFile ? values.isRegularFile == true : values.isDirectory == true),
              let identifier = values.fileResourceIdentifier else {
            throw ExactStatePreservationError.unsafe(
                "The state at \(source.path) is linked, has the wrong type, or cannot be bound to one filesystem object."
            )
        }
        let sourceIdentity = String(describing: identifier)
        let sourceData: Data? = switch kind {
        case .regularFile:
            try Data(contentsOf: source, options: [.mappedIfSafe])
        case .directory:
            nil
        }
        if let sourceData, let fileEligibility,
           try !fileEligibility(sourceData) {
            throw ExactStatePreservationError.preservationFailed(
                "The file changed and no longer qualifies for recovery. Reload its current state."
            )
        }
        if kind == .directory, let directoryEligibility,
           try !directoryEligibility(source) {
            throw ExactStatePreservationError.preservationFailed(
                "The directory changed and no longer qualifies for recovery. Reload its current state."
            )
        }
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        var name = "\(recoveryStem)-\(timestamp)-\(UUID().uuidString.lowercased())"
        if let recoveryExtension { name += ".\(recoveryExtension)" }
        let destination = source.deletingLastPathComponent().appendingPathComponent(
            name,
            isDirectory: kind == .directory
        )

        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw ExactStatePreservationError.preservationFailed(
                "The original state could not be moved to its recovery location: \(error.localizedDescription)"
            )
        }

        do {
            let movedValues = try destination.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileResourceIdentifierKey,
            ])
            let movedIdentity = movedValues.fileResourceIdentifier.map(String.init(describing:))
            guard movedValues.isSymbolicLink != true,
                  (kind == .regularFile
                    ? movedValues.isRegularFile == true
                    : movedValues.isDirectory == true),
                  movedIdentity == sourceIdentity else {
                throw ExactStatePreservationError.preservationFailed(
                    "The preserved state did not retain the source filesystem identity."
                )
            }
            if let sourceData {
                let movedData = try Data(contentsOf: destination, options: [.mappedIfSafe])
                guard movedData == sourceData else {
                    throw ExactStatePreservationError.preservationFailed(
                        "The preserved file did not retain the exact source bytes."
                    )
                }
            }
            if kind == .directory, let directoryEligibility,
               try !directoryEligibility(destination) {
                throw ExactStatePreservationError.preservationFailed(
                    "The directory changed while recovery was preserving it."
                )
            }
        } catch {
            if !fileManager.fileExists(atPath: source.path) {
                try? fileManager.moveItem(at: destination, to: source)
            }
            if let preservation = error as? ExactStatePreservationError {
                throw preservation
            }
            throw ExactStatePreservationError.preservationFailed(
                "The preserved state could not be verified: \(error.localizedDescription)"
            )
        }
        return destination
    }

    static func entryExists(at url: URL) -> Bool {
        var status = stat()
        return url.path.withCString { lstat($0, &status) == 0 }
    }
}
