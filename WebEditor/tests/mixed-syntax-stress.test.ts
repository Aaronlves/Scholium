import {Compartment, EditorState, StateEffect, Transaction} from "@codemirror/state";
import {history, isolateHistory, redo, redoDepth, undo, undoDepth} from "@codemirror/commands";
import {ensureSyntaxTree} from "@codemirror/language";
import {EditorView, WidgetType} from "@codemirror/view";
import {DOMParser as LinkedomDOMParser, parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createMarkdownDocumentState} from "../bootstrap";
import {createCommittedReviewProjection} from "../committed-review-projection";
import {createDeferredEditingInfrastructure} from "../deferred-editing-infrastructure";
import {captureExactHistory, exactSourceHistory, exactSourceState, restoreExactHistory} from "../exact-source-history";
import {scholiumNoteLanguage} from "../language";
import {createLiveDisplayMathProjection} from "../live-display-math-projection";
import {createLiveFootnoteProjection} from "../live-footnote-projection";
import {createLiveMermaidProjection} from "../live-mermaid-projection";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveSelectionController} from "../live-selection";
import {createLiveSemanticLayout} from "../live-semantic-layout";
import {createLiveStructuredBlockProjections} from "../live-structured-block-projections";
import {mermaidPresentation} from "../mermaid-presentation";
import {scholiumMermaidRuntime} from "../mermaid-runtime";
import {createNativeFloatingPorts} from "../native-floating";
import {createProjectedWidgetRegistry} from "../projected-widget-registry";
import type {EditorMode, MarkdownEditingDialect} from "../protocol";
import {createReaderMermaidPass} from "../reader-mermaid-pass";
import {ExactSourceMirror} from "../state";
import {transformMarkdown} from "../transformations";

const dialect: MarkdownEditingDialect = {
  version: 6,
  callouts: [{identifier: "state", label: "Statement", meaning: "Statement"},
    {identifier: "quote", label: "Quotation", meaning: "Quotation"}],
  linkAnnotation: {openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\",
    allowsMultiline: true, allowsNesting: false},
  footnotes: {namedReferenceOpening: "[^", namedReferenceClosing: "]", definitionSeparator: ":",
    inlineOpening: "^[", continuationIndentSpaces: 2, allowsTabContinuation: true,
    caseSensitiveIdentifiers: true, ordinalByFirstReference: true},
  mathematics: {inlineDelimiter: "$", displayDelimiter: "$$", singleDollarInline: true},
};

const groupCount = 96;
function mixedSource() {
  const groups = Array.from({length: groupCount}, (_, index) => [
    `## Section ${index}`,
    "",
    `Ordinary paragraph ${index}: 中文 🦉 e\u0301 **strong** *emphasis* ~~strike~~ ==highlight== $x_${index}$.`,
    Array.from({length: 8}, (_, link) => `[[Target-${index}-${link}#Heading|别名 ${link}]]`).join(" "),
    "`[[Literal-inline]] $literal$` and \\[\\[Escaped-literal\\]\\].",
    "",
    `> [!state]+ Claim ${index}`,
    `> Body [[Callout-${index}]] and [^note-${index}].`,
    ">",
    `> > [!quote]- Nested ${index}`,
    "> > Quoted **reason**.",
    "",
    "| Column 中文 | Value 🦉 |",
    "|:---|---:|",
    "| A \\| B | `[[Literal-cell]]` |",
    "",
    "- [ ] Task",
    "  - Nested list",
    "1. Ordered item",
    "",
    "```typescript",
    `const protected${index} = "[[Literal-code]] **not emphasis** $notMath$";`,
    "%% unclosed comment-looking code [[Literal-percent]]",
    "<!-- unclosed comment-looking code [[Literal-html]]",
    "> [!state] Not a Callout",
    "```",
    "",
    "````markdown",
    "```mermaid",
    "flowchart LR; Fake --> Literal",
    "```",
    "[[Literal-nested-fence]]",
    "````",
    "",
    "```mermaid",
    `flowchart LR; A${index}[理由 ${index}] --> B${index}[结论]`,
    "```",
    "",
    "$$",
    `x_${index}^2 + y_${index}^2 = z_${index}^2`,
    "$$",
    "",
    `[^note-${index}]: Definition 中文 e\u0301.`,
    "",
    "%% [[Literal-hidden-comment]] $hidden$ %%",
    "",
    "<!-- [[Literal-html-comment]] -->",
    "",
  ].join("\n"));
  return "\uFEFF---\r\ntitle: Mixed syntax stress\r\nunknown: 'retain exact bytes'\r\n---\r\n\r\n"
    + groups.join("\n").replaceAll("\n", "\r\n");
}

const historyExtensions = [history(), exactSourceHistory, EditorState.lineSeparator.of("\n")];
const exact = (state: EditorState) => state.field(exactSourceState).text;
function command(state: EditorState, action: typeof undo) {
  let next = state;
  expect(action({state, dispatch: transaction => { next = transaction.state; }})).toBe(true);
  return next;
}
function controller() {
  return createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
}
function indexedDocument(source: string, index: ReturnType<typeof controller>) {
  const state = createMarkdownDocumentState(source, [historyExtensions, scholiumNoteLanguage]);
  expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
  return state.update({effects: StateEffect.appendConfig.of(index.extension)}).state;
}
function publishCompletedSyntax(state: EditorState): EditorState {
  expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
  // Parser completion advances its context; a transaction publishes that tree
  // to the immutable language and projection fields before the next assertion.
  return state.update({}).state;
}
function completeIndex(state: EditorState, index: ReturnType<typeof controller>) {
  const result = index.index(state);
  expect(result.syntaxComplete).toBe(true);
  return result;
}
function expectEquivalentIndex(actual: ReturnType<typeof completeIndex>, expected: ReturnType<typeof completeIndex>) {
  // Excluded ranges have no public metadata contract; fresh construction may
  // retain a code-block object's additional properties at the same location.
  const ranges = (values: readonly {from: number; to: number}[]) => values.map(({from, to}) => ({from, to}));
  const normalized = (index: typeof actual) => ({...index, literals: {...index.literals,
    excluded: ranges(index.literals.excluded)}, commandProtectedRanges: ranges(index.commandProtectedRanges),
    mutationSensitiveRanges: ranges(index.mutationSensitiveRanges)});
  const a = normalized(actual), e = normalized(expected);
  for (const key of Object.keys(a) as Array<keyof typeof a>) {
    if (key === "syntax") {
      for (const kind of ["blocks", "inlines", "literals"] as const) {
        expect(a.syntax[kind].length, `${key}.${kind} count`).toBe(e.syntax[kind].length);
        for (let index = 0; index < a.syntax[kind].length; index++) {
          if (JSON.stringify(a.syntax[kind][index]) !== JSON.stringify(e.syntax[kind][index])) {
            expect(a.syntax[kind][index], `${key}.${kind}[${index}]`).toEqual(e.syntax[kind][index]);
          }
        }
      }
    } else expect(a[key], key).toEqual(e[key]);
  }
}

afterEach(() => vi.unstubAllGlobals());

describe("dense mixed Markdown stress", () => {
  it("keeps semantic counts, protected literals and a fresh-parse oracle through distributed Unicode edits and exact history recovery", () => {
    const source = mixedSource();
    const index = controller();
    let state = publishCompletedSyntax(indexedDocument(source, index));
    const initial = completeIndex(state, index);
    const links = initial.syntax.inlines.filter(inline => inline.kind === "wikilink");
    expect(links).toHaveLength(groupCount * 9);
    expect(links.every(link => !state.doc.sliceString(link.from, link.to).includes("Literal"))).toBe(true);
    expect(initial.callouts).toHaveLength(groupCount * 2);
    expect(initial.tables).toHaveLength(groupCount);
    expect(initial.literals.codeBlocks).toHaveLength(groupCount * 3);
    expect(initial.footnotes.definitions).toHaveLength(groupCount);
    expect(initial.mathExpressions).toHaveLength(groupCount * 2);
    expect(initial.literals.codeBlocks.flatMap(block => mermaidPresentation(state.doc, block) ?? []))
      .toHaveLength(groupCount);
    const protectedFrom = state.doc.toString().indexOf("[[Literal-code]]");
    expect(transformMarkdown(state.doc.toString(), [{anchor: protectedFrom, head: protectedFrom + 16}], "bold",
      {protectedRanges: initial.commandProtectedRanges})).toBeNull();

    for (let edit = 0; edit < 24; edit++) {
      const section = (edit * 37) % groupCount;
      const from = state.doc.toString().indexOf(`Ordinary paragraph ${section}:`) + 8;
      state = state.update({changes: {from, insert: "中文e\u0301🦉"},
        annotations: isolateHistory.of("full")}).state;
      const freshController = controller();
      state = publishCompletedSyntax(state);
      const fresh = publishCompletedSyntax(indexedDocument(exact(state), freshController));
      expectEquivalentIndex(completeIndex(state, index), completeIndex(fresh, freshController));
    }
    const targetFrom = state.doc.toString().indexOf("Target-53-7");
    state = state.update({changes: {from: targetFrom, to: targetFrom + "Target-53-7".length, insert: "Changed-中文🦉"},
      annotations: isolateHistory.of("full")}).state;
    const edited = exact(state);
    expect(undoDepth(state)).toBe(25);
    const restored = restoreExactHistory(captureExactHistory(state)!, edited,
      [historyExtensions, scholiumNoteLanguage, controller().extension]);
    let recovered = restored;
    for (let step = 0; step < 25; step++) recovered = command(recovered, undo);
    expect(exact(recovered)).toBe(source);
    for (let step = 0; step < 25; step++) recovered = command(recovered, redo);
    expect(exact(recovered)).toBe(edited);
  });

  it("retains real Edit projection fields, one semantic catalog and both Undo branches across 30 mode transitions", () => {
    vi.stubGlobal("window", {});
    const source = mixedSource();
    const mode = new Compartment();
    const index = controller();
    const infrastructure = createDeferredEditingInfrastructure([scholiumNoteLanguage, index.extension]);
    const review = createCommittedReviewProjection({nativeFloating: createNativeFloatingPorts(() => {}),
      projection: () => null, mirror: () => new ExactSourceMirror(source), imageResources: () => ({}), postMessage: () => {}});
    const selection = createLiveSelectionController({handleModifiedLink: () => false, handleProjectedPointerStart: () => false});
    const widgets = createProjectedWidgetRegistry();
    const blocks = createLiveStructuredBlockProjections({selection, projections: index, widgets,
      editingDialect: () => dialect, reuseCounts: {table: 0}});
    const layout = createLiveSemanticLayout({projections: index, selection, editingDialect: () => dialect});
    const footnotes = createLiveFootnoteProjection({selection, projections: index, widgets, reuseCounts: {footnote: 0}});
    const math = createLiveDisplayMathProjection({selection, projections: index,
      widget: () => new class extends WidgetType {toDOM(): HTMLElement {throw new Error("State-only stress fixture");}},
      shouldRefreshRuntime: () => false});
    const mermaid = createLiveMermaidProjection({selection, projections: index, widgets, ensureRuntime: async () => null,
      currentThemeRevision: () => 0, refreshThemeEffect: StateEffect.define<number>()});
    const live = [selection.extension, layout.extension, blocks.tableExtension, blocks.calloutExtension,
      footnotes.extension, math.extension, mermaid.extension];
    let state = createMarkdownDocumentState(source,
      [historyExtensions, infrastructure.forDocument("review"), mode.of(review.extension)]);
    expect(() => index.index(state)).toThrow();
    function changeMode(target: EditorMode) {
      const activation = infrastructure.activationEffects(state, target);
      if (activation.length) state = state.update({effects: activation}).state;
      state = state.update({effects: mode.reconfigure(target === "review" ? review.extension : target === "livePreview" ? live : []),
        annotations: Transaction.addToHistory.of(false)}).state;
    }
    changeMode("livePreview");
    state = state.update({changes: {from: state.doc.length, insert: "First"}, annotations: isolateHistory.of("full")}).state;
    const first = exact(state);
    state = state.update({changes: {from: state.doc.length, insert: " second"}, annotations: isolateHistory.of("full")}).state;
    state = publishCompletedSyntax(command(state, undo));
    const catalog = completeIndex(state, index);
    const historyBefore = captureExactHistory(state);
    const selectionBefore = state.selection;
    expect(undoDepth(state)).toBe(1);
    expect(redoDepth(state)).toBe(1);
    for (let round = 0; round < 10; round++) {
      for (const target of ["review", "source", "livePreview"] as const) {
        changeMode(target);
        expect(exact(state)).toBe(first);
        expect(state.selection.eq(selectionBefore)).toBe(true);
        expect(captureExactHistory(state)).toBe(historyBefore);
        expect(index.index(state)).toBe(catalog);
        expect(state.readOnly).toBe(target === "review");
        if (target === "livePreview") expect(state.facet(EditorView.decorations).length).toBeGreaterThan(5);
      }
    }
    expect(exact(command(state, undo))).toBe(source);
    expect(exact(command(state, redo))).toBe(first + " second");
  });

  it("renders and independently mounts 96 real Pele diagrams across four families while keeping malformed and cancelled input bounded", async () => {
    const {document} = parseHTML("<html><body></body></html>");
    vi.stubGlobal("DOMParser", LinkedomDOMParser);
    const colors: Record<string, string> = {"--scholium-color-document-background": "#ffffff",
      "--scholium-color-surface-background": "#eeeeee", "--scholium-color-primary-text": "#111111",
      "--scholium-color-accent": "#0066cc", "--scholium-color-separator": "#777777",
      "--scholium-document-body-font-family": "system-ui"};
    vi.stubGlobal("getComputedStyle", () => ({getPropertyValue: (name: string) => colors[name] ?? ""}));
    const unique = Array.from({length: 24}, (_, index) => [
      `flowchart LR\nA[理由 ${index}] --> B[结论 ${index}]`,
      `sequenceDiagram\nA->>B: Reason ${index}\nB-->>A: Reply ${index}`,
      `stateDiagram-v2\n[*] --> Draft${index}\nDraft${index} --> Reviewed${index}`,
      `classDiagram\nClaim${index} <|-- Objection${index}`,
    ][index % 4]);
    const sources = Array.from({length: 4}, () => unique).flat();
    const render = createReaderMermaidPass(sources, document.documentElement as unknown as Element, () => 0);
    const mounted = new Set<SVGSVGElement>();
    for (const source of sources) {
      const result = await render(scholiumMermaidRuntime, source);
      expect(result.ok, source).toBe(true);
      if (!result.ok) throw new Error(result.reason);
      expect(result.svg.querySelector("a, image, script, foreignObject, use, [href], [onclick]")).toBeNull();
      const host = document.createElement("div") as unknown as HTMLElement;
      expect(scholiumMermaidRuntime.mount(host, result.svg)).toBe(true);
      expect(host.shadowRoot?.querySelector("svg")).toBe(result.svg);
      expect(scholiumMermaidRuntime.mount(host, result.svg)).toBe(false);
      mounted.add(result.svg);
    }
    expect(mounted.size).toBe(96);
    for (const source of ["flowchart LR\nA -->", "flowchart LR\nclick A https://example.invalid",
      "flowchart LR\n" + Array.from({length: 513}, (_, index) => `A${index} --> A${index + 1}`).join("\n")]) {
      expect((await scholiumMermaidRuntime.render({source, themeRoot: document.documentElement as unknown as Element})).ok).toBe(false);
    }
    const abort = new AbortController();
    const pending = scholiumMermaidRuntime.render({source: unique[0], signal: abort.signal,
      themeRoot: document.documentElement as unknown as Element});
    abort.abort();
    expect(await pending).toEqual({ok: false, reason: "cancelled"});
  });
});
