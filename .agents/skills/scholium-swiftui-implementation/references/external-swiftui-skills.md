# External SwiftUI skill map

Last reviewed: 2026-07-12. These are secondary discovery and comparison sources. Apple documentation and the selected Xcode's exported skills remain implementation authority.

## Use policy

- Prefer `xcrun agent skills export` over installing a public collection.
- Check the upstream repository, commit, release, license, platform bias, and cited Apple sources before using a community idea.
- Do not infer quality from marketplace installs or badges.
- Do not copy large API catalogs, tutorial text, transcripts, or Apple-exported references into Scholium's plugin.
- Use community material to discover a question or evaluation pattern, then verify the answer in current Apple documentation and the live SDK.

## Reviewed sources

| Source | License and freshness at review | Useful role | Limitation |
| --- | --- | --- | --- |
| [Apple Xcode agent skills](https://developer.apple.com/documentation/xcode/extending-and-customizing-agents) | Apple-authored; exported from the selected Xcode; no standalone redistribution license | Primary best-practice and SDK-change router | Must be re-exported after Xcode changes and gated by the actual compiler/SDK |
| [AvdLee SwiftUI Agent Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill/tree/main/swiftui-expert-skill) | MIT; v4.0.0, 2026-06-16 at review | Broad topic routing, maintenance ideas, Instruments discovery | Large references and iOS-biased Liquid Glass material |
| [twostraws SwiftUI Agent Skill](https://github.com/twostraws/SwiftUI-Agent-Skill/tree/main/swiftui-pro) | MIT; v1.1.0, 2026-04-20 at review | Compact genuine-problem review checklist | Primarily iOS; little Mac or Liquid Glass depth |
| [Dimillian SwiftUI skills](https://github.com/Dimillian/Skills) | MIT; Liquid Glass skill last materially changed 2025-12-30 at review | Focused decision-tree and performance-audit structure | iOS-oriented and some repository-local paths |
| [dpearson2699 Swift skills](https://github.com/dpearson2699/swift-ios-skills) | PolyForm Perimeter 1.0; v3.6.1 at review | Scenario/evaluation ideas | Restricted license, duplicated content, explicitly iOS-first; do not derive or copy |
| [rshankras Apple skills](https://github.com/rshankras/claude-code-apple-skills) | MIT; repository active 2026-07-11 at review | Freshness-tripwire idea | Broken references and recommendations that overuse glass cards |

The [Raven Xcode skill mirror](https://github.com/raven/xcode-agent-skills) is useful for change tracking only. It says the mirrored content is Apple copyright and reproduced for study; read the selected Xcode export rather than the mirror when applying guidance.

## Patterns independently retained

- Keep the entry skill short and route to only the relevant reference.
- Trigger known SDK migration guidance from exact errors rather than vague modernity.
- During review, report genuine reachable problems with file, line, consequence, and focused verification.
- Evaluate Liquid Glass with contrasting scenarios: functional control versus static status, navigation layer versus content layer, standard component versus custom effect, and default appearance versus accessibility adaptations.
- Recheck any statement labelled latest after the Xcode build changes.

These are general workflow patterns, not copied skill prose. If future work materially adapts an external implementation or text, record its license and attribution in the plugin's third-party notices before distribution.
