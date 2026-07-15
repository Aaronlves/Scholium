# Source-Analysis Submodes

Choose the narrowest submode that satisfies the current request.

## `analysis-only`

Analyze the source without project-use proposals or file updates.

Use when:

- no project context is supplied;
- the researcher wants understanding only;
- source access is partial and only a provisional analysis is responsible.

Default permission: `read-only`.

## `analysis-plus-handoff-candidates`

Analyze the source and propose bounded future uses without modifying project files.

Label every candidate with its proposed role, basis, verification status, limitation, and required next check. A handoff is not settled knowledge.

Default permission: `candidate-only`.

## `analysis-plus-authorized-updates`

Use only when the current researcher instruction both requests Source Analysis and explicitly authorizes updates to exact named note targets.

This is a request-level Mixed route, not one phase with broad permission:

1. run Source Analysis with `read-only` permission;
2. emit a source bridge packet stating the exact claim, evidential layer, source role, locator, scope, qualification, and what the source does not establish;
3. reset context and permission;
4. run `source-to-note` through `scholium-research-integration` for only the named targets and current fingerprints;
5. run `scholium-content-audit` once on each final substantively changed fingerprint.

If the requested update target is not exact, current, or inside the original task scope, downgrade to `analysis-plus-handoff-candidates` and report the missing authorization. Never carry Source Analysis read access into note-write permission.

## `topic-map`

Use for a genuine overview, survey, introduction, textbook, or reference source whose function is to organize a domain. Map topic architecture, positions, distinctions, omissions, and the source's organizing narrative. Do not treat that narrative as independently verified field history.

## `hybrid`

Use when one source genuinely contains both an overview function and an authored philosophical intervention. Separate the map from the close reconstruction. Do not let the source's overview authority automatically support its original argument.

## Mode changes

If analysis reveals a need for integration, writing, development, review, or synthesis, complete the current source-analysis output and begin the next phase with a fresh task packet. Use `scholium-research-integration` for any live Triptych write. Use a researcher-owned citation skill when a particular citation system or bibliographic convention requires specialist verification. Do not carry write permission into the new mode.

For a long source, a new session unit does not create a new durable Analysis by default. Reuse the existing source-level Analysis and update its minimal Research Unit after the three passes. A separate chapter or section Analysis requires an explicit researcher choice or an independently durable scholarly purpose.
