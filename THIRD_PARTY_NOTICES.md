# Third-Party Notices

This file records the dependencies used to build Scholium. Exact JavaScript versions are authoritative in `WebEditor/package-lock.json`; exact Swift versions are authoritative in `Package.resolved`.

## Runtime libraries

- CodeMirror 6 packages (`@codemirror/autocomplete`, `commands`, `lang-markdown`, `lang-yaml`, `language`, `search`, `state`, and `view`) and their CodeMirror/Lezer runtime dependencies: MIT License.
- KaTeX 0.18.1 and its bundled KaTeX fonts: MIT License.
- Remend 1.4.0 (Vercel, Inc.), used only for display-time completion of streaming
  Markdown: Apache License 2.0. Its license and upstream notice are retained in
  `Tools/Packaging/Licenses/Remend-Apache-2.0.txt` and `Remend-NOTICE.txt`.
- Pele 1.6.0, used to render Mermaid syntax locally: MIT License, with
  incorporated icon attribution retained in
  `Tools/Packaging/Licenses/Pele-NOTICES.txt`.
- Yams 6.2.2: MIT License.
- ThinkingOrbs 1.1.0 (Haplo LLC; original designs and engine by Jakub Antalik): MIT License.
- Swift Markdown 0.8.0: Apache License 2.0, including its notice and bundled
  Swift CMark attribution.
- Swift CMark 0.8.0 and its incorporated sources: BSD-2-Clause and the
  additional permissive notices reproduced in its `COPYING` file.
- Swift Subprocess 1.0.0: Apache License 2.0.
- Swift System (transitive): Apache License 2.0 with Swift Runtime Library Exception.
- Sparkle 2.10.0: MIT License, including incorporated BSD and other permissive
  notices. Packaging retains its complete upstream `LICENSE` with the framework's
  installer helpers and resources.

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
