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
  references, including philosophical lenses, from the registered folder.
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
Discussion and Zotero adapters. Typed Application/CLI contracts own current
identity, provenance, Session, bounded-write, and Result fields. The exact
first-authentication Core Protocol is
`scholium-core-protocol/references/runtime-protocol.md`; Application loads that
resource verbatim and embeds no second prompt. Platform contracts and current
Application state remain the runtime authority, so Skill text cannot grant
scope, capability, or write permission.

Each default Skill's `references/` directory directly contains its
methodologically substantive philosophical lenses, and that Skill's
`SKILL.md` decides when each lens applies. Lenses have no independent shared
library, catalog, registration, resolver, snapshot, or execution authority.
Citation style is a protected Platform integration setting; it is not
represented by a bundled Skill.
