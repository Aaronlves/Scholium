import Foundation
import Subprocess

/// Ephemeral package I/O for a generated Word export. Callers format immutable
/// part bytes; this owner never reads or writes a research Note or destination.
public enum WordDocumentArchiveOperations {
    public static func unpack(_ data: Data) async throws -> [String: Data] {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("Scholium-Word-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let source = root.appendingPathComponent("source.docx")
        let package = root.appendingPathComponent("package", isDirectory: true)
        try files.createDirectory(at: package, withIntermediateDirectories: true)
        try data.write(to: source)
        try await run("/usr/bin/unzip", arguments: ["-q", source.path, "-d", package.path], directory: root)
        return try readParts(at: package)
    }

    private static func readParts(at package: URL) throws -> [String: Data] {
        let files = FileManager.default
        guard let entries = files.enumerator(atPath: package.path) else {
            throw ArchiveError.invalidPackage
        }
        var parts: [String: Data] = [:]
        for case let path as String in entries {
            try Task.checkCancellation()
            try validate(path)
            let url = package.appendingPathComponent(path)
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isSymbolicLink != true else { throw ArchiveError.invalidPackage }
            guard attributes.isRegularFile == true else { continue }
            parts[path] = try Data(contentsOf: url)
        }
        return parts
    }

    public static func pack(_ parts: [String: Data]) async throws -> Data {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("Scholium-Word-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        let destination = root.appendingPathComponent("document.docx")
        try files.createDirectory(at: package, withIntermediateDirectories: true)
        for (path, data) in parts {
            try Task.checkCancellation()
            try validate(path)
            let url = package.appendingPathComponent(path)
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try await run("/usr/bin/zip", arguments: ["-q", "-r", destination.path, "."], directory: package)
        return try Data(contentsOf: destination)
    }

    private enum ArchiveError: Error { case invalidPackage, commandFailed }

    private static func validate(_ path: String) throws {
        guard !path.hasPrefix("/"), path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ArchiveError.invalidPackage
        }
    }

    private static func run(_ executable: String, arguments: [String], directory: URL) async throws {
        let result = try await Subprocess.run(
            .path(.init(executable)), arguments: .init(arguments), workingDirectory: .init(directory.path), output: .discarded, error: .discarded)
        guard result.terminationStatus.isSuccess else { throw ArchiveError.commandFailed }
        try Task.checkCancellation()
    }
}
