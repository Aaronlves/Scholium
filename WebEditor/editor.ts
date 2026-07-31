import {
  Annotation,
  Compartment,
  EditorSelection,
  EditorState,
  Facet,
  Prec,
  Range,
  StateEffect,
  StateField,
  Text,
  Transaction,
} from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  ViewPlugin,
  WidgetType,
  ViewUpdate,
  drawSelection,
  dropCursor,
  highlightActiveLine,
  highlightActiveLineGutter,
  highlightSpecialChars,
  keymap,
  lineNumbers,
  rectangularSelection,
} from "@codemirror/view";
import {
  bidiIsolates,
  bracketMatching,
  foldGutter,
  foldKeymap,
  forceParsing,
  indentOnInput,
  syntaxTree,
} from "@codemirror/language";
import {
  defaultKeymap,
  history,
  historyField,
  historyKeymap,
  redoDepth,
  undoDepth,
} from "@codemirror/commands";
import {
  CompletionContext,
  autocompletion,
  closeBrackets,
  closeBracketsKeymap,
  completionKeymap,
} from "@codemirror/autocomplete";
import {
  EDITOR_PROTOCOL_VERSION,
  MAX_INBOUND_BYTES,
  MAX_SOURCE_UTF8_BYTES,
  type EditorCommandResult,
  type EditorContext,
  type EditorMode,
  type EditorRequest,
  type EditorScrollAnchor,
  type MarkdownEditingDialect,
  type RecoverySnapshot,
  encodedByteLength,
  isEditorRequest,
  recoveryGenerationCanReplaceCurrent,
  rejected,
} from "./protocol";
import {applySourceChanges, transformMarkdown} from "./transformations";
import {continueList, indentList} from "./interaction";
import {tableTabAction} from "./tables";
import {
  tablePresentation,
  type TablePresentation,
} from "./table-presentation";
import {
  footnotePresentation,
  type FootnotePresentation,
  type FootnoteReferencePresentation,
} from "./footnote-presentation";
import {decodeClipboardPayload, isSingleSafeURL, pasteAsMarkdown} from "./clipboard";
import {linkTargetAt} from "./projection";
import {scholiumNoteLanguage} from "./language";
import {
  boundedProjectionRanges,
  boundedLinePrefix,
  mapSemanticProjectionRanges,
  rangeKey,
  semanticProjectionRanges,
  type SemanticBlockProjection,
  type SemanticInlineProjection,
  type SemanticProjectionRanges,
} from "./semantic-projection";
import {
  activeProjectionSignature,
  selectionAffectedProjectionRanges,
  selectionIntersectsProjection,
  selectionProjectionSignature,
  transactionCanMapProjection,
  transactionChangedSyntaxTree,
  transactionMayCreateProjection,
  type ProjectionSourceRange,
} from "./projection-update";
import {
  ExactSourceMirror,
  frontmatterBodyOffset,
  frontmatterBoundary,
  normalizedDocumentText,
  replacementChange,
  type NormalizedSourceChange,
} from "./state";
import {
  announceEditorMessage,
  editorAccessibilityAttributes,
  unsupportedFilePasteMessage,
  updateEditorAccessibility,
} from "./accessibility";
import {CompositionRequestGate, compositionRequestPolicy} from "./composition";
import {createMarkdownEditor} from "./bootstrap";
import {editorPerformanceSamples, recordEditorMetric, sampleEditorMemory} from "./performance";
import {createPreviewPopoverController} from "./preview-popover";
import {createEditorScrollCoordinator} from "./scroll-coordinator";
import {
  createSelectionActionsController,
  type SelectionActionCommand,
} from "./selection-actions";
import {
  AnimationFrameCoalescer,
  interactionAvailabilitySignature,
} from "./interaction-reporting";
import {
  commandProtectionRanges,
  immutableProjectionRanges,
  projectionRangeContaining,
  projectionRangesIntersecting as rangesIntersecting,
  projectionSelectionOverlaps,
} from "./projection-index";
import type {MathProjection} from "./math";
import {appendMarkdownBlocks, createTableDOM} from "./markdown-fragment";
import {validatedLinkPreviews, type LinkPreview, type VectorLinkKind} from "./previews";

const editorStartupStartedAt = performance.now();

interface ScholiumWindow extends Window {
  webkit?: { messageHandlers?: { scholium?: { postMessage(message: unknown): void } } };
  scholiumEditor?: ScholiumEditorAPI;
}
interface LinkCandidate { label: string; insertion: string; detail: string; path: string; isAmbiguous: boolean }
interface SourceDelta { from: number; to: number; insert: string }
interface WikilinkPresentation { displayStart: number; displayEnd: number; isLegacyRelationship: boolean }
interface SemanticCodeBlockRange extends ProjectionSourceRange {
  readonly fenced: boolean;
  readonly markerRanges: readonly ProjectionSourceRange[];
}
interface SemanticLiteralRanges {
  readonly excluded: readonly Readonly<ProjectionSourceRange>[];
  readonly codeBlocks: readonly Readonly<SemanticCodeBlockRange>[];
}
interface CalloutPresentation {
  from: number;
  to: number;
  source: string;
}
interface LiveBlockProjectionRange extends ProjectionSourceRange {
  readonly kind: "table" | "callout" | "footnote" | "math";
}
interface IndexedTablePositionRange extends ProjectionSourceRange {
  readonly position: {row: number; column: number; rowCount: number; columnCount: number};
}
interface LiveProjectionIndex {
  readonly syntax: SemanticProjectionRanges;
  readonly literals: SemanticLiteralRanges;
  readonly inlineRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly footnotes: FootnotePresentation;
  readonly tables: readonly TablePresentation[];
  readonly callouts: readonly CalloutPresentation[];
  readonly mathExpressions: readonly MathProjection[];
  readonly frontmatterRange: Readonly<ProjectionSourceRange> | null;
  readonly commandProtectedRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly structuralRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly mutationSensitiveRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly blockRanges: readonly Readonly<LiveBlockProjectionRange>[];
  readonly footnoteRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly tablePositionRanges: readonly Readonly<IndexedTablePositionRange>[];
  readonly hasUnclosedFrontmatter: boolean;
}
interface ScholiumEditorAPI {
  dispatch(request: unknown): Promise<EditorCommandResult>;
  resolveLinkCompletionQuery(requestID: string, candidates: unknown): void;
}

const webkitWindow = window as ScholiumWindow;
const nativeHandler = webkitWindow.webkit?.messageHandlers?.scholium;
let bridgeSessionID = "";
let bridgeDocumentID = "";
let bridgeFingerprint = "";
let documentVersion = 0;
const exactSourceMirror = new ExactSourceMirror();
let nextLinkCompletionRequest = 0;
const pendingLinkCompletionQueries = new Map<
  string,
  (candidates: LinkCandidate[]) => void
>();
let linkPreviews: LinkPreview[] = [];
let linkPreviewIndexByRange = new Map<string, number>();
let editingDialect: MarkdownEditingDialect | null = null;
let hiddenFrontmatterSourceSelection: {
  documentVersion: number;
  sourceSelection: EditorSelection;
  clampedLiveSelection: EditorSelection;
} | null = null;
let modeTransitionSequence = 0;
const liveWidgetReuseCounts = {table: 0, callout: 0, footnote: 0};
let lastUndoLabel: string | undefined;
let lastRedoLabel: string | undefined;
const post = (message: Record<string, unknown>) => nativeHandler?.postMessage({
  protocolVersion: EDITOR_PROTOCOL_VERSION,
  sessionID: bridgeSessionID,
  documentID: bridgeDocumentID,
  startingFingerprint: bridgeFingerprint,
  documentVersion,
  ...message,
});

function exactEditorSource() {
  return exactSourceMirror.text;
}

const modeCompartment = new Compartment();
const lineSeparatorCompartment = new Compartment();
const editorModeFacet = Facet.define<EditorMode, EditorMode>({
  // Mode absence must fail closed to exact Source. Live Preview is installed
  // only by the mode compartment and can never be inferred from a missing
  // configuration input.
  combine: (modes) => modes[0] ?? "source",
});
const programmaticDocumentChange = Annotation.define<boolean>();
const refreshLivePreviewEffect = StateEffect.define<null>();

function configuredEditorMode(state: EditorState): EditorMode {
  return state.facet(editorModeFacet);
}

type LiveBlockEntryEdge = "start" | "end";
interface LiveBlockActivation {
  kind: "callout";
  from: number;
  to: number;
  edge: LiveBlockEntryEdge;
}
const setLiveBlockActivationEffect = StateEffect.define<LiveBlockActivation | null>({
  map(value, changes) {
    if (value === null) return null;
    return {
      ...value,
      from: changes.mapPos(value.from, 1),
      to: changes.mapPos(value.to, -1),
    };
  },
});
const liveBlockActivationField = StateField.define<LiveBlockActivation | null>({
  create: () => null,
  update(previous, transaction) {
    let next = previous;
    if (next && transaction.docChanged) {
      next = {
        ...next,
        from: transaction.changes.mapPos(next.from, 1),
        to: transaction.changes.mapPos(next.to, -1),
      };
      if (next.to < next.from) next = null;
    }
    for (const effect of transaction.effects) {
      if (effect.is(setLiveBlockActivationEffect)) next = effect.value;
    }
    if (!next) return null;
    const selectionKeepsActivation = transaction.state.selection.ranges.some((range) =>
      selectionIntersectsProjection(range, next!)
      || (range.empty && range.head === (next!.edge === "start" ? next!.from : next!.to)),
    );
    return selectionKeepsActivation ? next : null;
  },
  provide: (field) => EditorView.editorAttributes.from(field, (value): Record<string, string> => value
    ? {"data-scholium-active-live-block": value.kind}
    : {}),
});
const hiddenSyntax = Decoration.replace({});
const liveMark = (className: string) => Decoration.mark({ class: className });
const liveInlineClassByKind: Partial<Record<SemanticInlineProjection["kind"], string>> = {
  strong: "cm-live-strong",
  emphasis: "cm-live-emphasis",
  strikethrough: "cm-live-strike",
  highlight: "cm-live-highlight",
  code: "cm-live-code",
  link: "cm-live-link",
};

/** @param {{from: number, to: number}[]} ranges @param {number} from @param {number} to */
function overlaps(ranges: {from: number; to: number}[], from: number, to: number) {
  return ranges.some((range) => range.from < to && range.to > from);
}

const neutralCallout = {
  identifier: "neutral",
  aliases: [] as string[],
  label: "Note",
  meaning: "Preserves an unsupported callout without assigning a research role.",
};

function calloutDefinition(rawKind: string) {
  const kind = rawKind.toLowerCase().replace(/:+$/, "").trim();
  return editingDialect?.callouts.find((callout) =>
    callout.identifier === kind || callout.aliases.includes(kind),
  ) ?? neutralCallout;
}

/** @param {string} text */
function calloutHeader(text: string): RegExpExecArray | null {
  return /^(\s*(?:>\s*)+)\[!([^\]]+)\]([+-])?\s*(.*)$/.exec(text);
}

class ListMarkerWidget extends WidgetType {
  readonly marker: string;
  readonly ordered: boolean;
  readonly nested: boolean;
  readonly task: boolean;
  constructor(marker: string, ordered: boolean, nested: boolean, task: boolean) {
    super();
    this.marker = marker;
    this.ordered = ordered;
    this.nested = nested;
    this.task = task;
  }
  eq(other: ListMarkerWidget) {
    return other.marker === this.marker
      && other.ordered === this.ordered
      && other.nested === this.nested
      && other.task === this.task;
  }
  toDOM() {
    const span = document.createElement("span");
    span.className = [
      "cm-live-list-marker",
      this.ordered ? "cm-live-list-marker-ordered" : "cm-live-list-marker-unordered",
      this.nested ? "cm-live-list-marker-nested" : "",
      this.task ? "cm-live-list-marker-task" : "",
    ].filter(Boolean).join(" ");
    span.textContent = this.ordered ? this.marker : this.nested ? "◦" : "•";
    span.setAttribute("aria-hidden", "true");
    return span;
  }
  // Let CodeMirror own pointer placement at the exact source marker. If the
  // browser handles selection inside this replacement widget, a single click
  // can start a native DOM selection that spans unrelated projected prose.
  ignoreEvent() { return false; }
}

const vectorLinkSemantics: Record<VectorLinkKind, {label: string; symbol: string}> = {
  neutral: { label: "Related note", symbol: "—" },
  supports: { label: "Supports", symbol: "+" },
  opposes: { label: "Opposes", symbol: "−" },
  incompatible: { label: "Incompatible", symbol: "" },
};

class VectorLinkIconWidget extends WidgetType {
  readonly kind: VectorLinkKind;
  constructor(kind: VectorLinkKind) { super(); this.kind = kind; }
  eq(other: VectorLinkIconWidget) { return other.kind === this.kind; }
  toDOM() {
    const semantics = vectorLinkSemantics[this.kind];
    const span = document.createElement("span");
    span.className = `cm-live-vector-icon cm-live-vector-icon-${this.kind.replaceAll("_", "-")}`;
    span.title = semantics.label;
    span.setAttribute("role", "img");
    span.setAttribute("aria-label", semantics.label);
    if (this.kind === "incompatible") {
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.setAttribute("viewBox", "0 0 20 20");
      svg.setAttribute("aria-hidden", "true");
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", "M3.1 10.1c2.5-.2 4.5-.1 6.1.1L10 7.1M16.9 10.1c-2.5-.2-4.5-.1-6.1.1L10 13.1");
      svg.append(path);
      span.append(svg);
    } else {
      span.textContent = semantics.symbol;
    }
    return span;
  }
  // Let CodeMirror place the caret at this replacement when it is clicked so
  // the exact source marker becomes available for editing immediately.
  ignoreEvent() { return false; }
}

class MathWidget extends WidgetType {
  readonly expression: MathProjection;

  constructor(expression: MathProjection) {
    super();
    this.expression = expression;
  }

  eq(other: MathWidget) {
    return other.expression.kind === this.expression.kind
      && other.expression.content === this.expression.content
      && other.expression.delimiterLength === this.expression.delimiterLength;
  }

  toDOM() {
    const element = document.createElement("span");
    element.className = `scholium-math scholium-math-${this.expression.kind} cm-live-math`;
    element.dataset.scholiumProtected = "math";

    const runtime = window.scholiumMath;
    const rendered = runtime?.version === 1
      ? runtime.render({source: this.expression.content, kind: this.expression.kind})
      : {ok: false as const, reason: "invalid-source" as const};
    if (rendered.ok) {
      element.classList.add("scholium-math-rendered");
      const output = document.createElement("span");
      output.className = "scholium-math-output";
      output.innerHTML = rendered.html;
      element.append(output);
    } else {
      const source = document.createElement("code");
      const delimiter = "$".repeat(this.expression.delimiterLength);
      source.className = "scholium-math-source";
      source.textContent = this.expression.kind === "display"
        ? `${delimiter}\n${this.expression.content}\n${delimiter}`
        : `${delimiter}${this.expression.content}${delimiter}`;
      element.classList.add("scholium-math-error");
      element.setAttribute("aria-label", "Mathematics could not be rendered. Source is shown.");
      element.append(source);
    }
    if (this.expression.kind === "display") {
      const slot = document.createElement("div");
      slot.className = "cm-live-math-slot";
      slot.append(element);
      return slot;
    }
    return element;
  }

  // A click places the caret at the replacement boundary so the exact source
  // construct is revealed on the next projection update.
  ignoreEvent() { return false; }
}

function isFencedDelimiterLine(doc: Text, block: SemanticCodeBlockRange, lineFrom: number) {
  if (!block.fenced) return false;
  return block.markerRanges.some((range) => doc.lineAt(range.from).from === lineFrom);
}

const legacyRelationshipPredicates = new Set([
  "supports", "contradicts", "extends", "refines", "incompatible_with",
  "cites", "see_also", "connected", "answers", "subquestion_of", "premise_of",
  "concludes", "assumes", "pressures", "uses_concept", "has_commitment", "targets",
  "objects_to", "rebuts", "undercuts", "replies_to", "concedes", "depends_on",
  "supersedes", "qualifies", "elicits", "tests", "illustrates", "counterexample_to",
  "evidence_for", "attributes_to", "interprets", "derived_from", "is_case_for",
  "is_source_for", "is_background_for", "is_not_evidence_for",
]);

function isLegacyRelationshipPredicate(raw: string): boolean {
  const normalized = raw.trim().toLowerCase().replaceAll("-", "_");
  if (legacyRelationshipPredicates.has(normalized)) return true;
  return [
    "seealso", "objectsto", "repliesto", "dependson", "iscasefor", "issourcefor",
    "isbackgroundfor", "isnotevidencefor",
  ].includes(normalized);
}

function wikilinkPresentation(
  targetStart: number,
  target: string,
  annotationStart: number | null,
  annotation: string | undefined,
): WikilinkPresentation {
  const targetPresentation = {
    displayStart: targetStart,
    displayEnd: targetStart + target.length,
    isLegacyRelationship: false,
  };
  if (annotationStart === null || annotation === undefined) return targetPresentation;

  const trimmed = annotation.trim();
  if (trimmed.startsWith(":") && isLegacyRelationshipPredicate(trimmed.slice(1))) {
    return { ...targetPresentation, isLegacyRelationship: true };
  }

  const lastColon = trimmed.lastIndexOf(":");
  if (lastColon >= 0 && isLegacyRelationshipPredicate(trimmed.slice(lastColon + 1))) {
    const rawAlias = trimmed.slice(0, lastColon);
    const alias = rawAlias.trim();
    if (!alias) return { ...targetPresentation, isLegacyRelationship: true };
    const trimmedOffset = annotation.indexOf(trimmed);
    const aliasOffset = rawAlias.indexOf(alias);
    const displayStart = annotationStart + trimmedOffset + aliasOffset;
    return {
      displayStart,
      displayEnd: displayStart + alias.length,
      isLegacyRelationship: true,
    };
  }

  return {
    displayStart: annotationStart,
    displayEnd: annotationStart + annotation.length,
    isLegacyRelationship: false,
  };
}

function indexedTablePositionRanges(
  doc: Text,
  tables: readonly TablePresentation[],
) {
  const ranges: IndexedTablePositionRange[] = [];
  for (const table of tables) {
    const rows = [table.header, ...table.body];
    const rowCount = rows.length;
    const columnCount = table.header.length;
    rows.forEach((cells, row) => {
      const first = cells[0];
      if (!first) return;
      const line = doc.lineAt(first.sourceOffset);
      cells.forEach((cell, column) => {
        const next = cells[column + 1];
        ranges.push({
          from: column === 0 ? line.from : cell.sourceOffset,
          to: next?.sourceOffset ?? line.to + 1,
          position: {row, column, rowCount, columnCount},
        });
      });
    });
  }
  return immutableProjectionRanges(ranges);
}

function finalizedLiveProjectionIndex(
  doc: Text,
  syntax: SemanticProjectionRanges,
  excluded: readonly ProjectionSourceRange[],
  codeBlocks: readonly SemanticCodeBlockRange[],
  inlineRanges: readonly ProjectionSourceRange[],
  footnotes: FootnotePresentation,
  tables: readonly TablePresentation[],
  callouts: readonly CalloutPresentation[],
  mathExpressions: readonly MathProjection[],
  frontmatterRange: ProjectionSourceRange | null,
  hasUnclosedFrontmatter: boolean,
): LiveProjectionIndex {
  const immutableExcluded = immutableProjectionRanges(excluded);
  const immutableCodeBlocks = immutableProjectionRanges(codeBlocks);
  const immutableFrontmatter = frontmatterRange === null
    ? null
    : Object.freeze({...frontmatterRange});
  const immutableTables = Object.freeze([...tables]);
  const immutableCallouts = Object.freeze([...callouts]);
  const immutableMathExpressions = Object.freeze([...mathExpressions]);
  const footnoteRanges = immutableProjectionRanges(
    footnotes.references.map(({from, to}) => ({from, to})),
  );
  const immutableCommandProtectedRanges = commandProtectionRanges(
    immutableExcluded,
    immutableFrontmatter ?? undefined,
  );
  const immutableStructuralRanges = immutableProjectionRanges([
    ...immutableTables,
    ...immutableCallouts,
    ...footnotes.definitions,
    ...footnotes.references,
    ...immutableMathExpressions.filter((expression) => expression.kind === "display"),
  ].map(({from, to}) => ({from, to})));
  return Object.freeze({
    syntax,
    literals: Object.freeze({
      excluded: immutableExcluded,
      codeBlocks: immutableCodeBlocks,
    }),
    inlineRanges: immutableProjectionRanges(inlineRanges),
    footnotes,
    tables: immutableTables,
    callouts: immutableCallouts,
    mathExpressions: immutableMathExpressions,
    frontmatterRange: immutableFrontmatter,
    commandProtectedRanges: immutableCommandProtectedRanges,
    structuralRanges: immutableStructuralRanges,
    mutationSensitiveRanges: immutableProjectionRanges([
      ...immutableCommandProtectedRanges,
      ...immutableStructuralRanges,
    ]),
    blockRanges: immutableProjectionRanges([
      ...immutableTables.map(({from, to}) => ({from, to, kind: "table" as const})),
      ...immutableCallouts.map(({from, to}) => ({from, to, kind: "callout" as const})),
      ...immutableMathExpressions.flatMap(({from, to, kind}) =>
        kind === "display" ? [{from, to, kind: "math" as const}] : []),
    ]),
    footnoteRanges,
    tablePositionRanges: indexedTablePositionRanges(doc, immutableTables),
    hasUnclosedFrontmatter,
  });
}

function mathExpressionsFromCatalog(
  state: EditorState,
  syntax: SemanticProjectionRanges,
): MathProjection[] {
  const expressions: MathProjection[] = [];
  for (const inline of syntax.inlines.filter((candidate) => candidate.kind === "inlineMath")) {
    const contentRange = inline.visibleRanges[0];
    const opening = inline.markerRanges[0];
    if (!contentRange || !opening) continue;
    const sourceContent = state.doc.sliceString(contentRange.from, contentRange.to);
    const content = sourceContent.length > 2
      && /^\s/.test(sourceContent) && /\s$/.test(sourceContent) && /\S/.test(sourceContent)
      ? sourceContent.slice(1, -1)
      : sourceContent;
    expressions.push({
      kind: "inline",
      content,
      delimiterLength: opening.to - opening.from,
      from: inline.from,
      to: inline.to,
      contentFrom: contentRange.from,
      contentTo: contentRange.to,
    });
  }
  for (const block of syntax.blocks.filter((candidate) => candidate.kind === "displayMath")) {
    const opening = block.markerRanges[0];
    const closing = block.markerRanges.at(-1);
    if (!opening || !closing || opening === closing) continue;
    const openingLine = state.doc.lineAt(opening.from);
    const closingLine = state.doc.lineAt(closing.from);
    const contentFrom = openingLine.number < state.doc.lines
      ? state.doc.line(openingLine.number + 1).from
      : openingLine.to;
    const contentTo = closingLine.from;
    expressions.push({
      kind: "display",
      content: state.doc.sliceString(contentFrom, contentTo).replace(/^[\r\n]+|[\r\n]+$/g, ""),
      delimiterLength: opening.to - opening.from,
      from: block.from,
      to: block.to,
      contentFrom,
      contentTo,
    });
  }
  return expressions.sort((left, right) => left.from - right.from || left.to - right.to);
}

function buildLiveProjectionIndex(state: EditorState): LiveProjectionIndex {
  const startedAt = performance.now();
  const syntax = semanticProjectionRanges(
    state,
    [{from: 0, to: state.doc.length}],
    0,
  );
  const codeBlocks: SemanticCodeBlockRange[] = syntax.blocks
    .filter((block) => block.kind === "code")
    .map((block) => ({
      from: block.from,
      to: block.to,
      fenced: block.nodeName === "FencedCode",
      markerRanges: block.markerRanges,
    }));
  const excluded: ProjectionSourceRange[] = [
    ...codeBlocks,
    ...syntax.blocks
      .filter((block) => block.kind === "html" || block.kind === "comment")
      .map(({from, to}) => ({from, to})),
    ...syntax.inlines
      .filter((inline) => inline.kind === "code")
      .map(({from, to}) => ({from, to})),
    ...syntax.literals.map(({from, to}) => ({from, to})),
  ];
  const inlineRanges = syntax.inlines.map(({from, to}) => ({from, to}));
  const namedDefinitionStarts = new Set(syntax.blocks
    .filter((block) => block.kind === "footnoteDefinition")
    .map((block) => block.from));
  const inlineDefinitionRanges = new Set<string>();
  const referenceRanges = new Set(syntax.inlines
    .filter((inline) => inline.kind === "footnoteReference" || inline.kind === "inlineFootnote")
    .map((inline) => rangeKey(inline.from, inline.to)));
  for (const inline of syntax.inlines.filter((candidate) => candidate.kind === "inlineFootnote")) {
    inlineDefinitionRanges.add(rangeKey(inline.from, inline.to));
  }
  const tableRanges = syntax.blocks
    .filter((block) => block.kind === "table")
    .map(({from, to}) => ({from, to}));
  const calloutRanges = syntax.blocks
    .filter((block) => block.kind === "callout")
    .map(({from, to}) => ({from, to}));
  const yamlBoundary = frontmatterBoundary(state.doc);
  const yamlBodyFrom = yamlBoundary.endLine === 0
    ? 0
    : yamlBoundary.endLine < state.doc.lines
      ? state.doc.line(yamlBoundary.endLine + 1).from
      : state.doc.line(yamlBoundary.endLine).to;
  const frontmatterRange = yamlBodyFrom > 0 ? {from: 0, to: yamlBodyFrom} : null;
  const footnoteExcluded = [...excluded];
  if (frontmatterRange) footnoteExcluded.push(frontmatterRange);
  let completeSource: string | null = null;
  const source = () => completeSource ??= state.doc.toString();
  let footnotes: FootnotePresentation = {definitions: [], references: []};
  if (namedDefinitionStarts.size > 0 || inlineDefinitionRanges.size > 0 || referenceRanges.size > 0) {
    const projectedFootnotes = footnotePresentation(
      source(),
      footnoteExcluded,
      editingDialect?.footnotes,
    );
    footnotes = {
      definitions: projectedFootnotes.definitions.filter((definition) =>
        definition.isInline
          ? inlineDefinitionRanges.has(rangeKey(definition.from, definition.to))
          : namedDefinitionStarts.has(definition.from)),
      references: projectedFootnotes.references.filter((reference) =>
        referenceRanges.has(rangeKey(reference.from, reference.to))),
    };
  }
  const tables = tableRanges.flatMap((range): TablePresentation[] => {
    const presentation = tablePresentation(source(), range.from, range.to);
    return presentation ? [presentation] : [];
  });
  const callouts = calloutRanges.flatMap((range): CalloutPresentation[] => {
    return [{...range, source: state.doc.sliceString(range.from, range.to)}];
  });
  const mathExpressions = mathExpressionsFromCatalog(state, syntax);
  const index = finalizedLiveProjectionIndex(
    state.doc,
    syntax,
    excluded,
    codeBlocks,
    inlineRanges,
    footnotes,
    tables,
    callouts,
    mathExpressions,
    frontmatterRange,
    yamlBoundary.unclosed,
  );
  recordEditorMetric("projection-index", startedAt, {
    documentLength: state.doc.length,
    literalCount: excluded.length,
    tableCount: tables.length,
    calloutCount: callouts.length,
    footnoteCount: footnotes.definitions.length + footnotes.references.length,
  });
  return index;
}

function mapLiveProjectionIndex(index: LiveProjectionIndex, transaction: Transaction): LiveProjectionIndex {
  const map = (position: number) => transaction.changes.mapPos(position);
  const syntax = mapSemanticProjectionRanges(index.syntax, transaction.state, map);
  const footnotes: FootnotePresentation = {
    definitions: index.footnotes.definitions.map((definition) => ({
        ...definition,
        from: map(definition.from),
        to: map(definition.to),
        contentFrom: map(definition.contentFrom),
      })),
      references: index.footnotes.references.map((reference) => ({
        ...reference,
        from: map(reference.from),
        to: map(reference.to),
        definitionFrom: reference.definitionFrom === null ? null : map(reference.definitionFrom),
        definitionContentFrom: reference.definitionContentFrom === null
          ? null
          : map(reference.definitionContentFrom),
      })),
    };
  const tables = index.tables.map((presentation) => ({
      ...presentation,
      from: map(presentation.from),
      to: map(presentation.to),
      header: presentation.header.map((cell) => ({...cell, sourceOffset: map(cell.sourceOffset)})),
      body: presentation.body.map((row) =>
        row.map((cell) => ({...cell, sourceOffset: map(cell.sourceOffset)}))),
    }));
  const callouts = index.callouts.map((presentation) => ({
      ...presentation,
      from: map(presentation.from),
    to: map(presentation.to),
  }));
  const mathExpressions = index.mathExpressions.map((expression) => ({
    ...expression,
    from: map(expression.from),
    to: map(expression.to),
    contentFrom: map(expression.contentFrom),
    contentTo: map(expression.contentTo),
  }));
  const frontmatterRange = index.frontmatterRange === null ? null : {
    from: map(index.frontmatterRange.from),
    to: map(index.frontmatterRange.to),
  };
  return finalizedLiveProjectionIndex(
    transaction.state.doc,
    syntax,
    index.literals.excluded.map((range) => ({from: map(range.from), to: map(range.to)})),
    index.literals.codeBlocks.map((range) => ({
      from: map(range.from),
      to: map(range.to),
      fenced: range.fenced,
      markerRanges: range.markerRanges.map((marker) => ({
        from: map(marker.from),
        to: map(marker.to),
      })),
    })),
    index.inlineRanges.map((range) => ({from: map(range.from), to: map(range.to)})),
    footnotes,
    tables,
    callouts,
    mathExpressions,
    frontmatterRange,
    index.hasUnclosedFrontmatter,
  );
}

const liveProjectionIndexField = StateField.define<LiveProjectionIndex>({
  create: buildLiveProjectionIndex,
  update(previous, transaction) {
    if (!transaction.docChanged) {
      // Pure selection transactions retain the same Lezer tree and reuse this
      // index. A background parse publication is the intentional exception:
      // it may reveal structural constructs absent from the earlier partial
      // tree, so one refresh is required for that newly published tree.
      return transactionChangedSyntaxTree(transaction)
        ? buildLiveProjectionIndex(transaction.state)
        : previous;
    }
    const structuralMarker = /[\r\n`~<>%$\[\]!*_|^:]/;
    if (previous.mutationSensitiveRanges.length === 0
        && !transactionMayCreateProjection(transaction, structuralMarker)) {
      return mapLiveProjectionIndex(previous, transaction);
    }
    return transactionCanMapProjection(
      transaction,
      structuralMarker,
      previous.mutationSensitiveRanges,
    )
      ? mapLiveProjectionIndex(previous, transaction)
      : buildLiveProjectionIndex(transaction.state);
  },
});

function liveProjectionIndexForState(state: EditorState) {
  return state.field(liveProjectionIndexField, false) ?? buildLiveProjectionIndex(state);
}

function visibleInlineMathExpressions(
  state: EditorState,
  coveredRanges: readonly ProjectionSourceRange[],
  index: LiveProjectionIndex,
): MathProjection[] {
  if (!editingDialect || coveredRanges.length === 0) return [];
  return index.mathExpressions.filter((expression) =>
    expression.kind === "inline"
      && coveredRanges.some((range) =>
        range.from <= expression.from && range.to >= expression.to)
      && (!index.frontmatterRange || expression.from >= index.frontmatterRange.to)
      && expression.to <= state.doc.length);
}

interface LiveBlockProjectionState {
  decorations: DecorationSet;
  hasConstructs: boolean;
}

interface LiveTableProjectionState extends LiveBlockProjectionState {
  presentations: readonly TablePresentation[];
}

function projectedSourceOffsetAt(
  event: MouseEvent,
  root: HTMLElement,
  fallback: number,
  upperBound: number,
) {
  const caretDocument = document as Document & {
    caretRangeFromPoint?: (x: number, y: number) => globalThis.Range | null;
  };
  const caret = caretDocument.caretRangeFromPoint?.(event.clientX, event.clientY) ?? null;
  const caretElement = caret?.startContainer instanceof Element
    ? caret.startContainer
    : caret?.startContainer.parentElement;
  const pointMapped = document.elementsFromPoint(event.clientX, event.clientY)
    .flatMap((element) => {
      const candidate = element.closest<HTMLElement>("[data-source-offset]");
      return candidate && root.contains(candidate) ? [candidate] : [];
    })[0] ?? null;
  const mapped = caretElement?.closest<HTMLElement>("[data-source-offset]")
    ?? pointMapped
    ?? (event.target instanceof Element
      ? event.target.closest<HTMLElement>("[data-source-offset]")
      : null)
    ?? root;
  const base = Number(mapped.dataset.sourceOffset);
  if (!Number.isSafeInteger(base)) return fallback;
  let visibleOffset = 0;
  if (caret && mapped.contains(caret.startContainer)) {
    const range = document.createRange();
    range.setStart(mapped, 0);
    range.setEnd(caret.startContainer, caret.startOffset);
    visibleOffset = range.toString().length;
  } else if (mapped !== root || pointMapped) {
    const walker = document.createTreeWalker(mapped, NodeFilter.SHOW_TEXT);
    let textOffset = 0;
    let bestScore = Number.POSITIVE_INFINITY;
    let bestOffset = 0;
    let node: Node | null;
    while ((node = walker.nextNode())) {
      const content = node.textContent ?? "";
      for (let index = 0; index < content.length; index += 1) {
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + 1);
        const rect = range.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) continue;
        const verticalDistance = event.clientY < rect.top
          ? rect.top - event.clientY
          : event.clientY > rect.bottom
            ? event.clientY - rect.bottom
            : 0;
        const horizontalDistance = event.clientX < rect.left
          ? rect.left - event.clientX
          : event.clientX > rect.right
            ? event.clientX - rect.right
            : 0;
        const score = verticalDistance * 1_000 + horizontalDistance;
        if (score < bestScore) {
          bestScore = score;
          bestOffset = textOffset + index + (event.clientX > (rect.left + rect.right) / 2 ? 1 : 0);
        }
      }
      textOffset += content.length;
    }
    visibleOffset = bestOffset;
  }
  return Math.max(fallback, Math.min(upperBound - 1, base + visibleOffset));
}

function beginProjectedPointerSelection(
  view: EditorView,
  event: MouseEvent,
  sourceOffset: number,
) {
  event.preventDefault();
  const pointerOrigin = {x: event.clientX, y: event.clientY};
  const anchor = event.shiftKey ? view.state.selection.main.anchor : sourceOffset;
  view.dispatch({selection: {anchor, head: sourceOffset}, scrollIntoView: true});
  view.focus();
  let latestCoordinates: {x: number; y: number} | null = null;
  let measurePending = false;
  const measureLatestPosition = () => {
    if (measurePending) return;
    measurePending = true;
    view.requestMeasure({
      read: () => {
        const coordinates = latestCoordinates;
        latestCoordinates = null;
        return coordinates ? view.posAtCoords(coordinates) : null;
      },
      write: (head) => {
        measurePending = false;
        if (head !== null) view.dispatch({selection: {anchor, head}});
        if (latestCoordinates) measureLatestPosition();
      },
    });
  };
  const move = (moveEvent: MouseEvent) => {
    const horizontalDistance = moveEvent.clientX - pointerOrigin.x;
    const verticalDistance = moveEvent.clientY - pointerOrigin.y;
    // WebKit can emit sub-pixel mouse moves between mouse-down and mouse-up.
    // Treat those as a click, not the beginning of a drag selection. A real
    // pointer selection starts only after the standard small movement slop.
    if (horizontalDistance * horizontalDistance + verticalDistance * verticalDistance < 16) {
      return;
    }
    latestCoordinates = {x: moveEvent.clientX, y: moveEvent.clientY};
    measureLatestPosition();
  };
  const finish = () => {
    latestCoordinates = null;
    window.removeEventListener("mousemove", move, true);
    window.removeEventListener("mouseup", finish, true);
  };
  window.addEventListener("mousemove", move, true);
  window.addEventListener("mouseup", finish, true);
  // The dispatch above removes the block replacement that owned this event.
  // Remeasure before any subsequent pointer coordinate is interpreted.
  view.requestMeasure();
}

const liveInlinePointerPlacement = EditorView.domEventHandlers({
  mousedown(event, view) {
    if (event.button !== 0 || view.composing) return false;
    const target = event.target instanceof Element ? event.target : null;
    if (!target?.closest([
      ".cm-live-strong",
      ".cm-live-emphasis",
      ".cm-live-strike",
      ".cm-live-highlight",
      ".cm-live-code",
      ".cm-live-link",
      ".cm-live-vector-link",
      ".cm-live-embed",
    ].join(","))) return false;

    const position = view.posAtCoords({x: event.clientX, y: event.clientY});
    if (position === null) return false;
    const construct = projectionRangeContaining(
      liveProjectionIndexForState(view.state).syntax.inlines,
      Math.min(position, Math.max(0, view.state.doc.length - 1)),
    );
    if (!construct || construct.kind === "comment") return false;
    const sourceOffset = Math.max(construct.from, Math.min(construct.to - 1, position));
    beginProjectedPointerSelection(view, event, sourceOffset);
    return true;
  },
});

const tableWidgetPresentations = new WeakMap<HTMLElement, TablePresentation>();

class TableWidget extends WidgetType {
  constructor(readonly presentation: TablePresentation) { super(); }

  eq(other: TableWidget) {
    const equal = other.presentation.from === this.presentation.from
      && other.presentation.to === this.presentation.to
      && other.presentation.source === this.presentation.source;
    if (equal) liveWidgetReuseCounts.table += 1;
    return equal;
  }

  toDOM(view: EditorView) {
    const scroller = createTableDOM(this.presentation, document, {
      mathematics: editingDialect?.mathematics,
      resolveCallout: calloutDefinition,
    });
    scroller.classList.add("cm-live-table-widget");
    tableWidgetPresentations.set(scroller, this.presentation);
    scroller.addEventListener("mousedown", (event) => {
      const presentation = tableWidgetPresentations.get(scroller);
      if (!presentation) return;
      const sourceOffset = projectedSourceOffsetAt(
        event,
        scroller,
        presentation.from,
        presentation.to,
      );
      beginProjectedPointerSelection(view, event, sourceOffset);
    });
    return scroller;
  }

  updateDOM(dom: HTMLElement) {
    const previous = tableWidgetPresentations.get(dom);
    if (!previous || previous.source !== this.presentation.source) return false;
    const elements = [...dom.querySelectorAll<HTMLElement>("[data-source-offset]")];
    const previousOffsets = [...previous.header, ...previous.body.flat()].map((cell) => cell.sourceOffset);
    const nextOffsets = [...this.presentation.header, ...this.presentation.body.flat()].map((cell) => cell.sourceOffset);
    if (elements.length !== previousOffsets.length || elements.length !== nextOffsets.length) return false;
    elements.forEach((element, index) => {
      element.dataset.sourceOffset = String(nextOffsets[index]);
    });
    tableWidgetPresentations.set(dom, this.presentation);
    liveWidgetReuseCounts.table += 1;
    return true;
  }

  ignoreEvent() { return true; }
}

function liveTableDecorations(
  state: EditorState,
  presentations: readonly TablePresentation[],
) {
  const decorations = presentations.flatMap((presentation): Range<Decoration>[] => {
    const active = state.selection.ranges.some((range) =>
      selectionIntersectsProjection(range, presentation),
    );
    if (active) return [];
    return [Decoration.replace({
      widget: new TableWidget(presentation),
      block: true,
    }).range(presentation.from, presentation.to)];
  });
  return Decoration.set(decorations, true);
}

function buildLiveTableDecorations(state: EditorState): LiveTableProjectionState {
  const index = liveProjectionIndexForState(state);
  if (index.hasUnclosedFrontmatter) {
    return {decorations: Decoration.none, hasConstructs: true, presentations: []};
  }
  const presentations = index.tables;
  return {
    decorations: liveTableDecorations(state, presentations),
    hasConstructs: presentations.length > 0,
    presentations,
  };
}

function mapTablePresentations(
  presentations: readonly TablePresentation[],
  transaction: Transaction,
) {
  const map = (position: number) => transaction.changes.mapPos(position);
  return presentations.map((presentation): TablePresentation => ({
    ...presentation,
    from: map(presentation.from),
    to: map(presentation.to),
    header: presentation.header.map((cell) => ({...cell, sourceOffset: map(cell.sourceOffset)})),
    body: presentation.body.map((row) =>
      row.map((cell) => ({...cell, sourceOffset: map(cell.sourceOffset)}))),
  }));
}

const liveTableField = StateField.define<LiveTableProjectionState>({
  create: buildLiveTableDecorations,
  update(previous, transaction) {
    const syntaxTreeChanged = transactionChangedSyntaxTree(transaction);
    if (!transaction.docChanged && syntaxTreeChanged) {
      return buildLiveTableDecorations(transaction.state);
    }
    if (!previous.hasConstructs) {
      if (!transaction.docChanged) return previous;
      if (!transactionMayCreateProjection(transaction, /\|/)) return previous;
    }
    if (!transaction.docChanged) {
      if (transaction.startState.selection.eq(transaction.state.selection)) return previous;
      if (activeProjectionSignature(transaction.startState.selection.ranges, previous.presentations)
          === activeProjectionSignature(transaction.state.selection.ranges, previous.presentations)) {
        return previous;
      }
      return {
        ...previous,
        decorations: liveTableDecorations(transaction.state, previous.presentations),
      };
    }
    if (transactionCanMapProjection(transaction, /\|/, previous.presentations)) {
      const presentations = mapTablePresentations(previous.presentations, transaction);
      return {
        decorations: liveTableDecorations(transaction.state, presentations),
        hasConstructs: true,
        presentations,
      };
    }
    return buildLiveTableDecorations(transaction.state);
  },
  provide: (field) => [
    EditorView.decorations.from(field, (value) => value.decorations),
    EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
  ],
});

interface LiveDisplayMathProjectionState extends LiveBlockProjectionState {
  presentations: readonly MathProjection[];
}

function liveDisplayMathDecorations(
  state: EditorState,
  presentations: readonly MathProjection[],
) {
  return Decoration.set(presentations.flatMap((presentation): Range<Decoration>[] => {
    const active = state.selection.ranges.some((range) =>
      selectionIntersectsProjection(range, presentation));
    if (active) return [];
    return [Decoration.replace({
      widget: new MathWidget(presentation),
      block: true,
    }).range(presentation.from, presentation.to)];
  }), true);
}

function buildLiveDisplayMathDecorations(state: EditorState): LiveDisplayMathProjectionState {
  const index = liveProjectionIndexForState(state);
  if (index.hasUnclosedFrontmatter) {
    return {decorations: Decoration.none, hasConstructs: true, presentations: []};
  }
  const presentations = index.mathExpressions.filter((expression) => expression.kind === "display");
  return {
    decorations: liveDisplayMathDecorations(state, presentations),
    hasConstructs: presentations.length > 0,
    presentations,
  };
}

function mapMathPresentations(
  presentations: readonly MathProjection[],
  transaction: Transaction,
) {
  const map = (position: number) => transaction.changes.mapPos(position);
  return presentations.map((presentation): MathProjection => ({
    ...presentation,
    from: map(presentation.from),
    to: map(presentation.to),
    contentFrom: map(presentation.contentFrom),
    contentTo: map(presentation.contentTo),
  }));
}

const liveDisplayMathField = StateField.define<LiveDisplayMathProjectionState>({
  create: buildLiveDisplayMathDecorations,
  update(previous, transaction) {
    const syntaxTreeChanged = transactionChangedSyntaxTree(transaction);
    if (!transaction.docChanged && syntaxTreeChanged) {
      return buildLiveDisplayMathDecorations(transaction.state);
    }
    if (!previous.hasConstructs) {
      if (!transaction.docChanged) return previous;
      if (!transactionMayCreateProjection(transaction, /\$/)) return previous;
    }
    if (!transaction.docChanged) {
      if (transaction.startState.selection.eq(transaction.state.selection)) return previous;
      if (activeProjectionSignature(transaction.startState.selection.ranges, previous.presentations)
          === activeProjectionSignature(transaction.state.selection.ranges, previous.presentations)) {
        return previous;
      }
      return {
        ...previous,
        decorations: liveDisplayMathDecorations(transaction.state, previous.presentations),
      };
    }
    if (transactionCanMapProjection(transaction, /\$/, previous.presentations)) {
      const presentations = mapMathPresentations(previous.presentations, transaction);
      return {
        decorations: liveDisplayMathDecorations(transaction.state, presentations),
        hasConstructs: true,
        presentations,
      };
    }
    return buildLiveDisplayMathDecorations(transaction.state);
  },
  provide: (field) => [
    EditorView.decorations.from(field, (value) => value.decorations),
    EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
  ],
});

interface RawHTMLPresentation extends ProjectionSourceRange {
  readonly source: string;
}

interface LiveRawHTMLProjectionState extends LiveBlockProjectionState {
  readonly presentations: readonly RawHTMLPresentation[];
}

class RawHTMLWidget extends WidgetType {
  constructor(readonly presentation: RawHTMLPresentation) { super(); }
  eq(other: RawHTMLWidget) { return other.presentation.source === this.presentation.source; }
  toDOM() {
    const pre = document.createElement("pre");
    pre.className = [
      "raw-html",
      "cm-live-raw-html",
      "cm-live-raw-html-start",
      "cm-live-raw-html-end",
      "cm-live-raw-html-widget",
    ].join(" ");
    pre.dataset.scholiumProtected = "raw-html";
    pre.textContent = this.presentation.source;
    return pre;
  }
  ignoreEvent() { return false; }
}

function liveRawHTMLDecorations(
  state: EditorState,
  presentations: readonly RawHTMLPresentation[],
) {
  return Decoration.set(presentations.flatMap((presentation): Range<Decoration>[] => {
    const active = state.selection.ranges.some((range) =>
      selectionIntersectsProjection(range, presentation));
    if (active) return [];
    return [Decoration.replace({
      widget: new RawHTMLWidget(presentation),
      block: true,
    }).range(presentation.from, presentation.to)];
  }), true);
}

function buildLiveRawHTMLDecorations(state: EditorState): LiveRawHTMLProjectionState {
  const index = liveProjectionIndexForState(state);
  if (index.hasUnclosedFrontmatter) {
    return {decorations: Decoration.none, hasConstructs: true, presentations: []};
  }
  const presentations = index.syntax.blocks
    .filter((block) => block.kind === "html")
    .map((block): RawHTMLPresentation => ({
      from: block.from,
      to: block.to,
      source: state.doc.sliceString(block.from, block.to),
    }));
  return {
    decorations: liveRawHTMLDecorations(state, presentations),
    hasConstructs: presentations.length > 0,
    presentations,
  };
}

function mapRawHTMLPresentations(
  presentations: readonly RawHTMLPresentation[],
  transaction: Transaction,
) {
  return presentations.map((presentation): RawHTMLPresentation => ({
    ...presentation,
    from: transaction.changes.mapPos(presentation.from),
    to: transaction.changes.mapPos(presentation.to),
  }));
}

const liveRawHTMLField = StateField.define<LiveRawHTMLProjectionState>({
  create: buildLiveRawHTMLDecorations,
  update(previous, transaction) {
    if (!transaction.docChanged && transactionChangedSyntaxTree(transaction)) {
      return buildLiveRawHTMLDecorations(transaction.state);
    }
    if (!previous.hasConstructs) {
      if (!transaction.docChanged) return previous;
      if (!transactionMayCreateProjection(transaction, /[<>]/)) return previous;
    }
    if (!transaction.docChanged) {
      if (transaction.startState.selection.eq(transaction.state.selection)) return previous;
      if (activeProjectionSignature(transaction.startState.selection.ranges, previous.presentations)
          === activeProjectionSignature(transaction.state.selection.ranges, previous.presentations)) {
        return previous;
      }
      return {
        ...previous,
        decorations: liveRawHTMLDecorations(transaction.state, previous.presentations),
      };
    }
    if (transactionCanMapProjection(transaction, /[<>]/, previous.presentations)) {
      const presentations = mapRawHTMLPresentations(previous.presentations, transaction);
      return {
        decorations: liveRawHTMLDecorations(transaction.state, presentations),
        hasConstructs: true,
        presentations,
      };
    }
    return buildLiveRawHTMLDecorations(transaction.state);
  },
  provide: (field) => [
    EditorView.decorations.from(field, (value) => value.decorations),
    EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
  ],
});

interface LiveCalloutProjectionState extends LiveBlockProjectionState {
  presentations: readonly CalloutPresentation[];
}

const calloutWidgetPresentations = new WeakMap<HTMLElement, CalloutPresentation>();

class CalloutWidget extends WidgetType {
  constructor(readonly presentation: CalloutPresentation) { super(); }

  eq(other: CalloutWidget) {
    const equal = other.presentation.from === this.presentation.from
      && other.presentation.to === this.presentation.to
      && other.presentation.source === this.presentation.source;
    if (equal) liveWidgetReuseCounts.callout += 1;
    return equal;
  }

  toDOM(view: EditorView) {
    const slot = document.createElement("div");
    slot.className = "cm-live-callout-slot";
    appendMarkdownBlocks(this.presentation.source, slot, {
      mathematics: editingDialect?.mathematics,
      resolveCallout: calloutDefinition,
    });
    const callout = slot.firstElementChild;
    if (!(callout instanceof HTMLElement) || !callout.classList.contains("scholium-callout")) {
      const fallback = document.createElement("pre");
      fallback.className = "cm-live-callout-widget cm-live-callout-widget-fallback";
      fallback.textContent = this.presentation.source;
      slot.replaceChildren(fallback);
      return slot;
    }
    // The fragment renderer appends its terminal newline as a text node.
    // Inside a CodeMirror block widget that whitespace creates an otherwise
    // invisible 24px line box after every Callout, so retain only the single
    // semantic component owned by this projection.
    slot.replaceChildren(callout);
    callout.classList.add("cm-live-callout-widget");
    calloutWidgetPresentations.set(slot, this.presentation);
    callout.addEventListener("mousedown", (event) => {
      if ((event.target as Element | null)?.closest(".scholium-callout-fold-mark")) return;
      const presentation = calloutWidgetPresentations.get(slot);
      if (presentation) beginCalloutPointerSelection(view, event, presentation);
    });
    callout.addEventListener("click", (event) => {
      if ((event.target as Element | null)?.closest(".scholium-callout-fold-mark")) return;
      event.preventDefault();
    });
    if (callout instanceof HTMLDetailsElement) {
      let measurePending = false;
      callout.addEventListener("toggle", () => {
        if (measurePending) return;
        measurePending = true;
        queueMicrotask(() => {
          measurePending = false;
          view.requestMeasure();
        });
      });
    }
    return slot;
  }

  updateDOM(dom: HTMLElement) {
    const previous = calloutWidgetPresentations.get(dom);
    if (!previous || previous.source !== this.presentation.source) return false;
    calloutWidgetPresentations.set(dom, this.presentation);
    liveWidgetReuseCounts.callout += 1;
    return true;
  }

  ignoreEvent() { return true; }
}

function beginCalloutPointerSelection(
  view: EditorView,
  event: MouseEvent,
  presentation: CalloutPresentation,
) {
  event.preventDefault();
  // Projection ranges are half-open. `presentation.to` belongs to the
  // following source boundary, where Backspace may otherwise treat the whole
  // replaced Callout as the preceding atomic unit. Enter through the final
  // source unit instead; a subsequent pointer drag is then measured against
  // the revealed exact Markdown and clamped to the same safe range.
  const sourceHead = Math.max(presentation.from, presentation.to - 1);
  const anchor = event.shiftKey ? view.state.selection.main.anchor : sourceHead;
  view.dispatch({
    effects: setLiveBlockActivationEffect.of({
      kind: "callout",
      from: presentation.from,
      to: presentation.to,
      edge: "end",
    }),
    selection: {anchor, head: sourceHead},
    scrollIntoView: true,
  });
  view.focus();

  let latestCoordinates: {x: number; y: number} | null = null;
  let measurePending = false;
  const measureLatestPosition = () => {
    if (measurePending) return;
    measurePending = true;
    view.requestMeasure({
      read: () => {
        const coordinates = latestCoordinates;
        latestCoordinates = null;
        return coordinates ? view.posAtCoords(coordinates) : null;
      },
      write: (head) => {
        measurePending = false;
        if (head !== null) {
          const safeHead = Math.max(
            presentation.from,
            Math.min(Math.max(presentation.from, presentation.to - 1), head),
          );
          view.dispatch({selection: {anchor, head: safeHead}});
        }
        if (latestCoordinates) measureLatestPosition();
      },
    });
  };
  const move = (moveEvent: MouseEvent) => {
    latestCoordinates = {x: moveEvent.clientX, y: moveEvent.clientY};
    measureLatestPosition();
  };
  const finish = () => {
    latestCoordinates = null;
    window.removeEventListener("mousemove", move, true);
    window.removeEventListener("mouseup", finish, true);
  };
  window.addEventListener("mousemove", move, true);
  window.addEventListener("mouseup", finish, true);
  view.requestMeasure();
}

function liveCalloutDecorations(
  state: EditorState,
  presentations: readonly CalloutPresentation[],
) {
  const decorations = presentations.flatMap((presentation): Range<Decoration>[] => {
    const activation = state.field(liveBlockActivationField, false);
    const active = state.selection.ranges.some((range) =>
      selectionIntersectsProjection(range, presentation),
    ) || activation?.kind === "callout"
      && activation.from === presentation.from
      && activation.to === presentation.to;
    if (active) return [];
    return [Decoration.replace({
      widget: new CalloutWidget(presentation),
      block: true,
    }).range(presentation.from, presentation.to)];
  });
  return Decoration.set(decorations, true);
}

function buildLiveCalloutDecorations(state: EditorState): LiveCalloutProjectionState {
  const index = liveProjectionIndexForState(state);
  if (index.hasUnclosedFrontmatter) {
    return {decorations: Decoration.none, hasConstructs: true, presentations: []};
  }
  const presentations = index.callouts;
  return {
    decorations: liveCalloutDecorations(state, presentations),
    hasConstructs: presentations.length > 0,
    presentations,
  };
}

const liveCalloutField = StateField.define<LiveCalloutProjectionState>({
  create: buildLiveCalloutDecorations,
  update(previous, transaction) {
    const syntaxTreeChanged = transactionChangedSyntaxTree(transaction);
    if (!transaction.docChanged && syntaxTreeChanged) {
      return buildLiveCalloutDecorations(transaction.state);
    }
    if (!previous.hasConstructs) {
      if (!transaction.docChanged) return previous;
      if (!transactionMayCreateProjection(transaction, /[>\[\]!]/)) return previous;
    }
    if (!transaction.docChanged) {
      const previousActivation = transaction.startState.field(liveBlockActivationField, false);
      const nextActivation = transaction.state.field(liveBlockActivationField, false);
      const activationChanged = previousActivation?.kind !== nextActivation?.kind
        || previousActivation?.from !== nextActivation?.from
        || previousActivation?.to !== nextActivation?.to
        || previousActivation?.edge !== nextActivation?.edge;
      if (transaction.startState.selection.eq(transaction.state.selection) && !activationChanged) return previous;
      if (activeProjectionSignature(transaction.startState.selection.ranges, previous.presentations)
          === activeProjectionSignature(transaction.state.selection.ranges, previous.presentations)
          && !activationChanged) {
        return previous;
      }
      return {
        ...previous,
        decorations: liveCalloutDecorations(transaction.state, previous.presentations),
      };
    }
    if (transactionCanMapProjection(transaction, /[>\[\]!]/, previous.presentations)) {
      const presentations = previous.presentations.map((presentation) => ({
        ...presentation,
        from: transaction.changes.mapPos(presentation.from),
        to: transaction.changes.mapPos(presentation.to),
      }));
      return {
        decorations: liveCalloutDecorations(transaction.state, presentations),
        hasConstructs: true,
        presentations,
      };
    }
    return buildLiveCalloutDecorations(transaction.state);
  },
  provide: (field) => [
    EditorView.decorations.from(field, (value) => value.decorations),
    EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
  ],
});

const footnoteReferencePresentations = new WeakMap<HTMLElement, FootnoteReferencePresentation>();

class FootnoteReferenceWidget extends WidgetType {
  constructor(readonly reference: FootnoteReferencePresentation) { super(); }

  eq(other: FootnoteReferenceWidget) {
    const equal = other.reference.identifier === this.reference.identifier
      && other.reference.ordinal === this.reference.ordinal
      && other.reference.occurrence === this.reference.occurrence
      && other.reference.from === this.reference.from
      && other.reference.definitionFrom === this.reference.definitionFrom
      && other.reference.definitionContentFrom === this.reference.definitionContentFrom;
    if (equal) liveWidgetReuseCounts.footnote += 1;
    return equal;
  }

  toDOM(view: EditorView) {
    const wrapper = document.createElement("sup");
    wrapper.className = "footnote-reference-wrap cm-live-footnote-reference-widget";
    wrapper.dataset.scholiumProtected = "footnote";
    const marker = document.createElement("span");
    marker.className = "footnote-reference";
    marker.dataset.footnote = String(this.reference.ordinal);
    marker.dataset.scholiumProtected = "footnote-marker";
    marker.setAttribute("aria-label", `Footnote ${this.reference.ordinal}`);
    marker.textContent = String(this.reference.ordinal);
    if (this.reference.definitionFrom === null) {
      marker.setAttribute("aria-disabled", "true");
      marker.classList.add("footnote-reference-missing");
    }
    wrapper.addEventListener("mousedown", (event) => {
      const reference = footnoteReferencePresentations.get(wrapper);
      if (!reference || reference.definitionContentFrom === null) return;
      beginProjectedPointerSelection(view, event, reference.definitionContentFrom);
    });
    footnoteReferencePresentations.set(wrapper, this.reference);
    wrapper.append(marker);
    return wrapper;
  }

  updateDOM(dom: HTMLElement) {
    const previous = footnoteReferencePresentations.get(dom);
    const sameContent = previous
      && previous.identifier === this.reference.identifier
      && previous.ordinal === this.reference.ordinal
      && previous.occurrence === this.reference.occurrence
      && previous.definitionFrom === this.reference.definitionFrom
      && previous.definitionContentFrom === this.reference.definitionContentFrom;
    if (!sameContent) return false;
    footnoteReferencePresentations.set(dom, this.reference);
    liveWidgetReuseCounts.footnote += 1;
    return true;
  }

  ignoreEvent() { return false; }
}

interface LiveFootnoteReferenceState {
  decorations: DecorationSet;
  hasConstructs: boolean;
  presentation: FootnotePresentation;
  ranges: readonly Readonly<ProjectionSourceRange>[];
}

function liveFootnoteReferenceDecorations(
  state: EditorState,
  presentation: FootnotePresentation,
) {
  const decorations: Range<Decoration>[] = [];
  const active = (from: number, to: number) => state.selection.ranges.some((range) =>
    selectionIntersectsProjection(range, {from, to}),
  );
  for (const reference of presentation.references) {
    const containedByDefinition = presentation.definitions.some((definition) =>
      !definition.isInline && definition.from <= reference.from && definition.to >= reference.to,
    );
    if (containedByDefinition || active(reference.from, reference.to)) continue;
    decorations.push(Decoration.replace({
      widget: new FootnoteReferenceWidget(reference),
    }).range(reference.from, reference.to));
  }
  return Decoration.set(decorations, true);
}

function buildLiveFootnoteReferenceState(state: EditorState): LiveFootnoteReferenceState {
  const index = liveProjectionIndexForState(state);
  if (index.hasUnclosedFrontmatter) {
    return {
      decorations: Decoration.none,
      hasConstructs: true,
      presentation: {definitions: [], references: []},
      ranges: [],
    };
  }
  const presentation = index.footnotes;
  return {
    decorations: liveFootnoteReferenceDecorations(state, presentation),
    hasConstructs: presentation.definitions.length > 0 || presentation.references.length > 0,
    presentation,
    ranges: index.footnoteRanges,
  };
}

function mapFootnotePresentation(
  presentation: FootnotePresentation,
  transaction: Transaction,
): FootnotePresentation {
  const map = (position: number) => transaction.changes.mapPos(position);
  return {
    definitions: presentation.definitions.map((definition) => ({
      ...definition,
      from: map(definition.from),
      to: map(definition.to),
      contentFrom: map(definition.contentFrom),
    })),
    references: presentation.references.map((reference) => ({
      ...reference,
      from: map(reference.from),
      to: map(reference.to),
      definitionFrom: reference.definitionFrom === null ? null : map(reference.definitionFrom),
      definitionContentFrom: reference.definitionContentFrom === null
        ? null
        : map(reference.definitionContentFrom),
    })),
  };
}

const liveFootnoteReferenceField = StateField.define<LiveFootnoteReferenceState>({
  create: buildLiveFootnoteReferenceState,
  update(previous, transaction) {
    const syntaxTreeChanged = transactionChangedSyntaxTree(transaction);
    if (!transaction.docChanged && syntaxTreeChanged) {
      return buildLiveFootnoteReferenceState(transaction.state);
    }
    if (!previous.hasConstructs) {
      if (!transaction.docChanged) return previous;
      if (!transactionMayCreateProjection(transaction, /[\[\]\^:]/)) return previous;
    }
    if (!transaction.docChanged) {
      if (transaction.startState.selection.eq(transaction.state.selection)) return previous;
      if (activeProjectionSignature(transaction.startState.selection.ranges, previous.ranges)
          === activeProjectionSignature(transaction.state.selection.ranges, previous.ranges)) {
        return previous;
      }
      return {
        ...previous,
        decorations: liveFootnoteReferenceDecorations(transaction.state, previous.presentation),
      };
    }
    if (transactionCanMapProjection(transaction, /[\[\]\^:]/, previous.ranges)) {
      const presentation = mapFootnotePresentation(previous.presentation, transaction);
      const ranges = immutableProjectionRanges([
        ...presentation.definitions,
        ...presentation.references,
      ].map(({from, to}) => ({from, to})));
      return {
        decorations: liveFootnoteReferenceDecorations(transaction.state, presentation),
        hasConstructs: true,
        presentation,
        ranges,
      };
    }
    return buildLiveFootnoteReferenceState(transaction.state);
  },
  provide: (field) => [
    EditorView.decorations.from(field, (value) => value.decorations),
    EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
  ],
});

interface LiveInlineProjectionState {
  decorations: DecorationSet;
  atomicRanges: DecorationSet;
  coveredRanges: readonly ProjectionSourceRange[];
}

interface SemanticPhysicalLine {
  readonly from: number;
  readonly to: number;
  readonly length: number;
  readonly number: number;
  readonly text: string;
}

interface SemanticLinePresentation {
  readonly active: boolean;
  readonly classes: readonly string[];
  readonly codeBlock: Readonly<SemanticCodeBlockRange> | null;
  readonly heading: SemanticBlockProjection | null;
  readonly headingMarkers: readonly {from: number; to: number}[];
  readonly paragraph: SemanticBlockProjection | null;
  readonly quote: SemanticBlockProjection | null;
  readonly quoteMarkers: readonly {from: number; to: number}[];
  readonly rule: SemanticBlockProjection | null;
  readonly html: SemanticBlockProjection | null;
  readonly comment: SemanticBlockProjection | null;
  readonly list: SemanticBlockProjection | null;
  readonly listMarker: {from: number; to: number} | null;
}

function semanticLinePresentation(
  state: EditorState,
  line: SemanticPhysicalLine,
  index: LiveProjectionIndex,
): SemanticLinePresentation {
  const lineQueryTo = Math.min(state.doc.length, line.to + 1);
  const active = state.selection.ranges.some((range) =>
    range.head >= line.from && range.head <= line.to
      || !range.empty && range.from < lineQueryTo && range.to >= line.from);
  const blocks = rangesIntersecting(index.syntax.blocks, line.from, lineQueryTo);
  const codeBlock = rangesIntersecting(index.literals.codeBlocks, line.from, lineQueryTo)[0] ?? null;
  const heading = blocks.find((block) => block.kind === "heading") ?? null;
  const headingMarkers = heading?.markerRanges.filter((range) =>
    range.from < lineQueryTo && range.to > line.from) ?? [];
  const headingMarkerOnly = line.length > 0 && headingMarkers.some((range) =>
    range.from <= line.from && range.to >= line.to);
  const paragraph = blocks.find((block) => block.kind === "paragraph") ?? null;
  const callout = blocks.find((block) => block.kind === "callout") ?? null;
  const quote = callout ? null : blocks.find((block) => block.kind === "blockQuote") ?? null;
  const quoteMarkers = quote?.markerRanges.filter((range) =>
    range.from < lineQueryTo && range.to > line.from) ?? [];
  const rule = blocks.find((block) => block.kind === "thematicBreak") ?? null;
  const html = blocks.find((block) => block.kind === "html") ?? null;
  const blockComment = blocks.find((block) => block.kind === "comment") ?? null;
  const inlineComment = rangesIntersecting(index.syntax.inlines, line.from, lineQueryTo)
    .find((inline) => inline.kind === "comment") ?? null;
  const comment = blockComment ?? (inlineComment ? {
    kind: "comment" as const,
    nodeName: inlineComment.nodeName,
    from: inlineComment.from,
    to: inlineComment.to,
    depth: 0,
    parent: null,
    headingLevel: null,
    listDepth: null,
    markerRanges: inlineComment.markerRanges,
    taskMarkerRange: null,
  } : null);
  const list = blocks
    .filter((block) => block.kind === "listItem")
    .filter((block) => block.markerRanges.some((range) =>
      range.from >= line.from && range.from <= line.to))
    .sort((left, right) => (right.listDepth ?? 0) - (left.listDepth ?? 0))[0] ?? null;
  const listMarker = list?.markerRanges.find((range) =>
    range.from >= line.from
      && range.from <= line.to
      && !state.doc.sliceString(range.from, range.to).startsWith("[")) ?? null;
  const classes = new Set<string>();
  const outsideFrontmatter = !index.frontmatterRange || line.from >= index.frontmatterRange.to;
  if (line.length === 0 && outsideFrontmatter && !codeBlock) {
    classes.add("cm-live-blank-line");
  }
  if (codeBlock) {
    classes.add("cm-live-codeblock");
    if (!active && isFencedDelimiterLine(state.doc, codeBlock, line.from)) {
      classes.add("cm-live-code-fence-line");
    } else {
      const firstContentLine = codeBlock.fenced && codeBlock.markerRanges.length > 0
        ? Math.min(
            state.doc.lines,
            state.doc.lineAt(codeBlock.markerRanges[0].from).number + 1,
          )
        : state.doc.lineAt(codeBlock.from).number;
      const lastContentLine = codeBlock.fenced && codeBlock.markerRanges.length > 1
        ? Math.max(
            firstContentLine,
            state.doc.lineAt(codeBlock.markerRanges.at(-1)!.from).number - 1,
          )
        : state.doc.lineAt(codeBlock.to).number;
      if (line.number === firstContentLine) classes.add("cm-live-codeblock-start");
      if (line.number === lastContentLine) classes.add("cm-live-codeblock-end");
    }
  } else if (comment) {
    classes.add("cm-live-paragraph");
    classes.add("cm-live-paragraph-start");
    classes.add("cm-live-paragraph-end");
  } else if (html) {
    classes.add("cm-live-raw-html");
    if (line.from <= html.from) classes.add("cm-live-raw-html-start");
    if (line.to >= html.to) classes.add("cm-live-raw-html-end");
  } else {
    if (heading && heading.headingLevel !== null) {
      if (headingMarkerOnly) {
        if (!active) classes.add("cm-live-heading-marker-line");
      } else {
        classes.add("cm-live-heading");
        classes.add(`cm-live-h${heading.headingLevel}`);
        if (heading.headingLevel === 1) classes.add("cm-live-document-title");
      }
    }
    if (paragraph && !callout && !heading) {
      classes.add("cm-live-paragraph");
      if (line.from <= paragraph.from) classes.add("cm-live-paragraph-start");
      if (line.to >= paragraph.to) classes.add("cm-live-paragraph-end");
    }
    if (quote) classes.add("cm-live-quote");
    if (rule && !active) classes.add("cm-live-rule");
    if (list && listMarker) {
      classes.add("cm-live-list");
      if ((list.listDepth ?? 0) > 0) classes.add("cm-live-list-nested");
      if (list.taskMarkerRange) classes.add("cm-live-task-list");
    }
  }
  return {
    active,
    classes: [...classes],
    codeBlock,
    heading,
    headingMarkers,
    paragraph,
    quote,
    quoteMarkers,
    rule,
    html,
    comment,
    list,
    listMarker,
  };
}

interface LiveSemanticLineState {
  readonly decorations: DecorationSet;
}

function semanticLineDecorationRanges(
  state: EditorState,
  from = 0,
  to = state.doc.length,
): Range<Decoration>[] {
  const index = liveProjectionIndexForState(state);
  if (index.hasUnclosedFrontmatter) return [];
  const ranges: Range<Decoration>[] = [];
  const scanFrom = Math.max(0, Math.min(from, state.doc.length));
  const scanTo = Math.max(scanFrom, Math.min(to, state.doc.length));
  let line = state.doc.lineAt(scanFrom);
  while (line.from <= scanTo) {
    const presentation = semanticLinePresentation(state, line, index);
    const direction = presentation.codeBlock || presentation.html
      ? "ltr"
      : presentation.heading
          || presentation.paragraph
          || presentation.quote
          || presentation.list
          || presentation.comment
        ? "auto"
        : null;
    if (presentation.classes.length > 0 || direction) {
      const attributes: Record<string, string> = {};
      if (presentation.classes.length > 0) {
        attributes.class = presentation.classes.join(" ");
      }
      if (direction) attributes.dir = direction;
      ranges.push(Decoration.line({
        attributes,
      }).range(line.from));
    }
    if (line.number >= state.doc.lines) break;
    line = state.doc.line(line.number + 1);
  }
  return ranges;
}

function expandedPhysicalLineRanges(
  state: EditorState,
  sourceRanges: readonly ProjectionSourceRange[],
) {
  const expanded = sourceRanges.map((range) => {
    const from = Math.max(0, Math.min(range.from, state.doc.length));
    const to = Math.max(from, Math.min(range.to, state.doc.length));
    return {
      from: state.doc.lineAt(from).from,
      to: state.doc.lineAt(to).to,
    };
  }).sort((left, right) => left.from - right.from || left.to - right.to);
  const merged: ProjectionSourceRange[] = [];
  for (const range of expanded) {
    const previous = merged.at(-1);
    if (previous && range.from <= previous.to + 1) previous.to = Math.max(previous.to, range.to);
    else merged.push({...range});
  }
  return merged;
}

function replacingLineDecorationsInRanges(
  existing: DecorationSet,
  state: EditorState,
  affected: readonly ProjectionSourceRange[],
) {
  let decorations = existing;
  for (const range of expandedPhysicalLineRanges(state, affected)) {
    decorations = decorations.update({
      filter: (from) => from < range.from || from > range.to,
      add: semanticLineDecorationRanges(state, range.from, range.to),
      sort: true,
    });
  }
  return decorations;
}

function buildLiveSemanticLineState(state: EditorState): LiveSemanticLineState {
  return {
    decorations: Decoration.set(semanticLineDecorationRanges(state), true),
  };
}

const liveSemanticLineField = StateField.define<LiveSemanticLineState>({
  create: buildLiveSemanticLineState,
  update(previous, transaction) {
    if (transactionChangedSyntaxTree(transaction)) {
      return buildLiveSemanticLineState(transaction.state);
    }
    if (transaction.docChanged) {
      const oldIndex = liveProjectionIndexForState(transaction.startState);
      const structuralMarker = /[\r\n`~<>%$\[\]!*_|^:]/;
      if (!transactionCanMapProjection(
        transaction,
        structuralMarker,
        oldIndex.mutationSensitiveRanges,
      )) {
        return buildLiveSemanticLineState(transaction.state);
      }
      const mapped = previous.decorations.map(transaction.changes);
      const affected = mergedChangedLineRanges(transaction);
      return {
        decorations: replacingLineDecorationsInRanges(mapped, transaction.state, affected),
      };
    }
    if (!transaction.startState.selection.eq(transaction.state.selection)) {
      const affected = selectionAffectedProjectionRanges(
        transaction.state.doc.length,
        transaction.startState.selection.ranges,
        transaction.state.selection.ranges,
      );
      return {
        decorations: replacingLineDecorationsInRanges(
          previous.decorations,
          transaction.state,
          affected,
        ),
      };
    }
    return previous;
  },
  provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
});

function sourceDirectionDecorations(view: EditorView) {
  const ranges: Range<Decoration>[] = [];
  const decoratedLines = new Set<number>();
  for (const visible of view.visibleRanges) {
    let line = view.state.doc.lineAt(visible.from);
    while (line.from <= visible.to) {
      if (!decoratedLines.has(line.from)) {
        decoratedLines.add(line.from);
        ranges.push(Decoration.line({attributes: {dir: "auto"}}).range(line.from));
      }
      if (line.number >= view.state.doc.lines) break;
      line = view.state.doc.line(line.number + 1);
    }
  }
  return Decoration.set(ranges, true);
}

// Source remains exact Markdown. This viewport-bounded adapter adds only the
// HTML writing-direction attribute consumed by CodeMirror's own bidi cursor
// model; it owns no semantic typography, replacement, or vertical geometry.
const sourceTextDirection = ViewPlugin.fromClass(class {
  decorations: DecorationSet;
  constructor(view: EditorView) {
    this.decorations = sourceDirectionDecorations(view);
  }
  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = sourceDirectionDecorations(update.view);
    }
  }
}, {
  decorations: (value) => value.decorations,
});

type SemanticBlockSpacing = "none" | "half" | "paragraph" | "standard" | "callout";

function semanticBlockSpacing(block: SemanticBlockProjection): SemanticBlockSpacing {
  switch (block.kind) {
  case "unorderedList":
  case "orderedList":
  case "blockQuote":
  case "code":
  case "html": return "standard";
  case "table":
  case "displayMath": return "paragraph";
  case "callout": return "callout";
  case "thematicBreak": return "half";
  default: return "none";
  }
}

class SemanticBlockGapWidget extends WidgetType {
  readonly previous: SemanticBlockSpacing;
  readonly next: SemanticBlockSpacing;
  constructor(previous: SemanticBlockSpacing, next: SemanticBlockSpacing) {
    super();
    this.previous = previous;
    this.next = next;
  }
  eq(other: SemanticBlockGapWidget) {
    return other.previous === this.previous && other.next === this.next;
  }
  toDOM() {
    const gap = document.createElement("div");
    gap.className = [
      "cm-live-semantic-gap",
      `cm-live-semantic-gap-after-${this.previous}`,
      `cm-live-semantic-gap-before-${this.next}`,
    ].join(" ");
    gap.setAttribute("aria-hidden", "true");
    return gap;
  }
  ignoreEvent() { return true; }
}

interface LiveSemanticBlockSpacingState {
  readonly decorations: DecorationSet;
}

function semanticBlockGapRanges(state: EditorState): Range<Decoration>[] {
  const index = liveProjectionIndexForState(state);
  if (index.hasUnclosedFrontmatter) return [];
  const spacingPriority: Partial<Record<SemanticBlockProjection["kind"], number>> = {
    callout: 100,
    displayMath: 90,
    table: 80,
    code: 70,
    html: 60,
    orderedList: 50,
    unorderedList: 50,
    blockQuote: 40,
    thematicBreak: 30,
    heading: 20,
    paragraph: 10,
  };
  const rawTopLevelBlocks = index.syntax.blocks
    .filter((block) => block.parent === null)
    .filter((block) => block.to > (index.frontmatterRange?.to ?? 0));
  const topLevelBlocks = rawTopLevelBlocks
    .filter((candidate) => !rawTopLevelBlocks.some((owner) =>
      owner !== candidate
        && owner.from <= candidate.from
        && owner.to >= candidate.to
        && (spacingPriority[owner.kind] ?? 0) > (spacingPriority[candidate.kind] ?? 0)))
    .sort((left, right) => left.from - right.from || left.to - right.to);
  const ranges: Range<Decoration>[] = [];
  let previous: SemanticBlockProjection | null = null;
  for (const current of topLevelBlocks) {
    const previousSpacing = previous ? semanticBlockSpacing(previous) : "none";
    const nextSpacing = semanticBlockSpacing(current);
    if (previousSpacing !== "none" || nextSpacing !== "none") {
      ranges.push(Decoration.widget({
        widget: new SemanticBlockGapWidget(previousSpacing, nextSpacing),
        block: true,
        side: -1,
      }).range(current.from));
    }
    previous = current;
  }
  if (previous) {
    const spacing = semanticBlockSpacing(previous);
    if (spacing !== "none") {
      ranges.push(Decoration.widget({
        widget: new SemanticBlockGapWidget(spacing, "none"),
        block: true,
        side: 1,
      }).range(previous.to));
    }
  }
  return ranges;
}

function buildLiveSemanticBlockSpacingState(state: EditorState): LiveSemanticBlockSpacingState {
  return {decorations: Decoration.set(semanticBlockGapRanges(state), true)};
}

const liveSemanticBlockSpacingField = StateField.define<LiveSemanticBlockSpacingState>({
  create: buildLiveSemanticBlockSpacingState,
  update(previous, transaction) {
    if (!transaction.docChanged && !transactionChangedSyntaxTree(transaction)) return previous;
    if (transactionChangedSyntaxTree(transaction)) {
      return buildLiveSemanticBlockSpacingState(transaction.state);
    }
    const oldIndex = liveProjectionIndexForState(transaction.startState);
    const structuralMarker = /[\r\n`~<>%$\[\]!*_|^:]/;
    return transactionCanMapProjection(
      transaction,
      structuralMarker,
      oldIndex.mutationSensitiveRanges,
    )
      ? {decorations: previous.decorations.map(transaction.changes)}
      : buildLiveSemanticBlockSpacingState(transaction.state);
  },
  provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
});

function bufferedVisibleRanges(view: EditorView, margin = 2_000) {
  return immutableProjectionRanges(boundedProjectionRanges(
    view.state.doc.length,
    view.visibleRanges,
    margin,
  ));
}

function coversVisibleRanges(
  covered: readonly ProjectionSourceRange[],
  visible: readonly ProjectionSourceRange[],
) {
  return visible.every((range) => covered.some((candidate) =>
    candidate.from <= range.from && candidate.to >= range.to));
}

/** @param {EditorView} view */
function buildLiveDecorations(
  view: EditorView,
  requestedRanges?: readonly ProjectionSourceRange[],
): LiveInlineProjectionState {
  const projectionStartedAt = performance.now();
  const decorations: Range<Decoration>[] = [];
  const atomicRanges: Range<Decoration>[] = [];
  const doc = view.state.doc;
  const coveredRanges = requestedRanges
    ? immutableProjectionRanges(requestedRanges)
    : bufferedVisibleRanges(view);
  const projectionWindowUTF16Count = coveredRanges.reduce(
    (total, range) => total + Math.max(0, range.to - range.from),
    0,
  );
  const index = liveProjectionIndexForState(view.state);
  if (index.hasUnclosedFrontmatter) {
    recordEditorMetric("projection", projectionStartedAt, {
      documentLength: doc.length,
      visibleRangeCount: view.visibleRanges.length,
      decorationCount: 0,
      projectionWindowUTF16Count,
    });
    return {decorations: Decoration.none, atomicRanges: Decoration.none, coveredRanges};
  }
  const semanticLiterals = index.literals;
  const parsedProjection = index.syntax;
  const visibleLiterals = new Map<string, ProjectionSourceRange>();
  for (const covered of coveredRanges) {
    for (const literal of rangesIntersecting(
      semanticLiterals.excluded,
      covered.from,
      Math.min(doc.length + 1, covered.to + 1),
    )) {
      visibleLiterals.set(rangeKey(literal.from, literal.to), literal);
    }
  }
  const literals = [...visibleLiterals.values()];
  const mathExpressions = visibleInlineMathExpressions(view.state, coveredRanges, index);
  const activeBlockActivation = view.state.field(liveBlockActivationField, false);

  /** @param {number} from @param {number} to */
  const addHidden = (from: number, to: number) => {
    if (to <= from) return;
    const range = hiddenSyntax.range(from, to);
    decorations.push(range);
    atomicRanges.push(range);
  };
  const addAtomicReplacement = (decoration: Decoration, from: number, to: number) => {
    if (to <= from) return;
    const range = decoration.range(from, to);
    decorations.push(range);
    atomicRanges.push(range);
  };
  /** @param {number} from @param {number} to @param {string} className */
  const addMark = (from: number, to: number, className: string) => {
    if (to > from) decorations.push(liveMark(className).range(from, to));
  };
  const addPreviewMark = (from: number, to: number, className: string, previewIndex: number) => {
    if (to <= from) return;
    decorations.push(Decoration.mark({
      class: className,
      attributes: {
        "data-link-preview-index": String(previewIndex),
        "data-scholium-protected": "link-preview-anchor",
      },
    }).range(from, to));
  };
  for (const expression of mathExpressions) {
    literals.push({from: expression.from, to: expression.to});
    const activeConstruct = view.state.selection.ranges.some((range) =>
      selectionIntersectsProjection(range, expression),
    );
    if (activeConstruct) continue;
    addAtomicReplacement(Decoration.replace({
      widget: new MathWidget(expression),
    }), expression.from, expression.to);
  }

  literals.sort((left, right) => left.from - right.from || left.to - right.to);

  for (const visible of coveredRanges) {
    let line = doc.lineAt(visible.from);
    while (line.from <= visible.to) {
      const scanFrom = Math.max(line.from, visible.from);
      const scanTo = Math.min(line.to, visible.to);
      const text = doc.sliceString(scanFrom, scanTo);
      const lineFullyScanned = scanFrom === line.from && scanTo === line.to;
      const lineQueryTo = Math.min(doc.length, scanTo + 1);
      const activeLine = view.state.selection.ranges.some((range) =>
        range.head >= line.from && range.head <= line.to
          || !range.empty && range.from < lineQueryTo && range.to >= line.from,
      ) || view.composing && view.state.selection.ranges.some(
        (range) => range.from < lineQueryTo && range.to >= line.from,
      );
      const activeProtectedBlockLine = activeLine && rangesIntersecting(
        index.blockRanges,
        line.from,
        lineQueryTo,
      ).some((block) => view.state.selection.ranges.some((range) =>
        selectionIntersectsProjection(range, block),
      ));
      const inlineConstructIsActive = (from: number, to: number) =>
        activeProtectedBlockLine || view.state.selection.ranges.some((range) =>
          selectionIntersectsProjection(range, {from, to}),
        );
      const excluded = [...rangesIntersecting(literals, scanFrom, lineQueryTo)];
      const semanticBlocksOnLine = rangesIntersecting(
        parsedProjection.blocks,
        line.from,
        lineQueryTo,
      );

      if (index.frontmatterRange && line.from < index.frontmatterRange.to) {
        // The direct frontmatter StateField owns the entire closed envelope.
        // Adding line/CSS decorations here would desynchronize CodeMirror's
        // height map from the visible DOM.
      } else {
        const semanticCodeBlock = rangesIntersecting(
          semanticLiterals.codeBlocks,
          scanFrom,
          lineQueryTo,
        )[0];
        if (semanticCodeBlock) {
          const fenceLine = semanticCodeBlock
            ? isFencedDelimiterLine(doc, semanticCodeBlock, line.from)
            : false;
          if (fenceLine && !activeLine) {
            addHidden(line.from, line.to);
          } else if (!fenceLine) {
            addMark(scanFrom, scanTo, "cm-live-code");
          }
          if (line.to === doc.length) break;
          line = doc.line(line.number + 1);
          continue;
        }

        const heading = semanticBlocksOnLine.find((block) => block.kind === "heading");
        if (heading && heading.headingLevel !== null) {
          const lineMarkers = heading.markerRanges.filter((range) =>
            range.from < lineQueryTo && range.to > line.from);
          if (!activeLine) {
            for (const marker of lineMarkers) {
              addHidden(Math.max(line.from, marker.from), Math.min(line.to, marker.to));
            }
          }
        }

        const parsedCallout = rangesIntersecting(
          parsedProjection.callouts,
          scanFrom,
          lineQueryTo,
        )[0];
        const activeCalloutLine = parsedCallout && (
          activeBlockActivation?.kind === "callout"
            && activeBlockActivation.from === parsedCallout.from
            && activeBlockActivation.to === parsedCallout.to
          || view.state.selection.ranges.some((range) =>
            selectionIntersectsProjection(range, parsedCallout))
        );
        const quote = semanticBlocksOnLine.find((block) => block.kind === "blockQuote");
        if (quote && !parsedCallout) {
          if (!activeLine) {
            for (const marker of quote.markerRanges.filter((range) =>
              range.from < lineQueryTo && range.to > line.from)) {
              addHidden(Math.max(line.from, marker.from), Math.min(line.to, marker.to));
            }
          }
        }
        // An active Callout is exact editable Markdown. The block widget is
        // removed by liveCalloutField, and no Callout line styling, role
        // widget, marker hiding, or quote projection is permitted here.
        if (activeCalloutLine) {
          if (line.to === doc.length) break;
          line = doc.line(line.number + 1);
          continue;
        }

        const rule = lineFullyScanned
          ? semanticBlocksOnLine.find((block) => block.kind === "thematicBreak")
          : null;
        if (rule && !activeLine) {
          addHidden(rule.from, rule.to);
        }

        const list = semanticBlocksOnLine
          .filter((block) => block.kind === "listItem")
          .filter((block) => block.markerRanges.some((range) =>
            range.from >= line.from && range.from <= line.to))
          .sort((left, right) => (right.listDepth ?? 0) - (left.listDepth ?? 0))[0];
        const listMarker = list?.markerRanges.find((range) =>
          range.from >= line.from
            && range.from <= line.to
            && range !== list.taskMarkerRange
            && !doc.sliceString(range.from, range.to).startsWith("["));
        if (list && listMarker) {
          const marker = doc.sliceString(listMarker.from, listMarker.to);
          const ordered = list.parent?.kind === "orderedList";
          const nested = (list.listDepth ?? 0) > 0;
          const task = list.taskMarkerRange !== null;
          if (!activeLine) {
            // Review parses task brackets as ListItem metadata rather than
            // prose. Replace the same exact prefix while this line is
            // inactive; activating it restores every authoritative byte.
            const content = semanticBlocksOnLine.find((block) =>
              block.kind === "paragraph"
                && block.parent?.kind === "listItem"
                && block.parent.from === list.from
                && block.parent.to === list.to);
            const replacementTo = content?.from
              ?? (task ? list.taskMarkerRange!.to : listMarker.to);
            addAtomicReplacement(
              Decoration.replace({widget: new ListMarkerWidget(marker, ordered, nested, task)}),
              line.from,
              replacementTo,
            );
          }
        }

        const parsedTable = rangesIntersecting(
          parsedProjection.tables,
          scanFrom,
          lineQueryTo,
        )[0];
        const activeTable = parsedTable && view.state.selection.ranges.some((range) =>
          selectionIntersectsProjection(range, parsedTable),
        );
        if (activeTable) {
          decorations.push(Decoration.line({ attributes: { class: "cm-live-table" } }).range(line.from));
          if (!activeLine) {
            for (const match of text.matchAll(/\|/g)) addMark(scanFrom + match.index, scanFrom + match.index + 1, "cm-live-table-separator");
          }
        }

        // The Lezer-owned catalog decides whether this is a wikilink, embed,
        // or vector link and supplies its exact target/alias ranges. This
        // adapter only chooses the inactive visual representation.
        for (const construct of rangesIntersecting(
          parsedProjection.inlines,
          scanFrom,
          lineQueryTo,
        ).filter((candidate) =>
          candidate.kind === "wikilink" || candidate.kind === "vectorLink")) {
          if (construct.from < scanFrom || construct.to > scanTo
              || overlaps(excluded, construct.from, construct.to)) continue;
          const targetRange = construct.targetRange;
          if (!targetRange) continue;
          excluded.push({from: construct.from, to: construct.to});
          if (inlineConstructIsActive(construct.from, construct.to)) continue;

          const embed = construct.kind === "wikilink"
            && doc.sliceString(construct.from, Math.min(construct.to, construct.from + 3)) === "![[";
          const marker = construct.kind === "vectorLink"
            ? doc.sliceString(construct.from, construct.from + 1)
            : "";
          const kind = construct.kind === "vectorLink"
            ? editingDialect?.vectorLinkOperators.find((candidate) => candidate.marker === marker)?.kind
              ?? "neutral"
            : "neutral";
          const target = doc.sliceString(targetRange.from, targetRange.to);
          const alias = construct.aliasRange
            ? doc.sliceString(construct.aliasRange.from, construct.aliasRange.to)
            : undefined;
          const presentation = wikilinkPresentation(
            targetRange.from,
            target,
            construct.aliasRange?.from ?? null,
            alias,
          );
          if (embed) {
            addHidden(construct.from, targetRange.from);
          } else {
            addAtomicReplacement(
              Decoration.replace({widget: new VectorLinkIconWidget(kind)}),
              construct.from,
              targetRange.from,
            );
          }

          const linkClass = embed
            ? "cm-live-embed"
            : presentation.isLegacyRelationship && kind === "neutral"
              ? "cm-live-vector-link cm-live-vector-neutral cm-live-vector-legacy"
              : `cm-live-vector-link cm-live-vector-${kind.replaceAll("_", "-")}`;
          addHidden(targetRange.from, presentation.displayStart);
          const previewIndex = linkPreviewIndexByRange.get(rangeKey(construct.from, construct.to));
          if (previewIndex === undefined) {
            addMark(presentation.displayStart, presentation.displayEnd, linkClass);
          } else {
            addPreviewMark(presentation.displayStart, presentation.displayEnd, linkClass, previewIndex);
          }
          addHidden(presentation.displayEnd, construct.to);
        }

        for (const construct of rangesIntersecting(
          parsedProjection.inlines,
          scanFrom,
          lineQueryTo,
        )) {
          const className = liveInlineClassByKind[construct.kind];
          if (construct.kind === "comment") continue;
          if (!className) continue;
          const constructFrom = Math.max(scanFrom, construct.from);
          const constructTo = Math.min(scanTo, construct.to);
          if (constructTo <= constructFrom) continue;
          if (inlineConstructIsActive(construct.from, construct.to)) {
            addMark(constructFrom, constructTo, className);
            continue;
          }
          const visibleRanges = construct.visibleRanges
            .map((range) => ({
              from: Math.max(constructFrom, range.from),
              to: Math.min(constructTo, range.to),
            }))
            .filter((range) => range.to > range.from)
            .sort((left, right) => left.from - right.from || left.to - right.to);
          let position = constructFrom;
          for (const visible of visibleRanges) {
            if (visible.from > position) addHidden(position, visible.from);
            const previewIndex = construct.kind === "link"
              ? linkPreviewIndexByRange.get(rangeKey(construct.from, construct.to))
              : undefined;
            if (previewIndex === undefined) {
              addMark(visible.from, visible.to, className);
            } else {
              addPreviewMark(visible.from, visible.to, className, previewIndex);
            }
            position = Math.max(position, visible.to);
          }
          if (position < constructTo) addHidden(position, constructTo);
        }
      }

      if (line.to === doc.length) break;
      line = doc.line(line.number + 1);
    }
  }

  const result = Decoration.set(decorations, true);
  const atoms = Decoration.set(atomicRanges, true);
  recordEditorMetric("projection", projectionStartedAt, {
    documentLength: doc.length,
    visibleRangeCount: view.visibleRanges.length,
    decorationCount: decorations.length,
    projectionWindowUTF16Count,
    selectionScoped: requestedRanges ? 1 : 0,
    widgetReuseCount: liveWidgetReuseCounts.table
      + liveWidgetReuseCounts.callout
      + liveWidgetReuseCounts.footnote,
  });
  return {decorations: result, atomicRanges: atoms, coveredRanges};
}

function replacingDecorationsInRanges(
  existing: DecorationSet,
  replacement: DecorationSet,
  affected: readonly ProjectionSourceRange[],
) {
  const touches = (from: number, to: number) => affected.some((range) =>
    from === to
      ? from >= range.from && from <= range.to
      : from < range.to && to > range.from);
  const add: Range<Decoration>[] = [];
  replacement.between(0, editor.state.doc.length, (from, to, decoration) => {
    if (touches(from, to)) add.push(decoration.range(from, to));
  });
  return existing.update({
    filter: (from, to) => !touches(from, to),
    add,
    sort: true,
  });
}

class LivePreviewPlugin {
  decorations: DecorationSet;
  atomicRanges: DecorationSet;
  coveredRanges: readonly ProjectionSourceRange[];
  constructor(view: EditorView) {
    const projection = buildLiveDecorations(view);
    this.decorations = projection.decorations;
    this.atomicRanges = projection.atomicRanges;
    this.coveredRanges = projection.coveredRanges;
  }
  update(update: ViewUpdate) {
    const explicitlyRefreshed = update.transactions.some((transaction) =>
      transaction.effects.some((effect) => effect.is(refreshLivePreviewEffect)),
    );
    const syntaxTreeChanged = update.transactions.some(transactionChangedSyntaxTree);
    const viewportNeedsProjection = update.viewportChanged
      && !coversVisibleRanges(this.coveredRanges, update.view.visibleRanges);
    // Projection depends on document, selection, composition, syntax, and the
    // visible range—not on window focus. Rebuilding on focus loss can observe
    // an inactive WebKit page with temporarily empty visible ranges and erase
    // otherwise valid heading/block decorations until another transaction.
    if (update.docChanged || viewportNeedsProjection
        || explicitlyRefreshed || syntaxTreeChanged) {
      const projection = buildLiveDecorations(update.view);
      this.decorations = projection.decorations;
      this.atomicRanges = projection.atomicRanges;
      this.coveredRanges = projection.coveredRanges;
    } else if (update.selectionSet
        && !update.startState.selection.eq(update.state.selection)) {
      const inlineRanges = liveProjectionIndexForState(update.state).inlineRanges;
      if (!update.view.composing
          && selectionProjectionSignature(
            update.startState.doc,
            update.startState.selection.ranges,
            inlineRanges,
          ) === selectionProjectionSignature(
            update.state.doc,
            update.state.selection.ranges,
            inlineRanges,
          )) {
        return;
      }
      const affected = selectionAffectedProjectionRanges(
        update.state.doc.length,
        update.startState.selection.ranges,
        update.state.selection.ranges,
      );
      const projection = buildLiveDecorations(update.view, affected);
      this.decorations = replacingDecorationsInRanges(
        this.decorations,
        projection.decorations,
        affected,
      );
      this.atomicRanges = replacingDecorationsInRanges(
        this.atomicRanges,
        projection.atomicRanges,
        affected,
      );
    }
  }
}
const livePreview = ViewPlugin.fromClass(LivePreviewPlugin, {
  decorations: (value: LivePreviewPlugin) => value.decorations,
  provide: (plugin) => EditorView.atomicRanges.of((view) =>
    view.plugin(plugin)?.atomicRanges ?? Decoration.none),
});

class UnclosedFrontmatterWidget extends WidgetType {
  eq(other: UnclosedFrontmatterWidget) { return other instanceof UnclosedFrontmatterWidget; }

  get estimatedHeight() { return 72; }

  toDOM() {
    const notice = document.createElement("div");
    notice.className = "cm-live-frontmatter-unavailable";
    notice.dataset.scholiumProtected = "frontmatter-unavailable";
    notice.setAttribute("role", "note");
    notice.setAttribute(
      "aria-label",
      "Edit mode is unavailable because YAML frontmatter is not closed. Use Source mode to finish the frontmatter.",
    );

    const title = document.createElement("strong");
    title.textContent = "Edit mode unavailable";
    const detail = document.createElement("span");
    detail.textContent = "Close the YAML frontmatter in Source mode to restore the visual projection.";
    notice.append(title, detail);
    return notice;
  }

  ignoreEvent() { return true; }
}

interface LiveFrontmatterProjectionState {
  decorations: DecorationSet;
  atomicRanges: DecorationSet;
}

function buildLiveFrontmatterProjection(state: EditorState): LiveFrontmatterProjectionState {
  const index = liveProjectionIndexForState(state);
  if (index.hasUnclosedFrontmatter) {
    const unavailable = Decoration.set([
      Decoration.replace({
        widget: new UnclosedFrontmatterWidget(),
        block: true,
      }).range(0, state.doc.length),
    ]);
    return {
      decorations: unavailable,
      atomicRanges: unavailable,
    };
  }
  const bodyFrom = index.frontmatterRange?.to ?? 0;
  if (bodyFrom === 0) {
    return {decorations: Decoration.none, atomicRanges: Decoration.none};
  }
  // End before the line break that introduces the first body line. A block
  // replacement ending exactly at that line's start suppresses CodeMirror's
  // line and inline decorations at the shared boundary, leaving the H1 as
  // raw source even though its semantic node is present.
  const hiddenTo = state.doc.lineAt(Math.max(0, bodyFrom - 1)).to;
  const hiddenFrontmatter = Decoration.set([
    Decoration.replace({block: true}).range(0, hiddenTo),
  ]);
  const atomicFrontmatter = Decoration.set([
    Decoration.replace({block: true}).range(0, bodyFrom),
  ]);
  return {decorations: hiddenFrontmatter, atomicRanges: atomicFrontmatter};
}

const liveFrontmatterGuardField = StateField.define<LiveFrontmatterProjectionState>({
  create: buildLiveFrontmatterProjection,
  update(previous, transaction) {
    return transaction.docChanged ? buildLiveFrontmatterProjection(transaction.state) : previous;
  },
  provide: (field) => [
    EditorView.decorations.from(field, (value) => value.decorations),
    EditorView.atomicRanges.of((view) => view.state.field(field).atomicRanges),
  ],
});

function mergedChangedLineRanges(transaction: Transaction) {
  const ranges: ProjectionSourceRange[] = [];
  transaction.changes.iterChangedRanges((_fromA, _toA, fromB, toB) => {
    const startLine = transaction.state.doc.lineAt(Math.min(fromB, transaction.state.doc.length));
    const endLine = transaction.state.doc.lineAt(Math.min(toB, transaction.state.doc.length));
    const expandedStart = transaction.state.doc.line(Math.max(1, startLine.number - 1)).from;
    const expandedEnd = transaction.state.doc.line(
      Math.min(transaction.state.doc.lines, endLine.number + 1),
    ).to;
    const previous = ranges.at(-1);
    if (previous && expandedStart <= previous.to) {
      previous.to = Math.max(previous.to, expandedEnd);
    } else {
      ranges.push({from: expandedStart, to: expandedEnd});
    }
  });
  return ranges;
}

let dirty = false;
let pendingKeyStartedAt: number | null = null;
let forceNextInteractionContext = true;
let lastInteractionAvailabilitySignature: string | null = null;
const interactionReporter = new AnimationFrameCoalescer(
  (callback) => window.requestAnimationFrame(callback),
  (identifier) => window.cancelAnimationFrame(identifier),
  (callback, delayMilliseconds) => window.setTimeout(callback, delayMilliseconds),
  (identifier) => window.clearTimeout(identifier),
);
/** @type {number | null} */
let idleTimer: number | null = null;

const stateReporter = EditorView.updateListener.of((update) => {
  const isProgrammatic = update.transactions.some(
    (transaction) => transaction.annotation(programmaticDocumentChange) === true,
  );
  if (isProgrammatic) return;
  if (update.selectionSet && hiddenFrontmatterSourceSelection
      && !update.state.selection.eq(hiddenFrontmatterSourceSelection.clampedLiveSelection)) {
    // The hidden Source selection is a one-transition restoration aid, not a
    // second selection owner. Any subsequent researcher or command movement
    // in Edit invalidates it.
    hiddenFrontmatterSourceSelection = null;
  }
  if (update.docChanged) dirty = true;
  if (!update.docChanged && !update.selectionSet) return;

  if (update.docChanged) {
    if (pendingKeyStartedAt !== null) {
      const keyStartedAt = pendingKeyStartedAt;
      pendingKeyStartedAt = null;
      recordEditorMetric("key-to-state", keyStartedAt, {documentLength: update.state.doc.length});
      window.requestAnimationFrame(() => recordEditorMetric("key-to-paint", keyStartedAt, {
        documentLength: update.state.doc.length,
      }));
    }
    const baseGeneration = documentVersion;
    documentVersion += 1;
    if (hiddenFrontmatterSourceSelection?.documentVersion !== documentVersion) {
      hiddenFrontmatterSourceSelection = null;
    }
    /** @type {{from: number, to: number, insert: string}[]} */
    const changes: SourceDelta[] = [];
    const mirrorChanges: NormalizedSourceChange[] = [];
    update.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
      const insert = inserted.toString();
      changes.push({from: fromA, to: toA, insert});
      mirrorChanges.push({
        from: fromA,
        to: toA,
        insert,
        removed: update.startState.doc.sliceString(fromA, toA),
      });
    });
    const exactUpdateStartedAt = performance.now();
    if (!exactSourceMirror.apply(mirrorChanges)) {
      post({
        type: "editorError",
        message: "The editor could not preserve the exact source line endings.",
      });
      return;
    }
    recordEditorMetric("exact-source-update", exactUpdateStartedAt, {
      changeCount: mirrorChanges.length,
      documentLength: update.state.doc.length,
    });
    post({ type: "documentChanged", baseGeneration, resultingGeneration: documentVersion, changes });
  }

  scheduleEditorInteractionReport();

  if (update.docChanged) {
    if (idleTimer !== null) window.clearTimeout(idleTimer);
    idleTimer = window.setTimeout(() => post({ type: "idle", dirty }), 500);
  }
});

const linkActivation = EditorView.domEventHandlers({
  click(event) {
    if (event.metaKey) {
      const position = editor.posAtCoords({x: event.clientX, y: event.clientY});
      const target = position === null ? null : linkTargetAt(editor.state.doc, position);
      if (target) {
        post({type: "linkActivated", target});
        event.preventDefault();
        return true;
      }
    }
    return false;
  },
});

const saveKeymap = keymap.of([
  {
    key: "Mod-s",
    preventDefault: true,
    run: () => {
      post({ type: "requestSave" });
      return true;
    },
  },
  {
    key: "Mod-f",
    preventDefault: true,
    run: () => {
      post({ type: "requestSearch" });
      return true;
    },
  },
]);

function applyInteraction(
  transformation: ReturnType<typeof continueList>,
  userEvent: string,
) {
  if (!transformation) return false;
  editor.dispatch({
    changes: transformation.changes,
    selection: EditorSelection.create(
      transformation.selections.map((range) => EditorSelection.range(range.anchor, range.head)),
    ),
    annotations: Transaction.userEvent.of(userEvent),
  });
  lastUndoLabel = transformation.undoLabel;
  lastRedoLabel = transformation.undoLabel;
  return true;
}

const structuralInteractionKeymap = keymap.of([
  {
    key: "Enter",
    run: (view) => applyInteraction(
      continueList(view.state.doc, editorSelections()),
      "input.scholium.continueList",
    ),
  },
  {
    key: "Tab",
    run: (view) => {
      if (view.state.selection.ranges.length !== 1) {
        return applyInteraction(indentList(view.state.doc, editorSelections(), false), "input.scholium.indentList");
      }
      return applyInteraction(
        tableTabAction(view.state.doc, view.state.selection.main.head, false)
          ?? indentList(view.state.doc, editorSelections(), false),
        "input.scholium.structuralTab",
      );
    },
  },
  {
    key: "Shift-Tab",
    run: (view) => {
      if (view.state.selection.ranges.length !== 1) {
        return applyInteraction(indentList(view.state.doc, editorSelections(), true), "input.scholium.outdentList");
      }
      return applyInteraction(
        tableTabAction(view.state.doc, view.state.selection.main.head, true)
          ?? indentList(view.state.doc, editorSelections(), true),
        "input.scholium.structuralBackTab",
      );
    },
  },
]);

function revealProjectedBlockForVerticalMove(
  view: EditorView,
  forward: boolean,
  extend: boolean,
) {
  if (configuredEditorMode(view.state) !== "livePreview" || view.composing) return false;
  const selection = view.state.selection.main;
  const moved = view.moveVertically(selection, forward);
  const index = liveProjectionIndexForState(view.state);
  const crossed = rangesIntersecting(
    index.blockRanges,
    Math.min(selection.head, moved.head),
    Math.max(selection.head, moved.head) + 1,
  ).filter((candidate) => {
    if (view.state.selection.ranges.some((range) => selectionIntersectsProjection(range, candidate))) {
      return false;
    }
    return forward
      ? selection.head <= candidate.from && moved.head >= candidate.to
      : selection.head >= candidate.to && moved.head <= candidate.from;
  });
  const projection = forward ? crossed[0] : crossed.at(-1);
  if (!projection) return false;

  const isCallout = projection.kind === "callout";
  const sourceHead = forward
    ? projection.from
    : Math.max(projection.from, projection.to - 1);
  const originalCoords = view.coordsAtPos(selection.head);
  const desiredX = originalCoords?.left ?? originalCoords?.right ?? 0;
  const anchor = extend ? selection.anchor : sourceHead;
  view.dispatch({
    effects: isCallout
      ? setLiveBlockActivationEffect.of({
        kind: "callout",
        from: projection.from,
        to: projection.to,
        edge: forward ? "start" : "end",
      })
      : undefined,
    selection: {anchor, head: sourceHead},
    scrollIntoView: true,
  });
  if (isCallout) {
    view.requestMeasure();
    return true;
  }
  view.requestMeasure({
    read: () => {
      const line = view.state.doc.lineAt(sourceHead);
      const lineEdge = forward ? line.from : line.to;
      const coords = view.coordsAtPos(lineEdge);
      if (!coords) return sourceHead;
      return view.posAtCoords({
        x: desiredX,
        y: (coords.top + coords.bottom) / 2,
      }) ?? sourceHead;
    },
    write: (measuredHead) => {
      if (view.state.selection.main.head !== sourceHead) return;
      view.dispatch({
        selection: {anchor, head: measuredHead},
        scrollIntoView: true,
      });
    },
  });
  return true;
}

function revealProjectedBlockForHorizontalMove(
  view: EditorView,
  forward: boolean,
  extend: boolean,
) {
  if (configuredEditorMode(view.state) !== "livePreview" || view.composing) return false;
  const selection = view.state.selection.main;
  const projection = rangesIntersecting(
    liveProjectionIndexForState(view.state).blockRanges,
    Math.max(0, selection.head - 1),
    selection.head + 1,
  ).find((candidate) =>
    forward ? selection.head === candidate.from : selection.head === candidate.to,
  );
  if (!projection) return false;
  const head = forward ? projection.from : Math.max(projection.from, projection.to - 1);
  view.dispatch({
    selection: {anchor: extend ? selection.anchor : head, head},
    scrollIntoView: true,
  });
  return true;
}

const liveProjectionNavigationKeymap = keymap.of([
  {key: "ArrowDown", run: (view) => revealProjectedBlockForVerticalMove(view, true, false)},
  {key: "Shift-ArrowDown", run: (view) => revealProjectedBlockForVerticalMove(view, true, true)},
  {key: "ArrowUp", run: (view) => revealProjectedBlockForVerticalMove(view, false, false)},
  {key: "Shift-ArrowUp", run: (view) => revealProjectedBlockForVerticalMove(view, false, true)},
  {key: "ArrowRight", run: (view) => revealProjectedBlockForHorizontalMove(view, true, false)},
  {key: "Shift-ArrowRight", run: (view) => revealProjectedBlockForHorizontalMove(view, true, true)},
  {key: "ArrowLeft", run: (view) => revealProjectedBlockForHorizontalMove(view, false, false)},
  {key: "Shift-ArrowLeft", run: (view) => revealProjectedBlockForHorizontalMove(view, false, true)},
]);

/** @param {import("@codemirror/autocomplete").CompletionContext} context */
function wikilinkCompletionSource(context: CompletionContext) {
  const line = context.state.doc.lineAt(context.pos);
  const scanFrom = Math.max(line.from, context.pos - 512);
  const beforeCursor = context.state.doc.sliceString(scanFrom, context.pos);
  const match = /\[\[[^\]\n]*$/.exec(beforeCursor);
  if (!match) return null;
  const typed = match[0].slice(2);
  const from = scanFrom + match.index + 2;
  const requestID = crypto.randomUUID?.()
    ?? `link-${Date.now()}-${nextLinkCompletionRequest++}`;
  const candidates = new Promise<LinkCandidate[]>((resolve) => {
    pendingLinkCompletionQueries.set(requestID, resolve);
    const cancel = () => {
      if (!pendingLinkCompletionQueries.delete(requestID)) return;
      resolve([]);
    };
    context.addEventListener("abort", cancel, {onDocChange: true});
    window.setTimeout(cancel, 3000);
    post({type: "linkCompletionQuery", requestID, query: typed});
  });
  return candidates.then((resolved) => ({
    from,
    options: resolved.slice(0, 100).map((candidate) => ({
      label: candidate.label,
      detail: candidate.detail,
      type: "text",
      apply: candidate.isAmbiguous
        ? () => undefined
        : candidate.insertion + "]]",
    })),
    filter: false,
  }));
}

function resolveLinkCompletionQuery(requestID: string, value: unknown) {
  const resolve = pendingLinkCompletionQueries.get(requestID);
  if (!resolve) return;
  pendingLinkCompletionQueries.delete(requestID);
  const candidates = Array.isArray(value)
    ? value.slice(0, 100).filter((candidate): candidate is LinkCandidate => (
      candidate !== null
      && typeof candidate === "object"
      && typeof candidate.label === "string"
      && typeof candidate.insertion === "string"
      && typeof candidate.detail === "string"
      && typeof candidate.path === "string"
      && typeof candidate.isAmbiguous === "boolean"
    ))
    : [];
  resolve(candidates);
}

/** @param {import("@codemirror/autocomplete").CompletionContext} context */
function calloutCompletionSource(context: CompletionContext) {
  const line = context.state.doc.lineAt(context.pos);
  if (context.pos - line.from > 512) return null;
  const beforeCursor = context.state.doc.sliceString(line.from, context.pos);
  const match = /^(\s*(?:>\s*)+)\[!([A-Za-z-]*)$/.exec(beforeCursor);
  if (!match) return null;
  const typed = match[2].toLocaleLowerCase();
  const dialectCallouts = editingDialect?.callouts ?? [];
  const options = dialectCallouts
    .filter((callout) => !typed || callout.identifier.startsWith(typed))
    .map((callout) => ({
      label: callout.identifier,
      detail: `${callout.label} — ${callout.meaning}`,
      type: "keyword",
      apply: `${callout.identifier}] `,
    }));
  return { from: context.pos - match[2].length, options, filter: false };
}

function applySelectionAction(view: EditorView, command: SelectionActionCommand) {
  const transformed = transformMarkdown(
    view.state.doc.toString(),
    view.state.selection.ranges.map((range) => ({anchor: range.anchor, head: range.head})),
    command,
    {protectedRanges: protectedCommandRanges()},
  );
  if (!transformed) return;
  const transformedSource = applySourceChanges(view.state.doc.toString(), transformed.changes);
  if (new TextEncoder().encode(transformedSource).byteLength > MAX_SOURCE_UTF8_BYTES) return;
  view.dispatch({
    changes: transformed.changes,
    selection: EditorSelection.create(
      transformed.selections.map((range) => EditorSelection.range(range.anchor, range.head)),
    ),
    annotations: Transaction.userEvent.of(`input.scholium.${command}`),
  });
  lastUndoLabel = transformed.undoLabel;
  lastRedoLabel = transformed.undoLabel;
  view.focus();
}

const selectionActions = createSelectionActionsController({
  applyCommand: applySelectionAction,
});

const previewPopover = createPreviewPopoverController({
  previews: () => linkPreviews,
});

// One CodeMirror compartment is the complete presentation-mode boundary.
// Source contains no Live Preview state field, view plugin, widget provider,
// navigation keymap, formatting overlay, preview overlay, or semantic class.
const livePreviewMode = [
  editorModeFacet.of("livePreview"),
  EditorView.editorAttributes.of({class: "scholium-live-mode"}),
  EditorView.contentAttributes.of(editorAccessibilityAttributes("livePreview")),
  liveProjectionIndexField,
  liveSemanticLineField,
  liveSemanticBlockSpacingField,
  liveFrontmatterGuardField,
  liveBlockActivationField,
  liveTableField,
  liveDisplayMathField,
  liveRawHTMLField,
  liveCalloutField,
  liveFootnoteReferenceField,
  livePreview,
  Prec.high(liveInlinePointerPlacement),
  Prec.high(liveProjectionNavigationKeymap),
  selectionActions.extension,
  previewPopover.extension,
  EditorView.lineWrapping,
];
const sourceMode = [
  editorModeFacet.of("source"),
  EditorView.editorAttributes.of({class: "scholium-source-mode"}),
  EditorView.contentAttributes.of(editorAccessibilityAttributes("source")),
  lineNumbers(),
  highlightActiveLineGutter(),
  foldGutter(),
  highlightActiveLine(),
  sourceTextDirection,
  EditorView.lineWrapping,
];

const editorExtensions = [
      highlightSpecialChars(),
      history(),
      drawSelection(),
      dropCursor(),
      EditorState.allowMultipleSelections.of(true),
      indentOnInput(),
      bidiIsolates(),
      bracketMatching(),
      closeBrackets(),
      autocompletion({ override: [calloutCompletionSource, wikilinkCompletionSource] }),
      rectangularSelection(),
      EditorView.perLineTextDirection.of(true),
      scholiumNoteLanguage,
      keymap.of([
        ...closeBracketsKeymap,
        ...defaultKeymap,
        ...historyKeymap,
        ...foldKeymap,
        ...completionKeymap,
      ]),
      structuralInteractionKeymap,
      saveKeymap,
      stateReporter,
      linkActivation,
      lineSeparatorCompartment.of(EditorState.lineSeparator.of("\n")),
      modeCompartment.of(sourceMode),
      EditorView.theme({
        "&": { height: "100%" },
        ".cm-scroller": { overflow: "auto" },
      }),
];
const editor = createMarkdownEditor(document.getElementById("editor")!, editorExtensions);
editor.contentDOM.addEventListener("keydown", () => { pendingKeyStartedAt = performance.now(); }, {capture: true});
const scrollCoordinator = createEditorScrollCoordinator(editor, {
  post: (scrollAnchor) => post({
    type: "scrollChanged",
    scrollFraction: scrollAnchor.fallbackFraction,
    scrollAnchor,
  }),
  onScroll: () => selectionActions.update(editor),
  flushPresentationGeometry: flushPresentationStyleAndGeometry,
});

const allCommands = [
  "bold", "emphasis", "strikethrough", "highlight", "inlineCode",
  "standardLink", "wikilink", "vectorSupports", "vectorOpposes", "vectorIncompatible",
  "paragraph", "heading1", "heading2", "heading3", "heading4", "heading5", "heading6",
  "blockQuotation", "bulletList", "numberedList", "taskList", "fencedCode", "thematicBreak",
  "calloutOrient", "calloutCite", "calloutConnect", "calloutState", "calloutIllustrate", "calloutQuote", "calloutFlag",
  "insertFootnote", "insertTable", "toggleTask", "tableInsertRowBefore", "tableInsertRowAfter", "tableDeleteRow",
  "tableInsertColumnBefore", "tableInsertColumnAfter", "tableDeleteColumn",
  "tableAlignLeft", "tableAlignCenter", "tableAlignRight", "pastePlain", "pasteMarkdown", "linkSelectedText",
] as const;

function editorSelections() {
  return editor.state.selection.ranges.map((range) => ({anchor: range.anchor, head: range.head}));
}

function protectedCommandRanges() {
  return liveProjectionIndexForState(editor.state).commandProtectedRanges;
}

function indexedTablePositionAt(state: EditorState, offset: number) {
  return projectionRangeContaining(
    liveProjectionIndexForState(state).tablePositionRanges,
    offset,
  )?.position;
}

function currentEditorContext(): EditorContext {
  const inline = new Set<string>();
  const block = new Set<string>();
  const selectionLinePrefixes: string[] = [];
  for (const selection of editor.state.selection.ranges) {
    const linePrefix = boundedLinePrefix(editor.state.doc, selection.head);
    selectionLinePrefixes.push(linePrefix);
    for (let node = syntaxTree(editor.state).resolveInner(selection.head, -1); node; node = node.parent!) {
      if (["Emphasis", "StrongEmphasis", "InlineCode", "Link"].includes(node.name)) inline.add(node.name);
      if (["ATXHeading1", "ATXHeading2", "ATXHeading3", "ATXHeading4", "ATXHeading5", "ATXHeading6", "Blockquote", "Callout", "BlockMath", "FootnoteDefinition", "BulletList", "OrderedList", "FencedCode", "Table"].includes(node.name)) block.add(node.name);
      if (!node.parent) break;
    }
    if (calloutHeader(linePrefix)) block.add("Callout");
  }
  const protectedRanges = protectedCommandRanges();
  const protectedSelection = editor.state.selection.ranges.some((selection) =>
    projectionSelectionOverlaps(protectedRanges, selection));
  const currentTablePosition = editor.state.selection.ranges.length === 1
    ? indexedTablePositionAt(editor.state, editor.state.selection.main.head)
    : undefined;
  const tableOnlyCommands = new Set([
    "tableInsertRowBefore", "tableInsertRowAfter", "tableDeleteRow",
    "tableInsertColumnBefore", "tableInsertColumnAfter", "tableDeleteColumn",
    "tableAlignLeft", "tableAlignCenter", "tableAlignRight",
  ]);
  const availableCommands = allCommands.filter((command) => {
    if (tableOnlyCommands.has(command)) return currentTablePosition !== undefined;
    if (command === "toggleTask") {
      return selectionLinePrefixes.every((linePrefix) => /^\s*-\s+\[[ xX]\]/.test(linePrefix));
    }
    if (command === "linkSelectedText") return editor.state.selection.ranges.every((selection) => !selection.empty);
    return true;
  });
  return {
    selections: editorSelections(),
    activeInlineConstructs: [...inline],
    activeBlockConstructs: [...block],
    tablePosition: currentTablePosition,
    composing: editor.composing,
    availableCommands: editor.composing || protectedSelection ? [] : availableCommands,
    undoLabel: undoDepth(editor.state) > 0 ? lastUndoLabel || "Undo Editing" : undefined,
    redoLabel: redoDepth(editor.state) > 0 ? lastRedoLabel || "Redo Editing" : undefined,
  };
}

function scheduleEditorInteractionReport(forceContext = false) {
  forceNextInteractionContext ||= forceContext;
  interactionReporter.schedule(() => {
    const context = currentEditorContext();
    const head = editor.state.selection.main.head;
    const line = editor.state.doc.lineAt(head);
    const availabilitySignature = interactionAvailabilitySignature(context);
    const includeContext = forceNextInteractionContext
      || availabilitySignature !== lastInteractionAvailabilitySignature;
    forceNextInteractionContext = false;
    lastInteractionAvailabilitySignature = availabilitySignature;
    updateEditorAccessibility(editor.contentDOM, configuredEditorMode(editor.state), context);
    post({
      type: "interactionChanged",
      selections: context.selections,
      line: line.number,
      column: head - line.from + 1,
      lineCount: editor.state.doc.lines,
      ...(includeContext ? {context} : {}),
    });
  });
}

function publishEditorContext() {
  scheduleEditorInteractionReport(true);
}

function successfulResult(requestID: string, sourceChanged = false, undoLabel?: string): EditorCommandResult {
  return {
    requestID,
    resultingGeneration: documentVersion,
    sourceChanged,
    selections: editorSelections(),
    undoLabel,
    text: sourceChanged ? exactEditorSource() : undefined,
    context: currentEditorContext(),
    accepted: true,
  };
}

async function executeEditorRequest(request: EditorRequest): Promise<EditorCommandResult> {
  const operation = request.operation;
  if (operation.type === "initialize") {
    const loadStartedAt = performance.now();
    if (request.expectedGeneration !== 0
        || new TextEncoder().encode(operation.text).byteLength > MAX_SOURCE_UTF8_BYTES) {
      return rejected(request.requestID, documentVersion, "invalid initialization");
    }
    bridgeSessionID = request.sessionID;
    bridgeDocumentID = request.documentID;
    bridgeFingerprint = request.startingFingerprint;
    editingDialect = operation.dialect;
    editorOperations.setDocument(
      operation.text, request.sessionID, request.documentID, request.startingFingerprint,
    );
    await editorOperations.setMode(operation.mode);
    recordEditorMetric("document-load", loadStartedAt, {documentLength: editor.state.doc.length});
    sampleEditorMemory(editor.state.doc.length);
    return successfulResult(request.requestID);
  }
  if (request.sessionID !== bridgeSessionID || request.documentID !== bridgeDocumentID
      || request.startingFingerprint !== bridgeFingerprint) {
    return rejected(request.requestID, documentVersion, "stale editor identity");
  }
  if (request.expectedGeneration !== documentVersion) {
    return rejected(request.requestID, documentVersion, "stale editor generation");
  }

  switch (operation.type) {
  case "setMode": await editorOperations.setMode(operation.mode); break;
  case "setPresentationCSS": editorOperations.setPresentationCSS(operation.value); break;
  case "setUserCSS": editorOperations.setUserCSS(operation.value); break;
  case "setLinkPreviews": editorOperations.setLinkPreviews(operation.value); break;
  case "showPreview": previewPopover.showAtSelection(); break;
  case "showPreviewAt": previewPopover.showAtPoint(operation.x, operation.y); break;
  case "announceStatus": announceEditorMessage(editor.contentDOM, operation.value); break;
  case "goToLine": editorOperations.goToLine(operation.line); break;
  case "revealSourceRange": editorOperations.revealSourceRange(operation.fromUTF16, operation.toUTF16); break;
  case "setScrollFraction": editorOperations.setScrollFraction(operation.fraction); break;
  case "setScrollAnchor": editorOperations.setScrollAnchor(operation.anchor); break;
  case "queryText": return {...successfulResult(request.requestID), text: exactEditorSource()};
  case "querySelection": {
    const snapshot = {documentID: bridgeDocumentID, fingerprint: bridgeFingerprint, generation: documentVersion, ranges: editorSelections()};
    return {...successfulResult(request.requestID), selection: snapshot};
  }
  case "queryContext": return {...successfulResult(request.requestID), context: currentEditorContext()};
  case "queryScrollAnchor": return {
    ...successfulResult(request.requestID),
    scrollAnchor: scrollCoordinator.currentAnchor(),
  };
  case "queryPerformance": return {
    ...successfulResult(request.requestID),
    performanceSamples: editorPerformanceSamples(),
  };
  case "captureRecovery": {
    let stateJSON: string | undefined;
    try {
      const candidate = JSON.stringify(editor.state.toJSON({history: historyField}));
      if (new TextEncoder().encode(candidate).byteLength <= MAX_INBOUND_BYTES) stateJSON = candidate;
    } catch { stateJSON = undefined; }
    const recovery: RecoverySnapshot = {
      documentID: bridgeDocumentID,
      fingerprint: bridgeFingerprint,
      generation: documentVersion,
      ranges: editorSelections(),
      source: exactEditorSource(),
      stateJSON,
      undoHistoryPreserved: stateJSON !== undefined,
      dirty,
    };
    return {...successfulResult(request.requestID), recovery};
  }
  case "restoreRecovery": {
    const snapshot = operation.snapshot;
    if (snapshot.documentID !== bridgeDocumentID || snapshot.fingerprint !== bridgeFingerprint
        || !recoveryGenerationCanReplaceCurrent(snapshot.generation, documentVersion)
        || new TextEncoder().encode(snapshot.source).byteLength > MAX_SOURCE_UTF8_BYTES) {
      return rejected(request.requestID, documentVersion, "stale recovery snapshot");
    }
    const recoveredSelection = EditorSelection.create(snapshot.ranges.map((range) =>
      EditorSelection.range(range.anchor, range.head)));
    const separator = snapshot.source.includes("\r\n") ? "\r\n" : "\n";
    let restoredHistory = false;
    let recoveredState: EditorState | null = null;
    if (snapshot.stateJSON && new TextEncoder().encode(snapshot.stateJSON).byteLength <= MAX_INBOUND_BYTES) {
      try {
        const serializedState = JSON.parse(snapshot.stateJSON);
        if (serializedState && typeof serializedState.doc === "string") {
          // CodeMirror history offsets are expressed in its normalized LF
          // coordinate space. The state serializer follows the configured
          // presentation separator, so normalize only this disposable state
          // document before reconstruction; the exact-source mirror remains untouched.
          serializedState.doc = normalizedDocumentText(serializedState.doc);
        }
        const restored = EditorState.fromJSON(
          serializedState,
          {extensions: editorExtensions},
          {history: historyField},
        );
        if (normalizedDocumentText(restored.doc.toString())
            === normalizedDocumentText(snapshot.source)) {
          recoveredState = restored.update({
            selection: recoveredSelection,
            effects: lineSeparatorCompartment.reconfigure(EditorState.lineSeparator.of(separator)),
            annotations: Transaction.addToHistory.of(false),
          }).state;
          restoredHistory = true;
        }
      } catch { restoredHistory = false; }
    }
    if (!recoveredState) {
      try {
        recoveredState = editor.state.update({
        changes: replacementChange(editor.state.doc.toString(), snapshot.source),
        selection: recoveredSelection,
        effects: lineSeparatorCompartment.reconfigure(EditorState.lineSeparator.of(separator)),
        annotations: [Transaction.addToHistory.of(false), programmaticDocumentChange.of(true)],
        }).state;
      } catch {
        return rejected(request.requestID, documentVersion, "invalid recovery snapshot");
      }
    }
    // Source, history, line separator, and the latest exact selection become
    // visible together. No partially restored state can escape a failed
    // stateJSON or selection validation path.
    const restoredMode = configuredEditorMode(editor.state);
    editor.setState(recoveredState);
    exactSourceMirror.replace(snapshot.source);
    await editorOperations.setMode(restoredMode);
    dirty = snapshot.dirty;
    documentVersion = snapshot.generation;
    return {...successfulResult(request.requestID), recovery: {...snapshot, undoHistoryPreserved: restoredHistory}};
  }
  case "synchronizeCommittedText": {
    if (new TextEncoder().encode(operation.committedText).byteLength > MAX_SOURCE_UTF8_BYTES) {
      return rejected(request.requestID, documentVersion, "committed source is too large");
    }
    const accepted = editorOperations.synchronizeCommittedText(
      operation.expectedText, operation.committedText, operation.committedFingerprint,
    );
    return accepted ? successfulResult(request.requestID) : rejected(request.requestID, documentVersion, "editor source did not reconcile");
  }
  case "command": {
    const argument = operation.command === "pasteMarkdown"
      ? pasteAsMarkdown(decodeClipboardPayload(operation.argument))
      : operation.argument;
    const transformed = transformMarkdown(editor.state.doc.toString(), editorSelections(), operation.command, {
      argument,
      protectedRanges: protectedCommandRanges(),
    });
    if (!transformed) return rejected(request.requestID, documentVersion, "command is unavailable for the exact selection");
    const transformedSource = applySourceChanges(editor.state.doc.toString(), transformed.changes);
    if (new TextEncoder().encode(transformedSource).byteLength > MAX_SOURCE_UTF8_BYTES) {
      return rejected(request.requestID, documentVersion, "command result is too large");
    }
    editor.dispatch({
      changes: transformed.changes,
      selection: EditorSelection.create(transformed.selections.map((range) => EditorSelection.range(range.anchor, range.head))),
      annotations: Transaction.userEvent.of(`input.scholium.${operation.command}`),
    });
    lastUndoLabel = transformed.undoLabel;
    lastRedoLabel = transformed.undoLabel;
    return successfulResult(request.requestID, true, transformed.undoLabel);
  }
  case "markClean": editorOperations.markClean(); break;
  case "focus": editorOperations.focus(); break;
  case "blur": editorOperations.blur(); break;
  }
  return successfulResult(request.requestID);
}

const compositionGate = new CompositionRequestGate<EditorRequest, EditorCommandResult>();
async function dispatchEditorRequest(value: unknown): Promise<EditorCommandResult> {
  const bridgeStartedAt = performance.now();
  const requestBytes = (() => { try { return encodedByteLength(value); } catch { return 0; } })();
  if (!isEditorRequest(value)) {
    recordEditorMetric("bridge-request", bridgeStartedAt, {requestBytes});
    return rejected("invalid", documentVersion, "malformed editor request");
  }
  const compositionPolicy = compositionRequestPolicy(value.operation.type);
  if ((editor.composing || compositionGate.active) && compositionPolicy === "reject") {
    return rejected(value.requestID, documentVersion, "editor identity cannot change during composition");
  }
  if ((editor.composing || compositionGate.active) && compositionPolicy === "defer") {
    const result = compositionGate.enqueue(value);
    return result.then((accepted) => {
      recordEditorMetric("bridge-request", bridgeStartedAt, {
        requestBytes,
        resultBytes: encodedByteLength(accepted),
      });
      return accepted;
    });
  }
  try {
    const result = await executeEditorRequest(value);
    recordEditorMetric("bridge-request", bridgeStartedAt, {requestBytes, resultBytes: encodedByteLength(result)});
    return result;
  } catch (error) {
    const result = rejected(
      value.requestID,
      documentVersion,
      error instanceof Error ? error.message : "editor request failed",
    );
    recordEditorMetric("bridge-request", bridgeStartedAt, {requestBytes, resultBytes: encodedByteLength(result)});
    return result;
  }
}
editor.contentDOM.addEventListener("compositionend", () => {
  // WebKit may deliver the final input/change notification after
  // compositionend. A task boundary lets CodeMirror publish that delta and
  // advance the generation before queued native mutations are validated.
  window.setTimeout(() => {
    const pending = compositionGate.finish();
    for (const item of pending) void dispatchEditorRequest(item.request).then(item.resolve);
    publishEditorContext();
  }, 0);
});
editor.contentDOM.addEventListener("compositionstart", () => {
  compositionGate.begin();
  window.queueMicrotask(publishEditorContext);
});

function pasteTransfer(transfer: DataTransfer, dropPosition?: number) {
  if (Array.from(transfer.files).length > 0
      || Array.from(transfer.items).some((item) => item.kind === "file")) {
    post({type: "failure", message: unsupportedFilePasteMessage});
    announceEditorMessage(editor.contentDOM, unsupportedFilePasteMessage);
    return true;
  }
  const text = transfer.getData("text/plain");
  if (!text) return false;
  if (dropPosition !== undefined) editor.dispatch({selection: {anchor: dropPosition}});
  const url = isSingleSafeURL(text);
  const command = url && editor.state.selection.ranges.every((selection) => !selection.empty)
    ? "linkSelectedText"
    : "pastePlain";
  const transformed = transformMarkdown(editor.state.doc.toString(), editorSelections(), command, {
    argument: url ?? text,
    protectedRanges: protectedCommandRanges(),
  });
  return applyInteraction(transformed, command === "linkSelectedText" ? "input.scholium.linkPaste" : "input.scholium.plainPaste");
}

editor.contentDOM.addEventListener("paste", (event) => {
  if (!event.clipboardData) return;
  if (pasteTransfer(event.clipboardData)) event.preventDefault();
}, {capture: true});
editor.contentDOM.addEventListener("drop", (event) => {
  if (!event.dataTransfer) return;
  const position = editor.posAtCoords({x: event.clientX, y: event.clientY});
  if (pasteTransfer(event.dataTransfer, position ?? undefined)) event.preventDefault();
}, {capture: true});

function setDynamicStyle(id: string, css: string) {
  const style = document.getElementById(id);
  if (!style || style.textContent === css) return;
  style.textContent = css;
  scrollCoordinator.scheduleGeometryReport();
  void document.fonts.ready.then(scrollCoordinator.scheduleGeometryReport);
}

function flushPresentationStyleAndGeometry() {
  // Native keeps a newly created editor hidden until the final presentation
  // request is acknowledged. WebKit can otherwise defer style invalidation on
  // that hidden page and briefly expose body-sized headings when SwiftUI makes
  // the surface visible. Resolve the cascade and representative geometry in
  // this final bridge turn; no animation frame or second state owner is needed.
  for (const selector of [
    ".cm-content",
    ".cm-live-h1",
    ".cm-live-h2",
    ".cm-live-callout-widget",
    ".cm-live-list",
  ]) {
    const element = document.querySelector<HTMLElement>(selector);
    if (!element) continue;
    void getComputedStyle(element).fontSize;
    void element.getBoundingClientRect().width;
  }
}

/**
 * A native mode acknowledgement is also the presentation readiness boundary.
 * On a newly constructed Review -> Edit surface, the document transaction can
 * precede CodeMirror's first real viewport and background syntax publication.
 * Source -> Edit happened to mask that race because reconfiguration occurred
 * after layout. Advance a bounded leading/visible parse window and explicitly
 * refresh the projection before acknowledging the command. Native style and
 * scroll convergence then provide additional bridge turns before Swift reveals
 * a freshly constructed editor, without making the bridge depend on animation
 * frames that WebKit is allowed to suspend while the view is hidden.
 */
function convergeLivePreviewProjection() {
  if (configuredEditorMode(editor.state) !== "livePreview") return;
  const visibleTo = editor.visibleRanges.reduce(
    (maximum, range) => Math.max(maximum, range.to),
    editor.viewport.to,
  );
  const leadingWindowTo = Math.min(editor.state.doc.length, 8_000);
  const parseTo = Math.min(editor.state.doc.length, Math.max(leadingWindowTo, visibleTo + 2_000));
  forceParsing(editor, parseTo, 12);
  editor.dispatch({effects: refreshLivePreviewEffect.of(null)});
}

const editorOperations = {
  /** @param {string} text @param {string} sessionID @param {string} documentID */
  setDocument(text: string, sessionID: string, documentID: string, startingFingerprint: string) {
    previewPopover.hide();
    compositionGate.rejectAll((pending) => rejected(
      pending.requestID,
      documentVersion,
      "editor identity changed during composition",
    ));
    bridgeSessionID = sessionID;
    bridgeDocumentID = documentID;
    bridgeFingerprint = startingFingerprint;
    documentVersion = 0;
    hiddenFrontmatterSourceSelection = null;
    const separator = text.includes("\r\n") ? "\r\n" : "\n";
    exactSourceMirror.replace(text);
    editor.dispatch({
      changes: replacementChange(editor.state.doc.toString(), text),
      effects: lineSeparatorCompartment.reconfigure(EditorState.lineSeparator.of(separator)),
      annotations: [
        Transaction.addToHistory.of(false),
        programmaticDocumentChange.of(true),
      ],
    });
    dirty = false;
    lastInteractionAvailabilitySignature = null;
    scheduleEditorInteractionReport(true);
  },

  /** @param {string} mode */
  async setMode(mode: string) {
    const startedAt = performance.now();
    const transitionSequence = ++modeTransitionSequence;
    previewPopover.hide();
    const scrollSnapshot = editor.scrollSnapshot();
    const nextMode = mode === "livePreview" ? "livePreview" : "source";
    const previousMode = configuredEditorMode(editor.state);
    let selection: EditorSelection | undefined;
    if (nextMode === "livePreview") {
      const bodyFrom = frontmatterBodyOffset(editor.state.doc);
      if (bodyFrom > 0 && editor.state.selection.ranges.some((range) => range.from < bodyFrom)) {
        if (previousMode === "source") {
          const clampedLiveSelection = EditorSelection.create([
            EditorSelection.cursor(bodyFrom),
          ]);
          hiddenFrontmatterSourceSelection = {
            documentVersion,
            sourceSelection: editor.state.selection,
            clampedLiveSelection,
          };
          selection = clampedLiveSelection;
        } else {
          selection = EditorSelection.create([EditorSelection.cursor(bodyFrom)]);
        }
      }
    } else if (nextMode === "source" && previousMode === "livePreview"
        && hiddenFrontmatterSourceSelection?.documentVersion === documentVersion) {
      selection = hiddenFrontmatterSourceSelection.sourceSelection;
      hiddenFrontmatterSourceSelection = null;
    }
    editor.dispatch({
      selection,
      effects: [
        modeCompartment.reconfigure(nextMode === "livePreview" ? livePreviewMode : sourceMode),
        scrollSnapshot,
      ],
    });
    const appliedMode = configuredEditorMode(editor.state);
    selectionActions.update(editor);
    updateEditorAccessibility(editor.contentDOM, appliedMode, currentEditorContext());
    scheduleEditorInteractionReport(true);
    recordEditorMetric("mode-toggle-work", startedAt, {
      documentLength: editor.state.doc.length,
      transitionSequence,
    });
    editor.requestMeasure({
      read: () => editor.state.doc.length,
      write: (documentLength) => window.requestAnimationFrame(() => recordEditorMetric(
        "mode-toggle",
        startedAt,
        {documentLength, transitionSequence},
      )),
    });
    window.setTimeout(scrollCoordinator.postCurrent, 0);
    if (appliedMode === "livePreview") convergeLivePreviewProjection();
    // The typed response is the native visibility boundary. Ensure the
    // compartment, semantic projection, cascade, and representative geometry
    // belong to the same completed configuration before acknowledging it.
    flushPresentationStyleAndGeometry();
  },

  /** @param {string} css */
  setPresentationCSS(css: string) {
    setDynamicStyle("scholium-presentation-css", css);
  },

  /** @param {string} css */
  setUserCSS(css: string) {
    setDynamicStyle("scholium-user-css", css);
  },

  setLinkPreviews(value: unknown) {
    linkPreviews = validatedLinkPreviews(value, editor.state.doc.length);
    linkPreviewIndexByRange = new Map(
      linkPreviews.map((preview, index) => [rangeKey(preview.from, preview.to), index]),
    );
    if (configuredEditorMode(editor.state) === "livePreview") {
      editor.dispatch({effects: refreshLivePreviewEffect.of(null)});
    }
  },

  /** @param {number} requestedLine */
  goToLine(requestedLine: number) {
    const lineNumber = Math.max(1, Math.min(Math.trunc(requestedLine), editor.state.doc.lines));
    const line = editor.state.doc.line(lineNumber);
    editor.dispatch({
      selection: { anchor: line.from },
      effects: EditorView.scrollIntoView(line.from, { y: "center" }),
    });
    editor.focus();
  },

  /** Selects an exact source range without changing Markdown or undo history. */
  revealSourceRange(requestedFromUTF16: number, requestedToUTF16: number) {
    const documentLength = editor.state.doc.length;
    const from = Math.max(0, Math.min(Math.trunc(requestedFromUTF16), documentLength));
    const to = Math.max(from, Math.min(Math.trunc(requestedToUTF16), documentLength));
    editor.dispatch({
      selection: EditorSelection.single(from, to),
      effects: EditorView.scrollIntoView(EditorSelection.range(from, to), {y: "center"}),
      annotations: Transaction.addToHistory.of(false),
    });
    editor.focus();
  },

  setScrollFraction(requestedFraction: number) {
    // Scroll restoration is the final independent bridge turn before native
    // reveals a newly created editor. Resolve presentation CSS and projected
    // line geometry here so its acknowledgement is a real visibility barrier.
    scrollCoordinator.setFraction(requestedFraction);
  },

  setScrollAnchor(anchor: EditorScrollAnchor) {
    scrollCoordinator.setAnchor(anchor);
  },

  synchronizeCommittedText(expectedText: string, committedText: string, startingFingerprint: string) {
    if (exactSourceMirror.text !== expectedText
        || normalizedDocumentText(editor.state.doc.toString())
            !== normalizedDocumentText(expectedText)) return false;

    bridgeFingerprint = startingFingerprint;
    const separator = committedText.includes("\r\n") ? "\r\n" : "\n";
    editor.dispatch({
      changes: replacementChange(editor.state.doc.toString(), committedText),
      effects: lineSeparatorCompartment.reconfigure(EditorState.lineSeparator.of(separator)),
      annotations: [
        Transaction.addToHistory.of(false),
        programmaticDocumentChange.of(true),
      ],
    });
    exactSourceMirror.replace(committedText);
    dirty = false;
    scheduleEditorInteractionReport(true);
    return true;
  },

  markClean() {
    dirty = false;
  },

  focus() {
    editor.focus();
  },

  blur() {
    previewPopover.hide();
    editor.contentDOM.blur();
  },
};

webkitWindow.scholiumEditor = {
  dispatch: dispatchEditorRequest,
  resolveLinkCompletionQuery,
};

recordEditorMetric("startup", editorStartupStartedAt, {documentLength: editor.state.doc.length});
post({ type: "ready" });
