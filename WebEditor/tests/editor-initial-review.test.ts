import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {EDITOR_PROTOCOL_VERSION, type EditorCommandResult, type EditorPresentationConfiguration,
  type EditorRequest, type MarkdownEditingDialect} from "../protocol";
import {installConstructableStylesheet} from "./stylesheet-fixture";
import type {NativeFloatingEvent} from "../native-floating";

const dialect: MarkdownEditingDialect = {
  version: 6, callouts: [{identifier: "state", label: "Statement", meaning: "Claim"}],
  linkAnnotation: {openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\", allowsMultiline: true, allowsNesting: false},
  footnotes: {namedReferenceOpening: "[^", namedReferenceClosing: "]", definitionSeparator: ":", inlineOpening: "^[",
    continuationIndentSpaces: 2, allowsTabContinuation: true, caseSensitiveIdentifiers: true, ordinalByFirstReference: true},
  mathematics: {inlineDelimiter: "$", displayDelimiter: "$$", singleDollarInline: true},
};
interface RuntimeWindow extends Window {
  scholiumEditor?: {dispatch(request: unknown): Promise<EditorCommandResult>; prepareForReuse(): boolean};
  scholiumReadReady?: Promise<void>;
  scholiumNativeFloatingEvent?: (id: number, action: string, index: number) => boolean;
}

afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.useRealTimers(); });

async function runtime() {
  vi.resetModules();
  vi.useFakeTimers();
  const {document, window} = parseHTML('<html><head><style id="scholium-presentation-css"></style><style id="scholium-user-css"></style></head><body><div id="editor"></div></body></html>');
  vi.stubGlobal("document", document);
  vi.stubGlobal("window", window);
  vi.stubGlobal("Window", class {
    static [Symbol.hasInstance](value: unknown) { return value === window; }
  });
  for (const name of ["MutationObserver", "HTMLElement", "Element", "Node", "HTMLImageElement"] as const) vi.stubGlobal(name, window[name]);
  vi.stubGlobal("requestAnimationFrame", () => 1);
  vi.stubGlobal("cancelAnimationFrame", () => {});
  vi.stubGlobal("matchMedia", () => ({matches: false, addEventListener() {}, removeEventListener() {}}));
  vi.stubGlobal("getComputedStyle", () => ({display: "block", visibility: "visible", direction: "ltr", getPropertyValue: () => ""}));
  vi.stubGlobal("ResizeObserver", class { observe() {} unobserve() {} disconnect() {} });
  vi.stubGlobal("CSS", {escape: (value: string) => value});
  Object.defineProperty(document, "getSelection", {value: () => null});
  Object.defineProperty(document, "hasFocus", {value: () => false});
  Object.defineProperty(document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
  const floating: NativeFloatingEvent[] = [];
  Object.defineProperty(window, "webkit", {configurable: true, value: {messageHandlers: {scholium: {
    postMessage(message: {type: string; event?: NativeFloatingEvent}) {
      if (message.type === "floatingSurface" && message.event) floating.push(message.event);
    },
  }}}});
  window.getSelection = () => null;
  installConstructableStylesheet(document);
  await import("../editor");
  const api = (window as unknown as RuntimeWindow).scholiumEditor!;
  const {EditorView} = await import("@codemirror/view");
  const view = EditorView.findFromDOM(document.querySelector(".cm-editor")!)!;
  view.scrollDOM.scrollTo = vi.fn();
  return {document, window: window as unknown as RuntimeWindow, api, view, floating};
}

function presentation(documentID: string, generation: number): EditorPresentationConfiguration {
  return {documentTitle: "Image note", presentationCSS: "", userCSS: "", linkPreviews: [], linkPreviewGeneration: generation,
    imageResources: {"a.png": "data:image/png;base64,AAAA"}, imageResourceGeneration: generation,
    writingContinuationEnabled: false, writingContinuationContextKey: "", writingIndexContextKey: "",
    reviewProjection: {documentID, sourceFingerprint: "fingerprint", css: "",
      htmlBody: '<main id="scholium-document"><p>Body</p><img class="scholium-embedded-image" data-scholium-image-resource="a.png"></main><aside id="scholium-preview-popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside>',
      configuration: {version: 8, documentID, fingerprint: "fingerprint", loadGeneration: 0, selectionEnabled: false,
        imagePreviewsEnabled: false, testingEnabled: false, presentationCSS: "", userCSS: "",
        localization: {languageTag: "en", strings: {}}, linkPreviews: []}}};
}

function request(documentID: string, operation: EditorRequest["operation"], knownGeneration = 0): EditorRequest {
  return {protocolVersion: EDITOR_PROTOCOL_VERSION, requestID: crypto.randomUUID(), expiresAt: Date.now() + 2000,
    sessionID: "session", documentID, startingFingerprint: "fingerprint", knownGeneration, operation};
}

function substituteAnchorGeometry(f: Awaited<ReturnType<typeof runtime>>) {
  vi.spyOn(f.view, "coordsAtPos").mockReturnValue({left: 10, right: 20, top: 40, bottom: 60});
  // Linkedom has no text layout; source/state, mode installation and bridge
  // ownership remain real, while native anchor geometry is substituted.
  const rect = {left: 10, right: 20, top: 40, bottom: 60, width: 10, height: 20} as DOMRect;
  f.document.createRange = (() => ({setStart() {}, setEnd() {}, collapse() {}, selectNodeContents() {},
    getBoundingClientRect: () => rect, getClientRects: () => [rect]})) as unknown as typeof document.createRange;
}

describe("Review initialization presentation admission", () => {
  it.each([{catalog: 0, recovery: 0}, {catalog: 1, recovery: 0}, {catalog: 5, recovery: 5},
    {catalog: 0, recovery: 5}, {catalog: 4, recovery: 5}, {catalog: 6, recovery: 5}])(
    "admits only the initial source generation through the actual editor bridge ($catalog catalog / $recovery recovery)", async ({catalog, recovery}) => {
    const f = await runtime();
    try {
      const value = presentation("fresh-document", catalog);
      const source = "Body\n\n![](a.png)\n";
      const result = await f.api.dispatch(request("fresh-document", {type: "initialize", mode: "review", text: source, dialect, presentation: value,
        ...(recovery ? {recovery: {documentID: "fresh-document", fingerprint: "fingerprint", generation: recovery,
          source, ranges: [{anchor: 0, head: 0}], undoHistoryPreserved: false, hasHistory: false, dirty: false}} : {})}));
      expect(result.accepted, result.error).toBe(true);
      expect(result.resultingGeneration).toBe(recovery);
      await f.window.scholiumReadReady;
      const image = f.document.querySelector<HTMLImageElement>("main#scholium-document img")!;
      expect(image).not.toBeNull();
      expect(image.getAttribute("src")).toBe(catalog === recovery ? value.imageResources["a.png"] : null);
      // A subsequent current-generation catalog remains admitted in place.
      const updated = presentation("fresh-document", recovery);
      updated.imageResources = {"a.png": "data:image/png;base64,AQID"};
      const refreshed = await f.api.dispatch(request("fresh-document", {type: "setPresentation", value: updated}, recovery));
      expect(refreshed.accepted, refreshed.error).toBe(true);
      expect(f.document.querySelector("main#scholium-document img")).toBe(image);
      expect(image.getAttribute("src")).toBe(updated.imageResources["a.png"]);
    } finally { f.view.destroy(); }
  });
});

describe("editor mode selection lifecycle", () => {
  it.each([
    {from: "livePreview", to: "source"},
    {from: "source", to: "livePreview"},
    {from: "livePreview", to: "review"},
    {from: "source", to: "review"},
  ] as const)("revokes the old $from selection surface before entering $to while preserving source and history", async ({from, to}) => {
    const f = await runtime();
    try {
      substituteAnchorGeometry(f);
      const {undoDepth} = await import("@codemirror/commands");
      const {exactSourceState} = await import("../exact-source-history");
      const source = "Body\r\n";
      const value = presentation("selection-note", 0);
      value.imageResources = {};
      value.reviewProjection!.htmlBody = '<main id="scholium-document"><p>Body</p></main><aside id="scholium-preview-popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside>';
      const initialized = await f.api.dispatch(request("selection-note", {type: "initialize", mode: from,
        text: source, initialSelection: {anchor: 0, head: 4}, dialect, presentation: value}));
      expect(initialized.accepted, initialized.error).toBe(true);
      const selection = f.view.state.selection;
      const history = undoDepth(f.view.state);
      const shown = await f.api.dispatch(request("selection-note", {type: "showSelectionActions"}));
      expect(shown.selectionSurfaceID).toBeGreaterThan(0);
      const id = shown.selectionSurfaceID!;
      expect(f.window.scholiumNativeFloatingEvent?.(id, "choose", 0)).toBe(true);
      const switched = await f.api.dispatch(request("selection-note", {type: "setMode", mode: to}));
      expect(switched.accepted, switched.error).toBe(true);
      expect(f.floating).toContainEqual({type: "dismissSurface", kind: "selection", id});
      expect(f.window.scholiumNativeFloatingEvent?.(id, "choose", 0)).toBe(false);
      expect(f.view.state.selection.eq(selection)).toBe(true);
      expect(f.view.state.field(exactSourceState).text).toBe(source);
      expect(undoDepth(f.view.state)).toBe(history);
      if (to !== "review") {
        const reopened = await f.api.dispatch(request("selection-note", {type: "showSelectionActions"}));
        expect(reopened.selectionSurfaceID).toBeGreaterThan(id);
        expect(f.window.scholiumNativeFloatingEvent?.(reopened.selectionSurfaceID!, "choose", 0)).toBe(true);
        expect(f.window.scholiumNativeFloatingEvent?.(id, "choose", 0)).toBe(false);
      }
    } finally { f.view.destroy(); }
  });
});

describe("Edit preview catalog lifecycle", () => {
  it.each(["images", "peer"] as const)("revokes changed %s payloads, retains equal catalogs, and reopens the current target without changing source or Undo", async kind => {
    const f = await runtime();
    try {
      substituteAnchorGeometry(f);
      const {history, undo, undoDepth} = await import("@codemirror/commands");
      const {captureExactHistory, exactSourceHistory, exactSourceState} = await import("../exact-source-history");
      const {createMarkdownDocumentState} = await import("../bootstrap");
      const source = "[[Peer]]\r\n\r\n![](a.png)\r\n";
      let retained = createMarkdownDocumentState(source + "draft", [history(), exactSourceHistory]);
      retained = retained.update({changes: {from: retained.doc.length - 5, to: retained.doc.length},
        selection: {anchor: 2}, userEvent: "delete.forward"}).state;
      const value = presentation("preview-note", 0);
      const peerImage = "data:image/png;base64,AQID";
      const peer = {from: 0, to: 8, title: "Peer", isEmbedded: false,
        htmlBody: `<p>Snapshot A</p><img class="scholium-embedded-image" src="${peerImage}">`};
      value.linkPreviews = [peer];
      value.imageResources = {"a.png": "data:image/png;base64,AAAA", "b.png": "data:image/png;base64,AQID"};
      const initialized = await f.api.dispatch(request("preview-note", {type: "initialize", mode: "livePreview",
        text: source, dialect, presentation: value, recovery: {
          documentID: "preview-note", fingerprint: "fingerprint", generation: 0,
          source, ranges: [{anchor: 2, head: 2}], stateJSON: captureExactHistory(retained),
          undoHistoryPreserved: true, hasHistory: true, dirty: false,
        }}));
      expect(initialized.accepted, initialized.error).toBe(true);
      expect(initialized.recoveryHistoryPreserved).toBe(true);
      expect(undoDepth(f.view.state)).toBe(1);
      const selection = f.view.state.selection;
      expect((await f.api.dispatch(request("preview-note", {type: "showPreview"}))).accepted).toBe(true);
      const first = f.floating.at(-1)!;
      if (first.type !== "previewSurface") throw new Error("Missing initial preview");
      expect(first.surface.html).toContain("Snapshot A");
      expect(first.surface.html).toContain(peerImage);
      const beforeEqual = f.floating.length;
      const equivalent = {...value,
        // Admission normalizes field order and authored title whitespace.
        linkPreviews: [{htmlBody: peer.htmlBody, title: " Peer ", to: 8, from: 0, isEmbedded: false}],
        imageResources: {"b.png": value.imageResources["b.png"], "a.png": value.imageResources["a.png"]},
      };
      expect((await f.api.dispatch(request("preview-note", {type: "setPresentation", value: equivalent}))).accepted).toBe(true);
      expect(f.floating).toHaveLength(beforeEqual);
      const changed = kind === "images"
        ? {...value, imageResources: {...value.imageResources, "a.png": "data:image/png;base64,BAUG"}}
        : {...value, linkPreviews: [{...peer, htmlBody: '<p>Snapshot B</p><img class="scholium-embedded-image" src="data:image/png;base64,BAUG">'}]};
      expect((await f.api.dispatch(request("preview-note", {type: "setPresentation", value: changed}))).accepted).toBe(true);
      expect(f.floating).toContainEqual({type: "dismissSurface", kind: "preview", id: first.surface.id});
      expect(f.window.scholiumNativeFloatingEvent?.(first.surface.id, "enter", -1)).toBe(false);
      expect((await f.api.dispatch(request("preview-note", {type: "showPreview"}))).accepted).toBe(true);
      const reopened = f.floating.at(-1)!;
      if (reopened.type !== "previewSurface") throw new Error("Missing refreshed preview");
      expect(reopened.surface.id).toBeGreaterThan(first.surface.id);
      expect(reopened.surface.html).toContain(kind === "peer" ? "Snapshot B" : "Snapshot A");
      expect(reopened.surface.html).toContain(kind === "peer" ? "data:image/png;base64,BAUG" : peerImage);
      // Peer bytes stay independent of the current note's identically named
      // image, while the note's own image projection takes the new catalog.
      expect(reopened.surface.imageResourceKeys).toEqual([]);
      expect(f.document.querySelector('.cm-live-image img')?.getAttribute("src")).toBe(changed.imageResources["a.png"]);
      expect(f.view.state.field(exactSourceState).text).toBe(source);
      expect(f.view.state.selection.eq(selection)).toBe(true);
      expect(undoDepth(f.view.state)).toBe(1);
      expect(undo(f.view)).toBe(true);
      expect(f.view.state.field(exactSourceState).text).toBe(source + "draft");
    } finally { f.view.destroy(); }
  });
});
