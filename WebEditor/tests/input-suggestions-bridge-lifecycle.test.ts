import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {EDITOR_PROTOCOL_VERSION, type EditorCommandResult, type EditorPresentationConfiguration,
  type EditorRequest, type MarkdownEditingDialect} from "../protocol";
import type {NativeFloatingEvent, NativeSuggestionSurface} from "../native-floating";
import {installConstructableStylesheet} from "./stylesheet-fixture";

type Message = {type: string; event?: NativeFloatingEvent; requestID?: string; resultingGeneration?: number; [key: string]: unknown};
interface RuntimeWindow extends Window {
  Event: typeof Event;
  scholiumEditor: {
    dispatch(request: EditorRequest): Promise<EditorCommandResult>;
    resolveLinkCompletionQuery(requestID: string, value: unknown): void;
  };
  scholiumNativeFloatingEvent(id: number, action: string, index: number): boolean;
}
const dialect: MarkdownEditingDialect = {
  version: 6, callouts: [{identifier: "state", label: "Statement", meaning: "Claim"}],
  linkAnnotation: {openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\", allowsMultiline: true, allowsNesting: false},
  footnotes: {namedReferenceOpening: "[^", namedReferenceClosing: "]", definitionSeparator: ":", inlineOpening: "^[",
    continuationIndentSpaces: 2, allowsTabContinuation: true, caseSensitiveIdentifiers: true, ordinalByFirstReference: true},
  mathematics: {inlineDelimiter: "$", displayDelimiter: "$$", singleDollarInline: true},
};
const presentation = (index = ""): EditorPresentationConfiguration => ({
  documentTitle: "Synthetic Note", presentationCSS: "", userCSS: "", linkPreviews: [], linkPreviewGeneration: 0,
  imageResources: {}, imageResourceGeneration: 0, writingContinuationEnabled: false,
  writingContinuationContextKey: "", writingIndexContextKey: index,
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.useRealTimers(); });

// Real editor.ts, CodeMirror transactions, content reporter and native ports.
// Linkedom substitutes layout/focus services; this is not physical typing, IME,
// native presentation, persistence, or derived-index acceptance.
async function runtime() {
  vi.resetModules(); vi.useFakeTimers();
  const {document, window} = parseHTML('<html><head><style id="scholium-presentation-css"></style><style id="scholium-user-css"></style></head><body><div id="editor"></div></body></html>');
  vi.stubGlobal("document", document); vi.stubGlobal("window", window);
  vi.stubGlobal("Window", class { static [Symbol.hasInstance](value: unknown) { return value === window; } });
  for (const name of ["MutationObserver", "HTMLElement", "Element", "Node", "HTMLImageElement"] as const) vi.stubGlobal(name, window[name]);
  vi.stubGlobal("requestAnimationFrame", () => 1); vi.stubGlobal("cancelAnimationFrame", () => {});
  vi.stubGlobal("matchMedia", () => ({matches: false, addEventListener() {}, removeEventListener() {}}));
  vi.stubGlobal("getComputedStyle", () => ({display: "block", visibility: "visible", direction: "ltr", getPropertyValue: () => ""}));
  vi.stubGlobal("ResizeObserver", class { observe() {} unobserve() {} disconnect() {} });
  vi.stubGlobal("CSS", {escape: (value: string) => value});
  let focused = false;
  let content: HTMLElement | null = null;
  let focusTarget: HTMLElement | null = null;
  Object.defineProperty(document, "getSelection", {value: () => null});
  Object.defineProperty(document, "hasFocus", {value: () => focused});
  Object.defineProperty(document, "activeElement", {get: () => focused ? focusTarget ?? content : null});
  Object.defineProperty(document, "fonts", {value: {status: "loaded", ready: Promise.resolve()}});
  const messages: Message[] = [];
  Object.defineProperty(window, "webkit", {configurable: true, value: {messageHandlers: {scholium: {
    postMessage(message: Message) { messages.push(message); },
  }}}});
  window.getSelection = () => null;
  installConstructableStylesheet(document);
  await import("../editor");
  const {EditorView, runScopeHandlers} = await import("@codemirror/view");
  const {Transaction} = await import("@codemirror/state");
  const completions = await import("@codemirror/autocomplete");
  const commands = await import("@codemirror/commands");
  const view = EditorView.findFromDOM(document.querySelector(".cm-editor")!)!;
  const api = (window as unknown as RuntimeWindow).scholiumEditor;
  content = view.contentDOM;
  Object.defineProperty(view.scrollDOM, "scrollHeight", {value: 1200});
  Object.defineProperty(view.scrollDOM, "clientHeight", {value: 400});
  view.scrollDOM.scrollTop = 0; view.scrollDOM.scrollLeft = 0; view.scrollDOM.scrollTo = vi.fn();
  vi.spyOn(view, "coordsAtPos").mockReturnValue({left: 10, right: 20, top: 40, bottom: 60});
  const rect = {left: 10, right: 20, top: 40, bottom: 60, width: 10, height: 20} as DOMRect;
  document.createRange = (() => ({setStart() {}, setEnd() {}, collapse() {}, selectNodeContents() {},
    getBoundingClientRect: () => rect, getClientRects: () => [rect]})) as unknown as typeof document.createRange;
  let documentID = "synthetic";
  const count = (type: string) => messages.filter(message => message.type === type).length;
  const generation = () => messages.filter(message => message.type === "documentChanged").at(-1)?.resultingGeneration ?? 0;
  const request = (operation: EditorRequest["operation"]): EditorRequest => ({
    protocolVersion: EDITOR_PROTOCOL_VERSION, requestID: crypto.randomUUID(), expiresAt: Date.now() + 2000,
    sessionID: "session", documentID, startingFingerprint: "fingerprint", knownGeneration: operation.type === "initialize" ? 0 : generation(), operation,
  });
  const settle = () => vi.advanceTimersByTimeAsync(200);
  async function initialize(text = "", name = "synthetic") {
    documentID = name;
    const result = await api.dispatch(request({type: "initialize", text, mode: "livePreview", dialect,
      initialSelection: {anchor: text.length, head: text.length}, presentation: presentation()}));
    expect(result.accepted, result.error).toBe(true);
    focused = true; focusTarget = null;
    await settle(); messages.length = 0;
  }
  const edit = (insert: string, from = view.state.selection.main.head, to = from, event = "input.type") =>
    view.dispatch({changes: {from, to, insert}, selection: {anchor: from + insert.length}, annotations: Transaction.userEvent.of(event)});
  function surface(): NativeSuggestionSurface {
    const message = messages.filter(message => message.type === "floatingSurface" && message.event?.type === "suggestionSurface").at(-1);
    expect(message?.event?.type).toBe("suggestionSurface");
    return (message!.event as {type: "suggestionSurface"; surface: NativeSuggestionSurface}).surface;
  }
  function domEvent(type: string) {
    const event = new window.Event(type);
    view.contentDOM.dispatchEvent(event);
  }
  return {api, view, window: window as unknown as RuntimeWindow, messages, count, request, initialize, edit, settle, surface, domEvent,
    setFocus(value: boolean) { focused = value; focusTarget = null; },
    setFocusedElement(value: HTMLElement) { focused = true; focusTarget = value; }, completions, commands,
    advance: (milliseconds: number) => vi.advanceTimersByTimeAsync(milliseconds),
    escape() { return runScopeHandlers(view, {key: "Escape", keyCode: 27, altKey: false, ctrlKey: false, shiftKey: false, metaKey: false,
      preventDefault() {}, stopPropagation() {}} as KeyboardEvent, "editor"); },
    destroy() { focused = false; view.destroy(); },
  };
}

const available = (label: string) => ({label, insertion: label, displayText: label, detail: "Synthetic source", availability: "available"});

describe("Suggestion lifecycle through the full editor content reporter", () => {
  it.each([
    {action: "choose", freshLabel: "Other"}, {action: "select", freshLabel: "Other"},
    {action: "choose", freshLabel: "Kerr"}, {action: "select", freshLabel: "Kerr"},
  ] as const)("binds native $action to the displayed result set before publishing fresh $freshLabel rows", async ({action, freshLabel}) => {
    const f = await runtime();
    try {
      await f.initialize(); f.edit("@"); await f.settle();
      const initialQuery = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
      f.api.resolveLinkCompletionQuery(initialQuery.requestID!, [available("Kerr")]); await f.settle();
      const oldSurface = f.surface();
      const oldIndex = oldSurface.items.findIndex(item => item.label === "Kerr");
      expect(oldIndex).toBeGreaterThanOrEqual(0);
      const beforeSelection = f.view.state.selection;
      const beforeHistory = f.commands.undoDepth(f.view.state);
      const refreshed = await f.api.dispatch(f.request({type: "setPresentation", value: presentation("replacement-catalog")}));
      expect(refreshed.accepted, refreshed.error).toBe(true);
      // Start the documented explicit query delay, then drain only provider
      // microtasks. RAF is held by this fixture, and native's 50ms fallback has
      // not run: CM has new rows while the real native port still owns old rows.
      await f.advance(50);
      const freshQuery = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
      expect(freshQuery.requestID).not.toBe(initialQuery.requestID);
      const insertion = freshLabel === "Kerr" ? "People/Kerr" : freshLabel;
      f.api.resolveLinkCompletionQuery(freshQuery.requestID!, [{...available(freshLabel), insertion}]);
      await f.advance(0);
      const freshIndex = f.completions.currentCompletions(f.view.state).findIndex(item => item.label === freshLabel);
      expect(freshIndex).toBeGreaterThanOrEqual(0);
      expect(f.surface().id).toBe(oldSurface.id);
      expect(f.surface().items[oldIndex].label).toBe("Kerr");
      const selectedBeforeCallback = f.completions.selectedCompletionIndex(f.view.state);
      const accepted = f.window.scholiumNativeFloatingEvent(oldSurface.id, action, oldIndex);
      expect(f.view.state.doc.toString(), "An old visible row must never insert a newly ranked target").toBe("@");
      expect(f.completions.selectedCompletionIndex(f.view.state)).toBe(selectedBeforeCallback);
      if (action === "choose") expect(accepted).toBe(false);
      expect(f.view.state.selection.eq(beforeSelection)).toBe(true);
      expect(f.commands.undoDepth(f.view.state)).toBe(beforeHistory);
      expect(f.count("documentChanged")).toBe(1);

      await f.settle();
      const freshSurface = f.surface();
      expect(freshSurface.id).not.toBe(oldSurface.id);
      expect(f.window.scholiumNativeFloatingEvent(oldSurface.id, "choose", oldIndex)).toBe(false);
      const visibleIndex = freshSurface.items.findIndex(item => item.label === freshLabel);
      expect(visibleIndex).toBeGreaterThanOrEqual(0);
      expect(f.window.scholiumNativeFloatingEvent(freshSurface.id, "choose", visibleIndex)).toBe(true); await f.settle();
      const expected = insertion === freshLabel ? `[[${insertion}]]` : `[[${insertion}|${freshLabel}]]`;
      expect(f.view.state.doc.toString()).toBe(expected);
      expect(f.count("documentChanged")).toBe(2);
      expect(f.commands.undo(f.view)).toBe(true);
      expect(f.view.state.doc.toString()).toBe("@");
      expect(f.commands.redo(f.view)).toBe(true);
      expect(f.view.state.doc.toString()).toBe(expected);
    } finally { f.destroy(); }
  });

  it("refreshes a changed catalog without dismissing or remounting the active native suggestion list", async () => {
    const f = await runtime();
    const lifetimes = {mounted: 0, removed: 0};
    const countPopup = (node: Node) => {
      if (!(node instanceof Element)) return 0;
      return Number(node.matches(".cm-tooltip-autocomplete")) + node.querySelectorAll(".cm-tooltip-autocomplete").length;
    };
    const observer = new MutationObserver(records => {
      for (const record of records) {
        for (const node of record.addedNodes) lifetimes.mounted += countPopup(node);
        for (const node of record.removedNodes) lifetimes.removed += countPopup(node);
      }
    });
    try {
      await f.initialize(); f.edit("@"); await f.settle();
      const initialQuery = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
      f.api.resolveLinkCompletionQuery(initialQuery.requestID!, [available("Alison"), available("Kerr")]);
      await f.settle();
      const list = f.window.document.querySelector(".cm-tooltip-autocomplete");
      expect(list).not.toBeNull();
      const selected = f.completions.currentCompletions(f.view.state)[f.completions.selectedCompletionIndex(f.view.state)!];
      expect(selected.label).toBe("Insert Citation…");
      const source = f.view.state.doc.toString();
      const selection = f.view.state.selection;
      const dismissals = () => f.messages.filter(message => message.type === "floatingSurface"
        && message.event?.type === "dismissSurface" && message.event.kind === "suggestions").length;
      const beforeDismissals = dismissals();
      observer.observe(f.window.document.body, {childList: true, subtree: true});

      const same = await f.api.dispatch(f.request({type: "setPresentation", value: presentation()}));
      expect(same.accepted, same.error).toBe(true); await f.settle();
      expect(f.count("linkCompletionQuery")).toBe(1);
      expect(f.window.document.querySelector(".cm-tooltip-autocomplete")).toBe(list);
      expect(dismissals()).toBe(beforeDismissals);
      expect(lifetimes).toEqual({mounted: 0, removed: 0});

      const changed = await f.api.dispatch(f.request({type: "setPresentation", value: presentation("new-catalog")}));
      expect(changed.accepted, changed.error).toBe(true); await f.settle();
      expect(f.count("linkCompletionQuery")).toBe(2);
      expect(dismissals() - beforeDismissals, "catalog refresh must not dismiss the visible native popup").toBe(0);
      expect(lifetimes, "catalog refresh must retain the CodeMirror list lifetime").toEqual({mounted: 0, removed: 0});
      expect(f.window.document.querySelector(".cm-tooltip-autocomplete")).toBe(list);
      expect(f.view.state.doc.toString()).toBe(source);
      expect(f.view.state.selection.eq(selection)).toBe(true);
      expect(f.view.root.activeElement).toBe(f.view.contentDOM);
      expect(f.count("documentChanged")).toBe(1);
      const query = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
      f.api.resolveLinkCompletionQuery(query.requestID!, [available("Fresh")]); await f.settle();
      expect(f.completions.currentCompletions(f.view.state).map(option => option.label)).toContain("Fresh");
      expect(dismissals() - beforeDismissals).toBe(0);
      expect(f.window.document.querySelector(".cm-tooltip-autocomplete")).toBe(list);
    } finally { observer.disconnect(); f.destroy(); }
  });
  it("keeps a lone at-sign popup alive across repeated catalogs while rejecting obsolete native, Enter and click choices", async () => {
    const f = await runtime();
    try {
      await f.initialize(); f.edit("@"); await f.settle();
      const initialQuery = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
      f.api.resolveLinkCompletionQuery(initialQuery.requestID!, [available("Kerr")]); await f.settle();
      const noteIndex = f.completions.currentCompletions(f.view.state).findIndex(option => option.label === "Kerr");
      expect(noteIndex).toBeGreaterThanOrEqual(0);
      expect(f.window.scholiumNativeFloatingEvent(f.surface().id, "select", noteIndex)).toBe(true); await f.settle();
      const popup = f.window.document.querySelector(".cm-tooltip-autocomplete")!;
      const selectedOption = popup.querySelector<HTMLElement>("[aria-selected=true]")!;
      expect(selectedOption.textContent).toContain("Kerr");
      const previousSurface = f.surface();
      const selection = f.view.state.selection;
      const beforeDismissals = f.messages.filter(message => message.type === "floatingSurface"
        && message.event?.type === "dismissSurface" && message.event.kind === "suggestions").length;
      const obsoleteQueries: Message[] = [];
      for (let revision = 1; revision <= 4; revision++) {
        const result = await f.api.dispatch(f.request({type: "setPresentation", value: presentation(`catalog-${revision}`)}));
        expect(result.accepted, result.error).toBe(true);
        if (revision === 1) {
          expect(f.completions.completionStatus(f.view.state)).toBe("pending");
          expect(popup.querySelector("[aria-selected=true]")).toBe(selectedOption);
          expect(f.window.scholiumNativeFloatingEvent(previousSurface.id, "choose", noteIndex)).toBe(false);
          // acceptCompletion is CodeMirror's Enter command. Its disabled pending
          // dialog also rejects a click through the actual tooltip handler.
          expect(f.completions.acceptCompletion(f.view)).toBe(false);
          selectedOption.dispatchEvent(new f.window.Event("mousedown", {bubbles: true, cancelable: true}));
          expect(f.view.state.doc.toString()).toBe("@");
        }
        await f.settle();
        expect(f.count("linkCompletionQuery")).toBe(revision + 1);
        const latest = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
        obsoleteQueries.push(latest);
        const same = await f.api.dispatch(f.request({type: "setPresentation", value: presentation(`catalog-${revision}`)}));
        expect(same.accepted, same.error).toBe(true); await f.settle();
        expect(f.count("linkCompletionQuery")).toBe(revision + 1);
        expect(f.window.document.querySelector(".cm-tooltip-autocomplete")).toBe(popup);
        expect(f.messages.filter(message => message.type === "floatingSurface"
          && message.event?.type === "dismissSurface" && message.event.kind === "suggestions")).toHaveLength(beforeDismissals);
        expect(f.view.state.doc.toString()).toBe("@");
        expect(f.view.state.selection.eq(selection)).toBe(true);
        expect(f.view.root.activeElement).toBe(f.view.contentDOM);
      }
      for (const stale of obsoleteQueries.slice(0, -1)) f.api.resolveLinkCompletionQuery(stale.requestID!, [available("Obsolete")]);
      await f.settle();
      expect(f.completions.currentCompletions(f.view.state).some(option => option.label === "Obsolete")).toBe(false);
      const last = obsoleteQueries.at(-1)!;
      f.api.resolveLinkCompletionQuery(last.requestID!, [{...available("Unavailable"), insertion: "", availability: "unavailable", unavailableReason: "Synthetic target is missing"}]);
      await f.settle();
      const unavailable = f.completions.currentCompletions(f.view.state).findIndex(option => option.label === "Unavailable");
      expect(unavailable).toBeGreaterThanOrEqual(0);
      expect(f.surface().items[unavailable].disabled).toBe(true);
      expect(f.window.scholiumNativeFloatingEvent(f.surface().id, "choose", unavailable)).toBe(false);
      expect(f.count("documentChanged")).toBe(1);
      expect(f.escape()).toBe(true); await f.settle();
      expect(f.completions.completionStatus(f.view.state)).toBeNull();
      expect(f.window.document.querySelector(".cm-tooltip-autocomplete")).toBeNull();
      const dismissed = f.messages.filter(message => message.type === "floatingSurface"
        && message.event?.type === "dismissSurface" && message.event.kind === "suggestions").length;
      expect(dismissed - beforeDismissals).toBe(1);
      const afterEscape = await f.api.dispatch(f.request({type: "setPresentation", value: presentation("after-escape")}));
      expect(afterEscape.accepted, afterEscape.error).toBe(true); await f.settle();
      expect(f.count("linkCompletionQuery")).toBe(5);
      expect(f.window.document.querySelector(".cm-tooltip-autocomplete")).toBeNull();
      expect(f.view.state.doc.toString()).toBe("@");
    } finally { f.destroy(); }
  });

  it("does not restart a dismissed completion during programmed composition or after a note change", async () => {
    const f = await runtime();
    try {
      await f.initialize(); f.edit("@"); await f.settle();
      const initial = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
      f.api.resolveLinkCompletionQuery(initial.requestID!, [available("Kerr")]); await f.settle();
      // First establish a real popup, then leave its replacement query pending
      // across composition instead of assuming an unresolved query is visible.
      const refresh = await f.api.dispatch(f.request({type: "setPresentation", value: presentation("before-composition")}));
      expect(refresh.accepted, refresh.error).toBe(true); await f.settle();
      const old = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
      const beforeComposition = f.surface();
      f.domEvent("compositionstart"); await f.settle();
      const publications = () => f.messages.filter(message => message.type === "floatingSurface"
        && message.event?.type === "suggestionSurface").length;
      const beforePublications = publications();
      const beforeQueries = f.count("linkCompletionQuery");
      // Presentation requests intentionally defer while marked text is active.
      const pendingPresentation = f.api.dispatch(f.request({type: "setPresentation", value: presentation("composition-catalog")}));
      await f.settle();
      expect(f.count("linkCompletionQuery")).toBe(beforeQueries);
      f.api.resolveLinkCompletionQuery(old.requestID!, [available("Late")]); await f.settle();
      // Cached CM candidates may settle while composition owns input, but must
      // neither republish the native popup nor accept its departed callbacks.
      expect(publications()).toBe(beforePublications);
      expect(f.window.scholiumNativeFloatingEvent(beforeComposition.id, "choose", 0)).toBe(false);
      expect(f.count("documentChanged")).toBe(1);
      f.edit("自由", 0, 1, "input.type.compose"); f.domEvent("compositionend"); await f.settle();
      const result = await pendingPresentation;
      expect(result.accepted, result.error).toBe(true);
      expect(f.view.state.doc.toString()).toBe("自由");
      expect(f.count("documentChanged")).toBe(2);
      await f.initialize("Different note", "different");
      f.api.resolveLinkCompletionQuery(old.requestID!, [available("Late")]); await f.settle();
      expect(f.view.state.doc.toString()).toBe("Different note");
      expect(f.window.document.querySelector(".cm-tooltip-autocomplete")).toBeNull();
      expect(f.count("documentChanged")).toBe(0);
    } finally { f.destroy(); }
  });

  it("emits exactly one content delta per ordinary, deletion, paste, slash and at-sign edit", async () => {
    const f = await runtime();
    try {
      for (const action of ["letter", "backspace", "paste", "slash", "at"] as const) {
        await f.initialize(action === "backspace" ? "x" : "", action);
        if (action === "paste") {
          const result = await f.api.dispatch(f.request({type: "pasteClipboard", plainText: "ordinary text", selections: [{anchor: 0, head: 0}]}));
          expect(result.accepted, result.error).toBe(true);
        } else if (action === "backspace") f.edit("", 0, 1, "delete.backward");
        else f.edit(action === "letter" ? "x" : action === "slash" ? "/" : "@");
        await f.settle();
        expect(f.count("documentChanged"), action).toBe(1);
        expect(f.count("interactionChanged"), action).toBeGreaterThan(0);
        expect(f.messages.filter(message => message.type === "documentChanged").map(message => message.resultingGeneration)).toEqual([1]);
      }
    } finally { f.destroy(); }
  });

  it("keeps popup open, highlight, dismissal, Escape and blur source-neutral, with one extra delta for acceptance", async () => {
    const f = await runtime();
    try {
      await f.initialize(); f.edit("/"); await f.settle();
      expect(f.count("documentChanged")).toBe(1);
      const first = f.surface();
      expect(f.window.scholiumNativeFloatingEvent(first.id, "select", 1)).toBe(true);
      await f.settle(); expect(f.count("documentChanged")).toBe(1);
      expect(f.window.scholiumNativeFloatingEvent(first.id, "choose", 0)).toBe(false);
      expect(f.window.scholiumNativeFloatingEvent(f.surface().id, "dismiss", 0)).toBe(true);
      await f.settle(); expect(f.count("documentChanged")).toBe(1);
      f.completions.startCompletion(f.view); await f.settle();
      expect(f.escape()).toBe(true); await f.settle();
      expect(f.completions.completionStatus(f.view.state)).toBeNull();
      expect(f.count("documentChanged")).toBe(1);
      f.completions.startCompletion(f.view); await f.settle();
      const beforeCaret = f.surface();
      f.view.dispatch({selection: {anchor: 0}}); await f.settle();
      expect(f.count("documentChanged")).toBe(1);
      expect(f.window.scholiumNativeFloatingEvent(beforeCaret.id, "choose", 0)).toBe(false);
      f.view.dispatch({selection: {anchor: f.view.state.doc.length}});
      f.completions.startCompletion(f.view); await f.settle();
      const beforeBlur = f.surface(); f.setFocus(false); f.domEvent("blur"); await f.settle();
      expect(f.count("documentChanged")).toBe(1);
      expect(f.window.scholiumNativeFloatingEvent(beforeBlur.id, "choose", 0)).toBe(false);
      f.setFocus(true); f.completions.startCompletion(f.view); await f.settle();
      const index = f.completions.currentCompletions(f.view.state).findIndex(option => option.label === "Date");
      expect(index).toBeGreaterThanOrEqual(0);
      expect(f.window.scholiumNativeFloatingEvent(f.surface().id, "choose", index)).toBe(true);
      await f.settle(); expect(f.count("documentChanged")).toBe(2);
      expect(f.view.state.doc.toString()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    } finally { f.destroy(); }
  });

  it("emits one additional content delta when an at-sign Note candidate is accepted", async () => {
    const f = await runtime();
    try {
      await f.initialize(); f.edit("@"); await f.settle();
      const query = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
      f.api.resolveLinkCompletionQuery(query.requestID!, [available("Alison Duncan Kerr")]); await f.settle();
      expect(f.count("documentChanged")).toBe(1);
      const index = f.completions.currentCompletions(f.view.state).findIndex(option => option.label === "Alison Duncan Kerr");
      expect(index).toBeGreaterThanOrEqual(0);
      expect(f.window.scholiumNativeFloatingEvent(f.surface().id, "choose", index)).toBe(true);
      await f.settle();
      expect(f.count("documentChanged")).toBe(2);
      expect(f.view.state.doc.toString()).toBe("[[Alison Duncan Kerr]]");
      expect(f.messages.filter(message => message.type === "documentChanged").map(message => message.resultingGeneration)).toEqual([1, 2]);
    } finally { f.destroy(); }
  });

  it.each(["Enter", "blur"] as const)("keeps filename typing outside Markdown and retains the focused control through unrelated presentation/body changes until %s", async commit => {
    const f = await runtime();
    try {
      await f.initialize();
      const input = f.window.document.querySelector<HTMLTextAreaElement>(".scholium-note-title-input")!;
      expect(input).not.toBeNull();
      // Linkedom has no native textarea focus/selection service. Retain the real
      // mounted widget and handlers; DOM identity catches control replacement.
      input.setSelectionRange = (start, end) => { input.selectionStart = start ?? 0; input.selectionEnd = end ?? 0; };
      f.setFocusedElement(input);
      input.dispatchEvent(new f.window.Event("focus", {bubbles: true}));
      for (const value of ["N", "Ne", "New filename 自由"]) {
        input.value = value; input.setSelectionRange(2, 2);
        input.dispatchEvent(new f.window.Event("input", {bubbles: true})); await f.settle();
        expect(f.count("documentChanged")).toBe(0);
        expect(f.count("requestDocumentTitleRename")).toBe(0);
        expect(f.window.document.querySelector(".scholium-note-title-input")).toBe(input);
        expect(f.window.document.activeElement).toBe(input);
        expect(input.selectionStart).toBe(2);
      }
      for (const index of ["catalog-generatedAt-1", "catalog-generatedAt-2"]) {
        const result = await f.api.dispatch(f.request({type: "setPresentation", value: {...presentation(index), linkPreviewGeneration: 1}}));
        expect(result.accepted, result.error).toBe(true); await f.settle();
        expect(f.window.document.querySelector(".scholium-note-title-input")).toBe(input);
        expect(input.isConnected).toBe(true);
        expect(f.window.document.activeElement).toBe(input);
        expect(input.value).toBe("New filename 自由");
        expect([input.selectionStart, input.selectionEnd]).toEqual([2, 2]);
        expect(f.count("requestDocumentTitleRename")).toBe(0);
        expect(f.count("documentChanged")).toBe(0);
      }
      f.edit("Body changes independently.", 0); await f.settle();
      expect(f.count("documentChanged")).toBe(1);
      expect(f.count("requestDocumentTitleRename")).toBe(0);
      expect(f.window.document.querySelector(".scholium-note-title-input")).toBe(input);
      expect(f.window.document.activeElement).toBe(input);
      expect(input.value).toBe("New filename 自由");
      expect([input.selectionStart, input.selectionEnd]).toEqual([2, 2]);
      const committedBody = f.view.state.doc.toString();
      const committedFingerprint = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(committedBody)))]
        .map(byte => byte.toString(16).padStart(2, "0")).join("");
      const acknowledged = await f.api.dispatch(f.request({type: "acknowledgeCommittedSnapshot",
        expectedText: committedBody, committedText: committedBody, committedFingerprint}));
      expect(acknowledged.accepted, acknowledged.error).toBe(true); await f.settle();
      expect(f.window.document.querySelector(".scholium-note-title-input")).toBe(input);
      expect(input.isConnected).toBe(true);
      expect(f.window.document.activeElement).toBe(input);
      expect(input.value).toBe("New filename 自由");
      expect([input.selectionStart, input.selectionEnd]).toEqual([2, 2]);
      expect(f.count("requestDocumentTitleRename")).toBe(0);
      expect(f.count("documentChanged")).toBe(1);
      // No further fixture-native request uses its initial fingerprint. The
      // title's DOM commit below must carry the runtime's advanced disk base.
      const event = new f.window.Event(commit === "Enter" ? "keydown" : "blur", {bubbles: true, cancelable: true});
      if (commit === "Enter") Object.defineProperty(event, "key", {value: "Enter"});
      input.dispatchEvent(event); await f.settle();
      const rename = f.messages.filter(message => message.type === "requestDocumentTitleRename");
      expect(rename).toHaveLength(1);
      expect(rename[0]).toMatchObject({expectedTitle: "Synthetic Note", requestedTitle: "New filename 自由", startingFingerprint: committedFingerprint});
      expect(f.count("documentChanged")).toBe(1);
      expect(f.view.state.doc.toString()).toBe("Body changes independently.");
    } finally { f.destroy(); }
  });

  it("keeps programmed title composition and Escape cancellation outside source and rename", async () => {
    const f = await runtime();
    try {
      await f.initialize("Existing body");
      const input = f.window.document.querySelector<HTMLTextAreaElement>(".scholium-note-title-input")!;
      f.setFocusedElement(input);
      input.dispatchEvent(new f.window.Event("focus", {bubbles: true}));
      input.dispatchEvent(new f.window.Event("compositionstart", {bubbles: true}));
      input.value = "自由标题";
      input.dispatchEvent(new f.window.Event("input", {bubbles: true}));
      const enter = new f.window.Event("keydown", {bubbles: true, cancelable: true});
      Object.defineProperty(enter, "key", {value: "Enter"});
      input.dispatchEvent(enter); await f.settle();
      expect(f.count("documentChanged")).toBe(0);
      expect(f.count("requestDocumentTitleRename")).toBe(0);
      input.dispatchEvent(new f.window.Event("compositionend", {bubbles: true})); await f.settle();
      expect(f.count("requestDocumentTitleRename")).toBe(0);
      input.blur = () => {
        f.setFocus(false);
        input.dispatchEvent(new f.window.Event("blur", {bubbles: true}));
      };
      const escape = new f.window.Event("keydown", {bubbles: true, cancelable: true});
      Object.defineProperty(escape, "key", {value: "Escape"});
      input.dispatchEvent(escape); await f.settle();
      expect(input.value).toBe("Synthetic Note");
      expect(f.count("requestDocumentTitleRename")).toBe(0);
      expect(f.count("documentChanged")).toBe(0);
      expect(f.view.state.doc.toString()).toBe("Existing body");
    } finally { f.destroy(); }
  });

  it("requeries without source writes and rejects late replies after note change; programmed composition reports only its real edit", async () => {
    const f = await runtime();
    try {
      await f.initialize(); f.edit("@"); await f.settle();
      const old = f.messages.filter(message => message.type === "linkCompletionQuery").at(-1)!;
      expect(old.requestID).toBeTypeOf("string");
      const interactionBefore = f.count("interactionChanged");
      const result = await f.api.dispatch(f.request({type: "setPresentation", value: presentation("changed-catalog")}));
      expect(result.accepted, result.error).toBe(true); await f.settle();
      const queries = f.messages.filter(message => message.type === "linkCompletionQuery");
      expect(queries).toHaveLength(2);
      expect(f.count("interactionChanged")).toBe(interactionBefore);
      expect(f.count("documentChanged")).toBe(1);
      f.api.resolveLinkCompletionQuery(old.requestID!, [available("Obsolete")]); await f.settle();
      expect(f.count("documentChanged")).toBe(1);
      expect(f.completions.currentCompletions(f.view.state).every(option => option.label !== "Obsolete")).toBe(true);
      const latest = queries.at(-1)!;
      await f.initialize("Other source", "other-note");
      f.api.resolveLinkCompletionQuery(latest.requestID!, [available("Late")]); await f.settle();
      expect(f.count("documentChanged")).toBe(0);
      expect(f.view.state.doc.toString()).toBe("Other source");
      expect(f.completions.currentCompletions(f.view.state)).toEqual([]);
      await f.initialize(); f.edit("@"); await f.settle();
      f.domEvent("compositionstart"); await f.settle();
      expect(f.count("documentChanged")).toBe(1);
      f.edit("自由", 0, 1, "input.type.compose"); await f.settle();
      expect(f.count("documentChanged")).toBe(2);
      f.domEvent("compositionend"); await f.settle();
      expect(f.count("documentChanged")).toBe(2);
      expect(f.view.state.doc.toString()).toBe("自由");
    } finally { f.destroy(); }
  });
});
