import Foundation
import Testing
import ScholiumContracts
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

    @Test("Live Human Review values match their persisted delivery projection")
    func liveReviewMatchesPersistedProjection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        let vaultID = UUID()
        let store = HumanReviewStore(storageURL: fixture.support)

        let returned = try await store.completeReview(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: "Note.md",
            fingerprint: DocumentFingerprint(content: "# Note\n"),
            qualification: .qualified,
            reviewNote: "The live and reopened delivery surfaces must agree."
        )
        let live = try #require(await store.record(noteID: noteID))
        let reopened = HumanReviewStore(storageURL: fixture.support)
        let persisted = try #require(await reopened.record(noteID: noteID))

        #expect(returned == live)
        #expect(live == persisted)
    }

    @Test("Live Dialogue and Critique values match persisted delivery projections")
    func liveDialogueAndCritiqueMatchPersistedProjection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        let vaultID = UUID()
        let reference = DialogueNoteReference(
            noteID: noteID,
            vaultID: vaultID,
            vaultName: "Works",
            title: "A Work",
            relativePath: "A Work.md",
            fingerprint: DocumentFingerprint(content: "# A Work\n")
        )

        let dialogueDirectory = fixture.support.appendingPathComponent(
            "dialogue",
            isDirectory: true
        )
        let dialogueStore = DialogueStore(storageURL: dialogueDirectory)
        let dialogue = DialogueEntry(
            triptychID: UUID(),
            instruction: "Inspect the argument.",
            selectedNotes: [reference],
            includedComments: [],
            preparedInstructions: "Prompt",
            checkpointID: UUID()
        )
        let returnedDialogue = try await dialogueStore.save(dialogue)
        let liveDialogue = try await dialogueStore.entry(id: dialogue.id)
        let reopenedDialogueStore = DialogueStore(storageURL: dialogueDirectory)
        let persistedDialogue = try await reopenedDialogueStore.entry(id: dialogue.id)
        #expect(returnedDialogue == liveDialogue)
        #expect(liveDialogue == persistedDialogue)

        let controlURL = fixture.support.appendingPathComponent(
            "control",
            isDirectory: true
        )
        let critiqueStore = CritiqueRegistry(controlURL: controlURL)
        let association = CritiqueAssociation(
            workNoteID: noteID,
            workRelativePath: reference.relativePath,
            targetFingerprint: reference.fingerprint,
            critiqueRelativePath: "Critiques/A Work Critique.md"
        )
        let returnedCritique = try await critiqueStore.save(association)
        let liveCritique = try #require(await critiqueStore.association(workNoteID: noteID))
        let reopenedCritiqueStore = CritiqueRegistry(controlURL: controlURL)
        let persistedCritique = try #require(
            await reopenedCritiqueStore.association(workNoteID: noteID)
        )
        #expect(returnedCritique == liveCritique)
        #expect(liveCritique == persistedCritique)
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
                comment: ResearcherComment(
                    text: "Do not overwrite the corrupt store.",
                    anchor: testCommentAnchor()
                )
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
                preparedInstructions: "Prompt",
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
                comment: ResearcherComment(
                    text: "Must not appear in memory.",
                    anchor: testCommentAnchor()
                )
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
            preparedInstructions: "Prompt",
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
            comment: ResearcherComment(
                text: "Private comment",
                anchor: testCommentAnchor()
            )
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
            preparedInstructions: "Contains private deleted-note context.",
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
        #expect(record.comments[0].anchor.state == .attached)
        #expect(record.comments[0].anchor.line == 3)

        let ambiguous = NoteDocument(
            relativePath: "Note.md",
            rawContent: "The claim matters.\nThe claim matters.\n"
        )
        try await store.reattachComments(noteID: noteID, to: ambiguous)
        record = try #require(await store.record(noteID: noteID))
        #expect(record.comments[0].anchor.state == .needsReattachment)
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
        #expect(record.comments[0].anchor.quotation == "revised claim")
        #expect(record.comments[0].anchor.fingerprint == replacement.fingerprint)

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
            comment: ResearcherComment(
                text: "Keep this comment.",
                anchor: testCommentAnchor()
            )
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
            comment: ResearcherComment(
                text: "Revise this.",
                anchor: testCommentAnchor(fingerprint: reference.fingerprint)
            )
        )
        let dialogueStore = DialogueStore(storageURL: fixture.support.appendingPathComponent("dialogue"))
        let followUp = DialogueFollowUpComment(
            text: "Preserve this follow-up.",
            noteID: noteID,
            commentID: included.comment.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let response = DialogueReply(
            agentName: "Codex",
            text: "Preserve this response.",
            noteID: noteID,
            commentID: included.comment.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_201)
        )
        let entry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Revise.",
            selectedNotes: [reference],
            includedComments: [included],
            preparedInstructions: "Historical path: Old.md",
            checkpointID: nil,
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
        #expect(migrated.includedComments[0].note.relativePath == "Folder/New.md")
        #expect(migrated.preparedInstructions == "Historical path: Old.md")
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
            preparedInstructions: prompt,
            checkpointID: UUID(),
            requestedDestination: "Update relevant notes in Topics when warranted.",
            linkedNoteSummary: "Topic B neutrally links to Paper A; this is not evidence."
        )
        _ = try await store.save(entry)
        #expect((await store.entries(noteID: first.noteID)).map(\.id) == [entry.id])
        #expect((await store.entries(noteID: second.noteID)).map(\.id) == [entry.id])
        #expect(prompt.contains("selected Target and contextual Materials are read-only"))
        #expect(prompt.contains("creates no checkpoint and authorizes no research-note mutation"))
        #expect(!prompt.localizedCaseInsensitiveContains("proposal"))
        #expect(prompt.localizedCaseInsensitiveContains("concise attributed academic result"))
        #expect(prompt.localizedCaseInsensitiveContains("warranted promotion"))
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
            comment: ResearcherComment(
                text: "Separate textual support from reconstruction.",
                anchor: testCommentAnchor(fingerprint: note.fingerprint)
            )
        )
        let entry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Clarify the argument without overstating the source.",
            selectedNotes: [note],
            includedComments: [included],
            preparedInstructions: "",
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

    @Test("Every Comment record decoder requires a source anchor")
    func commentRecordDecodersRequireAnchor() throws {
        let comment = ResearcherComment(
            text: "This Comment is bound to an exact passage.",
            anchor: testCommentAnchor()
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(comment)) as? [String: Any]
        )
        object.removeValue(forKey: "anchor")
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ResearcherComment.self, from: data)
        }

        let reviewRecord = HumanReviewRecord(
            noteID: UUID(),
            vaultID: UUID(),
            relativePath: "Analysis.md",
            comments: [comment]
        )
        var reviewObject = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(reviewRecord)
            ) as? [String: Any]
        )
        var reviewComments = try #require(reviewObject["comments"] as? [[String: Any]])
        reviewComments[0].removeValue(forKey: "anchor")
        reviewObject["comments"] = reviewComments
        let reviewData = try JSONSerialization.data(withJSONObject: reviewObject)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HumanReviewRecord.self, from: reviewData)
        }

        let note = DialogueNoteReference(
            noteID: reviewRecord.id,
            vaultID: reviewRecord.vaultID,
            vaultName: "Analyses",
            title: "Analysis",
            relativePath: reviewRecord.relativePath,
            fingerprint: comment.anchor.fingerprint
        )
        let included = DialogueIncludedComment(note: note, comment: comment)
        var includedObject = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(included)
            ) as? [String: Any]
        )
        var includedComment = try #require(
            includedObject["comment"] as? [String: Any]
        )
        includedComment.removeValue(forKey: "anchor")
        includedObject["comment"] = includedComment
        let includedData = try JSONSerialization.data(withJSONObject: includedObject)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(DialogueIncludedComment.self, from: includedData)
        }
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

    @Test("Dialogue function evidence advances monotonically and incomplete preparation rolls back")
    func dialogueFunctionEvidenceLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = DialogueStore(storageURL: fixture.support.appendingPathComponent("dialogue"))
        let noteID = UUID()
        let vaultID = UUID()
        let source = "# Analysis\n"
        let preparedFingerprint = DocumentFingerprint(content: source)
        let target = ResearchFunctionTarget(
            noteID: noteID,
            note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Analysis.md"),
            role: .analysis,
            fingerprint: preparedFingerprint,
            title: "Analysis"
        )
        let checkpointID = UUID()
        let snapshot = ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(function: .develop, target: target),
            recordKind: .dialogue,
            checkpointID: checkpointID,
            fidelityHandoff: ResearchFunctionFidelityHandoff(
                required: true,
                checks: [.content],
                preparedTargetFingerprint: preparedFingerprint
            ),
            preparedAt: Date(timeIntervalSince1970: 100)
        )
        let reference = DialogueNoteReference(
            noteID: noteID,
            vaultID: vaultID,
            vaultName: "Analyses",
            title: "Analysis",
            relativePath: "Analysis.md",
            fingerprint: preparedFingerprint
        )
        let entry = DialogueEntry(
            triptychID: UUID(),
            instruction: "Develop the argument.",
            selectedNotes: [reference],
            includedComments: [],
            preparedInstructions: "Prepared instructions",
            checkpointID: checkpointID,
            functionSnapshot: snapshot
        )
        _ = try await store.save(entry)
        #expect(try await store.functionRecord(runID: snapshot.runID)?.snapshot == snapshot)

        let finalizedRequest = try snapshot.request.selectingResources([])
        let finalizedSnapshot = ResearchFunctionSnapshot(
            runID: snapshot.runID,
            request: finalizedRequest,
            recordKind: snapshot.recordKind,
            recordID: snapshot.recordID,
            checkpointID: snapshot.checkpointID,
            skills: snapshot.skills,
            phases: snapshot.phases,
            requiredChildFunctions: snapshot.requiredChildFunctions,
            preparedOutput: snapshot.preparedOutput,
            evidenceRevisions: snapshot.evidenceRevisions,
            fidelityHandoff: snapshot.fidelityHandoff,
            confirmationToken: snapshot.confirmationToken,
            preparedAt: snapshot.preparedAt
        )
        let finalized = try await store.finalizeFunctionPreflight(
            snapshot: finalizedSnapshot,
            instructions: "Finalized instructions",
            runID: snapshot.runID
        )
        #expect(finalized.functionSnapshot == finalizedSnapshot)
        #expect(finalized.preparedInstructions == "Finalized instructions")
        #expect(finalized.checkpointID == checkpointID)
        _ = try await store.finalizeFunctionPreflight(
            snapshot: finalizedSnapshot,
            instructions: "Finalized instructions",
            runID: snapshot.runID
        )
        let conflictingSnapshot = ResearchFunctionSnapshot(
            runID: snapshot.runID,
            request: try snapshot.request.selectingResources([.developmentSynthesis]),
            recordKind: snapshot.recordKind,
            recordID: snapshot.recordID,
            checkpointID: snapshot.checkpointID,
            skills: snapshot.skills,
            phases: snapshot.phases,
            requiredChildFunctions: snapshot.requiredChildFunctions,
            preparedOutput: snapshot.preparedOutput,
            evidenceRevisions: snapshot.evidenceRevisions,
            fidelityHandoff: snapshot.fidelityHandoff,
            confirmationToken: snapshot.confirmationToken,
            preparedAt: snapshot.preparedAt
        )
        await #expect(throws: ResearchFunctionRecordStoreError.self) {
            _ = try await store.finalizeFunctionPreflight(
                snapshot: conflictingSnapshot,
                instructions: "Different instructions",
                runID: snapshot.runID
            )
        }

        let finalFingerprint = DocumentFingerprint(content: "# Developed Analysis\n")
        let awaiting = ResearchFunctionCompletion(
            runID: snapshot.runID,
            function: .develop,
            state: .awaitingFidelity,
            targetFingerprint: finalFingerprint,
            materialFingerprints: [:],
            summary: "The authorized Analysis changed and awaits Fidelity.",
            didModifyTarget: true,
            fidelityOutcomes: [],
            completedAt: Date(timeIntervalSince1970: 200)
        )
        _ = try await store.setFunctionCompletion(awaiting, runID: snapshot.runID)

        let complete = ResearchFunctionCompletion(
            runID: snapshot.runID,
            function: .develop,
            state: .complete,
            targetFingerprint: finalFingerprint,
            materialFingerprints: [:],
            summary: "Content Fidelity passed for the exact final revision.",
            didModifyTarget: true,
            fidelityOutcomes: [
                FidelityCheckOutcome(
                    check: .content,
                    state: .passed,
                    summary: "Content Fidelity passed for the attributed final revision."
                ),
            ],
            completedAt: Date(timeIntervalSince1970: 300)
        )
        _ = try await store.setFunctionCompletion(complete, runID: snapshot.runID)
        #expect(try await store.functionRecord(runID: snapshot.runID)?.completion == complete)
        await #expect(throws: ResearchFunctionRecordStoreError.self) {
            _ = try await store.setFunctionCompletion(awaiting, runID: snapshot.runID)
        }
        await #expect(throws: ResearchFunctionRecordStoreError.self) {
            _ = try await store.discardPreparedFunctionRecord(runID: snapshot.runID)
        }

        let rollbackSnapshot = ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(function: .develop, target: target),
            recordKind: .dialogue
        )
        _ = try await store.save(DialogueEntry(
            triptychID: entry.triptychID,
            instruction: "Prepare, then fail.",
            selectedNotes: [reference],
            includedComments: [],
            preparedInstructions: "Prepared instructions",
            checkpointID: nil,
            functionSnapshot: rollbackSnapshot
        ))
        _ = try await store.discardPreparedFunctionRecord(runID: rollbackSnapshot.runID)
        #expect(try await store.functionRecord(runID: rollbackSnapshot.runID) == nil)

        let reopened = DialogueStore(storageURL: fixture.support.appendingPathComponent("dialogue"))
        #expect(try await reopened.functionRecord(runID: snapshot.runID)?.completion == complete)
    }

    @Test("Critique preparation rollback removes only its incomplete round")
    func critiqueFunctionPreparationRollback() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let registry = CritiqueRegistry(
            controlURL: fixture.support.appendingPathComponent("control", isDirectory: true)
        )
        let workID = UUID()
        let vaultID = UUID()
        let fingerprint = DocumentFingerprint(content: "# Work\n")
        let target = ResearchFunctionTarget(
            noteID: workID,
            note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Drafts/Work.md"),
            role: .work,
            fingerprint: fingerprint,
            title: "Work"
        )
        let olderRoundID = UUID()
        _ = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: "Drafts/Work.md",
            targetFingerprint: fingerprint,
            critiqueRelativePath: "Critiques/Work Critique.md",
            checkpointID: UUID(),
            scope: .overall,
            roundID: olderRoundID
        )
        let snapshot = ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(
                function: .critique,
                target: target,
                scope: .whole
            ),
            recordKind: .critique,
            preparedAt: Date(timeIntervalSince1970: 100)
        )
        _ = try await registry.recordRequest(
            workNoteID: workID,
            workRelativePath: "Drafts/Work.md",
            targetFingerprint: fingerprint,
            critiqueRelativePath: "Critiques/Work Critique.md",
            checkpointID: UUID(),
            scope: .overall,
            roundID: UUID(),
            functionSnapshot: snapshot
        )

        let preparedRecord = try await registry.functionRecord(runID: snapshot.runID)
        #expect(preparedRecord?.snapshot == snapshot)
        _ = try await registry.discardPreparedFunctionRecord(runID: snapshot.runID)
        #expect(try await registry.functionRecord(runID: snapshot.runID) == nil)
        let retained = try #require(await registry.association(workNoteID: workID))
        #expect(retained.rounds.map(\.id) == [olderRoundID])
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

    private func testCommentAnchor(
        fingerprint: DocumentFingerprint = DocumentFingerprint(content: "Test passage"),
        quotation: String = "Test passage"
    ) -> ResearcherCommentAnchor {
        ResearcherCommentAnchor(
            fingerprint: fingerprint,
            utf8Range: 0..<quotation.utf8.count,
            utf16Range: 0..<quotation.utf16.count,
            line: 1,
            endLine: 1,
            quotation: quotation
        )
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
