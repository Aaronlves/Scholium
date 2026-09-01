# Implementation Status: Open Work

[IMPLEMENTATION_STATUS.md](../IMPLEMENTATION_STATUS.md) · Work and acceptance still open.

## Interface and accessibility acceptance

- Establish the first retained complete deterministic Core UI baseline on the
  next Core Beta because current evidence is focused journeys and target
  compilation, not a complete UI gate. Run the current matrix on an isolated QA
  build from the exact source. Later Betas retain repository guards and rerun
  affected UI journeys; a new supported macOS baseline and Core App 1.0 repeat
  the complete matrix. Artifact-specific journeys remain governed by §21.5.
- Establish §20's first retained Core human baseline on the next Core Beta
  because none exists: one genuine VoiceOver journey, one physical Full
  Keyboard Access journey, one installed Simplified Chinese IME exact-source
  journey, and one visual-adaptation set. Later Betas rerun only checks whose
  representative journey, failure-mode owner, framework boundary, or supported
  macOS baseline changed, or when a new independent human failure mode appears;
  Core App 1.0 repeats all four. Every Beta still requires current deterministic
  guards, affected UI journeys, and no unresolved critical or high-severity
  accessibility defect.
- Run Voice Control or Dictation human compatibility only when a named release
  claims that route or a change touches command discoverability or text-service
  integration. Do not keep them as unconditional per-feature release rows.
- Put shell/lifecycle and stress coverage inside the first complete
  deterministic UI baseline, then rerun only when their owners or supported
  macOS behavior changes. Existing journeys cover native Sidebar/Inspector
  visibility, independent/new windows and relaunch, document-tab neighbor
  closure, Note/Folder/root drag-and-drop, Library minimum width, Records window
  routing, one Attention item/notification stack, and Action focus/minimum
  width. The baseline still must close fullscreen, Dock/last-tab system
  behavior, long Connect/Attention populations, Library command shortcuts,
  Records' actual minimum, and Action/Discussion cancellation/recovery. These
  are deterministic UI claims unless §20 identifies an independent human
  failure mode; default coordinates and sizes remain non-gates.
- When Finder-facing naming/restoration or its package owner changes, run one
  representative packaged Finder journey; Core App 1.0 also runs it. Limit
  human judgment to Trash naming/collisions, restoration discoverability, and
  continued access to retained Records. Deterministic or system-integration
  evidence owns separately moved Critiques, dirty peers, File Provider/sync
  races, original-path reappearance, Trash emptying, plan persistence, native
  outcome uncertainty, receipts, and cleanup recovery. Do not repeat human
  process interruption for those variants; no Finder acceptance is retained yet.
- Close remaining deterministic Metadata coverage for custom definitions,
  optional Agent preferences, lifecycle/use counts, controlled choices,
  Complete Metadata, CreatorList, first-record creation, removal/Undo,
  conflict and authored `summary`/`keywords` exact-source routes. Add a
  separate human journey only if a custom boundary is not exercised by §20's
  representative VoiceOver, keyboard or adaptation checks.
- Close remaining deterministic Zotero Link/Fill coverage for unavailable,
  empty/no-result, library identity, proposed fill, retained conflict, changed
  item/server, revision, partial commit, set/rebind/refresh and confirmed clear.
  Reuse the representative human checks instead of repeating every state at
  every width and adaptation.
- Close remaining deterministic grouped Settings, Hotkey and Appearance
  coverage for relaunch, menu update, conflict, reserved shortcut, clear/default,
  search, unsaved-draft switching, narrow reflow and enlarged text. Human visual
  judgment belongs to the one §20 adaptation set.

## Agent collaboration acceptance

- In one clean external account, independently download and install the CLI
  archive and sandboxed App, verify the copied instruction and version-matched
  user-local launch, then exercise the production bridge through one
  representative handoff, Context, applicable bounded write or recovery,
  Result, continuation or End, and unavailable-App fallback. Include explicit
  CLI self-update only when its updater/installer changed and for 1.0. This is
  artifact smoke, not a human failure-state matrix.
- On those artifacts, exercise one representative `preflight-analysis` route.
  Deterministic fixtures retain omitted/populated authored YAML, optional
  Settings preferences, managed-root/existing-Analysis destinations,
  path/identity occupation, missing/trashed or restored source, restart, stale
  projection, replay conflict, expired Session, and outcome-unknown transport.
  Use §20's single Agent human journey to judge one consequential recovery's
  wording and branch choice; do not replay the deterministic matrix there.
- Complete one Agent Collaboration human accessibility journey across handoff,
  activity tracking, Result and recovery, with enlarged mixed-script content.
  Deterministic coverage retains evaluation and continuation semantics; do not
  repeat the human matrix for every Action or lifecycle state.

## Editor input and semantics

- Complete §20's installed Simplified Chinese IME journey in Edit and Source,
  including nondefault candidate selection, mixed-script cursor/selection,
  selection replacement, Undo, autosave, mode switching, reopen and exact-source
  comparison. Deterministic tests continue to cover inactivity, conflict and
  recovery without requiring each branch in the human journey.
- Exercise pointer and keyboard behavior for construct-scoped syntax, completed-
  selection toolbar timing, context menus, Callouts, footnotes, lists, tables,
  suggestions, previews, and source-return navigation.
- Complete deterministic keyboard, semantic, relaunch, missing-path and cleanup
  coverage for image Import, pasted-image Import, absolute-path Index and
  indexed-attachment reminders. Focused tests prove typed transactions and
  path/bookmark boundaries but not human acceptance; add no separate human row
  unless an independent custom interaction remains outside §20's core journeys.
- For a Beta that changes an Editor performance owner or boundary, run the
  affected packaged latency, correctness, and memory series; include them in the
  complete Core App 1.0 or named-baseline campaign. Each selected series must
  pass, while a focused report remains Incomplete and never becomes G7. Extend
  shared source-range fixtures before changing parser or syntax rules.
- Include one representative managed-New-Note direct-to-Edit journey in the
  first complete UI baseline and rerun it when the creation or editor-focus
  owner changes. It proves immediate Edit, exact body-start focus, first-key
  persistence, and that adding a custom Metadata definition does not alter the
  fixed YAML scaffold. Deterministic creation, YAML-patch, and editor tests own
  empty and populated `summary`/`keywords`; do not multiply those states into
  UI or human journeys. §21.4 owns applicable latency evidence, and Scholium
  makes no zero-latency claim. No retained run currently closes this journey.

## Search and performance

- Review the [Search Case Pack](04-verification.md#search-case-pack) with the
  researcher and directly accept dynamic Metadata-key and controlled-value
  completion before deciding whether Note-identity completion is also needed.
  Keep Explain Query compact only if its complete fields remain keyboard and
  VoiceOver reachable.
- Complete GUI first-paint, pointer, ranking, deterministic accessibility and
  research-use acceptance for Note and Record Search. The representative Core
  VoiceOver/keyboard journey crosses Search once; CJK IME belongs to its editor
  journey, while Voice Control and Dictation follow §20's change-triggered rule.
- For Core App 1.0 or the next named G7 baseline, freeze the exact source,
  artifact, fixture, driver, and reference-machine configuration, then complete
  the bounded campaign. A performance-affecting Beta freezes the same applicable
  provenance but runs only affected packaged series. Preserve complete matching
  series when replacing an invalid series; do not erase a valid threshold
  failure by changing the plan after inspection. Working-tree and scenario
  evidence is not release acceptance. Confirm that blank owners expose
  accessible Loading and that long or unbounded work keeps nonblocking progress
  and safe cancellation where applicable; retained-content transitions require
  no synthetic progress state solely because of duration.

## Source coordination, recovery, and external locators

- Exercise a real File Provider domain, dataless materialization/eviction,
  provider-side replacement, sync rename, concurrent external edits, and
  packaged-process interruption. Prove silent Saved only after exact canonical
  readback, Conflict on revision change, Autosave Failed on unproven commit,
  and retained editor bytes in both exceptional outcomes.
- Recheck conflict focus, direct Record Undo and retained interrupted candidates
  deterministically. Include one high-consequence conflict or recovery route in
  §20's representative VoiceOver/keyboard checks rather than repeating every
  recovery branch with assistive technology. Finder
  metadata, ACL/xattr identity, parent-directory synchronization, and cleanup
  completion are not save-success acceptance criteria.
- Treat packaged reopen after an external Skill folder or selected Analyze
  source moves, disappears, is evicted, or is restored as an Agent
  Collaboration integration journey under §21.5: rerun it for a Beta only when
  its locator, source-access, or package boundary changes, and close its
  applicable profile-scoped acceptance for 1.0. It never blocks the Core App
  profile. Skill-file content changes remain outside Scholium observation.
- Implement the specific-Zotero-attachment route in the Analyze source
  selector before claiming direct selection acceptance. Its functional and
  packaged acceptance belongs to the Agent Collaboration/Zotero integration
  and follows §21.5's change-triggered cadence. Deterministic tests already own
  exact parent/attachment identity, selected-file and symlink refusal, and
  missing, changed, or unavailable source behavior; they do not prove the
  direct interface journey. Scholium has no built-in PDF reader, and §17
  defers attachment presentation, so there is no reader-versus-MCP gate.

## Distribution and release

- Run a focused source/privacy audit when a Beta changes permissions,
  credentials, source containment, external-data disclosure, generated state
  or logging, or package ownership; repeat the complete audit for Core App 1.0.
  Unchanged owners do not block a Beta, while per-artifact source, package,
  entitlement, private-path, credential, and state-disclosure guards remain
  mandatory.
- Complete the per-Beta G9 smoke on the exact mounted DMG and copied App in one
  clean external account: Bootstrap, connect a disposable Triptych, open one
  Note, edit/save with exact readback, relaunch, and reopen. Confirm that absent
  optional integrations do not block this Agent-independent Core path. The
  current packaged-first-launch script reaches Bootstrap only and does not
  close this smoke.
- Run packaged Search, Inspector, conflict/recovery, Finder restoration, or
  integration-specific journeys only when their owner or package boundary
  changed; Core App 1.0 includes one representative of each. Deterministic QA
  owns remaining variants, while §20 owns its bounded human checks.
- Close the Agent Collaboration distribution profile with the clean-account
  artifact smoke above and §20's one representative human Agent journey;
  deterministic protocol variants and any changed-template review remain
  separate.
- Establish the retained human icon baseline on the next Core Beta because none
  exists: inspect the canonical icon in Finder, Dock, standard small sizes,
  Light/Dark, and the packaged App. Later Betas repeat only after artwork, icon
  generation, bundle metadata, package presentation, or supported macOS icon
  presentation changes; Core App 1.0 repeats the complete inspection. Every
  artifact still verifies the icon resource and reference structurally.
- Close the complete packaged G7 campaign before Core App 1.0 or the next named
  performance baseline; it is not an unconditional Beta blocker when measured
  surfaces are unchanged. Complete remaining Core App distribution integrity
  and final researcher acceptance. Ongoing Method field use is nonblocking
  product research; Agent collaboration acceptance remains separate and cannot
  block the Core App profile. Earlier
  Beta waivers did not convert missing evidence into a pass. Release and gate
  decisions retain exact source, toolchain, artifact, fixture, procedure, and
  result provenance; focused evidence keeps only the context its claim needs.
