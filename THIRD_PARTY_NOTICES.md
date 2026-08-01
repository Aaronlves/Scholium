# Third-Party Notices

This file records the dependencies used to build Scholium. Exact JavaScript versions are authoritative in `WebEditor/package-lock.json`; exact Swift versions are authoritative in `Package.resolved`.

## Runtime libraries

- CodeMirror 6 packages (`@codemirror/autocomplete`, `commands`, `lang-markdown`, `language`, `search`, `state`, and `view`) and their CodeMirror/Lezer runtime dependencies: MIT License.
- KaTeX 0.18.1 and its bundled KaTeX fonts: MIT License.
- Mermaid 11.16.0 and the runtime packages included in its offline browser
  bundle: permissive licenses reproduced package-by-package in
  `Tools/Packaging/Licenses/Mermaid-and-transitive-NOTICES.txt`.
- Yams 6.2.x: MIT License.
- Swift Markdown 0.8.0: Apache License 2.0, including its notice and bundled
  Swift CMark attribution.
- Swift CMark 0.8.0 and its incorporated sources: BSD-2-Clause and the
  additional permissive notices reproduced in its `COPYING` file.

## Build tools

- esbuild 0.28.1 and its selected platform binary: MIT License.
- TypeScript 7.0.2 and its selected platform package: Apache License 2.0.

## Agent skill sources

- Twostraws SwiftUI Agent Skill, Swift Concurrency Agent Skill, and Swift Testing Agent Skill: MIT License. Scholium uses selected review patterns as secondary material, adapted to its macOS architecture, source-fidelity boundary, and current toolchain; the upstream packages are not vendored wholesale.
- Emil Kowalski's published design-engineering material: Scholium retains a short, explicitly attributed craft lens and web-only heuristic reference. It does not vendor course material or treat those heuristics as Apple or Scholium authority.

## Bundled fonts

- Alegreya: SIL Open Font License 1.1. See `Scholium/Resources/Fonts/OFL-Alegreya.txt`.
- Victor Mono: SIL Open Font License 1.1. See `Scholium/Resources/Fonts/OFL-VictorMono.txt`.

Transitive JavaScript packages and their exact versions are retained in the
lockfile. The beta packaging script embeds the complete runtime notices from
`Tools/Packaging/Licenses/` together with Scholium's GPL and this file. Build
tools are not included in the distributed app. Any dependency update must
refresh the checked-in notices before another binary is released.
