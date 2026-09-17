import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Related materials") @MainActor
struct RelatedMaterialsTests {
    private let vault = UUID()
    private func seed(_ text: String = "unsaved freedom 自由") -> RelatedMaterialsSeed {
        let snapshot = RelatedContentSeedSnapshot(
            noteID: .init(vaultID: vault, relativePath: "Draft.md"),
            source: "# Draft\n\n" + text, focuses: [.init(kind: .selectedPassage, text: text)])
        return .init(
            request: .init(seed: snapshot),
            attachment: .init(
                noteID: UUID(), vaultID: vault,
                relativePath: "Draft.md", text: text, fingerprint: snapshot.fingerprint, sourceLine: 3))
    }
    private func candidate(_ source: String) -> RelatedContentCandidate {
        .init(
            note: .init(vaultID: vault, relativePath: "Source.md"), vaultRole: .sourceCorpus,
            title: "Source", fingerprint: .init(content: source),
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [.init(seedKind: .selectedPassage, terms: ["自由"])])))
    }
    private func reference() -> VaultNoteReference {
        .init(vaultID: vault, vaultName: "Analyses", vaultRole: .sourceCorpus, relativePath: "Source.md", stableNoteID: UUID().uuidString)
    }
    private func response(_ request: RelatedContentRequest, candidates: [RelatedContentCandidate] = []) -> RelatedContentResponse {
        .init(
            requestID: request.id, seedFingerprint: request.seed.fingerprint, freshnessToken: .init("fixture"),
            availability: .current(.init(triptychID: UUID(), sequence: 1, sourceManifestHash: "fixture")),
            state: candidates.isEmpty ? .empty : .current,
            identityCandidates: candidates, lexicalCandidates: candidates, identityHasMore: false, lexicalHasMore: false)
    }

    private func populatedResponse(_ seed: RelatedMaterialsSeed) -> RelatedContentResponse {
        let candidate = candidate("自由")
        let passage = RelatedContentPassage(
            candidate: candidate,
            range: .init(utf16LowerBound: 0, utf16UpperBound: 2, line: 1, column: 1, endLine: 1, endColumn: 3),
            source: "自由", displayText: "自由", excerpt: "自由", excerptMatches: [0..<2],
            matches: [.init(seedKind: .selectedPassage, terms: ["自由"])])
        return .init(
            requestID: seed.request.id, seedFingerprint: seed.request.seed.fingerprint,
            freshnessToken: .init("fixture"), availability: .unavailable, state: .current,
            identityCandidates: [], lexicalCandidates: [candidate], identityHasMore: false,
            lexicalHasMore: false, passages: [passage])
    }

    private func descriptor(_ path: String) -> WindowDocumentDescriptor {
        .init(
            sessionKey: .init(vaultID: vault, noteID: UUID()),
            reference: .init(vaultID: vault, vaultName: "Topics", vaultRole: .topicKnowledge, relativePath: path))
    }

    private func identityPassage(_ reference: VaultNoteReference, title: String, line: Int = 1) -> RelatedContentPassage {
        let candidate = RelatedContentCandidate(
            note: .init(vaultID: reference.vaultID, relativePath: reference.relativePath), vaultRole: reference.vaultRole,
            title: title, fingerprint: .init(content: "自由"),
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [.init(seedKind: .selectedPassage, terms: ["自由"])])))
        return .init(
            candidate: candidate,
            range: .init(
                utf16LowerBound: line * 3, utf16UpperBound: line * 3 + 2,
                line: line, column: 1, endLine: line, endColumn: 3),
            source: "自由", displayText: "自由", excerpt: "自由", excerptMatches: [0..<2],
            matches: [.init(seedKind: .selectedPassage, terms: ["自由"])])
    }

    @Test("Duplicate titles show their directories while preserving ranked cards and Note groups")
    func duplicateTitleIdentity() async {
        let references = ["Philosophy/Freedom.md", "Ethics/Freedom.md", "Unique.md"].map {
            VaultNoteReference(vaultID: vault, vaultName: "My Topics", vaultRole: .topicKnowledge, relativePath: $0)
        }
        let first = identityPassage(references[0], title: "Freedom")
        let unique = identityPassage(references[2], title: "Unique")
        let second = identityPassage(references[1], title: "Freedom")
        let another = identityPassage(references[0], title: "Freedom", line: 3)
        let passages = [first, unique, second, another]
        let model = RelatedMaterialsSession()
        let seed = seed()
        let response = RelatedContentResponse(
            requestID: seed.request.id, seedFingerprint: seed.request.seed.fingerprint,
            freshnessToken: .init("fixture"), availability: .unavailable, state: .current,
            identityCandidates: [], lexicalCandidates: passages.map(\.candidate), identityHasMore: false,
            lexicalHasMore: false, passages: passages)
        await model.find(capture: { seed }, retrieve: { _ in response }, references: references).value
        #expect(model.cards.map(\.id) == passages.map(\.id))
        #expect(model.noteGroups.map(\.id) == [first.candidate.note, unique.candidate.note, second.candidate.note])
        #expect(model.noteGroups.map(\.directoryContext) == ["My Topics / Philosophy", nil, "My Topics / Ethics"])
        #expect(model.noteGroups.first?.passages.map(\.id) == [first.id, another.id])
    }

    @Test(
        "Source identity retains exact authored title and path with each localized registered role",
        arguments: [VaultRole.sourceCorpus, .topicKnowledge, .draftProject])
    func sourceRoleIdentity(_ role: VaultRole) {
        let title = "自由 — Freedom 😀"
        let reference = VaultNoteReference(
            vaultID: vault, vaultName: "Private Vault", vaultRole: role,
            relativePath: "研究/自由 — Freedom 😀.md")
        let card = RelatedMaterialCard(passage: identityPassage(reference, title: title), reference: reference)
        #expect(card.sourceIdentity == [title, ScholiumL10n.dynamicString(role.displayName), reference.relativePath].joined(separator: ", "))
    }

    @Test("Document selection clears recommendations synchronously, including while hidden", arguments: [false, true])
    func documentDeparture(closing: Bool) async {
        let documents = DocumentController()
        let research = ResearchController(selectedDocuments: documents.$selectedDocument.eraseToAnyPublisher())
        let otherWindow = RelatedMaterialsSession()
        let first = descriptor("Draft.md")
        documents.installOpenedDocument(first)
        var seed = seed()
        seed.insertionPoint = .init(sessionID: UUID(), documentID: "draft", generation: 1, selection: .init(anchor: 3, head: 3))
        let captured = seed
        let response = populatedResponse(seed)
        let model = research.relatedMaterials
        for session in [model, otherWindow] {
            await session.find(capture: { captured }, retrieve: { _ in response }, references: [reference()]).value
        }
        #expect(!model.cards.isEmpty && model.insertionPoint != nil)
        #expect(documents.selectRetainedDocument(.workspace(first)))
        #expect(!model.cards.isEmpty && model.insertionPoint != nil)
        model.report(RelatedMaterialsError.staleIndex)
        #expect(model.issue != nil && model.needsRefresh)
        model.scheduleAutomaticSearch(selection: true, immediate: true) {
            Issue.record("A departed Note's scheduled search must not execute")
        }
        if closing {
            documents.clearSelectionAfterClosingLastTab()
        } else {
            documents.installOpenedDocument(descriptor("Second.md"))
        }
        // No await or view callback between navigation and these expectations.
        #expect(model.cards.isEmpty && model.seed == nil && model.insertionPoint == nil)
        #expect(model.issue == nil && !model.needsRefresh && !model.contextChanged)
        #expect(!model.isLoading && !model.didSearch && model.omittedCount == 0)
        #expect(model.presentation == .waiting)
        #expect(!research.inspector.isVisible)
        #expect(!otherWindow.cards.isEmpty)
        #expect(documents.selectRetainedDocument(.workspace(first)))
        #expect(model.cards.isEmpty && model.seed == nil)
        await Task.yield()
    }

    @Test("A late passage response cannot overwrite a new search after navigation", arguments: [false, true])
    func lateResponseAfterDocumentDeparture(returnToFirst: Bool) async {
        let documents = DocumentController()
        let research = ResearchController(selectedDocuments: documents.$selectedDocument.eraseToAnyPublisher())
        let first = descriptor("Draft.md")
        documents.installOpenedDocument(first)
        let model = research.relatedMaterials
        let original = seed()
        let response = populatedResponse(original)
        let ready = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        let oldOperation = model.find(
            capture: { original }, retrieve: { _ in response }, references: [reference()],
            linkTarget: { _ in
                await withCheckedContinuation { continuation in
                    release = continuation
                    ready.continuation.yield(())
                    ready.continuation.finish()
                }
                return "[[Source]]"
            })
        for await _ in ready.stream {}
        documents.installOpenedDocument(descriptor("Second.md"))
        if returnToFirst { #expect(documents.selectRetainedDocument(.workspace(first))) }
        let current = seed("current context")
        let currentResponse = self.response(current.request)
        await model.find(capture: { current }, retrieve: { _ in currentResponse }, references: []).value
        release?.resume()
        await oldOperation.value
        #expect(model.seed?.request.id == current.request.id)
        #expect(model.cards.isEmpty && model.presentation == .empty && !model.isLoading)
        #expect(model.issue == nil)
    }

    @Test("A Note group retains both ranked paragraphs and exact source ranges")
    func selectionAndParagraphs() async {
        let model = RelatedMaterialsSession()
        let seed = seed()
        let candidate = candidate("whole source")
        let first = RelatedContentPassage(
            candidate: candidate,
            range: .init(
                utf16LowerBound: 12, utf16UpperBound: 18,
                line: 3, column: 1, endLine: 3, endColumn: 7), source: "**自由**", displayText: "自由", excerpt: "自由", excerptMatches: [0..<2],
            matches: [.init(seedKind: .selectedPassage, terms: ["自由"])])
        let second = RelatedContentPassage(
            candidate: candidate,
            range: .init(
                utf16LowerBound: 20, utf16UpperBound: 26,
                line: 5, column: 1, endLine: 5, endColumn: 7), source: "另一段自由。", displayText: "另一段自由。", excerpt: "另一段自由。", excerptMatches: [3..<5],
            matches: first.matches)
        let response = RelatedContentResponse(
            requestID: seed.request.id, seedFingerprint: seed.request.seed.fingerprint,
            freshnessToken: .init("fixture"), availability: .unavailable, state: .current, identityCandidates: [],
            lexicalCandidates: [candidate], identityHasMore: false, lexicalHasMore: false, passages: [first, second])
        await model.find(
            capture: { seed },
            retrieve: { request in
                #expect(request.seed.source.contains("unsaved"))
                #expect(request.seed.focuses.first?.text == seed.attachment.text)
                return response
            }, references: [reference()]
        ).value
        #expect(model.cards.count == 2)
        #expect(model.noteGroups.count == 1)
        #expect(model.noteGroups.first?.passages.count == 2)
        #expect(model.noteGroups.first?.directoryContext == nil)
        #expect(model.cards.map(\.id) == [first.id, second.id])
        #expect(model.seed?.attachment.text == seed.attachment.text)
        #expect(model.didSearch && !model.isLoading)
        #expect(model.cards.first?.attachment?.sourceRange == first.range)
        #expect(model.cards.first?.attachment?.text == "**自由**")
        #expect(model.cards.first?.linkTarget == nil)  // Reading does not require an insertable link.
        model.invalidateWritingContext()
        #expect(model.insertionPoint == nil && model.contextChanged)
        #expect(model.cards.first?.id == first.id)
        let nextSeed = self.seed("different context")
        let ready = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        let replacement = model.find(
            capture: {
                await withCheckedContinuation { continuation in
                    release = continuation
                    ready.continuation.yield(())
                    ready.continuation.finish()
                }
                return nextSeed
            }, retrieve: { _ in throw RelatedMaterialsError.unavailable }, references: [])
        for await _ in ready.stream {}
        #expect(model.presentation == .loading)
        #expect(model.cards.first?.id == first.id && model.insertionPoint == nil)
        release?.resume()
        await replacement.value
        #expect(model.cards.first?.id == first.id)
        #expect(model.seed?.request.id == seed.request.id)
        #expect(model.issue != nil && !model.isLoading)

    }

    @Test("Works provenance and exact passages survive cards, grouping, link preparation and Chat staging")
    func workMaterialProvenance() async throws {
        let model = RelatedMaterialsSession()
        let seed = seed()
        let workVault = UUID()
        let stableID = UUID()
        let workReference = VaultNoteReference(
            vaultID: workVault, vaultName: "Works", vaultRole: .draftProject,
            relativePath: "Earlier Work.md", stableNoteID: stableID.uuidString)
        let exact = "**自由**与 autonomy 😀。\r\n第二行保持原样。"
        let prefix = "\u{FEFF}# Earlier Work\r\n\r\n"
        let raw = prefix + exact + "\r\n"
        let workCandidate = RelatedContentCandidate(
            note: .init(vaultID: workVault, relativePath: workReference.relativePath), vaultRole: .draftProject,
            title: "Earlier Work", fingerprint: .init(content: raw),
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [.init(seedKind: .selectedPassage, terms: ["自由", "autonomy"])])))
        let passage = RelatedContentPassage(
            candidate: workCandidate,
            range: .init(
                utf16LowerBound: prefix.utf16.count, utf16UpperBound: prefix.utf16.count + exact.utf16.count,
                line: 3, column: 1, endLine: 4, endColumn: "第二行保持原样。".utf16.count + 1),
            source: exact, displayText: "自由与 autonomy 😀。 第二行保持原样。", excerpt: "自由与 autonomy 😀。", excerptMatches: [0..<2],
            matches: [.init(seedKind: .selectedPassage, terms: ["自由", "autonomy"])])
        let result = RelatedContentResponse(
            requestID: seed.request.id, seedFingerprint: seed.request.seed.fingerprint,
            freshnessToken: .init("fixture"), availability: .unavailable, state: .current,
            identityCandidates: [], lexicalCandidates: [workCandidate], identityHasMore: false, lexicalHasMore: false,
            passages: [passage])
        var preparedLinks: [VaultNoteReference] = []
        await model.find(
            capture: { seed }, retrieve: { _ in result }, references: [workReference],
            linkTarget: { reference in
                preparedLinks.append(reference)
                return "[[Earlier Work]]"
            }
        ).value
        #expect(model.presentation == .results && model.omittedCount == 0 && model.issue == nil)
        #expect(model.cards.count == 1 && model.noteGroups.count == 1)
        let card = try #require(model.cards.first)
        #expect(card.reference == workReference)
        #expect(card.reference.vaultRole == .draftProject && card.candidate.vaultRole == .draftProject)
        #expect(card.passage == passage && card.text == exact)
        #expect(preparedLinks == [workReference] && card.linkTarget == "[[Earlier Work]]")
        let group = try #require(model.noteGroups.first)
        #expect(group.id == workCandidate.note && group.passages == [card])
        #expect(group.passages.first?.reference.vaultRole == .draftProject)
        let attachment = try #require(card.attachment)
        #expect(attachment.noteID == stableID && attachment.vaultID == workVault)
        #expect(attachment.relativePath == workReference.relativePath && attachment.vaultRole == .draftProject)
        #expect(attachment.text == exact && attachment.fingerprint == workCandidate.fingerprint)
        #expect(attachment.sourceRange == passage.range && attachment.source == .savedSource && attachment.extent == .passage)

        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/related-materials-chat-staging/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let chat = fixtureChatController(triptychID: UUID(), root: root) { request in
            Issue.record("Staging a Work must not invoke an Agent tool")
            return try! .init(requestID: request.requestID, result: .object([:]))
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !chat.isLoaded {
            try #require(ContinuousClock.now < deadline, "Chat staging fixture did not become ready")
            try await Task.sleep(for: .milliseconds(10))
        }
        chat.editDraft("Compare this with my current argument.")
        let receiver: any AgentChatContextReceiving = chat
        #expect(receiver.attachContext([seed.attachment, attachment]))
        let staged = try #require(chat.selected?.attachments.first { $0.noteID == stableID })
        #expect(staged == attachment && staged.vaultRole == .draftProject)
        #expect(chat.selected?.draft == "Compare this with my current argument.")
        #expect(chat.selected?.messages.isEmpty == true && chat.state == .disconnected)
        try await chat.flushPersistence()
    }

    @Test("Reset or selection departure invalidates an uncooperative late response", arguments: [false, true])
    func cancelledPublication(reset: Bool) async {
        let model = RelatedMaterialsSession()
        let seed = seed()
        var release: CheckedContinuation<Void, Never>?
        var started: CheckedContinuation<Void, Never>?
        let latch = Task { await withCheckedContinuation { started = $0 } }
        await Task.yield()
        let response = response(seed.request)
        let operation = model.find(
            capture: {
                await withCheckedContinuation { continuation in
                    release = continuation
                    started?.resume()
                }
                return seed
            }, retrieve: { _ in response }, references: [])
        await latch.value
        if reset { model.reset() } else { model.stopAutomaticSearch() }
        release?.resume()
        await operation.value
        #expect(model.seed == nil && model.cards.isEmpty && !model.isLoading && !model.didSearch)
    }

    @Test(
        "Stale retrieval offers refresh while an invalid selection asks for different wording",
        arguments: [RelatedContentResultState.stale, .invalidSeed, .unavailable])
    func retrievalStates(_ state: RelatedContentResultState) async {
        let model = RelatedMaterialsSession()
        let seed = seed()
        let response = RelatedContentResponse(
            requestID: seed.request.id,
            seedFingerprint: seed.request.seed.fingerprint, freshnessToken: .init("fixture"), availability: .unavailable,
            state: state, identityCandidates: [], lexicalCandidates: [], identityHasMore: false, lexicalHasMore: false)
        await model.find(
            capture: { seed }, retrieve: { _ in response },
            references: []
        ).value
        #expect(model.issue != nil && !model.isLoading)
        #expect(model.needsRefresh == (state != .invalidSeed))
        #expect(model.cards.isEmpty && !model.didSearch)
    }

    @Test("Omitted sources are visible and no-selection preserves a recoverable error")
    func failures() async {
        let model = RelatedMaterialsSession()
        let seed = seed()
        let response = RelatedContentResponse(
            requestID: seed.request.id, seedFingerprint: seed.request.seed.fingerprint,
            freshnessToken: .init("fixture"), availability: .unavailable, state: .partial, identityCandidates: [],
            lexicalCandidates: [], identityHasMore: false, lexicalHasMore: false, omittedSourceCount: 1)
        await model.find(capture: { seed }, retrieve: { _ in response }, references: [reference()]).value
        #expect(model.omittedCount == 1 && model.cards.isEmpty && model.didSearch)
        await model.find(capture: { throw RelatedMaterialsError.selectionRequired }, retrieve: { _ in response }, references: []).value
        #expect(model.issue != nil && !model.isLoading)
    }
    @Test("Automatic empty selection preserves context without a selection error")
    func automaticEmptySelection() async {
        let model = RelatedMaterialsSession()
        let seed = seed()
        let response = response(seed.request)
        await model.find(capture: { seed }, retrieve: { _ in response }, references: [], automatic: true).value
        await model.find(
            capture: { throw RelatedMaterialsError.selectionRequired },
            retrieve: { _ in response }, references: [], automatic: true
        ).value
        #expect(model.seed?.request.id == seed.request.id)
        #expect(model.issue == nil && !model.isLoading && model.didSearch)
    }

    @Test("Closing the pane cancels a pending automatic selection request")
    func closingCancelsScheduledSearch() async {
        let model = RelatedMaterialsSession()
        var ran = false
        model.scheduleAutomaticSearch(selection: true, immediate: true) { ran = true }
        model.stopAutomaticSearch()
        for _ in 0..<10 { await Task.yield() }
        #expect(!ran && !model.isLoading)
    }

    @Test("Unchanged automatic context reuses results instead of rerunning retrieval")
    func unchangedContext() async {
        let model = RelatedMaterialsSession()
        let seed = seed()
        let response = response(seed.request)
        await model.find(capture: { seed }, retrieve: { _ in response }, references: [], automatic: true).value
        model.invalidateWritingContext()
        var moved = seed
        moved.insertionPoint = .init(sessionID: UUID(), documentID: "draft", generation: 1, selection: .init(anchor: 3, head: 3))
        await model.find(
            capture: { moved },
            retrieve: { _ in
                Issue.record("Unchanged selection unexpectedly repeated retrieval")
                return response
            }, references: [], automatic: true
        ).value
        #expect(model.didSearch && !model.isLoading && model.issue == nil)
        #expect(model.insertionPoint == moved.insertionPoint && !model.contextChanged)
    }

    @Test("Automatic reading pause does not publish or retrieve replacement results")
    func readingPause() async {
        let model = RelatedMaterialsSession()
        let original = seed()
        let response = response(original.request)
        await model.find(capture: { original }, retrieve: { _ in response }, references: []).value
        await model.find(
            capture: { self.seed("new paragraph") },
            retrieve: { _ in
                Issue.record("Paused automatic search should not retrieve")
                return response
            }, references: [], automatic: true, canPublish: { false }
        ).value
        #expect(model.seed?.request.id == original.request.id)
        #expect(!model.isLoading && model.issue == nil)
    }

    @Test("Sidebar presentation distinguishes waiting, empty, failure and reset")
    func presentationLifecycle() async {
        let model = RelatedMaterialsSession()
        #expect(model.presentation == .waiting)
        let seed = seed()
        let response = response(seed.request)
        await model.find(capture: { seed }, retrieve: { _ in response }, references: []).value
        #expect(model.presentation == .empty)
        model.report(RelatedMaterialsError.unavailable)
        guard case .problem = model.presentation else {
            Issue.record("Failure must replace empty guidance")
            return
        }
        model.reset()
        #expect(model.presentation == .waiting)
    }

    @Test("Only complete current results allow paragraph insertion, and one insertion owns the request", arguments: [false, true])
    func paragraphInsertionAdmission(partial: Bool) async {
        let model = RelatedMaterialsSession()
        var seed = seed()
        seed.insertionPoint = .init(sessionID: UUID(), documentID: "draft", generation: 1, selection: .init(anchor: 3, head: 3))
        let captured = seed
        let complete = populatedResponse(seed)
        let response = RelatedContentResponse(
            requestID: complete.requestID, seedFingerprint: complete.seedFingerprint,
            freshnessToken: complete.freshnessToken, availability: complete.availability,
            state: partial ? .partial : .current, identityCandidates: complete.identityCandidates,
            lexicalCandidates: complete.lexicalCandidates, identityHasMore: false, lexicalHasMore: false,
            passages: complete.passages)
        await model.find(capture: { captured }, retrieve: { _ in response }, references: [reference()]).value
        let card = model.cards[0]
        #expect(model.canInsertParagraphLink == !partial)
        #expect(model.beginParagraphInsertion(card) == !partial)
        #expect(!model.beginParagraphInsertion(card))
        if !partial {
            await model.find(
                capture: { captured },
                retrieve: { _ in
                    Issue.record("Retrieval replaced a request during its source mutation")
                    return response
                }, references: []
            ).value
            #expect(model.cards == [card])
            model.invalidateWritingContext()
            model.finishParagraphInsertion()
            #expect(!model.canInsertParagraphLink)
        }
        model.reset()
        #expect(!model.canInsertParagraphLink)
    }

}
