import Foundation
import Testing
@testable import ScholiumContracts

@Suite("Document paths and capabilities")
struct DocumentPathAndCapabilitiesTests {
    @Test(
        "Markdown paths reject unsafe components",
        arguments: ["", "/Absolute.md", "A//B.md", "./A.md", "A/../B.md", "A\0B.md"]
    )
    func rejectsUnsafePaths(_ raw: String) {
        #expect(throws: MarkdownRelativePathError.self) {
            _ = try MarkdownRelativePath(raw)
        }
    }

    @Test("Backslash remains a literal character")
    func backslashIsLiteral() throws {
        let path = try MarkdownRelativePath(#"Folder\Note.md"#)
        #expect(path.components.count == 1)
        #expect(path.rawValue == #"Folder\Note.md"#)
    }

    @Test("Comparison keys obey volume case and normalization rules")
    func comparisonKeys() throws {
        let uppercase = try MarkdownRelativePath("CAFÉ.md")
        let decomposed = try MarkdownRelativePath("cafe\u{301}.md")
        #expect(VaultPathComparisonKey(
            uppercase,
            caseSensitive: false,
            normalizationSensitive: false
        ) == VaultPathComparisonKey(
            decomposed,
            caseSensitive: false,
            normalizationSensitive: false
        ))
        #expect(VaultPathComparisonKey(
            uppercase,
            caseSensitive: true,
            normalizationSensitive: false
        ) != VaultPathComparisonKey(
            decomposed,
            caseSensitive: true,
            normalizationSensitive: false
        ))
    }

    @Test("A vault comparison policy projects the same rules for Notes and Folders")
    func comparisonPolicy() throws {
        let insensitive = VaultPathComparisonPolicy(
            caseSensitive: false,
            normalizationSensitive: false
        )
        #expect(insensitive.comparisonKey(
            for: try MarkdownRelativePath("Draft/Café.md")
        ) == insensitive.comparisonKey(
            for: try MarkdownRelativePath("draft/Cafe\u{301}.md")
        ))
        #expect(insensitive.comparisonKey(
            for: try VaultRelativeFolderPath("Draft/Café")
        ) == insensitive.comparisonKey(
            for: try VaultRelativeFolderPath("draft/Cafe\u{301}")
        ))

        let sensitive = VaultPathComparisonPolicy(
            caseSensitive: true,
            normalizationSensitive: true
        )
        #expect(sensitive.comparisonKey(
            for: try MarkdownRelativePath("Draft.md")
        ) != sensitive.comparisonKey(
            for: try MarkdownRelativePath("draft.md")
        ))
    }

    @Test(
        "Unresolved identity fails closed",
        arguments: [
            DocumentIdentityResolution.unresolved,
            .pending,
            .ambiguous,
        ]
    )
    func unresolvedFailsClosed(_ identity: DocumentIdentityResolution) {
        let capabilities = DocumentCapabilities(
            role: .topicKnowledge,
            identity: identity,
            isManagedCritique: false
        )
        #expect(!capabilities.canEditSource)
        #expect(!capabilities.canComment)
        #expect(!capabilities.canUseResearchActions)
        #expect(!capabilities.isManagedCritique)
        #expect(capabilities.fileActions.isEmpty)
    }

    @Test("Managed Critique is commentable but not editable, reviewable, duplicable, or agent-writable")
    func critiqueBoundary() {
        let capabilities = DocumentCapabilities(
            role: .draftProject,
            identity: .resolved,
            isManagedCritique: true
        )
        #expect(!capabilities.canEditSource)
        #expect(capabilities.canComment)
        #expect(!capabilities.canUseResearchActions)
        #expect(capabilities.isManagedCritique)
        #expect(!capabilities.allows(.duplicate))
        #expect(capabilities.allows(.moveToSystemTrash))
    }

    @Test("Resolved ordinary Notes expose only current file actions")
    func fileActionMatrix() {
        let capabilities = DocumentCapabilities(
            role: .topicKnowledge,
            identity: .resolved,
            isManagedCritique: false
        )
        #expect(capabilities.fileActions == [
            .duplicate,
            .move,
            .moveToSystemTrash,
        ])
        #expect(capabilities.canComment)
    }

    @Test("Workspace snapshots publish the Application capability projection")
    func workspaceSnapshotCapabilities() {
        let vaultID = UUID()
        let snapshot = WorkspaceNoteSnapshot(
            id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Critiques/Current.md"),
            vaultRole: .draftProject,
            stableIdentity: .resolved(UUID()),
            document: NoteDocument(relativePath: "Critiques/Current.md", rawContent: "Critique"),
            fileMetadata: WorkspaceFileMetadata(
                byteCount: 8,
                creationDate: nil,
                modificationDate: nil
            ),
            graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0)
        )

        #expect(snapshot.capabilities.isManagedCritique)
        #expect(snapshot.capabilities.canComment)
        #expect(!snapshot.capabilities.canEditSource)
        #expect(!snapshot.capabilities.canUseResearchActions)
    }
}
