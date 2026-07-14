import Foundation
import Testing
@testable import ScholiumCore

@Suite("Human Review, comments, Dialogue, and Critique records")
struct ResearchRecordsTests {
    @Test("Human Review display state reflects only the current reviewed fingerprint")
    func humanReviewDisplayState() {
        #expect(HumanReviewDisplayState(isReviewed: false, qualification: nil) == .notReviewed)
        #expect(HumanReviewDisplayState(isReviewed: true, qualification: nil) == .reviewed)
        #expect(HumanReviewDisplayState(isReviewed: true, qualification: .qualified) == .qualified)
        #expect(HumanReviewDisplayState(isReviewed: true, qualification: .unqualified) == .unqualified)
    }

    @Test("Review drafts do not mark a fingerprint reviewed")
    func reviewDraftAndCompletion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = HumanReviewStore(storageURL: fixture.support)
        let noteID = UUID()
        let vaultID = UUID()
        let fingerprint = DocumentFingerprint(content: "# Note\n")

        let draftRecord = try await store.saveDraft(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: "Note.md",
            draft: HumanReviewDraft(
                fingerprint: fingerprint,
                qualification: .qualified,
                reviewNote: "Needs one more source check."
            )
        )
        #expect(draftRecord.latestReview == nil)
        #expect(draftRecord.draft?.qualification == .qualified)

        let completed = try await store.completeReview(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: "Note.md",
            fingerprint: fingerprint,
            qualification: .qualified,
            reviewNote: "Source fidelity and argument reconstruction checked."
        )
        #expect(completed.draft == nil)
        #expect(completed.review(for: fingerprint)?.qualification == .qualified)
        #expect(!completed.hasChangedSinceReview(current: fingerprint))
        #expect(completed.hasChangedSinceReview(current: DocumentFingerprint(content: "Changed")))
    }

    @Test("A completed Review requires a verdict and a concise nonempty note")
    func reviewValidation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = HumanReviewStore(storageURL: fixture.support)
        let noteID = UUID()
        let vaultID = UUID()
        let fingerprint = DocumentFingerprint(content: "note")

        await #expect(throws: HumanReviewError.self) {
            try await store.completeReview(
                noteID: noteID,
                vaultID: vaultID,
                relativePath: "Note.md",
                fingerprint: fingerprint,
                qualification: nil,
                reviewNote: "Assessment"
            )
        }
        await #expect(throws: HumanReviewError.self) {
            try await store.completeReview(
                noteID: noteID,
                vaultID: vaultID,
                relativePath: "Note.md",
                fingerprint: fingerprint,
                qualification: .unqualified,
                reviewNote: "   "
            )
        }
        await #expect(throws: HumanReviewError.self) {
            try await store.completeReview(
                noteID: noteID,
                vaultID: vaultID,
                relativePath: "Note.md",
                fingerprint: fingerprint,
                qualification: .unqualified,
                reviewNote: String(repeating: "x", count: 501)
            )
        }
    }

    @Test("Corrupt research-record files remain untouched and block replacement writes")
    func corruptResearchRecordStoresAreReadOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let corrupt = Data("{not valid json".utf8)

        let reviewDirectory = fixture.support.appendingPathComponent("review", isDirectory: true)
        try FileManager.default.createDirectory(at: reviewDirectory, withIntermediateDirectories: true)
        let reviewURL = reviewDirectory.appendingPathComponent("human-reviews.json")
        try corrupt.write(to: reviewURL)
        let reviewStore = HumanReviewStore(storageURL: reviewDirectory)
        #expect(await reviewStore.healthError() != nil)
        await #expect(throws: ResearchRecordStoreError.self) {
            _ = try await reviewStore.addComment(
                noteID: UUID(),
                vaultID: UUID(),
                relativePath: "Note.md",
                comment: ResearcherComment(text: "Do not overwrite the corrupt store.")
            )
        }
        await #expect(throws: ResearchRecordStoreError.self) {
            _ = try await reviewStore.purge(noteID: UUID())
        }
        #expect(try Data(contentsOf: reviewURL) == corrupt)

        let dialogueDirectory = fixture.support.appendingPathComponent("dialogue", isDirectory: true)
        try FileManager.default.createDirectory(at: dialogueDirectory, withIntermediateDirectories: true)
        let dialogueURL = dialogueDirectory.appendingPathComponent("dialogue.json")
        try corrupt.write(to: dialogueURL)
        let dialogueStore = DialogueStore(storageURL: dialogueDirectory)
        #expect(await dialogueStore.healthError() != nil)
        let reference = DialogueNoteReference(
            noteID: UUID(),
            vaultID: UUID(),
            vaultName: "Analyses",
            title: "Analysis",
            relativePath: "Analysis.md",
            fingerprint: DocumentFingerprint(content: "analysis")
        )
        await #expect(throws: ResearchRecordStoreError.self) {
            _ = try await dialogueStore.save(DialogueEntry(
                triptychID: UUID(),
                instruction: "Inspect this note.",
                selectedNotes: [reference],
                includedComments: [],
                generatedPrompt: "Prompt",
                checkpointID: UUID()
            ))
        }
        await #expect(throws: ResearchRecordStoreError.self) {
            _ = try await dialogueStore.purgeEntries(containing: reference.noteID)
        }
        #expect(try Data(contentsOf: dialogueURL) == corrupt)

        let control = fixture.root.appendingPathComponent(".scholium", isDirectory: true)
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        let critiqueURL = control.appendingPathComponent("critiques.json")
        try corrupt.write(to: critiqueURL)
        let critiqueStore = CritiqueRegistry(controlURL: control)
        #expect(await critiqueStore.healthError() != nil)
        await #expect(throws: ResearchRecordStoreError.self) {
            _ = try await critiqueStore.save(CritiqueAssociation(
                workNoteID: UUID(),
                workRelativePath: "Works/Paper.md",
                targetFingerprint: DocumentFingerprint(content: "paper"),
                critiqueRelativePath: "Critiques/Paper Critique.md"
            ))
        }
        await #expect(throws: ResearchRecordStoreError.self) {
            _ = try await critiqueStore.purgeAssociations(
                noteID: UUID(),
                relativePath: "Critiques/Paper Critique.md"
            )
        }
        #expect(try Data(contentsOf: critiqueURL) == corrupt)
    }

    @Test("Failed persistence does not publish uncommitted research-record state")
    func failedPersistenceLeavesMemoryUnchanged() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let blocked = fixture.root.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blocked)

        let noteID = UUID()
        let reviewStore = HumanReviewStore(storageURL: blocked)
        await #expect(throws: (any Error).self) {
            _ = try await reviewStore.addComment(
                noteID: noteID,
                vaultID: UUID(),
                relativePath: "Note.md",
                comment: ResearcherComment(text: "Must not appear in memory.")
            )
        }
        #expect(await reviewStore.record(noteID: noteID) == nil)

        let reference = DialogueNoteReference(
            noteID: UUID(),
            vaultID: UUID(),
            vaultName: "Topics",
            title: "Topic",
            relativePath: "Topic.md",
            fingerprint: DocumentFingerprint(content: "topic")
        )
        let dialogueStore = DialogueStore(storageURL: blocked)
        let dialogue = DialogueEntry(
            triptychID: UUID(),
            instruction: "Inspect this topic.",
            selectedNotes: [reference],
            includedComments: [],
            generatedPrompt: "Prompt",
            checkpointID: UUID()
        )
        await #expect(throws: (any Error).self) {
            _ = try await dialogueStore.save(dialogue)
        }
        await #expect(throws: DialogueError.self) {
            _ = try await dialogueStore.entry(id: dialogue.id)
        }

        let critiqueStore = CritiqueRegistry(controlURL: blocked)
        let association = CritiqueAssociation(
            workNoteID: UUID(),
            workRelativePath: "Paper.md",
            targetFingerprint: DocumentFingerprint(content: "paper"),
            critiqueRelativePath: "Critiques/Paper Critique.md"
        )
        await #expect(throws: (any Error).self) {
            _ = try await critiqueStore.save(association)
        }
        #expect(await critiqueStore.association(workNoteID: association.workNoteID) == nil)
    }

    @Test("Permanent deletion purges Review, shared Dialogue, and Critique associations")
    func permanentDeletionPurgesAppOwnedRecords() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        let otherNoteID = UUID()
        let vaultID = UUID()
        let fingerprint = DocumentFingerprint(content: "# Work\n")

        let reviewStore = HumanReviewStore(
            storageURL: fixture.support.appendingPathComponent("review", isDirectory: true)
        )
        _ = try await reviewStore.addComment(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: "Trash/Work.md",
            comment: ResearcherComment(text: "Private comment")
        )

        let deletedReference = DialogueNoteReference(
            noteID: noteID,
            vaultID: vaultID,
            vaultName: "Works",
            title: "Work",
            relativePath: "Trash/Work.md",
            fingerprint: fingerprint
        )
        let retainedReference = DialogueNoteReference(
            noteID: otherNoteID,
            vaultID: vaultID,
            vaultName: "Works",
            title: "Other",
            relativePath: "Other.md",
            fingerprint: DocumentFingerprint(content: "# Other\n")
        )
        let dialogueStore = DialogueStore(
            storageURL: fixture.support.appendingPathComponent("dialogue", isDirectory: true)
        )
        let shared = DialogueEntry(
            triptychID: UUID(),
            instruction: "Compare these notes.",
            selectedNotes: [deletedReference, retainedReference],
            includedComments: [],
            generatedPrompt: "Contains private deleted-note context.",
            checkpointID: UUID()
        )
        _ = try await dialogueStore.save(shared)

        let critiqueStore = CritiqueRegistry(controlURL: fixture.root.appendingPathComponent(".scholium"))
        let association = CritiqueAssociation(
            workNoteID: noteID,
            workRelativePath: "Trash/Work.md",
            targetFingerprint: fingerprint,
            critiqueRelativePath: "Critiques/Work Critique.md"
        )
        _ = try await critiqueStore.save(association)

        #expect(try await reviewStore.purge(noteID: noteID)?.id == noteID)
        #expect(try await dialogueStore.purgeEntries(containing: noteID).map(\.id) == [shared.id])
        #expect(try await critiqueStore.purgeAssociations(
            noteID: noteID,
            relativePath: "Trash/Work.md"
        ).map(\.id) == [association.id])

        #expect(await reviewStore.record(noteID: noteID) == nil)
        #expect(await dialogueStore.entries(noteID: noteID).isEmpty)
        #expect(await dialogueStore.entries(noteID: otherNoteID).isEmpty)
        #expect(await critiqueStore.association(workNoteID: noteID) == nil)
    }

    @Test("Anchored comments reattach only at one reliable location")
    func commentReattachment() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = HumanReviewStore(storageURL: fixture.support)
        let noteID = UUID()
        let vaultID = UUID()
        let original = NoteDocument(relativePath: "Note.md", rawContent: "Intro\nThe claim matters.\nEnd\n")
        let quotation = "claim"
        let range = try #require(original.rawContent.range(of: quotation))
        let utf8Start = Data(original.rawContent[..<range.lowerBound].utf8).count
        let utf8End = Data(original.rawContent[..<range.upperBound].utf8).count
        let anchor = ResearcherCommentAnchor(
            fingerprint: original.fingerprint,
            utf8Range: utf8Start..<utf8End,
            utf16Range: range.lowerBound.utf16Offset(in: original.rawContent)..<range.upperBound.utf16Offset(in: original.rawContent),
            line: 2,
            endLine: 2,
            quotation: quotation,
            contextBefore: "The ",
            contextAfter: " matters"
        )
        _ = try await store.addComment(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: "Note.md",
            comment: ResearcherComment(text: "Clarify the support.", anchor: anchor)
        )

        let moved = NoteDocument(relativePath: "Note.md", rawContent: "New preface\nIntro\nThe claim matters.\nEnd\n")
        try await store.reattachComments(noteID: noteID, to: moved)
        var record = try #require(await store.record(noteID: noteID))
        #expect(record.comments[0].anchor?.state == .attached)
        #expect(record.comments[0].anchor?.line == 3)

        let ambiguous = NoteDocument(
            relativePath: "Note.md",
            rawContent: "The claim matters.\nThe claim matters.\n"
        )
        try await store.reattachComments(noteID: noteID, to: ambiguous)
        record = try #require(await store.record(noteID: noteID))
        #expect(record.comments[0].anchor?.state == .needsReattachment)
    }

    @Test("Comment anchors preserve full-file Unicode ranges and visible selection")
    func exactCommentAnchor() throws {
        let source = "---\r\ntitle: 測試\r\n---\r\n# Claim\r\nA 🧠 **reason** matters.\r\n"
        let document = NoteDocument(relativePath: "Note.md", rawContent: source)
        let selected = "reason"
        let range = try #require(source.range(of: selected))
        let lower = range.lowerBound.utf16Offset(in: source)
        let upper = range.upperBound.utf16Offset(in: source)
        let anchor = try #require(ResearcherCommentAnchorBuilder.anchor(
            in: source,
            fingerprint: document.fingerprint,
            utf16Range: lower..<upper,
            selectedText: selected
        ))

        #expect(anchor.fingerprint == document.fingerprint)
        #expect(anchor.line == 5)
        #expect(anchor.endLine == 5)
        #expect(anchor.quotation == selected)
        #expect(anchor.utf16Range == lower..<upper)
        #expect(Data(source.utf8)[anchor.utf8Range] == Data(selected.utf8))
        #expect(anchor.contextBefore.hasSuffix("A 🧠 **"))
        #expect(anchor.contextAfter.hasPrefix("** matters."))
    }

    @Test("Read-mode selections map across Markdown punctuation to one exact source range")
    func renderedCommentAnchor() throws {
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: "---\ntitle: Note\n---\nA **strong** claim matters.\n"
        )
        let anchor = try #require(ResearcherCommentAnchorBuilder.anchor(
            forRenderedQuotation: "A strong claim matters.",
            in: document
        ))

        #expect(anchor.line == 4)
        #expect(anchor.quotation == "A **strong** claim matters.")
        #expect(anchor.selectedText == "A strong claim matters.")
        let bytes = Data(document.rawContent.utf8)[anchor.utf8Range]
        #expect(String(decoding: bytes, as: UTF8.self) == "A **strong** claim matters.")
    }

    @Test("Source comments derive visible marked-up text without global quotation guessing")
    func sourceCommentRenderedQuotation() throws {
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: "**Repeated claim.**\n\nRepeated claim.\n"
        )
        let sourceSelection = try #require(document.rawContent.range(of: "**Repeated claim.**"))
        let sourceLower = sourceSelection.lowerBound.utf16Offset(in: document.rawContent)
        let sourceUpper = sourceSelection.upperBound.utf16Offset(in: document.rawContent)
        let anchor = try #require(ResearcherCommentAnchorBuilder.anchor(
            in: document.rawContent,
            fingerprint: document.fingerprint,
            utf16Range: sourceLower..<sourceUpper
        ))

        #expect(anchor.quotation == "**Repeated claim.**")
        #expect(ResearcherCommentAnchorBuilder.renderedQuotation(
            for: anchor,
            in: document
        ) == "Repeated claim.")
    }

    @Test("Read-mode context disambiguates repeated rendered quotations without guessing")
    func renderedCommentContextDisambiguation() throws {
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: "First **claim** here.\n\nSecond **claim** there.\n"
        )
        #expect(ResearcherCommentAnchorBuilder.anchor(
            forRenderedQuotation: "claim",
            in: document
        ) == nil)

        let anchor = try #require(ResearcherCommentAnchorBuilder.anchor(
            forRenderedQuotation: "claim",
            contextBefore: "Second ",
            contextAfter: " there.",
            in: document
        ))
        #expect(anchor.line == 3)
        #expect(anchor.quotation == "claim")
    }

    @Test("Comments can be edited, resolved, reopened, reattached, and deleted without Review")
    func independentCommentLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = HumanReviewStore(storageURL: fixture.support)
        let noteID = UUID()
        let vaultID = UUID()
        let document = NoteDocument(relativePath: "Work.md", rawContent: "# Work\nA claim.\n")
        let range = try #require(document.rawContent.range(of: "claim"))
        let rangeLower = range.lowerBound.utf16Offset(in: document.rawContent)
        let rangeUpper = range.upperBound.utf16Offset(in: document.rawContent)
        let anchor = try #require(ResearcherCommentAnchorBuilder.anchor(
            in: document.rawContent,
            fingerprint: document.fingerprint,
            utf16Range: rangeLower..<rangeUpper
        ))
        let comment = ResearcherComment(text: "Clarify this.", anchor: anchor)

        _ = try await store.addComment(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: document.relativePath,
            comment: comment
        )
        try await store.updateCommentText(
            noteID: noteID,
            commentID: comment.id,
            text: "Clarify the premise."
        )
        try await store.setCommentResolvedByResearcher(noteID: noteID, commentID: comment.id, resolved: true)
        var record = try #require(await store.record(noteID: noteID))
        #expect(record.latestReview == nil)
        #expect(record.comments[0].text == "Clarify the premise.")
        #expect(record.comments[0].resolvedAt != nil)

        try await store.setCommentResolvedByResearcher(noteID: noteID, commentID: comment.id, resolved: false)
        let replacement = NoteDocument(relativePath: "Work.md", rawContent: "# Work\nA revised claim.\n")
        let replacementRange = try #require(replacement.rawContent.range(of: "revised claim"))
        let replacementLower = replacementRange.lowerBound.utf16Offset(in: replacement.rawContent)
        let replacementUpper = replacementRange.upperBound.utf16Offset(in: replacement.rawContent)
        let replacementAnchor = try #require(ResearcherCommentAnchorBuilder.anchor(
            in: replacement.rawContent,
            fingerprint: replacement.fingerprint,
            utf16Range: replacementLower..<replacementUpper
        ))
        try await store.reattachComment(
            noteID: noteID,
            commentID: comment.id,
            to: replacementAnchor
        )
        record = try #require(await store.record(noteID: noteID))
        #expect(record.comments[0].resolvedAt == nil)
        #expect(record.comments[0].anchor?.quotation == "revised claim")
        #expect(record.comments[0].anchor?.fingerprint == replacement.fingerprint)

        try await store.removeComment(noteID: noteID, commentID: comment.id)
        #expect((await store.record(noteID: noteID))?.comments.isEmpty == true)
    }

    @Test("Human Review and Dialogue path migration is idempotent and preserves historical prompt")
    func appOwnedPathMigration() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        let vaultID = UUID()
        let reviewStore = HumanReviewStore(storageURL: fixture.support.appendingPathComponent("review"))
        _ = try await reviewStore.addComment(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: "Old.md",
            comment: ResearcherComment(text: "Keep this comment.")
        )
        #expect(try await reviewStore.migratePathIfPresent(
            noteID: noteID,
            vaultID: vaultID,
            from: "Old.md",
            to: "Folder/New.md"
        ))
        #expect(try await reviewStore.migratePathIfPresent(
            noteID: noteID,
            vaultID: vaultID,
            from: "Old.md",
            to: "Folder/New.md"
        ) == false)

        let reference = DialogueNoteReference(
            noteID: noteID,
            vaultID: vaultID,
            vaultName: "Works",
            title: "Work",
            relativePath: "Old.md",
            fingerprint: DocumentFingerprint(content: "source")
        )
        let included = DialogueIncludedComment(
            note: reference,
            comment: ResearcherComment(text: "Revise this.")
        )
        let dialogueStore = DialogueStore(storageURL: fixture.support.appendingPathComponent("dialogue"))
        let followUp = DialogueFollowUpComment(
            text: "Preserve this follow-up.",
            noteID: noteID,
            commentID: included.comment.id
        )
        let response = DialogueReply(
            agentName: "Codex",
            text: "Preserve this response.",
            noteID: noteID,
            commentID: included.comment.id
        )
        let entry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Revise.",
            selectedNotes: [reference],
            includedComments: [included],
            generatedPrompt: "Historical path: Old.md",
            checkpointID: UUID(),
            followUpComments: [followUp],
            replies: [response]
        )
        _ = try await dialogueStore.save(entry)
        #expect(try await dialogueStore.migratePathIfPresent(
            noteID: noteID,
            vaultID: vaultID,
            from: "Old.md",
            to: "Folder/New.md"
        ) == 1)
        #expect(try await dialogueStore.migratePathIfPresent(
            noteID: noteID,
            vaultID: vaultID,
            from: "Old.md",
            to: "Folder/New.md"
        ) == 0)
        let migrated = try await dialogueStore.entry(id: entry.id)
        #expect(migrated.selectedNotes[0].relativePath == "Folder/New.md")
        #expect(migrated.includedComments[0].note?.relativePath == "Folder/New.md")
        #expect(migrated.generatedPrompt == "Historical path: Old.md")
        #expect(migrated.followUpComments == [followUp])
        #expect(migrated.replies == [response])
    }

    @Test("One Dialogue entry appears in every selected note history")
    func multiNoteDialogueAndReplies() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = DialogueStore(storageURL: fixture.support)
        let first = DialogueNoteReference(
            noteID: UUID(),
            vaultID: UUID(),
            vaultName: "Analyses",
            title: "Paper A",
            relativePath: "Paper A.md",
            fingerprint: DocumentFingerprint(content: "A")
        )
        let second = DialogueNoteReference(
            noteID: UUID(),
            vaultID: UUID(),
            vaultName: "Topics",
            title: "Topic B",
            relativePath: "Topic B.md",
            fingerprint: DocumentFingerprint(content: "B"),
            kind: "Concept"
        )
        let firstComment = ResearcherComment(
            text: "Clarify the interpretation in Paper A.",
            anchor: ResearcherCommentAnchor(
                fingerprint: first.fingerprint,
                utf8Range: 0..<1,
                utf16Range: 0..<1,
                line: 12,
                endLine: 12,
                quotation: "A"
            )
        )
        let secondComment = ResearcherComment(
            text: "Connect the distinction in Topic B.",
            anchor: ResearcherCommentAnchor(
                fingerprint: second.fingerprint,
                utf8Range: 0..<1,
                utf16Range: 0..<1,
                line: 12,
                endLine: 12,
                quotation: "B"
            )
        )
        let includedComments = [
            DialogueIncludedComment(note: first, comment: firstComment),
            DialogueIncludedComment(note: second, comment: secondComment),
        ]
        let prompt = DialoguePromptBuilder.build(DialoguePromptContext(
            instruction: "Revise the relevant Triptych notes.",
            selectedNotes: [first, second],
            comments: includedComments,
            triptychSummary: "Analyses, Topics, and Works belong to the Triptych named Ethics.",
            linkedNoteSummary: "Topic B neutrally links to Paper A; this is not evidence.",
            requestedDestination: "Update relevant notes in Topics when warranted."
        ))
        let entry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Revise the relevant Triptych notes.",
            selectedNotes: [first, second],
            includedComments: includedComments,
            generatedPrompt: prompt,
            checkpointID: UUID(),
            requestedDestination: "Update relevant notes in Topics when warranted.",
            linkedNoteSummary: "Topic B neutrally links to Paper A; this is not evidence."
        )
        _ = try await store.save(entry)
        #expect((await store.entries(noteID: first.noteID)).map(\.id) == [entry.id])
        #expect((await store.entries(noteID: second.noteID)).map(\.id) == [entry.id])
        #expect(prompt.contains("directly modify other relevant Triptych files"))
        #expect(!prompt.localizedCaseInsensitiveContains("proposal"))
        #expect(prompt.localizedCaseInsensitiveContains("academic change summary"))
        #expect(prompt.localizedCaseInsensitiveContains("unresolved question"))
        #expect(prompt.localizedCaseInsensitiveContains("researcher review"))
        #expect(prompt.contains("Kind: Concept"))
        #expect(prompt.contains("Triptych context:"))
        #expect(prompt.contains("Relevant linked-note context:"))
        #expect(prompt.contains("Requested destination:"))
        #expect(entry.requestedDestination == "Update relevant notes in Topics when warranted.")
        #expect(prompt.contains("""
        - Note: Paper A
          Note ID: \(first.noteID.uuidString)
          Vault: Analyses
          Path: Paper A.md
          Location: Lines 12–12
          Comment: Clarify the interpretation in Paper A.
        """))
        #expect(prompt.contains("""
        - Note: Topic B
          Note ID: \(second.noteID.uuidString)
          Vault: Topics
          Path: Topic B.md
          Location: Lines 12–12
          Comment: Connect the distinction in Topic B.
        """))

        let updated = try await store.appendReply(
            DialogueReply(
                agentName: "Codex",
                text: "I revised the source distinction.",
                noteID: first.noteID,
                commentID: firstComment.id
            ),
            to: entry.id
        )
        #expect(updated.replies.count == 1)

        await #expect(throws: DialogueError.self) {
            _ = try await store.appendReply(
                DialogueReply(
                    agentName: "Codex",
                    text: "This target pair is inconsistent.",
                    noteID: second.noteID,
                    commentID: firstComment.id
                ),
                to: entry.id
            )
        }
        await #expect(throws: DialogueError.self) {
            _ = try await store.appendReply(
                DialogueReply(agentName: "", text: "Unattributed reply"),
                to: entry.id
            )
        }
        let duplicate = DialogueReply(agentName: "Codex", text: "One durable reply")
        _ = try await store.appendReply(duplicate, to: entry.id)
        await #expect(throws: DialogueError.self) {
            _ = try await store.appendReply(duplicate, to: entry.id)
        }
    }

    @Test("Dialogue preserves chronological researcher follow-ups and attributed agent responses")
    func dialogueFollowUpChronologyAndPersistence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = DialogueStore(storageURL: fixture.support)
        let note = DialogueNoteReference(
            noteID: UUID(),
            vaultID: UUID(),
            vaultName: "Topics",
            title: "Normative Force",
            relativePath: "Normative Force.md",
            fingerprint: DocumentFingerprint(content: "Topic")
        )
        let included = DialogueIncludedComment(
            note: note,
            comment: ResearcherComment(text: "Separate textual support from reconstruction.")
        )
        let entry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Clarify the argument without overstating the source.",
            selectedNotes: [note],
            includedComments: [included],
            generatedPrompt: "",
            checkpointID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        _ = try await store.save(entry)

        let response = DialogueReply(
            agentName: "Codex",
            text: "I separated the textual claim from the reconstruction.",
            noteID: note.noteID,
            createdAt: Date(timeIntervalSince1970: 1_010)
        )
        let followUp = DialogueFollowUpComment(
            text: "State the remaining interpretive uncertainty explicitly.",
            noteID: note.noteID,
            commentID: included.comment.id,
            createdAt: Date(timeIntervalSince1970: 1_020)
        )
        let secondResponse = DialogueReply(
            agentName: "Local Agent",
            text: "The note now identifies the unresolved scope question.",
            noteID: note.noteID,
            commentID: included.comment.id,
            createdAt: Date(timeIntervalSince1970: 1_030)
        )
        _ = try await store.appendReply(response, to: entry.id)
        _ = try await store.appendFollowUpComment(followUp, to: entry.id)
        let updated = try await store.appendReply(secondResponse, to: entry.id)

        #expect(updated.followUpComments == [followUp])
        #expect(updated.replies == [response, secondResponse])
        #expect(updated.chronologicalTurns == [
            .agent(response),
            .researcher(followUp),
            .agent(secondResponse),
        ])

        let reopened = DialogueStore(storageURL: fixture.support)
        let persisted = try await reopened.entry(id: entry.id)
        #expect(persisted.chronologicalTurns == updated.chronologicalTurns)

        await #expect(throws: DialogueError.self) {
            _ = try await store.appendFollowUpComment(followUp, to: entry.id)
        }
        await #expect(throws: DialogueError.self) {
            _ = try await store.appendFollowUpComment(
                DialogueFollowUpComment(text: "   "),
                to: entry.id
            )
        }
        await #expect(throws: DialogueError.self) {
            _ = try await store.appendFollowUpComment(
                DialogueFollowUpComment(text: "Wrong target", noteID: UUID()),
                to: entry.id
            )
        }
    }

    @Test("Dialogue entries written before source-bound comments still decode")
    func legacyDialogueCommentsDecode() throws {
        let note = DialogueNoteReference(
            noteID: UUID(),
            vaultID: UUID(),
            vaultName: "Analyses",
            title: "Legacy Analysis",
            relativePath: "Legacy Analysis.md",
            fingerprint: DocumentFingerprint(content: "legacy")
        )
        let comment = ResearcherComment(text: "Legacy comment without an owning-note field.")
        let entry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Revisit this note.",
            selectedNotes: [note],
            includedComments: [DialogueIncludedComment(note: note, comment: comment)],
            generatedPrompt: "Legacy prompt",
            checkpointID: UUID()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(entry)) as? [String: Any]
        )
        object.removeValue(forKey: "followUpComments")
        object["includedComments"] = [
            try JSONSerialization.jsonObject(with: encoder.encode(comment)),
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DialogueEntry.self, from: legacyData)
        #expect(decoded.followUpComments.isEmpty)

        #expect(decoded.includedComments.count == 1)
        #expect(decoded.includedComments[0].comment.id == comment.id)
        #expect(decoded.includedComments[0].comment.text == comment.text)
        #expect(decoded.includedComments[0].note == note)

        let secondNote = DialogueNoteReference(
            noteID: UUID(),
            vaultID: UUID(),
            vaultName: "Topics",
            title: "Legacy Topic",
            relativePath: "Legacy Topic.md",
            fingerprint: DocumentFingerprint(content: "topic")
        )
        let multiEntry = DialogueEntry(
            triptychID: entry.triptychID,
            instruction: entry.instruction,
            selectedNotes: [note, secondNote],
            includedComments: [DialogueIncludedComment(note: note, comment: comment)],
            generatedPrompt: entry.generatedPrompt,
            checkpointID: entry.checkpointID
        )
        object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(multiEntry)) as? [String: Any]
        )
        object["includedComments"] = [
            try JSONSerialization.jsonObject(with: encoder.encode(comment)),
        ]
        let legacyMultiData = try JSONSerialization.data(withJSONObject: object)
        let decodedMulti = try decoder.decode(DialogueEntry.self, from: legacyMultiData)
        #expect(decodedMulti.includedComments[0].note == nil)
    }

    @Test("Critique association is portable and remains bound to the Work revision")
    func critiqueAssociation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = fixture.root.appendingPathComponent(".scholium", isDirectory: true)
        let registry = CritiqueRegistry(controlURL: control)
        let workID = UUID()
        let association = CritiqueAssociation(
            workNoteID: workID,
            workRelativePath: "Drafts/Paper.md",
            targetFingerprint: DocumentFingerprint(content: "draft"),
            critiqueRelativePath: "Critiques/Paper Critique.md"
        )
        try await registry.save(association)

        let reopened = CritiqueRegistry(controlURL: control)
        let loaded = try #require(await reopened.association(workNoteID: workID))
        #expect(loaded.critiqueRelativePath == "Critiques/Paper Critique.md")
        #expect(loaded.targetFingerprint == association.targetFingerprint)

        _ = try await reopened.movePath(
            noteID: workID,
            from: "Drafts/Paper.md",
            to: "Drafts/Renamed Paper.md"
        )
        _ = try await reopened.movePath(
            noteID: UUID(),
            from: "Critiques/Paper Critique.md",
            to: "Critiques/Renamed Critique.md"
        )
        let moved = try #require(await reopened.association(workNoteID: workID))
        #expect(moved.workRelativePath == "Drafts/Renamed Paper.md")
        #expect(moved.critiqueRelativePath == "Critiques/Renamed Critique.md")
        #expect(moved.targetFingerprint == association.targetFingerprint)
    }

    @Test("Repeated Critique requests keep one association and bind each round to the current Work")
    func repeatedCritiqueRequests() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let control = fixture.root.appendingPathComponent(".scholium", isDirectory: true)
        let registry = CritiqueRegistry(controlURL: control)
        let workID = UUID()
        let first = DocumentFingerprint(content: "first")
        let second = DocumentFingerprint(content: "second")
        let firstCheckpoint = UUID()
        let secondCheckpoint = UUID()

        let created = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: "Drafts/Paper.md",
            targetFingerprint: first,
            critiqueRelativePath: "Critiques/Paper Critique.md",
            checkpointID: firstCheckpoint,
            scope: .overall
        )
        let updated = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: "Drafts/Paper.md",
            targetFingerprint: second,
            critiqueRelativePath: created.critiqueRelativePath,
            checkpointID: secondCheckpoint,
            scope: .specific
        )

        #expect(updated.id == created.id)
        #expect(updated.targetFingerprint == second)
        #expect(updated.rounds.count == 2)
        #expect(updated.rounds.map(\.checkpointID) == [firstCheckpoint, secondCheckpoint])
        #expect(updated.rounds.map(\.scope) == [.overall, .specific])

        let reopened = CritiqueRegistry(controlURL: control)
        let persisted = try #require(await reopened.association(workNoteID: workID))
        #expect(persisted.id == created.id)
        #expect(persisted.targetFingerprint == second)
        #expect(persisted.rounds.count == 2)
        #expect(await reopened.association(critiqueRelativePath: created.critiqueRelativePath)?.id == created.id)
    }

    @Test("Critique scaffold exposes agent provenance and exact target metadata")
    func critiqueScaffoldAndTargetedMetadataUpdate() throws {
        let first = DocumentFingerprint(content: "first")
        let second = DocumentFingerprint(content: "second")
        let scaffold = CritiqueDocumentContract.scaffold(
            title: "Paper: A \"Test\"",
            targetRelativePath: "Drafts/Paper: A.md",
            targetFingerprint: first,
            scope: .overall,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let document = NoteDocument(relativePath: "Critiques/Paper Critique.md", rawContent: scaffold)
        let metadata = CritiqueDocumentContract.metadata(in: document)
        #expect(document.validationWarnings.isEmpty)
        #expect(metadata.isAgentAttributed)
        #expect(metadata.targetRelativePath == "Drafts/Paper: A.md")
        #expect(metadata.targetFingerprintSHA256 == first.sha256)
        #expect(metadata.scope == .overall)

        let updatedSource = try document.applying(
            .frontmatter(CritiqueDocumentContract.requestEdits(
                targetRelativePath: "Drafts/Paper: A.md",
                targetFingerprint: second,
                scope: .both,
                requestedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )),
            timestampKey: nil
        )
        let updated = NoteDocument(relativePath: document.relativePath, rawContent: updatedSource)
        #expect(updated.body == document.body)
        #expect(updated.rawFrontmatter?.contains("critique_target_fingerprint: \(second.sha256)") == true)
        #expect(CritiqueDocumentContract.metadata(in: updated).targetFingerprintSHA256 == second.sha256)
        #expect(CritiqueDocumentContract.metadata(in: updated).scope == .both)

        let customSource = scaffold.replacingOccurrences(
            of: "critique_authorship: agent\n",
            with: "# keep this comment\ncustom:\n  nested: \"a: b\"\ncritique_authorship: agent\n"
        )
        let custom = NoteDocument(relativePath: document.relativePath, rawContent: customSource)
        let customUpdated = try custom.applying(
            .frontmatter(CritiqueDocumentContract.requestEdits(
                targetRelativePath: "Drafts/Paper: A.md",
                targetFingerprint: second,
                scope: .both
            )),
            timestampKey: nil
        )
        #expect(customUpdated.contains("# keep this comment\ncustom:\n  nested: \"a: b\"\ncritique_authorship: agent\n"))
    }

    @Test("Adding Critique metadata to a legacy file preserves its exact existing bytes")
    func legacyCritiqueMetadataPrefix() throws {
        let existing = "\u{FEFF}# Legacy Critique\r\n\r\nKeep **all** of this.\r\n"
        let document = NoteDocument(relativePath: "Critiques/Legacy.md", rawContent: existing)
        let fingerprint = DocumentFingerprint(content: "target")
        let migrated = try CritiqueDocumentContract.sourceByAddingRequestMetadata(
            to: document,
            targetRelativePath: "Drafts/Target.md",
            targetFingerprint: fingerprint,
            scope: .specific,
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(migrated.hasPrefix("\u{FEFF}---\r\n"))
        #expect(migrated.hasSuffix(String(existing.dropFirst())))
        let parsed = NoteDocument(relativePath: document.relativePath, rawContent: migrated)
        #expect(parsed.validationWarnings.isEmpty)
        #expect(parsed.body == String(existing.dropFirst()))
        #expect(CritiqueDocumentContract.metadata(in: parsed).targetFingerprintSHA256 == fingerprint.sha256)
    }

    @Test("Critique findings resolve explicit lines, headings, and unique quotations")
    func critiqueFindingNavigation() throws {
        let work = NoteDocument(
            relativePath: "Drafts/Paper.md",
            rawContent: "# Paper\n\n## Source Support\n\nA uniquely quoted claim appears here.\n"
        )
        let critiqueSource = """
        ---
        critique_authorship: agent
        critique_target_path: Drafts/Paper.md
        critique_target_fingerprint: \(work.fingerprint.sha256)
        critique_requested_at: "2026-07-13T00:00:00Z"
        critique_request_scope: "Both"
        ---
        # Critique

        ## Specific Findings

        ### Traced — Direct locator
        - Target Work: Drafts/Paper.md
        - Target fingerprint: \(work.fingerprint.sha256)
        - Target line: 5
        - Target quotation: "A uniquely quoted claim appears here."

        ### Disputed: Heading locator
        - Target heading: Source Support

        ### Beyond Sources — Quotation locator
        - Target quotation: A uniquely quoted claim appears here.

        ## Materials Consulted and Limitations
        """
        let critique = NoteDocument(relativePath: "Critiques/Paper Critique.md", rawContent: critiqueSource)
        let findings = CritiqueDocumentContract.findings(in: critique)

        #expect(findings.count == 3)
        #expect(findings.map(\.judgment) == [.traced, .disputed, .beyondSources])
        #expect(findings[0].targetRelativePath == work.relativePath)
        #expect(findings[0].targetFingerprintSHA256 == work.fingerprint.sha256)
        #expect(findings[0].resolvedTargetLine(in: work) == 5)
        #expect(findings[1].resolvedTargetLine(in: work) == 3)
        #expect(findings[2].resolvedTargetLine(in: work) == 5)

        let ambiguousWork = NoteDocument(
            relativePath: "Drafts/Ambiguous.md",
            rawContent: "Repeated quotation.\nRepeated quotation.\n"
        )
        let ambiguous = CritiqueFinding(
            judgment: .untraced,
            title: "Ambiguous quotation",
            critiqueSourceLine: 1,
            targetQuotation: "Repeated quotation."
        )
        let invalidLine = CritiqueFinding(
            judgment: .untraced,
            title: "Invalid line",
            critiqueSourceLine: 1,
            targetLine: 99
        )
        #expect(ambiguous.resolvedTargetLine(in: ambiguousWork) == nil)
        #expect(invalidLine.resolvedTargetLine(in: ambiguousWork) == nil)
    }

    @Test("Ordinary moves cannot cross the Critiques boundary")
    func critiquePlacement() throws {
        try CritiquePlacement.validateOrdinaryMove(
            from: "Critiques/Paper Critique.md",
            to: "Critiques/Renamed Critique.md"
        )
        try CritiquePlacement.validateOrdinaryMove(
            from: "Set Aside/Critiques/Paper Critique.md",
            to: "Critiques/Paper Critique.md"
        )
        #expect(throws: CritiquePlacementError.self) {
            try CritiquePlacement.validateOrdinaryMove(
                from: "Critiques/Paper Critique.md",
                to: "Drafts/Paper Critique.md"
            )
        }
        #expect(throws: CritiquePlacementError.self) {
            try CritiquePlacement.validateOrdinaryMove(
                from: "Drafts/Paper.md",
                to: "Critiques/Paper.md"
            )
        }
    }

    private struct Fixture {
        let root: URL
        let support: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-Research-Records-\(UUID().uuidString)", isDirectory: true)
            support = root.appendingPathComponent("Application Support", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
