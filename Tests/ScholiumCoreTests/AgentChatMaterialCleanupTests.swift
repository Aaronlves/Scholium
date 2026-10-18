import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Unused managed Chat-material cleanup")
struct AgentChatMaterialCleanupTests {
    @Test("Inventory protects shared references, links, future names, directories and oversized files")
    func inventoryOwnership() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = UUID()
        for suffix in ["pdf", "page-1.png", "tiff", "png"] { try fixture.write(retained.uuidString + "." + suffix) }
        let orphan = UUID().uuidString + ".md"
        try fixture.write(orphan, "orphan snapshot")
        let unsupportedCopy = UUID().uuidString + ".docx"
        try fixture.write(unsupportedCopy)
        try fixture.write(UUID().uuidString + ".future-format")
        try fixture.write(UUID().uuidString + ".page-01.png")
        try fixture.write("unknown.md")
        let outside = fixture.root.appendingPathComponent("outside.md")
        try Data("research sentinel".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: fixture.materials.appendingPathComponent(UUID().uuidString + ".md"), withDestinationURL: outside)
        try FileManager.default.linkItem(at: outside, to: fixture.materials.appendingPathComponent(UUID().uuidString + ".pdf"))
        try FileManager.default.createDirectory(at: fixture.materials.appendingPathComponent(UUID().uuidString + ".png"), withIntermediateDirectories: false)
        let oversized = fixture.materials.appendingPathComponent(UUID().uuidString + ".data")
        try Data().write(to: oversized)
        let file = try FileHandle(forWritingTo: oversized)
        try file.truncate(atOffset: 21 * 1_024 * 1_024)
        try file.close()
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [retained], expectedHistoryFingerprint: nil)
        #expect(plan.candidateFileNames == [orphan, unsupportedCopy].sorted())
        #expect(plan.byteCount == Int64("orphan snapshot".utf8.count + "snapshot".utf8.count))
        #expect(plan.preservedFiles == 11)
        #expect(try Data(contentsOf: outside) == Data("research sentinel".utf8))
    }

    @Test("Verified transfers retain exact bytes at recoverable destinations and can be restored")
    func recoverableTransfer() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let id = UUID()
        let payloads = [id.uuidString + ".pdf": "PDF snapshot", id.uuidString + ".page-1.png": "rendered page", UUID().uuidString + ".data": "captured copy"]
        for (name, bytes) in payloads { try fixture.write(name, bytes) }
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        let result = try AgentChatMaterialCleanup.cleanup(plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil, recycle: fixture.recycle)
        #expect(result.movedFiles == 3 && result.failedFiles == 0 && result.uncertainFiles == 0)
        #expect(result.movedBytes == plan.byteCount)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.materials.path).isEmpty)
        #expect(result.resultingTrashURLs.count == 3)
        for (url, original) in zip(result.resultingTrashURLs, plan.candidateFileNames) {
            #expect(try Data(contentsOf: url) == Data(try #require(payloads[original]).utf8))
            try FileManager.default.moveItem(at: url, to: fixture.materials.appendingPathComponent(original))
        }
        #expect(try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil).fileCount == 3)
    }

    @Test("A stale cohort or newly acquired reference rejects the whole operation before any move", arguments: [false, true])
    func staleCohort(newReference: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = UUID()
        let second = UUID()
        try fixture.write(first.uuidString + ".txt")
        try fixture.write(second.uuidString + ".pdf")
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        if !newReference { try fixture.write(second.uuidString + ".pdf", "concurrent revision") }
        var calls = 0
        #expect(throws: AgentChatMaterialCleanupError.changed) {
            try AgentChatMaterialCleanup.cleanup(
                plan, referencedMaterialIDs: newReference ? [first] : [], expectedHistoryFingerprint: nil,
                recycle: { _, _, _, _ in
                    calls += 1
                    throw CocoaError(.fileWriteUnknown)
                })
        }
        #expect(calls == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.materials.path).count == 2)
    }

    @Test("Internal Chat and Materials symlinks cannot authorize traversal or cleanup", arguments: [false, true])
    func ancestorSubstitution(chatAncestor: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(UUID().uuidString + ".md")
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        let target = chatAncestor ? fixture.materials.deletingLastPathComponent().deletingLastPathComponent() : fixture.materials
        let parked = target.deletingLastPathComponent().appendingPathComponent("parked-" + target.lastPathComponent)
        try FileManager.default.moveItem(at: target, to: parked)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: parked)
        #expect(throws: (any Error).self) {
            try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        }
        var called = false
        #expect(throws: (any Error).self) {
            try AgentChatMaterialCleanup.cleanup(
                plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil,
                recycle: { _, _, _, _ in
                    called = true
                    throw CocoaError(.fileWriteUnknown)
                })
        }
        #expect(!called)
    }

    @Test("Identical-byte source substitution between preview and isolation is preserved")
    func exactByteSubstitution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let name = UUID().uuidString + ".md"
        try fixture.write(name, "original bytes")
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        var calls = 0
        let result = try AgentChatMaterialCleanup.cleanup(
            plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil,
            recycle: { _, _, _, _ in
                calls += 1
                throw CocoaError(.fileWriteUnknown)
            },
            checkpoint: { point in
                if case .beforeIsolation = point {
                    try FileManager.default.moveItem(
                        at: fixture.materials.appendingPathComponent(name), to: fixture.root.appendingPathComponent("retained-original.md"))
                    try fixture.write(name, "original bytes")
                }
            })
        #expect(calls == 0 && result.movedFiles == 0 && result.failedFiles == 1)
        #expect(try Data(contentsOf: fixture.materials.appendingPathComponent(name)) == Data("original bytes".utf8))
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent("retained-original.md")) == Data("original bytes".utf8))
    }

    @Test("A concurrent write after isolation cancels transfer and preserves the changed file")
    func concurrentWrite() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let name = UUID().uuidString + ".txt"
        try fixture.write(name)
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        let result = try AgentChatMaterialCleanup.cleanup(
            plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil, recycle: fixture.recycle,
            checkpoint: { point in
                if case .afterIsolation(let isolated) = point { try fixture.write(isolated, "concurrent writing") }
            })
        #expect(result.movedFiles == 0 && result.failedFiles == 1 && result.uncertainFiles == 0)
        let retained = try #require(result.retainedFileNames.first)
        #expect(retained.hasPrefix(".chat-material-cleanup-"))
        #expect(try Data(contentsOf: fixture.materials.appendingPathComponent(retained)) == Data("concurrent writing".utf8))
        #expect(!FileManager.default.fileExists(atPath: fixture.materials.appendingPathComponent(name).path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.trash.path).isEmpty)
    }

    @Test("Partial failure restores its source and reports only verified transferred bytes")
    func partialFailure() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let names = ["00000000-0000-0000-0000-000000000001.txt", "00000000-0000-0000-0000-000000000002.pdf"]
        for name in names { try fixture.write(name) }
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        var calls = 0
        let result = try AgentChatMaterialCleanup.cleanup(
            plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil,
            recycle: { url, device, inode, validate in
                calls += 1
                if calls == 2 {
                    try validate()
                    throw CocoaError(.fileWriteNoPermission)
                }
                return try fixture.recycle(url, device, inode, validate)
            })
        #expect(result.movedFiles == 1 && result.failedFiles == 1 && result.uncertainFiles == 0)
        #expect(result.movedBytes == Int64("snapshot".utf8.count))
        #expect(result.retainedFileNames == [names[1]])
        #expect(try Data(contentsOf: fixture.materials.appendingPathComponent(names[1])) == Data("snapshot".utf8))
        #expect(result.resultingTrashURLs.count == 1)
    }

    @Test("A transferred source with a missing receipt is uncertain and is never retried")
    func uncertainTransfer() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(UUID().uuidString + ".png")
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        var calls = 0
        let result = try AgentChatMaterialCleanup.cleanup(
            plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil,
            recycle: { url, device, inode, validate in
                calls += 1
                _ = try fixture.recycle(url, device, inode, validate)
                throw CocoaError(.fileWriteUnknown)
            })
        #expect(calls == 1 && result.movedFiles == 0 && result.failedFiles == 0 && result.uncertainFiles == 1)
        #expect(result.uncertainFileNames == plan.candidateFileNames && result.rootURL == fixture.materials)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.trash.path).count == 1)
    }

    @Test("Identical-byte replacement of a Trash receipt cannot be reported as a verified move")
    func trashReceiptSubstitution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(UUID().uuidString + ".png")
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        let result = try AgentChatMaterialCleanup.cleanup(
            plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil, recycle: fixture.recycle,
            checkpoint: { point in
                if case .afterTrashReadback = point {
                    let url = try #require(FileManager.default.contentsOfDirectory(at: fixture.trash, includingPropertiesForKeys: nil).first)
                    try FileManager.default.moveItem(at: url, to: fixture.root.appendingPathComponent("original-recoverable-copy"))
                    try Data("snapshot".utf8).write(to: url)
                }
            })
        #expect(result.movedFiles == 0 && result.uncertainFiles == 1)
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent("original-recoverable-copy")) == Data("snapshot".utf8))
    }

    @Test("Failed rollback leaves a recognized recoverable copy and preserves a new original-name file")
    func rollbackCollision() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let id = UUID()
        let name = id.uuidString + ".txt"
        try fixture.write(name)
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        let result = try AgentChatMaterialCleanup.cleanup(
            plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil,
            recycle: { _, _, _, validate in
                try validate()
                try fixture.write(name, "new concurrent copy")
                throw CocoaError(.fileWriteNoPermission)
            })
        #expect(result.movedFiles == 0 && result.failedFiles == 1 && result.retainedFileNames.count == 1)
        let retained = try #require(result.retainedFileNames.first)
        #expect(retained.hasPrefix(".chat-material-cleanup-"))
        #expect(try Data(contentsOf: fixture.materials.appendingPathComponent(retained)) == Data("snapshot".utf8))
        #expect(try Data(contentsOf: fixture.materials.appendingPathComponent(name)) == Data("new concurrent copy".utf8))
        #expect(try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil).fileCount == 2)
        #expect(try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [id], expectedHistoryFingerprint: nil).fileCount == 0)
    }

    @Test("A substituted isolated symlink is never restored over the original source identity")
    func isolatedLeafSubstitution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let name = UUID().uuidString + ".txt"
        try fixture.write(name)
        let outside = fixture.root.appendingPathComponent("outside-source.md")
        try Data("outside sentinel".utf8).write(to: outside)
        let parked = fixture.root.appendingPathComponent("parked-original-copy")
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        let result = try AgentChatMaterialCleanup.cleanup(
            plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil, recycle: fixture.recycle,
            checkpoint: { point in
                if case .afterIsolation(let isolated) = point {
                    let isolatedURL = fixture.materials.appendingPathComponent(isolated)
                    try FileManager.default.moveItem(at: isolatedURL, to: parked)
                    try FileManager.default.createSymbolicLink(at: isolatedURL, withDestinationURL: outside)
                }
            })
        #expect(result.movedFiles == 0 && result.failedFiles == 1 && result.uncertainFiles == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.materials.appendingPathComponent(name).path))
        let retained = try #require(result.retainedFileNames.first)
        #expect(try fixture.materials.appendingPathComponent(retained).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try Data(contentsOf: outside) == Data("outside sentinel".utf8))
        #expect(try Data(contentsOf: parked) == Data("snapshot".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.trash.path).isEmpty)
    }

    @Test("The controller's decoded history fingerprint must match the exact sibling history")
    func historyFingerprintAdmission() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(UUID().uuidString + ".txt")
        let history = fixture.materials.deletingLastPathComponent().appendingPathComponent("conversations.json")
        let decoded = Data("decoded history".utf8)
        let changed = Data("external history with a retained reference".utf8)
        try changed.write(to: history)
        #expect(throws: AgentChatMaterialCleanupError.changed) {
            try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: .init(data: decoded))
        }
        #expect(throws: AgentChatMaterialCleanupError.changed) {
            try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        }
        #expect(
            try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: .init(data: changed))
                .fileCount == 1)
    }

    @Test("Concurrent history changes at the final reference check preserve this and all remaining copies", arguments: [false, true])
    func historyWriteDuringCleanup(existingHistory: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for name in ["00000000-0000-0000-0000-000000000001.txt", "00000000-0000-0000-0000-000000000002.pdf"] { try fixture.write(name) }
        let history = fixture.materials.deletingLastPathComponent().appendingPathComponent("conversations.json")
        let bytes = Data("decoded history".utf8)
        if existingHistory { try bytes.write(to: history) }
        let fingerprint: DocumentFingerprint? = existingHistory ? .init(data: bytes) : nil
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: fingerprint)
        var calls = 0
        let result = try AgentChatMaterialCleanup.cleanup(
            plan, referencedMaterialIDs: [], expectedHistoryFingerprint: fingerprint,
            recycle: { _, _, _, validate in
                calls += 1
                try Data("external history reintroduces a reference".utf8).write(to: history, options: .atomic)
                try validate()
                throw CocoaError(.fileWriteUnknown)
            })
        #expect(calls == 1 && result.movedFiles == 0 && result.failedFiles == 1 && result.preservedFiles == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.materials.path).count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.trash.path).isEmpty)
    }

    @Test("A history write after transfer makes that outcome uncertain and stops the remaining cohort")
    func historyWriteAfterTransfer() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for name in ["00000000-0000-0000-0000-000000000001.txt", "00000000-0000-0000-0000-000000000002.pdf"] { try fixture.write(name) }
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        let result = try AgentChatMaterialCleanup.cleanup(
            plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil, recycle: fixture.recycle,
            checkpoint: { point in
                if case .afterTrashReadback = point {
                    try Data("new history".utf8).write(to: fixture.materials.deletingLastPathComponent().appendingPathComponent("conversations.json"))
                }
            })
        #expect(result.movedFiles == 0 && result.uncertainFiles == 1 && result.preservedFiles == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.materials.path).count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.trash.path).count == 1)
    }

    @Test("Missing material folders stay absent and linked sibling history is refused")
    func absentRootAndHistoryLink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.materials)
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        #expect(plan.fileCount == 0)
        #expect(
            try AgentChatMaterialCleanup.cleanup(plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil, recycle: fixture.recycle).movedFiles == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.materials.path))
        let outside = fixture.root.appendingPathComponent("outside-history.json")
        try Data("preserved history".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.materials.deletingLastPathComponent().appendingPathComponent("conversations.json"), withDestinationURL: outside)
        #expect(throws: (any Error).self) {
            try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        }
        #expect(try Data(contentsOf: outside) == Data("preserved history".utf8))
    }

    @Test("Cancellation after a verified transfer returns its evidence and preserves the remaining files")
    func cancellationAfterTransfer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for name in ["00000000-0000-0000-0000-000000000001.txt", "00000000-0000-0000-0000-000000000002.pdf"] { try fixture.write(name) }
        let plan = try AgentChatMaterialCleanup.inspect(rootURL: fixture.materials, referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        let operation = Task {
            try AgentChatMaterialCleanup.cleanup(
                plan, referencedMaterialIDs: [], expectedHistoryFingerprint: nil, recycle: fixture.recycle,
                checkpoint: { point in
                    if case .afterTrashReadback = point { withUnsafeCurrentTask { $0?.cancel() } }
                })
        }
        let result = try await operation.value
        #expect(result.wasCancelled && result.movedFiles == 1 && result.preservedFiles == 1)
        #expect(result.movedBytes == Int64("snapshot".utf8.count))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.materials.path).count == 1)
    }

    private struct Fixture {
        let root: URL
        let materials: URL
        let trash: URL
        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/chat-material-cleanup-tests/\(UUID().uuidString)", isDirectory: true)
            materials = root.appendingPathComponent("State-v1/Chat/\(UUID().uuidString)/Materials", isDirectory: true)
            trash = root.appendingPathComponent("RecoverableTrash", isDirectory: true)
            try FileManager.default.createDirectory(at: materials, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        }
        func write(_ name: String, _ text: String = "snapshot") throws { try Data(text.utf8).write(to: materials.appendingPathComponent(name)) }
        func recycle(_ source: URL, _: UInt64, _: UInt64, _ validate: () throws -> Void) throws -> URL {
            try validate()
            let destination = trash.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
