# Implementation Status: Open Work

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Work and acceptance still open.

## Native design, accessibility and human acceptance

- Complete the retained Core human baseline: one genuine VoiceOver journey, one
  physical Full Keyboard Access journey, one installed Simplified Chinese IME
  exact-source journey, and one visual-adaptation set at supported window sizes.
  Include only the distinct failure modes required by §20: Agents & Chat
  command copying, Agent Changes comparison/Undo, Library navigation, Inspector
  Links/Related Material, Document mode transitions, system Trash, conflict and
  recovery.
- Complete the changed editor syntax-continuity journey for rapid reversal,
  full-line prefix borrowing, minimum width, system adaptations, IME and
  conflict/recovery. Automated editor checks and exploratory QA do not close
  this human boundary.
- Exercise the intermittent Sidebar symptom under physical mixed
  pointer/keyboard use and window reactivation. Re-run the Agent Changes
  comparison/Undo journey with the disposable fixture, and accept Settlement
  milestone feedback, ordinary Edit entry and native-row emphasis only through
  the applicable human checks.
- Complete visual and assistive-technology acceptance for note reorganization,
  the Chat composer and approvals, file navigation, Related Material, native
  sheets, previews and the affected motion/adaptation variants. Offscreen
  renders and Computer Use accessibility snapshots remain development evidence.

## Agent collaboration and integrations

- Complete the packaged external-host journey in §21.5, including the installed
  App and bundled helper, both user-scope setup commands, production bridge,
  clean-account smoke and exact artifact provenance. Local helper tests do not
  establish packaged behavior.
- Complete real-provider/browser authentication and tool setup, declared
  dependency availability, search-result provenance, model/input support,
  source-linked Note selection, editor-snapshot capture, file picker/paste/drop,
  Quick Look and image-input acceptance.
- Complete Zotero page/annotation navigation and exact original-file opening,
  including the separate local API, first-party read-only MCP and material
  report boundaries. No Zotero write scope is implied.
- Complete live acceptance for branching, concurrent execution, background
  notifications, model/reasoning/web-search choices, context and quota
  presentation, research questions, Note-update comparisons, runtime command /
  terminal / network / file approvals, and supported scheduled execution.
- Complete delegated-Agent roster/detail observation and exact-turn
  interruption with the real runtime. Child messaging and child approval
  routing remain subject to the runtime's reported direct-input capability; do
  not bypass that capability through another Agent mode. Unsupported MCP
  elicitation, imported runtime-history and other unsupported server requests
  remain explicit unavailable states.
- Complete the remaining Chat recovery cases: prolonged offline operation,
  in-flight source-operation interruption, persisted-draft recovery, and
  source/material evidence retention after restart. The bounded signed-in loop
  already recorded in Verification does not establish these broader paths.

## Note reorganization and source recovery

- Complete the background-tab insertion journey and the visual,
  assistive-technology and adaptation acceptance for same-vault extraction,
  move, copy and merge. Retain the existing refusals for ambiguous YAML,
  unresolved destinations, unsupported reference definitions and unsafe linked
  resources.
- Complete live filesystem/sync, File Provider, Finder restoration and human
  Recovery acceptance, including displaced external-source candidates and
  post-Trash cleanup. Deterministic late-writer and process-interruption proof
  remains bounded evidence only.
- Continue Zotero and other system-integration acceptance where the
  specification requires an external application or packaged environment.

## Gate and release boundary

- The complete repository gate and the exact-tag Beta package for
  `v0.2.2-beta` passed on 2026-09-17; the dated evidence and artifact
  provenance are recorded in [Verification](04-verification.md). Repeat this
  gate for each subsequent release candidate rather than treating this result
  as reusable proof.
- Run the affected packaged performance series when the §21.3 change-trigger
  rule requires it; do not promote focused measurements to G7.
- The `v0.2.2-beta` artifact, checksum, ad-hoc signature, source/license,
  package-content/private-path, and clean-account checks passed. Developer ID
  signing and notarization remain a future channel, outside the current
  ad-hoc source-first Beta profile.

## Current boundary

This chapter lists remaining implementation, environment and human-acceptance
work only. Reachable behavior belongs to [Reachable Capabilities](01-capabilities.md)
and [Reachable Interface](02-interface.md); dated proof belongs to
[Verification Evidence](04-verification.md). The Specification set owns target
behavior and does not acquire new requirements from this list.
