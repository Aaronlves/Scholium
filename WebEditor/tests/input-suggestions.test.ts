import {
  CompletionContext,
  type CompletionResult,
  type CompletionSource,
} from "@codemirror/autocomplete";
import {EditorState, Transaction, type TransactionSpec} from "@codemirror/state";
import type {EditorView} from "@codemirror/view";
import {describe, expect, it} from "vitest";
import {
  createEditorInputSuggestions,
  inputSuggestionTesting,
} from "../input-suggestions";
import type {EditorMode, MarkdownEditingDialect} from "../protocol";

const dialect: MarkdownEditingDialect = {
  version: 4,
  callouts: [
    {identifier: "orient", aliases: ["mini"], label: "Orient", meaning: "Purpose and route."},
    {identifier: "state", aliases: ["definition"], label: "State", meaning: "A compact claim."},
  ],
  vectorLinkOperators: [
    {marker: "", kind: "neutral", meaning: "Neutral."},
    {marker: "+", kind: "supports", meaning: "Supports."},
    {marker: "-", kind: "opposes", meaning: "Opposes."},
    {marker: "?", kind: "incompatible", meaning: "Incompatible."},
  ],
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
) {
  let request: {id: string; kind: string; query: string} | null = null;
  const undoLabels: string[] = [];
  const suggestions = createEditorInputSuggestions({
    mode: () => mode,
    dialect: () => dialect,
    isComposing: () => false,
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
  it("starts with a bounded featured set and progressively searches the catalog", () => {
    const {suggestions} = controller();
    const block = synchronousResult(suggestions.slashCompletionSource, "/")!;
    expect(block.options.map((option) => option.label)).toEqual([
      "Callout",
      "Date",
      "Inline Math",
      "Mermaid",
    ]);

    const inline = synchronousResult(suggestions.slashCompletionSource, "Claim /")!;
    expect(inline.options.map((option) => option.label)).toEqual([
      "Date",
      "Inline Math",
      "Footnote",
    ]);

    expect(synchronousResult(suggestions.slashCompletionSource, "/tab")!
      .options.map((option) => option.label)).toEqual(["Table"]);
    expect(synchronousResult(suggestions.slashCompletionSource, "/math")!
      .options.map((option) => option.label)).toEqual(["Inline Math", "Display Math"]);
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

  it("inserts bounded structural templates and chains Callout role choice", () => {
    const {suggestions} = controller();
    expect(applyOption(suggestions.slashCompletionSource, "/", "Date").doc.toString())
      .toBe(inputSuggestionTesting.localISODate());
    expect(applyOption(suggestions.slashCompletionSource, "/", "Inline Math").doc.toString())
      .toBe("$$");
    expect(applyOption(suggestions.slashCompletionSource, "/math", "Display Math").doc.toString())
      .toBe("$$\n\n$$");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Mermaid").doc.toString())
      .toBe("```mermaid\n\n```");
    expect(applyOption(suggestions.slashCompletionSource, "/tab", "Table").doc.toString())
      .toBe("| Column 1 | Column 2 |\n| --- | --- |\n|  |  |");
    expect(applyOption(suggestions.slashCompletionSource, "/foot", "Footnote").doc.toString())
      .toBe("[^1]\n\n[^1]: \n");
    expect(applyOption(suggestions.slashCompletionSource, "/code", "Code Block").doc.toString())
      .toBe("```language\n\n```");
    expect(applyOption(suggestions.slashCompletionSource, "/div", "Divider").doc.toString())
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

  it("turns an Analysis-only at completion into a neutral Wikilink reference", async () => {
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

  it("formats the inserted date as a local ISO calendar date", () => {
    expect(inputSuggestionTesting.localISODate(new Date(2026, 7, 3, 12, 30)))
      .toBe("2026-08-03");
  });
});
