import Foundation
import Testing
@testable import ScholiumContracts

@Suite("Research Source Access contracts")
struct ResearchSourceAccessContractsTests {
    private let sourceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("Local and Zotero identities round trip only their safe fields")
    func identityRoundTrip() throws {
        let identities = [
            ResearchSourceIdentity.localFile(id: sourceID),
            try ResearchSourceIdentity.zoteroAttachment(
                id: sourceID,
                itemKey: "parent01",
                attachmentKey: "attach02"
            ),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for identity in identities {
            #expect(try decoder.decode(
                ResearchSourceIdentity.self,
                from: encoder.encode(identity)
            ) == identity)
        }
        #expect(identities[1].zoteroItemKey == "PARENT01")
        #expect(identities[1].zoteroAttachmentKey == "ATTACH02")
    }

    @Test("A source reference excludes bookmark, path, and source bytes")
    func portableProjectionIsNarrow() throws {
        let reference = try ResearchSourceReference(
            identity: .localFile(id: sourceID),
            displayName: "Source.pdf",
            fingerprint: DocumentFingerprint(content: "private source bytes")
        )
        let data = try JSONEncoder().encode(reference)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "schemaVersion", "identity", "displayName", "fingerprint",
        ])
        let encoded = String(decoding: data, as: UTF8.self)
        #expect(!encoded.contains("bookmark"))
        #expect(!encoded.contains("/Users/"))
        #expect(!encoded.contains("private source bytes"))

        let snapshot = ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(
                function: .develop,
                target: target()
            ),
            recordKind: .functionEnvelope,
            sourceReference: reference
        )
        let snapshotData = try JSONEncoder().encode(snapshot)
        let snapshotJSON = String(decoding: snapshotData, as: UTF8.self)
        #expect(snapshotJSON.contains("Source.pdf"))
        #expect(!snapshotJSON.contains("bookmark"))
        #expect(!snapshotJSON.contains("/Users/"))
        #expect(!snapshotJSON.contains("private source bytes"))
    }

    @Test("Unknown fields and schema versions fail closed")
    func unknownFieldsAndVersions() throws {
        let decoder = JSONDecoder()
        let identityJSON = """
        {
          "schemaVersion": 1,
          "id": "\(sourceID.uuidString)",
          "route": "local_file",
          "absolutePath": "/private/source.pdf"
        }
        """
        #expect(throws: ResearchSourceAccessContractError.self) {
            try decoder.decode(
                ResearchSourceIdentity.self,
                from: Data(identityJSON.utf8)
            )
        }

        let referenceJSON = """
        {
          "schemaVersion": 2,
          "identity": {
            "schemaVersion": 1,
            "id": "\(sourceID.uuidString)",
            "route": "local_file"
          },
          "displayName": "Source.pdf",
          "fingerprint": {
            "sha256": "\(String(repeating: "a", count: 64))",
            "byteCount": 1
          }
        }
        """
        #expect(throws: ResearchSourceAccessContractError.self) {
            try decoder.decode(
                ResearchSourceReference.self,
                from: Data(referenceJSON.utf8)
            )
        }
    }

    @Test("Route-specific identity and Zotero keys are bounded")
    func identityValidation() throws {
        let decoder = JSONDecoder()
        let invalidLocal = """
        {
          "schemaVersion": 1,
          "id": "\(sourceID.uuidString)",
          "route": "local_file",
          "zoteroItemKey": "PARENT01",
          "zoteroAttachmentKey": "ATTACH02"
        }
        """
        #expect(throws: ResearchSourceAccessContractError.self) {
            try decoder.decode(
                ResearchSourceIdentity.self,
                from: Data(invalidLocal.utf8)
            )
        }
        #expect(throws: ResearchSourceAccessContractError.self) {
            try ResearchSourceIdentity.zoteroAttachment(
                itemKey: "SAMEKEY",
                attachmentKey: "SAMEKEY"
            )
        }
        #expect(throws: ResearchSourceAccessContractError.self) {
            try ResearchSourceIdentity.zoteroAttachment(
                itemKey: "bad/path",
                attachmentKey: "ATTACH02"
            )
        }
    }

    @Test("Display names and fingerprints are bounded")
    func referenceValidation() throws {
        #expect(throws: ResearchSourceAccessContractError.self) {
            try ResearchSourceReference(
                identity: .localFile(id: sourceID),
                displayName: "\n",
                fingerprint: DocumentFingerprint(content: "source")
            )
        }
        #expect(throws: ResearchSourceAccessContractError.self) {
            try ResearchSourceReference(
                identity: .localFile(id: sourceID),
                displayName: "/Users/researcher/Source.pdf",
                fingerprint: DocumentFingerprint(content: "source")
            )
        }
        #expect(throws: ResearchSourceAccessContractError.self) {
            try ResearchSourceReference(
                identity: .localFile(id: sourceID),
                displayName: "Source.pdf",
                fingerprint: DocumentFingerprint(sha256: "ABC", byteCount: -1)
            )
        }
    }

    @Test("Every source failure has one explicit researcher repair route")
    func repairBoundary() {
        for code in ResearchSourceAccessFailureCode.allTestCases {
            let status = ResearchSourceAccessStatus.repairRequired(code)
            #expect(status.state == .repairRequired)
            #expect(status.failure?.code == code)
            #expect(status.failure?.repairAction == .chooseSourceAgain)
            #expect(status.reference == nil)
        }
    }

    @Test("Function snapshots written before Source Reference remain decodable")
    func legacyFunctionSnapshotDecoding() throws {
        let snapshot = ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(function: .develop, target: target()),
            recordKind: .functionEnvelope,
            sourceReference: try ResearchSourceReference(
                identity: .localFile(id: sourceID),
                displayName: "Source.pdf",
                fingerprint: DocumentFingerprint(content: "source")
            )
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["sourceReference"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            ResearchFunctionSnapshot.self,
            from: legacy
        )
        #expect(decoded.sourceReference == nil)
        #expect(decoded.request == snapshot.request)
    }

    private func target() -> ResearchFunctionTarget {
        ResearchFunctionTarget(
            noteID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
                relativePath: "Analysis.md"
            ),
            role: .analysis,
            fingerprint: DocumentFingerprint(content: "# Analysis"),
            title: "Analysis"
        )
    }
}

private extension ResearchSourceAccessFailureCode {
    static let allTestCases: [Self] = [
        .missingBinding,
        .corruptBinding,
        .bookmarkUnavailable,
        .bookmarkStale,
        .sourceMissing,
        .sourceUnreadable,
        .sourceNotRegular,
        .sourceIsSymbolicLink,
        .sourceChanged,
        .zoteroUnavailable,
        .zoteroAttachmentMissing,
        .zoteroIdentityMismatch,
    ]
}
