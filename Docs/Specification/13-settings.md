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
A stable, noncustomizable icon-and-label toolbar
identifies the selected category; the window title reflects that pane. Reopening
restores the last category. Switching categories adjusts the window from its
current top-left corner to the pane's preferred size within screen bounds,
using native animation and an immediate Reduce Motion result. Routine field
edits and status updates do not repeatedly resize the window.

The native toolbar presents six top-level panes: Workspace, Appearance,
Metadata, Notifications, Interaction and Integrations. Workspace contains local
Triptych registration and folder access. Appearance contains the complete
document-content appearance profile, including reading and typography controls.
Metadata contains
Triptych field definitions and About ordering; Notifications contains reminder
timing and the local dismissal ledger.
Interaction groups machine-local Keyboard Shortcuts and Selection Actions.
Integrations groups Agents & Chat and Zotero because both are connection or
external-tool configuration; each child retains its own owner and scope.
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
Results name the setting and category; choosing a
result reveals its control, page or sheet without changing its value.
No matches preserves the query; clearing search restores the browsing context.

### Page composition

The selected pane makes its scope and any necessary target identity legible
through its category, group and adjacent state labels before or beside the
editable control. Group headings name related tasks or preferences, with common
choices before optional detail. Reuse the window's category title instead of
adding a duplicate large heading. Short panes remain compact; longer forms and
collections scroll without losing access to their actions.

Forms share one control axis and a trailing-aligned label column.
Related controls form compact groups with clear
separation between groups; supporting copy stays beside its owner. Native
collections hold field/shortcut rows and adjacent actions. Shared relationships
use consistent alignment and spacing without forcing every pane into identical
height or containers. Status and validation fit beside the affected control
without replacing the active form or needlessly shifting its controls.

Ordinary groups use headings and measured whitespace rather than repeated
horizontal rules. Separators remain for a native collection or menu, or for a
genuine structural boundary such as a persistent action area. A peer preference
is not hidden in a nested disclosure merely to shorten a pane. When detail has a
different scope or workflow, use a child pane or native sheet; reserve a
disclosure for one genuinely secondary detail group that is not needed to
understand current state or repair.

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
| Behavioral preference | Describe the enabled behavior. | Use System Appearance / 跟随系统外观 |
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
preserves subordinate choices for reuse. Low-frequency detail may live behind
one clearly labelled Advanced Options action that opens a native child sheet; it
must not hide current failures or required repair. Default, Automatic and Follow
System identify their actual source; show the effective value when needed to
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

### Feature ownership

[Document Appearance §18.4](07-document-and-research-interface.md#184-document-modes-context-and-metadata)
owns appearance controls, configuration-file editing and restoration; Settings
does not create a second appearance owner or duplicate its controls. One
Appearance pane owns the Profile, Reading, Typography, Text Styles, Heading
Hierarchy, Configuration File and Advanced CSS groups against the same draft.
Text Styles uses an aligned Body/Headings matrix, while Heading Hierarchy shows
an aligned H1–H6 summary matrix. Detailed per-level spacing stays in one
explicit native child sheet, revealed on demand; it is not a second appearance
owner. Letter spacing, word spacing, hyphenation, kerning and ligatures are
intentionally omitted from the structured profile and native form; Advanced CSS
is their explicit configuration surface for ordinary document content. Its
child sheet exposes **Open CSS Folder**, **Reload**, import, enablement, order,
and per-snippet recovery actions. Direct `.css` files in the managed folder are
discovered and watched; invalid or missing files remain visible with errors.
The public Callout selectors `.callout`, `.callout-title`, `.callout-body`,
`.callout-content`, and `.callout-<role>` are supported there and projected to
Review/Edit without exposing internal selectors. These matrices collapse before
the available width or text size makes the form cramped. CSS remains an
explicit action to the configuration surface and file, and profile saving does
not reset CSS snippets. [Metadata Appendix A](11-metadata.md)
owns definitions and profiles; [Agent Chat §8.7](12-agent-chat.md) owns Selection
Actions and runtime configuration. Agents & Chat keeps connection state and
primary connect or sign-in actions in the main pane; custom connection paths,
runtime Skills and Tools, and External Agent Hosts open in explicit native
child sheets because they are distinct or low-frequency workflows. [Agent Collaboration §8](03-agent-collaboration-and-workflows.md)
and [Zotero §15](05-integrations-onboarding-and-boundaries.md) own integration
behavior. [Chat capability presentation](06-interface-shell-and-library.md#chat-capability-presentation)
owns the Agent pane's feature-specific controls. [Triptych §§3–4](01-foundation-and-triptych.md)
and [Attention §13](04-connect-search-and-recovery.md) own their respective
workflow meanings. Their save, confirmation and source-preservation rules remain
binding; this chapter does not grant new configuration or mutation capabilities.

Keyboard Shortcuts is machine-local and limited to frequent Scholium-specific
menu commands. It requires Command, rejects conflicts and reserved shortcuts,
and supports clear and restore. Standard macOS commands remain outside
remapping.
