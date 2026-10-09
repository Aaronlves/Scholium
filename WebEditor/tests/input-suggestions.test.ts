import {
  CompletionContext,
  type CompletionResult,
  type CompletionSource,
} from "@codemirror/autocomplete";
import {EditorSelection, EditorState, StateEffect, Transaction, type Extension, type TransactionSpec} from "@codemirror/state";
import {EditorView, type DecorationSet, type WidgetType} from "@codemirror/view";
import {history, undo, undoDepth} from "@codemirror/commands";
import {parseHTML} from "linkedom";
import {describe, expect, it, vi} from "vitest";
import {
  createEditorInputSuggestions,
  inputSuggestionTesting,
  safeContinuationSuffix,
  type EditorCitationSuggestionIntent,
  type EditorInputSuggestionActionCompletion,
} from "../input-suggestions";
import type {EditorMode, MarkdownEditingDialect} from "../protocol";
import {exactSourceHistory, exactSourceState, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";
import type {NativeSuggestionPort} from "../native-floating";

function inlineContinuationHarness(source = "A claim about res", options: {
  composing?: boolean; protectedRanges?: readonly {from: number; to: number}[]; multipleSelections?: boolean;
  mode?: EditorMode; readOnly?: boolean; editable?: boolean; aiEnabled?: boolean;
} = {}) {
  const requests: string[] = [], cancelled: string[] = [], terms: string[] = [], labels: string[] = [];
  let state = EditorState.create({doc: normalizedDocumentText(source),
    selection: options.multipleSelections ? EditorSelection.create([EditorSelection.cursor(0), EditorSelection.cursor(normalizedDocumentText(source).length)])
      : {anchor: normalizedDocumentText(source).length},
    extensions: [history(), exactSourceHistory, EditorState.allowMultipleSelections.of(true),
      ...(options.readOnly ? [EditorState.readOnly.of(true)] : []),
      ...(options.editable === false ? [EditorView.editable.of(false)] : [])]})
    .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
  const suggestions = createEditorInputSuggestions({
    nativeFloating: {show: () => 0, hide: () => {}}, mode: () => options.mode ?? "livePreview",
    dialect: () => dialect, isComposing: () => options.composing ?? false, protectedRanges: () => options.protectedRanges ?? [],
    requestLinkCompletions: id => { terms.push(id); },
    requestWritingContinuation: id => { requests.push(id); },
    cancelWritingContinuation: id => { cancelled.push(id); }, didApply: label => labels.push(label),
  });
  state = state.update({effects: StateEffect.appendConfig.of(suggestions.extension),
    annotations: Transaction.addToHistory.of(false)}).state;
  const view = {get state() {return state;}, composing: false, hasFocus: true,
    dispatch(spec: TransactionSpec) { state = state.update(spec).state; }} as unknown as EditorView;
  // A detached plugin exercises scheduling without pretending to establish WebKit input acceptance.
  const definition = (suggestions.extension as Extension[])[1] as unknown as {create(view: EditorView): {
    decorations: DecorationSet; schedule(): void; clear(): void; accept(): boolean;
  }};
  const plugin = definition.create(view);
  suggestions.configureWritingContinuation(options.aiEnabled ?? true, "model-a");
  plugin.schedule();
  return {suggestions, plugin, requests, cancelled, terms, labels, state: () => state, view};
}

function renderedInlineWidget(decorations: DecorationSet) {
  let widget: WidgetType | undefined;
  let side: number | undefined;
  decorations.between(0, Number.MAX_SAFE_INTEGER, (_from, _to, decoration) => {
    widget = decoration.spec.widget;
    side = decoration.spec.side;
  });
  expect(widget).toBeDefined();
  const {document} = parseHTML("<html><body></body></html>");
  vi.stubGlobal("document", document);
  try { return {node: widget!.toDOM({} as EditorView) as HTMLElement, side}; }
  finally { vi.unstubAllGlobals(); }
}

describe("AI-first inline continuation", () => {
  it("rejects a visible ghost as soon as composition starts before its first text change", async () => {
    vi.useFakeTimers();
    const options = {composing: false, aiEnabled: false};
    const h = inlineContinuationHarness("res", options);
    await vi.advanceTimersByTimeAsync(300);
    expect(h.terms).toHaveLength(1);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], [{label: "responsibility", insertion: "",
      detail: "", path: "term.md", isAmbiguous: false, writingAction: "term", replacementUTF16Count: 3}]);
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(1);
    options.composing = true;
    expect(h.view.composing).toBe(false);
    expect(h.plugin.accept()).toBe(false);
    expect(h.state().doc.toString()).toBe("res");
    h.plugin.clear();
    vi.useRealTimers();
  });
  it("requests only after an unfinished current sentence", async () => {
    vi.useFakeTimers();
    for (const source of ["A completed claim. ", "A completed claim。", "A completed claim.”"]) {
      const h = inlineContinuationHarness(source);
      await vi.advanceTimersByTimeAsync(1_200);
      expect(h.requests).toEqual([]);
      expect(h.terms).toEqual([]);
      h.plugin.clear();
    }
    const h = inlineContinuationHarness("Earlier claim. A claim about res");
    await vi.advanceTimersByTimeAsync(1_200);
    expect(h.requests).toHaveLength(1);
    vi.useRealTimers();
  });

  it("waits for AI without exposing or requesting local terms, and accepts one exact Undo event", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("\uFEFFFirst 😀.\r\nA claim about res");
    await vi.advanceTimersByTimeAsync(1_199);
    expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
    await vi.advanceTimersByTimeAsync(1);
    expect(h.requests).toHaveLength(1); expect(h.terms).toEqual([]);
    h.suggestions.configureWritingIndexContext("catalog-1");
    expect(h.cancelled).toEqual([]);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility needs qualification."});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(1);
    const ai = renderedInlineWidget(h.plugin.decorations);
    expect(ai.node.querySelector(".scholium-writing-ghost-key")?.textContent).toBe("AI ⇥");
    expect(ai.node.getAttribute("aria-label")).toContain("Accept AI continuation:");
    h.suggestions.configureWritingIndexContext("catalog-2");
    expect(h.plugin.decorations.size).toBe(1);
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().field(exactSourceState).text).toBe("\uFEFFFirst 😀.\r\nA claim about responsibility needs qualification.");
    expect(h.labels).toEqual(["Accept AI Continuation"]);
    expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
    expect(h.state().field(exactSourceState).text).toBe("\uFEFFFirst 😀.\r\nA claim about res");
    vi.useRealTimers();
  });

  it("shows composing progress and keeps a visible connection failure at the caret", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    await vi.advanceTimersByTimeAsync(1_200);
    expect(h.requests).toHaveLength(1);
    expect(h.plugin.decorations.size).toBe(1);
    h.suggestions.setWritingContinuationStatus(h.requests[0], {phase: "generating"});
    expect(h.plugin.decorations.size).toBe(1);
    expect(renderedInlineWidget(h.plugin.decorations).side).toBe(1);
    h.suggestions.resolveWritingContinuation(h.requests[0], {
      text: null, reason: "AI continuation could not connect. Check Agents & Chat.",
    });
    await vi.advanceTimersByTimeAsync(0);
    expect(h.terms).toHaveLength(1);
    expect(h.plugin.decorations.size).toBe(0);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], []);
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(1);
    expect(h.plugin.accept()).toBe(false);
    const error = renderedInlineWidget(h.plugin.decorations);
    expect(error.side).toBe(1);
    expect(error.node.textContent).toBe("!");
    expect(error.node.getAttribute("aria-label")).toBe("AI continuation could not connect. Check Agents & Chat.");
    expect(error.node.querySelectorAll(".scholium-writing-status-badge")).toHaveLength(1);
    vi.useRealTimers();
  });

  it("falls back after timeout and ignores the late AI response", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    await vi.advanceTimersByTimeAsync(9_200);
    expect(h.cancelled).toEqual(h.requests); expect(h.terms).toHaveLength(1);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], [{label: "responsibility", insertion: "", detail: "", path: "topic.md",
      isAmbiguous: false, writingAction: "term", replacementUTF16Count: 3}]);
    await vi.advanceTimersByTimeAsync(0);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: "different sentence."});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().doc.toString()).toBe("A claim about responsibility");
    vi.useRealTimers();
  });

  it("uses local term fallback in Source after AI failure", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("A claim about res", {mode: "source"});
    await vi.advanceTimersByTimeAsync(1_200);
    expect(h.requests).toHaveLength(1); expect(h.terms).toEqual([]);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: null, reason: "Offline"});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.terms).toHaveLength(1);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], [{label: "responsibility", insertion: "", detail: "", path: "topic.md",
      isAmbiguous: false, writingAction: "term", replacementUTF16Count: 3}]);
    await vi.advanceTimersByTimeAsync(0);
    const fallback = renderedInlineWidget(h.plugin.decorations);
    expect(fallback.node.querySelectorAll(".scholium-writing-status")).toHaveLength(0);
    expect(fallback.node.querySelectorAll(".scholium-writing-ghost-error-badge")).toHaveLength(1);
    expect(fallback.node.querySelector(".scholium-writing-ghost-key")?.textContent).toBe("Index ⇥");
    expect(fallback.node.getAttribute("aria-label")).toContain("Accept index suggestion:");
    expect(fallback.node.getAttribute("aria-description")).toBe("Offline");
    h.suggestions.configureWritingContinuation(true, "model-b");
    expect(h.plugin.decorations.size).toBe(1);
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().doc.toString()).toBe("A claim about responsibility");
    vi.useRealTimers();
  });

  it("uses the index when AI is off, with no AI request or failure badge", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("A claim about res", {aiEnabled: false});
    await vi.advanceTimersByTimeAsync(299);
    expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
    await vi.advanceTimersByTimeAsync(1);
    expect(h.terms).toHaveLength(1);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], [{label: "responsibility", insertion: "", detail: "", path: "topic.md",
      isAmbiguous: false, writingAction: "term", replacementUTF16Count: 3}]);
    await vi.advanceTimersByTimeAsync(0);
    const ghost = renderedInlineWidget(h.plugin.decorations);
    expect(ghost.node.querySelector(".scholium-writing-ghost-key")?.textContent).toBe("Index ⇥");
    expect(ghost.node.querySelector(".scholium-writing-ghost-error-badge")).toBeNull();
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().doc.toString()).toBe("A claim about responsibility");
    vi.useRealTimers();
  });

  it("keeps a quiet AI absence quiet through empty index fallback", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    await vi.advanceTimersByTimeAsync(1_200);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: null, reason: ""});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.terms).toHaveLength(1);
    expect(h.plugin.decorations.size).toBe(0);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], []);
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(0);
    expect(h.plugin.accept()).toBe(false);
    vi.useRealTimers();
  });

  it("discards an old index result on catalog change", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    await vi.advanceTimersByTimeAsync(1_200);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: null, reason: ""});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.terms).toHaveLength(1);
    h.suggestions.configureWritingIndexContext("catalog-2");
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], [{label: "responsibility", insertion: "", detail: "", path: "old.md",
      isAmbiguous: false, writingAction: "term", replacementUTF16Count: 3}]);
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(0);
    expect(h.plugin.accept()).toBe(false);
    vi.useRealTimers();
  });

  it("does not query or accept inline writing in read-only or noneditable states", async () => {
    vi.useFakeTimers();
    for (const options of [{readOnly: true}, {editable: false}]) {
      const h = inlineContinuationHarness("A claim about res", options);
      await vi.advanceTimersByTimeAsync(1_200);
      expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
      expect(h.suggestions.writingCompletionSource(new CompletionContext(h.state(), h.state().doc.length, false))).toBeNull();
      expect(h.plugin.accept()).toBe(false);
    }
    for (const extension of [EditorState.readOnly.of(true), EditorView.editable.of(false)]) {
      const h = inlineContinuationHarness();
      await vi.advanceTimersByTimeAsync(1_200);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponse."});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.decorations.size).toBe(1);
      h.view.dispatch({effects: StateEffect.appendConfig.of(extension)});
      expect(h.plugin.accept()).toBe(false);
      expect(h.state().doc.toString()).toBe("A claim about res");
      h.plugin.clear();
    }
    vi.useRealTimers();
  });

  it("cancels on dismissal and model change without falling back", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    await vi.advanceTimersByTimeAsync(1_200);
    h.plugin.clear();
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponse."});
    await vi.advanceTimersByTimeAsync(10_000);
    expect(h.terms).toEqual([]); expect(h.plugin.decorations.size).toBe(0);
    h.plugin.schedule(); await vi.advanceTimersByTimeAsync(1_200);
    h.suggestions.configureWritingContinuation(true, "model-b");
    h.suggestions.resolveWritingContinuation(h.requests[1], {text: "ponse."});
    await vi.advanceTimersByTimeAsync(10_000);
    expect(h.cancelled).toEqual(h.requests); expect(h.terms).toEqual([]);
    expect(h.plugin.decorations.size).toBe(0);
    vi.useRealTimers();
  });

  it("rejects multiline, hidden controls, Markdown structures and malformed UTF16", () => {
    for (const text of ["", " ", "a\nb", "a\u0085b", "a\u2028b", "a\u2029b", "a\u202eb", "[[note]]", "*claim*", "\ud800", "x".repeat(513), " first. second", "第一句。第二句"]) {
      expect(safeContinuationSuffix(text)).toBeNull();
    }
    expect(safeContinuationSuffix(" qualifies the claim 😀。" )).toBe(" qualifies the claim 😀。");
    expect(safeContinuationSuffix(" 👩‍🔬 می‌نویسد।")).toBe(" 👩‍🔬 می‌نویسد।");
  });

  it("does not request AI in composition, protected constructs, trigger menus or multiple selections", async () => {
    vi.useFakeTimers();
    for (const [source, options] of [
      ["A claim about res", {composing: true}],
      ["A claim about res", {protectedRanges: [{from: 0, to: 20}]}],
      ["A claim about res", {multipleSelections: true}],
      ["[[respons", {}], ["Claim @author", {}], ["Claim /table", {}],
    ] as const) {
      const h = inlineContinuationHarness(source, options);
      await vi.advanceTimersByTimeAsync(1_200);
      expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
      h.plugin.clear();
    }
    vi.useRealTimers();
  });
});

const dialect: MarkdownEditingDialect = {
  version: 6,
  callouts: [
    {identifier: "orient", label: "Orient", meaning: "Purpose and route."},
    {identifier: "state", label: "State", meaning: "A compact claim."},
  ],
  linkAnnotation: {
    openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\",
    allowsMultiline: true, allowsNesting: false,
  },
  footnotes: {
    namedReferenceOpening: "[^",
    namedReferenceClosing: "]",
    definitionSeparator: ":",
    inlineOpening: "^[",
    continuationIndentSpaces: 2,
    allowsTabContinuation: true,
    caseSensitiveIdentifiers: true,
    ordinalByFirstReference: true,
  },
  mathematics: {
    inlineDelimiter: "$",
    displayDelimiter: "$$",
    singleDollarInline: true,
  },
};

function controller(
  mode: EditorMode = "livePreview",
  protectedRanges: readonly {from: number; to: number}[] = [],
  composing = false,
) {
  let request: {id: string; kind: string; query: string} | null = null;
  const undoLabels: string[] = [];
  const suggestions = createEditorInputSuggestions({
    nativeFloating: {show: () => 0, hide: () => {}},
    mode: () => mode,
    dialect: () => dialect,
    isComposing: () => composing,
    protectedRanges: () => protectedRanges,
    requestLinkCompletions: (id, kind, query) => { request = {id, kind, query}; },
    didApply: (label) => { undoLabels.push(label); },
  });
  return {suggestions, request: () => request, undoLabels};
}

function synchronousResult(
  source: CompletionSource,
  text: string,
): CompletionResult | null {
  const state = EditorState.create({
    doc: text,
    selection: {anchor: text.length},
  });
  const result = source(new CompletionContext(state, text.length, false));
  expect(result).not.toBeInstanceOf(Promise);
  return result as CompletionResult | null;
}

function mutableView(initialState: EditorState) {
  let state = initialState;
  const view = {
    get state() { return state; },
    dispatch(...specs: (Transaction | TransactionSpec)[]) {
      if (specs.length === 1 && specs[0] instanceof Transaction) {
        state = specs[0].state;
      } else {
        state = state.update(...specs as TransactionSpec[]).state;
      }
    },
  } as unknown as EditorView;
  return {view, state: () => state};
}

function applyOption(source: CompletionSource, text: string, label: string) {
  const initialState = EditorState.create({doc: text, selection: {anchor: text.length}});
  const result = source(new CompletionContext(initialState, text.length, false)) as CompletionResult;
  const completion = result.options.find((option) => option.label === label)!;
  const mutable = mutableView(initialState);
  expect(typeof completion.apply).toBe("function");
  if (typeof completion.apply === "function") {
    completion.apply(mutable.view, completion, result.from, text.length);
  }
  return mutable.state();
}

describe("Edit input suggestions", () => {
  it("hides native candidates and rejects queued native actions for the entire composition lifetime", () => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {setTimeout, clearTimeout});
    const callbacks: Array<Parameters<NativeSuggestionPort["show"]>[1]> = [];
    const nativeFloating: NativeSuggestionPort = {
      show: vi.fn((_surface, actions) => { callbacks.push(actions); return 1; }),
      hide: vi.fn(),
    };
    let composing = false;
    const suggestions = createEditorInputSuggestions({nativeFloating, mode: () => "livePreview",
      dialect: () => dialect, isComposing: () => composing, protectedRanges: () => [],
      requestLinkCompletions: () => {}, didApply: () => {}});
    const state = EditorState.create({doc: "> [!sta", selection: {anchor: 7}});
    const measurement = {state, status: "active", items: [{label: "State", detail: ""}],
      anchor: {left: 0, top: 0, bottom: 20}, selected: 0};
    const writes: Array<(value: typeof measurement) => void> = [];
    const contentDOM = {};
    const dispatch = vi.fn();
    const view = {state, composing: false, contentDOM, root: {activeElement: contentDOM}, dispatch,
      requestMeasure(request: {write(value: typeof measurement): void}) { writes.push(request.write); },
    } as unknown as EditorView;
    const definition = (suggestions.extension as Extension[])[3] as unknown as {
      create(view: EditorView): {destroy(): void};
    };
    const plugin = definition.create(view);
    try {
      writes[0](measurement);
      expect(callbacks).toHaveLength(1);
      composing = true;
      expect(view.composing).toBe(false);
      callbacks[0].select?.(0);
      expect(callbacks[0].choose?.(0)).toBe(false);
      expect(dispatch).not.toHaveBeenCalled();
      writes[0](measurement);
      expect(nativeFloating.hide).toHaveBeenCalledWith(1);
      expect(callbacks).toHaveLength(1);
    } finally {
      plugin.destroy();
      vi.unstubAllGlobals();
      vi.useRealTimers();
    }
  });
  it("suppresses every caret suggestion while the composition lifetime gate is active", () => {
    const {suggestions, request} = controller("livePreview", [], true);
    for (const [source, text] of [
      [suggestions.slashCompletionSource, "/"],
      [suggestions.calloutCompletionSource, "> [!"],
      [suggestions.wikilinkCompletionSource, "[["],
      [suggestions.analysisReferenceCompletionSource, "@"],
      [suggestions.citationCompletionSource, "@"],
      [suggestions.writingCompletionSource, "res"],
    ] as const) {
      expect(synchronousResult(source, text)).toBeNull();
    }
    expect(request()).toBeNull();
  });
  function expectCompletionUndo(mutable: ReturnType<typeof mutableView>, original: string) {
    const completed = mutable.state().doc.toString();
    const range = mutable.state().selection.main;
    mutable.view.dispatch({changes: {from: range.from, to: range.to, insert: "x"},
      selection: {anchor: range.from + 1}, userEvent: "input.type"});
    expect(undo({state: mutable.state(), dispatch: mutable.view.dispatch})).toBe(true);
    expect(mutable.state().doc.toString()).toBe(completed);
    expect(undo({state: mutable.state(), dispatch: mutable.view.dispatch})).toBe(true);
    expect(mutable.state().doc.toString()).toBe(original);
  }

  it.each(["Date", "Code Block", "Footnote"])("isolates %s slash acceptance from subsequent typing", label => {
    const {suggestions} = controller();
    const mutable = mutableView(EditorState.create({doc: "/", selection: {anchor: 1},
      extensions: [history(), suggestions.extension]}));
    const result = suggestions.slashCompletionSource(
      new CompletionContext(mutable.state(), 1, false),
    ) as CompletionResult;
    const completion = result.options.find(option => option.label === label)!;
    expect(typeof completion.apply).toBe("function");
    if (typeof completion.apply === "function") {
      completion.apply(mutable.view, completion, result.from, 1);
    }
    expectCompletionUndo(mutable, "/");
  });

  it.each(["wikilink", "analysisReference"] as const)("isolates %s acceptance from subsequent typing", async kind => {
    const {suggestions, request} = controller();
    const source = kind === "wikilink" ? "[[Val" : "@Val";
    const mutable = mutableView(EditorState.create({doc: source, selection: {anchor: source.length},
      extensions: [history(), suggestions.extension]}));
    const completionSource = kind === "wikilink"
      ? suggestions.wikilinkCompletionSource : suggestions.analysisReferenceCompletionSource;
    const pending = completionSource(new CompletionContext(mutable.state(), source.length, false));
    suggestions.resolveLinkCompletionQuery(request()!.id, [{label: "Value", insertion: "Value",
      displayText: "Value", detail: "", path: "Value.md", isAmbiguous: false}]);
    const result = (await pending)!;
    const completion = result.options[0];
    expect(typeof completion.apply).toBe("function");
    if (typeof completion.apply === "function") {
      completion.apply(mutable.view, completion, result.from, source.length);
    }
    expectCompletionUndo(mutable, source);
  });
  it("offers every context-available slash command and filters while editing", () => {
    const {suggestions} = controller();
    const block = synchronousResult(suggestions.slashCompletionSource, "/")!;
    expect(block.options.map((option) => option.label)).toEqual([
      "Callout",
      "Date",
      "Inline Math",
      "Display Math",
      "Mermaid",
      "Table",
      "Footnote",
      "Code Block",
      "Divider",
    ]);

    const inline = synchronousResult(suggestions.slashCompletionSource, "Claim /")!;
    expect(inline.options.map((option) => option.label)).toEqual([
      "Date",
      "Inline Math",
      "Footnote",
    ]);

    expect(synchronousResult(suggestions.slashCompletionSource, "/tab")?.options.map(option => option.label)).toEqual(["Table"]);
    expect(synchronousResult(suggestions.slashCompletionSource, "/math")?.options.map(option => option.label)).toEqual(["Inline Math", "Display Math"]);
    for (const text of ["https://", "word/", "/table/"]) {
      expect(synchronousResult(suggestions.slashCompletionSource, text)).toBeNull();
    }

  });

  it("keeps input suggestions out of Source and protected syntax", () => {
    const source = controller("source").suggestions;
    expect(synchronousResult(source.slashCompletionSource, "/")).toBeNull();

    const protectedSuggestions = controller("livePreview", [{from: 0, to: 4}]).suggestions;
    expect(synchronousResult(protectedSuggestions.slashCompletionSource, "/")).toBeNull();
  });

  it("uses compact callout role labels without syntax or explanatory prose", () => {
    const {suggestions} = controller();
    const result = synchronousResult(suggestions.calloutCompletionSource, "> [!")!;
    expect(result.options.map((option) => option.label)).toEqual(["Orient", "State"]);
    expect(result.options.every((option) => option.detail === undefined)).toBe(true);
  });

  it("updates local Callout results synchronously through filtering and context exit", () => {
    const {suggestions} = controller();
    const initial = synchronousResult(suggestions.calloutCompletionSource, "> [!")!;
    const update = (text: string) => {
      const state = EditorState.create({doc: text, selection: {anchor: text.length}});
      return initial.update!(initial, initial.from, text.length, new CompletionContext(state, text.length, false));
    };
    expect(update("> [!sta")!.options.map(option => option.label)).toEqual(["State"]);
    expect(update("> [!")!.options.map(option => option.label)).toEqual(["Orient", "State"]);
    expect(update("> [!state] text")).toBeNull();
  });

  it("reuses a closing Callout bracket and preserves authored folding and title text", () => {
    for (const [text, expected] of [
      ["> [!sta]", "> [!state] "],
      ["> [!sta] Title", "> [!state] Title"],
      ["> [!sta]+ Title", "> [!state]+ Title"],
      ["> [!sta]-\tTitle", "> [!state]-\tTitle"],
      ["> [!sta]  Title", "> [!state]  Title"],
    ]) {
      const {suggestions} = controller();
      const position = text.indexOf("]");
      const state = EditorState.create({doc: text, selection: {anchor: position}});
      const result = suggestions.calloutCompletionSource(
        new CompletionContext(state, position, false),
      ) as CompletionResult;
      const completion = result.options[0];
      const mutable = mutableView(state);
      expect(typeof completion.apply).toBe("function");
      if (typeof completion.apply === "function") {
        completion.apply(mutable.view, completion, result.from, position);
      }
      expect(mutable.state().doc.toString()).toBe(expected);
      expect(mutable.state().sliceDoc(0, mutable.state().selection.main.head))
        .toMatch(/^> \[!state\][+-]?[ \t]$/);
    }
  });

  it("keeps Callout completion separate from subsequent typing in Undo", () => {
    const {suggestions} = controller();
    const query = "> [!sta]";
    const position = query.indexOf("]");
    const mutable = mutableView(EditorState.create({doc: query,
      selection: {anchor: position}, extensions: [history(), suggestions.extension]}));
    const result = suggestions.calloutCompletionSource(
      new CompletionContext(mutable.state(), position, false),
    ) as CompletionResult;
    const completion = result.options[0];
    expect(typeof completion.apply).toBe("function");
    if (typeof completion.apply === "function") {
      completion.apply(mutable.view, completion, result.from, position);
    }
    const completed = mutable.state().doc.toString();
    const head = mutable.state().selection.main.head;
    mutable.view.dispatch({changes: {from: head, insert: "Title"},
      selection: {anchor: head + 5}, userEvent: "input.type"});
    expect(undo({state: mutable.state(), dispatch: mutable.view.dispatch})).toBe(true);
    expect(mutable.state().doc.toString()).toBe(completed);
    expect(undo({state: mutable.state(), dispatch: mutable.view.dispatch})).toBe(true);
    expect(mutable.state().doc.toString()).toBe(query);
  });

  it("inserts bounded structural templates and chains Callout role choice", () => {
    const {suggestions} = controller();
    expect(applyOption(suggestions.slashCompletionSource, "/", "Date").doc.toString())
      .toBe(inputSuggestionTesting.localISODate());
    expect(applyOption(suggestions.slashCompletionSource, "/", "Inline Math").doc.toString())
      .toBe("$$");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Display Math").doc.toString())
      .toBe("$$\n\n$$");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Mermaid").doc.toString())
      .toBe("```mermaid\n\n```");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Table").doc.toString())
      .toBe("| Column 1 | Column 2 |\n| --- | --- |\n|  |  |");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Footnote").doc.toString())
      .toBe("[^1]\n\n[^1]: \n");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Code Block").doc.toString())
      .toBe("```language\n\n```");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Divider").doc.toString())
      .toBe("---");

    const calloutStart = applyOption(
      suggestions.slashCompletionSource,
      "/",
      "Callout",
    );
    expect(calloutStart.doc.toString()).toBe("> [!");
    expect(applyOption(
      suggestions.calloutCompletionSource,
      calloutStart.doc.toString(),
      "Orient",
    ).doc.toString()).toBe("> [!orient] ");
  });

  it("queries note titles incrementally and reuses auto-inserted closing brackets", async () => {
    const {suggestions, request, undoLabels} = controller();
    const state = EditorState.create({doc: "[[价值]]", selection: {anchor: 4}});
    const pending = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 4, false),
    ) as Promise<CompletionResult>;
    const query = request();
    expect(query?.kind).toBe("wikilink");
    expect(query?.query).toBe("价值");
    suggestions.resolveLinkCompletionQuery(query!.id, [{
      label: "价值理论",
      insertion: "价值理论",
      detail: "Topics — 价值理论.md",
      path: "Topics/价值理论.md",
      isAmbiguous: false,
    }]);
    const result = await pending;
    expect(result.options.map((option) => option.label)).toEqual(["价值理论"]);
    expect(result.options[0].detail).toBe("Topics — 价值理论.md");

    const mutable = mutableView(state);
    const apply = result.options[0].apply;
    expect(typeof apply).toBe("function");
    if (typeof apply === "function") {
      apply(mutable.view, result.options[0], result.from, 4);
    }
    expect(mutable.state().doc.toString()).toBe("[[价值理论]]");
    expect(undoLabels).toEqual(["Insert Wikilink"]);
  });

  it("inserts a stored alias as canonical target plus display text", async () => {
    const {suggestions, request} = controller();
    const text = "[[Value Theory]]";
    const state = EditorState.create({doc: text, selection: {anchor: 14}});
    const pending = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 14, false),
    ) as Promise<CompletionResult>;
    const query = request()!;
    suggestions.resolveLinkCompletionQuery(query.id, [{
      label: "Value Theory",
      insertion: "Axiology",
      detail: "Axiology — Topics/Value.md",
      path: "Topics/Value.md",
      displayText: "Value Theory",
      isAmbiguous: false,
    }]);
    const result = await pending;
    const mutable = mutableView(state);
    const apply = result.options[0].apply;
    if (typeof apply === "function") {
      apply(mutable.view, result.options[0], result.from, 14);
    }
    expect(mutable.state().doc.toString()).toBe("[[Axiology|Value Theory]]");
  });

  it("turns an Analysis-only at completion into a Wikilink reference", async () => {
    const {suggestions, request, undoLabels} = controller();
    const text = "According to @Scanlon";
    const state = EditorState.create({doc: text, selection: {anchor: text.length}});
    const pending = suggestions.analysisReferenceCompletionSource(
      new CompletionContext(state, text.length, false),
    ) as Promise<CompletionResult>;
    const query = request()!;
    expect(query.kind).toBe("analysisReference");
    expect(query.query).toBe("Scanlon");
    suggestions.resolveLinkCompletionQuery(query.id, [{
      label: "T. M. Scanlon 1998",
      insertion: "What We Owe",
      detail: "What We Owe to Each Other — T. M. Scanlon — 1998",
      path: "Analyses/What We Owe.md",
      displayText: "T. M. Scanlon 1998",
      isAmbiguous: false,
    }]);
    const result = await pending;
    const mutable = mutableView(state);
    const apply = result.options[0].apply;
    if (typeof apply === "function") {
      apply(mutable.view, result.options[0], result.from, text.length);
    }
    expect(mutable.state().doc.toString())
      .toBe("According to [[What We Owe|T. M. Scanlon 1998]]");
    expect(undoLabels).toEqual(["Insert Analysis Reference"]);
    expect(synchronousResult(suggestions.analysisReferenceCompletionSource, "mail@example"))
      .toBeNull();
  });

  it("keeps completion active inside an empty auto-closed Wikilink", async () => {
    const {suggestions, request} = controller();
    const state = EditorState.create({doc: "[[]]", selection: {anchor: 2}});
    const pending = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 2, false),
    ) as Promise<CompletionResult>;
    const query = request();
    expect(query?.query).toBe("");
    suggestions.resolveLinkCompletionQuery(query!.id, []);
    const result = await pending;
    expect(result.from).toBe(2);
    expect(result.options).toEqual([]);
  });

  it("cancels pending candidates when the retained editor changes document", async () => {
    const {suggestions, request} = controller();
    const state = EditorState.create({doc: "[[old", selection: {anchor: 5}});
    const pending = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 5, false),
    ) as Promise<CompletionResult>;
    const oldID = request()!.id;
    suggestions.resetDocument();
    suggestions.resolveLinkCompletionQuery(oldID, [{
      label: "Old note", insertion: "Old note", detail: "", path: "old.md", isAmbiguous: false,
    }]);
    expect((await pending).options).toEqual([]);

    const next = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 5, false),
    ) as Promise<CompletionResult>;
    suggestions.resolveLinkCompletionQuery(request()!.id, [{
      label: "New note", insertion: "New note", detail: "", path: "new.md", isAmbiguous: false,
    }]);
    expect((await next).options.map(option => option.label)).toEqual(["New note"]);
  });

  it("formats the inserted date as a local ISO calendar date", () => {
    expect(inputSuggestionTesting.localISODate(new Date(2026, 7, 3, 12, 30)))
      .toBe("2026-08-03");
  });
});

describe("Indexed writing suggestions", () => {
  it("inserts a term as ordinary text and rejects acceptance after an edit", async () => {
    const {suggestions, request} = controller();
    const state = EditorState.create({doc: "res", selection: {anchor: 3}});
    const pending = suggestions.writingCompletionSource(new CompletionContext(state, 3, false));
    expect(request()?.kind).toBe("term");
    suggestions.resolveLinkCompletionQuery(request()!.id, [{label: "responsibility", insertion: "responsibility", detail: "Origin", path: "Origin.md", isAmbiguous: false, writingAction: "term", replacementUTF16Count: 3}]);
    const result = (await pending)!;
    const mutable = mutableView(state);
    const choice = result.options[0];
    if (typeof choice.apply === "function") choice.apply(mutable.view, choice, result.from, 3);
    expect(mutable.state().doc.toString()).toBe("responsibility");
    const changed = mutableView(state);
    changed.view.dispatch({changes: {from: 3, insert: "x"}});
    if (typeof choice.apply === "function") choice.apply(changed.view, choice, result.from, 3);
    expect(changed.state().doc.toString()).toBe("resx");
  });
  it("preserves capitalization and source bytes before the ghost suffix", async () => {
    const {suggestions, request} = controller();
    const state = EditorState.create({doc: "Res", selection: {anchor: 3}});
    const pending = suggestions.writingCompletionSource(new CompletionContext(state, 3, false));
    suggestions.resolveLinkCompletionQuery(request()!.id, [{label: "responsibility", insertion: "responsibility", detail: "Origin", path: "Origin.md", isAmbiguous: false, writingAction: "term", replacementUTF16Count: 3}]);
    const result = (await pending)!;
    const mutable = mutableView(state);
    const choice = result.options[0];
    if (typeof choice.apply === "function") choice.apply(mutable.view, choice, result.from, 3);
    expect(mutable.state().doc.toString()).toBe("Responsibility");
  });
  it("leaves IME composition and existing word tails untouched", () => {
    expect(synchronousResult(controller("livePreview", [], true).suggestions.writingCompletionSource, "res")).toBeNull();
    const state = EditorState.create({doc: "result", selection: {anchor: 3}});
    expect(controller().suggestions.writingCompletionSource(new CompletionContext(state, 3, false))).toBeNull();
  });
  it("does not suggest after spaces or at the end of a protected region", () => {
    expect(synchronousResult(controller().suggestions.writingCompletionSource, "   ")).toBeNull();
    expect(synchronousResult(controller("source", [{from: 0, to: 3}]).suggestions.writingCompletionSource, "res")).toBeNull();
  });
});


function citationSuggestionHarness(source = "According to @", setup: {
  composing?: boolean; mode?: EditorMode; protectedRanges?: readonly {from: number; to: number}[];
  readOnly?: boolean; editable?: boolean; multipleSelections?: boolean;
  canInsertCitation?: (state: EditorState) => boolean;
} = {}) {
  const normalized = normalizedDocumentText(source);
  let composing = setup.composing ?? false, revision = 1;
  let state = EditorState.create({doc: normalized,
    selection: setup.multipleSelections ? EditorSelection.create([EditorSelection.cursor(0), EditorSelection.cursor(normalized.length)])
      : {anchor: normalized.length},
    extensions: [history(), exactSourceHistory, EditorState.allowMultipleSelections.of(true),
      ...(setup.readOnly ? [EditorState.readOnly.of(true)] : []),
      ...(setup.editable === false ? [EditorView.editable.of(false)] : [])]})
    .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
  const intents: EditorCitationSuggestionIntent[] = [], queries: {id: string; kind: string; query: string}[] = [];
  const suggestions = createEditorInputSuggestions({
    nativeFloating: {show: () => 0, hide: () => {}}, mode: () => setup.mode ?? "livePreview",
    dialect: () => dialect, isComposing: () => composing,
    protectedRanges: () => setup.protectedRanges ?? [],
    requestLinkCompletions: (id, kind, query) => {queries.push({id, kind, query});},
    requestCitationInsertion: intent => intents.push(intent), citationContextRevision: () => revision,
    canInsertCitation: setup.canInsertCitation,
    didApply: () => {throw new Error("A citation intent must not label an editor mutation.");},
  });
  const view = {get state() {return state;}, get composing() {return composing;}, hasFocus: true,
    dispatch(spec: Transaction | TransactionSpec) {
      state = spec instanceof Transaction ? spec.state : state.update(spec).state;
    }} as unknown as EditorView;
  function result() {
    return suggestions.citationCompletionSource(new CompletionContext(state, state.selection.main.head, false)) as CompletionResult | null;
  }
  function accept(completionResult: CompletionResult) {
    const action = completionResult.options[0];
    expect(typeof action.apply).toBe("function");
    if (typeof action.apply === "function") action.apply(view, action, completionResult.from, state.selection.main.head);
  }
  return {suggestions, intents, queries, view, result, accept, state: () => state,
    setComposing: (value: boolean) => {composing = value;}, changeRevision: () => {revision++;}};
}

describe("local citation completion", () => {
  it("checks citation availability when offering and accepting without restricting Analysis references", async () => {
    let available = false;
    const checkedStates: EditorState[] = [];
    const h = citationSuggestionHarness("According to @Scanlon", {canInsertCitation: state => {
      checkedStates.push(state);
      return available;
    }});
    expect(h.result()).toBeNull();
    expect(checkedStates).toEqual([h.state()]);
    const pending = h.suggestions.analysisReferenceCompletionSource(
      new CompletionContext(h.state(), h.state().selection.main.head, false),
    ) as Promise<CompletionResult>;
    expect(h.queries[0]).toMatchObject({kind: "analysisReference", query: "Scanlon"});
    h.suggestions.resolveLinkCompletionQuery(h.queries[0].id, [{
      label: "T. M. Scanlon 1998", insertion: "What We Owe", detail: "Analysis", path: "Analyses/What We Owe.md",
      displayText: "T. M. Scanlon 1998", isAmbiguous: false,
    }]);
    expect((await pending).options.map(option => option.label)).toEqual(["T. M. Scanlon 1998"]);
    expect(checkedStates).toHaveLength(1);
    available = true;
    const offered = h.result()!;
    expect(offered.options).toHaveLength(1);
    available = false;
    h.accept(offered);
    expect(checkedStates).toHaveLength(3);
    expect(checkedStates[2]).toBe(h.state());
    expect(h.intents).toEqual([]);
    expect(h.state().field(exactSourceState).text).toBe("According to @Scanlon");
    expect(undoDepth(h.state())).toBe(0);
  });

  it("shares the 512 UTF-16 unit query limit with Analysis references and keeps the preceding boundary", async () => {
    const query = "🧭".repeat(255) + "ab";
    expect(query.length).toBe(512);
    const h = citationSuggestionHarness(`According to @${query}`);
    const offered = h.result()!;
    expect(offered.from).toBe("According to ".length);
    const pending = h.suggestions.analysisReferenceCompletionSource(
      new CompletionContext(h.state(), h.state().selection.main.head, false),
    ) as Promise<CompletionResult>;
    expect(h.queries[0]).toMatchObject({kind: "analysisReference", query});
    h.suggestions.resolveLinkCompletionQuery(h.queries[0].id, []);
    expect((await pending).from).toBe(offered.from);
    h.accept(offered);
    expect(h.intents[0].query).toBe(query);
    expect(h.intents[0].toUTF16 - h.intents[0].fromUTF16).toBe(513);
    for (const source of [`@${query}c`, `mail@${query}`]) {
      const invalid = citationSuggestionHarness(source);
      expect(invalid.result()).toBeNull();
      expect(invalid.suggestions.analysisReferenceCompletionSource(
        new CompletionContext(invalid.state(), invalid.state().selection.main.head, false),
      )).toBeNull();
      expect(invalid.queries).toEqual([]);
    }
  });

  it("offers an immediate typed action while Analysis references are still pending", async () => {
    const h = citationSuggestionHarness("According to @Scanlon");
    const context = new CompletionContext(h.state(), h.state().selection.main.head, false);
    const pending = h.suggestions.analysisReferenceCompletionSource(context) as Promise<CompletionResult>;
    expect(pending).toBeInstanceOf(Promise);
    expect(h.queries[0].kind).toBe("analysisReference");
    const local = h.result()!;
    expect(local).not.toBeInstanceOf(Promise);
    const action = local.options[0] as EditorInputSuggestionActionCompletion;
    expect(action.label).toBe("Insert Citation…");
    expect(action.actionID).toBe("insertCitation");
    expect(action.detail).toBe("Zotero");
    expect(action).not.toHaveProperty("path");
    h.suggestions.resolveLinkCompletionQuery(h.queries[0].id, [{
      label: "T. M. Scanlon 1998", insertion: "What We Owe", detail: "Analysis", path: "Analyses/What We Owe.md",
      displayText: "T. M. Scanlon 1998", isAmbiguous: false,
    }]);
    expect((await pending).options.map(option => option.label)).toEqual(["T. M. Scanlon 1998"]);
    expect(h.state().field(exactSourceState).text).toBe("According to @Scanlon");
  });

  it("emits checked exact offsets without deleting the query or adding an Undo event", () => {
    const source = "\uFEFF🧭 First.\r\nAccording to @作者 e\u0301";
    const h = citationSuggestionHarness(source);
    const result = h.result()!;
    h.accept(result);
    expect(h.intents).toHaveLength(1);
    expect(h.intents[0]).toMatchObject({actionID: "insertCitation", query: "作者 e\u0301",
      fromUTF16: source.indexOf("@"), toUTF16: source.length, caretUTF16Offset: source.length,
      editorCaretUTF16Offset: normalizedDocumentText(source).length, interactionRevision: 1});
    expect(h.intents[0].requestID.length).toBeGreaterThan(0);
    expect(h.state().field(exactSourceState).text).toBe(source);
    expect(undoDepth(h.state())).toBe(0);
    h.accept(result);
    expect(h.intents).toHaveLength(1);
  });

  it("rejects source, interaction, lifecycle and composition changes before acceptance", () => {
    for (const invalidate of [
      (h: ReturnType<typeof citationSuggestionHarness>) => h.view.dispatch({changes: {from: 0, insert: "changed "}}),
      (h: ReturnType<typeof citationSuggestionHarness>) => h.changeRevision(),
      (h: ReturnType<typeof citationSuggestionHarness>) => h.suggestions.resetDocument(),
      (h: ReturnType<typeof citationSuggestionHarness>) => h.setComposing(true),
      (h: ReturnType<typeof citationSuggestionHarness>) => h.view.dispatch({selection: {anchor: 0}}),
    ]) {
      const h = citationSuggestionHarness();
      const result = h.result()!;
      invalidate(h);
      const before = h.state().field(exactSourceState).text;
      h.accept(result);
      expect(h.intents).toEqual([]);
      expect(h.state().field(exactSourceState).text).toBe(before);
    }
    const restored = citationSuggestionHarness();
    const result = restored.result()!;
    restored.view.dispatch({selection: {anchor: 0}}); restored.changeRevision();
    restored.view.dispatch({selection: {anchor: restored.state().doc.length}}); restored.changeRevision();
    restored.accept(result);
    expect(restored.intents).toEqual([]);
  });

  it("yields to composition, protected spans, read-only state and unsupported completion contexts", () => {
    for (const h of [
      citationSuggestionHarness("@", {composing: true}),
      citationSuggestionHarness("@", {mode: "source"}),
      citationSuggestionHarness("@", {readOnly: true}),
      citationSuggestionHarness("@", {editable: false}),
      citationSuggestionHarness("@", {multipleSelections: true}),
      citationSuggestionHarness("@key", {protectedRanges: [{from: 0, to: 4}]}),
      citationSuggestionHarness("@name", {protectedRanges: [{from: 1, to: 5}]}),
      citationSuggestionHarness("mail@example"),
    ]) expect(h.result()).toBeNull();
    const {suggestions} = controller();
    const h = citationSuggestionHarness();
    expect(suggestions.citationCompletionSource(new CompletionContext(h.state(), h.state().doc.length, false))).toBeNull();
  });
});
