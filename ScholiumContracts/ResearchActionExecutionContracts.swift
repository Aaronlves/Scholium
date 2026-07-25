import Foundation

/// Exact note identity and revision at the public Action boundary.
///
/// This deliberately mirrors only the stable note facts needed by an Action;
/// it contains no protected Function identity or storage locator.
public struct ResearchActionNoteSnapshot: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let lifecycle: WorkspaceDocumentLifecycle
    public let fingerprint: DocumentFingerprint
    public let title: String

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        lifecycle: WorkspaceDocumentLifecycle,
        fingerprint: DocumentFingerprint,
        title: String
    ) {
        self.noteID = noteID
        self.note = note
        self.role = role
        self.lifecycle = lifecycle
        self.fingerprint = fingerprint
        self.title = title
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID
        case note
        case role
        case lifecycle
        case fingerprint
        case title
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionExecutionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            noteID: try container.decode(UUID.self, forKey: .noteID),
            note: try container.decode(VaultQualifiedNoteID.self, forKey: .note),
            role: try container.decode(ResearchActionTargetRole.self, forKey: .role),
            lifecycle: try container.decode(
                WorkspaceDocumentLifecycle.self,
                forKey: .lifecycle
            ),
            fingerprint: try container.decode(
                DocumentFingerprint.self,
                forKey: .fingerprint
            ),
            title: try container.decode(String.self, forKey: .title)
        )
    }
}

/// One closed, native value supplied to a declarative Action module.
/// Associated values are encoded explicitly so unknown future kinds fail
/// closed instead of being interpreted as text.
public enum ResearchActionParameterValue: Hashable, Sendable {
    case notes([ResearchActionNoteSnapshot])
    case passage(CommentAnchor)
    case source(ResearchSourceReference)
    case text(String)
    case boolean(Bool)
    case choices([ResearchActionModuleChoiceValue])
}

extension ResearchActionParameterValue: Codable {
    private enum Kind: String, Codable {
        case notes
        case passage
        case source
        case text
        case boolean
        case choices
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case notes
        case passage
        case source
        case text
        case boolean
        case choices
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ResearchActionExecutionAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchActionExecutionContractError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let populatedKeys = CodingKeys.allCases.filter {
            $0 != .kind && container.contains($0)
        }
        let expectedKey: CodingKeys
        switch kind {
        case .notes:
            expectedKey = .notes
            self = .notes(try container.decode(
                [ResearchActionNoteSnapshot].self,
                forKey: .notes
            ))
        case .passage:
            expectedKey = .passage
            self = .passage(try container.decode(CommentAnchor.self, forKey: .passage))
        case .source:
            expectedKey = .source
            self = .source(try container.decode(
                ResearchSourceReference.self,
                forKey: .source
            ))
        case .text:
            expectedKey = .text
            self = .text(try container.decode(String.self, forKey: .text))
        case .boolean:
            expectedKey = .boolean
            self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        case .choices:
            expectedKey = .choices
            self = .choices(try container.decode(
                [ResearchActionModuleChoiceValue].self,
                forKey: .choices
            ))
        }
        guard populatedKeys == [expectedKey] else {
            throw ResearchActionExecutionContractError.invalidParameter(
                "A parameter value must contain exactly the payload for its declared kind."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notes(let value):
            try container.encode(Kind.notes, forKey: .kind)
            try container.encode(value, forKey: .notes)
        case .passage(let value):
            try container.encode(Kind.passage, forKey: .kind)
            try container.encode(value, forKey: .passage)
        case .source(let value):
            try container.encode(Kind.source, forKey: .kind)
            try container.encode(value, forKey: .source)
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .boolean(let value):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(value, forKey: .boolean)
        case .choices(let value):
            try container.encode(Kind.choices, forKey: .kind)
            try container.encode(value, forKey: .choices)
        }
    }
}

/// Validated values for one exact Action Profile.
///
/// The model rejects unknown modules, value-kind mismatches, missing required
/// values, excessive selections, out-of-scope note roles, and values outside
/// a module's declared text or choice boundary.
public struct ResearchActionParameterModel: Codable, Hashable, Sendable {
    public let values: [String: ResearchActionParameterValue]

    public init(
        profile: ResearchActionProfile,
        values: [ResearchActionModuleID: ResearchActionParameterValue]
    ) throws {
        try self.init(
            profile: profile,
            rawValues: Dictionary(uniqueKeysWithValues: values.map {
                ($0.key.rawValue, $0.value)
            })
        )
    }

    public init(
        profile: ResearchActionProfile,
        rawValues: [String: ResearchActionParameterValue] = [:]
    ) throws {
        try self.init(
            profile: profile,
            rawValues: rawValues,
            defersRequiredSource: false
        )
    }

    /// Validates a preparation request before the Application has resolved its
    /// machine-local source binding. Only one missing required source value may
    /// be deferred; the complete Action snapshot always revalidates without
    /// this allowance after exact source resolution.
    public init(
        deferringRequiredSourceFor profile: ResearchActionProfile,
        rawValues: [String: ResearchActionParameterValue] = [:]
    ) throws {
        try self.init(
            profile: profile,
            rawValues: rawValues,
            defersRequiredSource: true
        )
    }

    private init(
        profile: ResearchActionProfile,
        rawValues: [String: ResearchActionParameterValue],
        defersRequiredSource: Bool
    ) throws {
        let definitions = Dictionary(uniqueKeysWithValues: profile.modules.map {
            ($0.id.rawValue, $0)
        })
        guard rawValues.keys.allSatisfy({ definitions[$0] != nil }) else {
            let unknown = rawValues.keys.sorted().first { definitions[$0] == nil } ?? ""
            throw ResearchActionExecutionContractError.unknownParameter(unknown)
        }

        var normalized = rawValues
        for module in profile.modules {
            if normalized[module.id.rawValue] == nil,
               module.kind == .boolean,
               let defaultValue = module.defaultBoolean {
                normalized[module.id.rawValue] = .boolean(defaultValue)
            }
            guard let value = normalized[module.id.rawValue] else {
                if defersRequiredSource,
                   module.isRequired,
                   module.kind == .sourceReference {
                    continue
                }
                if module.isRequired {
                    throw ResearchActionExecutionContractError.missingRequiredParameter(
                        module.id
                    )
                }
                continue
            }
            try Self.validate(value, for: module)
        }
        values = normalized
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case values
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        values = try container.decode(
            [String: ResearchActionParameterValue].self,
            forKey: .values
        )
        guard values.keys.allSatisfy({ ResearchActionModuleID(rawValue: $0) != nil }) else {
            let invalid = values.keys.sorted().first {
                ResearchActionModuleID(rawValue: $0) == nil
            } ?? ""
            throw ResearchActionExecutionContractError.unknownParameter(invalid)
        }
    }

    public func value(
        for moduleID: ResearchActionModuleID
    ) -> ResearchActionParameterValue? {
        values[moduleID.rawValue]
    }

    private static func validate(
        _ value: ResearchActionParameterValue,
        for module: ResearchActionModuleDefinition
    ) throws {
        switch (module.kind, value) {
        case (.notePicker, .notes(let notes)),
             (.materialSelector, .notes(let notes)):
            let maximum = module.maximumSelectionCount ?? 0
            guard notes.count <= maximum,
                  (!module.isRequired || !notes.isEmpty),
                  Set(notes.map(\.noteID)).count == notes.count else {
                throw invalid(module, "The note selection is empty, duplicated, or exceeds its declared maximum.")
            }
            let allowedRoles = Set(module.roleScope ?? [])
            guard notes.allSatisfy({ allowedRoles.contains($0.role) }) else {
                throw invalid(module, "A selected note is outside the module's declared role scope.")
            }
        case (.passageAnchor, .passage):
            break
        case (.sourceReference, .source):
            break
        case (.boundedText, .text(let text)):
            let maximum = module.maximumTextUTF8ByteCount ?? 0
            guard text.utf8.count <= maximum,
                  (!module.isRequired || !text.isEmpty),
                  module.allowsMultipleLines == true
                    || (!text.contains("\n") && !text.contains("\r")) else {
                throw invalid(module, "The text is empty, multiline, or exceeds its declared UTF-8 boundary.")
            }
        case (.boolean, .boolean):
            break
        case (.enumeration, .choices(let choices)):
            let maximum = module.maximumSelectionCount ?? 0
            let allowed = Set((module.choices ?? []).map(\.value))
            guard choices.count <= maximum,
                  (!module.isRequired || !choices.isEmpty),
                  Set(choices).count == choices.count,
                  choices.allSatisfy(allowed.contains) else {
                throw invalid(module, "The choice selection is empty, duplicated, unsupported, or exceeds its declared maximum.")
            }
        default:
            throw invalid(module, "The value kind does not match the module kind.")
        }
    }

    private static func invalid(
        _ module: ResearchActionModuleDefinition,
        _ reason: String
    ) -> ResearchActionExecutionContractError {
        .invalidParameter("Module \(module.id.rawValue): \(reason)")
    }

    private static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: [String]
    ) throws {
        let raw = try decoder.container(keyedBy: ResearchActionExecutionAnyCodingKey.self)
        let permitted = Set(allowed)
        if let unknown = raw.allKeys.map(\.stringValue)
            .first(where: { !permitted.contains($0) }) {
            throw ResearchActionExecutionContractError.unsupportedField(unknown)
        }
    }
}

/// Exact, concrete authority frozen for one prepared Action.
///
/// This value is evidence of the intersection Scholium actually issued, not
/// a reusable permission token. It contains only current note identities and
/// bounded existing-note operations.
public struct ResearchAuthorityEnvelope: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let readableNotes: [ResearchActionNoteSnapshot]
    public let writableNotes: [ResearchActionNoteSnapshot]
    public let writeOperations: [ResearchActionCandidateWriteOperation]
    public let editablePropertyKeys: [String]

    public init(
        readableNotes: [ResearchActionNoteSnapshot],
        writableNotes: [ResearchActionNoteSnapshot],
        writeOperations: [ResearchActionCandidateWriteOperation],
        editablePropertyKeys: [String]
    ) throws {
        let reads = Self.canonicalNotes(readableNotes)
        let writes = Self.canonicalNotes(writableNotes)
        guard reads.count == readableNotes.count,
              writes.count == writableNotes.count else {
            throw ResearchActionExecutionContractError.invalidAuthority(
                "Authority cannot repeat a note identity."
            )
        }
        guard writes.allSatisfy({ write in
            reads.contains(where: { $0 == write })
        }) else {
            throw ResearchActionExecutionContractError.invalidAuthority(
                "Every writable note must exactly match one readable identity and revision."
            )
        }
        let operations = Array(Set(writeOperations)).sorted { $0.rawValue < $1.rawValue }
        let propertyKeys = Array(Set(editablePropertyKeys)).sorted()
        if writes.isEmpty {
            guard operations.isEmpty, propertyKeys.isEmpty else {
                throw ResearchActionExecutionContractError.invalidAuthority(
                    "Read-only authority cannot contain write operations or property keys."
                )
            }
        } else {
            guard !operations.isEmpty else {
                throw ResearchActionExecutionContractError.invalidAuthority(
                    "Writable authority requires at least one bounded operation."
                )
            }
        }
        guard operations.contains(.modifyProperties) == !propertyKeys.isEmpty else {
            throw ResearchActionExecutionContractError.invalidAuthority(
                "Property keys and the modify-properties operation must be frozen together."
            )
        }
        guard propertyKeys.count
                <= ResearchActionCapabilityDeclaration.maximumEditablePropertyKeyCount,
              propertyKeys.allSatisfy({ key in
                  !key.isEmpty
                      && key.utf8.count
                          <= ResearchActionCapabilityDeclaration.maximumPropertyKeyUTF8ByteCount
                      && !key.unicodeScalars.contains(where: {
                          CharacterSet.controlCharacters.contains($0)
                      })
                      && !PropertyContractCatalog.isProtectedMachineKey(key)
              }) else {
            throw ResearchActionExecutionContractError.invalidAuthority(
                "Editable property keys exceed their bounded, nonprotected contract."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        self.readableNotes = reads
        self.writableNotes = writes
        self.writeOperations = operations
        self.editablePropertyKeys = propertyKeys
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case readableNotes = "readable_notes"
        case writableNotes = "writable_notes"
        case writeOperations = "write_operations"
        case editablePropertyKeys = "editable_property_keys"
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ResearchActionExecutionAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchActionExecutionContractError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchActionContractError.unsupportedSchemaVersion(schemaVersion)
        }
        try self.init(
            readableNotes: container.decode(
                [ResearchActionNoteSnapshot].self,
                forKey: .readableNotes
            ),
            writableNotes: container.decode(
                [ResearchActionNoteSnapshot].self,
                forKey: .writableNotes
            ),
            writeOperations: container.decode(
                [ResearchActionCandidateWriteOperation].self,
                forKey: .writeOperations
            ),
            editablePropertyKeys: container.decode(
                [String].self,
                forKey: .editablePropertyKeys
            )
        )
    }

    private static func canonicalNotes(
        _ notes: [ResearchActionNoteSnapshot]
    ) -> [ResearchActionNoteSnapshot] {
        var seen: Set<UUID> = []
        return notes
            .sorted { $0.noteID.uuidString < $1.noteID.uuidString }
            .filter { seen.insert($0.noteID).inserted }
    }
}

public struct ResearchActionResourceSnapshot: Codable, Hashable, Sendable {
    public let relativePath: String
    public let revision: DocumentFingerprint

    public init(relativePath: String, revision: DocumentFingerprint) {
        self.relativePath = relativePath
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case relativePath = "relative_path"
        case revision
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionExecutionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            relativePath: try container.decode(String.self, forKey: .relativePath),
            revision: try container.decode(DocumentFingerprint.self, forKey: .revision)
        )
    }
}

/// Exact ordinary Method Skill selected for one Action run.
public struct ResearchActionMethodSnapshot: Codable, Hashable, Sendable {
    public let packageID: String
    public let origin: ResearchSkillOrigin
    public let version: String
    public let packageRevision: DocumentFingerprint
    public let loadedResources: [ResearchActionResourceSnapshot]

    public init(
        packageID: String,
        origin: ResearchSkillOrigin,
        version: String,
        packageRevision: DocumentFingerprint,
        loadedResources: [ResearchActionResourceSnapshot]
    ) throws {
        let resourcePaths = loadedResources.map(\.relativePath)
        guard !packageID.isEmpty,
              !loadedResources.isEmpty,
              Set(resourcePaths).count == resourcePaths.count,
              resourcePaths.allSatisfy({ path in
                  !path.isEmpty
                      && !path.hasPrefix("/")
                      && !path.split(separator: "/", omittingEmptySubsequences: false)
                          .contains(where: { $0 == "." || $0 == ".." || $0.isEmpty })
              }) else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        self.packageID = packageID
        self.origin = origin
        self.version = version
        self.packageRevision = packageRevision
        self.loadedResources = loadedResources.sorted {
            $0.relativePath < $1.relativePath
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case packageID = "package_id"
        case origin
        case version
        case packageRevision = "package_revision"
        case loadedResources = "loaded_resources"
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionExecutionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            packageID: try container.decode(String.self, forKey: .packageID),
            origin: try container.decode(ResearchSkillOrigin.self, forKey: .origin),
            version: try container.decode(String.self, forKey: .version),
            packageRevision: try container.decode(
                DocumentFingerprint.self,
                forKey: .packageRevision
            ),
            loadedResources: try container.decode(
                [ResearchActionResourceSnapshot].self,
                forKey: .loadedResources
            )
        )
    }
}

public enum ResearchActionProfileOrigin: String, Codable, Hashable, Sendable {
    case applicationDefault = "application_default"
    case researcher
}

/// Complete resolved Profile plus its exact semantic and storage revisions.
/// The document revision is nil for Scholium's application-owned defaults.
public struct ResearchActionResolvedProfileSnapshot: Codable, Hashable, Sendable {
    public let origin: ResearchActionProfileOrigin
    public let profile: ResearchActionProfile
    public let profileRevision: DocumentFingerprint
    public let profileDocumentRevision: DocumentFingerprint?

    public init(
        origin: ResearchActionProfileOrigin,
        profile: ResearchActionProfile,
        profileRevision: DocumentFingerprint,
        profileDocumentRevision: DocumentFingerprint?
    ) throws {
        guard (origin == .researcher) == (profileDocumentRevision != nil) else {
            throw ResearchActionExecutionContractError.invalidProfileRevision
        }
        guard profileRevision == (try profile.contentRevision()) else {
            throw ResearchActionExecutionContractError.invalidProfileRevision
        }
        self.origin = origin
        self.profile = profile
        self.profileRevision = profileRevision
        self.profileDocumentRevision = profileDocumentRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case origin
        case profile
        case profileRevision = "profile_revision"
        case profileDocumentRevision = "profile_document_revision"
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ResearchActionExecutionAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchActionExecutionContractError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            origin: container.decode(ResearchActionProfileOrigin.self, forKey: .origin),
            profile: container.decode(ResearchActionProfile.self, forKey: .profile),
            profileRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .profileRevision
            ),
            profileDocumentRevision: container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .profileDocumentRevision
            )
        )
    }
}

public extension ResearchActionProfile {
    /// Deterministic semantic revision independent of the surrounding Profile
    /// document and unrelated Action bindings.
    func contentRevision() throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return DocumentFingerprint(data: try encoder.encode(self))
    }
}

public enum ResearchActionAvailabilityGroup: String, Codable, Hashable, Sendable {
    case defaultAction = "default"
    case researcherSkill = "researcher_skill"
}

public enum ResearchActionRepairReasonCode: String, Codable, Hashable, Sendable {
    case targetUnavailable = "target_unavailable"
    case targetChanged = "target_changed"
    case targetIdentityChanged = "target_identity_changed"
    case invalidTargetRole = "invalid_target_role"
    case inactiveTarget = "inactive_target"
    case sourceAccessRequired = "source_access_required"
    case methodMissing = "method_missing"
    case methodDisabled = "method_disabled"
    case methodInvalid = "method_invalid"
    case profileInvalid = "profile_invalid"
    case unsupportedCapability = "unsupported_capability"
}

public struct ResearchActionRepairReason: Codable, Hashable, Sendable {
    public let code: ResearchActionRepairReasonCode
    public let packageID: String?
    public let sourceAccessFailure: ResearchSourceAccessFailure?

    public init(
        code: ResearchActionRepairReasonCode,
        packageID: String? = nil,
        sourceAccessFailure: ResearchSourceAccessFailure? = nil
    ) {
        self.code = code
        self.packageID = packageID
        self.sourceAccessFailure = sourceAccessFailure
    }
}

/// Non-authorizing Action row resolved against current configuration.
/// Preparation always resolves again; this value cannot be replayed as a
/// grant after a Profile, Skill, Target, or permission change.
public struct ResearchActionAvailability: Codable, Hashable, Identifiable, Sendable {
    public let definition: ResearchActionDefinition
    public let buttonName: String
    public let order: Int
    public let group: ResearchActionAvailabilityGroup
    public let profile: ResearchActionResolvedProfileSnapshot
    public let isEnabled: Bool
    public let repairReasons: [ResearchActionRepairReason]

    public var id: ResearchActionID { definition.id }

    public init(
        definition: ResearchActionDefinition,
        buttonName: String,
        order: Int,
        group: ResearchActionAvailabilityGroup,
        profile: ResearchActionResolvedProfileSnapshot,
        isEnabled: Bool,
        repairReasons: [ResearchActionRepairReason] = []
    ) {
        self.definition = definition
        self.buttonName = buttonName
        self.order = order
        self.group = group
        self.profile = profile
        self.isEnabled = isEnabled
        self.repairReasons = repairReasons
    }
}

/// Delivery-neutral request. The Application resolves the Action, Profile,
/// Method, current source, and authority again before creating a run.
public struct ResearchActionExecutionRequest: Hashable, Sendable {
    public let actionID: ResearchActionID
    public let target: ResearchActionNoteSnapshot
    public let parameterValues: [String: ResearchActionParameterValue]

    public init(
        actionID: ResearchActionID,
        target: ResearchActionNoteSnapshot,
        parameterValues: [ResearchActionModuleID: ResearchActionParameterValue] = [:]
    ) {
        self.actionID = actionID
        self.target = target
        self.parameterValues = Dictionary(uniqueKeysWithValues: parameterValues.map {
            ($0.key.rawValue, $0.value)
        })
    }
}

/// Public preparation result. The protected Function remains an internal
/// compatibility mechanism and is therefore absent from this value.
public struct ResearchActionPreparation: Hashable, Sendable {
    public let snapshot: ResearchActionSnapshot
    public let runID: UUID
    public let instructions: String
    public let state: ResearchFunctionRunState
    public let derivedRefreshWarning: String?
    public let nextActions: [AgentCommandAction]

    public init(
        snapshot: ResearchActionSnapshot,
        runID: UUID,
        instructions: String,
        state: ResearchFunctionRunState,
        derivedRefreshWarning: String? = nil,
        nextActions: [AgentCommandAction] = []
    ) {
        self.snapshot = snapshot
        self.runID = runID
        self.instructions = instructions
        self.state = state
        self.derivedRefreshWarning = derivedRefreshWarning
        self.nextActions = nextActions
    }
}

public enum ResearchActionExecutionContractError: LocalizedError, Hashable, Sendable {
    case unsupportedField(String)
    case unknownParameter(String)
    case missingRequiredParameter(ResearchActionModuleID)
    case invalidParameter(String)
    case invalidAuthority(String)
    case invalidProfileRevision
    case actionUnavailable(ResearchActionID)
    case staleResolution

    public var errorDescription: String? {
        switch self {
        case .unsupportedField(let field):
            "Unsupported Research Action execution field: \(field)."
        case .unknownParameter(let id):
            "The Action request contains an unknown parameter: \(id)."
        case .missingRequiredParameter(let id):
            "The Action request is missing required parameter \(id.rawValue)."
        case .invalidParameter(let reason):
            "The Action request contains an invalid parameter. \(reason)"
        case .invalidAuthority(let reason):
            "The Action authority envelope is invalid. \(reason)"
        case .invalidProfileRevision:
            "The resolved Action Profile origin and storage revision do not match."
        case .actionUnavailable(let actionID):
            "Action \(actionID.rawValue) is not currently available."
        case .staleResolution:
            "The Action, Method, Profile, Target, or authority changed during preparation."
        }
    }
}

enum ResearchActionExecutionValidation {
    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>
    ) throws {
        let raw = try decoder.container(keyedBy: ResearchActionExecutionAnyCodingKey.self)
        let permitted = Set(allowed)
        if let unknown = raw.allKeys.map(\.stringValue).sorted()
            .first(where: { !permitted.contains($0) }) {
            throw ResearchActionExecutionContractError.unsupportedField(unknown)
        }
    }
}

private struct ResearchActionExecutionAnyCodingKey: CodingKey {
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
