---
name: scholium-markdown-yaml-fidelity
description: Implement, review, diagnose, or test Scholium's lossless Markdown and YAML frontmatter pipeline. Use for NoteDocument, MarkdownEngine, FrontmatterService, role-aware schema projection, source/body/property edits, delimiter detection, Yams validation, nested read-only metadata, topic notes without YAML, dissertation-control v3/v4 source handling, Unicode or BOM handling, newline preservation, or any bug where reading or saving a .md file could normalize, drop, reinterpret, or corrupt user-authored source.
---

# Scholium Markdown and YAML Fidelity

Treat exact source preservation as a product contract. Parsed YAML, rendered Markdown, and editor projections are derived views of the user's UTF-8 file, never replacement authorities.

## Locate the checkout

Do not infer the project path from this skill's installed location. Bind one repository root containing `AGENTS.md`, `Package.swift`, `ScholiumCore/`, and `Scholium/`. If the current scope does not contain one unique root, stop and request the checkout. Resolve all paths below from the repository root.

Pair this skill with `scholium-development` for repository-wide implementation and final verification, `scholium-trust-boundary-audit` for authorized writes, and `scholium-markdown-editor-integration` for the active editor buffer, payload, and autosave behavior.

## Inspect live ownership

Read the directly affected parts of:

- `ScholiumCore/DocumentTypes.swift` for exact bytes, delimiters, ranges, validation, and targeted patches;
- `ScholiumCore/VaultRepository.swift` for the only authoritative write path;
- `ScholiumCore/WorkspaceRegistry.swift`, `WorkflowSchema.swift`, and `DissertationControlV4.swift` for registered role and versioned profile selection;
- `Scholium/Services/MarkdownEngine.swift` and `FrontmatterService.swift` for app projections;
- `Scholium/Models/Models.swift` for typed frontmatter values;
- `Scholium/Views/Note/NoteContentView.swift` and the active editor adapter for the payload actually submitted to autosave;
- `Tests/ScholiumCoreTests/NoteDocumentTests.swift` and the active package test targets.

Identify every independent parser or serializer touched by the change. Do not allow two implementations to define different frontmatter boundaries or value semantics. Move shared deterministic behavior into a testable shared layer when that is the smallest safe correction.

## Resolve role before schema

Keep these layers distinct:

1. The registered `VaultRole` identifies the research space.
2. The versioned schema profile interprets metadata within that role.
3. Exact Markdown remains authoritative beneath both.

For a registered source, topic, dissertation-control, or draft vault, do not replace its role with a folder-name guess. Use explicit schema metadata and configurable legacy folders only as narrower profile evidence where the live resolver permits it, with generic Markdown as the fallback.

- Source Corpus uses the paper-analysis profile and may update only the canonical `updated` key after a successful save. If a note already contains only the legacy `analysis_updated_at` timestamp, target that existing field without injecting `updated`; migrate it only through a deliberate property edit.
- Topic Knowledge uses the topic-Markdown profile. Missing frontmatter is valid, and ordinary reading, body editing, full-source autosave, or dated-reference insertion must not create YAML.
- Dissertation Control resolves explicit `dissertation-control-v4` metadata to v4 and otherwise retains the v3 contract. Ordinary saves never update the substantive `last_reviewed` field.
- Nested paper metadata such as `audit` may be exposed through a dotted, read-only scalar projection. Do not flatten that projection back into writable YAML.

This skill owns exact bytes, parsing boundaries, typed projections, and lossless mutation. Workflow meanings, readiness, permissions, and philosophical status remain owned by their workflow implementation and documentation; displaying a field does not authorize changing its meaning.

## Choose the mutation contract

Classify the operation before coding:

- **Read or render:** do not mutate source.
- **Body edit:** replace only the owned body range and preserve all frontmatter bytes except the one unambiguous configured successful-save timestamp field, when that policy is enabled.
- **Property edit:** patch only the uniquely identified top-level field and the configured successful-save timestamp.
- **Full-source edit:** accept the active editor's complete buffer, validate its frontmatter, then route that unchanged buffer through the transactional repository. The reachable CodeMirror Source and Live Preview path currently submits this contract.
- **No-op:** produce byte-for-byte identical output and no synthetic timestamp.

Classify the operation from the actual submitted payload and mutation API, not from what the user appeared to edit. An editor that submits its complete `.source` buffer uses the full-source contract even when the user changed only body text. Use the body-edit contract only for an owned body-range mutation. Pair `scholium-markdown-editor-integration` when changing which payload the reachable editor or autosave path submits.

Reject a targeted property edit when the requested field cannot be located unambiguously. Do not repair, reindent, sort, or reserialize unrelated YAML as a side effect.

## Preserve format and meaning

- Keep the original UTF-8 bytes authoritative for fingerprints, snapshots, and unchanged regions.
- Preserve BOM, LF or CRLF convention, final-newline state, comments, blank lines, key order, quoting, flow or block style, scalar chomping, anchors, aliases, tags, and unknown nested values outside the changed field and the configured successful-save timestamp field.
- Recognize frontmatter only at the document start after an optional UTF-8 BOM, using exact delimiter-line rules. A thematic break later in the body is not frontmatter.
- Use Yams to validate the complete frontmatter mapping after a patch. Do not use decode-then-encode as a lossless editing strategy.
- Treat duplicate keys, malformed aliases, a non-mapping root, unterminated frontmatter, unsupported key syntax, and ambiguous scalar construction as explicit diagnostics. Keep malformed notes readable but fail closed for metadata edits.
- Keep semantic property types distinct: text, list, number, checkbox, date, date-time, tags, null, and unknown nested structures. Displaying a value does not authorize rewriting its spelling.
- Do not inject filesystem dates or other derived metadata into a writable frontmatter model unless the user explicitly saves that property.
- Do not treat absent YAML in Topic Knowledge as malformed or incomplete, and do not synthesize delimiters merely to attach an automatic timestamp.

Read [references/fidelity-fixture-matrix.md](references/fidelity-fixture-matrix.md) before changing parsing, patching, serialization, or property projection.

## Test with two oracles

For each fixture, assert both:

1. **Byte oracle:** unchanged byte ranges remain exactly equal, including BOM, line endings, and final newline.
2. **Semantic oracle:** the complete proposed frontmatter parses as one mapping with the intended changed value.

Add parameterized golden tests for no-op, body, property, full-source, malformed, and unsupported edits. Compare core and app projections on the same fixtures. If app-only logic cannot be imported by a test target, extract the pure logic or add a testable target instead of relying on manual UI checks.

Run the narrow tests, then `./Tools/Scripts/verify.sh`. Report unsupported YAML constructs and any deliberate normalization explicitly.

## Standards and lineage

Use the [YAML 1.2.2 specification](https://yaml.org/spec/1.2.2/), [CommonMark](https://spec.commonmark.org/), [Obsidian properties](https://obsidian.md/help/properties), and [Obsidian-flavored Markdown](https://obsidian.md/help/Editing%2Band%2Bformatting/Obsidian%2BFlavored%2BMarkdown) as compatibility references. The fixture organization selectively adapts ideas from the MIT-licensed [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) while keeping Scholium's exact-byte contract stricter than a note-authoring skill.
