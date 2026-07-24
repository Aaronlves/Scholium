import Foundation
import ScholiumContracts
import Testing

@Suite("Research Action Profile contracts")
struct ResearchActionProfileContractsTests {
    @Test("A bounded Profile round trips every supported native module")
    func profileRoundTrip() throws {
        let profile = try makeValidAnalyzeProfile()
        let data = try encodeProfileJSON(profile)
        let decoded = try decodeProfileJSON(data)

        #expect(decoded == profile)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.actionID == .analyze)
        #expect(decoded.executionKind == .analysis)
        #expect(decoded.applicableRoles == [.analysis])
        #expect(decoded.capabilities.readableRoles == [.analysis, .topic, .work])
        #expect(decoded.capabilities.candidateWritableRoles == [.analysis])
        #expect(decoded.capabilities.candidateWriteOperations == [
            .modifyMarkdown,
            .modifyProperties,
        ])
        #expect(decoded.capabilities.editablePropertyKeys == [
            "analysis_status",
            "source_role",
        ])
        #expect(Set(decoded.modules.map(\.kind)) == Set(ResearchActionModuleKind.allCases))

        let encoded = String(decoding: data, as: UTF8.self)
        for forbidden in [
            "function",
            "grant",
            "policy",
            "checkpoint",
            "conflict",
            "recovery",
            "javascript",
            "shell",
        ] {
            #expect(!encoded.contains("\"\(forbidden)\""))
        }
    }

    @Test("Unknown and executable fields fail closed at every Profile layer")
    func unknownAndExecutableFields() throws {
        let validData = try encodeProfileJSON(makeValidAnalyzeProfile())

        for field in [
            "swift",
            "html",
            "javascript",
            "shell",
            "executable",
        ] {
            var root = try jsonObject(validData)
            root[field] = "payload"
            #expect(throws: ResearchActionProfileContractError.self) {
                try decodeProfileJSON(jsonData(root))
            }
        }

        var moduleRoot = try jsonObject(validData)
        var modules = try #require(moduleRoot["modules"] as? [[String: Any]])
        modules[0]["script"] = "run()"
        moduleRoot["modules"] = modules
        #expect(throws: ResearchActionProfileContractError.self) {
            try decodeProfileJSON(jsonData(moduleRoot))
        }

        var choiceRoot = try jsonObject(validData)
        var choiceModules = try #require(choiceRoot["modules"] as? [[String: Any]])
        let enumerationIndex = try #require(
            choiceModules.firstIndex { $0["kind"] as? String == "enum" }
        )
        var choices = try #require(
            choiceModules[enumerationIndex]["choices"] as? [[String: Any]]
        )
        choices[0]["command"] = "delete"
        choiceModules[enumerationIndex]["choices"] = choices
        choiceRoot["modules"] = choiceModules
        #expect(throws: ResearchActionProfileContractError.self) {
            try decodeProfileJSON(jsonData(choiceRoot))
        }

        var capabilityRoot = try jsonObject(validData)
        var capabilities = try #require(capabilityRoot["capabilities"] as? [String: Any])
        capabilities["authority_token"] = "not-a-grant"
        capabilityRoot["capabilities"] = capabilities
        #expect(throws: ResearchActionProfileContractError.self) {
            try decodeProfileJSON(jsonData(capabilityRoot))
        }
    }

    @Test("Profiles cannot hide or impersonate Application-owned state")
    func applicationOwnedState() throws {
        let validData = try encodeProfileJSON(makeValidAnalyzeProfile())
        for field in [
            "show_target",
            "show_revision",
            "show_permission",
            "show_checkpoint",
            "show_conflict",
            "show_recovery",
        ] {
            var root = try jsonObject(validData)
            root[field] = false
            #expect(throws: ResearchActionProfileContractError.self) {
                try decodeProfileJSON(jsonData(root))
            }
        }

        for identifier in [
            "target",
            "identity",
            "revision",
            "permission",
            "checkpoint",
            "conflict",
            "recovery",
            "status",
        ] {
            #expect(ResearchActionModuleID(rawValue: identifier) == nil)
        }

        for label in ["Permission", "TARGET", "Ｔａｒｇｅｔ", "Source-Access"] {
            #expect(throws: ResearchActionProfileContractError.self) {
                try ResearchActionModuleDefinition.boolean(
                    id: requireModuleID("custom-field"),
                    label: label,
                    isRequired: false,
                    defaultValue: false
                )
            }
        }
    }

    @Test("Unknown schema, execution kinds, operations, and reserved mismatches fail closed")
    func unknownSchemaAndSemanticKinds() throws {
        let validData = try encodeProfileJSON(makeValidAnalyzeProfile())

        var versionRoot = try jsonObject(validData)
        versionRoot["schema_version"] = 2
        #expect(throws: ResearchActionProfileContractError.self) {
            try decodeProfileJSON(jsonData(versionRoot))
        }

        var kindRoot = try jsonObject(validData)
        kindRoot["execution_kind"] = "shell"
        #expect(throws: DecodingError.self) {
            try decodeProfileJSON(jsonData(kindRoot))
        }

        var reservedRoot = try jsonObject(validData)
        reservedRoot["execution_kind"] = "synthesis"
        #expect(throws: ResearchActionContractError.self) {
            try decodeProfileJSON(jsonData(reservedRoot))
        }

        var operationRoot = try jsonObject(validData)
        var capabilities = try #require(operationRoot["capabilities"] as? [String: Any])
        capabilities["candidate_write_operations"] = ["delete_note"]
        operationRoot["capabilities"] = capabilities
        #expect(throws: DecodingError.self) {
            try decodeProfileJSON(jsonData(operationRoot))
        }

        var moduleRoot = try jsonObject(validData)
        var modules = try #require(moduleRoot["modules"] as? [[String: Any]])
        modules[0]["kind"] = "javascript"
        moduleRoot["modules"] = modules
        #expect(throws: DecodingError.self) {
            try decodeProfileJSON(jsonData(moduleRoot))
        }
    }

    @Test("Recognized module fields cannot cross module-kind boundaries")
    func moduleFieldMatrix() throws {
        let validData = try encodeProfileJSON(makeValidAnalyzeProfile())
        var root = try jsonObject(validData)
        var modules = try #require(root["modules"] as? [[String: Any]])
        let booleanIndex = try #require(
            modules.firstIndex { $0["kind"] as? String == "boolean" }
        )
        modules[booleanIndex]["maximum_text_utf8_byte_count"] = 20
        root["modules"] = modules

        #expect(throws: ResearchActionProfileContractError.self) {
            try decodeProfileJSON(jsonData(root))
        }
    }

    @Test("Module identifiers, labels, help, and local values are bounded")
    func moduleValueBounds() throws {
        #expect(ResearchActionModuleID(rawValue: "") == nil)
        #expect(ResearchActionModuleID(rawValue: String(repeating: "a", count: 65)) == nil)
        #expect(ResearchActionModuleChoiceValue(rawValue: "Uppercase") == nil)

        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionModuleDefinition.boolean(
                id: requireModuleID("flag"),
                label: String(
                    repeating: "a",
                    count: ResearchActionModuleDefinition.maximumLabelUTF8ByteCount + 1
                ),
                isRequired: false,
                defaultValue: false
            )
        }
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionModuleDefinition.boolean(
                id: requireModuleID("flag"),
                label: "Flag",
                helpText: "invalid\nhelp",
                isRequired: false,
                defaultValue: false
            )
        }
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionModuleDefinition.boundedText(
                id: requireModuleID("instruction"),
                label: "Instruction",
                isRequired: true,
                maximumTextUTF8ByteCount:
                    ResearchActionModuleDefinition.maximumBoundedTextUTF8ByteCount + 1,
                allowsMultipleLines: true
            )
        }
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionModuleDefinition.notePicker(
                id: requireModuleID("notes"),
                label: "Notes",
                isRequired: false,
                roleScope: [.analysis],
                maximumSelectionCount:
                    ResearchActionModuleDefinition.maximumPickerSelectionCount + 1
            )
        }
    }

    @Test("Profile module count and identities are bounded")
    func profileModuleBounds() throws {
        var modules: [ResearchActionModuleDefinition] = []
        for index in 0...ResearchActionProfile.maximumModuleCount {
            modules.append(try .boolean(
                id: requireModuleID("flag-\(index)"),
                label: "Flag \(index)",
                isRequired: false,
                defaultValue: false
            ))
        }
        expectProfileError(containing: "at most 24 modules") {
            try makeAnalyzeProfile(modules: modules, sourceRequirement: .required)
        }

        let duplicate = try ResearchActionModuleDefinition.boolean(
            id: requireModuleID("duplicate"),
            label: "Duplicate",
            isRequired: false,
            defaultValue: false
        )
        expectProfileError(containing: "identifiers must be unique") {
            try makeAnalyzeProfile(
                modules: [duplicate, duplicate],
                sourceRequirement: .required
            )
        }
    }

    @Test("Enumeration choices are unique and bounded per module and Profile")
    func enumerationBounds() throws {
        let duplicateValue = try requireChoice("same", label: "One")
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionModuleDefinition.enumeration(
                id: requireModuleID("choice"),
                label: "Choice",
                isRequired: true,
                choices: [duplicateValue, duplicateValue],
                maximumSelectionCount: 1
            )
        }

        let tooManyChoices = try (0...ResearchActionModuleDefinition.maximumEnumerationChoiceCount)
            .map { try requireChoice("choice-\($0)", label: "Choice \($0)") }
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionModuleDefinition.enumeration(
                id: requireModuleID("too-many"),
                label: "Too Many",
                isRequired: true,
                choices: tooManyChoices,
                maximumSelectionCount: 1
            )
        }

        let choices = try (0..<26).map {
            try requireChoice("choice-\($0)", label: "Choice \($0)")
        }
        var modules: [ResearchActionModuleDefinition] = [try requiredSourceModule()]
        for index in 0..<5 {
            modules.append(try .enumeration(
                id: requireModuleID("enum-\(index)"),
                label: "Enumeration \(index)",
                isRequired: false,
                choices: choices,
                maximumSelectionCount: 1
            ))
        }
        expectProfileError(containing: "at most 128 enumeration choices") {
            try makeAnalyzeProfile(modules: modules, sourceRequirement: .required)
        }
    }

    @Test("Capability declarations retain only narrow existing-note operations")
    func capabilityDeclarationBounds() throws {
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionCapabilityDeclaration(
                readableRoles: [.analysis],
                candidateWritableRoles: [.work],
                candidateWriteOperations: [.modifyMarkdown]
            )
        }
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionCapabilityDeclaration(
                readableRoles: [.analysis],
                candidateWritableRoles: [.analysis]
            )
        }
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionCapabilityDeclaration(
                readableRoles: [.analysis],
                candidateWritableRoles: [.analysis],
                candidateWriteOperations: [.modifyProperties]
            )
        }
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionCapabilityDeclaration(
                readableRoles: [.analysis],
                candidateWritableRoles: [.analysis],
                candidateWriteOperations: [.modifyMarkdown],
                editablePropertyKeys: ["source_role"]
            )
        }
        let tooManyKeys = (0...ResearchActionCapabilityDeclaration.maximumEditablePropertyKeyCount)
            .map { "property_\($0)" }
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionCapabilityDeclaration(
                readableRoles: [.analysis],
                candidateWritableRoles: [.analysis],
                candidateWriteOperations: [.modifyProperties],
                editablePropertyKeys: tooManyKeys
            )
        }
        #expect(throws: ResearchActionProfileContractError.self) {
            try ResearchActionCapabilityDeclaration(
                readableRoles: [.analysis],
                candidateWritableRoles: [.analysis],
                candidateWriteOperations: [.modifyProperties],
                editablePropertyKeys: ["zotero_item_key"]
            )
        }
    }

    @Test("Execution kinds impose a hard candidate-write ceiling")
    func executionKindWriteCeiling() throws {
        let workWriting = try ResearchActionCapabilityDeclaration(
            readableRoles: [.analysis, .work],
            candidateWritableRoles: [.work],
            candidateWriteOperations: [.modifyMarkdown]
        )
        expectProfileError(containing: "exceed the hard limit") {
            try makeAnalyzeProfile(
                modules: [try requiredSourceModule()],
                sourceRequirement: .required,
                capabilities: workWriting
            )
        }

        let critiqueProfile = {
            try ResearchActionProfile(
                definition: .critique,
                buttonName: "Critique",
                order: 0,
                applicableRoles: [.work],
                showInActions: true,
                modules: [],
                sourceRequirement: .none,
                capabilities: workWriting,
                feedbackRequirement: .required
            )
        }
        expectProfileError(containing: "exceed the hard limit", critiqueProfile)

        #expect(ResearchActionExecutionKind.analysis.maximumCandidateWritableRoles == [.analysis])
        #expect(ResearchActionExecutionKind.synthesis.maximumCandidateWritableRoles == [.topic])
        #expect(ResearchActionExecutionKind.writing.maximumCandidateWritableRoles == [.work])
        #expect(ResearchActionExecutionKind.critique.maximumCandidateWritableRoles.isEmpty)
        #expect(ResearchActionExecutionKind.discussion.maximumCandidateWritableRoles.isEmpty)
        #expect(ResearchActionExecutionKind.checkFidelity.maximumCandidateWritableRoles.isEmpty)
    }

    @Test("Target and picker roles cannot escape the declared readable scope")
    func readableScopeBounds() throws {
        let topicOnly = try ResearchActionCapabilityDeclaration(readableRoles: [.topic])
        expectProfileError(containing: "Target role must remain readable") {
            try makeAnalyzeProfile(
                modules: [try requiredSourceModule()],
                sourceRequirement: .required,
                capabilities: topicOnly
            )
        }

        let analysisOnly = try ResearchActionCapabilityDeclaration(readableRoles: [.analysis])
        let topicPicker = try ResearchActionModuleDefinition.notePicker(
            id: requireModuleID("related-notes"),
            label: "Related Notes",
            isRequired: false,
            roleScope: [.topic],
            maximumSelectionCount: 2
        )
        expectProfileError(containing: "outside the declared readable scope") {
            try makeAnalyzeProfile(
                modules: [try requiredSourceModule(), topicPicker],
                sourceRequirement: .required,
                capabilities: analysisOnly
            )
        }
    }

    @Test("Source requirements and source-reference modules agree exactly")
    func sourceRequirementMatrix() throws {
        let capabilities = try ResearchActionCapabilityDeclaration(readableRoles: [.analysis])

        expectProfileError(containing: "Analysis requires one explicit source reference") {
            try makeAnalyzeProfile(
                modules: [],
                sourceRequirement: .none,
                capabilities: capabilities
            )
        }
        expectProfileError(containing: "requires one required source-reference module") {
            try makeAnalyzeProfile(
                modules: [],
                sourceRequirement: .required,
                capabilities: capabilities
            )
        }
        expectProfileError(containing: "requires one optional source-reference module") {
            try makeAnalyzeProfile(
                modules: [try requiredSourceModule()],
                sourceRequirement: .optional,
                capabilities: capabilities
            )
        }

        let optionalSource = try ResearchActionModuleDefinition.sourceReference(
            id: requireModuleID("source"),
            label: "Source",
            isRequired: false
        )
        expectProfileError(containing: "requires an optional or required source declaration") {
            try ResearchActionProfile(
                definition: .synthesize,
                buttonName: "Synthesize",
                order: 0,
                applicableRoles: [.topic],
                showInActions: true,
                modules: [optionalSource],
                sourceRequirement: .none,
                capabilities: ResearchActionCapabilityDeclaration(readableRoles: [.topic]),
                feedbackRequirement: .requested
            )
        }
    }

    @Test("Profile order, names, roles, and property boundaries reject oversized values")
    func profilePresentationBounds() throws {
        expectProfileError(containing: "button name") {
            try ResearchActionProfile(
                definition: .analyze,
                buttonName: String(
                    repeating: "a",
                    count: ResearchActionProfile.maximumButtonNameUTF8ByteCount + 1
                ),
                order: 0,
                applicableRoles: [.analysis],
                showInActions: true,
                modules: [try requiredSourceModule()],
                sourceRequirement: .required,
                capabilities: ResearchActionCapabilityDeclaration(readableRoles: [.analysis]),
                feedbackRequirement: .requested
            )
        }
        expectProfileError(containing: "Action order") {
            try ResearchActionProfile(
                definition: .analyze,
                buttonName: "Analyze",
                order: ResearchActionProfile.maximumOrder + 1,
                applicableRoles: [.analysis],
                showInActions: true,
                modules: [try requiredSourceModule()],
                sourceRequirement: .required,
                capabilities: ResearchActionCapabilityDeclaration(readableRoles: [.analysis]),
                feedbackRequirement: .requested
            )
        }
        expectProfileError(containing: "cannot repeat a role") {
            try ResearchActionProfile(
                definition: .analyze,
                buttonName: "Analyze",
                order: 0,
                applicableRoles: [.analysis, .analysis],
                showInActions: true,
                modules: [try requiredSourceModule()],
                sourceRequirement: .required,
                capabilities: ResearchActionCapabilityDeclaration(readableRoles: [.analysis]),
                feedbackRequirement: .requested
            )
        }
    }
}

private func makeValidAnalyzeProfile() throws -> ResearchActionProfile {
    let choices = [
        try requireChoice("narrow", label: "Narrow Reconstruction"),
        try requireChoice("dialectical", label: "Dialectical Pressure"),
    ]
    let modules: [ResearchActionModuleDefinition] = [
        try .sourceReference(
            id: requireModuleID("source"),
            label: "Source",
            isRequired: true
        ),
        try .passageAnchor(
            id: requireModuleID("passage"),
            label: "Passage",
            isRequired: false
        ),
        try .notePicker(
            id: requireModuleID("focal-notes"),
            label: "Focal Notes",
            isRequired: false,
            roleScope: [.work, .analysis, .topic],
            maximumSelectionCount: 4
        ),
        try .materialSelector(
            id: requireModuleID("materials"),
            label: "Materials",
            isRequired: false,
            roleScope: [.analysis, .topic],
            maximumSelectionCount: 8
        ),
        try .boundedText(
            id: requireModuleID("instruction"),
            label: "Instruction",
            helpText: "State the question naturally.",
            isRequired: true,
            maximumTextUTF8ByteCount: 4_096,
            allowsMultipleLines: true
        ),
        try .boolean(
            id: requireModuleID("preserve-uncertainty"),
            label: "Preserve Uncertainty",
            isRequired: false,
            defaultValue: true
        ),
        try .enumeration(
            id: requireModuleID("emphasis"),
            label: "Emphasis",
            isRequired: false,
            choices: choices,
            maximumSelectionCount: 2
        ),
    ]
    let capabilities = try ResearchActionCapabilityDeclaration(
        readableRoles: [.work, .analysis, .topic],
        candidateWritableRoles: [.analysis],
        candidateWriteOperations: [.modifyProperties, .modifyMarkdown],
        editablePropertyKeys: ["source_role", "analysis_status"]
    )
    return try makeAnalyzeProfile(
        modules: modules,
        sourceRequirement: .required,
        capabilities: capabilities
    )
}

private func makeAnalyzeProfile(
    modules: [ResearchActionModuleDefinition],
    sourceRequirement: ResearchActionSourceRequirement,
    capabilities: ResearchActionCapabilityDeclaration? = nil
) throws -> ResearchActionProfile {
    try ResearchActionProfile(
        definition: .analyze,
        buttonName: "Analyze",
        order: 1,
        applicableRoles: [.analysis],
        showInActions: true,
        modules: modules,
        sourceRequirement: sourceRequirement,
        capabilities: capabilities
            ?? ResearchActionCapabilityDeclaration(readableRoles: [.analysis]),
        feedbackRequirement: .required
    )
}

private func requiredSourceModule() throws -> ResearchActionModuleDefinition {
    try .sourceReference(
        id: requireModuleID("source"),
        label: "Source",
        isRequired: true
    )
}

private func requireModuleID(_ rawValue: String) throws -> ResearchActionModuleID {
    try #require(ResearchActionModuleID(rawValue: rawValue))
}

private func requireChoice(
    _ rawValue: String,
    label: String
) throws -> ResearchActionModuleChoice {
    try ResearchActionModuleChoice(
        value: #require(ResearchActionModuleChoiceValue(rawValue: rawValue)),
        label: label
    )
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func encodeProfileJSON(_ profile: ResearchActionProfile) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(profile)
}

private func decodeProfileJSON(_ data: Data) throws -> ResearchActionProfile {
    try JSONDecoder().decode(ResearchActionProfile.self, from: data)
}

private func expectProfileError(
    containing text: String,
    _ operation: () throws -> ResearchActionProfile
) {
    do {
        _ = try operation()
        Issue.record("Expected a ResearchActionProfileContractError containing: \(text)")
    } catch let error as ResearchActionProfileContractError {
        #expect(error.errorDescription?.localizedCaseInsensitiveContains(text) == true)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}
