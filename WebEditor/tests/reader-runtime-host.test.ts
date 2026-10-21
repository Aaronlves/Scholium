import {EditorState} from "@codemirror/state";
import {EditorView, type DecorationSet} from "@codemirror/view";
import {createCommittedReviewProjection} from "../committed-review-projection";
import type {CommittedReviewProjection} from "../committed-review-contract";
import {ExactSourceMirror} from "../state";
import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createNativeFloatingPorts} from "../native-floating";
import {initializeReader, type ReaderWindow} from "../reader-runtime";
import {currentDocumentScrollAnchor} from "../scroll-coordinator";
import {installConstructableStylesheet} from "./stylesheet-fixture";
import {clearEditorPerformanceSamples, editorPerformanceSamples, recordEditorMetric} from "../performance";
import {bindCommittedReviewImageResources} from "../committed-review-images";

function fixture() {
  const {document, window} = parseHTML('<html><head><style id="presentation"></style><style id="user"></style></head><body><div id="outside"><p>Outside</p><div class="scholium-math" data-math-source="eA==" data-math-kind="inline"></div></div><div id="scroll"><main id="scholium-document"><p data-source-line="1" data-source-utf16-start="0" data-source-utf16-end="4">Body</p></main></div><aside id="popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside></body></html>');
  Reflect.deleteProperty(window, "scholiumMath");
  vi.stubGlobal("document", document);
  vi.stubGlobal("window", window);
  vi.stubGlobal("HTMLElement", window.HTMLElement);
  vi.stubGlobal("Element", window.Element);
  vi.stubGlobal("Node", window.Node);
  vi.stubGlobal("HTMLImageElement", window.HTMLImageElement);
  vi.stubGlobal("CSS", {escape: (value: string) => value});
  vi.stubGlobal("getComputedStyle", () => ({display: "block", visibility: "visible"}));
  vi.stubGlobal("matchMedia", () => ({matches: false, addEventListener: () => {}}));
  installConstructableStylesheet(document);
  window.HTMLElement.prototype.getBoundingClientRect = () => ({left: 0, right: 400, top: 0, bottom: 400, width: 400, height: 400} as DOMRect);
  document.elementFromPoint = () => document.querySelector("#scholium-document p");
  const scroll = document.getElementById("scroll")!;
  Object.defineProperty(scroll, "scrollHeight", {value: 1200});
  Object.defineProperty(scroll, "clientHeight", {value: 400});
  scroll.scrollTop = 200;
  scroll.scrollTo = vi.fn(options => { if (options && typeof options === "object") scroll.scrollTop = options.top ?? 0; });
  const signal = new AbortController();
  const postMessage = vi.fn();
  const config = {version: 8, documentID: "note.md", fingerprint: "fingerprint", loadGeneration: 3,
    selectionEnabled: false, imagePreviewsEnabled: false, testingEnabled: false,
    presentationCSS: ".scholium-document { --reading-proof: 1; }", userCSS: ".scholium-document p { --user-proof: 1; }",
    localization: {languageTag: "en", strings: {}}, linkPreviews: []};
  const host = {root: document.getElementById("scholium-document")!, scrollDOM: scroll,
    presentationStyle: document.getElementById("presentation") as HTMLStyleElement,
    userStyle: document.getElementById("user") as HTMLStyleElement,
    popover: document.getElementById("popover")!, signal: signal.signal, nativeFloating: createNativeFloatingPorts(() => {}), postMessage};
  return {document, window: window as unknown as ReaderWindow, scroll, signal, postMessage, config, host};
}

function resizingFixture() {
  const f = fixture();
  const add = vi.fn(f.window.addEventListener);
  const remove = vi.fn(f.window.removeEventListener);
  // Linkedom exposes these methods through its window proxy, without own
  // property descriptors. Retain its real event target behind the recorder.
  f.window.addEventListener = add;
  f.window.removeEventListener = remove;
  let width = 400;
  Object.defineProperty(f.window, "innerWidth", {configurable: true, get: () => width});
  Object.defineProperty(f.document.documentElement, "clientWidth", {configurable: true, get: () => width});
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(() =>
    ({left: 0, right: width, top: 0, bottom: 400, width, height: 400} as DOMRect));
  return {...f, add, remove, resize() {
    width += 40;
    const event = f.document.createEvent("Event");
    event.initEvent("resize", false, false);
    f.window.dispatchEvent(event);
  }};
}

async function appearanceFixture(kind: "embedded" | "standalone") {
  const f = fixture();
  f.window.requestAnimationFrame = vi.fn(() => 1);
  f.window.cancelAnimationFrame = vi.fn();
  Object.defineProperty(f.document, "fonts", {configurable: true,
    value: {status: "loaded", ready: Promise.resolve()}});
  const paragraph = f.host.root.querySelector("p")!;
  paragraph.getBoundingClientRect = () => ({left: 0, right: 400, top: 100 - f.scroll.scrollTop,
    bottom: 500 - f.scroll.scrollTop, width: 400, height: 400} as DOMRect);
  const dispatch = (target: EventTarget, type: string) => {
    const event = f.document.createEvent("Event");
    event.initEvent(type, true, false);
    target.dispatchEvent(event);
  };
  if (kind === "standalone") {
    f.host.presentationStyle.id = "scholium-presentation-css";
    f.host.userStyle.id = "scholium-user-css";
    f.host.popover.id = "scholium-preview-popover";
    Object.defineProperty(f.window, "scrollY", {configurable: true, get: () => f.scroll.scrollTop});
    Object.defineProperty(f.window, "innerHeight", {configurable: true, value: 400});
    Object.defineProperty(f.document.documentElement, "scrollHeight", {configurable: true, value: 1200});
    f.window.scrollTo = f.scroll.scrollTo as typeof f.window.scrollTo;
  }
  const inputTarget = kind === "embedded" ? f.scroll : f.window;
  const add = vi.fn(inputTarget.addEventListener.bind(inputTarget));
  const remove = vi.fn(inputTarget.removeEventListener.bind(inputTarget));
  inputTarget.addEventListener = add;
  inputTarget.removeEventListener = remove;
  await initializeReader(f.config, kind === "embedded" ? f.host : undefined);
  const dispose = () => kind === "embedded" ? f.signal.abort() : dispatch(f.window, "pagehide");
  function waitForFonts() {
    let finish!: () => void;
    let entered!: () => void;
    const waiting = new Promise<void>(resolve => { finish = resolve; });
    const started = new Promise<void>(resolve => { entered = resolve; });
    const fonts = {status: "loading", get ready() { entered(); return waiting; }};
    Object.defineProperty(f.document, "fonts", {configurable: true, value: fonts});
    return {started, finish() { fonts.status = "loaded"; finish(); }};
  }
  return {...f, inputTarget, add, remove, dispatch, dispose, waitForFonts};
}

afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

describe("reader installation in a CodeMirror-owned viewport", () => {
  it.each(["initialize", "appearance", "cancelled"] as const)("reports current %s rendering failure without treating departure as failure", async stage => {
    const f = fixture();
    Object.defineProperty(f.document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
    const source = "Body";
    const committed: CommittedReviewProjection = {documentID: "editor-document", sourceFingerprint: "fingerprint",
      htmlBody: '<main id="scholium-document"><p>Body</p></main><aside id="scholium-preview-popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside>',
      css: "", configuration: {...f.config, version: 8}};
    const projection = createCommittedReviewProjection({projection: () => committed,
      mirror: () => new ExactSourceMirror(source), imageResources: () => ({}),
      nativeFloating: f.host.nativeFloating, postMessage: f.postMessage});
    const state = EditorState.create({doc: source, extensions: projection.extension});
    const decorations = state.facet(EditorView.decorations).find(value => typeof value !== "function") as DecorationSet;
    const widget = decorations.iter().value!.spec.widget;
    const dom = widget.toDOM({state, scrollDOM: f.scroll, requestMeasure() {}} as unknown as EditorView);
    f.scroll.replaceChildren(dom);
    if (stage === "initialize") {
      vi.spyOn(f.document.head, "appendChild").mockImplementationOnce(() => { throw new Error("forced reader initialization failure"); });
    } else if (stage === "cancelled") {
      widget.destroy(dom);
    } else {
      await projection.prepare(Date.now() + 2000);
      f.window.scholiumSetPresentationCSS = async () => { throw new Error("forced reading style failure"); };
      expect(projection.updateInPlace({...committed,
        configuration: {...committed.configuration, presentationCSS: "p {color: red}"}})).toBe(true);
    }
    await expect(projection.prepare(Date.now() + 2000)).rejects.toThrow();
    const failures = f.postMessage.mock.calls.map(([message]) => message).filter(message => message.type === "renderingFailed");
    if (stage === "cancelled") expect(failures).toHaveLength(0);
    else expect(failures).toContainEqual({version: 8, documentID: "note.md", fingerprint: "fingerprint",
      loadGeneration: 3, type: "renderingFailed"});
    if (stage !== "cancelled") widget.destroy(dom);
  });

  it("waits for a visible image at the bottom of an offset host viewport", async () => {
    const f = fixture();
    Object.defineProperty(f.document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
    f.scroll.getBoundingClientRect = () => ({left: 40, right: 440, top: 100, bottom: 500,
      width: 400, height: 400} as DOMRect);
    f.host.root.insertAdjacentHTML("beforeend", '<img src="data:image/png;base64,AAAA">');
    const image = f.host.root.querySelector("img")!;
    image.getBoundingClientRect = () => ({left: 40, right: 240, top: 450, bottom: 490,
      width: 200, height: 40} as DOMRect);
    let finishDecode!: () => void;
    let enteredDecode!: () => void;
    const decoded = new Promise<void>(resolve => { finishDecode = resolve; });
    const entered = new Promise<void>(resolve => { enteredDecode = resolve; });
    image.decode = vi.fn(() => { enteredDecode(); return decoded; });
    await initializeReader(f.config, f.host);
    const settling = f.window.scholiumReadPreparation!.settle(
      f.config.documentID, f.config.fingerprint, f.config.loadGeneration, Date.now() + 2000);
    try {
      expect(await Promise.race([entered.then(() => true), settling.then(() => false)])).toBe(true);
      expect(image.decode).toHaveBeenCalledOnce();
    } finally {
      finishDecode();
      await settling;
      f.signal.abort();
    }
  });

  it("shows actions for a visible bottom selection without scrolling an offset host", async () => {
    const f = fixture();
    vi.stubGlobal("Text", (f.window as ReaderWindow & typeof globalThis).Text);
    vi.stubGlobal("ShadowRoot", (f.window as ReaderWindow & typeof globalThis).ShadowRoot);
    f.scroll.getBoundingClientRect = () => ({left: 40, right: 440, top: 100, bottom: 500,
      width: 400, height: 400} as DOMRect);
    const paragraph = f.host.root.querySelector("p")!;
    const text = paragraph.firstChild!;
    const bounds = {left: 50, right: 150, top: 450, bottom: 470, width: 100, height: 20} as DOMRect;
    const range = {startContainer: text, endContainer: text, commonAncestorContainer: text,
      startOffset: 0, endOffset: 4, toString: () => "Body", intersectsNode: () => true,
      getBoundingClientRect: () => bounds, cloneRange: () => range} as unknown as Range;
    f.window.getSelection = () => ({rangeCount: 1, isCollapsed: false, getRangeAt: () => range} as unknown as Selection);
    f.document.createRange = () => ({selectNodeContents() {}, setEnd() {}, toString: () => ""} as unknown as Range);
    paragraph.scrollIntoView = vi.fn();
    await initializeReader({...f.config, selectionEnabled: true}, f.host);
    const surfaceID = await f.window.scholiumShowSelectionActions!();
    expect(surfaceID).toBeTypeOf("number");
    expect(paragraph.scrollIntoView).not.toHaveBeenCalled();
    expect(f.postMessage.mock.calls.map(([message]) => message).find(message =>
      message.type === "floatingSurface" && message.event.type === "selectionSurface")?.event.surface)
      .toMatchObject({top: 450, bottom: 470, utf16Count: 4});
    f.signal.abort();
  });

  it("renders and refreshes Mermaid with the hosted document's current local typography", async () => {
    const f = fixture();
    Object.defineProperty(f.document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
    f.host.root.insertAdjacentHTML("beforeend", '<pre><code class="language-mermaid">graph TD; A--&gt;B</code></pre>');
    f.document.documentElement.style.setProperty("--scholium-document-body-font-family", "Old Edit Font");
    const fontFor = (element: Element) => element === f.host.root
      ? f.host.presentationStyle.textContent!.match(/--scholium-document-body-font-family:\s*([^;}]+)/)?.[1]?.trim() ?? ""
      : f.document.documentElement.style.getPropertyValue("--scholium-document-body-font-family");
    vi.stubGlobal("getComputedStyle", (element: Element) => ({display: "block", visibility: "visible",
      getPropertyValue: (name: string) => name === "--scholium-document-body-font-family" ? fontFor(element) : ""}));
    const fonts: string[] = [];
    const render = vi.fn(async ({themeRoot}: {themeRoot?: Element}) => {
      fonts.push(getComputedStyle(themeRoot!).getPropertyValue("--scholium-document-body-font-family"));
      return {ok: false as const, reason: "unsupported-diagram" as const};
    });
    f.window.scholiumMermaid = {version: 3, render, copy: () => null, mount: () => false};
    await initializeReader({...f.config,
      presentationCSS: ":root { --scholium-document-body-font-family: First Review Font; }"}, f.host);
    expect(fonts).toEqual(["First Review Font"]);
    expect(render).toHaveBeenLastCalledWith(expect.objectContaining({themeRoot: f.host.root}));
    expect(await f.window.scholiumSetPresentationCSS!(
      ":root { --scholium-document-body-font-family: Updated Review Font; }", "")).toBe(true);
    expect(fonts).toEqual(["First Review Font", "Updated Review Font"]);
    expect(render).toHaveBeenLastCalledWith(expect.objectContaining({themeRoot: f.host.root}));
    expect(f.document.documentElement.style.getPropertyValue("--scholium-document-body-font-family")).toBe("Old Edit Font");
    f.signal.abort();
  });

  it("records numeric Review registry and layout phases only when the host opts in", async () => {
    clearEditorPerformanceSamples();
    const f = fixture();
    let clock = 10;
    vi.spyOn(performance, "now").mockImplementation(() => clock);
    let finishFonts!: () => void;
    let fontsEntered!: () => void;
    const ready = new Promise<void>(resolve => { finishFonts = resolve; });
    const entered = new Promise<void>(resolve => { fontsEntered = resolve; });
    const fonts = {status: "loading", get ready() { fontsEntered(); return ready; }};
    Object.defineProperty(f.document, "fonts", {configurable: true, value: fonts});
    await initializeReader(f.config, {...f.host, recordMetric: recordEditorMetric});
    const settling = f.window.scholiumReadPreparation!.settle(
      f.config.documentID, f.config.fingerprint, f.config.loadGeneration, Date.now() + 2000);
    await entered;
    clock = 45;
    fonts.status = "loaded";
    finishFonts();
    expect(await settling).toEqual({settled: true, geometryChanged: true});
    const samples = editorPerformanceSamples();
    expect(samples.map(sample => sample.name)).toEqual(["review-scroll-registry", "review-layout-settle"]);
    expect(samples[0].observed).toEqual({review: 1, candidateCount: 1,
      registeredBlockCount: 1, styleReadCount: 1, measureCount: 1});
    expect(samples[1].durationMilliseconds).toBe(35);
    expect(samples[1].observed).toEqual({review: 1, completed: 1, geometryChanged: 1,
      mathWaitMilliseconds: 0, mermaidWaitMilliseconds: 0, fontsWaitMilliseconds: 35,
      imageWaitMilliseconds: 0, imageWaitCount: 0, measureCount: 4});
    expect(samples.every(sample => Object.values(sample.observed).every(value => Number.isFinite(value) && value >= 0))).toBe(true);
    expect(f.scroll.scrollTop).toBe(200);
    expect(f.scroll.scrollTo).not.toHaveBeenCalled();
    f.signal.abort();
    clearEditorPerformanceSamples();
  });

  it.each(["embedded", "standalone"] as const)("leaves the editor performance ring untouched for an unobserved %s reader", async kind => {
    clearEditorPerformanceSamples();
    const f = await appearanceFixture(kind);
    await f.window.scholiumReadPreparation!.settle(
      f.config.documentID, f.config.fingerprint, f.config.loadGeneration, Date.now() + 2000);
    expect(editorPerformanceSamples()).toEqual([]);
    f.dispose();
  });

  for (const kind of ["embedded", "standalone"] as const) {
    it(`keeps the researcher's new ${kind} viewport when input interrupts appearance resource waiting`, async () => {
      vi.useFakeTimers();
      const f = await appearanceFixture(kind);
      const fonts = f.waitForFonts();
      const updating = f.window.scholiumSetPresentationCSS!(".scholium-document {font-size:20px}", "");
      await fonts.started;
      f.dispatch(f.inputTarget, "wheel");
      f.scroll.scrollTop = 600;
      fonts.finish();
      expect(await updating).toBe(true);
      expect(f.host.presentationStyle.textContent).toContain("font-size:20px");
      expect(f.scroll.scrollTop).toBe(600);
      expect(f.scroll.scrollTo).not.toHaveBeenCalled();
      f.dispose();
    });

    it(`restores the ${kind} appearance anchor after automatic scrolling without input`, async () => {
      vi.useFakeTimers();
      const f = await appearanceFixture(kind);
      const fonts = f.waitForFonts();
      const updating = f.window.scholiumSetPresentationCSS!(".scholium-document {font-size:20px}", "");
      await fonts.started;
      // A real reader navigation call and its scroll event do not establish
      // user input ownership and must not disable appearance convergence.
      f.window.scholiumReadScroll!.setFraction(0.75);
      expect(f.scroll.scrollTop).toBe(600);
      f.dispatch(kind === "embedded" ? f.scroll : f.window, "scroll");
      fonts.finish();
      expect(await updating).toBe(true);
      expect(f.scroll.scrollTop).toBe(200);
      expect(f.scroll.scrollTo).toHaveBeenLastCalledWith({top: 200, behavior: "auto"});
      f.dispose();
    });

    it(`removes all ${kind} appearance input listeners on disposal`, async () => {
      const f = await appearanceFixture(kind);
      const registrations = f.add.mock.calls.filter(([, listener]) =>
        typeof listener === "function" && listener.name === "abandonAppearanceRestoration");
      expect(registrations.map(([type]) => type).sort()).toEqual(["keydown", "pointerdown", "touchstart", "wheel"]);
      f.dispose();
      for (const [type, listener] of registrations) expect(f.remove).toHaveBeenCalledWith(type, listener, true);
    });
  }

  it("captures the reading paragraph for detachment and restores it after mounting a fresh Review widget", async () => {
    clearEditorPerformanceSamples();
    const f = fixture();
    Object.defineProperty(f.document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
    const source = "\uFEFFFirst.\r\n\r\nMiddle 😀 paragraph.\r\n\r\nLast.\r\n";
    const mirror = new ExactSourceMirror(source);
    const lower = source.indexOf("Middle"), upper = source.indexOf("\r\n\r\nLast");
    const committed: CommittedReviewProjection = {documentID: "editor-document", sourceFingerprint: "fingerprint",
      htmlBody: `<main id="scholium-document"><p data-source-line="1" data-source-utf16-start="0" data-source-utf16-end="7">First.</p><p class="middle" data-source-line="3" data-source-utf16-start="${lower}" data-source-utf16-end="${upper}">Middle 😀 paragraph.</p><p data-source-line="5" data-source-utf16-start="${source.indexOf("Last")}" data-source-utf16-end="${source.length - 2}">Last.</p></main><aside id="scholium-preview-popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside>`,
      css: "", configuration: {...f.config, version: 8}};
    const projection = createCommittedReviewProjection({projection: () => committed, mirror: () => mirror, imageResources: () => ({}),
      nativeFloating: f.host.nativeFloating, postMessage: f.postMessage});
    const state = EditorState.create({doc: source, extensions: projection.extension});
    const decorations = state.facet(EditorView.decorations).find(value => typeof value !== "function") as DecorationSet;
    const widget = decorations.iter().value!.spec.widget;
    const view = {state, scrollDOM: f.scroll, requestMeasure: vi.fn()} as unknown as EditorView;
    const mount = () => {
      const dom = widget.toDOM(view) as HTMLElement;
      f.scroll.replaceChildren(dom);
      const middle = dom.querySelector<HTMLElement>(".middle")!;
      middle.getBoundingClientRect = () => ({left: 0, right: 400, top: 350 - f.scroll.scrollTop,
        bottom: 450 - f.scroll.scrollTop, width: 400, height: 100} as DOMRect);
      f.document.elementFromPoint = () => middle;
      return dom;
    };
    f.scroll.scrollTop = 367;
    const firstDOM = mount();
    await projection.prepare(Date.now() + 2000);
    const samples = editorPerformanceSamples();
    expect(samples.find(sample => sample.name === "review-html-insertion")?.observed)
      .toEqual({review: 1, htmlUTF16Length: committed.htmlBody.length});
    expect(samples.find(sample => sample.name === "review-reader-initialization")?.observed)
      .toEqual({review: 1, completed: 1});
    expect(samples.some(sample => sample.name === "review-scroll-registry")).toBe(true);
    expect(samples.some(sample => sample.name === "review-layout-settle")).toBe(true);
    // CM sees a single replacement spanning all source. That geometry cannot
    // identify the paragraph displayed inside its native committed HTML.
    const wholeWidgetAnchor = {sourceUTF16Offset: 0, blockUTF16LowerBound: 0,
      blockUTF16UpperBound: source.length, relativeBlockPosition: 0.25, fallbackFraction: 367 / 800};
    const editing = {currentAnchor: vi.fn(() => wholeWidgetAnchor)};
    const captured = currentDocumentScrollAnchor("review", editing, projection)!;
    expect(captured.blockUTF16LowerBound).toBe(mirror.normalizedOffset(lower));
    expect(captured.blockUTF16UpperBound).toBe(mirror.normalizedOffset(upper));
    expect(captured.relativeBlockPosition).toBe(0.25);
    expect(captured.fallbackFraction).toBe(367 / 800);
    expect(editing.currentAnchor).not.toHaveBeenCalled();
    widget.destroy(firstDOM);
    expect(currentDocumentScrollAnchor("review", editing, projection)).toBeUndefined();
    expect(editing.currentAnchor).not.toHaveBeenCalled();
    f.scroll.scrollTop = 0;
    const restoredDOM = mount();
    await projection.prepare(Date.now() + 2000);
    expect(projection.setAnchor(captured)).toBe(true);
    expect(f.scroll.scrollTop).toBe(367);
    expect(currentDocumentScrollAnchor("review", editing, projection)).toEqual(captured);
    for (const mode of ["livePreview", "source"] as const) {
      expect(currentDocumentScrollAnchor(mode, editing, projection)).toBe(wholeWidgetAnchor);
    }
    expect(editing.currentAnchor).toHaveBeenCalledTimes(2);
    widget.destroy(restoredDOM);
    clearEditorPerformanceSamples();
  });

  it("binds catalog images before Reader initialization and refreshes their src in the existing Review DOM", async () => {
    const f = fixture();
    Object.defineProperty(f.window, "innerWidth", {configurable: true, value: 400});
    Object.defineProperty(f.document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
    const source = "Selected 图 e\u0301\r\n\r\n![](Attachments/a%2525.png)\r\n";
    const committed: CommittedReviewProjection = {documentID: "editor-document", sourceFingerprint: "fingerprint",
      htmlBody: '<main id="scholium-document"><p>Selected 图 é</p><img class="scholium-embedded-image" data-scholium-image-target="Attachments/a%2525.png" data-scholium-image-resource="Attachments/a%25.png"></main><aside id="scholium-preview-popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside>',
      css: "", configuration: {...f.config, version: 8}};
    let resources: Record<string, string> = {"Attachments/a%25.png": "data:image/png;base64,AAAA"};
    const mirror = new ExactSourceMirror(source);
    const projection = createCommittedReviewProjection({projection: () => committed, mirror: () => mirror,
      imageResources: () => resources, nativeFloating: f.host.nativeFloating, postMessage: f.postMessage});
    const state = EditorState.create({doc: source, selection: {anchor: 1, head: 8}, extensions: projection.extension});
    const decorations = state.facet(EditorView.decorations).find(value => typeof value !== "function") as DecorationSet;
    const widget = decorations.iter().value!.spec.widget;
    const dispatch = vi.fn(), requestMeasure = vi.fn();
    const view = {state, scrollDOM: f.scroll, requestMeasure, dispatch} as unknown as EditorView;
    const dom = widget.toDOM(view) as HTMLElement;
    f.scroll.replaceChildren(dom);
    const image = dom.querySelector("img")!;
    image.decode = vi.fn(() => Promise.resolve());
    // Binding is synchronous: Reader's visible-image barrier sees this src.
    expect(image.getAttribute("src")).toBe(resources["Attachments/a%25.png"]);
    await projection.prepare(Date.now() + 2000);
    const preparation = f.window.scholiumReadPreparation;
    const dismissPreview = vi.spyOn(f.window, "scholiumDismissPreview");
    const text = dom.querySelector("p")!.firstChild;
    resources = {"Attachments/a%25.png": "data:image/png;base64,AQID"};
    projection.refreshImageResources();
    expect(dismissPreview).toHaveBeenCalledOnce();
    expect(image.getAttribute("src")).toBe(resources["Attachments/a%25.png"]);
    await projection.prepare(Date.now() + 2000);
    expect(image.decode).toHaveBeenCalledTimes(2);
    expect(dom.querySelector("img")).toBe(image);
    expect(dom.querySelector("p")!.firstChild).toBe(text);
    expect(f.window.scholiumReadPreparation).toBe(preparation);
    expect(view.state).toBe(state);
    expect(state.selection.main.anchor).toBe(1);
    expect(state.selection.main.head).toBe(8);
    expect(mirror.text).toBe(source);
    expect(dispatch).not.toHaveBeenCalled();
    let releasePrevious!: () => void, releaseCurrent!: () => void;
    image.decode = vi.fn().mockImplementationOnce(() => new Promise<void>(resolve => { releasePrevious = resolve; }))
      .mockImplementationOnce(() => new Promise<void>(resolve => { releaseCurrent = resolve; }));
    resources = {"Attachments/a%25.png": "data:image/png;base64,AAAA"};
    projection.refreshImageResources();
    let settled = false;
    const settling = projection.prepare(Date.now() + 2000).then(() => { settled = true; });
    await vi.waitFor(() => expect(image.decode).toHaveBeenCalledOnce());
    resources = {"Attachments/a%25.png": "data:image/png;base64,AQID"};
    projection.refreshImageResources();
    releasePrevious();
    await vi.waitFor(() => expect(image.decode).toHaveBeenCalledTimes(2));
    expect(settled).toBe(false);
    releaseCurrent();
    await settling;
    resources = {};
    projection.refreshImageResources();
    expect(image.hasAttribute("src")).toBe(false);
    widget.destroy(dom);
    const measurements = requestMeasure.mock.calls.length;
    resources = {"Attachments/a%25.png": "data:image/png;base64,AAAA"};
    projection.refreshImageResources();
    expect(image.hasAttribute("src")).toBe(false);
    expect(requestMeasure).toHaveBeenCalledTimes(measurements);
  });

  it("does not refresh a canceled mount and binds only the current catalog on its next mount", async () => {
    const f = fixture();
    Object.defineProperty(f.document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
    const committed: CommittedReviewProjection = {documentID: "editor-document", sourceFingerprint: "fingerprint",
      htmlBody: '<main id="scholium-document"><p>Body</p><img class="scholium-embedded-image" data-scholium-image-resource="a.png"></main><aside id="scholium-preview-popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside>',
      css: "", configuration: {...f.config, version: 8}};
    let resources = {"a.png": "data:image/png;base64,AAAA"};
    const projection = createCommittedReviewProjection({projection: () => committed,
      mirror: () => new ExactSourceMirror("Body"), imageResources: () => resources,
      nativeFloating: f.host.nativeFloating, postMessage: f.postMessage});
    const state = EditorState.create({doc: "Body", extensions: projection.extension});
    const decorations = state.facet(EditorView.decorations).find(value => typeof value !== "function") as DecorationSet;
    const widget = decorations.iter().value!.spec.widget;
    const view = {state, scrollDOM: f.scroll, requestMeasure: vi.fn()} as unknown as EditorView;
    const canceled = widget.toDOM(view) as HTMLElement;
    const previousImage = canceled.querySelector("img")!;
    widget.destroy(canceled);
    resources = {"a.png": "data:image/png;base64,AQID"};
    projection.refreshImageResources();
    expect(previousImage.getAttribute("src")).toBe("data:image/png;base64,AAAA");
    const current = widget.toDOM(view) as HTMLElement;
    f.scroll.replaceChildren(current);
    const currentImage = current.querySelector("img")!;
    currentImage.decode = vi.fn(() => Promise.resolve());
    await projection.prepare(Date.now() + 2000);
    expect(currentImage.getAttribute("src")).toBe(resources["a.png"]);
    expect(currentImage).not.toBe(previousImage);
    expect(f.postMessage.mock.calls.filter(([message]) => message.type === "ready")).toHaveLength(1);
    widget.destroy(current);
  });

  it("sends admitted annotation image keys without copying resource bytes into the Native preview", async () => {
    const f = fixture();
    f.host.root.innerHTML = '<sup class="scholium-link-annotation-marker"><button class="scholium-link-annotation-button" data-link-annotation="annotation-1" data-link-annotation-target="Target">Annotation</button></sup>';
    const button = f.host.root.querySelector("button")!;
    const template = f.document.createElement("template");
    template.id = "annotation-1-template";
    const image = f.document.createElement("img");
    image.className = "scholium-embedded-image";
    image.alt = "Authored 图";
    image.dataset.scholiumImageResource = "a%25&b.png";
    image.dataset.scholiumImageTarget = "a%2525&b.png";
    template.content.append(image);
    button.parentElement!.append(template);
    bindCommittedReviewImageResources(f.host.root, {"a%25&b.png": "data:image/png;base64,AAAA"});
    await initializeReader(f.config, f.host);
    const open = () => {
      const event = f.document.createEvent("Event");
      event.initEvent("focusin", true, false);
      button.dispatchEvent(event);
      const surface = f.postMessage.mock.calls.filter(([message]) => message.type === "floatingSurface"
        && message.event.type === "previewSurface").at(-1)![0].event.surface;
      return parseHTML(`<html><body>${surface.html}</body></html>`).document.querySelector("img")!;
    };
    const original = open();
    expect(original.hasAttribute("src")).toBe(false);
    expect(original.getAttribute("data-scholium-image-resource")).toBe("a%25&b.png");
    expect(original.alt).toBe("Authored 图");
    expect(original).not.toBe(image);
    bindCommittedReviewImageResources(f.host.root, {"a%25&b.png": "data:image/png;base64,AQID"});
    f.window.scholiumDismissPreview?.();
    expect(open().hasAttribute("src")).toBe(false);
    expect(image.getAttribute("src")).toBe("data:image/png;base64,AQID");
    bindCommittedReviewImageResources(f.host.root, {});
    f.window.scholiumDismissPreview?.();
    expect(open().hasAttribute("src")).toBe(false);
    expect(template.content.firstChild).toBe(image);
    expect(image.alt).toBe("Authored 图");
    f.signal.abort();
  });

  it("preserves inert checked tasks and hydrates annotation/link mathematics once per target", async () => {
    const f = fixture();
    f.host.root.innerHTML = '<button class="footnote-reference" data-footnote="1">1</button>'
      + '<section id="fn-1"><div class="footnote-content"><input class="scholium-task-checkbox" type="checkbox" disabled checked><input type="text" value="unsafe"><p>Footnote</p></div></section>'
      + '<a class="wiki-link" data-source-utf16-start="0" data-source-utf16-end="4">Linked</a>'
      + '<sup class="scholium-link-annotation-marker"><button class="scholium-link-annotation-button" data-link-annotation="a" data-link-annotation-target="Linked">Annotation</button><template id="a-template"><span class="scholium-math" data-math-source="eA==" data-math-kind="inline"><code class="scholium-math-source">x</code></span></template></sup>';
    const render = vi.fn(() => ({ok: true as const, html: '<math><mi>x</mi></math>'}));
    f.window.scholiumMath = {version: 1, render};
    await initializeReader({...f.config, linkPreviews: [{utf16LowerBound: 0, utf16UpperBound: 4,
      title: "Linked", isEmbedded: false, htmlBody: '<p><span class="scholium-math" data-math-source="eA==" data-math-kind="inline"><code class="scholium-math-source">x</code></span></p>'}]}, f.host);
    const dispatch = (anchor: Element, type: string) => {
      const event = f.document.createEvent("Event"); event.initEvent(type, true, false); anchor.dispatchEvent(event);
    };
    const sent = () => f.postMessage.mock.calls.filter(([message]) => message.type === "floatingSurface"
      && message.event.type === "previewSurface");
    const footnote = f.host.root.querySelector('.footnote-reference')!;
    dispatch(footnote, 'pointerover');
    const before = sent().length;
    dispatch(footnote, 'focusin');
    expect(sent()).toHaveLength(before);
    const body = parseHTML(`<html><body>${sent().at(-1)![0].event.surface.html}</body></html>`).document;
    expect(body.querySelectorAll('input')).toHaveLength(1);
    expect(body.querySelector('input')?.hasAttribute('checked')).toBe(true);
    expect(body.querySelector('input')?.hasAttribute('disabled')).toBe(true);
    const annotation = f.host.root.querySelector('.scholium-link-annotation-button')!;
    dispatch(annotation, 'focusin');
    expect(sent().at(-1)![0].event.surface.html).toContain('<math>');
    const count = render.mock.calls.length;
    dispatch(annotation, 'pointerover');
    expect(render).toHaveBeenCalledTimes(count);
    dispatch(f.host.root.querySelector('a')!, 'focusin');
    expect(sent().at(-1)![0].event.surface.html).toContain('<math>');
    expect(render).toHaveBeenCalledTimes(count + 1);
    const finalCount = sent().length;
    f.signal.abort();
    dispatch(annotation, 'focusin');
    expect(sent()).toHaveLength(finalCount);
  });

  it("loads template-only mathematics on disclosure without delaying initial Review", async () => {
    const f = fixture();
    f.host.root.innerHTML = '<sup class="scholium-link-annotation-marker"><button class="scholium-link-annotation-button" data-link-annotation="a">Annotation</button><template id="a-template"><span class="scholium-math" data-math-source="eA==" data-math-kind="inline"><code class="scholium-math-source">x</code></span></template></sup>';
    await initializeReader(f.config, f.host);
    expect(f.postMessage.mock.calls.filter(([message]) => message.type === 'requestMathRuntime')).toHaveLength(0);
    const button = f.host.root.querySelector('button')!;
    const focus = f.document.createEvent('Event'); focus.initEvent('focusin', true, false); button.dispatchEvent(focus);
    expect(f.postMessage.mock.calls.filter(([message]) => message.type === 'requestMathRuntime')).toHaveLength(1);
    expect(f.postMessage.mock.calls.some(([message]) => message.type === 'floatingSurface'
      && message.event.type === 'previewSurface')).toBe(false);
    f.window.scholiumMath = {version: 1, render: () => ({ok: true, html: '<math><mi>x</mi></math>'})};
    const settled = f.document.createEvent('Event'); settled.initEvent('scholium-math-runtime-settled', false, false); f.window.dispatchEvent(settled);
    await Promise.resolve();
    expect(f.postMessage.mock.calls.filter(([message]) => message.type === 'floatingSurface'
      && message.event.type === 'previewSurface').at(-1)![0].event.surface.html).toContain('<math>');
    f.signal.abort();
  });

  it("requests one lazy math runtime for a later peer preview without initial document mathematics", async () => {
    const f = fixture();
    f.host.root.innerHTML = '<a class="wiki-link" data-source-utf16-start="0" data-source-utf16-end="4">Linked</a>';
    await initializeReader(f.config, f.host);
    expect(f.postMessage.mock.calls.some(([message]) => message.type === 'requestMathRuntime')).toBe(false);
    f.window.scholiumSetLinkPreviews?.([{utf16LowerBound: 0, utf16UpperBound: 4, title: 'Linked', isEmbedded: false,
      htmlBody: '<p><span class="scholium-math" data-math-source="eA==" data-math-kind="inline"><code class="scholium-math-source">x</code></span></p>'}]);
    const link = f.host.root.querySelector('a')!;
    for (const type of ['pointerover', 'focusin']) {
      const event = f.document.createEvent('Event'); event.initEvent(type, true, false); link.dispatchEvent(event);
    }
    expect(f.postMessage.mock.calls.filter(([message]) => message.type === 'requestMathRuntime')).toHaveLength(1);
    expect(f.postMessage.mock.calls.some(([message]) => message.type === 'floatingSurface'
      && message.event.type === 'previewSurface')).toBe(false);
    f.window.scholiumDismissPreview?.();
    f.window.scholiumMath = {version: 1, render: () => ({ok: true, html: '<math><mi>x</mi></math>'})};
    const settled = f.document.createEvent('Event'); settled.initEvent('scholium-math-runtime-settled', false, false); f.window.dispatchEvent(settled);
    await Promise.resolve();
    const messages = f.postMessage.mock.calls.filter(([message]) => message.type === 'floatingSurface'
      && message.event.type === 'previewSurface');
    expect(messages).toHaveLength(0);
    const reopen = f.document.createEvent('Event'); reopen.initEvent('focusin', true, false); link.dispatchEvent(reopen);
    const current = f.postMessage.mock.calls.filter(([message]) => message.type === 'floatingSurface'
      && message.event.type === 'previewSurface');
    expect(current).toHaveLength(1);
    expect(current[0][0].event.surface.html).toContain('<math>');
    f.signal.abort();
  });

  it("uses the host scroll container and clears its APIs/styles/probes when the mode leaves", async () => {
    const f = fixture();
    await initializeReader(f.config, f.host);
    expect(f.host.presentationStyle.textContent).toBe(f.config.presentationCSS);
    expect(f.host.userStyle.textContent).toBe(f.config.userCSS);
    expect(f.window.scholiumReadScroll?.fraction()).toBe(0.25);
    f.window.scholiumReadScroll?.setFraction(0.75);
    expect(f.scroll.scrollTo).toHaveBeenCalledWith({top: 600, behavior: "auto"});
    expect(f.document.querySelectorAll("head style")).toHaveLength(3); // Existing presentation + user + owned Find.
    f.signal.abort();
    expect(f.window.scholiumReadScroll).toBeUndefined();
    expect(f.window.scholiumReviewFind).toBeUndefined();
    expect(f.window.scholiumReadPreparation).toBeUndefined();
    expect(f.document.querySelectorAll("head style")).toHaveLength(2);
    expect(f.document.querySelector('[style*="100vw"]')).toBeNull();
  });

  it("does not install window-scrollbar resize state in embedded Review or leak it after abort", async () => {
    vi.useFakeTimers();
    const f = resizingFixture();
    await initializeReader(f.config, f.host);
    f.resize();
    expect(f.document.querySelector('[style*="100vw"]')).toBeNull();
    expect(f.document.documentElement.classList.contains("scholium-viewport-resize-suppresses-overlay-scrollbar")).toBe(false);
    expect(f.add.mock.calls.some(([type, listener]) => type === "resize"
      && typeof listener === "function" && listener.name === "viewportDidResize")).toBe(false);
    f.signal.abort();
    vi.advanceTimersByTime(100);
    f.resize();
    expect(f.document.documentElement.classList.contains("scholium-viewport-resize-suppresses-overlay-scrollbar")).toBe(false);
    expect(f.window.scholiumReadPreparation).toBeUndefined();
  });

  it.each(["settle", "rearm"])("cleans standalone resize state during a pending %s timer", async phase => {
    vi.useFakeTimers();
    const f = resizingFixture();
    f.host.presentationStyle.id = "scholium-presentation-css";
    f.host.userStyle.id = "scholium-user-css";
    f.host.popover.id = "scholium-preview-popover";
    await initializeReader(f.config);
    const listener = f.add.mock.calls.find(([type, listener]) => type === "resize"
      && typeof listener === "function" && listener.name === "viewportDidResize")![1];
    f.resize();
    expect(f.document.documentElement.classList.contains("scholium-viewport-resize-suppresses-overlay-scrollbar")).toBe(true);
    if (phase === "rearm") {
      vi.advanceTimersToNextTimer();
      expect(f.document.documentElement.classList.contains("scholium-viewport-resize-suppresses-overlay-scrollbar")).toBe(false);
      expect(f.add.mock.calls.filter(([type, value]) => type === "resize" && value === listener)).toHaveLength(1);
    }
    const event = f.document.createEvent("Event");
    event.initEvent("pagehide", false, false);
    f.window.dispatchEvent(event);
    const registrationCount = f.add.mock.calls.length;
    expect(f.remove).toHaveBeenCalledWith("resize", listener);
    expect(f.document.querySelector('[style*="100vw"]')).toBeNull();
    expect(f.document.documentElement.classList.contains("scholium-viewport-resize-suppresses-overlay-scrollbar")).toBe(false);
    vi.advanceTimersByTime(100);
    f.resize();
    expect(f.add.mock.calls).toHaveLength(registrationCount);
    expect(f.document.documentElement.classList.contains("scholium-viewport-resize-suppresses-overlay-scrollbar")).toBe(false);
  });

  it("keeps one floating callback and monotonic IDs through Review previews and returning Edit suggestions", async () => {
    const f = fixture();
    f.host.root.insertAdjacentHTML("beforeend", '<button class="footnote-reference" data-footnote="1">1</button><section id="fn-1"><div class="footnote-content">Footnote body</div></section>');
    const editChoose = vi.fn(() => true);
    const suggestions = {left: 10, top: 20, bottom: 30, selected: 0,
      items: [{label: "Continue", detail: "", disabled: false}]};
    const first = f.host.nativeFloating.suggestions.show(suggestions, {dismiss() {}, choose: editChoose});
    const callback = (f.window as ReaderWindow & {scholiumNativeFloatingEvent: (id: number, action: string, index: number) => boolean}).scholiumNativeFloatingEvent;
    await initializeReader(f.config, f.host);
    expect((f.window as unknown as {scholiumNativeFloatingEvent: unknown}).scholiumNativeFloatingEvent).toBe(callback);
    const pointerOver = f.document.createEvent("Event");
    pointerOver.initEvent("pointerover", true, false);
    f.host.root.querySelector("button")!.dispatchEvent(pointerOver);
    const preview = f.postMessage.mock.calls.map(([message]) => message)
      .find(message => message.type === "floatingSurface" && message.event.type === "previewSurface");
    expect(preview).toBeDefined();
    const reviewID = preview!.event.surface.id as number;
    expect(reviewID).toBeGreaterThan(first);
    expect(callback(reviewID, "enter", 0)).toBe(true);
    expect(callback(first, "choose", 0)).toBe(false);
    f.signal.abort();
    const returned = f.host.nativeFloating.suggestions.show(suggestions, {dismiss() {}, choose: editChoose});
    expect(returned).toBeGreaterThan(reviewID);
    expect(callback(reviewID, "leave", 0)).toBe(false);
    expect(callback(returned, "choose", 0)).toBe(true);
    expect(editChoose).toHaveBeenCalledExactlyOnceWith(0);
  });

  it("retains the mounted reading text and reader APIs during CSS updates with reordered transport dictionaries", async () => {
    const f = fixture();
    f.host.presentationStyle.id = "scholium-presentation-css";
    f.host.userStyle.id = "scholium-user-css";
    f.host.presentationStyle.textContent = ":root { --edit-presentation: 1; }";
    f.host.userStyle.textContent = ".cm-content { --edit-user: 1; }";
    Object.defineProperty(f.document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
    const initial: CommittedReviewProjection = {documentID: "editor-document", sourceFingerprint: "fingerprint",
      htmlBody: '<main id="scholium-document"><p data-source-line="1" data-source-utf16-start="0" data-source-utf16-end="10">Plain body</p></main><aside id="scholium-preview-popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside>', css: "",
      configuration: {...f.config, version: 8, localization: {languageTag: "en", strings: {"Note title": "Note title", Copy: "Copy"}}}};
    const projection = createCommittedReviewProjection({projection: () => initial, mirror: () => new ExactSourceMirror("Plain body"), imageResources: () => ({}),
      nativeFloating: f.host.nativeFloating, postMessage: f.postMessage});
    const state = EditorState.create({doc: "Plain body", extensions: projection.extension});
    const decorations = state.facet(EditorView.decorations).find(value => typeof value !== "function") as DecorationSet;
    const widget = decorations.iter().value!.spec.widget;
    const view = {state, scrollDOM: f.scroll, requestMeasure: vi.fn()} as unknown as EditorView;
    const dom = widget.toDOM(view) as HTMLElement;
    f.scroll.replaceChildren(dom);
    await projection.prepare(Date.now() + 2000);
    const readingMain = f.document.getElementById("scholium-document");
    const selectedTextNode = readingMain!.querySelector("p")!.firstChild;
    const preparationAPI = f.window.scholiumReadPreparation;
    const reordered = Object.fromEntries(Object.entries({...initial.configuration,
      presentationCSS: ".scholium-document { --test-style: 1; }",
      localization: {strings: {Copy: "Copy", "Note title": "Note title"}, languageTag: "en"},
    }).reverse()) as unknown as typeof initial.configuration;
    expect(projection.updateInPlace({...initial, configuration: reordered})).toBe(true);
    await projection.prepare(Date.now() + 2000);
    const readingStyle = dom.querySelector<HTMLStyleElement>('[data-scholium-review-style="presentation"]')!;
    const readingUserStyle = dom.querySelector<HTMLStyleElement>('[data-scholium-review-style="user"]')!;
    expect(readingStyle.textContent).toContain("@scope (.scholium-review-projection)");
    expect(readingStyle.textContent).toContain("--test-style: 1");
    expect(readingUserStyle.textContent).toContain(initial.configuration.userCSS);
    expect(f.host.presentationStyle.textContent).toBe(":root { --edit-presentation: 1; }");
    expect(f.host.userStyle.textContent).toBe(".cm-content { --edit-user: 1; }");
    expect(f.document.getElementById("scholium-document")).toBe(readingMain);
    expect(readingMain!.querySelector("p")!.firstChild).toBe(selectedTextNode);
    expect(selectedTextNode!.isConnected).toBe(true);
    expect(f.window.scholiumReadPreparation).toBe(preparationAPI);
    expect(f.postMessage.mock.calls.filter(([message]) => message.type === "ready")).toHaveLength(1);
    expect(projection.updateInPlace({...initial, configuration: {...reordered, loadGeneration: reordered.loadGeneration + 1}})).toBe(false);
    widget.destroy(dom);
  });

  it("requests no math runtime for protected content outside the hosted document", async () => {
    const f = fixture();
    await initializeReader(f.config, f.host);
    expect(f.postMessage.mock.calls.some(([message]) => message.type === "requestMathRuntime")).toBe(false);
    expect(f.document.querySelector("#outside .scholium-math")?.classList.contains("scholium-math-rendered")).toBe(false);
    f.signal.abort();
  });
});
