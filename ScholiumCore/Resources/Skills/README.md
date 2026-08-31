# Scholium research guidance resources

This tree is release-managed source material. It has no catalog, package,
plug-in, version, dependency, or execution semantics.

## Product ownership

- Protected System Protocol resources define Scholium mechanism. They remain
  release-managed and cannot be replaced by researcher prose. They are not
  Action Skills.
- Each available Action in a Triptych has exactly one current opaque Skill
  registration: relation key, visible name, Action, folder location, and
  enabled state. No primary entry, file inventory, or content revision is a
  product field.
- A registered Action Skill folder and every file below it are ordinary
  researcher-owned filesystem content. The researcher and external Agents may
  read or edit those files with ordinary filesystem tools.
- Scholium stores only the folder relation and availability. It does not open,
  enumerate, parse, validate, hash, snapshot, edit, restore, or execute the
  user-owned folder's contents. Settings can assign a folder or reveal it in
  Finder; it is not a Skill editor.
- Action Profiles own flat academic input/result fields only. Protected
  Platform Action definitions own roles, capabilities, machine facts, and
  supported operations. The Run owner records Agent activity without a
  per-document permission policy.

The files below are bundled templates for initial Action Skill copies:

| Action | Bundled template entry |
| --- | --- |
| Discuss | `Scholium Method Skills/scholium-discuss/SKILL.md` |
| Analyze | `Scholium Method Skills/scholium-analyze/SKILL.md` |
| Synthesize | `Scholium Method Skills/scholium-synthesize/SKILL.md` |
| Write | `Scholium Method Skills/scholium-write/SKILL.md` |
| Critique | `Scholium Method Skills/scholium-critique/SKILL.md` |
| Check Fidelity | `Scholium Method Skills/scholium-content-fidelity/SKILL.md` |

`BundledResearchSkillDefaults` provisions a new Triptych's initial user-owned
copies once, before publishing their registrations. Existing registrations are
never filled, repaired, overwritten, or restored from this tree. After that
one-time handoff Scholium does not read or write the copied files, including
`SKILL.md` and `references/`.

## Protected Protocol resources

`Scholium System Skills` is the resource-directory name for the protected Core
Protocol and the distinct Discussion and Zotero Protocol adapters. An external
Agent workspace registers those release-managed folders and the current
researcher-owned Action Skill folders through its host's project-level Skill
mechanism. Typed Application and CLI contracts own identity, required guidance,
registration revision, provenance, Session, bounded writes, and Result fields;
they transmit no Skill prose, content revision, or folder path.

The Core Protocol owns authenticated Run routing, current typed `next_actions`,
mutation and recovery operations, and completion references. The Discussion
Protocol separately owns Discussion-turn response composition because Discuss
does not use the generic Result-submission path. Platform contracts and current
Application state remain runtime authority, so Action Skill text cannot define
commands or executable operations.

Bundled Action templates may include a `references/` directory and route any
task-relevant philosophical lenses from their `SKILL.md`. Once copied, every
such file is researcher-owned and externally editable; Scholium does not
catalog or interpret it. Filename, Wikilink, and transclusion conventions create
no product relation or authority. Action Skill edits may change scholarly
procedure and content, but cannot change Scholium commands, typed operations,
lifecycle, Result serialization, or recovery.
