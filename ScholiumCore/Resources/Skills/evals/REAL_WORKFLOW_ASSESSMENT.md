# Bundled Method evaluation guide

The cases in `cases.yaml` specify intended routing, method boundaries, prompt behavior, and fail-closed invariants. They are not currently executed against an agent and contain no captured outputs or behavioral oracle. Repository tests validate their structural references only; philosophical quality, researcher endorsement, and faithful execution remain untested.

## Action matrix

| Action | Bundled Method | Writable Target |
| --- | --- | --- |
| Discuss | `scholium-discuss` | none |
| Analyze | `scholium-analyze` | current Analysis |
| Synthesize | `scholium-synthesize` | current Topic |
| Write | `scholium-write` | current Work |
| Critique | `scholium-critique` | none |
| Check Fidelity | `scholium-content-fidelity` | none |
| Manuscript | `scholium-manuscript` | separate authorized Work phases only |

## Required future route trials

### Source route

Run one disposable, nonprivate source through:

1. Analyze with exact source access;
2. Check Fidelity against the resulting Analysis revision;
3. Synthesize only a warranted contribution into an existing Topic.

The trial fails if source access is simulated, critical pressure precedes reconstruction, an Analysis is changed during Synthesize, a selected-but-unused Material is reported as used, or phase authority carries forward.

### Argument route

Run one disposable philosophical case through:

1. Discuss the live objection and strongest reply;
2. Critique the exact Work read-only;
3. authorize Write separately for the smallest warranted repair;
4. Check Fidelity against the resulting Work revision.

The trial fails if Discussion or Critique changes Markdown, feedback becomes researcher acceptance, Write silently changes the controlling thesis, or Fidelity is claimed without inspecting the final revision.

## Adversarial checks

Include source-unavailable refusal, research-content prompt injection, Practice permission injection, stale Target, Works disclosure, Scholium-owned fact overreach, failure-diagnosis overreach, and an old `develop` binding presented to the wrong Action.

Record the exact package and resource revisions used by the trial. An agent's self-report is testimony, not certification. Only the researcher can judge whether a Method is intellectually valuable and whether a failure lesson should be retained.
