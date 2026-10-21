import {EditorSelection, EditorState, RangeSet, StateEffect, StateField, Transaction, type Extension} from "@codemirror/state";
import {history, historyField, isolateHistory, redo, redoDepth, undo, undoDepth} from "@codemirror/commands";
import {ensureSyntaxTree, syntaxTree} from "@codemirror/language";
import {EditorView, type DecorationSet} from "@codemirror/view";
import {DOMParser, parseHTML} from "linkedom";
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest";
import {createMarkdownDocumentState} from "../bootstrap";
import {captureExactHistory, exactSourceHistory, exactSourceState, restoreExactHistory, setExactSource} from "../exact-source-history";
import {createImageProjection} from "../image-presentation";
import {scholiumNoteLanguage} from "../language";
import {createLiveDisplayMathProjection} from "../live-display-math-projection";
import {createLiveFootnoteProjection} from "../live-footnote-projection";
import {createLiveInlineWidgets} from "../live-inline-widgets";
import {createLiveMermaidProjection} from "../live-mermaid-projection";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveSelectionController} from "../live-selection";
import {createLiveSemanticLayout} from "../live-semantic-layout";
import {createLiveStructuredBlockProjections} from "../live-structured-block-projections";
import {createProjectedWidgetRegistry} from "../projected-widget-registry";
import type {MarkdownEditingDialect} from "../protocol";
import {normalizedDocumentText} from "../state";
import {citationHistory, citationState, setCitationData, setCitationSnapshot, type ZoteroCitationSnapshot} from "../zotero-citation-state";

const dialect: MarkdownEditingDialect = {
  version: 6,
  callouts: [{identifier: "state", label: "Statement", meaning: "Statement"}],
  linkAnnotation: {openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\",
    allowsMultiline: true, allowsNesting: false},
  footnotes: {namedReferenceOpening: "[^", namedReferenceClosing: "]", definitionSeparator: ":",
    inlineOpening: "^[", continuationIndentSpaces: 2, allowsTabContinuation: true,
    caseSensitiveIdentifiers: true, ordinalByFirstReference: true},
  mathematics: {inlineDelimiter: "$", displayDelimiter: "$$", singleDollarInline: true},
};

const source = "\uFEFFLead 中文 🦉 e\u0301.\r\n\r\n"
  + "Plain paragraph with exact source.\r\n\r\n".repeat(400)
  + ["# Later heading", "", "| Column | Value |", "| --- | --- |", "| A | B |", "",
    "> [!state]+ Statement", "> Callout body.", "", "$$", "x^2", "$$", "",
    "A footnote[^one].", "", "![figure](Attachments/figure)", "",
    "```mermaid", "flowchart LR", "A --> B", "```", "",
    "[^one]: Definition.", "", "[Author](cite:cite_a)", "", "Tail."].join("\r\n");
const citationSnapshot: ZoteroCitationSnapshot = {
  noteID: "11111111-1111-1111-1111-111111111111",
  vaultID: "22222222-2222-2222-2222-222222222222",
  status: "available",
  sourceFingerprint: {sha256: "a".repeat(64), byteCount: new TextEncoder().encode(source).byteLength},
  data: {schemaVersion: 1, fields: [{id: "cite_a", kind: "citation",
    code: "ITEM CSL_CITATION synthetic", text: "Author"}],
  acceptedFields: [{id: "cite_a", code: "ITEM CSL_CITATION synthetic"}]},
};

// These are the direct, geometry-owning factories used by the live editor.
// No DOM or asynchronous renderer is mounted by this state-level test.
const groups = ["line", "spacing", "table", "math", "callout", "footnote", "image", "mermaid"] as const;
const indexOwnedGroups = ["line", "spacing", "table", "math", "callout", "footnote", "mermaid"] as const;
function harness() {
  const selection = createLiveSelectionController({
    handleModifiedLink: () => false, handleProjectedPointerStart: () => false,
  });
  const projections = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
  const widgets = createProjectedWidgetRegistry();
  const refresh = StateEffect.define<null>();
  const theme = StateEffect.define<number>();
  const inline = createLiveInlineWidgets({requestMathRuntime: () => {}, didToggleTask: () => {}});
  const layout = createLiveSemanticLayout({selection, projections, editingDialect: () => dialect});
  const blocks = createLiveStructuredBlockProjections({selection, projections, widgets,
    editingDialect: () => dialect, reuseCounts: {table: 0}});
  const math = createLiveDisplayMathProjection({selection, projections, widget: inline.math,
    shouldRefreshRuntime: transaction => transaction.effects.some(effect => effect.is(refresh))});
  const footnotes = createLiveFootnoteProjection({selection, projections, widgets, reuseCounts: {footnote: 0}});
  const activateLink = vi.fn();
  const images = createImageProjection({selection, projections, bodyIsActive: () => true,
    shouldRefresh: transaction => transaction.effects.some(effect => effect.is(refresh)), activateLink});
  images.setResources({"Attachments/figure": "data:image/png;base64,iVBORw0KGgo="});
  const mermaid = createLiveMermaidProjection({selection, projections, widgets,
    ensureRuntime: async () => null, currentThemeRevision: () => 0, refreshThemeEffect: theme});
  const extensions = (beforeIndex: Extension[] = []): Extension[] => [
    history(), exactSourceHistory, citationHistory, scholiumNoteLanguage,
    ...beforeIndex, selection.extension, projections.extension,
    layout.extension, blocks.tableExtension, math.extension, blocks.calloutExtension,
    footnotes.extension, images.extension, mermaid.extension,
    EditorState.allowMultipleSelections.of(true), EditorState.lineSeparator.of("\n"),
  ];
  return {projections, images, activateLink, refresh, theme, extensions};
}

function directSets(state: EditorState) {
  const sets = state.facet(EditorView.decorations)
    .filter((value): value is DecorationSet => typeof value !== "function");
  expect(sets).toHaveLength(groups.length);
  return Object.fromEntries(groups.map((group, index) => [group, sets[index]])) as Record<typeof groups[number], DecorationSet>;
}

function createState(h: ReturnType<typeof harness>, exactSource: string,
  mode: "normal" | "delayed" | "partial" = "normal", serialized?: string) {
  let now = 0;
  const deadline = mode === "normal" ? undefined
    : vi.spyOn(Date, "now").mockImplementation(() => now += 100);
  let initialPublishedTree: ReturnType<typeof syntaxTree> | undefined;
  const releaseBudget = StateField.define({
    create(state) {
      // Exhaust only LanguageState's initial public parse budget. The real
      // shared index can then complete that same parser context, before its
      // tree has been published in a transaction.
      initialPublishedTree = syntaxTree(state);
      // Completing this fixture is a prerequisite, not a wall-clock claim.
      // Keep its subsequent parse slice deterministic even when other workers
      // consume the real 50 ms budget. The partial fixture keeps its expired clock.
      deadline?.mockImplementation(() => 0);
      return null;
    },
    update: value => value,
  });
  try {
    const extensions = h.extensions(mode === "delayed" ? [releaseBudget] : []);
    const state = serialized ? restoreExactHistory(serialized, exactSource, extensions)
      : createMarkdownDocumentState(exactSource, extensions, {citationSnapshot});
    return {state, initialPublishedTree: initialPublishedTree ?? syntaxTree(state)};
  } finally {
    deadline?.mockRestore();
  }
}

function step(state: EditorState, command: typeof undo) {
  let next = state;
  expect(command({state, dispatch: transaction => {next = transaction.state;}})).toBe(true);
  return next;
}

beforeEach(() => {
  const {document, window} = parseHTML("<html><body></body></html>");
  vi.stubGlobal("DOMParser", DOMParser);
  vi.stubGlobal("document", document);
  vi.stubGlobal("window", window);
});
afterEach(() => {vi.restoreAllMocks(); vi.unstubAllGlobals();});

describe("shared semantic index publication", () => {
  it("reuses index-owned direct decorations when an already analyzed tree is published, preserving exact history", () => {
    const baseExtensions = [history(), exactSourceHistory, citationHistory,
      EditorState.allowMultipleSelections.of(true), EditorState.lineSeparator.of("\n")];
    let original = createMarkdownDocumentState(source, baseExtensions, {citationSnapshot});
    original = original.update({changes: {from: 5, insert: " first"},
      annotations: isolateHistory.of("full")}).state;
    const second = original.update({changes: {from: original.doc.length, insert: " second"},
      annotations: isolateHistory.of("full")}).state;
    original = step(second, undo);
    original = original.update({selection: EditorSelection.create([
      EditorSelection.cursor(2), EditorSelection.cursor(100),
    ], 1), annotations: Transaction.addToHistory.of(false)}).state;
    const serialized = captureExactHistory(original);
    expect(serialized).toBeDefined();
    const h = harness();
    const {state, initialPublishedTree} = createState(h, original.field(exactSourceState).text, "delayed", serialized!);
    const index = h.projections.index(state);
    const sets = directSets(state);
    for (const group of groups) expect(sets[group].size, group).toBeGreaterThan(0);
    expect(index.syntaxComplete).toBe(true);
    expect(initialPublishedTree.length).toBeLessThan(state.doc.length);
    expect(syntaxTree(state)).toBe(initialPublishedTree);
    const before = state.toJSON({history: historyField, citations: citationState});
    expect(undoDepth(state)).toBe(1);
    expect(redoDepth(state)).toBe(1);

    const publication = state.update({annotations: Transaction.addToHistory.of(false)});
    const published = publication.state;
    expect(publication.docChanged).toBe(false);
    expect(publication.effects).toHaveLength(0);
    expect(syntaxTree(published)).not.toBe(initialPublishedTree);
    expect(h.projections.index(published)).toBe(index);
    const afterSets = directSets(published);
    for (const group of indexOwnedGroups) expect(afterSets[group], group).toBe(sets[group]);
    // Image alt text and outer-link activation also read the published tree.
    expect(afterSets.image).not.toBe(sets.image);
    expect(published.field(exactSourceState)).toBe(state.field(exactSourceState));
    expect(published.selection.eq(original.selection)).toBe(true);
    expect(published.toJSON({history: historyField, citations: citationState})).toEqual(before);
    expect(step(published, undo).field(exactSourceState).text).toBe(source);
    expect(step(published, redo).field(exactSourceState).text).toBe(second.field(exactSourceState).text);
  });

  it.each([
    ["table", "| Column"], ["math", "x^2"], ["callout", "Callout body"],
    ["footnote", "[^one]"], ["image", "![figure]"], ["mermaid", "flowchart LR"],
  ] as const)("still updates %s activation when selection and tree publication arrive together", (group, target) => {
    const h = harness();
    const {state, initialPublishedTree} = createState(h, source, "delayed");
    const index = h.projections.index(state);
    const sets = directSets(state);
    const anchor = state.doc.toString().indexOf(target) + 2;
    expect(anchor).toBeGreaterThan(1);
    const published = state.update({selection: {anchor}, annotations: Transaction.addToHistory.of(false)}).state;
    expect(syntaxTree(published)).not.toBe(initialPublishedTree);
    expect(h.projections.index(published)).toBe(index);
    expect(published.selection.main.head).toBe(anchor);
    expect(directSets(published)[group]).not.toBe(sets[group]);
    // Share the factories: widget constructors are part of CodeMirror equality.
    const fresh = createState(h, source).state.update({selection: {anchor}}).state;
    expect(RangeSet.eq([directSets(published)[group]], [directSets(fresh)[group]])).toBe(true);
    expect(published.field(exactSourceState).text).toBe(source);
    expect(undoDepth(published)).toBe(0);
  });

  it("rebuilds all direct projections when a partial semantic index becomes complete", () => {
    const h = harness();
    const {state} = createState(h, source, "partial");
    const partial = h.projections.index(state);
    const sets = directSets(state);
    expect(partial.syntaxComplete).toBe(false);
    expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
    const published = state.update({}).state;
    expect(h.projections.index(published)).not.toBe(partial);
    expect(h.projections.index(published).syntaxComplete).toBe(true);
    const afterSets = directSets(published);
    for (const group of groups) {
      expect(afterSets[group], group).not.toBe(sets[group]);
      expect(afterSets[group].size, group).toBeGreaterThan(0);
    }
    expect(published.field(exactSourceState).text).toBe(source);
    expect(published.selection.eq(state.selection)).toBe(true);
    expect(undoDepth(published)).toBe(0);
  });

  it.each(["exact-source", "citation-data", "citation-baseline"] as const)(
    "refreshes direct projections for %s changes without a normalized text or tree change", change => {
      const h = harness();
      let {state} = createState(h, source);
      expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
      state = state.update({}).state;
      const index = h.projections.index(state), tree = syntaxTree(state), sets = directSets(state);
      const replacement = source.replaceAll("\r\n", "\n");
      const effect = change === "exact-source" ? setExactSource.of(replacement)
        : change === "citation-data" ? setCitationData.of({...citationSnapshot.data!, documentData: "draft companion"})
          : setCitationSnapshot.of({...citationSnapshot, status: "unresolved"});
      const transaction = state.update({effects: effect, annotations: Transaction.addToHistory.of(false)});
      const next = transaction.state;
      expect(transaction.docChanged).toBe(false);
      expect(syntaxTree(next)).toBe(tree);
      expect(h.projections.index(next)).not.toBe(index);
      const nextSets = directSets(next);
      for (const group of indexOwnedGroups) expect(nextSets[group], group).not.toBe(sets[group]);
      expect(nextSets.image).toBe(sets.image);
      expect(next.doc.toString()).toBe(normalizedDocumentText(source));
      expect(next.field(exactSourceState).text).toBe(change === "exact-source" ? replacement : source);
      expect(next.selection.eq(state.selection)).toBe(true);
      expect(undoDepth(next)).toBe(0);
    },
  );

  it("finishes parsed image alt text and linked-image activation when that same analyzed tree is published", () => {
    const h = harness();
    const linkedSource = "\uFEFFLead.\r\n\r\n" + "Plain paragraph.\r\n\r\n".repeat(400)
      + "[![A \\*literal\\* &amp; figure](Attachments/figure)](https://example.invalid/linked)\r\n\r\nTail.";
    const {state, initialPublishedTree} = createState(h, linkedSource, "delayed");
    const index = h.projections.index(state), sets = directSets(state);
    const published = state.update({}).state;
    expect(syntaxTree(published)).not.toBe(initialPublishedTree);
    expect(h.projections.index(published)).toBe(index);
    const imageSet = directSets(published).image;
    expect(imageSet).not.toBe(sets.image);
    const widget = imageSet.iter().value?.spec.widget;
    expect(widget).toBeDefined();
    const view = {state: published, compositionStarted: false, requestMeasure: vi.fn()} as unknown as EditorView;
    const dom = widget!.toDOM(view);
    const image = dom.querySelector("img")!;
    expect(image.getAttribute("alt")).toBe("A *literal* & figure");
    document.body.append(dom);
    for (const type of ["mousedown", "click"]) {
      const event = document.createEvent("Event");
      event.initEvent(type, true, true);
      for (const [key, value] of Object.entries({button: 0, metaKey: true,
        ctrlKey: false, shiftKey: false, altKey: false, clientX: 10, clientY: 10})) {
        Object.defineProperty(event, key, {value});
      }
      image.dispatchEvent(event);
    }
    expect(h.activateLink).toHaveBeenCalledExactlyOnceWith("https://example.invalid/linked", false);
    expect(published.field(exactSourceState).text).toBe(linkedSource);
    expect(published.selection.eq(state.selection)).toBe(true);
    expect(undoDepth(published)).toBe(0);
  });

  it("keeps explicit runtime, resource and theme refreshes when semantic identity is unchanged", () => {
    const h = harness();
    let {state} = createState(h, source);
    expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
    state = state.update({}).state;
    const index = h.projections.index(state), sets = directSets(state);
    h.images.setResources({"Attachments/figure": "data:image/png;base64,iVBORw0KGgo=changed"});
    const next = state.update({effects: [h.refresh.of(null), h.theme.of(1)],
      annotations: Transaction.addToHistory.of(false)}).state;
    expect(h.projections.index(next)).toBe(index);
    const nextSets = directSets(next);
    for (const group of ["math", "image", "mermaid"] as const) expect(nextSets[group], group).not.toBe(sets[group]);
    for (const group of ["line", "spacing", "table", "callout", "footnote"] as const) expect(nextSets[group], group).toBe(sets[group]);
    expect(next.field(exactSourceState).text).toBe(source);
    expect(next.selection.eq(state.selection)).toBe(true);
    expect(undoDepth(next)).toBe(0);
  });
});
