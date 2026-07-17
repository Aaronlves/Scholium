import Foundation
import ScholiumContracts
import ScholiumCore

actor RecommendedBibliographyCoordinator {
    private let reference: WorkspaceHandleReference

    init(reference: WorkspaceHandleReference) {
        self.reference = reference
    }

    func overview(
        for target: RecommendedBibliographyTarget
    ) async throws -> RecommendedBibliographyOverview {
        let handle = try await reference.requireHandle()
        _ = try await handle.validateBibliographyTarget(target, requiresFingerprint: false)
        var overview = try await handle.services.recommendedBibliographyStore.overview(
            targetNoteID: target.noteID
        )
        let potentiallyStale = [overview.result, overview.latestRun]
            .compactMap { $0 }
            .reduce(into: [UUID: RecommendedBibliographyProjection]()) { result, projection in
                result[projection.id] = projection
            }
            .values
        for projection in potentiallyStale
        where projection.request.target.fingerprint != target.fingerprint
            && projection.state != .cancelled
            && projection.state != .stale {
            try await handle.services.recommendedBibliographyStore.markStale(id: projection.id)
        }
        overview = try await handle.services.recommendedBibliographyStore.overview(
            targetNoteID: target.noteID
        )
        return overview
    }

    func recommendations(
        for target: RecommendedBibliographyTarget
    ) async throws -> RecommendedBibliographyProjection? {
        try await overview(for: target).result
    }

    func prepare(
        _ request: RecommendedBibliographyRequest
    ) async throws -> RecommendedBibliographyPreparation {
        let handle = try await reference.requireHandle()
        try request.validate()
        _ = try await handle.validateBibliographyTarget(
            request.target,
            requiresFingerprint: true
        )
        let method = try await handle.resolveBibliographyMethod()
        let id = UUID()
        let token = UUID()
        let instructions = try bibliographyInstructions(
            request: request,
            requestID: id,
            confirmationToken: token,
            method: method,
            triptychID: handle.services.manifest.id
        )
        let preparation = RecommendedBibliographyPreparation(
            id: id,
            confirmationToken: token,
            request: request,
            method: method,
            instructions: instructions,
            preparedAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
            nextActions: bibliographyAgentActions(
                requestID: id,
                triptychID: handle.services.manifest.id
            )
        )
        _ = try await handle.validateBibliographyTarget(
            request.target,
            requiresFingerprint: true
        )
        _ = try await handle.services.recommendedBibliographyStore.save(
            preparation: preparation
        )
        return preparation
    }

    func request(id: UUID) async throws -> RecommendedBibliographyPreparation {
        let handle = try await reference.requireHandle()
        let preparation = try await handle.services.recommendedBibliographyStore.preparation(id: id)
        return RecommendedBibliographyPreparation(
            id: preparation.id,
            confirmationToken: preparation.confirmationToken,
            request: preparation.request,
            method: preparation.method,
            instructions: preparation.instructions,
            preparedAt: preparation.preparedAt,
            state: preparation.state,
            nextActions: bibliographyAgentActions(
                requestID: id,
                triptychID: handle.services.manifest.id
            )
        )
    }

    func complete(
        _ submission: RecommendedBibliographyCompletionSubmission
    ) async throws -> RecommendedBibliographyProjection {
        let handle = try await reference.requireHandle()
        try submission.validate()
        let preparation = try await handle.services.recommendedBibliographyStore.preparation(
            id: submission.requestID
        )
        guard preparation.confirmationToken == submission.confirmationToken else {
            throw RecommendedBibliographyError.confirmationMismatch
        }
        let preparedProjection = try await handle.services.recommendedBibliographyStore.projection(
            id: submission.requestID
        )
        guard preparedProjection.state != .cancelled else {
            throw RecommendedBibliographyError.cancelled(submission.requestID)
        }
        guard preparedProjection.state != .stale else {
            throw RecommendedBibliographyError.targetChanged
        }
        guard submission.targetFingerprint == preparation.request.target.fingerprint else {
            throw RecommendedBibliographyError.targetChanged
        }
        _ = try await handle.validateBibliographyTarget(
            preparation.request.target,
            requiresFingerprint: true
        )
        let currentMethod = try await handle.resolveBibliographyMethod()
        guard currentMethod.packageID == preparation.method.packageID,
              currentMethod.origin == preparation.method.origin,
              currentMethod.packageRevision == preparation.method.packageRevision else {
            throw RecommendedBibliographyError.methodChanged
        }

        let priorCandidates = try await handle.services.recommendedBibliographyStore.overview(
            targetNoteID: preparation.request.target.noteID
        ).result?.candidates ?? []
        var candidates: [RecommendedBibliographyCandidate] = []
        for candidate in submission.candidates {
            _ = try candidate.validatedForSubmission()
            candidates.append(try await handle.deriveBibliographyMatches(candidate))
        }
        candidates = BibliographyCandidateDiscriminator.classify(
            candidates,
            against: priorCandidates
        )
        _ = try await handle.validateBibliographyTarget(
            preparation.request.target,
            requiresFingerprint: true
        )
        return try await handle.services.recommendedBibliographyStore.complete(
            requestID: submission.requestID,
            sourceScope: submission.sourceScope,
            candidates: candidates
        )
    }

    func cancel(id: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await handle.services.recommendedBibliographyStore.cancel(id: id)
    }

    func dismiss(requestID: UUID, candidateID: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await handle.services.recommendedBibliographyStore.dismiss(
            requestID: requestID,
            candidateID: candidateID
        )
    }

    func methodStatus() async throws -> RecommendedBibliographyMethodStatus {
        let handle = try await reference.requireHandle()
        return try await handle.bibliographyMethodStatus()
    }

    func setMethod(
        packageID: String?,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> RecommendedBibliographyMethodStatus {
        let handle = try await reference.requireHandle()
        _ = try await handle.services.researchSkillStore.setBibliographyMethodBinding(
            packageID: packageID,
            expectedBindingRevision: expectedBindingRevision
        )
        return try await handle.bibliographyMethodStatus()
    }
}

private func bibliographyAgentActions(
    requestID: UUID,
    triptychID: UUID
) -> [AgentCommandAction] {
    let id = requestID.uuidString.lowercased()
    let selector = triptychID.uuidString.lowercased()
    return [
        AgentCommandAction(
            kind: .complete,
            label: "Submit Recommended Bibliography completion",
            command: [
                "scholium", "bibliography", "complete", "--from", "-",
                "--triptych", selector, "--format", "json",
            ]
        ),
        AgentCommandAction(
            kind: .inspect,
            label: "Show the immutable recommendation request",
            command: [
                "scholium", "bibliography", "show", id,
                "--triptych", selector, "--format", "json",
            ]
        ),
        AgentCommandAction(
            kind: .cancel,
            label: "Cancel this uncompleted recommendation request",
            command: [
                "scholium", "bibliography", "cancel", id,
                "--triptych", selector, "--format", "json",
            ]
        ),
    ]
}

extension WorkspaceHandle {
    func validateBibliographyTarget(
        _ target: RecommendedBibliographyTarget,
        requiresFingerprint: Bool
    ) throws -> WorkspaceNoteSnapshot {
        try requireActive()
        guard let note = currentSnapshot.vaults
            .flatMap(\.documents)
            .first(where: {
                $0.stableIdentity.resolvedID == target.noteID
            }),
              note.id == target.note,
              note.vaultRole == .sourceCorpus,
              note.lifecycle == .active else {
            throw RecommendedBibliographyError.analysisTargetRequired
        }
        if requiresFingerprint, note.fingerprint != target.fingerprint {
            throw RecommendedBibliographyError.targetChanged
        }
        return note
    }

    func resolveBibliographyMethod() async throws -> RecommendedBibliographyMethodSnapshot {
        try requireActive()
        let resolution = try await services.researchSkillStore
            .bibliographyMethodBindingResolution()
        guard resolution.issue == nil, let package = resolution.package,
              let revision = package.revision else {
            throw RecommendedBibliographyError.methodRequiresRepair
        }
        let requiredPaths = [
            "SKILL.md",
            "references/method.md",
            "references/bibliography-recommendations.md",
            "templates/recommended-bibliography-completion.json",
        ]
        let available = try await services.researchSkillStore.resourcePaths(id: package.id)
        guard requiredPaths.allSatisfy(available.contains) else {
            throw RecommendedBibliographyError.methodRequiresRepair
        }
        var resources: [ResearchFunctionResourceSnapshot] = []
        var renderedResources: [RecommendedBibliographyMethodResourceSnapshot] = []
        resources.reserveCapacity(requiredPaths.count)
        renderedResources.reserveCapacity(requiredPaths.count)
        for path in requiredPaths {
            let source = try await services.researchSkillStore.resource(
                id: package.id,
                relativePath: path
            )
            resources.append(ResearchFunctionResourceSnapshot(
                relativePath: path,
                revision: DocumentFingerprint(content: source)
            ))
            renderedResources.append(RecommendedBibliographyMethodResourceSnapshot(
                relativePath: path,
                revision: DocumentFingerprint(content: source),
                source: source
            ))
        }
        return RecommendedBibliographyMethodSnapshot(
            packageID: package.id,
            origin: package.origin,
            version: package.version,
            packageRevision: revision,
            loadedResources: resources,
            renderedResources: renderedResources
        )
    }

    func bibliographyMethodStatus() async throws -> RecommendedBibliographyMethodStatus {
        try requireActive()
        let resolution = try await services.researchSkillStore
            .bibliographyMethodBindingResolution()
        let packages = try await services.researchSkillStore.skills()
        let candidates = resolution.installedCandidateIDs.compactMap { id in
            packages.first(where: { $0.id == id }).map {
                RecommendedBibliographyMethodCandidate(
                    packageID: $0.id,
                    name: $0.name,
                    version: $0.version
                )
            }
        }
        let issue: RecommendedBibliographyMethodIssue?
        switch resolution.issue {
        case .none:
            issue = nil
        case .malformed:
            issue = .malformedBinding
        case .invalidPackage, .unsupportedFunction:
            issue = .invalidPackage
        case .missingCapability, .citationStyleMissing, .citationStyleMismatch, .missing:
            issue = .missingCapability
        }
        return RecommendedBibliographyMethodStatus(
            activePackageID: resolution.source == .triptychBinding
                ? resolution.package?.id
                : nil,
            usesBundledDefault: resolution.source == .bundledDefault
                && resolution.issue == nil,
            candidates: candidates,
            bindingRevision: resolution.bindingRevision,
            issue: issue
        )
    }

    func deriveBibliographyMatches(
        _ candidate: RecommendedBibliographyCandidate
    ) async throws -> RecommendedBibliographyCandidate {
        let source = ZoteroSourceIdentity(
            itemKey: candidate.identity.zoteroItemKey,
            doi: candidate.identity.doi,
            isbn: candidate.identity.isbn,
            citationKey: candidate.identity.citationKey,
            title: candidate.identity.title,
            authors: candidate.identity.authors,
            year: candidate.identity.year
        )
        var zoteroKey: String?
        var ambiguous = false
        if source.itemKey != nil || source.hasFallbackIdentity {
            do {
                switch try await services.zotero.resolve(source: source) {
                case .matched(let item, _):
                    if bibliographyCandidate(candidate.identity, isCompatibleWith: item) {
                        zoteroKey = item.key
                    } else {
                        ambiguous = true
                    }
                case .ambiguous(let items, _):
                    let compatible = items.filter {
                        bibliographyCandidate(candidate.identity, isCompatibleWith: $0)
                    }
                    if compatible.count == 1 {
                        zoteroKey = compatible[0].key
                    } else {
                        ambiguous = true
                    }
                case .notFound, .insufficientMetadata:
                    break
                }
            } catch {
                // Zotero availability must not destroy a source-grounded
                // recommendation. The row remains unmatched and inspectable.
            }
        }

        let analysisMatches = bibliographyAnalysisMatches(candidate.identity)
        if analysisMatches.count > 1 { ambiguous = true }
        if ambiguous {
            return candidate.deriving(
                matchState: .ambiguous,
                matchedZoteroItemKey: zoteroKey
            )
        }
        if let analysis = analysisMatches.first {
            return candidate.deriving(
                matchState: .matchedAnalysis,
                matchedAnalysis: analysis,
                matchedZoteroItemKey: zoteroKey
            )
        }
        if let zoteroKey {
            return candidate.deriving(
                matchState: .matchedZotero,
                matchedZoteroItemKey: zoteroKey
            )
        }
        return candidate
    }

    private func bibliographyAnalysisMatches(
        _ identity: BibliographyCandidateIdentity
    ) -> [VaultQualifiedNoteID] {
        currentSnapshot.vaults
            .flatMap(\.documents)
            .filter { $0.vaultRole == .sourceCorpus && $0.lifecycle == .active }
            .filter { analysis in
                bibliographyIdentityMatches(
                    identity,
                    frontmatter: analysis.document.parsedFrontmatter
                )
            }
            .map(\.id)
    }

    private func bibliographyCandidate(
        _ candidate: BibliographyCandidateIdentity,
        isCompatibleWith item: ZoteroItemMetadata
    ) -> Bool {
        if !candidate.authors.isEmpty,
           normalizedPeople(candidate.authors) != normalizedPeople(item.authors) {
            return false
        }
        if let candidateIsChapter = candidate.isChapter {
            let itemIsChapter = ["booksection", "chapter"]
                .contains(item.itemType?.lowercased() ?? "")
            guard candidateIsChapter == itemIsChapter else { return false }
        }
        if candidate.isChapter == true,
           let container = normalizedTitle(candidate.containerTitle),
           normalizedTitle(item.containerTitle) != container {
            return false
        }
        if let edition = normalizedIdentity(candidate.edition),
           normalizedIdentity(item.edition) != edition {
            return false
        }
        return true
    }

    private func bibliographyIdentityMatches(
        _ candidate: BibliographyCandidateIdentity,
        frontmatter: [String: YAMLValue]
    ) -> Bool {
        let itemKey = frontmatter["zotero_item_key"]?.scalarString
        if let expected = normalizedIdentity(candidate.zoteroItemKey),
           normalizedIdentity(itemKey) == expected { return true }

        let doi = frontmatter["doi"]?.scalarString ?? frontmatter["DOI"]?.scalarString
        if let expected = normalizedDOI(candidate.doi),
           normalizedDOI(doi) == expected { return true }

        let isbn = frontmatter["isbn"]?.scalarString ?? frontmatter["ISBN"]?.scalarString
        if let expected = normalizedISBN(candidate.isbn),
           [10, 13].contains(expected.count),
           normalizedISBN(isbn) == expected { return true }

        let citationKey = frontmatter["zotero_citation_key"]?.scalarString
            ?? frontmatter["citation_key"]?.scalarString
        if let expected = normalizedIdentity(candidate.citationKey),
           normalizedIdentity(citationKey) == expected { return true }

        guard let candidateTitle = normalizedTitle(candidate.title),
              let title = normalizedTitle(frontmatter["title"]?.scalarString),
              title == candidateTitle,
              let candidateYear = candidate.year,
              frontmatter["year"]?.scalarString.flatMap(Int.init) == candidateYear,
              !candidate.authors.isEmpty,
              let candidateIsChapter = candidate.isChapter,
              analysisIsChapter(frontmatter) == candidateIsChapter,
              let rawAuthors = bibliographyPeople(frontmatter["authors"]) else {
            return false
        }
        let authors = rawAuthors.map(normalizedTitle)
        let expectedAuthors = candidate.authors.map(normalizedTitle)
        guard authors.count == expectedAuthors.count,
              zip(authors, expectedAuthors).allSatisfy({ pair in
                  pair.0 == pair.1
              }),
              normalizedIdentity(candidate.edition)
                == normalizedIdentity(frontmatter["edition"]?.scalarString),
              candidate.translators.map(normalizedTitle)
                == (bibliographyPeople(frontmatter["translators"]) ?? []).map(normalizedTitle)
        else { return false }

        if candidateIsChapter {
            let container = frontmatter["container_title"]?.scalarString
                ?? frontmatter["book_title"]?.scalarString
            guard normalizedTitle(candidate.containerTitle) != nil,
                  normalizedTitle(candidate.containerTitle) == normalizedTitle(container),
                  candidate.editors.map(normalizedTitle)
                    == (bibliographyPeople(frontmatter["editors"]) ?? []).map(normalizedTitle)
            else { return false }
        }
        return true
    }
}

private func bibliographyInstructions(
    request: RecommendedBibliographyRequest,
    requestID: UUID,
    confirmationToken: UUID,
    method: RecommendedBibliographyMethodSnapshot,
    triptychID: UUID
) throws -> String {
    let exampleGoal = request.goals.first ?? .backgroundReading
    let exampleCandidate = RecommendedBibliographyCandidate(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        identity: BibliographyCandidateIdentity(
            rawCitation: "REPLACE with the exact raw citation",
            title: "REPLACE with the verified title when known",
            authors: ["REPLACE with every known source author in order"],
            year: 2000,
            doi: "10.0000/replace-when-verified",
            isbn: "9780000000000",
            citationKey: "replace-when-verified",
            zoteroItemKey: "REPLACE1",
            isChapter: true,
            containerTitle: "REPLACE with the edited volume title",
            editors: ["REPLACE with every known editor in order"],
            edition: "REPLACE when applicable",
            translators: ["REPLACE when applicable"]
        ),
        goals: [exampleGoal],
        reason: "REPLACE with the source-grounded reason to inspect this item",
        possibleUse: "REPLACE with a neutral possible use, or omit this field",
        uncertainty: "REPLACE with what remains unverified, or omit this field",
        evidence: BibliographyRecommendationEvidence(
            discussionStatus: .substantivelyDiscussed,
            sourceLocators: ["REPLACE with an exact locator"],
            authorialFraming: .central,
            metadataVerified: false,
            sourceInspected: false,
            verificationProvenance: "REPLACE with exact provenance, or omit this field"
        ),
        requiredNextCheck: "REPLACE with one bounded verification step"
    )
    let completion = RecommendedBibliographyCompletionSubmission(
        requestID: requestID,
        confirmationToken: confirmationToken,
        targetFingerprint: request.target.fingerprint,
        sourceScope: "REPLACE with the exact source unit inspected",
        candidates: [exampleCandidate]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let completionJSON = String(decoding: try encoder.encode(completion), as: UTF8.self)
    let goals = request.goals.isEmpty
        ? "neutral source-centered screening"
        : request.goals.map(\.rawValue).joined(separator: ", ")
    let renderedMethod = method.renderedResources.map { resource in
        """
        <scholium-method-resource path="\(resource.relativePath)" sha256="\(resource.revision.sha256)">
        \(resource.source)
        </scholium-method-resource>
        """
    }.joined(separator: "\n\n")
    return """
    # Scholium Recommended Bibliography

    Reading leads, not evidence. This request does not authorize a note edit or a Zotero write.

    Triptych ID: \(triptychID.uuidString.lowercased())
    Request ID: \(requestID.uuidString.lowercased())
    Confirmation token: \(confirmationToken.uuidString.lowercased())
    Analysis: \(request.target.title) [\(request.target.note.relativePath)]
    Analysis note ID: \(request.target.noteID.uuidString.lowercased())
    Analysis revision: \(request.target.fingerprint.sha256) (\(request.target.fingerprint.byteCount) bytes)
    Goals: \(goals)
    Purpose: \(request.purpose ?? "No researcher position supplied; remain neutral.")
    Method: \(method.packageID) @ \(method.packageRevision.sha256)

    Read the exact Analysis and only the source material actually available. Apply the immutable Source Analyzer resources below. Distinguish a reference-list occurrence, in-text citation, substantive discussion, authorial appraisal, metadata verification, and independent source inspection. Do not rate unread candidates or infer project relevance. Zero recommendations is a valid result.

    The JSON example below contains one illustrative candidate only to expose the complete wire schema. Replace every `REPLACE` value, remove fields whose evidence is unavailable, and use `"candidates": []` when no recommendation is warranted. Keep `matchState` as `unmatched`, `isDismissed` as `false`, and omit all other Scholium-owned matching fields.

    Immutable method resources:

    \(renderedMethod)

    Complete submission example:

    ```json
    \(completionJSON)
    ```

    Submit with: scholium bibliography complete --from <file|-> --triptych \(triptychID.uuidString.lowercased()) --format json
    Recover this request with: scholium bibliography show \(requestID.uuidString.lowercased()) --triptych \(triptychID.uuidString.lowercased()) --format markdown
    Cancel with: scholium bibliography cancel \(requestID.uuidString.lowercased()) --triptych \(triptychID.uuidString.lowercased())
    """
}

private func normalizedIdentity(_ value: String?) -> String? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized?.isEmpty == false ? normalized : nil
}

private func normalizedDOI(_ value: String?) -> String? {
    normalizedIdentity(value)?
        .replacingOccurrences(of: "https://doi.org/", with: "")
        .replacingOccurrences(of: "doi:", with: "")
}

private func normalizedISBN(_ value: String?) -> String? {
    normalizedIdentity(value)?.filter { $0.isNumber || $0 == "x" }
}

private func normalizedTitle(_ value: String?) -> String? {
    normalizedIdentity(value)?.filter { $0.isLetter || $0.isNumber }
}

private func normalizedPeople(_ values: [String]) -> [String] {
    values.compactMap { value in
        let tokens = value
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .sorted()
        return tokens.isEmpty ? nil : tokens.joined(separator: " ")
    }
}

private func bibliographyPeople(_ value: YAMLValue?) -> [String]? {
    guard case .array(let values)? = value else { return nil }
    return values.compactMap(\.scalarString)
}

private func analysisIsChapter(_ frontmatter: [String: YAMLValue]) -> Bool? {
    if let explicit = frontmatter["is_chapter"]?.scalarString?.lowercased() {
        if ["true", "yes", "1"].contains(explicit) { return true }
        if ["false", "no", "0"].contains(explicit) { return false }
    }
    let type = (frontmatter["source_type"]?.scalarString
        ?? frontmatter["item_type"]?.scalarString
        ?? frontmatter["type"]?.scalarString)?.lowercased()
    guard let type else { return nil }
    if ["chapter", "book chapter", "book_chapter"].contains(type) { return true }
    if ["article", "journal article", "paper", "book", "monograph"].contains(type) {
        return false
    }
    return nil
}
