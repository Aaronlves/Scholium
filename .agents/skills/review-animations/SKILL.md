---
name: review-animations
description: Review a named diff, patch, or bounded implementation for animation and motion regressions using the product's platform-specific authorities and runtime evidence. Use for focused motion code review. Do not implement fixes, audit an entire codebase, impose web rules on native code, or treat attributed craft heuristics as platform requirements.
---

# Review Animations

Review only the motion behavior in the requested diff or bounded surface.
Approval is evidence-based; flagging is not the default outcome.

## Select the authority profile

- **Scholium native:** Read the affected Product Guide workflow and the complete
  Design Handbook. Use `apple-hig` for Apple guidance,
  `scholium-apple-design` for Scholium interpretation, and the selected SDK and
  compiler for API claims. Read
  `../scholium-apple-design/references/fluid-interaction.md`. Do not apply web
  timing, CSS, or browser-performance rules to SwiftUI or AppKit.
- **Web:** Read `../emil-design-eng/references/web-motion-craft.md`. Use it as an
  attributed heuristic reference after checking product tokens and runtime
  evidence.
- **Other platforms:** Load the matching platform authority before judging the
  implementation.

If two authorities conflict, report the conflict and apply the documented
precedence. Do not synthesize a new rule.

## Review procedure

1. Read the complete diff and the surrounding implementation.
2. Identify the user task, input paths, frequency, and reachable states.
3. Inspect entry, exit, reversal, cancellation, repeated activation, failure,
   recovery, and reduced-motion behavior where applicable.
4. Confirm each candidate against the selected authority and actual framework.
5. Require measurement for performance claims and runtime or visual evidence
   for feel claims that code alone cannot establish.
6. Do not report a pattern match, preference, or missed enhancement as a defect.

Evaluate purpose, continuity, responsiveness, interruptibility, accessibility,
modality parity, product cohesion, and measured rendering behavior. Input
modality alone does not determine whether a shared state transition should
animate.

## Findings

Lead with actionable findings ordered by consequence. For each finding include:

- severity and confidence;
- file and line;
- violated product, platform, or implementation requirement;
- evidence and reachable consequence;
- smallest safe adjustment; and
- focused verification.

Keep optional polish suggestions separate from defects. State “No confirmed
motion findings” when appropriate and list any unverified runtime checks.

Give an explicit approve/block verdict only when the user asks for one or the
review is a release gate. Block only on a confirmed consequential regression,
not on a preferred easing, duration, or visual style.
