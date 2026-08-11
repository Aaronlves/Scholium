import {
  CompletionContext,
  autocompletion,
  pickedCompletion,
  snippet,
  type Completion,
  type CompletionSource,
} from "@codemirror/autocomplete";
import {
  EditorSelection,
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
import {localized, localizedCallout} from "./localization";

export interface EditorLinkCompletionCandidate {
  label: string;
  insertion: string;
  detail: string;
  path: string;
  isAmbiguous: boolean;
}

interface SourceRange {
  readonly from: number;
  readonly to: number;
}

interface InputSuggestionOptions {
  mode(state: EditorState): EditorMode;
  dialect(): MarkdownEditingDialect | null;
  isComposing(): boolean;
  protectedRanges(state: EditorState): readonly SourceRange[];
  requestLinkCompletions(requestID: string, query: string): void;
  didApply(undoLabel: string): void;
}

export interface EditorInputSuggestionsController {
  readonly extension: Extension;
  readonly wikilinkCompletionSource: CompletionSource;
  readonly slashCompletionSource: CompletionSource;
  readonly calloutCompletionSource: CompletionSource;
  resolveLinkCompletionQuery(requestID: string, candidates: unknown): void;
}

type SuggestionType =
  | "scholium-note"
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

function boundedUUID() {
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
    const insert = `${candidate.insertion}]]`;
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

function validLinkCandidate(value: unknown): value is EditorLinkCompletionCandidate {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<EditorLinkCompletionCandidate>;
  return typeof candidate.label === "string"
    && typeof candidate.insertion === "string"
    && typeof candidate.detail === "string"
    && typeof candidate.path === "string"
    && typeof candidate.isAmbiguous === "boolean";
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
      options.requestLinkCompletions(requestID, typed);
    });
    return candidates.then((resolved) => ({
      from,
      options: resolved
        .filter((candidate) => !candidate.isAmbiguous && candidate.insertion.length > 0)
        .slice(0, 100)
        .map((candidate): Completion => ({
          label: candidate.label,
          detail: candidate.path,
          type: "scholium-note" satisfies SuggestionType,
          apply: applyWikilinkCandidate(candidate, options.didApply),
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

  return {
    extension: autocompletion({
      override: [calloutCompletionSource, wikilinkCompletionSource, slashCompletionSource],
      activateOnCompletion: (completion) => completion.type === "scholium-command-callout",
      maxRenderedOptions: 7,
      icons: false,
      tooltipClass: () => "scholium-editor-suggestions",
      addToOptions: [{render: suggestionSymbol, position: 20}],
    }),
    wikilinkCompletionSource,
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
