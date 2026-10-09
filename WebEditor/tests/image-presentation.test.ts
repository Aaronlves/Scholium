import {EditorSelection, EditorState, type TransactionSpec} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {EditorView} from "@codemirror/view";
import {history, undoDepth} from "@codemirror/commands";
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
  function projectedEditor(source: string, resources: Readonly<Record<string, string>>,
    activateLink = (_target: string, _isImage: boolean) => {}) {
    const selection = createLiveSelectionController({
      handleModifiedLink: () => false,
      handleProjectedPointerStart: () => false,
    });
    const projections = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
    const images = createImageProjection({selection, projections, bodyIsActive: () => true,
      shouldRefresh: () => false, activateLink});
    images.setResources(resources);
    const state = EditorState.create({doc: source, selection: {anchor: source.length},
      extensions: [scholiumNoteLanguage, selection.extension, projections.extension, images.extension,
        history(), EditorState.allowMultipleSelections.of(true)]});
    return {state, images};
  }

  function projectedState(source: string, resources: Readonly<Record<string, string>>) {
    return projectedEditor(source, resources).state;
  }

  function imageWidget(state: EditorState) {
    let widget: import("@codemirror/view").WidgetType | undefined;
    for (const decorations of state.facet(EditorView.decorations)) {
      if (typeof decorations !== "function") decorations.between(0, state.doc.length, (_from, _to, decoration) => {
        if (decoration.spec.widget) widget = decoration.spec.widget;
      });
    }
    expect(widget).toBeDefined();
    return widget!;
  }

  function mouseEvent(document: Document, type: string, properties: Partial<MouseEvent> = {}) {
    const event = document.createEvent("Event") as MouseEvent;
    event.initEvent(type, true, true);
    for (const [key, value] of Object.entries({button: 0, clientX: 10, clientY: 10,
      metaKey: false, shiftKey: false, altKey: false, ctrlKey: false, ...properties})) {
      Object.defineProperty(event, key, {value});
    }
    return event;
  }

  it.each(["plain", "add", "extend", "composition"])("preserves %s selection behavior at a projected image", mode => {
    const {document} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    try {
      const source = "Before.\n\n![figure](Attachments/figure)\n\nAfter.";
      const imageFrom = source.indexOf("![");
      let state = projectedState(source, {"Attachments/figure": png});
      state = state.update({selection: EditorSelection.create([
        EditorSelection.cursor(2), EditorSelection.cursor(source.length),
      ], 1)}).state;
      const dispatch = vi.fn((spec: TransactionSpec) => {state = state.update(spec).state;});
      const view = {get state() {return state;}, composing: false,
        compositionStarted: mode === "composition", dispatch, focus: vi.fn()};
      const dom = imageWidget(state).toDOM(view as unknown as EditorView);
      dom.querySelector("img")!.getBoundingClientRect = () => ({left: 0, width: 100} as DOMRect);
      dom.querySelector("img")!.dispatchEvent(mouseEvent(document, "mousedown", {
        metaKey: mode === "add", altKey: mode === "add", shiftKey: mode === "extend",
      }));
      if (mode === "composition") expect(dispatch).not.toHaveBeenCalled();
      else expect(state.selection.ranges.map(range => [range.anchor, range.head])).toEqual(mode === "add"
        ? [[2, 2], [imageFrom, imageFrom], [source.length, source.length]]
        : mode === "extend" ? [[2, 2], [source.length, imageFrom]] : [[imageFrom, imageFrom]]);
      expect(state.doc.toString()).toBe(source);
    } finally {vi.unstubAllGlobals();}
  });

  it("opens the admitted original only after a pure Command-click without changing selection, focus or Undo", () => {
    const {document} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    try {
      const source = "Before.\n\n![figure](Attachments/a%2520b&amp;c)\n\nAfter.";
      const activateLink = vi.fn();
      let {state} = projectedEditor(source, {"Attachments/a%20b&c": png}, activateLink);
      state = state.update({changes: {from: source.length, insert: "!"}, userEvent: "input.type"}).state;
      const selection = state.selection, depth = undoDepth(state);
      const view = {get state() {return state;}, compositionStarted: false,
        dispatch: vi.fn(), focus: vi.fn(), requestMeasure: vi.fn()};
      const dom = imageWidget(state).toDOM(view as unknown as EditorView);
      document.body.append(dom);
      const image = dom.querySelector("img")!;
      image.dispatchEvent(mouseEvent(document, "mousedown", {metaKey: true}));
      expect(activateLink).not.toHaveBeenCalled();
      image.dispatchEvent(mouseEvent(document, "click", {metaKey: true}));
      expect(activateLink).toHaveBeenCalledExactlyOnceWith("Attachments/a%2520b&c", true);
      expect(view.dispatch).not.toHaveBeenCalled();
      expect(view.focus).not.toHaveBeenCalled();
      expect(state.selection).toBe(selection);
      expect(state.doc.toString()).toBe(source + "!");
      expect(undoDepth(state)).toBe(depth);
    } finally {vi.unstubAllGlobals();}
  });

  it.each(["no-start", "drag", "click-moved", "leave", "dragstart", "pointercancel", "composition", "source-change", "detached", "modifier-change"])(
    "rejects an image preview after %s", interruption => {
      const {document} = parseHTML("<html><body></body></html>");
      vi.stubGlobal("document", document);
      try {
        const source = "Before.\n\n![figure](Attachments/figure)\n\nAfter.";
        const activateLink = vi.fn();
        let {state} = projectedEditor(source, {"Attachments/figure": png}, activateLink);
        const view = {get state() {return state;}, compositionStarted: false,
          dispatch: vi.fn(), focus: vi.fn(), requestMeasure: vi.fn()};
        const dom = imageWidget(state).toDOM(view as unknown as EditorView);
        document.body.append(dom);
        const image = dom.querySelector("img")!;
        if (interruption !== "no-start") image.dispatchEvent(mouseEvent(document, "mousedown", {metaKey: true}));
        if (interruption === "drag") image.dispatchEvent(mouseEvent(document, "mousemove", {clientX: 30}));
        if (["leave", "dragstart", "pointercancel"].includes(interruption)) {
          dom.dispatchEvent(mouseEvent(document, interruption === "leave" ? "mouseleave" : interruption));
        }
        if (interruption === "composition") view.compositionStarted = true;
        if (interruption === "source-change") state = state.update({changes: {from: 0, insert: "New.\n"}}).state;
        if (interruption === "detached") dom.remove();
        image.dispatchEvent(mouseEvent(document, "click", {metaKey: true,
          clientX: interruption === "click-moved" ? 30 : 10, altKey: interruption === "modifier-change"}));
        expect(activateLink).not.toHaveBeenCalled();
        expect(view.dispatch).not.toHaveBeenCalled();
      } finally {vi.unstubAllGlobals();}
    },
  );

  it("preserves an authored outer link's destination and never substitutes the image original", () => {
    const {document} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    try {
      const source = "Before.\n\n[![figure](Attachments/figure)](<https://example.test/a%20b?x=1&amp;y=2>)\n\nAfter.";
      const activateLink = vi.fn();
      const {state} = projectedEditor(source, {"Attachments/figure": png}, activateLink);
      const view = {state, compositionStarted: false, dispatch: vi.fn(), focus: vi.fn()};
      const dom = imageWidget(state).toDOM(view as unknown as EditorView);
      document.body.append(dom);
      const image = dom.querySelector("img")!;
      image.dispatchEvent(mouseEvent(document, "mousedown", {metaKey: true}));
      image.dispatchEvent(mouseEvent(document, "click", {metaKey: true}));
      expect(activateLink).toHaveBeenCalledExactlyOnceWith("https://example.test/a%20b?x=1&y=2", false);
      expect(view.dispatch).not.toHaveBeenCalled();
    } finally {vi.unstubAllGlobals();}
  });

  it("sizes only independent images from their decoded intrinsic ratio without changing source", () => {
    const {document} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    try {
      for (const source of ["Before.\n\n![figure](Attachments/figure)\n\nAfter.", "Before ![figure](Attachments/figure) after."]) {
        const state = projectedState(source, {"Attachments/figure": png});
        const view = {state, requestMeasure: vi.fn()};
        const dom = imageWidget(state).toDOM(view as unknown as EditorView);
        document.body.append(dom);
        const image = dom.querySelector("img")!;
        Object.defineProperties(image, {naturalWidth: {value: 300}, naturalHeight: {value: 600}});
        const event = document.createEvent("Event");
        event.initEvent("load", false, false);
        image.dispatchEvent(event);
        expect(image.style.getPropertyValue("--scholium-image-aspect-ratio")).toBe("0.5");
        expect(image.classList.contains("scholium-embedded-image-block")).toBe(source.includes("\n\n"));
        expect(view.requestMeasure).toHaveBeenCalledOnce();
        expect(state.doc.toString()).toBe(source);
      }
    } finally {vi.unstubAllGlobals();}
  });

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
      .toEqual(["![first](Attachments/figure)", "![second](Attachments/figure)", "[![linked](Attachments/figure)](https://example.test)"]);
  });

  it("reveals the entire standalone linked image when the caret enters its authored outer link", () => {
    const link = "[![figure](Attachments/figure)](https://example.test)";
    const source = `Before.\n\n${link}\n\nAfter.`;
    const from = source.indexOf(link);
    const state = projectedState(source, {"Attachments/figure": png});
    expect(imageReplacementRanges(state)).toEqual([{from, to: from + link.length, block: true}]);
    for (const anchor of [from, source.indexOf("https:") + 3]) {
      const revealed = state.update({selection: {anchor}}).state;
      expect(imageReplacementRanges(revealed)).toEqual([]);
      expect(revealed.doc.toString()).toBe(source);
    }
  });

  it("keeps a linked image with authored label prose inline", () => {
    const image = "![figure](Attachments/figure)";
    const source = `Before.\n\n[See ${image} here](https://example.test)\n\nAfter.`;
    const state = projectedState(source, {"Attachments/figure": png});
    const from = source.indexOf(image);
    expect(imageReplacementRanges(state)).toEqual([{from, to: from + image.length, block: false}]);
  });

  it("replaces a linked image widget after an outer destination or replacement range edit", () => {
    const source = "Before.\n\n[![figure](Attachments/figure)](https://first.test)\n\nAfter.";
    const state = projectedState(source, {"Attachments/figure": png});
    const original = imageWidget(state);
    const targetFrom = source.indexOf("first.test");
    const updated = state.update({changes: {from: targetFrom, to: targetFrom + 10, insert: "other.test"}}).state;
    expect(original.eq(imageWidget(updated))).toBe(false);
    const expanded = state.update({changes: {from: source.indexOf(")\n\nAfter."), insert: ' "title"'}}).state;
    expect(original.eq(imageWidget(expanded))).toBe(false);
    const presentation = (imageWidget(updated) as unknown as {presentation: {activation: unknown}}).presentation;
    expect(presentation.activation).toEqual({target: "https://other.test", isImage: false});
    expect(imageReplacementRanges(expanded)[0].to).toBe(imageReplacementRanges(state)[0].to + 8);
  });

  it("never substitutes an image preview for an outer link without an admitted target", () => {
    const source = "Before.\n\n[![figure](Attachments/figure)][target]\n\n[target]: https://example.test\n\nAfter.";
    const state = projectedState(source, {"Attachments/figure": png});
    const presentation = (imageWidget(state) as unknown as {presentation: {activation: unknown}}).presentation;
    expect(presentation.activation).toBeNull();
  });

  it("offers one admitted image target for source-local menu selections, including authored linked images", () => {
    const image = "![figure](Attachments/a%2520b&#38;c)";
    const source = `Before.\n\n[${image}](https://example.test)\n\nAfter.`;
    const {state, images} = projectedEditor(source, {"Attachments/a%20b&c": png});
    const from = source.indexOf(image), to = from + image.length;
    for (const selection of [{from, to: from}, {from: from + 3, to: from + 3}, {from, to}]) {
      expect(images.imageTargetAt(state, selection)).toBe("Attachments/a%2520b&c");
    }
    for (const selection of [{from: to, to}, {from: from - 1, to}, {from, to: to + 1}]) {
      expect(images.imageTargetAt(state, selection)).toBeNull();
    }
    images.setResources({});
    expect(images.imageTargetAt(state, {from, to})).toBeNull();
  });

  it.each([false, true])("maps any context-click within an image to its validated source start (linked: %s)", linked => {
    const {document, window} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("Element", window.Element);
    try {
      const imageSource = "![figure](Attachments/figure)";
      const source = `Before.\n\n${linked ? `[${imageSource}](https://example.test)` : imageSource}\n\nAfter.`;
      const {state, images} = projectedEditor(source, {"Attachments/figure": png});
      const dom = imageWidget(state).toDOM({state} as EditorView);
      const image = dom.querySelector("img")!;
      const event = {target: image, button: 2, clientX: 600, clientY: 400} as unknown as MouseEvent;
      const from = source.indexOf(imageSource);
      expect(images.contextPositionAtEvent(state, event)).toBe(from);
      expect(images.imageTargetAt(state, {from, to: from})).toBe("Attachments/figure");
      expect(state.doc.toString()).toBe(source);

      dom.dataset.scholiumSourceFrom = String(from + 1);
      expect(images.contextPositionAtEvent(state, event)).toBeNull();
      dom.dataset.scholiumSourceFrom = String(from);
      const moved = state.update({changes: {from: 0, insert: "New.\n"}}).state;
      expect(images.contextPositionAtEvent(moved, event)).toBeNull();
      images.setResources({});
      expect(images.contextPositionAtEvent(state, event)).toBeNull();
    } finally {vi.unstubAllGlobals();}
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
