import {isolateHistory} from "@codemirror/commands";
import {
  CompletionContext,
  acceptCompletion,
  closeCompletion,
  currentCompletions,
  selectedCompletionIndex,
  setSelectedCompletion,
  autocompletion,
  pickedCompletion,
  snippet,
  type Completion,
  type CompletionSource,
} from "@codemirror/autocomplete";
import {
  EditorSelection,
  Prec,
  Transaction,
  type EditorState,
  type Extension,
} from "@codemirror/state";
import {
  MAX_SOURCE_UTF8_BYTES,
  type EditorMode,
  type MarkdownEditingDialect,
} from "./protocol";
import {applySourceChanges, transformMarkdown} from "./transformations";
import {systemSymbolElement, type WebSystemSymbolKey} from "./system-symbols";
import {Decoration, WidgetType, keymap, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate} from "@codemirror/view";
import type {NativeFloatingBridge} from "./native-floating";
import {localized, localizedTemplate, localizedCallout} from "./localization";

export interface EditorLinkCompletionCandidate {
  label: string;
  insertion: string;
  detail: string;
  path: string;
  displayText?: string;
  isAmbiguous: boolean;
  writingAction?: "term";
  replacementUTF16Count?: number;
}

export type EditorLinkCompletionKind = "wikilink" | "analysisReference" | "term";

interface SourceRange {
  readonly from: number;
  readonly to: number;
}

interface InputSuggestionOptions {
  nativeFloating: NativeFloatingBridge;
  mode(state: EditorState): EditorMode;
  dialect(): MarkdownEditingDialect | null;
  isComposing(): boolean;
  protectedRanges(state: EditorState): readonly SourceRange[];
  requestLinkCompletions(
    requestID: string,
    kind: EditorLinkCompletionKind,
    query: string,
  ): void;
  didApply(undoLabel: string): void;
}

export interface EditorInputSuggestionsController {
  readonly extension: Extension;
  readonly writingCompletionSource: CompletionSource;
  readonly wikilinkCompletionSource: CompletionSource;
  readonly analysisReferenceCompletionSource: CompletionSource;
  readonly slashCompletionSource: CompletionSource;
  readonly calloutCompletionSource: CompletionSource;
  resolveLinkCompletionQuery(requestID: string, candidates: unknown): void;
}

type SuggestionType =
  | "scholium-note"
  | "scholium-analysis-reference"
  | "scholium-callout-role"
  | "scholium-command-callout"
  | "scholium-command-date"
  | "scholium-command-math"
  | "scholium-command-mermaid"
  | "scholium-command-table"
  | "scholium-command-footnote"
  | "scholium-command-code"
  | "scholium-command-divider";

const suggestionSymbolByType: Record<SuggestionType, WebSystemSymbolKey> = {
  "scholium-note": "doc-text",
  "scholium-analysis-reference": "doc-text",
  "scholium-callout-role": "text-quote",
  "scholium-command-callout": "text-quote",
  "scholium-command-date": "calendar",
  "scholium-command-math": "function",
  "scholium-command-mermaid": "flowchart",
  "scholium-command-table": "tablecells",
  "scholium-command-footnote": "textformat-superscript",
  "scholium-command-code": "curlybraces-square",
  "scholium-command-divider": "minus",
};

function isLiveSuggestionContext(options: InputSuggestionOptions, state: EditorState) {
  return options.mode(state) === "livePreview"
    && !options.isComposing()
    && state.selection.ranges.length === 1
    && state.selection.main.empty;
}

function positionIsProtected(
  options: InputSuggestionOptions,
  state: EditorState,
  position: number,
) {
  return options.protectedRanges(state).some((range) =>
    position >= range.from && position < range.to,
  );
}

function termSuffix(state: EditorState, position: number, candidate: EditorLinkCompletionCandidate): string | null {
  const count = candidate.replacementUTF16Count ?? 0;
  if (!count || count > position || candidate.writingAction !== "term") return null;
  const typed = state.sliceDoc(position - count, position);
  if (candidate.label.slice(0, count).toLocaleLowerCase() !== typed.toLocaleLowerCase()) return null;
  const suffix = candidate.label.slice(count);
  // A ghost must show exactly the bytes acceptance appends, without hidden Markdown escapes.
  return suffix && !/[\\`*_{}[\]<>!|#+.]/u.test(suffix) ? suffix : null;
}

export function boundedUUID() {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0"));
  return [
    hex.slice(0, 4).join(""),
    hex.slice(4, 6).join(""),
    hex.slice(6, 8).join(""),
    hex.slice(8, 10).join(""),
    hex.slice(10, 16).join(""),
  ].join("-");
}

function localISODate(date = new Date()) {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function replaceSlashWithText(
  insertedText: string | (() => string),
  undoLabel: string,
  didApply: (undoLabel: string) => void,
): NonNullable<Completion["apply"]> {
  return (view, completion, from, to) => {
    const slashFrom = from - 1;
    if (slashFrom < 0 || view.state.sliceDoc(slashFrom, from) !== "/") return;
    const insert = typeof insertedText === "function" ? insertedText() : insertedText;
    view.dispatch({
      changes: {from: slashFrom, to, insert},
      selection: {anchor: slashFrom + insert.length},
      annotations: [
        pickedCompletion.of(completion),
        Transaction.userEvent.of("input.complete.scholium"),
      ],
    });
    didApply(undoLabel);
  };
}

function replaceSlashWithSnippet(
  template: string,
  undoLabel: string,
  didApply: (undoLabel: string) => void,
): NonNullable<Completion["apply"]> {
  const applySnippet = snippet(template);
  return (view, completion, from, to) => {
    const slashFrom = from - 1;
    if (slashFrom < 0 || view.state.sliceDoc(slashFrom, from) !== "/") return;
    applySnippet(view, completion, slashFrom, to);
    didApply(undoLabel);
  };
}

function replaceSlashWithFootnote(
  options: InputSuggestionOptions,
): NonNullable<Completion["apply"]> {
  return (view, completion, from, to) => {
    const slashFrom = from - 1;
    if (slashFrom < 0 || view.state.sliceDoc(slashFrom, from) !== "/") return;
    const source = view.state.doc.toString();
    const transformed = transformMarkdown(
      source,
      [{anchor: slashFrom, head: to}],
      "insertFootnote",
      {
        argument: "",
        protectedRanges: options.protectedRanges(view.state),
      },
    );
    if (!transformed) return;
    const transformedSource = applySourceChanges(source, transformed.changes);
    if (new TextEncoder().encode(transformedSource).byteLength > MAX_SOURCE_UTF8_BYTES) return;
    view.dispatch({
      changes: transformed.changes,
      selection: EditorSelection.create(
        transformed.selections.map((range) =>
          EditorSelection.range(range.anchor, range.head),
        ),
      ),
      annotations: [
        pickedCompletion.of(completion),
        Transaction.userEvent.of("input.complete.scholium.insertFootnote"),
      ],
    });
    options.didApply(transformed.undoLabel);
  };
}

function fuzzyCommandMatch(label: string, query: string) {
  if (!query) return true;
  const normalizedLabel = label.toLocaleLowerCase();
  const normalizedQuery = query.toLocaleLowerCase();
  let queryIndex = 0;
  for (const character of normalizedLabel) {
    if (character === normalizedQuery[queryIndex]) queryIndex += 1;
    if (queryIndex === normalizedQuery.length) return true;
  }
  return false;
}

function slashCommandOptions(
  options: InputSuggestionOptions,
  blockContext: boolean,
  query: string,
) {
  const commands: Array<Completion & {blockOnly?: boolean}> = [
    {
      label: localized("Callout"),
      type: "scholium-command-callout" satisfies SuggestionType,
      apply: replaceSlashWithText("> [!", "Insert Callout", options.didApply),
      boost: 20,
      blockOnly: true,
    },
    {
      label: localized("Date"),
      type: "scholium-command-date" satisfies SuggestionType,
      apply: replaceSlashWithText(localISODate, "Insert Date", options.didApply),
      boost: 18,
    },
    {
      label: localized("Inline Math"),
      type: "scholium-command-math" satisfies SuggestionType,
      apply: replaceSlashWithSnippet("$${}$", "Insert Inline Math", options.didApply),
      boost: 16,
    },
    {
      label: localized("Display Math"),
      type: "scholium-command-math" satisfies SuggestionType,
      apply: replaceSlashWithSnippet("$$\n${}\n$$", "Insert Display Math", options.didApply),
      boost: 14,
      blockOnly: true,
    },
    {
      label: localized("Mermaid"),
      type: "scholium-command-mermaid" satisfies SuggestionType,
      apply: replaceSlashWithSnippet("```mermaid\n${}\n```", "Insert Mermaid", options.didApply),
      boost: 12,
      blockOnly: true,
    },
    {
      label: localized("Table"),
      type: "scholium-command-table" satisfies SuggestionType,
      apply: replaceSlashWithSnippet(
        "| ${1:Column 1} | ${2:Column 2} |\n| --- | --- |\n| ${3} | ${4} |",
        "Insert Table",
        options.didApply,
      ),
      boost: 10,
      blockOnly: true,
    },
    {
      label: localized("Footnote"),
      type: "scholium-command-footnote" satisfies SuggestionType,
      apply: replaceSlashWithFootnote(options),
      boost: 8,
    },
    {
      label: localized("Code Block"),
      type: "scholium-command-code" satisfies SuggestionType,
      apply: replaceSlashWithSnippet(
        "```${1:language}\n${2}\n```",
        "Insert Code Block",
        options.didApply,
      ),
      boost: 6,
      blockOnly: true,
    },
    {
      label: localized("Divider"),
      type: "scholium-command-divider" satisfies SuggestionType,
      apply: replaceSlashWithText("---", "Insert Divider", options.didApply),
      boost: 4,
      blockOnly: true,
    },
  ];
  const available = commands.filter((command) => blockContext || !command.blockOnly);
  if (!query) {
    const featured = blockContext
      ? new Set([
        localized("Callout"), localized("Date"), localized("Inline Math"), localized("Mermaid"),
      ])
      : new Set([localized("Date"), localized("Inline Math"), localized("Footnote")]);
    return available.filter((command) => featured.has(command.label));
  }
  return available
    .filter((command) => fuzzyCommandMatch(command.label, query))
    .slice(0, 7);
}

function applyWikilinkCandidate(
  candidate: EditorLinkCompletionCandidate,
  didApply: (undoLabel: string) => void,
): NonNullable<Completion["apply"]> {
  return (view, completion, from, to) => {
    let closingLength = 0;
    while (closingLength < 2
      && view.state.sliceDoc(to + closingLength, to + closingLength + 1) === "]") {
      closingLength += 1;
    }
    const display = candidate.displayText ? `|${candidate.displayText}` : "";
    const insert = `${candidate.insertion}${display}]]`;
    view.dispatch({
      changes: {from, to: to + closingLength, insert},
      selection: {anchor: from + insert.length},
      annotations: [
        pickedCompletion.of(completion),
        Transaction.userEvent.of("input.complete.scholium.wikilink"),
      ],
    });
    didApply("Insert Wikilink");
  };
}

function applyAnalysisReferenceCandidate(
  candidate: EditorLinkCompletionCandidate,
  didApply: (undoLabel: string) => void,
): NonNullable<Completion["apply"]> {
  return (view, completion, from, to) => {
    const display = candidate.displayText ? `|${candidate.displayText}` : "";
    const insert = `[[${candidate.insertion}${display}]]`;
    view.dispatch({
      changes: {from, to, insert},
      selection: {anchor: from + insert.length},
      annotations: [
        pickedCompletion.of(completion),
        Transaction.userEvent.of("input.complete.scholium.analysis-reference"),
      ],
    });
    didApply("Insert Analysis Reference");
  };
}

function validLinkCandidate(value: unknown): value is EditorLinkCompletionCandidate {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<EditorLinkCompletionCandidate>;
  return typeof candidate.label === "string"
    && typeof candidate.insertion === "string"
    && typeof candidate.detail === "string"
    && typeof candidate.path === "string"
    && (candidate.displayText === undefined || typeof candidate.displayText === "string")
    && typeof candidate.isAmbiguous === "boolean"
    && (candidate.writingAction === undefined || candidate.writingAction === "term")
    && (candidate.replacementUTF16Count === undefined || (Number.isSafeInteger(candidate.replacementUTF16Count) && candidate.replacementUTF16Count > 0 && candidate.replacementUTF16Count <= 128));
}

function suggestionSymbol(completion: Completion) {
  const key = suggestionSymbolByType[completion.type as SuggestionType];
  return key ? systemSymbolElement(key, "scholium-completion-symbol") : null;
}

export function createEditorInputSuggestions(
  options: InputSuggestionOptions,
): EditorInputSuggestionsController {
  const pendingLinkQueries = new Map<string, {
    resolve(candidates: EditorLinkCompletionCandidate[]): void;
    timeout: ReturnType<typeof setTimeout>;
  }>();

  class Ghost extends WidgetType {
    constructor(readonly text: string, readonly accept: () => void) { super(); }
    toDOM() {
      const node = document.createElement("span");
      node.className = "scholium-writing-ghost";
      const suffix = document.createElement("span");
      suffix.className = "scholium-writing-ghost-text";
      suffix.textContent = this.text;
      const hint = document.createElement("span");
      hint.className = "scholium-writing-ghost-key";
      hint.textContent = "⇥";
      hint.setAttribute("aria-hidden", "true");
      node.append(suffix, hint);
      node.setAttribute("role", "button");
      node.setAttribute("aria-label", localizedTemplate("Accept suggestion: {text} (Tab)", {text: this.text}));
      node.addEventListener("mousedown", event => { event.preventDefault(); });
      node.addEventListener("click", () => this.accept());
      return node;
    }
    ignoreEvent() { return true; }
  }
  function requestTerms(query: string, context: CompletionContext) {
    const requestID = boundedUUID();
    return new Promise<EditorLinkCompletionCandidate[]>((resolve) => {
      const cancel = () => {
        const pending = pendingLinkQueries.get(requestID);
        if (!pending) return;
        pendingLinkQueries.delete(requestID);
        globalThis.clearTimeout(pending.timeout);
        resolve([]);
      };
      context.addEventListener("abort", cancel, {onDocChange: true});
      const timeout = globalThis.setTimeout(cancel, 5_000);
      pendingLinkQueries.set(requestID, {resolve, timeout});
      options.requestLinkCompletions(requestID, "term", query);
    });
  }
  const writingCompletionSource: CompletionSource = (context) => {
    if (options.isComposing() || context.state.selection.ranges.length !== 1 || !context.state.selection.main.empty
      || positionIsProtected(options, context.state, context.pos)
      || positionIsProtected(options, context.state, Math.max(0, context.pos - 1))) return null;
    const before = context.state.sliceDoc(Math.max(0, context.pos - 512), context.pos);
    const prefix = /[\p{L}\p{N}\p{M} -]{2,48}$/u.exec(before)?.[0];
    if (/[\p{L}\p{N}\p{M}]/u.test(context.state.sliceDoc(context.pos, context.pos + 1))
      || !prefix || !/[\p{L}\p{N}\p{M}]$/u.test(prefix) || /\[\[|@|\//u.test(before)) return null;
    return requestTerms(prefix, context).then(candidates => {
      if (context.aborted) return null;
      return {
        from: context.pos, filter: false,
        options: candidates.filter(c => !c.isAmbiguous && termSuffix(context.state, context.pos, c) !== null).map(candidate => ({
          label: candidate.label, ghostText: termSuffix(context.state, context.pos, candidate),
          apply: (view: EditorView) => {
            if (view.composing || options.isComposing() || view.state.doc !== context.state.doc
              || !view.state.selection.eq(context.state.selection)) return;
            const text = termSuffix(context.state, context.pos, candidate)!;
            if (new TextEncoder().encode(view.state.doc.toString() + text).length > MAX_SOURCE_UTF8_BYTES) return;
            view.dispatch({changes: {from: context.pos, insert: text}, selection: {anchor: context.pos + text.length},
              annotations: [Transaction.userEvent.of("input.complete.scholium.writing"), isolateHistory.of("full")]});
            options.didApply("Complete Term");
          },
        })),
      };
    });
  };

  const inlineWriting = ViewPlugin.fromClass(class {
    decorations: DecorationSet = Decoration.none;
    private generation = 0;
    private timer: ReturnType<typeof setTimeout> | undefined;
    private acceptChoice: (() => void) | null = null;
    constructor(readonly view: EditorView) {}
    clear() {
      this.generation++;
      clearTimeout(this.timer);
      this.acceptChoice = null;
      this.decorations = Decoration.none;
    }
    accept() {
      if (!this.acceptChoice || this.view.composing || options.isComposing()) return false;
      this.acceptChoice();
      return true;
    }
    update(update: ViewUpdate) {
      if (!update.docChanged && !update.selectionSet && !update.focusChanged) return;
      this.clear();
      if (!update.docChanged || !this.view.hasFocus
        || !update.transactions.some(t => t.isUserEvent("input.type"))) return;
      this.schedule();
    }
    schedule() {
      this.clear();
      const generation = this.generation;
      const state = this.view.state;
      this.timer = setTimeout(() => {
        if (this.view.composing || options.isComposing() || !this.view.hasFocus) return;
        const context = new CompletionContext(state, state.selection.main.head, false, this.view);
        void Promise.resolve(writingCompletionSource(context)).then(result => {
          if (this.generation !== generation || this.view.state.doc !== state.doc
            || !this.view.state.selection.eq(state.selection) || !this.view.hasFocus
            || this.view.composing || options.isComposing() || !result) return;
          const choice = result.options[0] as (Completion & {ghostText?: string}) | undefined;
          if (!choice?.ghostText || typeof choice.apply !== "function") return;
          const apply = choice.apply;
          this.acceptChoice = () => {
            if (this.view.state.doc !== state.doc || !this.view.state.selection.eq(state.selection)) return;
            this.clear();
            apply(this.view, choice, result.from, state.selection.main.head);
          };
          this.decorations = Decoration.set([Decoration.widget({
            widget: new Ghost(choice.ghostText, () => this.accept()), side: 1,
          }).range(state.selection.main.head)]);
          this.view.dispatch({});
        });
      }, 300);
    }
    destroy() { this.clear(); }
  }, {
    decorations: value => value.decorations,
    eventHandlers: {
      compositionstart() { this.clear(); this.view.dispatch({}); },
      compositionend() { this.schedule(); },
      blur() { this.clear(); this.view.dispatch({}); },
    },
  });

  const wikilinkCompletionSource: CompletionSource = (context: CompletionContext) => {
    if (!isLiveSuggestionContext(options, context.state)) return null;
    const line = context.state.doc.lineAt(context.pos);
    const scanFrom = Math.max(line.from, context.pos - 512);
    const beforeCursor = context.state.doc.sliceString(scanFrom, context.pos);
    const match = /\[\[([^\]\n|#]{0,510})$/.exec(beforeCursor);
    if (!match) return null;
    const typed = match[1];
    const from = scanFrom + match.index + 2;
    if (positionIsProtected(options, context.state, from - 2)) return null;

    const requestID = boundedUUID();
    const candidates = new Promise<EditorLinkCompletionCandidate[]>((resolve) => {
      const cancel = () => {
        const pending = pendingLinkQueries.get(requestID);
        if (!pending) return;
        pendingLinkQueries.delete(requestID);
        globalThis.clearTimeout(pending.timeout);
        resolve([]);
      };
      context.addEventListener("abort", cancel, {onDocChange: true});
      const timeout = globalThis.setTimeout(cancel, 3_000);
      pendingLinkQueries.set(requestID, {resolve, timeout});
      options.requestLinkCompletions(requestID, "wikilink", typed);
    });
    return candidates.then((resolved) => ({
      from,
      options: resolved
        .filter((candidate) => !candidate.isAmbiguous && candidate.insertion.length > 0)
        .slice(0, 100)
        .map((candidate): Completion => ({
          label: candidate.label,
          detail: candidate.detail,
          type: "scholium-note" satisfies SuggestionType,
          apply: applyWikilinkCandidate(candidate, options.didApply),
        })),
      filter: false,
    }));
  };

  const analysisReferenceCompletionSource: CompletionSource = (
    context: CompletionContext,
  ) => {
    if (!isLiveSuggestionContext(options, context.state)) return null;
    const line = context.state.doc.lineAt(context.pos);
    const scanFrom = Math.max(line.from, context.pos - 512);
    const beforeCursor = context.state.doc.sliceString(scanFrom, context.pos);
    const match = /(^|[\s([{])@([^\n@|\]]{0,510})$/u.exec(beforeCursor);
    if (!match) return null;
    const typed = match[2];
    const from = scanFrom + match.index + match[1].length;
    if (positionIsProtected(options, context.state, from)) return null;

    const requestID = boundedUUID();
    const candidates = new Promise<EditorLinkCompletionCandidate[]>((resolve) => {
      const cancel = () => {
        const pending = pendingLinkQueries.get(requestID);
        if (!pending) return;
        pendingLinkQueries.delete(requestID);
        globalThis.clearTimeout(pending.timeout);
        resolve([]);
      };
      context.addEventListener("abort", cancel, {onDocChange: true});
      const timeout = globalThis.setTimeout(cancel, 3_000);
      pendingLinkQueries.set(requestID, {resolve, timeout});
      options.requestLinkCompletions(requestID, "analysisReference", typed);
    });
    return candidates.then((resolved) => ({
      from,
      options: resolved
        .filter((candidate) => !candidate.isAmbiguous
          && candidate.insertion.length > 0
          && Boolean(candidate.displayText))
        .slice(0, 100)
        .map((candidate): Completion => ({
          label: candidate.label,
          detail: candidate.detail,
          type: "scholium-analysis-reference" satisfies SuggestionType,
          apply: applyAnalysisReferenceCandidate(candidate, options.didApply),
        })),
      filter: false,
    }));
  };

  const slashCompletionSource: CompletionSource = (context: CompletionContext) => {
    if (!isLiveSuggestionContext(options, context.state)) return null;
    const line = context.state.doc.lineAt(context.pos);
    const beforeCursor = context.state.doc.sliceString(line.from, context.pos);
    const match = /\/([\p{L}\p{N}_-]*)$/u.exec(beforeCursor);
    if (!match) return null;
    const slashFrom = line.from + match.index;
    if (slashFrom > line.from
      && !/\s/u.test(context.state.doc.sliceString(slashFrom - 1, slashFrom))) return null;
    if (positionIsProtected(options, context.state, slashFrom)) return null;
    const prefix = context.state.doc.sliceString(line.from, slashFrom);
    const blockContext = /^\s*$/u.test(prefix);
    return {
      from: slashFrom + 1,
      options: slashCommandOptions(options, blockContext, match[1]),
      filter: false,
    };
  };

  const calloutCompletionSource: CompletionSource = (context: CompletionContext) => {
    if (!isLiveSuggestionContext(options, context.state)) return null;
    const line = context.state.doc.lineAt(context.pos);
    if (context.pos - line.from > 512) return null;
    const beforeCursor = context.state.doc.sliceString(line.from, context.pos);
    const match = /^(\s*(?:>\s*)+)\[!([A-Za-z-]*)$/.exec(beforeCursor);
    if (!match || positionIsProtected(options, context.state, context.pos - match[2].length)) {
      return null;
    }
    const typed = match[2].toLocaleLowerCase();
    const dialectCallouts = options.dialect()?.callouts ?? [];
    return {
      from: context.pos - match[2].length,
      options: dialectCallouts
        .filter((callout) => !typed || callout.identifier.startsWith(typed))
        .map((callout): Completion => ({
          label: localizedCallout(callout.identifier, callout).label,
          type: "scholium-callout-role" satisfies SuggestionType,
          apply: (view, completion, from, to) => {
            const insert = `${callout.identifier}] `;
            view.dispatch({
              changes: {from, to, insert},
              selection: {anchor: from + insert.length},
              annotations: [
                pickedCompletion.of(completion),
                Transaction.userEvent.of("input.complete.scholium.callout"),
              ],
            });
            options.didApply("Insert Callout");
          },
        })),
      filter: false,
    };
  };

  let nativeID = 0;
  const nativePresentation = ViewPlugin.fromClass(class {
    private signature = "";
    private revision = 0;
    private measureFallback: number | undefined;
    constructor(readonly view: EditorView) { this.refresh(); }
    update(update: ViewUpdate) {
      if (update.docChanged || update.selectionSet) this.revision += 1;
      this.refresh();
    }
    private read() {
      return {
        items: currentCompletions(this.view.state).slice(0, 100)
          .map(item => ({label: item.label.slice(0, 512), detail: (item.detail ?? "").slice(0, 1024)})),
        anchor: this.view.coordsAtPos(this.view.state.selection.main.head),
        selected: selectedCompletionIndex(this.view.state) ?? -1,
      };
    }
    private write({items, anchor, selected}: {items: Array<{label: string; detail: string}>; anchor: {left: number; top: number; bottom: number} | null; selected: number}) {
      window.clearTimeout(this.measureFallback);
      this.measureFallback = undefined;
      if (!items.length || !anchor || this.view.root.activeElement !== this.view.contentDOM || this.view.composing) {
        options.nativeFloating.hide(nativeID);
        this.signature = "";
        return;
      }
      const signature = JSON.stringify({items, anchor, selected, revision: this.revision});
      if (signature === this.signature) return;
      this.signature = signature;
      nativeID = options.nativeFloating.show({
        kind: "suggestions", left: anchor.left, top: anchor.top, bottom: anchor.bottom,
        html: "", css: "", items, selected,
      }, {
        dismiss: () => { closeCompletion(this.view); },
        select: index => {
          if (this.view.composing || this.view.root.activeElement !== this.view.contentDOM) return;
          if (selectedCompletionIndex(this.view.state) !== index) {
            this.view.dispatch({effects: setSelectedCompletion(index)});
          }
        },
        choose: index => {
          if (this.view.composing || this.view.root.activeElement !== this.view.contentDOM) return;
          this.view.dispatch({effects: setSelectedCompletion(index)});
          acceptCompletion(this.view);
        },
      });
    }
    refresh() {
      window.clearTimeout(this.measureFallback);
      // WKWebView can throttle animation frames independently of keyboard input.
      // The same public geometry read runs once at idle if its keyed measure stalls.
      this.measureFallback = window.setTimeout(() => this.write(this.read()), 50);
      this.view.requestMeasure({key: this, read: () => this.read(), write: value => this.write(value)});
    }
    suspend() {
      window.clearTimeout(this.measureFallback);
      this.measureFallback = undefined;
      options.nativeFloating.hide(nativeID);
      this.signature = "";
    }
    destroy() { this.suspend(); }
  }, {
    eventHandlers: {
      compositionstart() { this.suspend(); },
      compositionend() { this.refresh(); },
    },
  });

  return {
    writingCompletionSource,
    extension: [autocompletion({
      override: [
        calloutCompletionSource,
        wikilinkCompletionSource,
        analysisReferenceCompletionSource,
        slashCompletionSource,
      ],
      activateOnCompletion: (completion) => completion.type === "scholium-command-callout",
      maxRenderedOptions: 7,
      icons: false,
      tooltipClass: () => "scholium-editor-suggestions",
      addToOptions: [{render: suggestionSymbol, position: 20}],
    }), inlineWriting, Prec.highest(keymap.of([
      {key: "Tab", run: view => view.plugin(inlineWriting)?.accept() ?? false},
      {key: "Escape", run: view => {
        const plugin = view.plugin(inlineWriting);
        if (!plugin) return false;
        const visible = plugin.decorations.size > 0;
        plugin.clear(); view.dispatch({}); return visible;
      }},
    ])), nativePresentation, EditorView.baseTheme({
      ".scholium-writing-ghost": {color: "var(--scholium-native-secondary-label)", cursor: "pointer", userSelect: "none"},
      ".scholium-writing-ghost-text": {textDecorationLine: "underline", textDecorationStyle: "dotted", textUnderlineOffset: "0.2em"},
      ".scholium-writing-ghost-key": {fontFamily: "system-ui", fontSize: "0.65em", marginInlineStart: "0.4em", whiteSpace: "nowrap"},
      // Keep CodeMirror's single accessible list and aria-activedescendant relation.
      // Native rows are a pointer/visual projection and do not duplicate that AX tree.
      ".cm-tooltip-autocomplete.scholium-editor-suggestions": {
        clipPath: "inset(100%)", pointerEvents: "none",
      },
    })],
    wikilinkCompletionSource,
    analysisReferenceCompletionSource,
    slashCompletionSource,
    calloutCompletionSource,
    resolveLinkCompletionQuery(requestID: string, value: unknown) {
      const pending = pendingLinkQueries.get(requestID);
      if (!pending) return;
      pendingLinkQueries.delete(requestID);
      globalThis.clearTimeout(pending.timeout);
      pending.resolve(Array.isArray(value)
        ? value.slice(0, 100).filter(validLinkCandidate)
        : []);
    },
  };
}

export const inputSuggestionTesting = {
  localISODate,
};
