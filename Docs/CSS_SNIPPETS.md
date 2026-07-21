# Scholium CSS Snippet Contract

Appearance provides typed, named document configurations. Its Advanced CSS section can additionally import CSS into a managed Application Support copy. Scholium never loads a snippet directly from a research vault. Snippets style document content in Read and Live Preview only; Source mode and the application interface are fixed.

## Supported surface

Prefer these document selectors:

- `.scholium-document`, `main`, `p`, `a`, `strong`, `em`, `mark`
- `h1` through `h6`, `ul`, `ol`, `li`, `blockquote`
- `table`, `thead`, `tbody`, `tr`, `th`, `td`
- `pre`, `code`, `hr`

Use ordinary visual properties such as color, background color, font family, font size, font style, font weight, line height, letter spacing, text decoration, borders, border radius, padding, and margins. Read and Live Preview map these selectors to their corresponding document projections; exact visual parity is not promised where the editor must preserve editable geometry.

## Protected research components

Do not target Scholium callouts, footnotes, review annotations, provenance warnings, diagnostics, conflict controls, or application chrome. Scholium protects these surfaces because their appearance communicates provenance, uncertainty, review state, or risk.

The sanitizer rejects:

- `@import`, `!important`, scripts, executable or escaped HTML;
- network, `file:`, or other external URLs;
- selectors that escape the document root or target protected components;
- declarations that hide, remove, reposition, or cover protected research information.

## App-owned Callout styles

Semantic Callout presentation, including the role-specific motifs and disclosure chevron, is maintained separately in `Scholium/Resources/Editor/callouts.css`. The app injects this resource into both Read and Live Preview, while `editor.css` and `SafeMarkdownReadWebView.swift` retain only their non-Callout presentation code and resource-loading hooks. Appearance may map typed spacing, type, and composition parameters onto that protected structure; Advanced CSS cannot edit it. Fold state remains source-controlled: `+` starts expanded, `-` starts collapsed, and no marker remains fixed.

## Failure and recovery

Validation errors disable the invalid projection and appear beside the snippet. A rendering failure enters persistent CSS Safe Mode, disables enabled snippets, and records the reason under Application Support. Use **Disable All Snippets** to return to the fixed Scholium document presentation, then re-enable snippets one at a time.

Import, duplicate, rename, reorder, edit the managed copy, reload, remove, and reveal actions operate only on managed copies. Original imported files are never modified.
