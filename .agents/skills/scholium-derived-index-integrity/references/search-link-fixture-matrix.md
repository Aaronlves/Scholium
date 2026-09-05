# Search, link, and index fixture matrix

The parent derived-index skill owns the active versioned user-visible contract. This matrix supplies executable cases. Each path must conform to that contract, including any explicitly versioned and separately tested exception; a backend may not introduce an accidental difference.

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
| CLI parity | same fixture and query in GUI and CLI | Both conform to the active contract; any deliberate difference is versioned and tested |
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
| Declared relation syntax | every marker, alias, and fragment form in the current specification | Normalize direction/symmetry, preserve exact marker span, and derive reverse views without writes |
| Removed or unknown relation syntax | one removed marker and one unknown form | Do not derive a relation or retain a decoder; keep source bytes unchanged and emit the current diagnostic |
| Ambiguity | duplicate basenames, case-only names, aliases | Return sorted candidates; never pick iteration order |
| Broken | missing path, deleted target, invalid characters | Keep a visible source-located diagnostic |
| Direction | every currently declared role combination, inverse-authored duplicate, and reciprocal relation | Match the current normalization contract and deterministic IDs |
| Transitive | output -> topic -> paper | Record a neutral path, not inferred support or citation |
| Shared semantics | every semantic construct and literal exclusion declared by the current projection | Search and graph consume the same spans and exclusions from the live owning projection |

## Mutation sequence oracle

After each step, compare the live derived state with a clean rebuild:

1. Open the base fixture.
2. Add a note containing Unicode metadata and links.
3. Edit title, body terms, one currently declared relation direction, and target.
4. Rename a target, including a case-only variant.
5. Delete and recreate the path with different bytes.
6. Introduce malformed frontmatter while preserving readable body text.
7. Cancel one rebuild and complete the next generation.
8. Corrupt or remove persisted derived files and rebuild.
9. Revoke one vault, rerun a saved workspace search, and verify no stale result survives.
10. Run the same permitted query through GUI and CLI adapters and compare ordered provenance-bearing hits.

Compare note inventory, tokens, ranked results, per-vault generations, eligibility, saved-search behavior, forward/backlinks, ambiguity diagnostics, relationship categories, source locators, and generated index contents.
