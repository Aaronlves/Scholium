# Specification: Settings

[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md) · Section 18.2.1.

## 18.2.1 Settings

Settings lets the researcher find a preference, understand its current value
and scope, and determine whether a change has taken effect. It holds durable,
infrequently changed preferences; frequent task-local adjustments remain with
their task. Defaults support ordinary research without mandatory customization.
Only settings with a distinct researcher need are exposed; system preferences
retain their authority without redundant app controls.

[Design §19](../../Design.md) owns auxiliary-window appearance, typography,
materials and motion. [Accessibility §20](09-accessibility-and-adaptation.md)
owns adaptation, keyboard and assistive routes, validation and draft protection.
This chapter is the entry point for Settings design and implementation. It owns
shared composition and interaction; feature contracts own what a setting may
change. It adds no theme or parallel accessibility rules. These are target
requirements; implementation evidence remains in the Status set.

### Navigation, discovery and scope

One native preferences window opens through the App menu and Command-Comma.
A fixed native icon-and-label navigation column remains visible and identifies
the selected category; it has no collapse action or draggable split divider.
The sidebar and content retain their separate native titlebar regions, with
sidebar material continuing to the window’s top edge.
The window title reflects that pane. Reopening restores the last category. The
window retains its size while switching categories; the researcher can resize it.
Category changes do not animate window geometry or discard unsaved drafts,
selection or scroll position in pages already opened in the settings session.
Inactive pages have no keyboard, pointer or accessibility interaction.

The navigation column presents seven task categories: Workspace, Document
Appearance, Writing Assistance, Agents & Chat, Keyboard Shortcuts,
Notifications & Reminders and Zotero. Workspace owns Triptych registration,
folder access and portable-data location. Document Appearance presents the
complete content profile and CSS snippets in one scrolling page. Writing
Assistance groups opt-in continuation and its independent model choice with
Selection Actions. Keyboard Shortcuts is directly reachable.
Agents & Chat uses three native segments: Connection and Chat, Skills and Tools,
and External Access. Each segment is a complete scrolling task page; manual
paths and external-host setup remain inline. Core Protocol, optional Skills and
connected tools belong to the same Agent configuration area. Zotero owns its
Desktop Local API diagnosis and the managed `scholium-zotero` Chat connection;
there is no separate user-editable Zotero connection editor. Notifications &
Reminders separates Triptych dismissal-return timing from the Mac-local ledger.
Category grouping does not imply storage or sharing scope. Pages identify This
Mac, This Triptych or mixed scope as applicable through their category, group
and adjacent state labels; exact Triptych identity is shown before a portable
draft. Scope changes cannot silently apply a draft to another target. Settings
does not repeat this information in a page-wide notice.

Settings does not duplicate macOS appearance, accent, contrast or motion
controls. Scholium's window chrome and semantic feedback use system-resolved
colors and adaptation. Document Appearance controls Markdown content
presentation only; researcher-editable document CSS and text colors remain in
that content layer and never style native app controls.

Each setting has one editing location. Contextual links and Settings search
lead to that location rather than maintaining duplicate controls. Search indexes
static page/control metadata, including English and Simplified Chinese labels
and common user-facing synonyms, never research or Skill content.
Results name the setting and category; choosing a result selects the owning
category and Agent segment, then reveals the named
control or group in the existing scroll plane without changing its value.
Search navigation preserves the prior browsing category and segment; clearing
the query restores them. Configuration links select their explicit destination
rather than restoring a prior search destination.
No matches preserves the query; clearing search restores the browsing context.

### Page composition

The selected pane makes its scope and any necessary target identity legible
through its category, group and adjacent state labels before or beside the
editable control. Group headings name related tasks or preferences, with common
choices before optional detail. Reuse the window's category title instead of
adding a duplicate large heading. Short panes remain compact; each longer page
has one primary vertical scroll plane without losing access to its scoped
actions. Content reflows at narrow
widths; a wide matrix becomes named rows instead of hiding its fields. Native
text editors may retain local text scrolling.

Related preferences use native grouped surfaces, with a heading above each
group and labels beside their controls. Groups use the available content width;
a wide, fixed label column must not compress the controls. Supporting copy stays
beside its owner. Native collections hold field/shortcut rows and adjacent
actions. Shared relationships
use consistent alignment and spacing without forcing every pane into identical
height or containers. Status and validation fit beside the affected control
without replacing the active form or needlessly shifting its controls.

Native group surfaces distinguish related preferences; individual peer rows
share that surface rather than each receiving a card. Separators remain for a
native collection or menu, or for a genuine structural boundary such as a
persistent action area. A peer preference
is not hidden in a nested disclosure merely to shorten a pane. Ordinary
configuration groups and single-object editors remain inline in their owning
page; one selected-object editor retains its target, draft, validation,
Save and Cancel. Segmented controls may switch a small set of coherent task
views or express mutually exclusive choices. Native file/folder selection,
provider sign-in and required confirmations retain their task presentations.

An ordinary setting row pairs a label with its current value or control;
explanation and field feedback follow that control. A collection keeps selection
and its Add, Remove or Edit actions together. A connection group presents the
observed state with its applicable setup or repair action. Use the composition
that expresses these relationships rather than wrapping every row in a card.
Group-wide Save or Restore actions sit with their affected group; a pane-wide
action is used only when the whole pane is one transaction. Unavailable setup
and loading states retain the pane's identity and explain what can happen next.

### Controls and writing

Control choice follows meaning: checkboxes or switches express independent
binary preferences, radio groups or pop-up buttons express mutually exclusive
values, and buttons perform actions. Small sets whose alternatives need direct
comparison remain visible; longer flat choices may use a pop-up button.

Labels use the following grammar. Examples illustrate wording, not additional
features or required literal translations.

| Item | Wording | Example |
| --- | --- | --- |
| Category or group | Name the subject. | Document Appearance / 文稿外观 |
| Behavioral preference | Describe the enabled behavior. | Enable Selection Action / 启用选区操作 |
| Parameter | Name the value being chosen. | Line Spacing / 行距 |
| Action | Name the immediate action and object. | Check Connection / 检查连接 |
| Status | State the observed fact. | Not Connected / 未连接 |

Prefer specific verbs and objects over generic Enable or Manage wording.
Toggle labels remain stable and positive across states; avoid double negatives.
Parameter labels such as Body Font or Line Spacing remain nouns. Supporting
copy explains scope, a nonobvious consequence or repair instead of repeating
the label. English and Chinese preserve the same meaning without requiring
identical word order. Terminology follows §18.7 and writing follows §19.5.
Numeric fields identify meaningful units and applicable limits; invalid input
is explained at its field rather than silently replaced with a valid value.

### Dependencies and defaults

Dependent controls stay near their prerequisite. Keep them visible but disabled
when knowing they exist helps explain availability, with a reason when needed;
hide detail that has no meaning in the current choice. Disabling a parent
preserves subordinate choices for reuse. Low-frequency detail follows common
choices in a specifically named inline group. It must not hide current failures
or required repair. Default, Automatic and Follow System identify their actual source; show the effective value when needed to
understand inherited behavior, without inventing configuration layers.

### Changes and feedback

Simple reversible preferences take effect immediately when their owning
contract permits it. Validated or coordinated changes use an
explicit, scoped Save or Apply action; category navigation is not an implicit
commit. Distinguish the edited value, saved configuration and effective runtime
state whenever they differ. Pending application or a required reload is named;
a successful save alone does not claim a successful connection or runtime change.
Local feedback follows §18.3, with retained invalid/conflicting drafts under §20.

Restore actions name the affected setting or group and preserve unrelated
configuration. A preview, where provided, represents the affected presentation
and clearly distinguishes unapplied changes. Presentation preferences do not
rewrite research source; any data-changing action names its target and effect
under its owning workflow contract.

### Configuration failure and recovery

A failed preference or configuration group does not disable unrelated settings
or prevent opening Settings. Read-time fallback never silently replaces saved
configuration. A supported configuration isolates invalid entries or fields,
keeps valid choices effective and identifies the affected values. An unreadable
or unsupported envelope remains preserved, with safe effective defaults and a
scoped reload or recovery route; unsupported values grant no new access.

Workspace owns explicit restoration of this Triptych's portable settings.
Confirmation identifies the scope; restoration preserves an exact copy of an
existing file before replacing it with defaults and checks the observed revision.
Folder registration, access grants, research source and unrelated preferences
remain unchanged. Missing files require an absence check before creation. A
changed target or file requires a fresh read and confirmation. Existing drafts
remain attached to their original target and revision; stale drafts need explicit
reload before saving. Recovery failure retains context and a retry route;
committed restoration with a later refresh failure is reported separately.

### Feature ownership

[Document Appearance §18.4](07-document-and-research-interface.md#184-document-modes-context-and-source-properties)
owns appearance controls, configuration-file editing and restoration; Settings
does not create a second appearance owner or duplicate its controls. Its native
form and Advanced CSS entry share the Document Appearance owner;
profile changes never reset CSS snippets. [Source Properties Appendix A](02-notes-and-file-operations.md#appendix-a-authored-source-properties)
owns authored YAML; [Agent Chat §8.7](12-agent-chat.md) owns Selection
Actions and runtime configuration. Agents & Chat keeps connection state and
primary connect or sign-in actions in Connection and Chat, with custom paths
inline. Skills and Tools and External Access are its retained task segments.
Selection Action edits belong to one page draft and have one scoped Save;
inline shortcut capture stops when its page becomes inactive. Tool edits remain
independent transactions; moving them inline does not alter configuration
version checks, shared-scope confirmation, credentials or sign-in. [Agent Collaboration §8](03-agent-collaboration-and-workflows.md)
and [Zotero §15](05-integrations-onboarding-and-boundaries.md) own integration
behavior. [Chat capability presentation](14-chat-interface.md#chat-capability-presentation)
owns the Agent pane's feature-specific controls. [Triptych §§3–4](01-foundation-and-triptych.md)
and [Attention §13](04-connect-search-and-recovery.md) own their respective
workflow meanings. Their save, confirmation and source-preservation rules remain
binding; this chapter does not grant new configuration or mutation capabilities.

Keyboard Shortcuts is machine-local and limited to frequent Scholium-specific
menu commands. It requires Command, rejects conflicts and reserved shortcuts,
and supports clear and restore. Standard macOS commands remain outside
remapping.
