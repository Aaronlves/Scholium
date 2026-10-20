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

function fixture() {
  const {document, window} = parseHTML('<html><head><style id="presentation"></style><style id="user"></style></head><body><div id="outside"><p>Outside</p><div class="scholium-math" data-math-source="eA==" data-math-kind="inline"></div></div><div id="scroll"><main id="scholium-document"><p data-source-line="1" data-source-utf16-start="0" data-source-utf16-end="4">Body</p></main></div><aside id="popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside></body></html>');
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
    const f = fixture();
    Object.defineProperty(f.document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
    const source = "\uFEFFFirst.\r\n\r\nMiddle 😀 paragraph.\r\n\r\nLast.\r\n";
    const mirror = new ExactSourceMirror(source);
    const lower = source.indexOf("Middle"), upper = source.indexOf("\r\n\r\nLast");
    const committed: CommittedReviewProjection = {documentID: "editor-document", sourceFingerprint: "fingerprint",
      htmlBody: `<main id="scholium-document"><p data-source-line="1" data-source-utf16-start="0" data-source-utf16-end="7">First.</p><p class="middle" data-source-line="3" data-source-utf16-start="${lower}" data-source-utf16-end="${upper}">Middle 😀 paragraph.</p><p data-source-line="5" data-source-utf16-start="${source.indexOf("Last")}" data-source-utf16-end="${source.length - 2}">Last.</p></main><aside id="scholium-preview-popover"><h2 class="scholium-preview-title"></h2><p class="scholium-preview-metadata"></p><div class="scholium-preview-body"></div></aside>`,
      css: "", configuration: {...f.config, version: 8}};
    const projection = createCommittedReviewProjection({projection: () => committed, mirror: () => mirror,
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
    const projection = createCommittedReviewProjection({projection: () => initial, mirror: () => new ExactSourceMirror("Plain body"),
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
