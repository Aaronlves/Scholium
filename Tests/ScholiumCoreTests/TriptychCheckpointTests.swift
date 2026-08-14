import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Self-contained Triptych checkpoints")
struct TriptychCheckpointTests {
    @Test("A checkpoint remains complete after source files change")
    func selfContainedCheckpoint() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )

        let checkpoint = try await store.create(
            name: "Before Agent Work",
            kind: .automatic,
            roots: fixture.roots
        )
        try Data("Changed".utf8).write(to: fixture.analysis)

        let snapshot = await store.checkpointURL(id: checkpoint.id)
            .appendingPathComponent("snapshot/Analyses/Paper.md")
        #expect(try String(contentsOf: snapshot, encoding: .utf8) == "# Analysis\n")
        #expect(checkpoint.files.count == 4)
        #expect(!checkpoint.triptychFingerprint.isEmpty)
    }

    @Test("Unreadable checkpoint metadata is reported instead of appearing absent")
    func corruptListingIsVisible() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        let valid = try await store.create(name: "Valid", kind: .manual, roots: fixture.roots)
        let corruptDirectory = store.storageURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        try Data("{not checkpoint metadata".utf8).write(
            to: corruptDirectory.appendingPathComponent("metadata.json")
        )

        let listing = await store.listing()

        #expect(listing.checkpoints.map(\.id) == [valid.id])
        #expect(listing.unreadableEntries.count == 1)
        #expect(listing.unreadableEntries[0].contains(corruptDirectory.lastPathComponent))
    }

    @Test("Only automatic checkpoints are capped at ten")
    func retention() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        _ = try await store.create(name: "Manual", kind: .manual, roots: fixture.roots)
        for index in 0..<11 {
            try Data("# Analysis \(index)\n".utf8).write(to: fixture.analysis)
            _ = try await store.create(name: "Automatic \(index)", kind: .automatic, roots: fixture.roots)
        }

        let checkpoints = await store.checkpoints()
        #expect(checkpoints.filter { $0.kind == .automatic }.count == 10)
        #expect(checkpoints.filter { $0.kind == .manual }.map(\.name) == ["Manual"])
    }

    @Test("Continuation recovery checkpoints are exact-note and never enter automatic retention")
    func continuationRecoveryRetention() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        for index in 0..<10 {
            try Data("# Analysis \(index)\n".utf8).write(to: fixture.analysis)
            _ = try await store.create(
                name: "Automatic \(index)",
                kind: .automatic,
                roots: fixture.roots
            )
        }

        let key = TriptychCheckpointFileKey(
            area: .analyses,
            relativePath: "Paper.md"
        )
        await #expect(throws: TriptychCheckpointError.self) {
            _ = try await store.create(
                name: "Invalid generic continuation",
                kind: .researchContinuation,
                roots: fixture.roots
            )
        }
        let fingerprint = DocumentFingerprint(
            data: try Data(contentsOf: fixture.analysis)
        )
        var continuationIDs: Set<UUID> = []
        for index in 0..<12 {
            let checkpoint = try await store.createResearchContinuation(
                name: "Continuation \(index)",
                key: key,
                expectedFingerprint: fingerprint,
                roots: fixture.roots
            )
            continuationIDs.insert(checkpoint.id)
            #expect(checkpoint.kind == .researchContinuation)
            #expect(checkpoint.files == [TriptychCheckpointFile(
                key: key,
                fingerprint: fingerprint
            )])
        }

        _ = try await store.create(
            name: "Automatic 10",
            kind: .automatic,
            roots: fixture.roots
        )
        let checkpoints = await store.checkpoints()
        #expect(checkpoints.filter { $0.kind == .automatic }.count == 10)
        #expect(Set(checkpoints.filter {
            $0.kind == .researchContinuation
        }.map(\.id)) == continuationIDs)

        let continuationID = try #require(continuationIDs.first)
        await #expect(throws: TriptychCheckpointError.self) {
            _ = try await store.restore(
                checkpointID: continuationID,
                selection: .completeTriptych,
                roots: fixture.roots,
                repositories: fixture.repositories()
            )
        }
        let sibling = TriptychCheckpointFileKey(
            area: .analyses,
            relativePath: "Sibling.md"
        )
        await #expect(throws: TriptychCheckpointError.self) {
            _ = try await store.restore(
                checkpointID: continuationID,
                selection: .mappedFiles([TriptychCheckpointFileRestore(
                    source: key,
                    destination: sibling
                )]),
                roots: fixture.roots,
                repositories: fixture.repositories()
            )
        }
        await #expect(throws: TriptychCheckpointError.self) {
            _ = try await store.restoreNoteFile(
                checkpointID: continuationID,
                sourceKey: key,
                destinationKey: sibling,
                roots: fixture.roots,
                repositories: fixture.repositories()
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: fixture.analyses.appendingPathComponent("Sibling.md").path
        ))
    }

    @Test("Preparation rollback discards exactly one verified automatic checkpoint")
    func discardsOnlyAutomaticCheckpoint() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        let manual = try await store.create(name: "Researcher Baseline", kind: .manual, roots: fixture.roots)
        let automatic = try await store.create(name: "Before Agent Work", kind: .automatic, roots: fixture.roots)

        let discarded = try await store.discardAutomaticCheckpoint(id: automatic.id)
        #expect(discarded.id == automatic.id)
        #expect(discarded.kind == .automatic)
        #expect(discarded.triptychFingerprint == automatic.triptychFingerprint)
        #expect(!FileManager.default.fileExists(atPath: await store.checkpointURL(id: automatic.id).path))
        #expect((await store.checkpoints()).map(\.id) == [manual.id])
        await #expect(throws: TriptychCheckpointError.self) {
            _ = try await store.discardAutomaticCheckpoint(id: manual.id)
        }
        #expect(FileManager.default.fileExists(atPath: await store.checkpointURL(id: manual.id).path))
    }

    @Test("Restoring the oldest automatic checkpoint defers retention until restore completes")
    func restoresOldestRetainedAutomaticCheckpoint() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )

        for index in 0..<10 {
            try Data("# Analysis \(index)\n".utf8).write(to: fixture.analysis)
            _ = try await store.create(
                name: "Automatic \(index)",
                kind: .automatic,
                roots: fixture.roots
            )
        }

        let automaticBeforeRestore = await store.checkpoints().filter { $0.kind == .automatic }
        #expect(automaticBeforeRestore.count == 10)
        let oldest = try #require(automaticBeforeRestore.last)
        let analysisKey = TriptychCheckpointFileKey(area: .analyses, relativePath: "Paper.md")
        let expectedData = try await store.fileData(checkpointID: oldest.id, key: analysisKey)
        let changedData = Data("# Changed after checkpoint\n".utf8)
        try changedData.write(to: fixture.analysis)

        let result = try await store.restore(
            checkpointID: oldest.id,
            selection: .files([analysisKey]),
            roots: fixture.roots,
            repositories: fixture.repositories()
        )

        #expect(try Data(contentsOf: fixture.analysis) == expectedData)
        #expect(result.restoredFiles == [analysisKey])
        #expect(try await store.fileData(
            checkpointID: result.recoveryCheckpoint.id,
            key: analysisKey
        ) == changedData)

        let automaticAfterRestore = await store.checkpoints().filter { $0.kind == .automatic }
        #expect(automaticAfterRestore.count == 10)
        #expect(automaticAfterRestore.contains { $0.id == result.recoveryCheckpoint.id })
        #expect(!automaticAfterRestore.contains { $0.id == oldest.id })
    }

    @Test("Comparison distinguishes created, changed, moved, and deleted files")
    func comparison() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        let checkpoint = try await store.create(name: "Baseline", kind: .manual, roots: fixture.roots)

        try Data("# Revised Analysis\n".utf8).write(to: fixture.analysis)
        let movedTopic = fixture.topics.appendingPathComponent("Moved/Topic.md")
        try FileManager.default.createDirectory(at: movedTopic.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: fixture.topic, to: movedTopic)
        try FileManager.default.removeItem(at: fixture.work)
        try Data("# New\n".utf8).write(to: fixture.works.appendingPathComponent("New.md"))

        let changes = try await store.comparison(checkpointID: checkpoint.id, roots: fixture.roots)
        #expect(changes.contains { $0.kind == .changed && $0.area == .analyses && $0.currentPath == "Paper.md" })
        #expect(changes.contains {
            $0.kind == .moved && $0.area == .topics &&
            $0.checkpointPath == "Topic.md" && $0.currentPath == "Moved/Topic.md"
        })
        #expect(changes.contains { $0.kind == .deleted && $0.area == .works && $0.checkpointPath == "Draft.md" })
        #expect(changes.contains { $0.kind == .created && $0.area == .works && $0.currentPath == "New.md" })
    }

    @Test("Selective restore writes a moved note at its current path")
    func selectiveRestoreUsesCurrentPath() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        let checkpoint = try await store.create(name: "Before Move", kind: .manual, roots: fixture.roots)
        let current = fixture.topics.appendingPathComponent("Moved/Topic.md")
        try FileManager.default.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: fixture.topic, to: current)
        try Data("# Changed after move\n".utf8).write(to: current)
        let source = TriptychCheckpointFileKey(area: .topics, relativePath: "Topic.md")
        let destination = TriptychCheckpointFileKey(area: .topics, relativePath: "Moved/Topic.md")

        let result = try await store.restore(
            checkpointID: checkpoint.id,
            selection: .mappedFiles([TriptychCheckpointFileRestore(source: source, destination: destination)]),
            roots: fixture.roots,
            repositories: fixture.repositories()
        )

        #expect(try String(contentsOf: current, encoding: .utf8) == "# Topic\n")
        #expect(!FileManager.default.fileExists(atPath: fixture.topic.path))
        #expect(result.restoredFiles == [destination])
    }

    @Test("Complete restore recovers checkpoint files and moves later files to Trash")
    func completeRestore() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        let checkpoint = try await store.create(name: "Baseline", kind: .manual, roots: fixture.roots)
        try Data("# Revised Analysis\n".utf8).write(to: fixture.analysis)
        try FileManager.default.removeItem(at: fixture.work)
        let newWork = fixture.works.appendingPathComponent("New.md")
        try Data("# New\n".utf8).write(to: newWork)

        let repositories = try fixture.repositories()
        let result = try await store.restore(
            checkpointID: checkpoint.id,
            selection: .completeTriptych,
            roots: fixture.roots,
            repositories: repositories
        )

        #expect(try String(contentsOf: fixture.analysis, encoding: .utf8) == "# Analysis\n")
        #expect(try String(contentsOf: fixture.work, encoding: .utf8) == "# Work\n")
        #expect(!FileManager.default.fileExists(atPath: newWork.path))
        #expect(FileManager.default.fileExists(
            atPath: fixture.works.appendingPathComponent("Trash/After Baseline/New.md").path
        ))
        #expect(result.recoveryCheckpoint.name == "Before Restore")
        #expect(result.movedToTrash.contains(TriptychCheckpointFileKey(area: .works, relativePath: "New.md")))
    }

    @Test("A checkpoint refuses symbolic links instead of following them")
    func symbolicLinkRejection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("Outside.md")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.analyses.appendingPathComponent("Link.md"),
            withDestinationURL: outside
        )
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )

        await #expect(throws: TriptychCheckpointError.self) {
            try await store.create(name: "Unsafe", kind: .manual, roots: fixture.roots)
        }
        #expect((await store.checkpoints()).isEmpty)
    }

    @Test("Portable restore refuses a parent swapped for an external symbolic link")
    func portableRestoreRejectsParentSymlinkSwap() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let configuration = fixture.control.appendingPathComponent("configuration", isDirectory: true)
        try FileManager.default.createDirectory(at: configuration, withIntermediateDirectories: true)
        let state = configuration.appendingPathComponent("state.json")
        let checkpointData = Data("{\"state\":\"checkpoint\"}\n".utf8)
        try checkpointData.write(to: state)
        let key = TriptychCheckpointFileKey(area: .control, relativePath: "configuration/state.json")

        let outside = fixture.root.appendingPathComponent("Outside-Control", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideState = outside.appendingPathComponent("state.json")
        let outsideSentinel = Data("outside must remain unchanged\n".utf8)
        try outsideSentinel.write(to: outsideState)
        let displacedConfiguration = fixture.control.appendingPathComponent(
            "configuration-before-swap",
            isDirectory: true
        )
        let interleaving = OneShotInterleaving {
            try FileManager.default.moveItem(at: configuration, to: displacedConfiguration)
            try FileManager.default.createSymbolicLink(at: configuration, withDestinationURL: outside)
        }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support,
            restoreHooks: TriptychCheckpointRestoreHooks { point in
                guard point == .beforePortableWrite(key) else { return }
                try interleaving.perform()
            }
        )
        let checkpoint = try await store.create(name: "Portable Baseline", kind: .manual, roots: fixture.roots)
        let currentData = Data("{\"state\":\"current\"}\n".utf8)
        try currentData.write(to: state, options: .atomic)

        await #expect(throws: TriptychCheckpointError.self) {
            _ = try await store.restore(
                checkpointID: checkpoint.id,
                selection: .files([key]),
                roots: fixture.roots,
                repositories: fixture.repositories()
            )
        }

        #expect(try Data(contentsOf: outsideState) == outsideSentinel)
        #expect(try Data(contentsOf: displacedConfiguration.appendingPathComponent("state.json")) == currentData)
    }

    @Test("Complete restore refuses to move an external file through a swapped parent link")
    func completeRestoreRejectsPortableMoveSymlinkSwap() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let key = TriptychCheckpointFileKey(area: .works, relativePath: "Attachments/new.pdf")
        let outside = fixture.root.appendingPathComponent("Outside-Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appendingPathComponent("new.pdf")
        let outsideSentinel = Data("outside attachment must remain unchanged".utf8)
        try outsideSentinel.write(to: outsideFile)

        let attachments = fixture.works.appendingPathComponent("Attachments", isDirectory: true)
        let displacedAttachments = fixture.works.appendingPathComponent(
            "Attachments-before-swap",
            isDirectory: true
        )
        let interleaving = OneShotInterleaving {
            try FileManager.default.moveItem(at: attachments, to: displacedAttachments)
            try FileManager.default.createSymbolicLink(at: attachments, withDestinationURL: outside)
        }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support,
            restoreHooks: TriptychCheckpointRestoreHooks { point in
                guard point == .beforePortableMove(key) else { return }
                try interleaving.perform()
            }
        )
        let checkpoint = try await store.create(name: "Move Baseline", kind: .manual, roots: fixture.roots)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let currentFile = attachments.appendingPathComponent("new.pdf")
        let currentData = Data("current attachment".utf8)
        try currentData.write(to: currentFile)

        await #expect(throws: TriptychCheckpointError.self) {
            _ = try await store.restore(
                checkpointID: checkpoint.id,
                selection: .completeTriptych,
                roots: fixture.roots,
                repositories: fixture.repositories()
            )
        }

        #expect(try Data(contentsOf: outsideFile) == outsideSentinel)
        #expect(try Data(contentsOf: displacedAttachments.appendingPathComponent("new.pdf")) == currentData)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.works.appendingPathComponent("Trash/After Move Baseline/Attachments/new.pdf").path
        ))
    }

    @Test("Tampered checkpoint bytes are rejected before restore changes the Triptych")
    func tamperedCheckpointFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        let checkpoint = try await store.create(name: "Trusted", kind: .manual, roots: fixture.roots)
        let key = TriptychCheckpointFileKey(area: .analyses, relativePath: "Paper.md")
        let stored = await store.checkpointURL(id: checkpoint.id)
            .appendingPathComponent("snapshot/Analyses/Paper.md")
        try Data("tampered".utf8).write(to: stored, options: .atomic)
        let current = Data("# Current work\n".utf8)
        try current.write(to: fixture.analysis, options: .atomic)

        await #expect(throws: TriptychCheckpointError.self) {
            _ = try await store.fileData(checkpointID: checkpoint.id, key: key)
        }
        await #expect(throws: TriptychCheckpointError.self) {
            _ = try await store.restore(
                checkpointID: checkpoint.id,
                selection: .files([key]),
                roots: fixture.roots,
                repositories: fixture.repositories()
            )
        }

        #expect(try Data(contentsOf: fixture.analysis) == current)
        #expect((await store.checkpoints()).count == 1)
    }

    @Test("Stable identity finds and restores a checkpoint version after a rename")
    func identityBoundRestoreAfterRename() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        let identity = NoteIdentityRecord(
            id: noteID,
            vaultID: UUID(),
            relativePath: "Paper.md",
            fingerprint: DocumentFingerprint(data: try Data(contentsOf: fixture.analysis))
        )
        let identityEncoder = JSONEncoder()
        identityEncoder.dateEncodingStrategy = .iso8601
        let identityData = try identityEncoder.encode(IdentityPayload(records: [identity]))
        try identityData.write(
            to: fixture.control.appendingPathComponent("identities.json"),
            options: .atomic
        )
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        let checkpoint = try await store.create(name: "Before Rename", kind: .manual, roots: fixture.roots)

        let renamed = fixture.analyses.appendingPathComponent("Archive/Paper.md")
        try FileManager.default.createDirectory(
            at: renamed.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: fixture.analysis, to: renamed)
        try Data("# Changed after rename\n".utf8).write(to: renamed, options: .atomic)

        let historical = try #require(try await store.noteFileKey(
            checkpointID: checkpoint.id,
            noteID: noteID,
            area: .analyses
        ))
        #expect(historical.relativePath == "Paper.md")
        let destination = TriptychCheckpointFileKey(
            area: .analyses,
            relativePath: "Archive/Paper.md"
        )
        _ = try await store.restoreNoteFile(
            checkpointID: checkpoint.id,
            sourceKey: historical,
            destinationKey: destination,
            roots: fixture.roots,
            repositories: fixture.repositories()
        )

        #expect(try String(contentsOf: renamed, encoding: .utf8) == "# Analysis\n")
        #expect(!FileManager.default.fileExists(atPath: fixture.analysis.path))
    }

    @Test("Permanent deletion invalidates every checkpoint containing the stable note identity")
    func permanentDeletionPurgesCheckpointCopies() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        let identity = NoteIdentityRecord(
            id: noteID,
            vaultID: UUID(),
            relativePath: "Paper.md",
            fingerprint: DocumentFingerprint(data: try Data(contentsOf: fixture.analysis))
        )
        let identityData = try JSONEncoder().encode(IdentityPayload(records: [identity]))
        try identityData.write(
            to: fixture.control.appendingPathComponent("identities.json"),
            options: .atomic
        )
        let store = TriptychCheckpointStore(
            triptychID: fixture.triptychID,
            applicationSupportURL: fixture.support
        )
        let first = try await store.create(name: "First", kind: .manual, roots: fixture.roots)
        try Data("# Revised\n".utf8).write(to: fixture.analysis, options: .atomic)
        let second = try await store.create(name: "Second", kind: .manual, roots: fixture.roots)

        let prepared = try await store.preparePurgeNoteCopies(
            noteID: noteID,
            area: .analyses,
            currentRelativePath: "Trash/Paper.md",
            additionalKeys: []
        )
        try await store.applyPreparedCheckpointPurge(prepared)
        try await store.finalizePreparedCheckpointPurge(prepared)
        let invalidated = prepared.checkpointIDs

        #expect(Set(invalidated) == Set([first.id, second.id]))
        #expect(await store.checkpoints().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: await store.checkpointURL(id: first.id).path))
        #expect(!FileManager.default.fileExists(atPath: await store.checkpointURL(id: second.id).path))
    }

    private struct IdentityPayload: Encodable {
        let records: [NoteIdentityRecord]
    }

    private final class OneShotInterleaving: @unchecked Sendable {
        private let lock = NSLock()
        private var hasRun = false
        private let action: @Sendable () throws -> Void

        init(action: @escaping @Sendable () throws -> Void) {
            self.action = action
        }

        func perform() throws {
            lock.lock()
            guard !hasRun else {
                lock.unlock()
                return
            }
            hasRun = true
            lock.unlock()
            try action()
        }
    }

    private struct Fixture {
        let root: URL
        let analyses: URL
        let topics: URL
        let works: URL
        let control: URL
        let support: URL
        let analysis: URL
        let topic: URL
        let work: URL
        let triptychID = UUID()

        var roots: TriptychRoots {
            TriptychRoots(analyses: analyses, topics: topics, works: works, control: control)
        }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-Checkpoint-\(UUID().uuidString)", isDirectory: true)
            analyses = root.appendingPathComponent("Analyses", isDirectory: true)
            topics = root.appendingPathComponent("Topics", isDirectory: true)
            works = root.appendingPathComponent("Works", isDirectory: true)
            control = root.appendingPathComponent(".scholium", isDirectory: true)
            support = root.appendingPathComponent("Application Support", isDirectory: true)
            for directory in [analyses, topics, works, control] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            analysis = analyses.appendingPathComponent("Paper.md")
            topic = topics.appendingPathComponent("Topic.md")
            work = works.appendingPathComponent("Draft.md")
            try Data("# Analysis\n".utf8).write(to: analysis)
            try Data("# Topic\n".utf8).write(to: topic)
            try Data("# Work\n".utf8).write(to: work)
            try Data("{\"portable\":true}\n".utf8).write(to: control.appendingPathComponent("manifest.json"))
        }

        func repositories(
            analysisHooks: VaultMutationHooks = .none
        ) throws -> [WorkspaceVaultSlot: VaultRepository] {
            [
                .paperAnalysis: try VaultRepository(
                    vaultURL: analyses,
                    identity: VaultIdentity(id: UUID(), canonicalPath: analyses.path, bookmarkData: nil),
                    applicationSupportURL: support,
                    vaultRole: .sourceCorpus,
                    mutationHooks: analysisHooks
                ),
                .topicKnowledge: try VaultRepository(
                    vaultURL: topics,
                    identity: VaultIdentity(id: UUID(), canonicalPath: topics.path, bookmarkData: nil),
                    applicationSupportURL: support,
                    vaultRole: .topicKnowledge
                ),
                .output: try VaultRepository(
                    vaultURL: works,
                    identity: VaultIdentity(id: UUID(), canonicalPath: works.path, bookmarkData: nil),
                    applicationSupportURL: support,
                    vaultRole: .draftProject
                ),
            ]
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
