import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {EditorView} from "@codemirror/view";
import {describe, expect, it, vi} from "vitest";
import {parseHTML} from "linkedom";
import {createImageProjection, imageDestination, imagePresentation} from "../image-presentation";
import {validImageResources, MAX_IMAGE_BYTES} from "../image-resources";
import {scholiumNoteLanguage} from "../language";
import {semanticProjectionRanges} from "../semantic-projection";
import {EDITOR_PROTOCOL_VERSION, generationCanExecuteEditorRequest, isEditorRequest} from "../protocol";
import {compositionRequestPolicy} from "../composition";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveSelectionController} from "../live-selection";

const png = "data:image/png;base64,iVBORw0KGgo=";
describe("source-backed local image presentation", () => {
  function projectedState(source: string, resources: Readonly<Record<string, string>>) {
    const selection = createLiveSelectionController({
      handleModifiedLink: () => false,
      handleProjectedPointerStart: () => false,
    });
    const projections = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
    const images = createImageProjection({selection, projections, bodyIsActive: () => true, shouldRefresh: () => false});
    images.setResources(resources);
    return EditorState.create({doc: source, selection: {anchor: source.length},
      extensions: [scholiumNoteLanguage, selection.extension, projections.extension, images.extension]});
  }

  function imageReplacementRanges(state: EditorState) {
    const ranges: Array<{from: number; to: number; block: boolean}> = [];
    for (const decorations of state.facet(EditorView.decorations)) {
      if (typeof decorations === "function") continue;
      decorations.between(0, state.doc.length, (from, to, decoration) => {
        ranges.push({from, to, block: decoration.spec.block === true});
      });
    }
    return ranges;
  }

  it("gives the outer image its complete caption and reveals all nested source at its caret", () => {
    const image = "![fixture![](Attachments/figure)](Attachments/figure)";
    const source = `Before.\n\n${image}\n\nAfter.`;
    const from = source.indexOf(image);
    const state = projectedState(source, {"Attachments/figure": png});
    expect(imageReplacementRanges(state)).toEqual([{from, to: from + image.length, block: true}]);

    const revealed = state.update({selection: {anchor: from + 2}}).state;
    expect(imageReplacementRanges(revealed)).toEqual([]);
    expect(revealed.selection.main.head).toBe(from + 2);
    expect(revealed.doc.toString()).toBe(source);
  });

  it("keeps a denied outer image and its admitted nested image together as authored source", () => {
    const source = "Before.\n\n![fixture![](Attachments/inner)](Attachments/missing)\n\nAfter.";
    const state = projectedState(source, {"Attachments/inner": png});
    expect(imageReplacementRanges(state)).toEqual([]);
    expect(state.doc.toString()).toBe(source);
  });

  it("retains independent side-by-side and link-contained images", () => {
    const source = "![first](Attachments/figure) ![second](Attachments/figure)\n\n"
      + "[![linked](Attachments/figure)](https://example.test)\n\nAfter.";
    const state = projectedState(source, {"Attachments/figure": png});
    expect(imageReplacementRanges(state).map(range => source.slice(range.from, range.to)))
      .toEqual(["![first](Attachments/figure)", "![second](Attachments/figure)", "![linked](Attachments/figure)"]);
  });

  it("admits bounded native raster payloads without admitting URLs or active media", () => {
    expect(validImageResources({"Attachments/a.png": png})).toBe(true);
    expect(validImageResources({})).toBe(true);
    for (const value of [[], null, {x: "file:///image.png"}, {x: "https://example.com/x.png"},
      {x: "data:image/svg+xml;base64,PHN2Zy8+"}, {x: "data:image/png;base64,a"}, {x: 4}]) {
      expect(validImageResources(value)).toBe(false);
    }
    const oversized = "data:image/png;base64," + "A".repeat(4 * Math.ceil((MAX_IMAGE_BYTES + 3) / 3));
    expect(validImageResources({x: oversized})).toBe(false);
  });

  it("decodes authored relative/absolute destinations without fetching them", () => {
    expect(imageDestination("Attachments/a%20b.png")).toBe("Attachments/a b.png");
    expect(imageDestination("<Attachments/a%20b.png>")).toBe("Attachments/a b.png");
    expect(imageDestination("/registered/image.png")).toBe("/registered/image.png");
    expect(imageDestination("Attachments/a\\(b\\).png")).toBe("Attachments/a(b).png");
    for (const source of ["https://example.com/x.png", "file:/x.png", "//host/x.png", "x.png#id", "x.png?q=1", "a%ZZ.png"]) {
      expect(imageDestination(source)).toBeNull();
    }
  });

  it("matches native URL character-reference and single-pass punctuation decoding", () => {
    vi.stubGlobal("document", parseHTML("<!doctype html><html><body></body></html>").document);
    try {
      for (const source of ["Attachments/a&amp;b.png", "Attachments/a&#38;b.png", "Attachments/a&#x26;b.png",
        "Attachments/a\\&amp;b.png", "<Attachments/a&amp;b.png>"]) {
        expect(imageDestination(source)).toBe("Attachments/a&b.png");
      }
      expect(imageDestination("Attachments/a\\&amp;amp;b.png")).toBe("Attachments/a&amp;b.png");
      expect(imageDestination("Attachments/a\\\\&amp;b.png")).toBe("Attachments/a\\&b.png");
      expect(imageDestination("Attachments/a&notit;b.png")).toBe("Attachments/a&notit;b.png");
      expect(imageDestination("Attachments/a&ampb.png")).toBe("Attachments/a&ampb.png");
    } finally { vi.unstubAllGlobals(); }
  });

  it("admits inline and reference URL character references without changing source", () => {
    const source = "![named](Attachments/a&amp;b.png)\n\n![numeric][figure]\n\n[figure]: Attachments/a&#38;b.png";
    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
    const tree = ensureSyntaxTree(state, source.length, 5_000)!;
    const syntax = semanticProjectionRanges(state, [{from: 0, to: source.length}], 0, tree);
    const images = syntax.inlines.filter(image => image.kind === "image");
    vi.stubGlobal("document", parseHTML("<!doctype html><html><body></body></html>").document);
    try {
      expect(images.map(image => imagePresentation(state, image, {"Attachments/a&b.png": png}, syntax)?.resource))
        .toEqual([png, png]);
      expect(state.doc.toString()).toBe(source);
    } finally { vi.unstubAllGlobals(); }
  });

  it("keeps percent-encoded reserved filename characters subject to native resource admission", () => {
    for (const [destination, key] of [
      ["Attachments/a%23b.png", "Attachments/a#b.png"],
      ["Attachments/a%3Fb.png", "Attachments/a?b.png"],
    ]) {
      const source = `![fixture](${destination})`;
      const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
      const tree = ensureSyntaxTree(state, source.length, 5_000)!;
      const syntax = semanticProjectionRanges(state, [{from: 0, to: source.length}], 0, tree);
      const image = syntax.inlines.find(inline => inline.kind === "image")!;
      expect(imageDestination(destination)).toBe(key);
      expect(imagePresentation(state, image, {[key]: png}, syntax)?.resource).toBe(png);
      expect(imagePresentation(state, image, {}, syntax)).toBeNull();
      expect(state.doc.toString()).toBe(source);
    }
  });

  it("rejects raw and character-reference URL schemes, queries and fragments even with matching resource keys", () => {
    vi.stubGlobal("document", parseHTML("<!doctype html><html><body></body></html>").document);
    try {
      for (const [destination, key] of [
        ["https&colon;//example.test/a.png", "https://example.test/a.png"],
        ["&sol;&sol;host/a.png", "//host/a.png"],
        ["Attachments/a.png&quest;x=1", "Attachments/a.png?x=1"],
        ["Attachments/a.png?x=1", "Attachments/a.png?x=1"],
        ["Attachments/a.png&#35;fragment", "Attachments/a.png#fragment"],
        ["Attachments/a.png#fragment", "Attachments/a.png#fragment"],
      ]) {
        const source = `![fixture](${destination})`;
        const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
        const tree = ensureSyntaxTree(state, source.length, 5_000)!;
        const syntax = semanticProjectionRanges(state, [{from: 0, to: source.length}], 0, tree);
        const image = syntax.inlines.find(inline => inline.kind === "image")!;
        expect(imageDestination(destination)).toBeNull();
        expect(imagePresentation(state, image, {[key]: png}, syntax)).toBeNull();
        expect(state.doc.toString()).toBe(source);
      }
    } finally { vi.unstubAllGlobals(); }
  });

  it("uses parser-owned image spans and distinguishes image-only paragraphs from prose", () => {
    const source = "Before.\n\n![Landscape](<Attachments/a%20b.png> \"Title\")\n\nProse ![Inline](Attachments/a%20b.png) after.\n\n`![Literal](Attachments/a%20b.png)`";
    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
    const tree = ensureSyntaxTree(state, source.length, 5_000)!;
    const images = semanticProjectionRanges(state, [{from: 0, to: source.length}], 2_000, tree)
      .inlines.filter(image => image.kind === "image");
    expect(images).toHaveLength(2);
    const resources = {"Attachments/a b.png": png};
    const block = imagePresentation(state, images[0], resources)!;
    const inline = imagePresentation(state, images[1], resources)!;
    expect(block.block).toBe(true);
    expect(block.alt).toBe("Landscape");
    expect(source.slice(block.sourceFrom, block.sourceTo)).toContain('"Title"');
    expect(inline.block).toBe(false);
    expect(inline.alt).toBe("Inline");
    expect(imagePresentation(state, images[0], {})).toBeNull();
  });

  it("binds image admission to current generation and defers it during composition", () => {
    const request = {protocolVersion: EDITOR_PROTOCOL_VERSION, requestID: "image", expiresAt: Date.now() + 8_000,
      sessionID: "session", documentID: "document", startingFingerprint: "fingerprint", knownGeneration: 4,
      operation: {type: "setImageResources", value: {"a.png": png}}};
    expect(isEditorRequest(request)).toBe(true);
    expect(isEditorRequest({...request, operation: {...request.operation, value: {"a.png": "file:/private.png"}}})).toBe(false);
    expect(generationCanExecuteEditorRequest("setImageResources", 4, 4)).toBe(true);
    expect(generationCanExecuteEditorRequest("setImageResources", 3, 4)).toBe(false);
    expect(compositionRequestPolicy("setImageResources")).toBe("defer");
  });

  it("gives formatted image labels readable accessibility text without changing literal code or source", () => {
    const source = "![Full *caption* &amp; [nested](wrong.png) `&amp;` \\*literal\\*][figure]\n\n[figure]: Attachments/a.png";
    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
    const tree = ensureSyntaxTree(state, source.length, 5_000)!;
    const syntax = semanticProjectionRanges(state, [{from: 0, to: source.length}], 0, tree);
    const image = syntax.inlines.find(inline => inline.kind === "image")!;
    vi.stubGlobal("document", parseHTML("<!doctype html><html><body></body></html>").document);
    try {
      expect(imagePresentation(state, image, {"Attachments/a.png": png}, syntax)?.alt)
        .toBe("Full caption & nested &amp; *literal*");
      expect(state.doc.toString()).toBe(source);
    } finally { vi.unstubAllGlobals(); }
  });
});
