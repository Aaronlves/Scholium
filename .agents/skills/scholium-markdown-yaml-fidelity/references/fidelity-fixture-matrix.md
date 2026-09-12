# Markdown and YAML fidelity fixture matrix

Use generated or copied test fixtures only. Never exercise mutations against a research vault.
Select rows for the changed conversion or failure mode; the table is not a
mandatory full matrix for a local correction. The live source contract owns
acceptance and rejection rules; these fixtures do not redefine them.

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
| Role/profile | every currently registered role and default profile | Resolve from registered identity and the live schema contract, not from a folder guess |
| Role/profile | unsupported pre-production metadata | Preserve bytes exactly, expose no current role or workflow authority, and do not retain a decoder or write path |
| Role/profile | every role/profile for which missing frontmatter is valid | Keep the complete file valid and YAML-free unless the submitted source explicitly authors frontmatter |
| Projection | every nested or otherwise unsupported property shape | Expose only as permitted by the live projection contract; never flatten a read-only projection into writable YAML |
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

- Frontmatter prefix, raw YAML, and closing delimiter are byte-identical.
- Only the submitted body range may differ; no synthetic property change is permitted.

### Property edit

- Exactly one unambiguous top-level field range changes.
- Unknown keys, comments, blank lines, order, nested values, anchors, and final newline are unchanged.
- Reparse the entire proposed YAML mapping after the patch.

### Full-source edit

- The active editor boundary's complete exact-source snapshot is the candidate; do not substitute normalized editor text, a parsed model, or a render tree.
- Reject malformed frontmatter before entering the write phase.
- Bind the save to the document identity and starting fingerprint.
- For any profile that permits YAML-free source, preserve the absence of
  delimiters unless the submitted source explicitly authored frontmatter.

## Differential checks

- Parse the selected fixture through the affected core layer and consuming projection.
- Compare frontmatter presence, body boundary, supported values, and diagnostics.
- When the projections disagree, choose the exact-document contract as authority and fix or remove the divergent parser.
- Retain the fixture as regression coverage when it detects the reported failure; diagnosis-only work describes the test without adding it.
