# Interaction verification

Turn the named user-visible claim into the smallest trustworthy automated
journey or human handoff. Follow repository fixture, isolation, build, and
cleanup rules; never open or capture a private research vault.

## Automated verification

Inspect current reachability, existing assertions, QA identity, and the affected
workflow. Before adding or broadening a journey, use the
[coverage derivation guide](ui-test-matrix.md). Reuse one representative journey
per distinct boundary; add dimensions only for independent failure modes.

Assert user-visible outcomes and affected focus, source, cancellation, conflict,
accessibility, and recovery behavior. Prefer semantic controls, menus, shortcuts,
roles, and stable accessibility identifiers over coordinates. Wait for observable
state with bounded failure, not fixed sleeps. Keep one QA process and clean up
test-owned state under repository rules.

Exploratory Computer Use supplies observations rather than deterministic proof
or human acceptance. Direct unit/CLI checks cannot establish app interaction.
A release artifact is required only for release-specific claims such as signing,
entitlements, persisted access, packaging, or installation.

## Human acceptance

When perception, speech, IME candidate selection, or assistive-technology judgment
is irreducibly human, load the [human-acceptance protocol](human-acceptance.md).
Automate safe setup and observable postconditions, then ask for the smallest
remaining human action and judgment. Do not label that gate passed from synthetic
input or an accessibility tree.

Report the build and fixture, exact claim and assertions, useful artifacts,
human-only conditions, and limits. Follow `AGENTS.md` for scope and cadence.
