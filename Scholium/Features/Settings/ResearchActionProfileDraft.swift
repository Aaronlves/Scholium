import Foundation
import ScholiumContracts

struct ResearchActionModuleDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var moduleID: String
    var kind: ResearchActionModuleKind
    var label: String
    var helpText: String
    var isRequired: Bool
    var roleScope: Set<ResearchActionTargetRole>
    var maximumSelectionCount: Int
    var maximumTextUTF8ByteCount: Int
    var allowsMultipleLines: Bool
    var enumerationChoices: String
    var defaultBoolean: Bool

    init(
        id: UUID = UUID(),
        moduleID: String,
        kind: ResearchActionModuleKind,
        label: String,
        helpText: String = "",
        isRequired: Bool = false,
        roleScope: Set<ResearchActionTargetRole> = Set(ResearchActionTargetRole.allCases),
        maximumSelectionCount: Int = 1,
        maximumTextUTF8ByteCount: Int = 1_200,
        allowsMultipleLines: Bool = true,
        enumerationChoices: String = "option-one: Option One\noption-two: Option Two",
        defaultBoolean: Bool = false
    ) {
        self.id = id
        self.moduleID = moduleID
        self.kind = kind
        self.label = label
        self.helpText = helpText
        self.isRequired = isRequired
        self.roleScope = roleScope
        self.maximumSelectionCount = maximumSelectionCount
        self.maximumTextUTF8ByteCount = maximumTextUTF8ByteCount
        self.allowsMultipleLines = allowsMultipleLines
        self.enumerationChoices = enumerationChoices
        self.defaultBoolean = defaultBoolean
    }

    init(definition: ResearchActionModuleDefinition) {
        id = UUID()
        moduleID = definition.id.rawValue
        kind = definition.kind
        label = definition.label
        helpText = definition.helpText ?? ""
        isRequired = definition.isRequired
        roleScope = Set(definition.roleScope ?? ResearchActionTargetRole.allCases)
        maximumSelectionCount = definition.maximumSelectionCount ?? 1
        maximumTextUTF8ByteCount = definition.maximumTextUTF8ByteCount ?? 1_200
        allowsMultipleLines = definition.allowsMultipleLines ?? true
        enumerationChoices = definition.choices?.map {
            "\($0.value.rawValue): \($0.label)"
        }.joined(separator: "\n") ?? "option-one: Option One\noption-two: Option Two"
        defaultBoolean = definition.defaultBoolean ?? false
    }

    func definition() throws -> ResearchActionModuleDefinition {
        guard let id = ResearchActionModuleID(rawValue: normalizedModuleID) else {
            throw ResearchActionProfileContractError.invalidModule(
                "Enter a unique lowercase module identifier."
            )
        }
        let help = normalizedHelpText
        switch kind {
        case .notePicker:
            return try .notePicker(
                id: id,
                label: label,
                helpText: help,
                isRequired: isRequired,
                roleScope: canonicalRoles,
                maximumSelectionCount: maximumSelectionCount
            )
        case .passageAnchor:
            return try .passageAnchor(
                id: id,
                label: label,
                helpText: help,
                isRequired: isRequired
            )
        case .materialSelector:
            return try .materialSelector(
                id: id,
                label: label,
                helpText: help,
                isRequired: isRequired,
                roleScope: canonicalRoles,
                maximumSelectionCount: maximumSelectionCount
            )
        case .sourceReference:
            return try .sourceReference(
                id: id,
                label: label,
                helpText: help,
                isRequired: isRequired
            )
        case .boundedText:
            return try .boundedText(
                id: id,
                label: label,
                helpText: help,
                isRequired: isRequired,
                maximumTextUTF8ByteCount: maximumTextUTF8ByteCount,
                allowsMultipleLines: allowsMultipleLines
            )
        case .boolean:
            return try .boolean(
                id: id,
                label: label,
                helpText: help,
                isRequired: isRequired,
                defaultValue: defaultBoolean
            )
        case .enumeration:
            let choices = try parsedChoices()
            return try .enumeration(
                id: id,
                label: label,
                helpText: help,
                isRequired: isRequired,
                choices: choices,
                maximumSelectionCount: maximumSelectionCount
            )
        }
    }

    private var normalizedModuleID: String {
        moduleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedHelpText: String? {
        let value = helpText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var canonicalRoles: [ResearchActionTargetRole] {
        ResearchActionTargetRole.allCases.filter(roleScope.contains)
    }

    private func parsedChoices() throws -> [ResearchActionModuleChoice] {
        try enumerationChoices.split(whereSeparator: \.isNewline).map { line in
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let value = ResearchActionModuleChoiceValue(
                      rawValue: parts[0].trimmingCharacters(in: .whitespaces)
                  ) else {
                throw ResearchActionProfileContractError.invalidModule(
                    "Enumeration choices use one `value: Label` pair per line."
                )
            }
            return try ResearchActionModuleChoice(
                value: value,
                label: parts[1].trimmingCharacters(in: .whitespaces)
            )
        }
    }
}

struct ResearchActionProfileDraft: Equatable, Sendable {
    var actionID: String
    var executionKind: ResearchActionExecutionKind
    var buttonName: String
    var order: Int
    var applicableRoles: Set<ResearchActionTargetRole>
    var showInActions: Bool
    var modules: [ResearchActionModuleDraft]
    var sourceRequirement: ResearchActionSourceRequirement
    var readableRoles: Set<ResearchActionTargetRole>
    var writableRoles: Set<ResearchActionTargetRole>
    var writeOperations: Set<ResearchActionCandidateWriteOperation>
    var editablePropertyKeys: String
    var feedbackRequirement: ResearchActionFeedbackRequirement

    init(
        actionID: String,
        executionKind: ResearchActionExecutionKind = .discussion,
        buttonName: String,
        order: Int,
        applicableRoles: Set<ResearchActionTargetRole>? = nil,
        showInActions: Bool = false,
        modules: [ResearchActionModuleDraft] = []
    ) {
        self.actionID = actionID
        self.executionKind = executionKind
        self.buttonName = buttonName
        self.order = order
        let roles = applicableRoles ?? executionKind.allowedTargetRoles
        self.applicableRoles = roles
        self.showInActions = showInActions
        self.modules = modules
        sourceRequirement = .none
        readableRoles = roles
        writableRoles = []
        writeOperations = []
        editablePropertyKeys = ""
        feedbackRequirement = .requested
    }

    init(binding: ResearchActionProfileBinding) {
        let profile = binding.profile
        actionID = profile.actionID.rawValue
        executionKind = profile.executionKind
        buttonName = profile.buttonName
        order = profile.order
        applicableRoles = Set(profile.applicableRoles)
        showInActions = profile.showInActions
        modules = profile.modules.map(ResearchActionModuleDraft.init)
        sourceRequirement = profile.sourceRequirement
        readableRoles = Set(profile.capabilities.readableRoles)
        writableRoles = Set(profile.capabilities.candidateWritableRoles)
        writeOperations = Set(profile.capabilities.candidateWriteOperations)
        editablePropertyKeys = profile.capabilities.editablePropertyKeys.joined(
            separator: "\n"
        )
        feedbackRequirement = profile.feedbackRequirement
    }

    mutating func selectExecutionKind(_ kind: ResearchActionExecutionKind) {
        executionKind = kind
        applicableRoles = applicableRoles.intersection(kind.allowedTargetRoles)
        if applicableRoles.isEmpty {
            applicableRoles = kind.allowedTargetRoles
        }
        readableRoles.formUnion(applicableRoles)
        writableRoles = writableRoles.intersection(kind.maximumCandidateWritableRoles)
        if writableRoles.isEmpty {
            writeOperations = []
            editablePropertyKeys = ""
        }
        if kind == .analysis {
            sourceRequirement = .required
            if !modules.contains(where: { $0.kind == .sourceReference }) {
                modules.append(Self.defaultModule(kind: .sourceReference, index: modules.count))
            }
            if let index = modules.firstIndex(where: { $0.kind == .sourceReference }) {
                modules[index].isRequired = true
            }
        }
    }

    mutating func addModule(kind: ResearchActionModuleKind) {
        guard modules.count < ResearchActionProfile.maximumModuleCount else { return }
        modules.append(Self.defaultModule(kind: kind, index: modules.count))
        if kind == .sourceReference {
            sourceRequirement = executionKind == .analysis ? .required : .optional
        }
    }

    mutating func removeModule(id: UUID) {
        modules.removeAll { $0.id == id }
        if !modules.contains(where: { $0.kind == .sourceReference }) {
            sourceRequirement = .none
        }
    }

    func binding(packageID: String) throws -> ResearchActionProfileBinding {
        let actionID = try resolvedActionID()
        let definition: ResearchActionDefinition
        if actionID == .manuscript {
            definition = .manuscript
        } else {
            definition = try ResearchActionDefinition(
                researcherOwnedID: actionID,
                executionKind: executionKind
            )
        }
        let propertyKeys = editablePropertyKeys.split(whereSeparator: {
            $0.isNewline || $0 == ","
        }).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let capabilities = try ResearchActionCapabilityDeclaration(
            readableRoles: canonical(readableRoles),
            candidateWritableRoles: canonical(writableRoles),
            candidateWriteOperations: ResearchActionCandidateWriteOperation.allCases.filter(
                writeOperations.contains
            ),
            editablePropertyKeys: propertyKeys
        )
        let profile = try ResearchActionProfile(
            definition: definition,
            buttonName: buttonName,
            order: order,
            applicableRoles: canonical(applicableRoles),
            showInActions: showInActions,
            modules: try modules.map { try $0.definition() },
            sourceRequirement: sourceRequirement,
            capabilities: capabilities,
            feedbackRequirement: feedbackRequirement
        )
        return try ResearchActionProfileBinding(packageID: packageID, profile: profile)
    }

    func validationMessage(packageID: String) -> String? {
        do {
            _ = try binding(packageID: packageID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func resolvedActionID() throws -> ResearchActionID {
        let value = actionID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == ResearchActionID.manuscript.rawValue {
            return .manuscript
        }
        guard let identifier = ResearchActionID(researcherOwnedRawValue: value) else {
            throw ResearchActionProfileStorageError.invalidActionID(value)
        }
        return identifier
    }

    private func canonical(
        _ roles: Set<ResearchActionTargetRole>
    ) -> [ResearchActionTargetRole] {
        ResearchActionTargetRole.allCases.filter(roles.contains)
    }

    private static func defaultModule(
        kind: ResearchActionModuleKind,
        index: Int
    ) -> ResearchActionModuleDraft {
        let stem: String
        let label: String
        switch kind {
        case .notePicker: (stem, label) = ("focal-notes", "Focal Notes")
        case .passageAnchor: (stem, label) = ("passage", "Passage")
        case .materialSelector: (stem, label) = ("materials", "Materials")
        case .sourceReference: (stem, label) = ("source", "Source")
        case .boundedText: (stem, label) = ("instruction", "Instruction")
        case .boolean: (stem, label) = ("option", "Option")
        case .enumeration: (stem, label) = ("choice", "Choice")
        }
        return ResearchActionModuleDraft(
            moduleID: index == 0 ? stem : "\(stem)-\(index + 1)",
            kind: kind,
            label: label,
            isRequired: kind == .boundedText
        )
    }
}
