# Markdown editor third-party notices

The bundled editor was built with CodeMirror 6 (`state` 6.7.1, `view` 6.43.6,
`language` 6.12.4, `lang-markdown` 6.5.0, `commands` 6.10.4,
`autocomplete` 6.20.3, and `search` 6.7.1) and their Lezer parsing packages.
These packages are distributed under the MIT License. Source and license
information:

- https://github.com/codemirror/dev
- https://github.com/lezer-parser

The generated `editor.bundle.js` contains only these editor dependencies and
Scholium's integration code. Scholium does not copy Tolaria or MarkEdit source.

The shared mathematics runtime, stylesheet, and fonts are built from KaTeX
0.18.1, distributed under the MIT License:

- https://github.com/KaTeX/KaTeX

`math.bundle.js`, `katex.min.css`, and the `KaTeX_*.woff2` files are generated
from the exact package version locked in `WebEditor/package-lock.json`.
