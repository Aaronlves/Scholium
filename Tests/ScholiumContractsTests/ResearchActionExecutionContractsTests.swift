import Foundation
import ScholiumContracts
import Testing

@Suite("Research Action execution contracts")
struct ResearchActionExecutionContractsTests {
    @Test("Flat academic values validate kind, requirement, choices, and unknown IDs")
    func academicValues() throws {
        let request = try ResearchAcademicFieldDefinition.freeText(
            id: ResearchAcademicFieldID(rawValue: "question")!,
            label: "Question",
            requirement: .required,
            maximumTextUTF8Count: 64
        )
        let lens = try ResearchAcademicFieldDefinition.multipleChoice(
            id: ResearchAcademicFieldID(rawValue: "lenses")!,
            label: "Lenses",
            requirement: .optional,
            choices: [
                ResearchAcademicChoice(value: "conceptual", label: "Conceptual"),
                ResearchAcademicChoice(value: "dialectical", label: "Dialectical"),
            ]
        )
        let values = try ResearchAcademicFieldValues(
            rawValues: [
                "question": .freeText("Test the strongest reply."),
                "lenses": .multipleChoice(["dialectical"]),
            ],
            definitions: [request, lens]
        )
        #expect(try JSONDecoder().decode(
            ResearchAcademicFieldValues.self,
            from: JSONEncoder().encode(values)
        ) == values)
        #expect(throws: ResearchAcademicProfileError.invalidFieldValues) {
            _ = try ResearchAcademicFieldValues(
                rawValues: ["unknown": .freeText("value")],
                definitions: [request, lens]
            )
        }
        #expect(throws: ResearchAcademicProfileError.invalidFieldValues) {
            _ = try ResearchAcademicFieldValues(
                rawValues: ["question": .singleChoice("conceptual")],
                definitions: [request, lens]
            )
        }
        #expect(throws: ResearchAcademicProfileError.invalidFieldValues) {
            _ = try ResearchAcademicFieldValues(
                values: [:],
                definitions: [request, lens]
            )
        }
    }

    @Test("Platform inputs reject unsupported selectors, duplicates, and stale passages")
    func platformInputs() throws {
        let target = note(role: .work, seed: "target")
        let focal = note(role: .analysis, seed: "focal")
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionPlatformInputs(focalNotes: [focal, focal])
        }
        let write = try #require(PlatformActionCatalog.definition(for: .write))
        let unsupportedChecks = try ResearchActionPlatformInputs(
            fidelityChecks: [.content]
        )
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try unsupportedChecks.validated(for: write, target: target)
        }
        let stalePassage = CommentAnchor(
            fingerprint: DocumentFingerprint(content: "stale"),
            utf8Range: 0..<1,
            utf16Range: 0..<1,
            line: 1,
            endLine: 1,
            quotation: "x"
        )
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionPlatformInputs(passage: stalePassage)
                .validated(for: write, target: target)
        }
    }

    @Test("Authority requires exact read and write identity equality")
    func exactAuthorityIntersection() throws {
        let readable = note(role: .topic, seed: "one")
        let changed = ResearchActionNoteSnapshot(
            noteID: readable.noteID,
            note: readable.note,
            role: readable.role,
            lifecycle: readable.lifecycle,
            fingerprint: DocumentFingerprint(content: "changed"),
            title: readable.title
        )
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchAuthorityEnvelope(
                readableNotes: [readable],
                writableNotes: [changed],
                writeOperations: [.modifyMarkdown],
                editablePropertyKeys: []
            )
        }
    }

    @Test("Resolved Profiles require their exact semantic and document revisions")
    func exactProfileRevision() throws {
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .discuss
            }
        )
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionResolvedProfileSnapshot(
                profile: profile,
                profileRevision: DocumentFingerprint(content: "different"),
                profileDocumentRevision: DocumentFingerprint(content: "profiles")
            )
        }
        _ = try ResearchActionResolvedProfileSnapshot(
            profile: profile,
            profileRevision: profile.contentRevision(),
            profileDocumentRevision: DocumentFingerprint(content: "profiles")
        )
    }

    @Test("Public Action mutation inputs reject unknown fields")
    func publicMutationInputsFailClosed() throws {
        let target = note(role: .work, seed: "target")
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .write
            }
        )
        let request = ResearchActionExecutionRequest(
            actionID: .write,
            expectedExecutionKind: .writing,
            expectedProfileRevision: try profile.contentRevision(),
            expectedProfileDocumentRevision: DocumentFingerprint(content: "profiles"),
            target: target,
            platformInputs: try ResearchActionPlatformInputs(),
            academicInputs: try ResearchAcademicFieldValues(
                values: [:],
                definitions: profile.academicInputFields
            )
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
                as? [String: Any]
        )
        object["unsupported"] = true
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionExecutionRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    private func note(
        role: ResearchActionTargetRole,
        seed: String
    ) -> ResearchActionNoteSnapshot {
        let noteID = seed == "target"
            ? UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
            : UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
        return ResearchActionNoteSnapshot(
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!,
                relativePath: "\(seed).md"
            ),
            role: role,
            lifecycle: .active,
            fingerprint: DocumentFingerprint(content: seed),
            title: seed
        )
    }
}
