import Darwin
import Foundation
import ScholiumContracts

/// Metadata for explicitly owned machine-local namespaces. This reader never
/// opens research payloads, grants source access, or descends into Agent Runtime.
public enum ScholiumStorageInventoryReader {
    public static func scan(applicationSupportURL: URL) throws -> ScholiumStorageInventory {
        let root = applicationSupportURL.resolvingSymlinksInPath().standardizedFileURL
        return try InventoryWalk(root: root).scan()
    }
}

private final class InventoryWalk {
    private struct FileIdentity: Hashable {
        let device: dev_t
        let inode: ino_t
        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
        }
    }

    private struct Usage {
        var byteCount: Int64 = 0
        var fileCount = 0
        var unreadableEntries = 0
        var skippedEntries = 0
    }

    private enum Directory: Equatable {
        case state, triptychs, triptych, vaults, vault, chat, chatTriptych, materials
        case workspace, styles, snippets, windowSessions, zotero, zoteroAccess, attachmentAccess
        case reviews, agentChanges, transactions, transactionRecords, citationPairs, saveTransactions, saveTransaction
        case indexes, sourceProjections, temporary, wordJobs, wordJob, wordPackage, appBridge, registryCoordination

        var category: ScholiumStorageCategory {
            switch self {
            case .indexes: .searchIndexes
            case .sourceProjections: .sourceProjectionCache
            case .chatTriptych: .chatHistory
            case .materials: .chatMaterials
            case .reviews, .agentChanges: .researchHistory
            case .transactions, .transactionRecords, .citationPairs, .saveTransactions, .saveTransaction: .recovery
            case .temporary, .wordJobs, .wordJob, .wordPackage: .temporaryFiles
            case .workspace, .styles, .snippets, .windowSessions, .zotero, .zoteroAccess, .attachmentAccess,
                .appBridge, .registryCoordination:
                .configuration
            default: .unclassified
            }
        }

        func child(_ name: String) -> Directory? {
            switch self {
            case .state:
                switch name {
                case "Triptychs": .triptychs
                case "Vaults": .vaults
                case "Chat": .chat
                case "Workspace": .workspace
                case "Window Sessions": .windowSessions
                case "Zotero": .zotero
                case "AppBridge": .appBridge
                case "Temporary": .temporary
                default: nil
                }
            case .triptychs: UUID(uuidString: name) == nil ? nil : .triptych
            case .vaults: UUID(uuidString: name) == nil ? nil : .vault
            case .chat: UUID(uuidString: name) == nil ? nil : .chatTriptych
            case .triptych:
                switch name {
                case "indexes": .indexes
                case "document-reviews-v1": .reviews
                case "agent-changes-v1": .agentChanges
                case "attachment-access": .attachmentAccess
                case "transactions": .transactions
                default: nil
                }
            case .vault:
                switch name {
                case "source-projections-v1": .sourceProjections
                case "save-transactions-v2": .saveTransactions
                default: nil
                }
            case .chatTriptych: name == "Materials" ? .materials : nil
            case .workspace:
                switch name {
                case "Styles": .styles
                case ".registry-coordination": .registryCoordination
                default: nil
                }
            case .styles: name == "Snippets" ? .snippets : nil
            case .zotero: name == "original-access" ? .zoteroAccess : nil
            case .transactions:
                switch name {
                case "records": .transactionRecords
                case "citation-pairs-v1": .citationPairs
                default: nil
                }
            case .saveTransactions: UUID(uuidString: name) == nil ? nil : .saveTransaction
            case .temporary: name == DerivedStateStorage.wordTemporaryDirectoryName ? .wordJobs : nil
            case .wordJobs: DerivedStateStorage.isRecognizedWordJobName(name) ? .wordJob : nil
            case .wordJob: name == "package" ? .wordPackage : nil
            case .wordPackage: .wordPackage
            default: nil
            }
        }

        func fileCategory(_ name: String) -> ScholiumStorageCategory? {
            switch self {
            case .indexes:
                return name == DerivedStateStorage.lockFileName || DerivedStateStorage.isRecognizedSearchArtifact(name) ? .searchIndexes : nil
            case .sourceProjections:
                return [DerivedStateStorage.lockFileName, ".projection-records.lock"].contains(name)
                    || SourceProjectionCache.isRecognizedRecordFileName(name)
                    || DerivedStateStorage.isRecognizedCacheStaging(name) ? .sourceProjectionCache : nil
            case .chatTriptych: return name == "conversations.json" ? .chatHistory : nil
            case .materials:
                return AgentChatMaterialCleanup.isRecognizedFileName(name) ? .chatMaterials : nil
            case .workspace:
                return ["workspace-registration-v3.json", "saved-searches.json", "search-term-groups.json"].contains(name) ? .configuration : nil
            case .styles:
                return ["snippets.json", "appearances.json", "css-safe-mode.txt"].contains(name) ? .configuration : nil
            case .snippets: return name.hasSuffix(".css") ? .configuration : nil
            case .windowSessions: return Self.uuidJSON(name) ? .configuration : nil
            case .zoteroAccess: return ["original-access-v1.json", "original-access.lock"].contains(name) ? .configuration : nil
            case .attachmentAccess: return ["indexed-attachments-v2.json", "indexed-attachments.lock"].contains(name) ? .configuration : nil
            case .reviews:
                return Self.uuidJSON(name) || ["preferences.json", "document-reviews.lock"].contains(name) ? .researchHistory : nil
            case .agentChanges: return Self.uuidJSON(name) || name == "agent-changes-v1.lock" ? .researchHistory : nil
            case .transactions: return name == "transaction-recovery.lock" ? .recovery : nil
            case .transactionRecords: return Self.uuidJSON(name) ? .recovery : nil
            case .citationPairs:
                return name.hasSuffix(".json") && UUID(uuidString: String(name.prefix(36))) != nil ? .recovery : nil
            case .saveTransactions: return name == ".transactions.lock" ? .recovery : nil
            case .saveTransaction: return ["expected.md", "candidate.md", "displaced.md", "manifest.json"].contains(name) ? .recovery : nil
            case .wordJob: return ["source.docx", "document.docx", DerivedStateStorage.lockFileName].contains(name) ? .temporaryFiles : nil
            case .wordJobs: return name == DerivedStateStorage.lockFileName ? .temporaryFiles : nil
            case .wordPackage: return .temporaryFiles
            case .appBridge: return name == "app-bridge-auth-v1" ? .configuration : nil
            case .registryCoordination: return name == DerivedStateStorage.lockFileName ? .configuration : nil
            default: return nil
            }
        }

        private static func uuidJSON(_ name: String) -> Bool {
            name.hasSuffix(".json") && UUID(uuidString: String(name.dropLast(5))) != nil
        }
    }

    private let root: URL
    private var usages: [String: Usage] = [:]
    private var searchIndexesByTriptych: [UUID: Usage] = [:]
    private var files: Set<FileIdentity> = []
    private var directories: Set<FileIdentity> = []
    private var namespaceIDs: [String: Set<UUID>] = [:]
    private var entryCount = 0
    private static let maximumEntries = 1_000_000
    private static let maximumDepth = 64

    init(root: URL) { self.root = root }

    func scan() throws -> ScholiumStorageInventory {
        try Task.checkCancellation()
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw DerivedStateStorageError.unavailable }
        defer { Darwin.close(descriptor) }
        try walk(descriptor, kind: .state, depth: 0)
        return ScholiumStorageInventory(
            rootURL: root, measuredAt: Date(),
            usages: ScholiumStorageCategory.allCases.map { category in
                let usage = usages[category.rawValue] ?? Usage()
                return ScholiumStorageUsage(
                    category: category, byteCount: usage.byteCount, fileCount: usage.fileCount,
                    unreadableEntries: usage.unreadableEntries, skippedEntries: usage.skippedEntries)
            },
            searchIndexesByTriptych: searchIndexesByTriptych.mapValues { usage in
                ScholiumStorageUsage(
                    category: .searchIndexes, byteCount: usage.byteCount, fileCount: usage.fileCount,
                    unreadableEntries: usage.unreadableEntries, skippedEntries: usage.skippedEntries)
            })
    }

    private func walk(_ descriptor: Int32, kind: Directory, depth: Int, triptychID: UUID? = nil) throws {
        let searchID = kind == .indexes ? triptychID : nil
        var parent = stat()
        guard fstat(descriptor, &parent) == 0 else {
            unreadable(kind.category, searchID: searchID)
            return
        }
        guard directories.insert(FileIdentity(parent)).inserted else { return }
        guard depth <= Self.maximumDepth, entryCount < Self.maximumEntries else {
            skipped(.unclassified, searchID: searchID)
            return
        }
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else {
            unreadable(kind.category, searchID: searchID)
            return
        }
        guard let stream = fdopendir(duplicate) else {
            Darwin.close(duplicate)
            unreadable(kind.category, searchID: searchID)
            return
        }
        defer { closedir(stream) }
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { unreadable(kind.category, searchID: searchID) }
                break
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            guard name != ".", name != ".." else { continue }
            // Exclusion precedes even a metadata lookup of this namespace.
            if case .chat = kind, name.caseInsensitiveCompare("Codex") == .orderedSame { continue }
            entryCount += 1
            guard entryCount <= Self.maximumEntries else {
                skipped(.unclassified, searchID: searchID)
                break
            }
            let child = kind.child(name)
            let childTriptychID = kind == .triptychs ? UUID(uuidString: name) : triptychID
            let childSearchID = child == .indexes ? childTriptychID : searchID
            if child == .indexes, let childSearchID, searchIndexesByTriptych[childSearchID] == nil {
                searchIndexesByTriptych[childSearchID] = Usage()
            }
            var status = stat()
            guard name.withCString({ fstatat(descriptor, $0, &status, AT_SYMLINK_NOFOLLOW) }) == 0 else {
                unreadable(kind.category, searchID: childSearchID)
                continue
            }
            if status.st_mode & S_IFMT == S_IFDIR {
                guard let child, admitNamespace(name, kind: kind) else {
                    skipped(.unclassified, searchID: searchID)
                    continue
                }
                let opened = name.withCString { openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW) }
                guard opened >= 0 else {
                    unreadable(child.category, searchID: childSearchID)
                    continue
                }
                defer { Darwin.close(opened) }
                var openedStatus = stat()
                guard fstat(opened, &openedStatus) == 0, FileIdentity(openedStatus) == FileIdentity(status) else {
                    unreadable(child.category, searchID: childSearchID)
                    continue
                }
                try walk(opened, kind: child, depth: depth + 1, triptychID: childTriptychID)
                var after = stat()
                if name.withCString({ fstatat(descriptor, $0, &after, AT_SYMLINK_NOFOLLOW) }) != 0 || FileIdentity(after) != FileIdentity(status) {
                    unreadable(child.category, searchID: childSearchID)
                }
            } else {
                let regular = status.st_mode & S_IFMT == S_IFREG && status.st_nlink == 1
                let category = regular ? kind.fileCategory(name) ?? .unclassified : .unclassified
                if category == .unclassified { skipped(category, searchID: childSearchID) }
                guard files.insert(FileIdentity(status)).inserted else { continue }
                let total = usages[category.rawValue, default: Usage()].byteCount.addingReportingOverflow(max(0, Int64(status.st_size)))
                usages[category.rawValue, default: Usage()].byteCount = total.overflow ? Int64.max : total.partialValue
                if total.overflow { skipped(category) }
                usages[category.rawValue, default: Usage()].fileCount += 1
                if category == .searchIndexes, let searchID {
                    let scopedTotal = searchIndexesByTriptych[searchID, default: Usage()].byteCount.addingReportingOverflow(max(0, Int64(status.st_size)))
                    searchIndexesByTriptych[searchID, default: Usage()].byteCount = scopedTotal.overflow ? Int64.max : scopedTotal.partialValue
                    searchIndexesByTriptych[searchID, default: Usage()].fileCount += 1
                    if scopedTotal.overflow { searchIndexesByTriptych[searchID, default: Usage()].skippedEntries += 1 }
                }
            }
        }
    }

    private func admitNamespace(_ name: String, kind: Directory) -> Bool {
        let namespace: String
        switch kind {
        case .triptychs: namespace = "Triptychs"
        case .vaults: namespace = "Vaults"
        case .chat: namespace = "Chat"
        default: return true
        }
        guard let id = UUID(uuidString: name) else { return false }
        return namespaceIDs[namespace, default: []].insert(id).inserted
    }

    private func skipped(_ category: ScholiumStorageCategory, searchID: UUID? = nil) {
        usages[category.rawValue, default: Usage()].skippedEntries += 1
        if let searchID { searchIndexesByTriptych[searchID, default: Usage()].skippedEntries += 1 }
    }

    private func unreadable(_ category: ScholiumStorageCategory, searchID: UUID? = nil) {
        usages[category.rawValue, default: Usage()].unreadableEntries += 1
        if let searchID { searchIndexesByTriptych[searchID, default: Usage()].unreadableEntries += 1 }
    }
}
