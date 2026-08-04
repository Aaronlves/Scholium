import Darwin
import Foundation
import ScholiumContracts

public struct ResearchCitationMethodDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let packageID: String?
    public let citationStyle: String?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        packageID: String? = nil,
        citationStyle: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID?.nilIfEmpty
        self.citationStyle = citationStyle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case packageID = "package_id"
        case citationStyle = "citation_style"
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ResearchCapabilityAnyCodingKey.self)
        let supported = Set(CodingKeys.allCases.map(\.rawValue))
        if let unknown = raw.allKeys.map(\.stringValue).first(where: {
            !supported.contains($0)
        }) {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Citation Method contains unsupported field \(unknown)."
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Unsupported Citation Method schema version \(schemaVersion)."
            )
        }
        self.init(
            schemaVersion: schemaVersion,
            packageID: try container.decodeIfPresent(String.self, forKey: .packageID),
            citationStyle: try container.decodeIfPresent(
                String.self,
                forKey: .citationStyle
            )
        )
        guard (packageID == nil) == (citationStyle == nil) else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Citation Method requires either both package and style or neither."
            )
        }
    }
}

public struct ResearchCitationMethodSnapshot: Hashable, Sendable {
    public let document: ResearchCitationMethodDocument
    public let revision: DocumentFingerprint

    public init(
        document: ResearchCitationMethodDocument,
        revision: DocumentFingerprint
    ) {
        self.document = document
        self.revision = revision
    }
}

public struct ResearchCitationMethodAdoption: Hashable, Sendable {
    public let package: ResearchSkillPackage
    public let binding: ResearchCitationMethodSnapshot

    public init(
        package: ResearchSkillPackage,
        binding: ResearchCitationMethodSnapshot
    ) {
        self.package = package
        self.binding = binding
    }
}

struct ResearchCitationMethodStore {
    let files: ResearchCapabilityDocumentFileStore

    func rawRevision() throws -> DocumentFingerprint? {
        try files.rawRevision()
    }

    func snapshotMigratingLegacyIfNeeded() throws -> ResearchCitationMethodSnapshot? {
        if let data = try files.currentData() {
            return ResearchCitationMethodSnapshot(
                document: try Self.decode(data),
                revision: DocumentFingerprint(data: data)
            )
        }
        guard let legacy = try legacySnapshot() else { return nil }
        guard legacy.document.packageID == nil
                || legacy.document.citationStyle != nil else {
            return legacy
        }
        return try save(
            legacy.document,
            expectedRevision: legacy.revision
        )
    }

    func snapshotWithoutMigration() throws -> ResearchCitationMethodSnapshot? {
        if let data = try files.currentData() {
            return ResearchCitationMethodSnapshot(
                document: try Self.decode(data),
                revision: DocumentFingerprint(data: data)
            )
        }
        return try legacySnapshot()
    }

    func save(
        _ document: ResearchCitationMethodDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchCitationMethodSnapshot {
        guard (document.packageID == nil) == (document.citationStyle == nil) else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Citation Method requires either both package and style or neither."
            )
        }
        let data = try files.save(document, expectedRevision: expectedRevision)
        return ResearchCitationMethodSnapshot(
            document: document,
            revision: DocumentFingerprint(data: data)
        )
    }

    private static func decode(_ data: Data) throws -> ResearchCitationMethodDocument {
        do {
            return try JSONDecoder().decode(ResearchCitationMethodDocument.self, from: data)
        } catch let error as ResearchSkillBindingError {
            throw error
        } catch {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Citation Method cannot be decoded. \(error.localizedDescription)"
            )
        }
    }

    private func legacySnapshot() throws -> ResearchCitationMethodSnapshot? {
        guard let data = try files.legacyData() else { return nil }
        let legacy = try LegacyResearchCapabilityBindingDocument.decode(data)
        guard legacy.citationBinding != nil || legacy.citationStyle == nil else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Retained Citation Method contains a style without a package."
            )
        }
        return ResearchCitationMethodSnapshot(
            document: ResearchCitationMethodDocument(
                packageID: legacy.citationBinding,
                citationStyle: legacy.citationStyle
            ),
            revision: DocumentFingerprint(data: data)
        )
    }
}

struct ResearchCapabilityDocumentFileStore {
    static let maximumByteCount = 1_048_576

    let controlURL: URL
    let currentURL: URL
    let legacyURL: URL
    let fileManager: FileManager

    func rawRevision() throws -> DocumentFingerprint? {
        if let current = try currentData() {
            return DocumentFingerprint(data: current)
        }
        return try legacyData().map(DocumentFingerprint.init(data:))
    }

    func currentData() throws -> Data? {
        try dataIfPresent(at: currentURL)
    }

    func legacyData() throws -> Data? {
        try dataIfPresent(at: legacyURL)
    }

    func save<Document: Encodable>(
        _ document: Document,
        expectedRevision: DocumentFingerprint?
    ) throws -> Data {
        try ensureControlDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumByteCount else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Capability binding exceeds the 1 MiB storage limit."
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
        let current = try read(
            rootDescriptor: rootDescriptor,
            url: currentURL
        )
        let legacy = current == nil
            ? try read(rootDescriptor: rootDescriptor, url: legacyURL)
            : nil
        guard (current ?? legacy).map(DocumentFingerprint.init(data:))
            == expectedRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }

        let stageName = ".capability-binding-\(UUID().uuidString.lowercased())"
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
            let recheckedCurrent = try read(
                rootDescriptor: rootDescriptor,
                url: currentURL
            )
            let recheckedLegacy = recheckedCurrent == nil
                ? try read(rootDescriptor: rootDescriptor, url: legacyURL)
                : nil
            guard recheckedCurrent == current,
                  recheckedLegacy == legacy,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      controlURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillBindingError.staleBindingFile
            }
            if current != nil {
                try SecureResearchSkillPackageIO.swapPackages(
                    rootDescriptor: rootDescriptor,
                    first: currentURL.lastPathComponent,
                    second: stageName
                )
            } else {
                try SecureResearchSkillPackageIO.movePackageExclusively(
                    rootDescriptor: rootDescriptor,
                    source: stageName,
                    destination: currentURL.lastPathComponent
                )
            }
            committed = true
            guard fsync(rootDescriptor) == 0 else {
                throw ResearchSkillBindingError.unsafeBindingFile
            }
            let readback = try SecureResearchSkillPackageIO.readDataFile(
                parentDescriptor: rootDescriptor,
                leaf: currentURL.lastPathComponent,
                path: currentURL.path,
                maximumByteCount: Self.maximumByteCount
            )
            guard readback == data,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      controlURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillBindingError.unsafeBindingFile
            }
            if current != nil {
                try SecureResearchSkillPackageIO.removeDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName
                )
                guard fsync(rootDescriptor) == 0 else {
                    throw ResearchSkillBindingError.unsafeBindingFile
                }
            }
            return readback
        } catch {
            if !committed, stageCreated {
                try? SecureResearchSkillPackageIO.removeDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName
                )
            }
            if committed {
                throw ResearchSkillBindingError.unsafeBindingFile
            }
            throw error
        }
    }

    private func dataIfPresent(at url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: controlURL.path) else { return nil }
        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        let data = try read(rootDescriptor: rootDescriptor, url: url)
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            controlURL,
            identity: rootIdentity
        ) else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
        return data
    }

    private func read(rootDescriptor: Int32, url: URL) throws -> Data? {
        try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: url.lastPathComponent,
            path: url.path,
            maximumByteCount: Self.maximumByteCount
        )
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

private struct LegacyResearchCapabilityBindingDocument: Decodable {
    static let schemaVersion = 1

    let citationBinding: String?
    let citationStyle: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case citationBinding = "citation_binding"
        case citationStyle = "citation_style"
    }

    static func decode(_ data: Data) throws -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch let error as ResearchSkillBindingError {
            throw error
        } catch {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Retained Function-era bindings cannot be decoded for capability migration. \(error.localizedDescription)"
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.schemaVersion else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Unsupported retained Function-era binding schema version \(schemaVersion)."
            )
        }
        citationBinding = try container.decodeIfPresent(
            String.self,
            forKey: .citationBinding
        )?.nilIfEmpty
        citationStyle = try container.decodeIfPresent(
            String.self,
            forKey: .citationStyle
        )?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty
    }
}

private struct ResearchCapabilityAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
