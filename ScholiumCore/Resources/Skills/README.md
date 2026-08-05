# Scholium research-method resources

This tree is release-managed source material. It has no catalog, package,
plugin, version, dependency, or execution semantics.

## Current product ownership

- Protected System Skills define Scholium mechanism and cannot be replaced by
  research prose.
- Each available Action in a Triptych has exactly one current opaque Skill
  registration: visible name, Action, primary Markdown entry, optional ordinary
  local folder path, and enabled state.
- The primary Markdown entry is the Method authority. Exact Wikilinks in that
  entry select ordered researcher-owned Philosophical Practice Markdown.
- An optional Skill folder is ordinary Agent-readable storage. Scholium stores
  only a portable machine-local marker plus a private path/bookmark locator and
  neither catalogs, copies, freezes, hashes, validates, proxies, nor executes
  the folder's other contents.
- Action Profiles own flat academic input/result fields only. Protected
  Platform Action definitions own roles, capabilities, machine facts, and
  supported operations. One Triptych collaboration policy owns interruption
  behavior.
- Scholium-mediated Method and Practice edits keep one replaceable
  previous-edit recovery point, not a version history.

The files below serve these defaults:

| Action | Default primary Method source |
| --- | --- |
| Discuss | `Scholium Method Skills/scholium-discuss/SKILL.md` |
| Analyze | `Scholium Method Skills/scholium-analyze/SKILL.md` |
| Synthesize | `Scholium Method Skills/scholium-synthesize/SKILL.md` |
| Write | `Scholium Method Skills/scholium-write/SKILL.md` |
| Critique | `Scholium Method Skills/scholium-critique/SKILL.md` |
| Check Fidelity | `Scholium Method Skills/scholium-content-fidelity/SKILL.md` |
| Manuscript | `Scholium Method Skills/scholium-manuscript/SKILL.md` |

`BundledResearchMethodDefaults` installs the current default primary Markdown
through the registration owner for a new Triptych. Later restoration explicitly
replaces the current primary bytes and preserves the displaced bytes as the one
previous-edit recovery point; no runtime fallback consults this tree.

## Protected reference resources

`Scholium System Skills` documents identity, provenance, Session,
bounded-write, Record, Discussion, Zotero, and integration mechanisms for
maintainers and Agent-facing method authors. Runtime authority remains in
Platform contracts and Application code; these Markdown files cannot grant
scope or replace the authenticated Core Protocol.

`Philosophical Practices` contains the nine exact default Practice documents
copied into a new Triptych. The folder has no entry point or activation
metadata and is not a Skill package. Citation style is a protected Platform
integration setting; it is not represented by a bundled Skill.
