# Search, link, and index fixture matrix

`scholium-derived-index-integrity` owns the active versioned user-visible contract. This matrix supplies executable cases. Each path must conform to that contract, including any explicitly versioned and separately tested exception; a backend may not introduce an accidental difference.

## Search semantics

| Area | Fixtures | Assertions |
|---|---|---|
| Case | upper/lower/mixed scripts | Indexed and cold paths conform to the active contract |
| Unicode | NFC/NFD, accents, emoji, supplementary scalars | Policy is explicit; snippets do not split invalid ranges |
| CJK | single characters, bigrams, mixed Latin/CJK | Query expansion and AND semantics are deterministic |
| Tokens | punctuation, hyphens, underscores, apostrophes, one-character terms | Inclusion and prefix behavior match the documented contract |
| Fields | title, tags, authors, arbitrary scalar/list metadata, body | Inclusion and weights are intentional |
| Queries | empty, whitespace, repeated terms, multi-term, prefixes | Stable result set, score, and limit behavior |
| Filters | KB, tag, review, arbitrary metadata | Cold and indexed paths conform to the active filter contract |
| Ranking | equal scores and duplicate display names | Stable tie-break uses a unique deterministic key |
| Snippets | match near start/end, long graphemes, CJK, no direct substring | Valid range, correct field, no private logging |
| CLI parity | same fixture and query in GUI and CLI | Both conform to the active contract; any deliberate difference is versioned and tested |
| Per-vault generation | two vault UUIDs, identical relative paths, changed fingerprints | Databases and generations remain isolated by stable vault identity |
| Federation | equal scores across vaults, per-vault limits, unavailable index | Stable global order, provenance, and no partial-generation publication |
| Eligibility | researcher, ordinary agent, explicit control inclusion, revoked access | Actor, role, privacy, explicit scope, and persisted access are checked before results merge |
| Saved searches | current-vault, workspace, selected roles, removed role | Persist definitions outside vaults and re-evaluate against current access and generations |

## Link syntax and resolution

| Area | Fixtures | Assertions |
|---|---|---|
| Wikilinks | `[[Note]]`, `.md`, path, alias | Resolve exact path first |
| Fragments | headings, nested headings, `#^block`, same-note fragments | Preserve locator separately from file target |
| Embeds | note, image, PDF page, width alias | Classify without inventing a note relation |
| Markdown links | relative path, percent encoding, fragment | Follow the declared compatibility policy |
| Literal regions | escaped link, inline code, variable-length code span, fenced code, comment | Do not emit a relationship |
| Vector links | `[[B]]`, `+[[B]]`, `-[[B]]`, `?[[B]]`, alias and fragment forms | Normalize direction/symmetry, preserve exact marker span, and derive reverse views without writes |
| Legacy relation | `|:supports`, alias plus type, arrow syntax, unknown suffix | Keep readable and separate from display alias; never recommend or auto-migrate |
| Ambiguity | duplicate basenames, case-only names, aliases | Return sorted candidates; never pick iteration order |
| Broken | missing path, deleted target, invalid characters | Keep a visible source-located diagnostic |
| Direction | source/topic/output combinations, inverse-authored duplicate, reciprocal support | Match Vector-Link normalization and deterministic IDs |
| Transitive | output -> topic -> paper | Record a neutral path, not inferred support or citation |
| Shared semantics | callout, footnote, link, code/comment literal in one note | Search and graph consume the same `MarkdownSemanticDocument` spans and exclusions |

## Mutation sequence oracle

After each step, compare the live derived state with a clean rebuild:

1. Open the base fixture.
2. Add a note containing Unicode metadata and links.
3. Edit title, body terms, vector direction, and target.
4. Rename a target, including a case-only variant.
5. Delete and recreate the path with different bytes.
6. Introduce malformed frontmatter while preserving readable body text.
7. Cancel one rebuild and complete the next generation.
8. Corrupt or remove persisted derived files and rebuild.
9. Revoke one vault, rerun a saved workspace search, and verify no stale result survives.
10. Run the same permitted query through GUI and CLI adapters and compare ordered provenance-bearing hits.

Compare note inventory, tokens, ranked results, per-vault generations, eligibility, saved-search behavior, forward/backlinks, ambiguity diagnostics, relationship categories, source locators, and generated index contents.
