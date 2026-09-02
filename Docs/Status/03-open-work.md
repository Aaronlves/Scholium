# Implementation Status: Open Work

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Work and acceptance still open.

## External-host and release acceptance

- Run a clean-account artifact smoke with the signed App already running:
  register `scholium mcp serve` independently in Codex and Claude Code, confirm
  fixed seven-tool discovery, exercise search/read/links and one create/update/
  trash sequence, verify stale-fingerprint rejection, and inspect the resulting
  Agent Changes and eligible Update Undo.
- Verify running-App absence, multiple-open-Triptych selection, reconnect, App
  relaunch, sandbox boundary, and packaged absolute CLI-path behavior on the
  actual release artifacts. These are external-host and packaging claims, not
  established by local unit tests.
- Complete Developer ID signing, notarization, distribution provenance,
  clean-machine installation, and the documented release smoke before claiming
  a distributable Core release.

## Human interface and accessibility acceptance

- Re-run the affected Agent Changes exact-comparison/Undo UI journey after the
  macOS XCTest sheet-presentation failure is isolated. On 2026-09-03 the focused
  runner entered the journey and completed Settlement plus the MCP mutation,
  but synthetic toolbar activation left the main window disabled for an
  attached sheet that XCTest neither rendered nor exposed; the journey failed
  before comparison and Undo assertions. The same isolated build and fixture
  rendered the comparison and exposed its accessibility rows under exploratory
  Computer Use, which is not a deterministic pass or human acceptance.
- Establish the retained Core human baseline: one genuine VoiceOver journey,
  one physical Full Keyboard Access journey, one installed Simplified Chinese
  IME exact-source journey, and one visual-adaptation set at supported window
  sizes.
- Include Agent Integration command copying, Agent Changes comparison/Undo,
  Library navigation, Document mode transitions, Inspector Overview/Connect,
  system Trash, conflict, and recovery where they exercise distinct human
  failure modes.
- Retain the current distinction between deterministic build/test evidence and
  human acceptance. Automated accessibility structure checks do not constitute
  VoiceOver, keyboard, IME, or visual acceptance.

## Remaining product work

- Research Records and Handoff are future §22 work. Their data model,
  authority, migration, interface, search participation, and acceptance must be
  specified and implemented as new work; deleted legacy implementations do not
  count as progress toward that target.
- Continue performance, File Provider/sync, Finder restoration, and Zotero
  system-integration acceptance where the current specification requires
  artifact or environment evidence.
