# Architecture: Research Guidance

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Skill
registration and ordinary references, academic Profiles,
Run-collaboration and citation configuration, Settings composition, and
configuration recovery. [Research Actions and Execution](02-research-actions-and-execution.md)
alone owns preparation, pairing, Sessions, Run context, Activity Ledgers,
results, evaluation, and completion.

## Configuration owners

Research Guidance has one strict configuration owner and one closed Platform
catalog:

```text
ResearchConfigurationStore
    strict revision-checked Triptych subdocuments
        |
        +-> ResearchSkillRegistrationDocument
              one Action -> one enabled registration
              hidden stable key, display name, folder locator, enabled state
        |
        +-> ResearchSkillFolderLocatorStore
              private absolute path and read-only folder bookmark
              folder availability without content access or enumeration
        |
        +-> ResearchAcademicProfileDocument
              flat academic input/result fields only
        |
        +-> ResearchCitationMethodDocument
              one optional code-catalog citation style per Triptych

PlatformActionCatalog
    protected supported roles, selectors, source preconditions,
    machine fields, and executable operations
```

The portable registration document contains no absolute path, bookmark, Skill
bytes, folder inventory, version, digest, dependency, or capability
declaration. A folder under the portable control root uses a descriptor-
relative locator. A folder outside that root uses a stable machine-local
locator in private Application Support with one read-only bookmark. The
researcher filesystem owns every file inside an Action Skill folder.

`ResearchConfigurationStore` resolves the folder relation and availability
only. It has no file-content I/O API, content revision, Markdown replacement,
default restoration, directory enumeration, dependency validation, or script
execution. Initial Triptych setup copies bundled templates once before it
publishes the registrations; later bootstrap sees the registration document
and never fills, repairs, or overwrites a user folder.

## Skills and ordinary references

A Skill registration points to one ordinary researcher-owned folder for
external Agent project discovery. It does not identify or require a primary
entry. Registering or removing a Skill never gives Scholium ownership of the
folder or any content beneath it.

Reference files, including philosophical lenses, remain ordinary files inside
the Skill folder. The external Agent's Skill may route task-relevant files;
Application neither catalogs nor parses any content, and no Wikilink,
title, filename, alias, or transclusion creates a second product relation.
Bundled defaults keep a bounded lens subset directly in each applicable
Skill's `references/` directory. Those references are release-managed parts of
their owning Skills, not an independently installed catalog or shared library.
The exact Action Method may change scholarly procedure, emphasis, organization,
and content only. It does not route System Skills or define commands, tools,
executable operations, Run lifecycle, Result serialization, or
recovery; Application contracts and Core Protocol retain those owners. Before
authentication, the request or official handoff routes project entry and an
explicit researcher request routes workspace bootstrap. After authentication,
current Run state, typed `next_actions`, and operation responses alone select
Core's Run references. This is progressive System-protocol disclosure, not a
philosophical Mode or another state owner.

Scholium exposes no Method-improvement Run and never edits the folder.
Researchers and external Agents use ordinary filesystem tools; the bundled
template is never a runtime fallback.

## Profiles and Platform authority

`PlatformActionCatalog` is code-owned and closed. It owns supported roles,
selectors, source preconditions, machine fields, executable operations, and
the limits that make an Action available.

`ResearchAcademicActionProfile` stores only bounded academic free-text,
single-choice, and multiple-choice input or result fields; their order,
necessity, visible name, role-valid placement, and enabled state. A Run's
`ResultContract` freezes those academic result fields together with
Application-provided machine fields. Neither type can represent readable or
writable roles, operations, Metadata boundaries, source capability, recovery
behavior.

## Run collaboration and citation configuration

Research Guidance persists no collaboration or per-document permission policy.
The Run owner automatically records declared targets and actual operations;
Session attribution, current identities and revisions, containment, and
recovery belong to Research Actions and Execution. Research Guidance owns no
global Agent prompt, selected-Agent preference, remembered Agent
application, launch path, or Agent credential. The transient handoff for the
current Run belongs to Research Actions and Execution.

The citation document stores one optional code-catalog identifier such as APA
7. It is an integration setting, not a Skill, reference, permission, or
executable component. Citation checking resolves it at preparation and fails
closed when a requested check has no configured style. Ordinary Actions never
require a citation or treat citation absence as incomplete; a researcher-
initiated Citations Fidelity check evaluates only citations present in its
selected scope.

## Settings and configuration transactions

Settings presents one Research Guidance list/detail surface for Skills, Action
Profiles, and External Tools & Citations. Skills assigns, opens,
enables, or disables an Action's folder relation; it has no content editor,
file picker, create-file command, or default-restoration command. Action
Profiles edits only the academic profile document.
Each editor mutates one owner at a time through an expected-revision
transaction.

Portable `TriptychSettings` schema 8 is a separate strict owner for role
Metadata. It contains stable field definitions by role, About order over
optional managed fields that remain visible when empty, and per-source-type
optional Agent preferences over managed Analysis fields. These are separate
subvalues in one transaction;
adding a definition mutates neither of the other two.
Definition keys and value kinds are stable identity, and definitions cannot be
removed. Existing controlled choices remain valid. Labels, optional
descriptions, field and choice order, active/archived state, and new choices are
editable. Archived definitions remain in record validation and Search. The one
candidate compiler removes them from new-value, About always-shown, and Agent
selection, but an archived field with a stored value remains visible in About.
`TriptychControlStore.settings()` returns decoded settings plus a
`SettingsRevision` computed from exact `settings.json` bytes. Save accepts the
complete candidate and expected revision, rechecks current bytes inside the
store actor, atomically replaces, readbacks, decodes, and returns the new
revision. It never value-compares decoded settings, falls back to defaults for
an existing invalid file, or ships an old-schema decoder.
`settingsLoadState()` keeps current, repairable current-schema, missing, old,
future, and corrupted files distinct. A repairable state retains its decoded
candidate and exact revision for Settings, while ordinary `settings()` fails
closed until the candidate validates. Fixed managed creation does not consume
Settings as authority.
The Settings draft freezes both Triptych identity and exact revision. A
confirmed commit installs its returned revision even if derived refresh fails;
an uncertain replacement is authoritatively reread before another save can be
attempted, and a failed reread keeps that Triptych mutation-blocked. A commit
that began in one Triptych remains truthfully attributed there if the active
Triptych changes while it is in flight; its snapshot is never installed into
the new target. Only a validated current state authorizes About; every other
state supplies an explicit empty display profile, never default authority.
Current-note Metadata editing instead depends on the exact portable metadata
revision and role catalog. Authored YAML editing remains an explicit Source
operation.
Researcher CLI Metadata read/set/remove commands call the same public
Application operations, use natural JSON at their boundary, and expose the
Metadata revision independently from the source fingerprint. No delivery
adapter imports Core or addresses the portable JSON directory.
Portable Triptych Settings does not store prompt bodies or active prompt
selection. User-owned Skill files remain external intellectual configuration;
runtime action contracts consume only their registered folder relation without
a second template representation.

`PropertyContractCatalog` owns the authored YAML allowlist;
`BuiltInNoteMetadataCatalog` owns product-managed shapes;
`TriptychSettings.metadataFields` owns researcher-defined simple shapes and
their presentation/lifecycle guidance;
`NoteMetadataCatalog` is the one immutable workspace-scoped resolution of both;
`AnalysisSourceTypeProfileCatalog` owns applicable/recommended/serialization
order for built-ins, while custom Analysis fields append to every source type.
About and Agent settings own only optional always-shown selection and Agent
preference. A later
managed-creation projection may compile those values
in memory, but no second persisted template or requirements revision exists.

The Action Profile editor can change only visible name, order, enabled state,
role-valid placement, and bounded ordered academic fields. The Skills settings pane
operates only on the Action-folder relation; all file editing remains outside
this surface. External Tools & Citations presents citation selection before machine-
local Zotero and CLI controls. Skill-locator recovery stays beside the affected settings pane.
Invalid machine-local Skill locators have one owner-specific,
confirmation-gated recovery operation. It uses the shared same-directory
exact-state preserver, archives only a typed invalid file, and resets only its
machine-local owner; unsafe storage remains fail-closed.

Removing a registration rechecks Action availability and active Runs. It does
not delete or modify the selected folder. Successful configuration mutation publishes one typed
invalidation so active windows re-resolve affected Action availability without
replacing their workspace snapshot.

## Bundled research resources

`BundledResearchSkillResources` is the one locator for release-managed System
Skill directories. Research Guidance distinguishes those release-managed bytes
from researcher-owned Skills and references, which contain the Action's
intellectual procedure. External Agent project discovery, rather than an
authenticated Context payload, loads both kinds. Run Brief, minimum required
Skill identities, frozen registration revision, Result Contract, capability
availability, command inputs, and Research Context remain typed current data.
Installed CLI help and tool schemas own current invocation syntax.

`ResearchConfigurationStore` also assembles one read-only project
Skill-source manifest from every release-managed System Skill and every enabled
current Action Skill registration. It requires one available folder but never
opens or validates a file within it. An explicitly registered
machine-local folder remains eligible because this command is the authorized
external-workspace setup surface. A source-only
`WorkspaceRuntime` route validates the selected portable manifest and binds the
result to the Works-parent Triptych root without constructing a Workspace,
inventorying research vaults, opening Search, or starting watchers. CLI
serializes it but does not detect a host, enumerate directories, create links,
or edit Agent configuration. The external setup Agent alone registers those
exact sources through its current host's project-level discovery mechanism.

The bundle is not a package manager or second prompt store. Research Guidance
has no staged installer, resource preview, package validation, version
comparison, Skill snapshot history, marketplace, per-Skill permission editor,
or executable extension surface. Project discovery registration does not
change the current Action-folder relation or authenticated Run authority.
