import {exactSourceFitsChanges, exactSourceState} from "./exact-source-history";
import {boundedUUID} from "./uuid";
import {isolateHistory} from "@codemirror/commands";
import {
  CompletionContext,
  acceptCompletion,
  closeCompletion,
  currentCompletions,
  completionStatus,
  selectedCompletionIndex,
  setSelectedCompletion,
  autocompletion,
  pickedCompletion,
  snippet,
  type Completion,
  type CompletionResult,
  type CompletionSource,
} from "@codemirror/autocomplete";
import {
  EditorSelection,
  EditorState,
  Prec,
  Transaction,
  type Extension,
} from "@codemirror/state";
import {
  type EditorMode,
  type MarkdownEditingDialect,
} from "./protocol";
import {transformMarkdown} from "./transformations";
import {exactOffsetForNormalizedOffset} from "./state";
import {systemSymbolElement, type WebSystemSymbolKey} from "./system-symbols";
import {Decoration, WidgetType, keymap, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate} from "@codemirror/view";
import type {NativeSuggestionPort} from "./native-floating";
import {localized, localizedTemplate, localizedCallout, type WebInterfaceLocalizationKey} from "./localization";

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

export type EditorInputSuggestionActionID = "insertCitation";
export interface EditorCitationSuggestionIntent {
  readonly actionID: EditorInputSuggestionActionID;
  readonly requestID: string;
  readonly query: string;
  readonly fromUTF16: number;
  readonly toUTF16: number;
  readonly caretUTF16Offset: number;
  readonly editorCaretUTF16Offset: number;
  readonly interactionRevision: number;
}

export interface EditorInputSuggestionActionCompletion extends Completion {
  readonly actionID: EditorInputSuggestionActionID;
}

interface SourceRange {
  readonly from: number;
  readonly to: number;
}

interface InputSuggestionOptions {
  nativeFloating: NativeSuggestionPort;
  mode(state: EditorState): EditorMode;
  dialect(): MarkdownEditingDialect | null;
  isComposing(): boolean;
  protectedRanges(state: EditorState): readonly SourceRange[];
  requestLinkCompletions(
    requestID: string,
    kind: EditorLinkCompletionKind,
    query: string,
  ): void;
  requestCitationInsertion?(intent: EditorCitationSuggestionIntent): void;
  citationContextRevision?(): number;
  canInsertCitation?(state: EditorState): boolean;
  requestWritingContinuation?(requestID: string, state: EditorState, position: number): void;
  cancelWritingContinuation?(requestID: string): void;
  didApply(undoLabel: string): void;
}

export interface EditorInputSuggestionsController {
  readonly extension: Extension;
  readonly writingCompletionSource: CompletionSource;
  readonly wikilinkCompletionSource: CompletionSource;
  readonly analysisReferenceCompletionSource: CompletionSource;
  readonly citationCompletionSource: CompletionSource;
  readonly slashCompletionSource: CompletionSource;
  readonly calloutCompletionSource: CompletionSource;
  resetDocument(): void;
  resolveLinkCompletionQuery(requestID: string, candidates: unknown): void;
  configureWritingContinuation(enabled: boolean, contextKey: string): void;
  configureWritingIndexContext(contextKey: string): void;
  setWritingContinuationStatus(requestID: string, value: unknown): void;
  resolveWritingContinuation(requestID: string, value: unknown): void;
}

type WritingContinuationPhase = "preparing" | "retrieving" | "generating";
type WritingSource = "ai" | "index";

function writingContinuationPhaseLabel(
  phase: WritingContinuationPhase,
): WebInterfaceLocalizationKey {
  switch (phase) {
    case "preparing": return "AI continuation is preparing.";
    case "retrieving": return "AI continuation is retrieving related context.";
    case "generating": return "AI continuation is composing.";
  }
}

type SuggestionType =
  | "scholium-note"
  | "scholium-analysis-reference"
  | "scholium-command-citation"
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
  "scholium-command-citation": "text-quote",
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
    && !state.readOnly && state.facet(EditorView.editable)
    && !options.isComposing()
    && state.selection.ranges.length === 1
    && state.selection.main.empty;
}

function isWritingSuggestionContext(options: InputSuggestionOptions, state: EditorState) {
  const mode = options.mode(state);
  return (mode === "livePreview" || mode === "source")
    && !state.readOnly && state.facet(EditorView.editable)
    && !options.isComposing()
    && state.selection.ranges.length === 1 && state.selection.main.empty;
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

function suggestionSpanIsProtected(options: InputSuggestionOptions, state: EditorState, from: number, to: number) {
  return options.protectedRanges(state).some(range => from < range.to && to > range.from);
}

function analysisReferenceContext(options: InputSuggestionOptions, state: EditorState, position: number) {
  if (!isLiveSuggestionContext(options, state)) return null;
  const line = state.doc.lineAt(position);
  const scanFrom = Math.max(line.from, position - 514);
  const beforeCursor = state.doc.sliceString(scanFrom, position);
  const match = /(^|[\s([{])@([^\n@|\]]{0,512})$/u.exec(beforeCursor);
  if (!match || match[2].length > 512) return null;
  const from = scanFrom + match.index + match[1].length;
  if (suggestionSpanIsProtected(options, state, from, position)) return null;
  return {from, query: match[2]};
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

/** One visible, literal sentence suffix; never hidden newlines, controls or Markdown structures. */
export function safeContinuationSuffix(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim() || value.length > 512
    || /[\u0000-\u001f\u007f\u0085\u2028\u2029\u202a-\u202e\u2066-\u2069\\`*_{}[\]<>|]/u.test(value)) return null;
  // Reject malformed UTF-16 rather than allowing display/insertion disagreement.
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(++index);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return null;
    } else if (code >= 0xdc00 && code <= 0xdfff) return null;
  }
  // A response may complete the current sentence, but it must not continue
  // into a second sentence. The native runtime applies the same check; keep
  // the page-side guard so a malformed bridge value never becomes a ghost.
  let sentenceEnd: number | null = null;
  for (let index = 0; index < value.length; index++) {
    const end = sentenceBoundaryEnd(value, index);
    if (end === null) continue;
    if (sentenceEnd !== null || value.slice(end).trim()) return null;
    sentenceEnd = end;
    index = end - 1;
  }
  return value;
}

const sentenceClosingCharacters = /[\])}"'’”》」』）】〉》]/u;

function sentenceBoundaryEnd(value: string, index: number): number | null {
  if (!/[.!?。！？…]/u.test(value[index] ?? "")) return null;
  if (value[index] === "." && /\d/u.test(value[index - 1] ?? "") && /\d/u.test(value[index + 1] ?? "")) return null;
  let end = index + 1;
  while (end < value.length && sentenceClosingCharacters.test(value[end])) end++;
  const cjkTerminator = /[。！？]/u.test(value[index] ?? "");
  return cjkTerminator || end === value.length || /\s/u.test(value[end] ?? "") ? end : null;
}

function sentenceIsUnfinished(before: string): boolean {
  const withoutTrailingSpace = before.replace(/\s+$/u, "");
  const withoutClosers = withoutTrailingSpace.replace(
    new RegExp(`${sentenceClosingCharacters.source}+$`, "u"),
    "",
  ).replace(/\s+$/u, "");
  return !/[.!?。！？…]$/u.test(withoutClosers);
}

function continuationContextAllowed(options: InputSuggestionOptions, state: EditorState, position: number) {
  if (!isWritingSuggestionContext(options, state)
    || positionIsProtected(options, state, position)
    || positionIsProtected(options, state, Math.max(0, position - 1))) return false;
  const before = state.sliceDoc(Math.max(0, position - 512), position);
  return /[\p{L}\p{N}]/u.test(before)
    && sentenceIsUnfinished(before)
    && !/\[\[[^\]\n]*$|(?:^|\s)@[^\s]*$|(?:^|\s)\/[^\s]*$/u.test(before)
    && !/[\p{L}\p{N}\p{M}]/u.test(state.sliceDoc(position, position + 1));
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
    if (!exactSourceFitsChanges(view.state, transformed.changes)) return;
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

function slashCommandOptions(
  options: InputSuggestionOptions,
  blockContext: boolean,
) {
  const commands: Array<Completion & {label: WebInterfaceLocalizationKey; blockOnly?: boolean}> = [
    {
      label: "Callout",
      type: "scholium-command-callout" satisfies SuggestionType,
      apply: replaceSlashWithText("> [!", "Insert Callout", options.didApply),
      blockOnly: true,
    },
    {
      label: "Date",
      type: "scholium-command-date" satisfies SuggestionType,
      apply: replaceSlashWithText(localISODate, "Insert Date", options.didApply),
    },
    {
      label: "Inline Math",
      type: "scholium-command-math" satisfies SuggestionType,
      apply: replaceSlashWithSnippet("$${}$", "Insert Inline Math", options.didApply),
    },
    {
      label: "Display Math",
      type: "scholium-command-math" satisfies SuggestionType,
      apply: replaceSlashWithSnippet("$$\n${}\n$$", "Insert Display Math", options.didApply),
      blockOnly: true,
    },
    {
      label: "Mermaid",
      type: "scholium-command-mermaid" satisfies SuggestionType,
      apply: replaceSlashWithSnippet("```mermaid\n${}\n```", "Insert Mermaid", options.didApply),
      blockOnly: true,
    },
    {
      label: "Table",
      type: "scholium-command-table" satisfies SuggestionType,
      apply: replaceSlashWithSnippet(
        "| ${1:Column 1} | ${2:Column 2} |\n| --- | --- |\n| ${3} | ${4} |",
        "Insert Table",
        options.didApply,
      ),
      blockOnly: true,
    },
    {
      label: "Footnote",
      type: "scholium-command-footnote" satisfies SuggestionType,
      apply: replaceSlashWithFootnote(options),
    },
    {
      label: "Code Block",
      type: "scholium-command-code" satisfies SuggestionType,
      apply: replaceSlashWithSnippet(
        "```${1:language}\n${2}\n```",
        "Insert Code Block",
        options.didApply,
      ),
      blockOnly: true,
    },
    {
      label: "Divider",
      type: "scholium-command-divider" satisfies SuggestionType,
      apply: replaceSlashWithText("---", "Insert Divider", options.didApply),
      blockOnly: true,
    },
  ];
  return commands.filter((command) => blockContext || !command.blockOnly)
    .map(command => ({...command, filterText: command.label, label: localized(command.label)}));
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
  let continuationEnabled = false;
  let continuationContextKey = "";
  let indexContextKey = "";
  let clearInlineWriting: (() => void) | undefined;
  let clearAIWriting: (() => void) | undefined;
  let clearIndexWriting: (() => void) | undefined;
  let showInlineContinuationStatus: ((requestID: string, phase: WritingContinuationPhase) => void) | undefined;
  const pendingContinuations = new Map<string, {
    resolve(value: {text: string | null; reason: string | null}): void;
    timeout: ReturnType<typeof setTimeout>;
  }>();
  function cancelContinuations() {
    for (const [requestID, pending] of pendingContinuations) {
      clearTimeout(pending.timeout);
      options.cancelWritingContinuation?.(requestID);
      pending.resolve({text: null, reason: null});
    }
    pendingContinuations.clear();
  }
  function requestContinuation(state: EditorState, position: number) {
    const requestID = boundedUUID();
    const promise = new Promise<{text: string | null; reason: string | null}>(resolve => {
      const timeout = setTimeout(() => {
        pendingContinuations.delete(requestID);
        options.cancelWritingContinuation?.(requestID);
        resolve({text: null, reason: localized("AI continuation timed out.")});
      }, 8_000);
      pendingContinuations.set(requestID, {resolve, timeout});
      if (options.requestWritingContinuation) options.requestWritingContinuation(requestID, state, position);
      else resolveContinuation(requestID, {text: null, reason: null});
    });
    return {requestID, promise};
  }
  function setContinuationStatus(requestID: string, value: unknown) {
    if (!pendingContinuations.has(requestID)) return;
    const payload = value && typeof value === "object" ? value as {phase?: unknown} : {};
    const phase = payload.phase;
    if (phase !== "preparing" && phase !== "retrieving" && phase !== "generating") return;
    showInlineContinuationStatus?.(requestID, phase);
  }
  function resolveContinuation(requestID: string, value: unknown) {
    const pending = pendingContinuations.get(requestID);
    if (!pending) return;
    pendingContinuations.delete(requestID);
    clearTimeout(pending.timeout);
    const payload = value && typeof value === "object" ? value as {text?: unknown; reason?: unknown} : {};
    pending.resolve({text: safeContinuationSuffix(payload.text),
      reason: typeof payload.reason === "string" && payload.reason.trim() ? payload.reason.slice(0, 512) : null});
  }
  const pendingLinkQueries = new Map<string, {
    resolve(candidates: EditorLinkCompletionCandidate[]): void;
    timeout: ReturnType<typeof setTimeout>;
    writingTerm?: boolean;
  }>();

  function cancelWritingTermQueries() {
    for (const [requestID, pending] of pendingLinkQueries) {
      if (!pending.writingTerm) continue;
      pendingLinkQueries.delete(requestID);
      globalThis.clearTimeout(pending.timeout);
      pending.resolve([]);
    }
  }

  class Ghost extends WidgetType {
    constructor(readonly text: string, readonly accept: () => void, readonly source: WritingSource, readonly reason: string | null = null) { super(); }
    toDOM() {
      const node = document.createElement("span");
      node.className = "scholium-writing-ghost";
      const suffix = document.createElement("span");
      suffix.className = "scholium-writing-ghost-text";
      suffix.textContent = this.text;
      const hint = document.createElement("span");
      hint.className = "scholium-writing-ghost-key";
      hint.textContent = `${localized(this.source === "ai" ? "AI" : "Index")} ⇥`;
      hint.setAttribute("aria-hidden", "true");
      node.append(suffix);
      if (this.reason) {
        const badge = document.createElement("span");
        badge.className = "scholium-writing-ghost-error-badge";
        badge.textContent = "!";
        badge.setAttribute("aria-hidden", "true");
        node.append(badge);
      }
      node.append(hint);
      node.setAttribute("role", "button");
      node.setAttribute("aria-label", localizedTemplate(this.source === "ai" ? "Accept AI continuation: {text} (Tab)" : "Accept index suggestion: {text} (Tab)", {text: this.text}));
      if (this.reason) { node.title = this.reason; node.setAttribute("aria-description", this.reason); }
      node.addEventListener("mousedown", event => { event.preventDefault(); });
      node.addEventListener("click", () => this.accept());
      return node;
    }
    ignoreEvent() { return true; }
  }

  class ContinuationStatus extends WidgetType {
    constructor(readonly message: string, readonly active: boolean) { super(); }
    toDOM() {
      const node = document.createElement("span");
      node.className = `scholium-writing-status${this.active ? " scholium-writing-status-active" : " scholium-writing-status-error"}`;
      if (this.active) {
        const orb = document.createElement("span");
        orb.className = "scholium-writing-orb";
        orb.setAttribute("aria-hidden", "true");
        for (let index = 0; index < 3; index++) {
          const dot = document.createElement("span");
          dot.className = "scholium-writing-orb-dot";
          dot.setAttribute("aria-hidden", "true");
          orb.append(dot);
        }
        node.append(orb);
      }
      if (this.active) {
        const label = document.createElement("span");
        label.textContent = this.message;
        node.append(label);
      } else {
        const badge = document.createElement("span");
        badge.className = "scholium-writing-status-badge";
        badge.textContent = "!";
        badge.setAttribute("aria-hidden", "true");
        node.append(badge);
      }
      node.setAttribute("role", "status");
      node.setAttribute("aria-live", "polite");
      node.setAttribute("aria-atomic", "true");
      node.setAttribute("aria-label", this.message);
      node.title = this.message;
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
      pendingLinkQueries.set(requestID, {resolve, timeout, writingTerm: true});
      options.requestLinkCompletions(requestID, "term", query);
    });
  }
  const writingCompletionSource: CompletionSource = (context) => {
    if (!isWritingSuggestionContext(options, context.state)
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
            if (view.composing || !isWritingSuggestionContext(options, view.state) || view.state.doc !== context.state.doc
              || !view.state.selection.eq(context.state.selection)) return false;
            const text = termSuffix(context.state, context.pos, candidate)!;
            if (!exactSourceFitsChanges(view.state, [{from: context.pos, to: context.pos, insert: text}])) return false;
            view.dispatch({changes: {from: context.pos, insert: text}, selection: {anchor: context.pos + text.length},
              annotations: Transaction.userEvent.of("input.complete.scholium.writing")});
            options.didApply("Complete Term");
            return true;
          },
        })),
      };
    });
  };

  const inlineWriting = ViewPlugin.fromClass(class {
    decorations: DecorationSet = Decoration.none;
    private generation = 0;
    private timer: ReturnType<typeof setTimeout> | undefined;
    private acceptChoice: (() => boolean) | null = null;
    private continuationRequestID: string | null = null;
    private source: WritingSource | null = null;
    constructor(readonly view: EditorView) {
      clearInlineWriting = () => { this.clear(); this.view.dispatch({}); };
      clearAIWriting = () => { if (this.source === "ai") { this.clear(); this.view.dispatch({}); } };
      clearIndexWriting = () => { if (this.source === "index") { this.clear(); this.view.dispatch({}); } };
      showInlineContinuationStatus = (requestID, phase) => {
        if (this.continuationRequestID !== requestID || !this.isValidContext()) return;
        this.showStatus(writingContinuationPhaseLabel(phase), true);
      };
    }
    clear() {
      this.generation++;
      clearTimeout(this.timer);
      cancelContinuations();
      cancelWritingTermQueries();
      this.acceptChoice = null;
      this.continuationRequestID = null;
      this.source = null;
      this.decorations = Decoration.none;
    }
    private isValidContext() {
      return this.view.hasFocus && !this.view.composing
        && isWritingSuggestionContext(options, this.view.state);
    }
    private showStatus(message: string, active: boolean) {
      if (!this.isValidContext()) return;
      this.decorations = Decoration.set([Decoration.widget({
        widget: new ContinuationStatus(message, active), side: 1,
      }).range(this.view.state.selection.main.head)]);
      this.view.dispatch({});
    }
    accept() {
      if (!this.acceptChoice || this.view.composing || !isWritingSuggestionContext(options, this.view.state)) return false;
      return this.acceptChoice();
    }
    update(update: ViewUpdate) {
      if (!isWritingSuggestionContext(options, update.state)) { this.clear(); return; }
      if (!update.docChanged && !update.selectionSet && !update.focusChanged) return;
      this.clear();
      if (!update.docChanged || !this.view.hasFocus
        || !update.transactions.some(t => t.isUserEvent("input.type"))) return;
      this.schedule();
    }
    schedule() {
      this.clear();
      if (!isWritingSuggestionContext(options, this.view.state)) return;
      const generation = this.generation;
      const state = this.view.state;
      const valid = () => this.generation === generation && this.view.state.doc === state.doc
        && this.view.state.selection.eq(state.selection) && this.view.hasFocus
        && !this.view.composing && isWritingSuggestionContext(options, this.view.state);
      const position = state.selection.main.head;
      const aiEligible = continuationEnabled && continuationContextAllowed(options, state, position);
      this.source = aiEligible ? "ai" : "index";
      this.timer = setTimeout(async () => {
        if (!valid()) return;
        let fallbackReason: string | null = null;
        if (aiEligible) {
          const request = requestContinuation(state, position);
          this.continuationRequestID = request.requestID;
          this.showStatus(writingContinuationPhaseLabel("preparing"), true);
          const result = await request.promise;
          if (!valid()) return;
          this.continuationRequestID = null;
          if (result.text) {
            const text = result.text;
            this.acceptChoice = () => {
              if (!valid() || !exactSourceFitsChanges(this.view.state, [{from: position, to: position, insert: text}])) {
                this.clear(); this.view.dispatch({}); return false;
              }
              this.clear();
              this.view.dispatch({changes: {from: position, insert: text}, selection: {anchor: position + text.length},
                annotations: Transaction.userEvent.of("input.complete.scholium.continuation")});
              options.didApply("Accept AI Continuation");
              return true;
            };
            this.decorations = Decoration.set([Decoration.widget({widget: new Ghost(text, () => this.accept(), "ai"), side: 1}).range(position)]);
            this.view.dispatch({});
            return;
          }
          fallbackReason = result.reason;
        }
        this.source = "index";
        this.decorations = Decoration.none;
        this.view.dispatch({});
        const context = new CompletionContext(state, state.selection.main.head, false, this.view);
        let result: CompletionResult | null = null;
        try { result = await writingCompletionSource(context); }
        catch { /* An unavailable local index has no completion to display. */ }
        if (!valid()) return;
        const choice = result?.options[0] as (Completion & {ghostText?: string; apply?: (view: EditorView) => boolean}) | undefined;
        if (!choice?.ghostText || typeof choice.apply !== "function") {
          if (fallbackReason) this.showStatus(fallbackReason, false);
          return;
        }
        const apply = choice.apply;
        this.acceptChoice = () => {
          if (!valid()) { this.clear(); this.view.dispatch({}); return false; }
          const accepted = apply(this.view);
          if (!accepted) { this.clear(); this.view.dispatch({}); }
          return accepted;
        };
        this.decorations = Decoration.set([Decoration.widget({
          widget: new Ghost(choice.ghostText, () => this.accept(), "index", fallbackReason), side: 1,
        }).range(state.selection.main.head)]);
        this.view.dispatch({});
      }, aiEligible ? 1_200 : 300);
    }
    destroy() {
      this.clear();
      clearInlineWriting = undefined;
      clearAIWriting = undefined;
      clearIndexWriting = undefined;
      showInlineContinuationStatus = undefined;
    }
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
    if (suggestionSpanIsProtected(options, context.state, from - 2, context.pos)) return null;

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

  let citationDocumentEpoch = 0;
  const citationCompletionSource: CompletionSource = (context: CompletionContext) => {
    if (!options.requestCitationInsertion || !options.citationContextRevision
      || !isLiveSuggestionContext(options, context.state) || context.state.readOnly
      || !context.state.facet(EditorView.editable)
      || options.canInsertCitation?.(context.state) === false) return null;
    const reference = analysisReferenceContext(options, context.state, context.pos);
    if (!reference) return null;
    const {from, query} = reference;
    const source = context.state.field(exactSourceState, false)?.text;
    if (source === undefined) return null;
    const fromUTF16 = exactOffsetForNormalizedOffset(source, from);
    const toUTF16 = exactOffsetForNormalizedOffset(source, context.pos);
    const interactionRevision = options.citationContextRevision();
    if (fromUTF16 === null || toUTF16 === null || !Number.isSafeInteger(interactionRevision)
      || interactionRevision < 0 || source.slice(fromUTF16, toUTF16) !== `@${query}`) return null;
    const documentEpoch = citationDocumentEpoch;
    const intent: EditorCitationSuggestionIntent = {
      actionID: "insertCitation", requestID: boundedUUID(), query, fromUTF16, toUTF16,
      caretUTF16Offset: toUTF16, editorCaretUTF16Offset: context.pos, interactionRevision,
    };
    let accepted = false;
    const action: EditorInputSuggestionActionCompletion = {
      actionID: "insertCitation", label: localized("Insert Citation…"), detail: "Zotero",
      type: "scholium-command-citation" satisfies SuggestionType, boost: 99,
      apply: (view, _completion, currentFrom, currentTo) => {
        if (accepted || documentEpoch !== citationDocumentEpoch || !view.hasFocus || view.composing
          || !isLiveSuggestionContext(options, view.state) || view.state.readOnly || !view.state.facet(EditorView.editable)
          || options.canInsertCitation?.(view.state) === false
          || view.state.doc !== context.state.doc || !view.state.selection.eq(context.state.selection)
          || view.state.field(exactSourceState, false)?.text !== source
          || options.citationContextRevision?.() !== interactionRevision
          || currentFrom !== from || currentTo !== context.pos
          || options.protectedRanges(view.state).some(range => from < range.to && context.pos > range.from)) return;
        accepted = true;
        closeCompletion(view);
        options.requestCitationInsertion?.(intent);
      },
    };
    return {from, options: [action], filter: false};
  };

  const analysisReferenceCompletionSource: CompletionSource = (
    context: CompletionContext,
  ) => {
    const reference = analysisReferenceContext(options, context.state, context.pos);
    if (!reference) return null;
    const {from, query: typed} = reference;

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

  const slashCompletionSource = (context: CompletionContext): CompletionResult | null => {
    if (!isLiveSuggestionContext(options, context.state)) return null;
    const line = context.state.doc.lineAt(context.pos);
    const beforeCursor = context.state.doc.sliceString(line.from, context.pos);
    const match = /\/([\p{L}\p{N}-]*)$/u.exec(beforeCursor);
    if (!match) return null;
    const slashFrom = line.from + match.index;
    if (slashFrom > line.from
      && !/\s/u.test(context.state.doc.sliceString(slashFrom - 1, slashFrom))) return null;
    if (positionIsProtected(options, context.state, slashFrom)) return null;
    const prefix = context.state.doc.sliceString(line.from, slashFrom);
    const blockContext = /^\s*$/u.test(prefix);
    return {
      from: slashFrom + 1,
      options: slashCommandOptions(options, blockContext).filter(command =>
        [command.label, command.filterText].some(label => label.toLocaleLowerCase().includes(match[1].toLocaleLowerCase()))),
      filter: false,
      update: (_current, _from, _to, context) => slashCompletionSource(context),
    };
  };

  const calloutCompletionSource = (context: CompletionContext): CompletionResult | null => {
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
            let end = to;
            let folding = "";
            if (view.state.sliceDoc(end, end + 1) === "]") {
              end += 1;
              const marker = view.state.sliceDoc(end, end + 1);
              if (marker === "+" || marker === "-") { folding = marker; end += 1; }
            }
            const following = view.state.sliceDoc(end, end + 1);
            const separator = /^[ \t]$/.test(following) ? following : " ";
            if (following === separator) end += 1;
            const insert = `${callout.identifier}]${folding}${separator}`;
            view.dispatch({
              changes: {from, to: end, insert},
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
      update: (_current, _from, _to, context) => calloutCompletionSource(context),
    };
  };

  let nativeID = 0;
  const nativePresentation = ViewPlugin.fromClass(class {
    private destroyed = false;
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
        state: this.view.state, status: completionStatus(this.view.state),
        items: currentCompletions(this.view.state).slice(0, 100)
          .map(item => ({label: item.label.slice(0, 512), detail: (item.detail ?? "").slice(0, 1024)})),
        anchor: this.view.coordsAtPos(this.view.state.selection.main.head),
        selected: selectedCompletionIndex(this.view.state) ?? -1,
      };
    }
    private write({items, anchor, selected, state, status}: {state: EditorState; status: ReturnType<typeof completionStatus>; items: Array<{label: string; detail: string}>; anchor: {left: number; top: number; bottom: number} | null; selected: number}) {
      if (this.destroyed) return;
      window.clearTimeout(this.measureFallback);
      this.measureFallback = undefined;
      if (!anchor || this.view.root.activeElement !== this.view.contentDOM
        || this.view.composing || !isLiveSuggestionContext(options, this.view.state)) {
        options.nativeFloating.hide(nativeID);
        this.signature = "";
        return;
      }
      // Retain the native container through an asynchronous query. Its old
      // callbacks reject changed source/selection until the new result arrives.
      if (!items.length && status === "pending") return;
      if (!items.length) {
        options.nativeFloating.hide(nativeID);
        this.signature = "";
        return;
      }
      const valid = () => !this.destroyed && state.doc === this.view.state.doc
        && state.selection.eq(this.view.state.selection)
        && !this.view.composing && isLiveSuggestionContext(options, this.view.state)
        && this.view.root.activeElement === this.view.contentDOM;
      const signature = JSON.stringify({items, anchor, selected, revision: this.revision});
      if (signature === this.signature) return;
      this.signature = signature;
      nativeID = options.nativeFloating.show({
        left: anchor.left, top: anchor.top, bottom: anchor.bottom, items, selected,
      }, {
        dismiss: () => { closeCompletion(this.view); },
        select: index => {
          if (!valid()) return;
          if (selectedCompletionIndex(this.view.state) !== index) {
            this.view.dispatch({effects: setSelectedCompletion(index)});
          }
        },
        choose: index => {
          if (!valid()) return false;
          this.view.dispatch({effects: setSelectedCompletion(index)});
          return acceptCompletion(this.view);
        },
      });
    }
    refresh() {
      if (this.destroyed) return;
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
    destroy() { this.destroyed = true; this.suspend(); }
  }, {
    eventHandlers: {
      compositionstart() { this.suspend(); },
      compositionend() { this.refresh(); },
    },
  });

  return {
    resetDocument() {
      citationDocumentEpoch++;
      clearInlineWriting?.();
      cancelContinuations();
      for (const pending of pendingLinkQueries.values()) {
        globalThis.clearTimeout(pending.timeout);
        pending.resolve([]);
      }
      pendingLinkQueries.clear();
    },
    configureWritingContinuation(enabled, contextKey) {
      if (continuationEnabled === enabled && continuationContextKey === contextKey) return;
      continuationEnabled = enabled;
      continuationContextKey = contextKey;
      clearAIWriting?.();
      cancelContinuations();
    },
    configureWritingIndexContext(contextKey) {
      if (indexContextKey === contextKey) return;
      indexContextKey = contextKey;
      clearIndexWriting?.();
      cancelWritingTermQueries();
    },
    setWritingContinuationStatus: setContinuationStatus,
    resolveWritingContinuation: resolveContinuation,
    writingCompletionSource,
    extension: [autocompletion({
      override: [
        slashCompletionSource,
        calloutCompletionSource,
        wikilinkCompletionSource,
        citationCompletionSource,
        analysisReferenceCompletionSource,
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
        const visible = plugin.decorations.size > 0 || pendingContinuations.size > 0;
        plugin.clear(); view.dispatch({}); return visible;
      }},
    ])), nativePresentation,
    // One acceptance boundary includes our sources and CodeMirror snippets,
    // retaining their complete transactions while separating later typing.
    EditorState.transactionExtender.of(transaction => transaction.isUserEvent("input.complete")
      ? {annotations: isolateHistory.of("full")} : null),
    EditorView.baseTheme({
      ".scholium-writing-ghost": {color: "var(--scholium-native-secondary-label)", cursor: "pointer", userSelect: "none", font: "inherit", marginInlineStart: "2px"},
      ".scholium-writing-ghost-text": {textDecorationLine: "underline", textDecorationStyle: "dotted", textUnderlineOffset: "0.2em"},
      ".scholium-writing-ghost-key": {display: "inline-flex", alignItems: "center", border: "1px solid currentColor", borderRadius: "0.35em", paddingInline: "0.3em", fontSize: "0.65em", marginInlineStart: "0.4em", whiteSpace: "nowrap"},
      ".scholium-writing-ghost-error-badge": {fontSize: "0.65em", marginInlineStart: "0.4em"},
      // Keep CodeMirror's single accessible list and aria-activedescendant relation.
      // Native rows are a pointer/visual projection and do not duplicate that AX tree.
      ".cm-tooltip-autocomplete.scholium-editor-suggestions": {
        clipPath: "inset(100%)", pointerEvents: "none",
      },
    })],
    wikilinkCompletionSource,
    analysisReferenceCompletionSource,
    citationCompletionSource,
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
