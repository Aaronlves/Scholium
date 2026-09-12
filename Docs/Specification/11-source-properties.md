# Specification: Source Properties

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Appendix A.

## Appendix A. Authored source properties

YAML frontmatter is the sole authority for user-authored structured properties.
All three Note roles permit user-defined keys and shapes. Scholium supplies no
managed field catalog, mandatory bibliography, field lifecycle, role-based
property restrictions, or separate Metadata record and editing surface.

### Shared authored YAML

The researcher or an authorized Agent edits exact Markdown. Comments, unknown
keys, ordering, quoting, multiline scalars, BOM and newline style remain source.
Parsing and indexing are read-only projections. Malformed or ambiguous YAML
never authorizes reconstructed source or guessed values.

`summary` and `keywords` can improve discovery; neither is required. Filename
owns Note identity. Authored `title`, `aliases`, `authors`/`author`, and
`publication_date` may supply search/navigation text without becoming managed
bibliographic truth. YAML cannot assign stable Note identity, Settlement,
permissions, or research acceptance.

Property Search uses the existing `property:` grammar. It discovers literal
user keys, supports presence and normalized scalar/direct-list equality, and
returns proved source ranges. Quoted keys may contain spaces or Unicode.
Nested mappings remain authored data; the first slice does not infer creator
names, flatten nested structures, or expand YAML aliases. §13 owns retrieval
semantics and limits. There is no YAML-specific query namespace.

Creating a Note accepts complete authored Markdown, with optional YAML, and
preserves its bytes. GUI New Note starts empty. No scaffold is injected.

The preproduction cutover removes managed Metadata, field Settings, and their
mutation APIs. Unsupported old control files remain byte-unchanged and cannot
authorize values, relationships, or writes; there is no migration or adapter.
