import {exactSourceFitsChanges, exactSourceState} from "./exact-source-history";
import {boundedUUID} from "./uuid";
import {isolateHistory} from "@codemirror/commands";
import {
  type CompletionContext,
  acceptCompletion,
  closeCompletion,
  currentCompletions,
  completionStatus,
  selectedCompletionIndex,
  setSelectedCompletion,
  startCompletion,
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
  displayText?: string;
  availability: "available" | "ambiguous" | "unsupportedSyntax" | "unavailable";
  unavailableReason?: string;
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

function sameExactSource(left: EditorState, right: EditorState) {
  const source = left.field(exactSourceState, false);
  const other = right.field(exactSourceState, false);
  return source === other || source !== undefined && other !== undefined && source.eq(other);
}

export type WritingContinuationCancellationReason = "superseded" | "typing" | "deletion" | "source" | "caret"
  | "focus" | "composition" | "configuration" | "mode" | "context" | "dismissed" | "accepted" | "lifecycle" | "watchdog";

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
  cancelWritingTermQuery?(requestID: string): void;
  requestCitationInsertion?(intent: EditorCitationSuggestionIntent): void;
  citationContextRevision?(): number;
  canInsertCitation?(state: EditorState): boolean;
  canContinueWriting?(state: EditorState, position: number): boolean;
  writingContextReady?(state: EditorState, position: number): boolean;
  requestWritingContinuation?(requestID: string, state: EditorState, position: number): void;
  cancelWritingContinuation?(requestID: string, reason: WritingContinuationCancellationReason): void;
  didApply(undoLabel: string): void;
}

export interface EditorInputSuggestionsController {
  readonly extension: Extension;
  readonly wikilinkCompletionSource: CompletionSource;
  readonly analysisReferenceCompletionSource: CompletionSource;
  readonly citationCompletionSource: CompletionSource;
  readonly slashCompletionSource: CompletionSource;
  readonly calloutCompletionSource: CompletionSource;
  resetDocument(): void;
  resumeWritingAfterComposition(): void;
  resolveLinkCompletionQuery(requestID: string, candidates: unknown): void;
  configureWritingContinuation(enabled: boolean, contextKey: string): void;
  configureWritingIndexContext(contextKey: string): void;
  setWritingContinuationStatus(requestID: string, value: unknown): void;
  resolveWritingContinuation(requestID: string, value: unknown): boolean;
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

function caretHasInputTrigger(before: string) {
  return /\[\[[^\]\n|]*$|(?:^|[\s([{])@[^\n@|\]]*$|(?:^|\s)\/[\p{L}\p{N}-]*$/u.test(before);
}

interface UnavailableCompletion extends Completion {
  unavailable?: boolean;
}

function completionIsUnavailable(completion: Completion | undefined) {
  return (completion as UnavailableCompletion | undefined)?.unavailable === true;
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

function wikilinkContext(options: InputSuggestionOptions, state: EditorState, position: number) {
  if (!isLiveSuggestionContext(options, state)) return null;
  const line = state.doc.lineAt(position);
  const scanFrom = Math.max(line.from, position - 512);
  const beforeCursor = state.doc.sliceString(scanFrom, position);
  const match = /\[\[([^\]\n|#]{0,510})$/.exec(beforeCursor);
  if (!match) return null;
  const from = scanFrom + match.index + 2;
  if (suggestionSpanIsProtected(options, state, from - 2, position)) return null;
  return {from, query: match[1]};
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
    || /[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069\\`*_{}[\]<>|]/u.test(value)) return null;
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

function continuationContextAllowed(options: InputSuggestionOptions, state: EditorState, position: number) {
  if (!isWritingSuggestionContext(options, state)
    || options.canContinueWriting?.(state, position) === false
    || positionIsProtected(options, state, position)
    || positionIsProtected(options, state, Math.max(0, position - 1))) return false;
  const before = state.sliceDoc(Math.max(0, position - 512), position);
  return /[\p{L}\p{N}]/u.test(before) && !caretHasInputTrigger(before);
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
  isCurrent: (view: EditorView) => boolean,
): NonNullable<Completion["apply"]> {
  return (view, completion, from, to) => {
    if (candidate.availability !== "available" || !candidate.insertion || !isCurrent(view)) return;
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
  isCurrent: (view: EditorView) => boolean,
): NonNullable<Completion["apply"]> {
  return (view, completion, from, to) => {
    if (candidate.availability !== "available" || !candidate.insertion || !isCurrent(view)) return;
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
    && (candidate.displayText === undefined || typeof candidate.displayText === "string")
    && ["available", "ambiguous", "unsupportedSyntax", "unavailable"].includes(candidate.availability ?? "")
    && (candidate.unavailableReason === undefined || typeof candidate.unavailableReason === "string")
    && (candidate.availability === "available" || Boolean(candidate.unavailableReason?.trim()))
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
  let linkCatalogEpoch = 0;
  let refreshLinkChoices: (() => void) | undefined;
  let clearInlineWriting: ((reason?: WritingContinuationCancellationReason) => void) | undefined;
  let resumeInlineWriting: (() => void) | undefined;
  let reconfigureWriting: ((enabledChanged: boolean) => void) | undefined;
  let refreshIndexWriting: (() => void) | undefined;
  let showInlineContinuationStatus: ((requestID: string, phase: WritingContinuationPhase) => void) | undefined;
  // A bridge watchdog, longer than the native service's 30-second deadline.
  // Preparation and generation each get their own budget; phase updates cannot
  // keep an unresponsive request alive indefinitely.
  const continuationWatchdogMilliseconds = 35_000;
  const pendingContinuations = new Map<string, {
    resolve(value: {text: string | null; reason: string | null}): void;
    timeout: ReturnType<typeof setTimeout>;
    generationStarted: boolean;
    expire(): void;
  }>();
  function cancelContinuations(reason: WritingContinuationCancellationReason) {
    for (const [requestID, pending] of pendingContinuations) {
      clearTimeout(pending.timeout);
      options.cancelWritingContinuation?.(requestID, reason);
      pending.resolve({text: null, reason: null});
    }
    pendingContinuations.clear();
  }
  function requestContinuation(state: EditorState, position: number) {
    const requestID = boundedUUID();
    const promise = new Promise<{text: string | null; reason: string | null}>(resolve => {
      const expire = () => {
        pendingContinuations.delete(requestID);
        options.cancelWritingContinuation?.(requestID, "watchdog");
        resolve({text: null, reason: localized("AI continuation timed out.")});
      };
      const timeout = setTimeout(expire, continuationWatchdogMilliseconds);
      pendingContinuations.set(requestID, {resolve, timeout, generationStarted: false, expire});
      if (options.requestWritingContinuation) options.requestWritingContinuation(requestID, state, position);
      else resolveContinuation(requestID, {text: null, reason: null});
    });
    return {requestID, promise};
  }
  function setContinuationStatus(requestID: string, value: unknown) {
    const pending = pendingContinuations.get(requestID);
    if (!pending) return;
    const payload = value && typeof value === "object" ? value as {phase?: unknown} : {};
    const phase = payload.phase;
    if (phase !== "preparing" && phase !== "retrieving" && phase !== "generating") return;
    if (pending.generationStarted && phase !== "generating") return;
    if (phase === "generating" && !pending.generationStarted) {
      pending.generationStarted = true;
      clearTimeout(pending.timeout);
      pending.timeout = setTimeout(pending.expire, continuationWatchdogMilliseconds);
    }
    showInlineContinuationStatus?.(requestID, phase);
  }
  function resolveContinuation(requestID: string, value: unknown) {
    const pending = pendingContinuations.get(requestID);
    if (!pending) return false;
    pendingContinuations.delete(requestID);
    clearTimeout(pending.timeout);
    const payload = value && typeof value === "object" ? value as {text?: unknown; reason?: unknown} : {};
    pending.resolve({text: safeContinuationSuffix(payload.text),
      reason: typeof payload.reason === "string" && payload.reason.trim() ? payload.reason.slice(0, 512) : null});
    return true;
  }
  const pendingLinkQueries = new Map<string, {
    resolve(candidates: EditorLinkCompletionCandidate[]): void;
    timeout: ReturnType<typeof setTimeout>;
    writingTerm?: boolean;
    unavailable?(): void;
  }>();

  function candidateContextIsCurrent(context: CompletionContext, epoch: number) {
    return (view: EditorView) => epoch === linkCatalogEpoch && !context.aborted
      && !view.composing && isLiveSuggestionContext(options, view.state)
      && view.state.doc === context.state.doc && view.state.selection.eq(context.state.selection);
  }

  function cancelLinkQuery(requestID: string) {
    const pending = pendingLinkQueries.get(requestID);
    if (!pending) return;
    pendingLinkQueries.delete(requestID);
    globalThis.clearTimeout(pending.timeout);
    if (pending.writingTerm) options.cancelWritingTermQuery?.(requestID);
    if (pending.writingTerm) pending.unavailable?.();
    else pending.resolve([]);
  }

  function cancelWritingTermQueries() {
    for (const [requestID, pending] of pendingLinkQueries) {
      if (pending.writingTerm) cancelLinkQuery(requestID);
    }
  }

  function cancelLinkQueries() {
    for (const requestID of pendingLinkQueries.keys()) cancelLinkQuery(requestID);
  }

  function retryButton(message: string, retry: () => void, doc: Document = document) {
    const button = doc.createElement("button");
    button.className = "scholium-writing-retry";
    button.type = "button";
    button.tabIndex = -1; // Option-Return provides the editor's keyboard route.
    button.textContent = localized("Retry AI");
    button.title = message;
    button.setAttribute("aria-label", `${message} ${localized("Retry AI continuation (Option-Return)")}`);
    button.addEventListener("mousedown", event => event.preventDefault());
    button.addEventListener("click", event => { event.stopPropagation(); retry(); });
    return button;
  }

  class Ghost extends WidgetType {
    constructor(readonly text: string, readonly accept: (text: string, source: WritingSource) => void, readonly source: WritingSource, readonly hold: (text: string, source: WritingSource) => void) { super(); }
    eq(other: Ghost) { return this.text === other.text && this.source === other.source && this.accept === other.accept && this.hold === other.hold; }
    toDOM() {
      const node = document.createElement("span");
      node.className = "scholium-writing-ghost";
      node.setAttribute("role", "button");
      const suffix = document.createElement("span");
      suffix.className = "scholium-writing-ghost-text";
      const hint = document.createElement("span");
      hint.className = "scholium-writing-ghost-key";
      hint.setAttribute("aria-hidden", "true");
      node.append(suffix, hint);
      this.updateDOM(node);
      let pointerIntent: {text: string; source: WritingSource} | null = null;
      node.addEventListener("mousedown", event => {
        event.preventDefault();
        pointerIntent = {text: suffix.textContent ?? "", source: node.dataset.source as WritingSource};
        this.hold(pointerIntent.text, pointerIntent.source);
      });
      node.addEventListener("click", () => {
        const intent = pointerIntent ?? {text: suffix.textContent ?? "", source: node.dataset.source as WritingSource};
        pointerIntent = null;
        if (node.isConnected) this.accept(intent.text, intent.source);
      });
      return node;
    }
    updateDOM(node: HTMLElement) {
      node.querySelector(".scholium-writing-ghost-text")!.textContent = this.text;
      node.querySelector(".scholium-writing-ghost-key")!.textContent = `${localized(this.source === "ai" ? "AI" : "Index")} ⇥`;
      node.dataset.source = this.source;
      node.setAttribute("aria-label", localizedTemplate(this.source === "ai" ? "Accept AI continuation: {text} (Tab)" : "Accept index suggestion: {text} (Tab)", {text: this.text}));
      return true;
    }
    ignoreEvent() { return true; }
  }
  function requestTerms(query: string) {
    const requestID = boundedUUID();
    return new Promise<{current: boolean; candidates: EditorLinkCompletionCandidate[]}>((resolve) => {
      const cancel = () => cancelLinkQuery(requestID);
      const timeout = globalThis.setTimeout(cancel, 5_000);
      pendingLinkQueries.set(requestID, {resolve: candidates => resolve({current: true, candidates}),
        unavailable: () => resolve({current: false, candidates: []}), timeout, writingTerm: true});
      options.requestLinkCompletions(requestID, "term", query);
    });
  }
  // Local lookup supplies literal candidates; inlineWriting alone owns insertion.
  type LocalWritingCandidates = {indexCurrent: boolean; texts: string[]};
  const localWritingCandidates = (state: EditorState, position: number): Promise<LocalWritingCandidates> | null => {
    if (!isWritingSuggestionContext(options, state)
      || options.canContinueWriting?.(state, position) === false
      || positionIsProtected(options, state, position)
      || positionIsProtected(options, state, Math.max(0, position - 1))) return null;
    const before = state.sliceDoc(Math.max(0, position - 512), position);
    const prefix = /[\p{L}\p{N}\p{M} -]{2,48}$/u.exec(before)?.[0];
    if (/[\p{L}\p{N}\p{M}]/u.test(state.sliceDoc(position, position + 1))
      || !prefix || !/[\p{L}\p{N}\p{M}]$/u.test(prefix) || caretHasInputTrigger(before)) return null;
    return requestTerms(prefix).then(({current, candidates}) => {
      return {indexCurrent: current, texts: candidates.flatMap(candidate => {
        const suffix = candidate.availability === "available" ? termSuffix(state, position, candidate) : null;
        return suffix ? [suffix] : [];
      })};
    });
  };

  interface DisplayedWritingCandidate {
    readonly text: string;
    readonly source: WritingSource;
    readonly proof: EditorState;
    readonly indexEpoch: number;
    readonly confirmed: boolean;
  }

  const inlineWriting = ViewPlugin.fromClass(class {
    decorations: DecorationSet = Decoration.none;
    private generation = 0;
    private localSerial = 0;
    private localTimer: ReturnType<typeof setTimeout> | undefined;
    private aiTimer: ReturnType<typeof setTimeout> | undefined;
    private acceptanceTimer: ReturnType<typeof setTimeout> | undefined;
    private round: EditorState | null = null;
    private preview: DisplayedWritingCandidate | null = null;
    private cachedLocal: DisplayedWritingCandidate | null = null;
    private awaitingAI = false;
    private rendered: {text: string; source: WritingSource; position: number} | null = null;
    private continuationRequestID: string | null = null;
    private localPending = false;
    private queuedAcceptance: string | null = null;
    private pointerHeld = false;
    private waitingForContext: EditorState | null = null;
    private deferredAI: {text: string; proof: EditorState; generation: number} | null = null;
    private failure: string | null = null;
    private phase: WritingContinuationPhase | null = null;
    private aiNeedsContext = false;
    private resumeOnFocus: EditorState | null = null;
    private suspendedAI: DisplayedWritingCandidate | null = null;
    private feedbackDOM: HTMLElement | null = null;
    private activityDOM: HTMLElement | null = null;
    private mode: EditorMode;
    private readonly acceptGhost = (text: string, source: WritingSource) => { this.accept(text, source); };
    private readonly holdGhost = (text: string, source: WritingSource) => {
      if (this.preview?.text === text && this.preview.source === source) {
        this.pointerHeld = true;
      }
    };
    private readonly retryAI = () => { this.retry(); };
    constructor(readonly view: EditorView) {
      this.mode = options.mode(view.state);
      clearInlineWriting = (reason = "dismissed") => { this.clear(reason); this.view.dispatch({}); };
      resumeInlineWriting = () => { this.schedule(); };
      reconfigureWriting = enabledChanged => {
        const pendingFocus = this.resumeOnFocus;
        this.resumeOnFocus = null; this.suspendedAI = null;
        if (this.round || this.preview || this.waitingForContext) {
          this.schedule("configuration"); this.view.dispatch({});
        } else if (continuationEnabled && (enabledChanged || (pendingFocus && this.samePoint(pendingFocus)))) {
          if (this.view.hasFocus) { this.schedule(); this.view.dispatch({}); }
          else this.resumeOnFocus = this.view.state;
        }
      };
      refreshIndexWriting = () => {
        if (this.preview?.source === "ai") return;
        if (this.preview) this.preview = {...this.preview, confirmed: false};
        if (this.cachedLocal) this.cachedLocal = {...this.cachedLocal, confirmed: false};
        if (this.round || this.preview) this.refreshLocal(0);
      };
      showInlineContinuationStatus = (requestID, phase) => {
        if (this.continuationRequestID === requestID && this.isValidContext() && this.phase !== phase) {
          this.phase = phase;
          this.renderGenerationActivity();
          this.view.dispatch({effects: EditorView.announce.of(localized(writingContinuationPhaseLabel(phase)))});
        }
      };
    }
    private isValidContext() {
      return this.view.hasFocus && !this.view.composing && isWritingSuggestionContext(options, this.view.state);
    }
    private samePoint(proof: EditorState) {
      return this.view.state.doc === proof.doc
        && this.view.state.selection.eq(proof.selection)
        && sameExactSource(this.view.state, proof);
    }
    private current(proof: EditorState) { return this.isValidContext() && this.samePoint(proof); }
    private contextReady() {
      return options.writingContextReady?.(this.view.state, this.view.state.selection.main.head) !== false;
    }
    private readable() {
      return this.contextReady()
        && options.canContinueWriting?.(this.view.state, this.view.state.selection.main.head) !== false;
    }
    private invalidateRequests(reason: WritingContinuationCancellationReason = "superseded") {
      this.generation++; this.localSerial++;
      clearTimeout(this.localTimer); clearTimeout(this.aiTimer); clearTimeout(this.acceptanceTimer);
      cancelContinuations(reason); cancelWritingTermQueries();
      this.continuationRequestID = null; this.localPending = false; this.phase = null;
      this.removeGenerationActivity();
      this.deferredAI = null; this.round = null; this.aiNeedsContext = false;
      this.cachedLocal = null; this.awaitingAI = false;
    }
    clear(reason: WritingContinuationCancellationReason = "context") {
      this.invalidateRequests(reason); this.preview = null; this.failure = null;
      this.queuedAcceptance = null; this.pointerHeld = false; this.waitingForContext = null; this.resumeOnFocus = null;
      this.suspendedAI = null;
      this.decorations = Decoration.none; this.rendered = null; this.feedbackDOM?.remove(); this.feedbackDOM = null;
    }
    suspend() {
      const point = this.round ?? this.preview?.proof ?? this.waitingForContext ?? this.resumeOnFocus;
      const retained = point && !this.view.composing && isWritingSuggestionContext(options, this.view.state) && this.samePoint(point) ? point : null;
      const candidate = this.preview?.source === "ai" ? this.preview : this.suspendedAI;
      const reusable = retained && continuationEnabled && candidate?.confirmed
        && candidate.indexEpoch === linkCatalogEpoch && this.samePoint(candidate.proof) ? candidate : null;
      this.clear("focus"); this.resumeOnFocus = retained; this.suspendedAI = reusable;
    }
    private render(dispatch = true) {
      const preview = this.preview;
      const position = this.view.state.selection.main.head;
      if (!preview) { this.decorations = Decoration.none; this.rendered = null; }
      else if (!this.rendered || this.rendered.text !== preview.text || this.rendered.source !== preview.source
        || this.rendered.position !== position) {
        this.decorations = Decoration.set([Decoration.widget({
          widget: new Ghost(preview.text, this.acceptGhost, preview.source, this.holdGhost), side: 1,
        }).range(position)]);
        this.rendered = {text: preview.text, source: preview.source, position};
      }
      this.renderFeedback(); this.renderGenerationActivity();
      if (dispatch) this.view.dispatch({});
    }
    private removeGenerationActivity() {
      this.activityDOM?.remove(); this.activityDOM = null;
    }
    private renderGenerationActivity() {
      if (this.phase !== "generating" || !this.continuationRequestID || this.preview
        || !this.round || !this.current(this.round)) { this.removeGenerationActivity(); return; }
      if (!this.activityDOM) {
        const node = this.view.dom.ownerDocument.createElement("span");
        node.className = "scholium-writing-activity";
        node.setAttribute("aria-hidden", "true");
        node.style.visibility = "hidden";
        // Keep the original dots after the caret, but outside CodeMirror's
        // text layout: a point widget can shrink its measured cursor height.
        const orb = node.ownerDocument.createElement("span");
        orb.className = "scholium-writing-orb";
        for (let index = 0; index < 3; index++) {
          const dot = node.ownerDocument.createElement("span");
          dot.className = "scholium-writing-orb-dot"; orb.append(dot);
        }
        node.append(orb); this.view.dom.append(node); this.activityDOM = node;
      }
      this.placeGenerationActivity();
    }
    placeGenerationActivity() {
      const activity = this.activityDOM, requestID = this.continuationRequestID, proof = this.round;
      if (!activity || !requestID || !proof) return;
      this.view.requestMeasure({key: activity, read: () => {
        const selection = this.view.state.selection.main;
        const point = this.view.coordsAtPos(selection.head, selection.assoc || 1);
        const root = this.view.dom.getBoundingClientRect();
        const viewport = this.view.scrollDOM.getBoundingClientRect();
        return {point, root, viewport, sx:this.view.scaleX || 1, sy:this.view.scaleY || 1};
      }, write: ({point, root, viewport, sx, sy}) => {
        if (this.activityDOM !== activity || this.continuationRequestID !== requestID
          || this.phase !== "generating" || !this.current(proof)) return;
        if (!point || point.bottom <= Math.max(root.top, viewport.top)
          || point.top >= Math.min(root.bottom, viewport.bottom)
          || point.left < Math.max(root.left, viewport.left) || point.left >= Math.min(root.right, viewport.right)) {
          activity.style.visibility = "hidden"; return;
        }
        const height = point.bottom - point.top;
        const space = Math.min(root.right, viewport.right) - point.left;
        const gap = Math.min(height * 0.18, space * 0.15);
        // Keep all three dots inside a narrow heading's remaining measure.
        // A fully clipped caret cannot support legible adjacent feedback.
        const fontSize = Math.min(height * 0.6 / sy, (space - gap - 2 * sx) / (1.2 * sx));
        if (fontSize < 8) { activity.style.visibility = "hidden"; return; }
        activity.style.fontSize = `${fontSize}px`;
        activity.style.left = `${(point.left + gap - root.left) / sx}px`;
        activity.style.top = `${(point.top + height / 2 - fontSize * sy / 2 - root.top) / sy}px`;
        activity.style.visibility = "visible";
      }});
    }
    private renderFeedback() {
      if (!this.failure) { this.feedbackDOM?.remove(); this.feedbackDOM = null; return; }
      const root = this.view.dom;
      if (!root) return;
      if (!this.feedbackDOM) {
        const node = root.ownerDocument.createElement("div");
        node.className = "scholium-writing-feedback";
        node.setAttribute("role", "status"); node.setAttribute("aria-live", "polite");
        const message = root.ownerDocument.createElement("span");
        message.className = "scholium-writing-feedback-message";
        node.append(message, retryButton(this.failure, this.retryAI, root.ownerDocument));
        node.addEventListener("mousedown", event => event.preventDefault());
        // A sibling of the scroller/content: never a point decoration, never a
        // source/caret rectangle, and never part of the document's line height.
        root.append(node); this.feedbackDOM = node;
      }
      this.feedbackDOM.querySelector(".scholium-writing-feedback-message")!.textContent = this.failure;
      this.feedbackDOM.querySelector("button")!.title = this.failure;
      this.placeFeedback();
    }
    placeFeedback() {
      const feedback = this.feedbackDOM;
      if (!feedback) return;
      this.view.requestMeasure?.({key: this, read: () => {
        const point = this.view.coordsAtPos(this.view.state.selection.main.head, -1);
        const root = this.view.dom.getBoundingClientRect();
        const panel = feedback.getBoundingClientRect();
        return {point, root, panel, sx: this.view.scaleX || 1, sy: this.view.scaleY || 1};
      }, write: ({point, root, panel, sx, sy}) => {
        if (this.feedbackDOM !== feedback || !point) return;
        const maxRight = Math.min(root.right, window.innerWidth) - 8;
        const x = Math.max(root.left + 8, Math.min(point.left, maxRight - panel.width));
        const below = point.bottom + 8;
        const y = below + panel.height <= window.innerHeight - 8 ? below : Math.max(8, point.top - panel.height - 8);
        feedback.style.left = `${(x - root.left) / sx}px`; feedback.style.top = `${(y - root.top) / sy}px`;
      }});
    }
    hasFeedback() { return this.failure !== null; }
    private confirmedLocal() {
      const candidate = this.cachedLocal;
      return candidate && candidate.confirmed && candidate.indexEpoch === linkCatalogEpoch
        && this.current(candidate.proof) ? candidate : null;
    }
    private publishAI(text: string, proof: EditorState, generation: number) {
      if (generation !== this.generation || !this.current(proof)) return;
      if (!this.contextReady()) { this.deferredAI = {text, proof, generation}; this.waitingForContext = proof; return; }
      if (!this.readable()) { this.clear(); this.view.dispatch({}); return; }
      // The visible suffix alone owns acceptance; pending local work stays hidden.
      if (this.pointerHeld || this.queuedAcceptance) return;
      this.awaitingAI = false;
      this.preview = {text, source: "ai", proof, indexEpoch: linkCatalogEpoch, confirmed: true};
      this.failure = null; this.render();
    }
    private startAI(delay: number) {
      clearTimeout(this.aiTimer);
      this.aiNeedsContext = false;
      const proof = this.round, generation = this.generation;
      if (!proof || !continuationEnabled || !continuationContextAllowed(options, proof, proof.selection.main.head)) {
        this.awaitingAI = false; this.preview = this.confirmedLocal(); return;
      }
      this.awaitingAI = true;
      this.aiTimer = setTimeout(async () => {
        if (generation !== this.generation || !this.current(proof)) return;
        // Parsing can become temporarily unavailable after this timer was
        // scheduled. Retain the exact round so its ready update can resume AI.
        if (!this.contextReady()) {
          this.waitingForContext = proof; this.aiNeedsContext = true; return;
        }
        if (!this.readable()) { this.clear(); this.view.dispatch({}); return; }
        const request = requestContinuation(proof, proof.selection.main.head);
        this.continuationRequestID = request.requestID; this.phase = "preparing";
        this.view.dispatch({effects: EditorView.announce.of(localized(writingContinuationPhaseLabel("preparing")))});
        const result = await request.promise;
        if (generation !== this.generation || !this.current(proof)) return;
        this.continuationRequestID = null; this.phase = null;
        this.removeGenerationActivity();
        if (result.text) this.publishAI(result.text, proof, generation);
        else {
          this.awaitingAI = false; this.failure = result.reason;
          this.preview = this.confirmedLocal(); this.render();
        }
      }, delay);
    }
    private refreshLocal(delay: number) {
      clearTimeout(this.localTimer); this.localSerial++; cancelWritingTermQueries();
      const proof = this.round ?? this.preview?.proof, generation = this.generation, serial = this.localSerial;
      if (!proof || !this.current(proof)) return;
      if (!this.contextReady()) { this.waitingForContext = proof; return; }
      if (!this.readable()) { this.clear(); return; }
      this.localPending = true;
      this.localTimer = setTimeout(async () => {
        if (generation !== this.generation || serial !== this.localSerial || !this.current(proof)) return;
        let result: LocalWritingCandidates | null;
        try { result = await localWritingCandidates(proof, proof.selection.main.head); }
        catch { result = {texts: [], indexCurrent: false}; }
        if (generation !== this.generation || serial !== this.localSerial || !this.current(proof)) return;
        this.localPending = false;
        if (this.preview?.source === "ai") return;
        if (!this.contextReady()) { this.waitingForContext = proof; return; }
        if (!this.readable()) { this.clear(); this.view.dispatch({}); return; }
        if (result?.indexCurrent === false) {
          if (this.cachedLocal) this.cachedLocal = {...this.cachedLocal, confirmed: false};
          if (!this.awaitingAI && this.preview) this.preview = {...this.preview, confirmed: false};
          this.queuedAcceptance = null; this.render(); return;
        }
        const choices = result?.texts ?? [];
        const text = choices.find(text => text === (this.preview ?? this.cachedLocal)?.text) ?? choices[0];
        this.cachedLocal = text ? {text, source: "index", proof, indexEpoch: linkCatalogEpoch, confirmed: true} : null;
        if (this.awaitingAI) return;
        this.preview = this.cachedLocal;
        const queued = this.queuedAcceptance; this.queuedAcceptance = null;
        this.render();
        if (text && queued === text) this.accept();
      }, delay);
    }
    schedule(reason: WritingContinuationCancellationReason = "superseded") {
      const candidate = this.preview?.source === "index" ? this.preview : this.cachedLocal;
      const retained = candidate && this.current(candidate.proof) ? candidate : null;
      this.invalidateRequests(reason); this.pointerHeld = false; this.cachedLocal = retained;
      this.resumeOnFocus = null; this.suspendedAI = null;
      this.awaitingAI = continuationEnabled;
      this.preview = this.awaitingAI ? null : this.confirmedLocal(); this.failure = null;
      this.queuedAcceptance = null; this.waitingForContext = null;
      if (!this.isValidContext()) { this.clear(); return; }
      this.round = this.view.state;
      if (!this.contextReady()) {
        this.waitingForContext = this.round;
        this.aiNeedsContext = continuationEnabled;
        this.render(false); return;
      }
      if (!this.readable()) { this.clear(); return; }
      if (this.preview?.source !== "ai") this.refreshLocal(100);
      this.startAI(400);
      this.render(false);
    }
    retry() {
      if (!continuationEnabled || !this.failure || !this.isValidContext() || !this.readable()) return false;
      this.schedule(); this.view.dispatch({}); return true;
    }
    private consumeMatchingInput(update: ViewUpdate) {
      const preview = this.preview;
      if (!preview || !this.isValidContext() || update.focusChanged || !update.docChanged
        || !update.transactions.every(t => t.isUserEvent("input.type"))) return false;
      const previous = update.startState.selection.main;
      let inserted = "", count = 0, appendOnly = true;
      update.changes.iterChanges((from, to, _newFrom, _newTo, text) => {
        count++; if (from !== previous.head || to !== previous.head) appendOnly = false;
        inserted = text.toString();
      });
      if (!previous.empty || count !== 1 || !appendOnly || !inserted || !preview.text.startsWith(inserted)
        || update.state.selection.main.head !== previous.head + inserted.length) return false;
      const text = preview.text.slice(inserted.length);
      this.invalidateRequests("typing"); this.pointerHeld = false; this.failure = null; this.queuedAcceptance = null;
      this.waitingForContext = null; this.round = update.state;
      this.preview = text ? {...preview, text, proof: update.state,
        confirmed: preview.source === "ai" || (preview.confirmed && preview.indexEpoch === linkCatalogEpoch)} : null;
      if (preview.source === "index") {
        this.cachedLocal = this.preview;
        this.awaitingAI = continuationEnabled;
        if (this.awaitingAI) this.preview = null;
      }
      if (!this.contextReady()) {
        this.waitingForContext = update.state;
        this.aiNeedsContext = preview.source === "index";
      }
      else if (!this.readable()) { this.clear(); return true; }
      else if (!text) this.schedule();
      else if (preview.source === "index") {
        if (!this.cachedLocal?.confirmed) this.refreshLocal(0);
        this.startAI(400);
      }
      this.render(false); return true;
    }
    accept(expectedText?: string, expectedSource?: WritingSource) {
      const preview = this.preview;
      if (!preview || !this.current(preview.proof)
        || (expectedText !== undefined && expectedText !== preview.text)
        || (expectedSource !== undefined && expectedSource !== preview.source)) return false;
      if (!this.contextReady()) { this.queuedAcceptance = preview.text; this.waitingForContext = preview.proof; return true; }
      if (!this.readable()) { this.clear(); this.view.dispatch({}); return false; }
      if (preview.source === "index" && (!preview.confirmed || preview.indexEpoch !== linkCatalogEpoch)) {
        this.queuedAcceptance = preview.text;
        if (!this.localPending) this.refreshLocal(0);
        return true;
      }
      const caret = this.view.state.selection.main.head, text = preview.text;
      if (!exactSourceFitsChanges(this.view.state, [{from: caret, to: caret, insert: text}])) return false;
      this.clear("accepted");
      this.view.dispatch({changes: {from: caret, insert: text}, selection: {anchor: caret + text.length},
        annotations: Transaction.userEvent.of(preview.source === "ai" ? "input.complete.scholium.continuation" : "input.complete.scholium.writing")});
      options.didApply(preview.source === "ai" ? "Accept AI Continuation" : "Complete Term"); return true;
    }
    update(update: ViewUpdate) {
      const mode = options.mode(update.state), modeChanged = mode !== this.mode; this.mode = mode;
      if (modeChanged || !isWritingSuggestionContext(options, update.state)) { this.clear(modeChanged ? "mode" : options.isComposing() ? "composition" : "context"); return; }
      const selectionChanged = update.selectionSet && !update.state.selection.eq(update.startState.selection);
      const sourceChanged = !sameExactSource(update.state, update.startState);
      if (update.focusChanged && !this.view.hasFocus && !update.docChanged && !selectionChanged && !sourceChanged) {
        this.suspend(); return;
      }
      if (!update.docChanged && !selectionChanged && !update.focusChanged && !sourceChanged) {
        if ((this.preview || this.round) && this.contextReady() && !this.readable()) { this.clear(); return; }
        const waiting = this.waitingForContext;
        if (waiting && this.current(waiting) && this.contextReady()) {
          this.waitingForContext = null;
          if (this.aiNeedsContext) this.startAI(400);
          if (this.deferredAI) {
            const result = this.deferredAI; this.deferredAI = null;
            this.acceptanceTimer = setTimeout(() => {
              this.publishAI(result.text, result.proof, result.generation);
              if (this.preview?.source === "index" && !this.preview.confirmed) this.refreshLocal(0);
              else if (this.preview && this.queuedAcceptance === this.preview.text) this.accept();
            }, 0);
          } else if (this.preview) {
            if (this.preview.source === "index" && !this.preview.confirmed) this.refreshLocal(0);
            else {
              const queued = this.queuedAcceptance, target = this.preview;
              if (queued === target.text) this.acceptanceTimer = setTimeout(() => {
                if (this.preview === target && this.queuedAcceptance === queued) this.accept(target.text, target.source);
              }, 0);
            }
          } else if (this.round) this.refreshLocal(100);
          else this.schedule();
        }
        if (update.viewportChanged || update.geometryChanged) { this.placeFeedback(); this.placeGenerationActivity(); }
        return;
      }
      if (this.consumeMatchingInput(update)) return;
      const resume = update.focusChanged && this.resumeOnFocus && this.current(this.resumeOnFocus);
      const candidate = this.suspendedAI;
      const reusable = resume && continuationEnabled && candidate?.confirmed
        && candidate.indexEpoch === linkCatalogEpoch && this.current(candidate.proof) && this.readable() ? candidate : null;
      const reason = update.docChanged ? update.transactions.some(t => t.isUserEvent("delete")) ? "deletion"
        : update.transactions.some(t => t.isUserEvent("input.type")) ? "typing" : "source"
        : update.focusChanged ? "focus" : selectionChanged ? "caret" : "source";
      this.clear(reason);
      if (reusable) {
        this.round = update.state; this.preview = {...reusable, proof: update.state}; this.render(false);
      } else if (resume || (update.docChanged && this.view.hasFocus
        && update.transactions.some(t => t.isUserEvent("input.type") || t.isUserEvent("delete")))) this.schedule();
    }
    destroy() {
      this.clear("lifecycle"); clearInlineWriting = undefined; resumeInlineWriting = undefined;
      reconfigureWriting = undefined; refreshIndexWriting = undefined; showInlineContinuationStatus = undefined;
    }
  }, {
    decorations: value => value.decorations,
    eventHandlers: {
      compositionstart() { this.clear("composition"); this.view.dispatch({}); },
      blur() { this.suspend(); this.view.dispatch({}); },
      scroll() { this.placeFeedback(); this.placeGenerationActivity(); },
    },
  });

  const wikilinkCompletionSource: CompletionSource = (context: CompletionContext) => {
    const reference = wikilinkContext(options, context.state, context.pos);
    if (!reference) return null;
    const {from, query: typed} = reference;
    const epoch = linkCatalogEpoch;
    const isCurrent = candidateContextIsCurrent(context, epoch);
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
    return candidates.then((resolved) => epoch !== linkCatalogEpoch || context.aborted ? null : ({
      from,
      options: resolved
        .slice(0, 100)
        .map((candidate): Completion => ({
          label: candidate.label,
          detail: [candidate.unavailableReason, candidate.detail].filter(Boolean).join(" — "),
          type: "scholium-note" satisfies SuggestionType,
          unavailable: candidate.availability !== "available" || !candidate.insertion,
          apply: applyWikilinkCandidate(candidate, options.didApply, isCurrent),
        } as UnavailableCompletion)),
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

    const epoch = linkCatalogEpoch;
    const isCurrent = candidateContextIsCurrent(context, epoch);

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
    return candidates.then((resolved) => epoch !== linkCatalogEpoch || context.aborted ? null : ({
      from,
      options: resolved
        .filter((candidate) => Boolean(candidate.displayText) || candidate.availability !== "available")
        .slice(0, 100)
        .map((candidate): Completion => ({
          label: candidate.label,
          detail: [candidate.unavailableReason, candidate.detail].filter(Boolean).join(" — "),
          type: "scholium-analysis-reference" satisfies SuggestionType,
          unavailable: candidate.availability !== "available" || !candidate.insertion,
          apply: applyAnalysisReferenceCandidate(candidate, options.didApply, isCurrent),
        } as UnavailableCompletion)),
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
    const match = /^(\s*(?:>\s*)+)\[!([\p{L}\p{N}-]*)$/u.exec(beforeCursor);
    if (!match || positionIsProtected(options, context.state, context.pos - match[2].length)) {
      return null;
    }
    const typed = match[2].toLocaleLowerCase();
    const dialectCallouts = options.dialect()?.callouts ?? [];
    return {
      from: context.pos - match[2].length,
      options: dialectCallouts
        .filter((callout) => !typed || [callout.identifier, callout.label, localizedCallout(callout.identifier, callout).label]
          .some(label => label.toLocaleLowerCase().includes(typed)))
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
    constructor(readonly view: EditorView) {
      refreshLinkChoices = () => {
        if (!view.hasFocus || !isLiveSuggestionContext(options, view.state)
          || completionStatus(view.state) === null
          || !(wikilinkContext(options, view.state, view.state.selection.main.head)
            || analysisReferenceContext(options, view.state, view.state.selection.main.head))) return;
        closeCompletion(view);
        // Closing only hides CodeMirror's list; an explicit unchanged selection
        // ends its running queries without editing source or adding history.
        view.dispatch({selection: view.state.selection, annotations: Transaction.addToHistory.of(false)});
        startCompletion(view);
      };
      this.refresh();
    }
    update(update: ViewUpdate) {
      if (update.docChanged || update.selectionSet) this.revision += 1;
      this.refresh();
    }
    private read() {
      return {
        state: this.view.state, status: completionStatus(this.view.state),
        items: currentCompletions(this.view.state).slice(0, 100)
          .map(item => ({label: item.label.slice(0, 512), detail: (item.detail ?? "").slice(0, 1024), disabled: completionIsUnavailable(item)})),
        anchor: this.view.coordsAtPos(this.view.state.selection.main.head),
        selected: selectedCompletionIndex(this.view.state) ?? -1,
      };
    }
    private write({items, anchor, selected, state, status}: {state: EditorState; status: ReturnType<typeof completionStatus>; items: Array<{label: string; detail: string; disabled: boolean}>; anchor: {left: number; top: number; bottom: number} | null; selected: number}) {
      if (this.destroyed) return;
      for (const option of this.view.dom?.querySelectorAll<HTMLElement>(".cm-tooltip-autocomplete [role=option]") ?? []) {
        option.setAttribute("aria-disabled", String(option.classList.contains("scholium-completion-unavailable")));
      }
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
          if (!valid() || items[index]?.disabled) return false;
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
    destroy() { this.destroyed = true; refreshLinkChoices = undefined; this.suspend(); }
  }, {
    eventHandlers: {
      compositionstart() { this.suspend(); },
      compositionend() { this.refresh(); },
    },
  });

  return {
    resetDocument() {
      citationDocumentEpoch++;
      linkCatalogEpoch++;
      clearInlineWriting?.("lifecycle");
      cancelContinuations("lifecycle");
      cancelLinkQueries();
    },
    configureWritingContinuation(enabled, contextKey) {
      if (continuationEnabled === enabled && continuationContextKey === contextKey) return;
      const enabledChanged = continuationEnabled !== enabled;
      continuationEnabled = enabled;
      continuationContextKey = contextKey;
      reconfigureWriting?.(enabledChanged);
    },
    configureWritingIndexContext(contextKey) {
      if (indexContextKey === contextKey) return;
      indexContextKey = contextKey;
      linkCatalogEpoch++;
      refreshIndexWriting?.();
      cancelLinkQueries();
      refreshLinkChoices?.();
    },
    // The shared body/title composition gate owns final-input timing.
    resumeWritingAfterComposition() { resumeInlineWriting?.(); },
    setWritingContinuationStatus: setContinuationStatus,
    resolveWritingContinuation: resolveContinuation,
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
      optionClass: completion => completionIsUnavailable(completion) ? "scholium-completion-unavailable" : "",
    }), inlineWriting, Prec.highest(keymap.of([
      {key: "Enter", run: view => {
        if (view.composing || options.isComposing()) return false;
        const selected = selectedCompletionIndex(view.state);
        return selected !== null && completionIsUnavailable(currentCompletions(view.state)[selected]);
      }},
      {key: "Tab", run: view => view.plugin(inlineWriting)?.accept() ?? false},
      {key: "Alt-Enter", run: view => view.plugin(inlineWriting)?.retry() ?? false},
      {key: "Escape", run: view => {
        const plugin = view.plugin(inlineWriting);
        if (!plugin) return false;
        const visible = plugin.decorations.size > 0 || plugin.hasFeedback() || pendingContinuations.size > 0;
        plugin.clear("dismissed"); view.dispatch({}); return visible;
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
      if (pending.writingTerm) {
        const response = value && typeof value === "object" ? value as {state?: unknown; candidates?: unknown} : {};
        if (response.state === "current" && Array.isArray(response.candidates)) {
          pending.resolve(response.candidates.slice(0, 100).filter(validLinkCandidate));
        } else pending.unavailable?.();
      } else pending.resolve(Array.isArray(value) ? value.slice(0, 100).filter(validLinkCandidate) : []);
    },
  };
}

export const inputSuggestionTesting = {
  localISODate,
};
