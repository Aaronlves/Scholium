# Scholium UI test matrix

`Docs/PRODUCT_GUIDE.md` owns target workflows. Proposal, Research Session, authored Canvas, and export are migration-data checks only and have no reachable target UI. Target journeys use Dialogue, Critique, Note History, checkpoints, view-only Canvas, and external-edit conflict recovery.

Use the exact meanings and labels in Section 10 of `Docs/DESIGN_HANDBOOK.md` in the bound checkout. This matrix asserts the contract at the user boundary; it does not redefine it.

## Critical workflows

| Workflow | Primary assertions |
|---|---|
| First launch and vault selection | valid vault opens; cancelled picker is harmless; bookmark lifecycle is correct |
| Sidebar navigation | selection, back/forward history, sorting, filters, and open-in-new-tab behavior remain coherent |
| Read, Live Preview, Source | one exact source buffer survives mode transitions; cursor, selection, and focus remain usable |
| Search Workspace | Shift-Command-F opens the workspace; current-note/current-vault/all-workspace/selected-role scopes compose with field queries; Unicode/CJK, phrases, prefixes, exclusions, snippets, source lines, vault names, and roles remain correct; saved searches persist outside vaults; keyboard selection opens the exact hit |
| Independent windows | Command-N creates a separate document surface rather than an automatic tab; tabs, history, document modes, scroll, inspector, search, and canvas selection remain session-local; shared repository and derived commits converge in every window without duplicate writes or stale relabelling |
| Authoritative save commit | repository returns a committed fingerprint; disk bytes and authoritative document model agree; the schema-role timestamp rule is correct; the document reaches **Saved** without waiting for derived consumers |
| Derived refresh after save | search, links, relationships, rendering, and review diagnostics reach the committed revision or expose the correctly scoped **Refreshing**, **Derived State Stale**, or **Refresh Failed** state; a derived failure never relabels the source as unsaved |
| External edit conflict | no overwrite; editor and buffer remain open; the exact lifecycle actions required by the canonical contract appear for the implemented comparison capability |
| Properties | only intended top-level fields change; malformed YAML blocks metadata editing without hiding content |
| Review workflow | review fingerprint updates; changed-since-review state appears; review-and-advance selects the right note |
| Agent proposal | target, provenance, revision, validation, and exact change appear before authorization; each valid, stale, invalid, applying, failed, and applied lifecycle exposes only the exact contract actions supported at that stage |
| Research sessions | task title, objective, mode, object, evidence layers, allowed/forbidden materials, privacy boundary, authorized output, and file-update permission survive creation and reopening; completing an unauthorized session cannot claim an authorized control update; checkpoints never imply source support, prose approval, or settlement |
| Attention queues | refresh, empty, error, severity, filtering, and exact-line navigation work; items are visibly derived and never change evidence or governance; opening one selects the correct vault/note/line without silently granting write authority |
| Relationships | incoming/outgoing direction, broken and ambiguous links, and neutral versus evidential links remain distinct |
| Document CSS and safe mode | allowed typography applies consistently to Read and Live Preview; rejected selectors/properties are explained; unsafe content cannot weaken protected research UI; a rendering failure enters recoverable CSS safe mode without changing Markdown or vault state |
| Export | cancellation is harmless; HTML and PDF use the selected review/provenance/metadata options; machine metadata, proposals, diagnostics, and local paths remain excluded; render and destination-write failures preserve the open note; output is written only to the researcher-selected destination |
| Canvas | named-canvas create/select/rename/duplicate/delete, searchable insertion, drag, relation filter, remove, clear, persistence, and keyboard-accessible alternatives work; canvas-only annotations remain outside the vault and are never presented as evidence |
| Zotero source boundary | unavailable or disabled localhost API, unresolved or ambiguous key, and failed Open-in-Zotero remain specific and recoverable; an Analysis exposes only its own item, a Topic or Work exposes only directly linked Analyses, and Scholium never enumerates attachments or unrelated library items |

## Current automated baseline

The repository's current `ScholiumUITests` harness deterministically covers only:

- keyboard reachability of the document-mode menu, Research Inspector, and Search Workspace;
- creation of a second window with Command-N.

Treat every other row as required or candidate coverage until a current test, failure artifact, or explicitly labelled exploratory run proves it. A missing historical QA log does not block the harness and is not evidence that a row passed.

## Harness and artifact choice

- Routine deterministic UI work: `./Tools/Scripts/build-qa-app.sh` followed by `./Tools/Scripts/run-ui-tests.sh`, using the isolated `com.kbmanager.qa` bundle and disposable fixture/state roots.
- Release signing, entitlements, persisted bookmark, clean-install, or acceptance-performance work: build the exact release artifact with `./Tools/Scripts/package-app.sh` and label any non-XCUITest smoke observations accurately.
- Never run either path against a private research vault. Never infer broad matrix coverage from a successful build or the two baseline tests.

## Keyboard and accessibility pass

- Reach every important command from the menu bar.
- Verify documented shortcuts and Escape cancellation.
- Traverse controls with Tab, Shift-Tab, arrows, Return, and Space.
- Restore focus after sheets, alerts, proposal review, and mode changes.
- Confirm identifiers are stable while visible labels remain user-facing and localizable.

## Failure artifacts

On failure, preserve evidence only from a synthetic disposable fixture and test-owned application state:

- screenshot of the relevant window;
- current accessibility hierarchy when available;
- build and fixture identifiers;
- step name, timeout, and expected state;
- redacted logs and test-owned Application Support state.

Never attach private research content or paths. Include synthetic note text only when it is necessary to explain the failed assertion.
