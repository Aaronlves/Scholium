import CryptoKit
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Source-authorized move planning")
struct WorkspaceMoveSourceProjectionTests {
    @Test("Rename discovers incoming links omitted by a matching persistent Catalog record")
    func renameRebuildsCompleteIncomingLinksFromSource() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/move-source-projection/\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        for directory in [analyses, topics, works, support] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let incomingPath = "Incoming.md"
        let incomingURL = analyses.appendingPathComponent(incomingPath)
        let sourceURL = topics.appendingPathComponent("B.md")
        let destinationURL = topics.appendingPathComponent("C.md")
        let untouchedURL = works.appendingPathComponent("Unchanged.md")
        let incomingBytes = Data(
            "\u{FEFF}---\r\nsummary: 'retain e\u{301}'\r\nunknown: [one, two]\r\n---\r\n# Incoming\r\n\r\nAuthored [[B|目标 😀]] without final newline".utf8)
        let rewrittenBytes = Data(
            "\u{FEFF}---\r\nsummary: 'retain e\u{301}'\r\nunknown: [one, two]\r\n---\r\n# Incoming\r\n\r\nAuthored [[C|目标 😀]] without final newline".utf8)
        let targetBytes = Data("\u{FEFF}# B\r\n\r\nExact target e\u{301} 中文 😀 without final newline".utf8)
        let untouchedBytes = Data("# Unchanged\n\nUnrelated source.\n".utf8)
        try incomingBytes.write(to: incomingURL)
        try targetBytes.write(to: sourceURL)
        try untouchedBytes.write(to: untouchedURL)

        let bootstrap = WorkspaceRuntime(
            configuration: .live(
                .init(applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("Registry"))))
        let assignment: TriptychAssignment
        do {
            let handle = try await bootstrap.configureTriptych(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: root, triptychName: "Move source projection fixture")
            _ = try await handle.refresh()
            assignment = handle.assignment
            await bootstrap.shutdown()
        } catch {
            await bootstrap.shutdown()
            throw error
        }

        let analysisVaultID = try #require(assignment.vault(for: .paperAnalysis)?.id)
        let cacheName =
            SHA256.hash(data: Data(incomingPath.utf8))
            .map { String(format: "%02x", $0) }.joined() + ".catalog.plist"
        let cacheURL = support.appendingPathComponent("Vaults/\(analysisVaultID.uuidString)/source-projections-v1/\(cacheName)")
        try omitLinksFromCatalogRecord(at: cacheURL)
        #expect(try Data(contentsOf: incomingURL) == incomingBytes)
        #expect(try Data(contentsOf: sourceURL) == targetBytes)

        let runtime = WorkspaceRuntime(
            configuration: .snapshot(.init(applicationSupportURL: support, assignments: [assignment])))
        do {
            let handle = try await runtime.openWorkspace(id: assignment.id)
            let snapshot = try await handle.snapshot()
            let services = await handle.services
            let catalog = try #require(services.sourceCatalogs[analysisVaultID])
            let restored = try await catalog.snapshot()
            let incomingProjection = try #require(restored.projections.first { $0.relativePath == incomingPath })
            // Prove the cold reader accepted the checksum-valid omission. A
            // rename must establish completeness independently of that cache.
            #expect(incomingProjection.authoredLinks.isEmpty)
            let source = try #require(snapshot.vaults.flatMap(\.documents).first { $0.id.relativePath == "B.md" })
            let stableID = try #require(source.stableIdentity.resolvedID)
            let moved = try await handle.documents.move(
                .init(documentID: source.id, stableNoteID: stableID, revision: source.fingerprint),
                to: "C.md")
            #expect(moved.committedValue.rewrites.contains { $0.note.vaultID == analysisVaultID && $0.note.relativePath == incomingPath })
            #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
            #expect(try Data(contentsOf: destinationURL) == targetBytes)
            #expect(try Data(contentsOf: incomingURL) == rewrittenBytes)
            #expect(try Data(contentsOf: untouchedURL) == untouchedBytes)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    private func omitLinksFromCatalogRecord(at url: URL) throws {
        var frame = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        let encoded = try #require(frame["payload"] as? Data)
        try #require(encoded.count >= 21 && encoded.prefix(4) == Data("SPB1".utf8))
        let material: Data
        if encoded[4] == 0 {
            material = Data(encoded.dropFirst(21))
        } else {
            try #require(encoded[4] == 1)
            material = try (Data(encoded.dropFirst(21)) as NSData).decompressed(using: .lzfse) as Data
        }
        var projection = try #require(
            PropertyListSerialization.propertyList(from: material, format: nil) as? [String: Any])
        let links = try #require(projection["authoredLinks"] as? [Any])
        #expect(!links.isEmpty)
        projection["authoredLinks"] = [Any]()
        let omitted = try PropertyListSerialization.data(fromPropertyList: projection, format: .binary, options: 0)
        // Emit the codec's raw envelope so only the persisted semantic content
        // changes; the frame remains bounded, decodable and checksum-valid.
        var payload = Data("SPB1".utf8)
        payload.append(0)
        var length = UInt64(omitted.count).littleEndian
        withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
        payload.append(omitted)
        frame["payload"] = payload
        frame["payloadDigest"] = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0).write(to: url, options: .atomic)
    }
}
