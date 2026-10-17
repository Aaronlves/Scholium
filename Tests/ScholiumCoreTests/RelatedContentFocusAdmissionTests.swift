import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related content focus admission")
struct RelatedContentFocusAdmissionTests {
    @Test("Early focused identity filtering preserves the all-segments oracle and ordinary source mentions")
    func focusedIdentityEarlyFilterParity() {
        let seed = NoteDocument(
            relativePath: "Draft.md",
            rawContent:
                "\u{FEFF}---\r\nsummary: Source Only and façade\r\nunknown: retained\r\n---\r\n\r\nFree Will, 自由agency and Source Only occur in surrounding source. café e\u{301} 🧭\r\n"
        )
        let projection = SearchDocumentProjection(document: seed)
        let focusCases: [[RelatedContentSeedFocus]] = [
            [],
            [.init(kind: .selectedPassage, text: "Compare FREE WILL with façade and 自由agency.")],
            [.init(kind: .researchRequest, text: "Free Will 自由agency", literalAlternatives: ["Free", "Will", "自由agency"])],
            [.init(kind: .selectedPassage, text: "Free Will"), .init(kind: .researchRequest, text: "façade")],
        ]
        let candidates = [
            NoteDocument(relativePath: "Free Will.md", rawContent: "---\naliases: [façade, 自由agency]\n---\n\nFree Will is locally named."),
            NoteDocument(relativePath: "Source Only.md", rawContent: "Source Only occurs here."),
            NoteDocument(relativePath: "Only.md", rawContent: "---\naliases: [only, never]\n---\n\nUnrelated text."),
            NoteDocument(relativePath: "Malformed.md", rawContent: "---\naliases: [broken\n---\n\nFree Will remains authored."),
        ]
        for focuses in focusCases {
            let material = RelatedContentSeedMaterial(projection: projection, focuses: focuses)
            for candidate in candidates {
                let aliases = SearchPropertyProjection(document: candidate).textValues(forExactKey: "aliases")
                let title = ResearchNoteTitleResolver.resolve(document: candidate)
                let all = material.identityMentionReason(title: title, aliases: aliases, includingSourceNote: true)?.mentions ?? []
                let reference = all.filter(RelatedContentRecommendationPolicy.isFocusedIdentity)
                let focused = material.identityMentionReason(title: title, aliases: aliases, includingSourceNote: false)?.mentions ?? []
                #expect(focused.filter(RelatedContentRecommendationPolicy.isFocusedIdentity) == reference)
                #expect(focused.allSatisfy { $0.seedKind != .sourceNote })
                #expect(RelatedContentRecommendationPolicy.focusedIdentityMentions(in: candidate, material: material) == reference)
            }
        }
        let sourceOnly = RelatedContentSeedMaterial(projection: projection, focuses: [])
        #expect(
            sourceOnly.identityMentionReason(title: "Source Only", aliases: [], includingSourceNote: true)?.mentions.contains { $0.seedKind == .sourceNote }
                == true)
        #expect(sourceOnly.identityMentionReason(title: "Source Only", aliases: [], includingSourceNote: false) == nil)
    }

    @Test(
        "Opt-in paired focused identity scan over actual Stress sources",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_FOCUSED_IDENTITY"] == "1"))
    func measureFocusedIdentityEarlyFilter() throws {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build", isDirectory: true)
        let fixture = URL(fileURLWithPath: try #require(environment["SCHOLIUM_STRESS_FIXTURE"])).standardizedFileURL
        try #require(fixture.path.hasPrefix(buildRoot.path + "/") && fixture == fixture.resolvingSymlinksInPath())
        let manifestURL = fixture.appendingPathComponent("stress-manifest.json")
        let manifestBytes = try Data(contentsOf: manifestURL)
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestBytes) as? [String: Any])
        try #require(manifest["synthetic_nonprivate"] as? Bool == true)
        let inventory = try #require(manifest["files"] as? [String: [String: Any]])
        let scenarios = try #require(manifest["scenarios"] as? [String: String])
        let searchOracles = try #require(manifest["search_oracles"] as? [[String: Any]])
        let namedTarget = try #require((searchOracles.first { $0["label"] as? String == "rare_body" }?["expected_paths"] as? [String])?.first)
        let paths = inventory.keys.filter { path in
            path.lowercased().hasSuffix(".md")
                && ["01-analyses/", "02-topics/", "03-works/"].contains { path.hasPrefix($0) }
        }.sorted()
        try #require(paths.count == 5_000 && paths.contains(namedTarget))
        let targetCount = try #require(Int(environment["SCHOLIUM_FOCUS_IDENTITY_TARGET_COUNT"] ?? "256"))
        try #require((1...5_000).contains(targetCount))
        // Stable quantiles cover all three roles; the selected Dense Links
        // paragraph's first named destination remains a positive control.
        var targetPaths = [namedTarget]
        var chosen = Set(targetPaths)
        for index in 0..<targetCount {
            let path = paths[index * paths.count / targetCount]
            if targetPaths.count < targetCount, chosen.insert(path).inserted { targetPaths.append(path) }
        }
        for path in paths where targetPaths.count < targetCount {
            if chosen.insert(path).inserted { targetPaths.append(path) }
        }
        try #require(targetPaths.count == targetCount)
        func readChecked(_ path: String) throws -> Data {
            let url = fixture.appendingPathComponent(path).standardizedFileURL
            try #require(url.path.hasPrefix(fixture.path + "/") && url == url.resolvingSymlinksInPath())
            let bytes = try Data(contentsOf: url)
            try #require(bytes.count == inventory[path]?["bytes"] as? Int)
            try #require(DocumentFingerprint(data: bytes).sha256 == inventory[path]?["sha256"] as? String)
            return bytes
        }
        var targets: [(title: String, aliases: [String])] = []
        var inputRecords: [[String: Any]] = []
        for path in targetPaths {
            let bytes = try readChecked(path)
            let text = String(decoding: bytes, as: UTF8.self)
            try #require(Data(text.utf8) == bytes)
            let document = NoteDocument(relativePath: path, rawContent: text)
            let title = ResearchNoteTitleResolver.resolve(document: document)
            let aliases = SearchPropertyProjection(document: document).textValues(forExactKey: "aliases")
            targets.append((title, aliases))
            inputRecords.append(["path": path, "source_sha256": document.fingerprint.sha256, "title": title, "aliases": aliases])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let targetHash = DocumentFingerprint(data: try JSONSerialization.data(withJSONObject: inputRecords, options: [.sortedKeys])).sha256
        var records: [[String: Any]] = []
        for scenario in ["long_prose", "dense_links"] {
            let path = try #require(scenarios[scenario])
            let bytes = try readChecked(path)
            let text = String(decoding: bytes, as: UTF8.self)
            try #require(Data(text.utf8) == bytes)
            let document = NoteDocument(relativePath: path, rawContent: text)
            let projection = SearchDocumentProjection(document: document)
            let pattern = scenario == "long_prose" ? #"(?m)^Record [^\r\n]+"# : #"(?m)^\[\[Stress Note [^\r\n]+"#
            let match = try #require(
                try NSRegularExpression(pattern: pattern).firstMatch(
                    in: text, range: NSRange(location: 0, length: text.utf16.count)))
            let focusRange = try #require(Range(match.range, in: text))
            let focus = String(text[focusRange])
            let material = RelatedContentSeedMaterial(projection: projection, focuses: [.init(kind: .selectedPassage, text: focus)])
            func scan(includingSourceNote: Bool) -> [[RelatedContentIdentityMention]] {
                targets.map { target in
                    (material.identityMentionReason(
                        title: target.title, aliases: target.aliases, includingSourceNote: includingSourceNote)?.mentions ?? [])
                        .filter(RelatedContentRecommendationPolicy.isFocusedIdentity)
                }
            }
            var samples: [[String: Any]] = []
            var reference: [[RelatedContentIdentityMention]]?
            var expectedHash: String?
            for pair in 0..<4 {
                for includesSource in (pair.isMultiple(of: 2) ? [true, false] : [false, true]) {
                    let mode = includesSource ? "all_then_filter" : "early_filter"
                    let marker: [String: Any] = ["phase": "begin", "scenario": scenario, "pair": pair, "mode": mode, "targets": targets.count]
                    FileHandle.standardOutput.write(
                        Data("FOCUS_IDENTITY ".utf8)
                            + (try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])) + Data([0x0A]))
                    let started = ContinuousClock.now
                    let result = scan(includingSourceNote: includesSource)
                    let duration = started.duration(to: .now).components
                    let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
                    if let reference { try #require(result == reference) } else { reference = result }
                    let hash = DocumentFingerprint(data: try encoder.encode(result)).sha256
                    if let expectedHash { try #require(hash == expectedHash) } else { expectedHash = hash }
                    let row: [String: Any] = [
                        "scenario": scenario, "pair": pair, "mode": mode, "excluded_warmup": pair == 0,
                        "milliseconds": milliseconds, "ordered_mentions_sha256": hash,
                        "mention_count": result.reduce(0) { $0 + $1.count }, "target_count": targets.count,
                    ]
                    samples.append(row)
                    FileHandle.standardOutput.write(
                        Data("FOCUS_IDENTITY ".utf8)
                            + (try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])) + Data([0x0A]))
                }
            }
            if scenario == "dense_links" {
                try #require(reference?.contains { !$0.isEmpty } == true)
            }
            try #require(try readChecked(path) == bytes)
            records.append([
                "scenario": scenario, "source_sha256": document.fingerprint.sha256,
                "source_utf16_count": text.utf16.count, "focus_sha256": DocumentFingerprint(content: focus).sha256,
                "focus_lower": match.range.location, "focus_upper": NSMaxRange(match.range), "samples": samples,
            ])
        }
        for path in targetPaths { _ = try readChecked(path) }
        try #require(try Data(contentsOf: manifestURL) == manifestBytes)
        let output = buildRoot.appendingPathComponent("stress-audit/focus-identity", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let report: [String: Any] = [
            "schema": "scholium-focused-identity-causal-diagnostic-v1",
            "fixture_manifest_sha256": DocumentFingerprint(data: manifestBytes).sha256,
            "target_input_sha256": targetHash, "target_count": targets.count,
            "sampling":
                "One excluded warmup pair, three measured pairs, alternating execution order. Same compiled API receives true then filters versus false then filters.",
            "scope":
                "Identity matching only; fixture reads, Note/YAML/title/alias/source projection preparation, output encoding and equality checks are outside timers. No complete Related, cache, native UI or release-gate claim.",
            "configuration": _isDebugAssertConfiguration() ? "SwiftPM Debug" : "SwiftPM Release",
            "selected_sources_unchanged": true, "records": records,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        let url = output.appendingPathComponent("focused-identity-\(UUID().uuidString.lowercased()).json")
        try data.write(to: url, options: .atomic)
        FileHandle.standardOutput.write(Data("FOCUS_IDENTITY_REPORT \(url.path)\n".utf8))
    }

    @Test("The selected concept Being remains retrievable without quotation marks")
    func selectedBeing() async throws {
        let result = try await evaluate(
            focus: "Being",
            notes: [
                "Exact.md": "Being names the topic of this authored paragraph.",
                "Nonexact.md": "Beings names a different literal word.",
                "Metadata.md": "---\nkeywords: [being]\n---\n\nA paragraph about unrelated catering expenses.",
            ])
        #expect(result.paths == ["Exact.md"])
        #expect(result.passages.first?.matches.filter { $0.seedKind == .selectedPassage }.flatMap(\.terms) == ["being"])
        #expect(result.stages["Metadata.md"]?.contains(.noLocalMatch) == true)
    }

    @Test(
        "Explicit quotes recall short and ordinary-filtered wording only when it occurs locally",
        arguments: [
            ("being", "beings"), ("I", "identity"), ("is", "isness"), ("as if", "as something if"),
        ])
    func quotedFilteredWording(input: (String, String)) async throws {
        let (literal, nonexact) = input
        let result = try await evaluate(
            focus: "\"\(literal)\"",
            notes: [
                "Exact.md": "The authored expression \(literal) occurs in this paragraph.",
                "Nonexact.md": "The authored expression \(nonexact) occurs in this paragraph.",
                "Metadata.md": "---\nkeywords: [\"\(literal)\"]\n---\n\nA paragraph about unrelated catering expenses.",
            ])
        #expect(result.paths == ["Exact.md"])
        #expect(result.passages.first?.matches.filter { $0.seedKind == .selectedPassage }.flatMap(\.terms) == [literal.lowercased()])
        #expect(result.stages["Metadata.md"]?.contains(.noLocalMatch) == true)
    }

    @Test("An otherwise-filtered quotation remains a local witness inside a long writing focus")
    func quotedFilteredWordingInLongFocus() async throws {
        let context = (0..<100).map { "context\($0)" }
        let focus =
            context.prefix(40).joined(separator: " ") + " “as if” "
            + context.dropFirst(40).joined(separator: " ") + " freedom autonomy"
        let result = try await evaluate(
            focus: focus,
            notes: [
                "Exact.md": "As if names the explicitly authored wording in this paragraph.",
                "Nonexact.md": "As something if separates the two authored words.",
                "Metadata.md": "---\nkeywords: [as if]\n---\n\nAn unrelated paragraph about catering.",
            ])
        #expect(result.paths == ["Exact.md"])
        #expect(result.passages.first?.matches.filter { $0.seedKind == .selectedPassage }.flatMap(\.terms) == ["as if"])
        #expect(result.stages["Exact.md"]?.contains(.eligible) == true)
    }

    @Test("One authored translation admits a paragraph without its other language")
    func oneLiteralAlternative() async throws {
        let notes = ["Source.md": "我们在这里讨论自由的限度。"]
        #expect(try await evaluate(focus: "freedom", notes: notes).paths.isEmpty)
        let result = try await evaluate(focus: "freedom", alternatives: ["freedom", "自由"], notes: notes)
        #expect(result.paths == ["Source.md"])
        #expect(result.passages.first?.matches.filter { $0.seedKind == .researchRequest }.flatMap(\.terms) == ["自由"])
    }

    @Test("Authored phrases retain exact bilingual alternative provenance and reject partial or metadata-only matches")
    func literalPhraseProvenance() async throws {
        let result = try await evaluate(
            focus: "unrelated selection", alternatives: ["Free Will", "自由意志"],
            notes: [
                "Latin.md": "FREE WILL is considered in this invented source passage.",
                "Chinese.md": "这里讨论自主的自由意志与责任。",
                "Partial.md": "这里只有自由。另一处出现由意，随后出现意志。",
                "Separated.md": "Free — will are separated by punctuation in this fixture.",
                "Metadata.md": "---\nkeywords: [Free Will]\n---\n\nA paragraph about unrelated catering expenses.",
            ])
        #expect(result.paths == ["Latin.md", "Chinese.md"])
        for (path, term) in [("Latin.md", "Free Will"), ("Chinese.md", "自由意志")] {
            let passage = try #require(result.passages.first { $0.candidate.note.relativePath == path })
            #expect(passage.matches.filter { $0.seedKind == .researchRequest }.flatMap(\.terms) == [term])
        }
    }

    @Test("Literal alternative boundaries do not manufacture a Note identity while ordinary research requests retain prose matching")
    func literalIdentityBoundaries() {
        let projection = SearchDocumentProjection(document: .init(relativePath: "Draft.md", rawContent: "unrelated"))
        let ordinary = RelatedContentSeedMaterial(projection: projection, focuses: [.init(kind: .researchRequest, text: "free will")])
        #expect(ordinary.termGroups.first?.terms == ["free", "will"])
        #expect(ordinary.identityMentionReason(title: "Free Will", aliases: [], includingSourceNote: true)?.mentions.first?.seedKind == .researchRequest)
        let alternatives = RelatedContentSeedMaterial(
            projection: projection, focuses: [.init(kind: .researchRequest, text: "free will", literalAlternatives: ["free", "will"])])
        #expect(alternatives.identityMentionReason(title: "Free Will", aliases: [], includingSourceNote: true) == nil)
    }

    @Test("A locally repeated named concept survives a longer writing request", arguments: [0, 500])
    func namedConcept(distractors: Int) async throws {
        var notes = [
            "Defeasibility.md": "Defeasibility concerns reasons that can lose their justificatory force when further information appears.",
            "Evidence.md": "Evidence should be collected before comparing possible explanations.",
            "Event.md": "This question requires a careful discussion of the relation between event evidence and catering expenses.",
        ]
        for index in 0..<distractors {
            notes["Background-\(index).md"] = "A question about room \(index) prompted a discussion of catering expenses."
        }
        let result = try await evaluate(
            focus: "This question requires a careful discussion of the relation between evidence and defeasibility.",
            notes: notes)
        #expect(result.paths.contains("Defeasibility.md"))
        #expect(result.paths.contains("Evidence.md"))
        #expect(result.stages["Defeasibility.md"]?.contains(.eligible) == true)
    }

    @Test(
        "A complete title or alias omitted by long-focus sampling still supplies a local witness",
        arguments: [("Defeasibility", false), ("Free Will", false), ("façade", true), ("自由意志", true)])
    func longFocusIdentity(input: (String, Bool)) async throws {
        let (identity, alias) = input
        let context = (0..<400).map { SearchTokenization.containsCJK(identity) ? "语境\($0)" : "context\($0)" }
        let focus = context.prefix(2).joined(separator: " ") + " \(identity) " + context.dropFirst(2).joined(separator: " ")
        let sampled = RelatedContentQueryTerms.terms(in: focus, limit: RelatedContentContract.maximumFocusSeedTerms)
        #expect(RelatedContentTermMatcher(terms: sampled).matchingTerms(in: SearchTextNormalization.lexicalNormalize(identity)).isEmpty)
        let path = alias ? "Glossary.md" : "\(identity).md"
        let properties = alias ? "---\naliases: [\(identity)]\n---\n\n" : ""
        let result = try await evaluate(
            focus: focus,
            notes: [
                path: properties
                    + "\(identity.decomposedStringWithCanonicalMapping.uppercased()) names the explicitly selected subject in this invented paragraph.",
                "Metadata.md": "---\nkeywords: [\(identity)]\n---\n\nAn unrelated paragraph about catering.",
            ])
        #expect(result.paths == [path])
        #expect(result.stages[path]?.contains(.eligible) == true)
        let passage = try #require(result.passages.first)
        let normalizedIdentity = SearchTextNormalization.lexicalNormalize(identity)
        #expect(passage.matches.filter { $0.seedKind == .selectedPassage }.flatMap(\.terms) == [normalizedIdentity])
        let highlighted = try passage.excerptMatches.map { range in
            let sourceRange = try #require(
                Range(NSRange(location: range.lowerBound, length: range.count), in: passage.excerpt))
            return SearchTextNormalization.lexicalNormalize(String(passage.excerpt[sourceRange]))
        }
        #expect(highlighted.contains(normalizedIdentity))
    }

    @Test("Restoring omitted names does not add lexical weight to names already represented in focus")
    func sampledNamesKeepTheirWeight() throws {
        let projection = SearchDocumentProjection(document: .init(relativePath: "Draft.md", rawContent: "unrelated source"))
        var material = RelatedContentSeedMaterial(
            projection: projection, focuses: [.init(kind: .selectedPassage, text: "Please compare free will and defeasibility.")])
        let original = material.termGroups.map(\.terms)
        material.includeUnsampledFocusedIdentities(
            try #require(material.identityMentionReason(title: "Free Will", aliases: ["Defeasibility"], includingSourceNote: true)).mentions)
        #expect(material.termGroups.map(\.terms) == original)
    }

    @Test("Long-focus title and alias admission survives the bounded identity channel")
    func longFocusIdentityChannelLimit() async throws {
        let context = (0..<400).map { "context\($0)" }
        let focus =
            context.prefix(40).joined(separator: " ") + " Aster Beryl Citrine Dolomite emerald "
            + context.dropFirst(40).joined(separator: " ")
        let sampled = Set(RelatedContentQueryTerms.terms(in: focus, limit: RelatedContentContract.maximumFocusSeedTerms))
        #expect(sampled.isDisjoint(with: ["aster", "beryl", "citrine", "dolomite", "emerald"]))
        let notes = [
            "Aster.md": "Aster names the first invented specimen.",
            "Beryl.md": "Beryl names the second invented specimen.",
            "Citrine.md": "Citrine names the third invented specimen.",
            "Dolomite.md": "Dolomite names the fourth invented specimen.",
            "Z Glossary.md": "---\naliases: [emerald]\n---\n\nEmerald names the fifth invented specimen.",
        ]
        let result = try await evaluate(focus: focus, notes: notes)
        #expect(result.paths == Set(notes.keys))
        #expect(result.stages["Dolomite.md"]?.contains(.eligible) == true)
        #expect(result.stages["Z Glossary.md"]?.contains(.eligible) == true)
    }

    @Test("An omitted full name still requires a complete paragraph witness and explicit focus mention")
    func longFocusIdentityNeedsLocalWitness() async throws {
        let context = (0..<100).map { "context\($0)" }
        let focus = context.prefix(40).joined(separator: " ") + " Crystalline Memory " + context.dropFirst(40).joined(separator: " ")
        let result = try await evaluate(
            focus: focus, surrounding: "Glacial Sediment is mentioned only outside the selected focus.",
            notes: [
                "Crystalline Memory.md": "Memory of an office meeting is recorded here.",
                "Metadata.md": "---\naliases: [Crystalline Memory]\n---\n\nAnnual catering expenses are recorded here.",
                "Glacial Sediment.md": "Glacial Sediment names a different invented subject.",
                "Partial.md": "Crystalline memories use a different literal word.",
            ])
        #expect(result.paths.isEmpty)
        #expect(result.stages["Crystalline Memory.md"]?.contains(.noLocalMatch) == true)
        #expect(result.stages["Metadata.md"]?.contains(.noLocalMatch) == true)
    }

    @Test("A wrong-path source cannot contribute focus names or hide the valid source for its candidate")
    func mismatchedSourceCannotEnrichFocus() throws {
        let vault = UUID()
        let context = (0..<100).map { "context\($0)" }
        let focus = context.prefix(40).joined(separator: " ") + " Crystalline Memory " + context.dropFirst(40).joined(separator: " ")
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: vault, relativePath: "Draft.md"), source: focus,
                focuses: [.init(kind: .selectedPassage, text: focus)]))
        func source(_ path: String, documentPath: String? = nil, body: String) -> RelatedContentSource {
            let document = NoteDocument(relativePath: documentPath ?? path, rawContent: body)
            return .init(
                candidate: .init(
                    note: .init(vaultID: vault, relativePath: path), vaultRole: .topicKnowledge, title: path,
                    fingerprint: document.fingerprint, reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: []))),
                document: document)
        }
        let control = source("Control.md", body: "Context98 context99 remain the independent local control.")
        let unnamed = source("Material.md", body: "Crystalline Memory names a synthetic subject.")
        let wrongPath = source("Control.md", documentPath: "Crystalline Memory.md", body: "An unrelated paragraph.")
        let baseline = try TriptychSearchIndex.relatedPassages(request, sources: [control, unnamed])
        #expect(baseline.map(\.candidate.note.relativePath) == ["Control.md"])
        var rejected: [VaultQualifiedNoteID] = []
        let actual = try TriptychSearchIndex.relatedPassages(request, sources: [wrongPath, control, unnamed]) { diagnostic in
            if diagnostic.stage == .rejectedSource { rejected.append(diagnostic.note) }
        }
        #expect(actual == baseline)
        #expect(rejected == [wrongPath.candidate.note])
    }

    @Test("A complete explicit alias is locally corroborated through canonical normalization")
    func aliasAdmission() async throws {
        let result = try await evaluate(
            focus: "Please compare the discussion of façade with the available architectural evidence.",
            notes: [
                "Glossary.md": "---\naliases: [façade]\n---\n\nFAC\u{0327}ADE is the authored term in this small fixture.",
                "Office.md": "Please compare the discussion of the available architectural evidence at the office meeting.",
            ])
        #expect(result.stages["Glossary.md"]?.contains(.localMatch) == true)
        #expect(result.stages["Glossary.md"]?.contains(.eligible) == true)
        #expect(result.paths.contains("Glossary.md"))
    }

    @Test("Focused-name admission is independent of the three-identity candidate channel limit")
    func identityChannelLimit() async throws {
        let notes = [
            "Aster.md": "Aster names the first sample.",
            "Beryl.md": "Beryl names the second sample.",
            "Citrine.md": "Citrine names the third sample.",
            "Dolomite.md": "Dolomite names the fourth sample.",
            "Z Glossary.md": "---\naliases: [emerald]\n---\n\nEmerald names the fifth sample.",
        ]
        let result = try await evaluate(
            focus: "Please compare Aster, Beryl, Citrine, Dolomite and emerald while considering where specimens occur.", notes: notes)
        #expect(result.paths == Set(notes.keys))
        #expect(result.stages["Dolomite.md"]?.contains(.eligible) == true)
        #expect(result.stages["Z Glossary.md"]?.contains(.eligible) == true)
    }

    @Test("Identity context cannot admit metadata-only or incomplete identity matches")
    func identityNeedsLocalCorroboration() async throws {
        let result = try await evaluate(
            focus: "Please examine crystalline memory together with glacial sediment evidence.",
            notes: [
                "Crystalline Memory.md": "Memory of an office meeting is recorded here.",
                "Glacial Sediment.md": "---\nkeywords: [glacial, sediment]\n---\n\nAnnual catering expenses are recorded here.",
                "Material.md": "Glacial sediment and crystalline memory are the two exact phrases in this invented fixture.",
            ])
        #expect(result.paths == ["Material.md"])
        #expect(result.stages["Crystalline Memory.md"]?.contains(.insufficientFocus) == true)
        #expect(result.stages["Glacial Sediment.md"]?.contains(.noLocalMatch) == true)
    }

    @Test("A Note named only in surrounding source does not bypass selected-focus coverage")
    func surroundingIdentityIsNotFocus() async throws {
        let result = try await evaluate(
            focus: "spectral calibration measurement",
            surrounding: "Appendix is discussed elsewhere.",
            notes: [
                "Appendix.md": "Calibration of an office printer is scheduled for tomorrow.",
                "Material.md": "Spectral calibration measurement uses a reference lamp.",
            ])
        #expect(result.paths == ["Material.md"])
    }

    @Test("A negation-only Note name supplies no single-term exception")
    func negationIsNotIdentityEvidence() async throws {
        let result = try await evaluate(
            focus: "not spectral calibration measurement",
            notes: [
                "Not.md": "Not an available fixture.",
                "Material.md": "Spectral calibration measurement uses a reference lamp.",
            ])
        #expect(result.paths == ["Material.md"])
    }

    @Test("Diagnostics distinguish duplicate material and result limits from focus rejection")
    func terminalDiagnostics() async throws {
        var notes = ["A Copy.md": "Spectral calibration.", "B Copy.md": "Spectral calibration."]
        for number in 0..<8 {
            notes["Material-\(number).md"] = "Spectral calibration measures fixture \(number)."
        }
        let result = try await evaluate(focus: "spectral calibration", notes: notes)
        #expect(result.paths.count == RelatedContentContract.maximumPassages)
        #expect(result.stages["B Copy.md"]?.contains(.duplicate) == true)
        #expect(result.stages.values.contains { $0.contains(.limited) })
        for (path, stages) in result.stages {
            let terminal = stages.intersection([.selected, .duplicate, .limited])
            #expect(terminal.count == 1)
            #expect(stages.contains(.eligible))
            #expect(stages.contains(.selected) == result.paths.contains(path))
        }
    }

    private struct Result {
        let paths: Set<String>
        let stages: [String: Set<RelatedContentRankingDiagnostic.Stage>]
        let passages: [RelatedContentPassage]
    }

    private func evaluate(focus: String, surrounding: String = "", alternatives: [String] = [], notes: [String: String]) async throws -> Result {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/related-focus-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/synthetic/topics")
        let index = try TriptychSearchIndex(isolatedDatabaseURL: root.appendingPathComponent("index.sqlite"), triptychID: UUID(), vaults: [vault])
        let documents = notes.sorted { $0.key < $1.key }.map { path, text in
            SearchIndexDocument(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: .init(relativePath: path, rawContent: "\u{FEFF}" + text.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"))
        }
        _ = try await index.synchronize(documents)
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: vault.id, relativePath: "Current.md"), source: surrounding + "\n\n" + focus,
                focuses: [.init(kind: .selectedPassage, text: focus)]
                    + (alternatives.isEmpty
                        ? [] : [.init(kind: .researchRequest, text: alternatives.joined(separator: " "), literalAlternatives: alternatives)])))
        let response = try await index.relatedMaterialSourceCandidates(request)
        var seen = Set<VaultQualifiedNoteID>()
        let candidates = (response.identityCandidates + response.lexicalCandidates).filter { seen.insert($0.note).inserted }
        let sources = try candidates.map { candidate in
            RelatedContentSource(
                candidate: candidate, document: try #require(documents.first { $0.document.relativePath == candidate.note.relativePath }).document)
        }
        var stages: [String: Set<RelatedContentRankingDiagnostic.Stage>] = [:]
        let passages = try TriptychSearchIndex.relatedPassages(request, sources: sources) {
            stages[$0.note.relativePath, default: []].insert($0.stage)
        }
        #expect(try await index.relatedPassages(request, sources: sources) == passages)
        #expect(try TriptychSearchIndex.relatedPassages(request, sources: sources.reversed()) == passages)
        for passage in passages {
            let original = try #require(sources.first { $0.candidate.note == passage.candidate.note })
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: original.document.rawContent))
            #expect(String(original.document.rawContent[range]) == passage.source)
            #expect(passage.candidate.fingerprint == original.document.fingerprint)
        }
        return .init(paths: Set(passages.map { $0.candidate.note.relativePath }), stages: stages, passages: passages)
    }
}
