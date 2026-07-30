import Darwin
import Foundation
import ScholiumContracts

enum ResearchWorkingMethodStoreWriteFailure: Error {
    case committed(
        snapshot: ResearchWorkingMethodBindingSnapshot?,
        underlying: any Error
    )
}

struct ResearchWorkingMethodStore {
    static let maximumDocumentByteCount = 1_048_576
    static let maximumBindingCount = 256

    let controlURL: URL
    let documentURL: URL
    let fileManager: FileManager
    let hooks: ResearchWorkingMethodStoreHooks

    func snapshot() throws -> ResearchWorkingMethodBindingSnapshot? {
        guard fileManager.fileExists(atPath: controlURL.path) else {
            return nil
        }
        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let identity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        guard let data = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: documentURL.lastPathComponent,
            path: documentURL.path,
            maximumByteCount: Self.maximumDocumentByteCount
        ) else {
            return nil
        }
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            controlURL,
            identity: identity
        ) else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
        let document: ResearchWorkingMethodBindingDocument
        do {
            document = try JSONDecoder().decode(
                ResearchWorkingMethodBindingDocument.self,
                from: data
            )
        } catch let error as ResearchSkillBindingError {
            throw error
        } catch {
            throw ResearchSkillBindingError.invalidBindingDocument(
                error.localizedDescription
            )
        }
        return ResearchWorkingMethodBindingSnapshot(
            document: document,
            revision: DocumentFingerprint(data: data)
        )
    }

    func rawRevision() throws -> DocumentFingerprint? {
        guard fileManager.fileExists(atPath: controlURL.path) else {
            return nil
        }
        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let identity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        guard let data = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: documentURL.lastPathComponent,
            path: documentURL.path,
            maximumByteCount: Self.maximumDocumentByteCount
        ) else {
            return nil
        }
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            controlURL,
            identity: identity
        ) else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
        return DocumentFingerprint(data: data)
    }

    @discardableResult
    func save(
        _ document: ResearchWorkingMethodBindingDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchWorkingMethodBindingSnapshot {
        try ensureControlDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumDocumentByteCount,
              document.actionBindings.count <= Self.maximumBindingCount else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Working Method binding v2 exceeds its bounded storage contract."
            )
        }

        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        let leaf = documentURL.lastPathComponent
        let current = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: leaf,
            path: documentURL.path,
            maximumByteCount: Self.maximumDocumentByteCount
        )
        if let current {
            guard let expectedRevision,
                  DocumentFingerprint(data: current) == expectedRevision else {
                throw ResearchSkillBindingError.staleBindingFile
            }
        } else if expectedRevision != nil {
            throw ResearchSkillBindingError.staleBindingFile
        }

        let stageName = ".working-binding-\(UUID().uuidString.lowercased())"
        var stageCreated = false
        var didCommit = false
        do {
            try SecureResearchSkillPackageIO.createDataFile(
                parentDescriptor: rootDescriptor,
                leaf: stageName,
                data: data,
                path: stageName
            )
            stageCreated = true
            if current != nil {
                do {
                    try SecureResearchSkillPackageIO.swapPackages(
                        rootDescriptor: rootDescriptor,
                        first: leaf,
                        second: stageName
                    )
                } catch {
                    throw ResearchSkillBindingError.staleBindingFile
                }
            } else {
                do {
                    try SecureResearchSkillPackageIO.movePackageExclusively(
                        rootDescriptor: rootDescriptor,
                        source: stageName,
                        destination: leaf
                    )
                } catch {
                    throw ResearchSkillBindingError.staleBindingFile
                }
            }
            didCommit = true
            try hooks.handler(.afterBindingCommit)
            if let current {
                let displaced = try SecureResearchSkillPackageIO.readDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName,
                    maximumByteCount: Self.maximumDocumentByteCount
                )
                guard displaced == current else {
                    throw ResearchSkillBindingError.staleBindingFile
                }
            }
            guard fsync(rootDescriptor) == 0 else {
                throw ResearchSkillBindingError.unsafeBindingFile
            }
            let readback = try SecureResearchSkillPackageIO.readDataFile(
                parentDescriptor: rootDescriptor,
                leaf: leaf,
                path: documentURL.path,
                maximumByteCount: Self.maximumDocumentByteCount
            )
            guard readback == data,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      controlURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillBindingError.unsafeBindingFile
            }
            let snapshot = ResearchWorkingMethodBindingSnapshot(
                document: document,
                revision: DocumentFingerprint(data: readback)
            )
            if current != nil {
                try SecureResearchSkillPackageIO.removeDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName
                )
                guard fsync(rootDescriptor) == 0 else {
                    throw ResearchSkillBindingError
                        .workingMethodBindingRecoveryRequired
                }
            }
            return snapshot
        } catch {
            guard didCommit else {
                if stageCreated {
                    try? SecureResearchSkillPackageIO.removeDataFile(
                        parentDescriptor: rootDescriptor,
                        leaf: stageName,
                        path: stageName
                    )
                }
                throw error
            }
            let readback = try? SecureResearchSkillPackageIO.readDataFile(
                parentDescriptor: rootDescriptor,
                leaf: leaf,
                path: documentURL.path,
                maximumByteCount: Self.maximumDocumentByteCount
            )
            let snapshot = readback == data
                ? ResearchWorkingMethodBindingSnapshot(
                    document: document,
                    revision: DocumentFingerprint(data: data)
                )
                : nil
            throw ResearchWorkingMethodStoreWriteFailure.committed(
                snapshot: snapshot,
                underlying: error
            )
        }
    }

    private func ensureControlDirectory() throws {
        if !fileManager.fileExists(atPath: controlURL.path) {
            try fileManager.createDirectory(
                at: controlURL,
                withIntermediateDirectories: true
            )
        }
        let values = try controlURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
    }
}

struct ResearchActionProfileStore {
    static let maximumDocumentByteCount = 8_388_608

    let controlURL: URL
    let documentURL: URL
    let fileManager: FileManager
    let hooks: ResearchWorkingMethodStoreHooks

    func snapshot() throws -> ResearchActionProfileSnapshot? {
        guard fileManager.fileExists(atPath: controlURL.path) else {
            return nil
        }
        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        guard let data = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: documentURL.lastPathComponent,
            path: documentURL.path,
            maximumByteCount: Self.maximumDocumentByteCount
        ) else {
            return nil
        }
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            controlURL,
            identity: rootIdentity
        ) else {
            throw ResearchActionProfileStorageError.unsafeDocument
        }
        let document: ResearchActionProfileDocument
        do {
            document = try JSONDecoder().decode(
                ResearchActionProfileDocument.self,
                from: data
            )
        } catch {
            throw ResearchActionProfileStorageError.invalidDocument(
                error.localizedDescription
            )
        }
        return ResearchActionProfileSnapshot(
            document: document,
            revision: DocumentFingerprint(data: data)
        )
    }

    @discardableResult
    func save(
        _ document: ResearchActionProfileDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchActionProfileSnapshot {
        try ensureControlDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumDocumentByteCount else {
            throw ResearchActionProfileStorageError.invalidDocument(
                "The encoded document exceeds the 8 MiB storage boundary."
            )
        }

        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        let leaf = documentURL.lastPathComponent
        let current = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: leaf,
            path: documentURL.path,
            maximumByteCount: Self.maximumDocumentByteCount
        )
        if let current {
            guard let expectedRevision,
                  DocumentFingerprint(data: current) == expectedRevision else {
                throw ResearchActionProfileStorageError.staleDocument
            }
        } else if expectedRevision != nil {
            throw ResearchActionProfileStorageError.staleDocument
        }

        let stageName = ".action-profiles-\(UUID().uuidString.lowercased())"
        var stageCreated = false
        var committed = false
        do {
            try SecureResearchSkillPackageIO.createDataFile(
                parentDescriptor: rootDescriptor,
                leaf: stageName,
                data: data,
                path: stageName
            )
            stageCreated = true
            if current != nil {
                try SecureResearchSkillPackageIO.swapPackages(
                    rootDescriptor: rootDescriptor,
                    first: leaf,
                    second: stageName
                )
            } else {
                try SecureResearchSkillPackageIO.movePackageExclusively(
                    rootDescriptor: rootDescriptor,
                    source: stageName,
                    destination: leaf
                )
            }
            committed = true
            try hooks.handler(.afterActionProfileCommit)
            guard fsync(rootDescriptor) == 0 else {
                throw ResearchActionProfileStorageError.unsafeDocument
            }
            let readback = try SecureResearchSkillPackageIO.readDataFile(
                parentDescriptor: rootDescriptor,
                leaf: leaf,
                path: documentURL.path,
                maximumByteCount: Self.maximumDocumentByteCount
            )
            guard readback == data,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      controlURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchActionProfileStorageError.unsafeDocument
            }
            if current != nil {
                try SecureResearchSkillPackageIO.removeDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName
                )
                guard fsync(rootDescriptor) == 0 else {
                    throw ResearchActionProfileStorageError.unsafeDocument
                }
            }
            return ResearchActionProfileSnapshot(
                document: document,
                revision: DocumentFingerprint(data: readback)
            )
        } catch {
            if !committed, stageCreated {
                try? SecureResearchSkillPackageIO.removeDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName
                )
            }
            if committed {
                throw ResearchActionProfileStorageError.unsafeDocument
            }
            throw error
        }
    }

    private func ensureControlDirectory() throws {
        if !fileManager.fileExists(atPath: controlURL.path) {
            try fileManager.createDirectory(
                at: controlURL,
                withIntermediateDirectories: true
            )
        }
        let values = try controlURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ResearchActionProfileStorageError.unsafeDocument
        }
    }
}
