# Search, link, and index fixture matrix

The live specification owns retrieval semantics; architecture and construction
identify their current implementation. This matrix supplies candidate cases,
not product authority or a mandatory suite. Select those that distinguish the
suspected stage. A backend may not introduce an accidental semantic difference.

## Search semantics

| Area | Fixtures | Assertions |
|---|---|---|
| Case | upper/lower/mixed scripts | Indexed and cold paths conform to the active contract |
| Unicode | NFC/NFD, accents, emoji, supplementary scalars | Policy is explicit; snippets do not split invalid ranges |
| CJK | single characters, bigrams, mixed Latin/CJK | Query expansion and AND semantics are deterministic |
| Tokens | punctuation, hyphens, underscores, apostrophes, one-character terms | Inclusion and prefix behavior match the documented contract |
| Fields | every field declared by the current indexed projection | Inclusion and weights conform to the current contract |
| Queries | empty, whitespace, repeated terms, multi-term, prefixes | Stable result set, score, and limit behavior |
| Filters | every filter and scope declared by the current contract | Cold and indexed paths conform to the active filter contract |
| Ranking | equal scores and duplicate display names | Stable tie-break uses a unique deterministic key |
| Snippets | match near start/end, long graphemes, CJK, no direct substring | Valid range, correct field, no private logging |
| Adapter parity | same fixture, query, and supported scope in the App and Scholium MCP | Both conform to the active contract; any deliberate difference is versioned and tested |
| Per-vault generation | two vault UUIDs, identical relative paths, changed fingerprints | Databases and generations remain isolated by stable vault identity |
| Federation | equal scores across vaults, per-vault limits, unavailable index | Stable global order, provenance, and no partial-generation publication |
| Eligibility | researcher, ordinary agent, explicit control inclusion, revoked access | Actor, role, privacy, explicit scope, and persisted access are checked before results merge |
| Saved searches | every currently supported scope plus one removed or invalid scope | Persist definitions outside vaults and re-evaluate against current access and generations |

## Link syntax and resolution

| Area | Fixtures | Assertions |
|---|---|---|
| Wikilinks | `[[Note]]`, `.md`, path, alias | Resolve exact path first |
| Fragments | headings, nested headings, `#^block`, same-note fragments | Preserve locator separately from file target |
| Embeds | note, image, PDF page, width alias | Classify without inventing a note relation |
| Markdown links | relative path, percent encoding, fragment | Follow the current declared link contract |
| Literal regions | escaped link, inline code, variable-length code span, fenced code, comment | Do not emit a relationship |
| Authored annotations | adjacent annotated Wikilinks, multiline Markdown, aliases, fragments, and escaped delimiters | Preserve each source occurrence, annotation, local context, and exact spans |
| Malformed annotations | unclosed, nested, or empty annotation | Diagnose without losing the ordinary link or rewriting source bytes |
| Removed relation syntax | one unsupported former marker | Preserve source bytes without restoring a typed-relation decoder or authority |
| Ambiguity | duplicate basenames, case-only names, aliases | Return sorted candidates; never pick iteration order |
| Broken | missing path, deleted target, invalid characters | Keep a visible source-located diagnostic |
| Direction | repeated occurrences and links authored in both directions | Preserve each directed source occurrence; Incoming and Outgoing views refer to the same occurrence without combining it or inferring a predicate |
| Transitive | output -> topic -> paper | Record a neutral path, not inferred support or citation |
| Shared semantics | every semantic construct and literal exclusion declared by the current projection | Search and graph consume the same spans and exclusions from the live owning projection |

## Mutation sequence oracle

For a generation or invalidation change, choose the relevant subsequence below
and compare the live derived state with a clean rebuild after each selected
step. Keep one independent expected result so shared parser or eligibility bugs
cannot pass merely because both paths agree:

1. Open the base fixture.
2. Add a note containing Unicode metadata and links.
3. Edit title, body terms, one link annotation, and its target.
4. Rename a target, including a case-only variant.
5. Delete and recreate the path with different bytes.
6. Introduce malformed frontmatter while preserving readable body text.
7. Cancel one rebuild and complete the next generation.
8. Corrupt or remove persisted derived files and rebuild.
9. Revoke one vault, rerun a saved workspace search, and verify no stale result survives.
10. Run the same permitted query and supported scope through the App and Scholium MCP adapters and compare ordered provenance-bearing hits.

Compare note inventory, tokens, ranked results, per-vault generations, eligibility, saved-search behavior, authored link occurrences and annotations, ambiguity diagnostics, source locators, and generated index contents. Connectivity never establishes a scholarly relationship class or philosophical support.
