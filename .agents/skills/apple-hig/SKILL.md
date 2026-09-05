---
name: apple-hig
description: >
  Route Apple-platform interface design and review to the current official
  Human Interface Guidelines and selected SDK documentation. Use for iOS,
  iPadOS, macOS, tvOS, visionOS, or watchOS layout, navigation, controls,
  materials, typography, color, symbols, motion, accessibility, privacy, and
  interaction conventions. The local distilled corpus is a dated locator and
  offline fallback, not an independent source of current Apple policy.
---

# Apple HIG

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Apple guidance owns platform conventions; Scholium documents own product and
research meaning and visual identity.

## Resolve the applicable authority

Use the current official [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
for design, Apple's Design Resources or official sessions for released assets
and platform direction, and the selected Xcode documentation, SDK, and compiler
for API signatures, availability, and buildability. Do not infer an API contract
from a design page.

Use `routing-index.md` to locate only the relevant `distilled/` topics. Include
platform or foundation material when it affects the question; do not load all
tiers or follow every related link. For current claims, verify the matching
official topic itself, including exact values and platform differences.

The local corpus is a dated locator and offline fallback. If live sources are
unavailable, state the snapshot date from `sources/`, mark possible staleness,
and limit the claim. A stable URL or page changelog does not prove completeness.
Keep source guidance, inference, and product decisions separate; cite the
controlling source and surface conflicts.

## Corpus maintenance

For corpus updates, read [process.md](process.md). Capture a dated official
snapshot, review changed topics, update source-backed distillations, regenerate
`routing-index.md`, and run the corpus and toolkit validators. The corpus and
its provenance serve offline source work; entry simplification does not justify
removing them.
