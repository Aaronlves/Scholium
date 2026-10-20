import {Compartment, EditorSelection, EditorState, StateEffect, Transaction} from "@codemirror/state";
import {history, redo, redoDepth, undo, undoDepth} from "@codemirror/commands";
import {EditorView, WidgetType, type DecorationSet} from "@codemirror/view";
import {ensureSyntaxTree} from "@codemirror/language";
import {afterEach, describe, expect, it, vi} from "vitest";
import {parseHTML} from "linkedom";
import {installConstructableStylesheet} from "./stylesheet-fixture";
import {ExactSourceMirror} from "../state";
import {createMarkdownDocumentState} from "../bootstrap";
import {createNativeFloatingPorts} from "../native-floating";
import {createCommittedReviewProjection} from "../committed-review-projection";
import {mapReviewAnchor, scopedReviewCSS, wrapReviewCSS, validCommittedReviewProjection, reviewProjectionMatches,
  type CommittedReviewProjection} from "../committed-review-contract";
import {createDeferredEditingInfrastructure} from "../deferred-editing-infrastructure";
import {captureExactHistory, exactSourceHistory, exactSourceState} from "../exact-source-history";
import {scholiumNoteLanguage} from "../language";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveSelectionController} from "../live-selection";
import {createLiveSemanticLayout} from "../live-semantic-layout";
import {createLiveStructuredBlockProjections} from "../live-structured-block-projections";
import {createLiveDisplayMathProjection} from "../live-display-math-projection";
import {createLiveFootnoteProjection} from "../live-footnote-projection";
import {createLiveMermaidProjection} from "../live-mermaid-projection";
import {createProjectedWidgetRegistry} from "../projected-widget-registry";
import {citationHistory} from "../zotero-citation-state";
import {EDITOR_PROTOCOL_VERSION, isEditorRequest} from "../protocol";

const projection: CommittedReviewProjection = {
  documentID: "editor-session-document", sourceFingerprint: "a".repeat(64), htmlBody: '<main id="scholium-document"><p>Body</p></main>', css: "body {margin:0}",
  configuration: {version: 8, documentID: "note.md", fingerprint: "a".repeat(64), loadGeneration: 2,
    selectionEnabled: true, imagePreviewsEnabled: true, testingEnabled: true, presentationCSS: "", userCSS: "",
    localization: {languageTag: "en", strings: {}}, linkPreviews: []},
};

function command(state: EditorState, action: typeof undo) {
  let next = state;
  const accepted = action({state, dispatch: transaction => { next = transaction.state; }});
  return {accepted, state: next};
}
function harness(source: string, reviewInitially = false, realLiveFields = false) {
  vi.stubGlobal("window", {});
  const mode = new Compartment();
  const review = createCommittedReviewProjection({nativeFloating: createNativeFloatingPorts(() => {}), projection: () => projection, mirror: () => new ExactSourceMirror(source), postMessage: () => {}});
  const samples: string[] = [];
  const index = createLiveProjectionIndexController({editingDialect: () => null,
    recordMetric: name => { samples.push(name); }});
  const infrastructure = createDeferredEditingInfrastructure([scholiumNoteLanguage, index.extension]);
  const selection = createLiveSelectionController({handleModifiedLink: () => false, handleProjectedPointerStart: () => false});
  const widgets = createProjectedWidgetRegistry();
  const layout = createLiveSemanticLayout({projections: index, selection, editingDialect: () => null});
  const blocks = createLiveStructuredBlockProjections({selection, projections: index, widgets,
    editingDialect: () => null, reuseCounts: {table: 0}});
  const footnotes = createLiveFootnoteProjection({selection, projections: index, widgets, reuseCounts: {footnote: 0}});
  const math = createLiveDisplayMathProjection({selection, projections: index,
    widget: () => new class extends WidgetType { toDOM(): HTMLElement { throw new Error("State-only fixture"); } },
    shouldRefreshRuntime: () => false});
  const mermaid = createLiveMermaidProjection({selection, projections: index, widgets,
    ensureRuntime: async () => null, currentThemeRevision: () => 0, refreshThemeEffect: StateEffect.define<number>()});
  const live = realLiveFields ? [selection.extension, layout.extension, blocks.tableExtension,
    blocks.calloutExtension, footnotes.extension, math.extension, mermaid.extension] : [];
  const state = createMarkdownDocumentState(source, [history(), exactSourceHistory, citationHistory,
    EditorState.lineSeparator.of("\n"), mode.of(reviewInitially ? review.extension : live),
    infrastructure.forDocument(reviewInitially ? "review" : "livePreview")]);
  return {state, index, samples, review,
    changeMode(state: EditorState, target: "review" | "livePreview" | "source") {
      const activation = infrastructure.activationEffects(state, target);
      if (activation.length) state = state.update({effects: activation}).state;
      return state.update({effects: mode.reconfigure(target === "review" ? review.extension : target === "livePreview" ? live : []),
        annotations: Transaction.addToHistory.of(false)}).state;
    },
  };
}

afterEach(() => vi.unstubAllGlobals());

describe("committed Review inside the persistent CodeMirror state", () => {
  it("keeps exact Unicode/newlines, selection and both Undo branches through repeated modes", () => {
    const source = "\uFEFF# Title\r\n\r\nBody 中文😀 e\u0301\r\n";
    const h = harness(source);
    let state = h.state.update({changes: {from: 3, insert: " first"},
      selection: EditorSelection.single(8), userEvent: "input.type"}).state;
    state = state.update({changes: {from: state.doc.length, insert: "Second"},
      userEvent: "input.paste"}).state;
    state = command(state, undo).state;
    const exact = state.field(exactSourceState).text;
    const selection = state.selection;
    const beforeHistory = captureExactHistory(state);
    expect(undoDepth(state)).toBeGreaterThan(0);
    expect(redoDepth(state)).toBeGreaterThan(0);
    for (const mode of ["review", "source", "review", "livePreview", "review", "source"] as const) {
      state = h.changeMode(state, mode);
      expect(state.field(exactSourceState).text).toBe(exact);
      expect(state.selection.eq(selection)).toBe(true);
      expect(captureExactHistory(state)).toBe(beforeHistory);
    }
    const undone = command(state, undo);
    expect(undone.accepted).toBe(true);
    expect(undone.state.field(exactSourceState).text).toBe(source);
    const redone = command(state, redo);
    expect(redone.accepted).toBe(true);
    expect(redone.state.field(exactSourceState).text).toBe(exact + "Second");
  });

  it("refuses typing, unfiltered mutation and Undo/Redo while Review is active", () => {
    const h = harness("Before\r\n");
    let state = h.state.update({changes: {from: 6, insert: " after"}}).state;
    state = h.changeMode(state, "review");
    const source = state.field(exactSourceState).text;
    const history = captureExactHistory(state);
    expect(state.readOnly).toBe(true);
    expect(state.facet(EditorView.editable)).toBe(false);
    const attempted = state.update({changes: {from: 0, insert: "lost"}, selection: {anchor: 4}}).state;
    expect(attempted.field(exactSourceState).text).toBe(source);
    expect(attempted.selection.eq(state.selection)).toBe(true);
    expect(captureExactHistory(attempted)).toBe(history);
    expect(command(state, undo).accepted).toBe(false);
    expect(command(state, redo).accepted).toBe(false);
    expect(() => state.update({changes: {from: 0, insert: "lost"}, filter: false}).state).toThrow("Review cannot mutate");
    state = h.changeMode(state, "livePreview");
    expect(command(state, undo).state.field(exactSourceState).text).toBe("Before\r\n");
  });

  it("does no editing index construction for cold Review, initializes once and retains it across mode changes", () => {
    const h = harness("# A\n\n" + "Body with [link](target).\n\n".repeat(600), true);
    expect(h.samples).toEqual([]);
    expect(() => h.index.index(h.state)).toThrow();
    let state = h.changeMode(h.state, "livePreview");
    expect(h.samples).toContain("projection-index");
    ensureSyntaxTree(state, state.doc.length, 1000);
    // Publish the completed parser before checking identity reuse.
    const index = h.index.index(state);
    const constructionCount = h.samples.filter(name => name === "projection-index").length;
    for (const mode of ["review", "source", "review", "livePreview"] as const) {
      state = h.changeMode(state, mode);
      expect(h.index.index(state)).toBe(index);
    }
    expect(h.samples.filter(name => name === "projection-index").length).toBe(constructionCount);
  });

  it("installs the real Live state fields after cold Review without losing source or history", () => {
    const source = "# Title\r\n\r\nBody[^one].\r\n\r\n> [!state] Claim\r\n> Quoted text.\r\n\r\n"
      + "| A | B |\r\n|---|---|\r\n| C | D |\r\n\r\n```mermaid\r\nflowchart LR\r\nA --> B\r\n```\r\n\r\n[^one]: Footnote.\r\n";
    const h = harness(source, true, true);
    const originalHistory = captureExactHistory(h.state);
    let state = h.changeMode(h.state, "livePreview");
    expect(state.readOnly).toBe(false);
    expect(state.facet(EditorView.editable)).toBe(true);
    expect(state.field(exactSourceState).text).toBe(source);
    expect(captureExactHistory(state)).toBe(originalHistory);
    expect(state.selection.eq(h.state.selection)).toBe(true);
    expect(state.facet(EditorView.decorations).length).toBeGreaterThan(5);
    state = state.update({changes: {from: state.doc.length, insert: "Tail"}, userEvent: "input.type"}).state;
    const typedHistory = captureExactHistory(state);
    for (const target of ["review", "livePreview", "source", "review", "livePreview"] as const) {
      state = h.changeMode(state, target);
      expect(captureExactHistory(state)).toBe(typedHistory);
    }
    expect(command(state, undo).state.field(exactSourceState).text).toBe(source);
  });

  it.each(["", "Body\n"])("uses one direct block widget over %j without owning source", source => {
    const h = harness(source, true);
    const decorations = h.state.facet(EditorView.decorations)
      .find(value => typeof value !== "function") as DecorationSet;
    const cursor = decorations.iter();
    expect(cursor.from).toBe(0);
    expect(cursor.to).toBe(h.state.doc.length);
    expect(cursor.value!.spec.widget.ignoreEvent(new Event("selectionchange"))).toBe(true);
    expect(cursor.value!.spec.block).toBe(true);
    expect(h.state.field(exactSourceState).text).toBe(source);
  });
});

describe("committed Review transport and style boundary", () => {
  it("binds native projection to the checked committed fingerprint and refuses dirty state", () => {
    expect(validCommittedReviewProjection(projection)).toBe(true);
    expect(reviewProjectionMatches(projection, "editor-session-document", projection.sourceFingerprint, false)).toBe(true);
    expect(reviewProjectionMatches(projection, "editor-session-document", "newer", false)).toBe(false);
    expect(reviewProjectionMatches(projection, "different-note-with-identical-source", projection.sourceFingerprint, false)).toBe(false);
    expect(reviewProjectionMatches(projection, "editor-session-document", projection.sourceFingerprint, true)).toBe(false);
    expect(validCommittedReviewProjection({...projection, configuration: {...projection.configuration, fingerprint: "other"}})).toBe(false);
    expect(validCommittedReviewProjection({...projection, configuration: {...projection.configuration, replyProjection: true}})).toBe(false);
    expect(validCommittedReviewProjection({...projection, htmlBody: "x".repeat(16_777_217)})).toBe(false);
  });

  it("admits Review mode and its bounded presentation without admitting old bridge versions", () => {
    const value = {documentTitle: "Note", presentationCSS: "", userCSS: "", linkPreviews: [],
      linkPreviewGeneration: 0, imageResources: {}, imageResourceGeneration: 0,
      writingContinuationEnabled: false, writingContinuationContextKey: "", writingIndexContextKey: "",
      reviewProjection: projection};
    const request = {protocolVersion: EDITOR_PROTOCOL_VERSION, requestID: "review", expiresAt: Date.now() + 8000,
      sessionID: "session", documentID: "document", startingFingerprint: projection.sourceFingerprint,
      knownGeneration: 0, operation: {type: "setPresentation", value}};
    expect(isEditorRequest(request)).toBe(true);
    expect(isEditorRequest({...request, protocolVersion: 54})).toBe(false);
    expect(isEditorRequest({...request, operation: {type: "setMode", mode: "review"}})).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "setPresentation", value: {...value,
      reviewProjection: {...projection, configuration: {...projection.configuration, fingerprint: "wrong"}}}}})).toBe(false);
  });

  it("round-trips exact Review anchors through the CodeMirror bridge with BOM, CRLF, non-BMP and decomposed text", () => {
    const source = "\uFEFF# Title\r\n\r\nBody 中文😀 e\u0301\r\nTail";
    const mirror = new ExactSourceMirror(source);
    const lower = source.indexOf("Body"), upper = source.indexOf("\r\nTail");
    const raw = {sourceUTF16Offset: source.indexOf("e\u0301"), blockUTF16LowerBound: lower,
      blockUTF16UpperBound: upper, relativeBlockPosition: 0.4, fallbackFraction: 0.7};
    const normalized = mapReviewAnchor(raw, mirror, "normalized")!;
    expect(normalized.sourceUTF16Offset).toBe(raw.sourceUTF16Offset - 2);
    expect(normalized.blockUTF16LowerBound).toBe(raw.blockUTF16LowerBound - 2);
    expect(mapReviewAnchor(normalized, mirror, "exact")).toEqual(raw);
    expect(mirror.normalizedOffset(0)).toBe(0); // BOM remains authoritative source.
    expect(mapReviewAnchor({...raw, sourceUTF16Offset: source.indexOf("\r\n") + 1}, mirror, "normalized")).toBeNull();
  });

  it("inherits native root defaults and scopes only CSSOM selectors, including compact appearance rules", () => {
    const {document} = parseHTML("<html></html>");
    installConstructableStylesheet(document);
    const base = scopedReviewCSS('html, body {margin:0} :root {--ink:red} html.custom p {content:"body :root"} @media (x) {body > main {width:100%}}');
    expect(base).toContain(":scope, :scope {margin: 0;}");
    expect(base).toContain(":root {--ink: red;}");
    expect(base).toContain(':scope.custom p {content: "body :root";}');
    expect(base).toContain(":scope > main {width: 100%;}");
    const appearance = scopedReviewCSS(':root {--size: 20px} @media (max-width: 40rem) {:root {--inline: 12px} .scholium-document {padding-inline: var(--inline)}}', "local");
    expect(appearance).toContain(":scope {--size: 20px;}");
    expect(appearance).toContain(":scope {--inline: 12px;}");
    expect(appearance).toContain(".scholium-document {padding-inline: var(--inline);}");
    const user = '.scholium-document p::before {content: "body :root { html }"; font-family: "body";}';
    expect(wrapReviewCSS(user)).toBe(`@scope (.scholium-review-projection) { ${user} }`);
  });
});
