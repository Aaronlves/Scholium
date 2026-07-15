# Native Markdown fallback checklist

Use this checklist only for `NativeMarkdownReadView`, isolated fallback behavior, or an explicitly authorized native-editor reactivation. The active editor is CodeMirror 6 and the active Read surface is `SafeMarkdownReadWebView`.

## Source and projection

- Keep one complete source string; never serialize attributed text back to Markdown.
- Reapply attributes without changing `textStorage.string`.
- Collapse frontmatter or inactive syntax only as presentation, without deleting backing characters.
- Prevent programmatic source or attribute changes from echoing as user edits.

## Range safety

- Convert `String.Index` ranges to `NSRange` in the same source instance.
- Keep AppKit, regex, selection, and text-storage offsets in UTF-16 units.
- Cover emoji, flags, skin-tone modifiers, composed accents, CJK, RTL text, and attachment characters.
- Avoid applying attributes during an outstanding text-storage edit transaction.

## Interaction and saving

- Preserve insertion point, selection, scroll position, first responder, marked text, and undo grouping.
- Preserve standard find, spelling, substitutions, copy/paste, drag selection, and keyboard commands.
- Cancel delayed work on vault, path, fingerprint, or session changes.
- Route any native edit through the same full-source reconciliation and revision-checked repository save path.
- On conflict or failure, keep the source and selection recoverable.

## Accessibility

- Expose useful text, selection, headings, and links to VoiceOver.
- Ensure collapsed syntax does not create misleading blank runs or trap navigation.
- Verify focus order, increased contrast, reduced transparency, keyboard-only use, and enlarged text.

## Reactivation gate

Before making the native editor active, demonstrate exact-source, autosave, conflict, selection, IME, accessibility, and performance parity with the CodeMirror path. Update reachable construction call sites, tests, README, and this skill in the same change.
