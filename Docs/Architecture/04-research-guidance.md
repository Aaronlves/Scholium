# Architecture: Research Guidance

[IMPLEMENTATION_ARCHITECTURE.md](../IMPLEMENTATION_ARCHITECTURE.md) · Method and
Practice registration, academic Profiles,
collaboration and citation configuration, Settings composition, and
configuration recovery. [Research Actions and Execution](02-research-actions-and-execution.md)
alone owns preparation, pairing, Sessions, Run context, Bounded Write Sets,
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
              hidden stable key, display name, primary Markdown locator,
              optional machine-local folder locator, enabled state
        |
        +-> SecureResearchMethodIO + ResearchPracticeResolver
              exact primary Markdown / Practice reads and targeted writes
              exact Wikilinks, first-use order, deterministic ambiguity
              one replaceable pre-edit recovery point per file
        |
        +-> ResearchAcademicProfileDocument
              flat academic input/result fields only
        |
        +-> ResearchCollaborationPolicyDocument
              one missing-is-Ask-Every-Time policy per Triptych
        |
        +-> ResearchCitationMethodDocument
              one optional code-catalog citation style per Triptych

PlatformActionCatalog
    protected supported roles, selectors, source preconditions,
    machine fields, and executable operations
```

The portable registration document contains no absolute path, bookmark,
Method bytes, folder inventory, version, digest, dependency, or capability
declaration. A primary entry under the portable control root uses a
descriptor-relative locator. An entry or optional folder outside that root
uses a stable machine-local locator and read/write bookmark in private
Application Support. The researcher filesystem owns every unregistered sibling
file in an ordinary Skill folder.

`ResearchConfigurationStore` and `SecureResearchMethodIO` support exact read,
revision-checked complete Markdown replacement, explicit app-default
restoration, and one replaceable recovery point. They do not snapshot a
directory, diff versions, list history, validate dependencies, enumerate
supplements, or execute scripts. External changes use the ordinary current-
revision and conflict boundary.

## Methods and Practices

A Method registration points to one exact primary Markdown file and may also
identify its containing ordinary folder for authenticated Agent access. New
simple Methods may consist of that file alone. Registering or removing a
Method never gives Scholium ownership of the surrounding directory.

Practices are ordinary Markdown files in a bounded Triptych-managed location
or an explicitly selected machine-local location. `ResearchPracticeResolver`
parses ordinary Wikilinks from the exact primary Method, resolves exact title
or explicit path within the Practice catalog, de-duplicates after first use,
and returns missing or ambiguous diagnostics. It does not resolve headings,
blocks, aliases, transclusion, nested Practice dependencies, or Connections.

Each Method and Practice retains at most one machine-local pre-edit recovery
point. A confirmed next Scholium edit replaces that point. Restore compares the
current revision before writing and never treats the bundled default as a
runtime fallback.

## Profiles and Platform authority

`PlatformActionCatalog` is code-owned and closed. It owns supported roles,
selectors, source preconditions, machine fields, executable operations, and
the limits that make an Action available.

`ResearchAcademicActionProfile` stores only bounded academic free-text,
single-choice, and multiple-choice input or result fields; their order,
necessity, visible name, role-valid placement, and enabled state. A Run's
`ResultContract` freezes those academic result fields together with
Application-provided machine fields. Neither type can represent readable or
writable roles, operations, Property boundaries, source capability, recovery
behavior, or permission.

## Collaboration and citation configuration

`ResearchConfigurationStore` persists one strict collaboration policy per
Triptych. Missing state means Ask Me Every Time. The document has no per-Method
override, digest approval, fallback subject, bearer key, or write capability.
The current Action owner recomputes authorization from Platform support, the
policy, the concrete Run request, current identities and revisions, and the
authenticated Run boundary.
It also owns no global Agent prompt, selected-Agent preference, remembered Agent
application, launch path, or Agent credential. The transient handoff for the
current Run belongs to Research Actions and Execution.

The citation document stores one optional code-catalog identifier such as APA
7. It is an integration setting, not a Method, Practice, permission, or
executable component. Citation checking resolves it at preparation and fails
closed when a requested check has no configured style.

## Settings and configuration transactions

Settings presents one Research Guidance list/detail surface for Methods,
Profiles & Practices, Collaboration, Sources & Integrations, and Recovery &
Technical. Each editor mutates one owner at a time through an expected-revision
transaction.

Portable `TriptychSettings` is a separate strict owner for role Properties.
Its current schema contains exact delimiter-free New Note YAML, About order,
and per-source-type Analysis Agent requirements.
`TriptychControlStore.settings()` returns decoded settings plus a
`SettingsRevision` computed from exact `settings.json` bytes. Save accepts the
complete candidate and expected revision, rechecks current bytes inside the
store actor, atomically replaces, readbacks, decodes, and returns the new
revision. It never value-compares decoded settings, falls back to defaults for
an existing invalid file, or ships an old-schema decoder.
`settingsLoadState()` keeps current, repairable current-schema, missing, old,
future, and corrupted files distinct. A repairable state retains its decoded
candidate and exact revision for Settings, while ordinary `settings()` and
managed creation continue to fail closed until the candidate validates.
The Settings draft freezes both Triptych identity and exact revision. A
confirmed commit installs its returned revision even if derived refresh fails;
an uncertain replacement is authoritatively reread before another save can be
attempted, and a failed reread keeps that Triptych mutation-blocked. A commit
that began in one Triptych remains truthfully attributed there if the active
Triptych changes while it is in flight; its snapshot is never installed into
the new target. Only a validated current state authorizes About; every other
state supplies an explicit empty display profile, never default authority.
Current-note structured editing instead depends only on the exact Note source
and targeted patch contract.
Current bundled prompt bodies are app projections selected by stable IDs; load
may replace or supply those in memory without writing the portable file. It
does not repair researcher templates or invalid active-template IDs.

`PropertyContractCatalog` owns shapes; `AnalysisSourceTypeProfileCatalog` owns
applicable/recommended/serialization order; Settings owns only selection and
exact seed source. A later managed-creation projection may compile those values
in memory, but no second persisted template or requirements revision exists.

The Profile editor can change only visible name, order, enabled state,
role-valid placement, and bounded ordered academic fields. The Methods and
Practices editors operate on exact Markdown and expose their one recovery
point. Sources & Integrations owns citation selection plus Zotero and installed
CLI controls. Recovery & Technical owns settled-Note retention; Method and
Practice recovery stays beside the affected editor.

Removing a registration rechecks Action availability and active Runs. It does
not recursively delete the selected folder. Removing a Scholium-managed simple
primary file uses a recoverable isolation transaction and states the exact file
consequence. Successful configuration mutation publishes one typed
invalidation so active windows re-resolve affected Action availability without
replacing their workspace snapshot.

## Bundled research resources

`BundledResearchSkillResources` is the one reader for release-managed Skill
bytes. [Research Actions and Execution](02-research-actions-and-execution.md)
owns loading and delivering the protected Core Skill during an authenticated
Run. Research Guidance distinguishes those release-managed bytes from
researcher-owned Methods and Practices, which contain the Action's intellectual
procedure. Run Brief, Method context, Result Contract, capability availability,
command inputs, and Research Context remain typed current data. Installed CLI
help owns current invocation syntax.

The bundle is not a package manager or second prompt store. Research Guidance
has no staged installer, resource preview, package validation, version
comparison, Skill snapshot history, marketplace, per-Skill permission editor,
or executable extension surface.
