import Darwin
import Foundation
import ScholiumNativeFileOperations
import Testing

@Suite("Native system-Trash object references")
struct NativeSystemTrashReferenceTests {
    @Test("The native file reference cannot redirect Trash to a replacement at the requested path", arguments: [false, true])
    func referenceRetainsOriginalObject(folder: Bool) async throws {
        try await Task.detached {
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("source-\(UUID().uuidString)" + (folder ? "" : ".md"), isDirectory: folder)
            let displaced = root.appendingPathComponent("displaced-\(UUID().uuidString)" + (folder ? "" : ".md"), isDirectory: folder)
            if folder { try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false) }
            let originalFile = folder ? source.appendingPathComponent("Original.md") : source
            let exactBytes = Data("exact original bytes\n".utf8)
            try exactBytes.write(to: originalFile)
            let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | (folder ? O_DIRECTORY : 0))
            #expect(descriptor >= 0)
            defer { close(descriptor) }
            var status = stat()
            #expect(fstat(descriptor, &status) == 0)
            var mutationFailure: Error?
            var destination: NSURL?
            var nativeError: NSError?
            let moved = ScholiumRecycleItem(
                source.path, UInt64(bitPattern: Int64(status.st_dev)), status.st_ino,
                {
                    do {
                        try FileManager.default.moveItem(at: source, to: displaced)
                        if folder { try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false) }
                        let replacement = folder ? source.appendingPathComponent("Replacement.md") : source
                        try Data("foreign replacement bytes\n".utf8).write(to: replacement)
                        return true
                    } catch {
                        mutationFailure = error
                        return false
                    }
                }, &destination, &nativeError)
            if let mutationFailure { throw mutationFailure }
            let trashed = try #require(destination as URL?)
            defer { try? FileManager.default.removeItem(at: trashed) }
            #expect(moved)
            #expect(nativeError == nil)
            #expect(!FileManager.default.fileExists(atPath: displaced.path))
            #expect(try Data(contentsOf: folder ? trashed.appendingPathComponent("Original.md") : trashed) == exactBytes)
            #expect(try Data(contentsOf: folder ? source.appendingPathComponent("Replacement.md") : source) == Data("foreign replacement bytes\n".utf8))
        }.value
    }

    @Test("A mismatched native identity never dispatches Finder Trash")
    func wrongReferenceRefusesDispatch() async throws {
        try await Task.detached {
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("Source.md")
            let bytes = Data("source stays\n".utf8)
            try bytes.write(to: source)
            var status = stat()
            #expect(lstat(source.path, &status) == 0)
            var wasInvoked = false
            var destination: NSURL?
            var error: NSError?
            let moved = ScholiumRecycleItem(
                source.path, UInt64(bitPattern: Int64(status.st_dev)), status.st_ino + 1,
                {
                    wasInvoked = true
                    return true
                }, &destination, &error)
            #expect(!moved)
            #expect(!wasInvoked)
            #expect(destination == nil)
            #expect(error != nil)
            #expect(try Data(contentsOf: source) == bytes)
        }.value
    }
}

private func makeRoot() throws -> URL {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = repository.appendingPathComponent(".build/file-operations-fixtures/\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
