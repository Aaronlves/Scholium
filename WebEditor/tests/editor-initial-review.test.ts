import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {EDITOR_PROTOCOL_VERSION, type EditorCommandResult, type EditorPresentationConfiguration,
  type EditorRequest, type MarkdownEditingDialect} from "../protocol";
import {installConstructableStylesheet} from "./stylesheet-fixture";

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
}

afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.useRealTimers(); });

async function runtime() {
  vi.resetModules();
  vi.useFakeTimers();
  const {document, window} = parseHTML('<html><head><style id="scholium-presentation-css"></style><style id="scholium-user-css"></style></head><body><div id="editor"></div></body></html>');
  vi.stubGlobal("document", document);
  vi.stubGlobal("window", window);
  for (const name of ["MutationObserver", "HTMLElement", "Element", "Node", "HTMLImageElement"] as const) vi.stubGlobal(name, window[name]);
  vi.stubGlobal("requestAnimationFrame", () => 1);
  vi.stubGlobal("cancelAnimationFrame", () => {});
  vi.stubGlobal("matchMedia", () => ({matches: false, addEventListener() {}, removeEventListener() {}}));
  vi.stubGlobal("getComputedStyle", () => ({display: "block", visibility: "visible", direction: "ltr", getPropertyValue: () => ""}));
  vi.stubGlobal("CSS", {escape: (value: string) => value});
  Object.defineProperty(document, "getSelection", {value: () => null});
  Object.defineProperty(document, "hasFocus", {value: () => false});
  Object.defineProperty(document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
  window.getSelection = () => null;
  installConstructableStylesheet(document);
  await import("../editor");
  const api = (window as unknown as RuntimeWindow).scholiumEditor!;
  const {EditorView} = await import("@codemirror/view");
  const view = EditorView.findFromDOM(document.querySelector(".cm-editor")!)!;
  view.scrollDOM.scrollTo = vi.fn();
  return {document, window: window as unknown as RuntimeWindow, api, view};
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
