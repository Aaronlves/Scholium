# SwiftUI and hybrid presentation performance hypotheses

Use these questions to narrow a measured issue, never to declare a bottleneck
from source shape alone.

When AppKit hosts, scrolls, or reuses the affected region, first apply
`scholium-interface-design`'s native-container diagnosis. Establish one owner
for geometry, identity and reuse, transient interaction state, and lifecycle
before attributing visible jitter to declarative rendering or adding caches.

- Does a frequently changing value invalidate views that need only a stable
  derived result?
- Is identity stable across filtering, sorting, refresh, and presentation?
- Does rendering perform parsing, filtering, formatting, I/O, graph, database,
  or other repeatable domain work owned elsewhere?
- Does view-local state duplicate derived or authoritative data without an
  explicit invalidation contract?
- Does structural branching change identity, focus, teardown, or accessibility
  unnecessarily?
- Do collections or layout recompute broad inputs for one local change?
- Does the active native or Web bridge repeat document transfer,
  configuration, readiness, reconciliation, or location work?
- Is blocking or CPU work on the UI actor, or has an attempted fix weakened
  isolation with detached tasks, unchecked sendability, or unsynchronized caches?

Prefer removing repeated work, narrowing observation, stabilizing identity, and
moving pure computation to its owner before introducing caches, wrappers, or a
new state system. Re-run the same measurement and correctness oracle after each
bounded change.

These questions adapt MIT-licensed review ideas from
[Dimillian/Skills](https://github.com/Dimillian/Skills/tree/main/swiftui-performance-audit)
and [twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill)
to Scholium's macOS and trust boundaries.
