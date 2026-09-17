import {
  CompletionContext,
  type CompletionResult,
  type CompletionSource,
} from "@codemirror/autocomplete";
import {EditorSelection, EditorState, StateEffect, Transaction, type Extension, type TransactionSpec} from "@codemirror/state";
import {EditorView, type DecorationSet} from "@codemirror/view";
import {history, undo} from "@codemirror/commands";
import {describe, expect, it, vi} from "vitest";
import {
  createEditorInputSuggestions,
  inputSuggestionTesting,
  safeContinuationSuffix,
} from "../input-suggestions";
import type {EditorMode, MarkdownEditingDialect} from "../protocol";
import {exactSourceHistory, exactSourceState, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";

function inlineContinuationHarness(source = "A claim about res", options: {
  composing?: boolean; protectedRanges?: readonly {from: number; to: number}[]; multipleSelections?: boolean;
  mode?: EditorMode; readOnly?: boolean; editable?: boolean;
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
    nativeFloating: {show: () => 0, hide: () => {}, event: () => true}, mode: () => options.mode ?? "livePreview",
    dialect: () => dialect, isComposing: () => options.composing ?? false, protectedRanges: () => options.protectedRanges ?? [],
    requestLinkCompletions: id => { terms.push(id); },
    requestWritingContinuation: id => { requests.push(id); },
    cancelWritingContinuation: id => { cancelled.push(id); }, didApply: label => labels.push(label),
  });
  const view = {get state() {return state;}, composing: false, hasFocus: true,
    dispatch(spec: TransactionSpec) { state = state.update(spec).state; }} as unknown as EditorView;
  // A detached plugin exercises scheduling without pretending to establish WebKit input acceptance.
  const definition = (suggestions.extension as Extension[])[1] as unknown as {create(view: EditorView): {
    decorations: DecorationSet; schedule(): void; clear(): void; accept(): boolean;
  }};
  const plugin = definition.create(view);
  suggestions.configureWritingContinuation(true, "model-a");
  plugin.schedule();
  return {suggestions, plugin, requests, cancelled, terms, labels, state: () => state, view};
}

describe("AI-first inline continuation", () => {
  it("waits for AI without exposing or requesting local terms, and accepts one exact Undo event", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("\uFEFFFirst 😀.\r\nA claim about res");
    await vi.advanceTimersByTimeAsync(1_199);
    expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
    await vi.advanceTimersByTimeAsync(1);
    expect(h.requests).toHaveLength(1); expect(h.terms).toEqual([]);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility needs qualification."});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(1);
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().field(exactSourceState).text).toBe("\uFEFFFirst 😀.\r\nA claim about responsibility needs qualification.");
    expect(h.labels).toEqual(["Accept AI Continuation"]);
    expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
    expect(h.state().field(exactSourceState).text).toBe("\uFEFFFirst 😀.\r\nA claim about res");
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
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().doc.toString()).toBe("A claim about responsibility");
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
    for (const text of ["", " ", "a\nb", "a\u0085b", "a\u2028b", "a\u2029b", "a\u202eb", "[[note]]", "*claim*", "\ud800", "x".repeat(513)]) {
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
  version: 5,
  callouts: [
    {identifier: "orient", aliases: ["mini"], label: "Orient", meaning: "Purpose and route."},
    {identifier: "state", aliases: ["definition"], label: "State", meaning: "A compact claim."},
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
    nativeFloating: {show: () => 0, hide: () => {}, event: () => true},
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
