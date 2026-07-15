# Markdown and YAML fidelity fixture matrix

Use generated or copied test fixtures only. Never exercise mutations against a research vault.

| Area | Required fixture | Required result |
|---|---|---|
| Envelope | UTF-8 BOM with CRLF | Detect frontmatter after the BOM; preserve BOM and CRLF |
| Envelope | LF, CRLF, no final newline, final newline | Preserve the existing form outside an explicitly replaced range |
| Envelope | Plain Markdown beginning with a heading | Treat the complete file as body |
| Envelope | Opening delimiter without a closing delimiter | Keep readable; reject metadata editing |
| Envelope | `---` later in the body or inside a fenced block | Do not treat it as frontmatter |
| YAML root | Empty mapping and mapping with comments | Parse as a mapping; preserve comments on no-op/body edit |
| YAML root | Sequence or scalar root | Diagnose; do not expose it as editable properties |
| Keys | Duplicate, quoted, colon-containing, and Unicode keys | Reject ambiguous targeted edits; never silently pick one |
| Scalars | quoted `true`, `null`, numbers, dates, colons, hashes | Preserve intended string typing and unrelated spelling |
| Scalars | literal/folded blocks with `|`, `|-`, `|+`, `>`, `>-` | Preserve content, indentation, and chomping outside the edit |
| Collections | block/flow sequences and mappings | Preserve style for untouched values |
| Graph | anchors, aliases, explicit tags, merge keys | Validate the complete result; preserve untouched syntax |
| Schema | unknown nested mapping or heterogeneous sequence | Display read-only if unsupported; never flatten or drop it |
| Role/profile | registered Source Corpus note in a non-legacy folder | Resolve the paper-analysis profile from the registered role, not the path; target canonical `updated`, or an existing legacy `analysis_updated_at`, when applicable |
| Role/profile | Topic Knowledge note without frontmatter | Treat the complete file as valid Markdown; body, source, and dated-reference edits remain YAML-free |
| Role/profile | dissertation-control v3 and explicit v4 notes | Keep the profile distinction; ordinary saves do not change `last_reviewed` |
| Projection | nested paper `audit` mapping | Expose dotted scalar values read-only; never serialize the flattened projection |
| Body | callouts, footnotes, math, HTML, comments, embeds, wikilinks | Preserve exact source through read/live/source transitions |
| Unicode | emoji, combining marks, non-Latin scripts, NUL-like controls | Keep UTF-8 bytes and range calculations valid |
| Failure | malformed quote, bracket, indentation, alias, or delimiter | Keep note readable; reject metadata mutation with a useful error |

## Operation assertions

Select the assertion group from the actual submitted mutation payload. A complete editor `.source` buffer uses the full-source assertions even when only body text was visibly changed; the body assertions apply only to an owned body-range mutation.

### No-op

- Output bytes equal input bytes.
- No timestamp or derived property is injected.
- Parsed warnings remain stable.

### Body edit

- Frontmatter prefix, raw YAML, and closing delimiter are byte-identical except for the one unambiguous configured successful-save timestamp field, when that policy is enabled.
- Only the body range and that configured timestamp field may differ; no other synthetic property change is permitted.

### Property edit

- Exactly one unambiguous top-level field range changes, plus the documented timestamp when applicable.
- Unknown keys, comments, blank lines, order, nested values, anchors, and final newline are unchanged.
- Reparse the entire proposed YAML mapping after the patch.

### Full-source edit

- The active editor's complete buffer is the proposal; do not reconstruct it from a parsed model or a Live Preview render tree.
- Reject malformed frontmatter before entering the write phase.
- Bind the save to the document identity and starting fingerprint.
- For a YAML-free topic note, preserve the absence of delimiters unless the researcher explicitly authored frontmatter in the submitted source.

## Differential checks

- Parse every fixture through the core document layer and every active app projection.
- Compare frontmatter presence, body boundary, supported values, and diagnostics.
- When the projections disagree, choose the exact-document contract as authority and fix or remove the divergent parser.
- Add the fixture to the regression suite before changing behavior.
