# Scholium Research Skill resources

This tree is release-managed source material. It has no catalog, package,
plugin, version, dependency, or execution semantics.

## Current product ownership

- Protected System Skills define Scholium mechanism and cannot be replaced by
  research prose.
- Each available Action in a Triptych has exactly one current opaque Skill
  registration: visible name, Action, primary Markdown entry, optional ordinary
  local folder path, and enabled state.
- `SKILL.md` is the Skill entry. It explicitly routes task-relevant ordinary
  intellectual references, including philosophical lenses, from the registered
  folder. It does not route Scholium operations or System Skills.
- A Skill folder is ordinary Agent-readable storage. Scholium stores
  only a portable machine-local marker plus a private path/bookmark locator and
  neither catalogs, copies, freezes, hashes, validates, proxies, nor executes
  the folder's other contents.
- Action Profiles own flat academic input/result fields only. Protected
  Platform Action definitions own roles, capabilities, machine facts, and
  supported operations. One Triptych collaboration policy owns interruption
  behavior.
- Scholium-mediated Skill improvement replaces only the exact expected
  `SKILL.md`; ordinary references are edited as ordinary files outside that
  bounded Run. This tree provides no edit history.

The files below serve these defaults:

| Action | Default Skill entry |
| --- | --- |
| Discuss | `Scholium Method Skills/scholium-discuss/SKILL.md` |
| Analyze | `Scholium Method Skills/scholium-analyze/SKILL.md` |
| Synthesize | `Scholium Method Skills/scholium-synthesize/SKILL.md` |
| Write | `Scholium Method Skills/scholium-write/SKILL.md` |
| Critique | `Scholium Method Skills/scholium-critique/SKILL.md` |
| Check Fidelity | `Scholium Method Skills/scholium-content-fidelity/SKILL.md` |

`BundledResearchMethodDefaults` installs the current default primary Markdown
through the registration owner for a new Triptych. Later restoration explicitly
replaces the expected current primary bytes; no recovery copy or runtime
fallback consults this tree.

## Protected reference resources

`Scholium System Skills` owns the protected Core workflow plus the distinct
Discussion and Zotero adapters. An external Agent workspace registers those
release-managed folders and the current Action Method folders through its
host's project-level Skill mechanism. Typed Application/CLI contracts own
current identity, required Skill names and frozen Method revision, provenance,
Session, bounded-write, and Result fields; they transmit no Skill prose or
source path. Core always loads its protected `runtime-kernel.md`; the current
request or official handoff routes project entry, and an explicit researcher
request routes workspace bootstrap. After authentication, Application-owned
Run state, typed `next_actions`, and operation responses route active-run,
mutation/recovery, and completion references. Those references are not
Agent-selected modes and add no command field or parallel state. The completion reference routes exactly one
per-Action Result reference, which owns the mapping from scholarly judgments
into the frozen Action Profile fields without defining the intellectual method
or overriding the Profile's field names, choices, types, or requirements. The
Discussion System Protocol separately owns Discussion-turn response composition
because Discuss does not use the generic Result submission path. Platform
contracts and current Application state remain the runtime authority, so Skill
registration or text cannot grant scope, capability, or write permission.

Each default Skill's `references/` directory directly contains its
methodologically substantive philosophical lenses, and that Skill's
`SKILL.md` decides when each lens applies. Lenses have no independent shared
library, catalog, registration, resolver, snapshot, or execution authority.
Method Skills do not own Result-field or Discussion-response templates.
Researcher edits may change scholarly procedure, emphasis, organization, and
content within the protected Action, but they cannot change the Application's
Action, commands, tools, permissions, Bounded Write Set, lifecycle, or recovery.
Citation style is a protected Platform integration setting; it is not
represented by a bundled Skill.
