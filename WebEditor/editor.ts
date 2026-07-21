import {
  Annotation,
  Compartment,
  EditorSelection,
  EditorState,
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
  bracketMatching,
  defaultHighlightStyle,
  foldGutter,
  HighlightStyle,
  foldKeymap,
  indentOnInput,
  syntaxTree,
  syntaxHighlighting,
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
import {highlightSelectionMatches} from "@codemirror/search";
import {
  EDITOR_PROTOCOL_VERSION,
  MAX_INBOUND_BYTES,
  MAX_SOURCE_UTF8_BYTES,
  type EditorCommandResult,
  type EditorContext,
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
  type FootnoteDefinitionPresentation,
  type FootnotePresentation,
  type FootnoteReferencePresentation,
} from "./footnote-presentation";
import {decodeClipboardPayload, isSingleSafeURL, pasteAsMarkdown} from "./clipboard";
import {linkTargetAt} from "./projection";
import {scholiumNoteLanguage} from "./language";
import {
  boundedProjectionRanges,
  boundedLinePrefix,
  rangeKey,
  semanticProjectionRanges,
} from "./semantic-projection";
import {
  activeProjectionSignature,
  selectionAffectedProjectionRanges,
  selectionIntersectsProjection,
  transactionCanMapProjection,
  transactionChangedSyntaxTree,
  transactionMayCreateProjection,
  type ProjectionSourceRange,
} from "./projection-update";
import {
  applyNormalizedChangesToExactSource,
  frontmatterBodyOffset,
  frontmatterBoundary,
  normalizedDocumentText,
  replacementChange,
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
import {
  footnotePreviewContent,
  footnoteReferenceAt,
  validatedLinkPreviews,
  type LinkPreview,
  type VectorLinkKind,
} from "./previews";

const editorStartupStartedAt = performance.now();

interface ScholiumWindow extends Window {
  webkit?: { messageHandlers?: { scholium?: { postMessage(message: unknown): void } } };
  scholiumEditor?: ScholiumEditorAPI;
}
interface LinkCandidate { label: string; insertion: string; detail: string; path: string; isAmbiguous: boolean }
interface ResearcherCommentAnnotation { id: string; from: number; to: number; comment: string; resolved: boolean }
interface SourceDelta { from: number; to: number; insert: string }
interface WikilinkPresentation { displayStart: number; displayEnd: number; isLegacyRelationship: boolean }
interface SemanticCodeBlockRange extends ProjectionSourceRange { readonly fenced: boolean }
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
  readonly kind: "table" | "callout" | "footnote";
}
interface IndexedTablePositionRange extends ProjectionSourceRange {
  readonly position: {row: number; column: number; rowCount: number; columnCount: number};
}
interface LiveProjectionIndex {
  readonly literals: SemanticLiteralRanges;
  readonly footnotes: FootnotePresentation;
  readonly tables: readonly TablePresentation[];
  readonly callouts: readonly CalloutPresentation[];
  readonly frontmatterRange: Readonly<ProjectionSourceRange> | null;
  readonly commandProtectedRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly structuralRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly blockRanges: readonly Readonly<LiveBlockProjectionRange>[];
  readonly footnoteRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly tablePositionRanges: readonly Readonly<IndexedTablePositionRange>[];
  readonly hasUnclosedFrontmatter: boolean;
  readonly firstBodyLineFrom: number;
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
let exactSource = "";
let linkCandidates: LinkCandidate[] = [];
let nextLinkCompletionRequest = 0;
const pendingLinkCompletionQueries = new Map<
  string,
  (candidates: LinkCandidate[]) => void
>();
let linkPreviews: LinkPreview[] = [];
let linkPreviewIndexByRange = new Map<string, number>();
let editingDialect: MarkdownEditingDialect | null = null;
let currentMode: "livePreview" | "source" = "livePreview";
let hiddenFrontmatterSourceSelection: {
  documentVersion: number;
  selection: EditorSelection;
} | null = null;
const liveWidgetReuseCounts = {table: 0, callout: 0, footnote: 0};
let selectedFootnotePreviewTarget: {
  identifier: string;
  from: number;
  rect: {left: number; right: number; top: number; bottom: number};
} | null = null;
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
  return exactSource;
}

const modeCompartment = new Compartment();
const lineSeparatorCompartment = new Compartment();
const programmaticDocumentChange = Annotation.define<boolean>();
const refreshLivePreviewEffect = StateEffect.define<null>();
const livePreviewHighlightStyle = HighlightStyle.define([]);

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
});
const setResearcherCommentsEffect = StateEffect.define<ResearcherCommentAnnotation[]>();
const researcherCommentField = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(value, transaction) {
    let next = value.map(transaction.changes);
    for (const effect of transaction.effects) {
      if (!effect.is(setResearcherCommentsEffect)) continue;
      const ranges: Range<Decoration>[] = effect.value
        .filter((comment) => comment.from >= 0
          && comment.to > comment.from
          && comment.to <= transaction.newDoc.length)
        .map((comment) => Decoration.mark({
          class: `cm-researcher-comment${comment.resolved ? " cm-researcher-comment-resolved" : ""}`,
          attributes: {
            "data-comment-id": comment.id,
            "data-scholium-protected": "researcher-comment",
            "aria-label": `Researcher comment: ${comment.comment}`,
            title: `Researcher comment: ${comment.comment}`,
          },
        }).range(comment.from, comment.to));
      next = Decoration.set(ranges, true);
    }
    return next;
  },
  provide: (field) => EditorView.decorations.from(field),
});

const hiddenSyntax = Decoration.replace({});
const liveMark = (className: string) => Decoration.mark({ class: className });

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
  constructor(marker: string) { super(); this.marker = marker; }
  eq(other: ListMarkerWidget) { return other.marker === this.marker; }
  toDOM() {
    const span = document.createElement("span");
    span.className = "cm-live-list-marker";
    span.textContent = /^\d/.test(this.marker) ? this.marker : "•";
    span.setAttribute("aria-hidden", "true");
    return span;
  }
  ignoreEvent() { return true; }
}

const vectorLinkSemantics: Record<VectorLinkKind, {label: string; symbol: string}> = {
  neutral: { label: "Related note", symbol: "link" },
  supports_target: { label: "Supports", symbol: "arrow.right.circle" },
  supported_by_target: { label: "Supported by", symbol: "arrow.left.circle" },
  incompatible: { label: "Incompatible with", symbol: "xmark.circle" },
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
    span.dataset.symbol = semantics.symbol;
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
      element.innerHTML = rendered.html;
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
    return element;
  }

  // A click places the caret at the replacement boundary so the exact source
  // construct is revealed on the next projection update.
  ignoreEvent() { return false; }
}

function isEscapedAt(text: string, index: number): boolean {
  let backslashes = 0;
  for (let cursor = index - 1; cursor >= 0 && text[cursor] === "\\"; cursor -= 1) {
    backslashes += 1;
  }
  return backslashes % 2 === 1;
}

function vectorLinkKindAt(text: string, wikiIndex: number): VectorLinkKind {
  const markerIndex = wikiIndex - 1;
  if (markerIndex < 0 || isEscapedAt(text, markerIndex)) return "neutral";
  const marker = text[markerIndex];
  const kind = editingDialect?.vectorLinkOperators.find((candidate) => candidate.marker === marker)?.kind;
  if (!kind) return "neutral";
  if (markerIndex === 0) return kind;
  const previous = text[markerIndex - 1];
  if (/\p{L}|\p{N}/u.test(previous) || ["_", "\\", "!", "+", "-", "?"].includes(previous)) {
    return "neutral";
  }
  return kind;
}

function isIndentedCodeLine(text: string): boolean {
  // A tab in the first four columns reaches a CommonMark code indentation
  // stop. Four or more literal spaces are the equivalent source form.
  return /^(?: {4,}| {0,3}\t)/.test(text);
}

function isFencedDelimiterLine(doc: Text, block: SemanticCodeBlockRange, lineFrom: number) {
  if (!block.fenced) return false;
  const openingLine = doc.lineAt(block.from);
  if (lineFrom === openingLine.from) return true;
  const closingLine = doc.lineAt(Math.max(block.from, block.to - 1));
  if (lineFrom !== closingLine.from) return false;
  const opening = /^ {0,3}(`{3,}|~{3,})/.exec(openingLine.text)?.[1];
  const closing = /^ {0,3}(`+|~+)[ \t]*$/.exec(closingLine.text)?.[1];
  return Boolean(opening && closing
    && opening[0] === closing[0]
    && closing.length >= opening.length);
}

const legacyRelationshipPredicates = new Set([
  "supports", "contradicts", "extends", "refines", "questions", "incompatible_with",
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
  excluded: readonly ProjectionSourceRange[],
  codeBlocks: readonly SemanticCodeBlockRange[],
  footnotes: FootnotePresentation,
  tables: readonly TablePresentation[],
  callouts: readonly CalloutPresentation[],
  frontmatterRange: ProjectionSourceRange | null,
  hasUnclosedFrontmatter: boolean,
  firstBodyLineFrom: number,
): LiveProjectionIndex {
  const immutableExcluded = immutableProjectionRanges(excluded);
  const immutableCodeBlocks = immutableProjectionRanges(codeBlocks);
  const immutableFrontmatter = frontmatterRange === null
    ? null
    : Object.freeze({...frontmatterRange});
  const immutableTables = Object.freeze([...tables]);
  const immutableCallouts = Object.freeze([...callouts]);
  const footnoteRanges = immutableProjectionRanges([
    ...footnotes.definitions,
    ...footnotes.references,
  ].map(({from, to}) => ({from, to})));
  return Object.freeze({
    literals: Object.freeze({
      excluded: immutableExcluded,
      codeBlocks: immutableCodeBlocks,
    }),
    footnotes,
    tables: immutableTables,
    callouts: immutableCallouts,
    frontmatterRange: immutableFrontmatter,
    commandProtectedRanges: commandProtectionRanges(
      immutableExcluded,
      immutableFrontmatter ?? undefined,
    ),
    structuralRanges: immutableProjectionRanges([
      ...immutableTables,
      ...immutableCallouts,
      ...footnotes.definitions,
      ...footnotes.references,
    ].map(({from, to}) => ({from, to}))),
    blockRanges: immutableProjectionRanges([
      ...immutableTables.map(({from, to}) => ({from, to, kind: "table" as const})),
      ...immutableCallouts.map(({from, to}) => ({from, to, kind: "callout" as const})),
      ...footnotes.definitions.flatMap(({from, to, isInline}) =>
        isInline ? [] : [{from, to, kind: "footnote" as const}]),
    ]),
    footnoteRanges,
    tablePositionRanges: indexedTablePositionRanges(doc, immutableTables),
    hasUnclosedFrontmatter,
    firstBodyLineFrom,
  });
}

function buildLiveProjectionIndex(state: EditorState): LiveProjectionIndex {
  const startedAt = performance.now();
  const excluded: {from: number; to: number}[] = [];
  const codeBlocks: SemanticCodeBlockRange[] = [];
  const definitionRanges = new Set<string>();
  const referenceRanges = new Set<string>();
  const tableRanges: ProjectionSourceRange[] = [];
  const calloutRanges: ProjectionSourceRange[] = [];
  syntaxTree(state).iterate({
    enter(node) {
      const key = rangeKey(node.from, node.to);
      if (node.name === "FootnoteDefinition") definitionRanges.add(key);
      if (node.name === "FootnoteReference") referenceRanges.add(key);
      if (node.name === "InlineFootnote") {
        definitionRanges.add(key);
        referenceRanges.add(key);
      }
      if (node.name === "Table") {
        tableRanges.push({from: node.from, to: node.to});
        return false;
      }
      if (node.name === "Callout") {
        calloutRanges.push({from: node.from, to: node.to});
        return false;
      }
      if (node.name === "FencedCode" || node.name === "CodeBlock") {
        const range = { from: node.from, to: node.to };
        excluded.push(range);
        codeBlocks.push({...range, fenced: node.name === "FencedCode"});
        return false;
      }
      // These are the CodeMirror counterparts of the Swift Markdown literal
      // nodes excluded by MarkdownSemanticDocument. Obsidian %% comments are
      // added separately because the CommonMark grammar does not name them.
      if ([
        "InlineCode", "HTMLBlock", "HTMLTag", "CommentBlock", "Comment",
        "ObsidianComment", "UnclosedObsidianComment",
        "ObsidianCommentBlock", "UnclosedObsidianCommentBlock",
      ].includes(node.name)) {
        excluded.push({ from: node.from, to: node.to });
        return false;
      }
      return undefined;
    },
  });
  const yamlBoundary = frontmatterBoundary(state.doc);
  const yamlBodyFrom = yamlBoundary.endLine === 0
    ? 0
    : yamlBoundary.endLine < state.doc.lines
      ? state.doc.line(yamlBoundary.endLine + 1).from
      : state.doc.line(yamlBoundary.endLine).to;
  const frontmatterRange = yamlBodyFrom > 0 ? {from: 0, to: yamlBodyFrom} : null;
  const footnoteExcluded = [...excluded];
  if (frontmatterRange) footnoteExcluded.push(frontmatterRange);
  const projectedFootnotes = footnotePresentation(
    state.doc.toString(),
    footnoteExcluded,
    editingDialect?.footnotes,
  );
  const footnotes: FootnotePresentation = {
    definitions: projectedFootnotes.definitions.filter((definition) =>
      definitionRanges.has(rangeKey(definition.from, definition.to))),
    references: projectedFootnotes.references.filter((reference) =>
      referenceRanges.has(rangeKey(reference.from, reference.to))),
  };
  const insideNamedDefinition = (range: ProjectionSourceRange) => footnotes.definitions.some(
    (definition) => !definition.isInline
      && definition.from <= range.from && definition.to >= range.to,
  );
  const source = state.doc.toString();
  const tables = tableRanges.flatMap((range): TablePresentation[] => {
    if (insideNamedDefinition(range)) return [];
    const presentation = tablePresentation(source, range.from, range.to);
    return presentation ? [presentation] : [];
  });
  const callouts = calloutRanges.flatMap((range): CalloutPresentation[] => {
    if (insideNamedDefinition(range)) return [];
    return [{...range, source: state.doc.sliceString(range.from, range.to)}];
  });
  const index = finalizedLiveProjectionIndex(
    state.doc,
    excluded,
    codeBlocks,
    footnotes,
    tables,
    callouts,
    frontmatterRange,
    yamlBoundary.unclosed,
    firstSemanticBodyLineFrom(state.doc, yamlBodyFrom),
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
  let recomputeFirstBody = false;
  transaction.changes.iterChanges((fromA) => {
    if (fromA <= index.firstBodyLineFrom) recomputeFirstBody = true;
  });
  const footnotes: FootnotePresentation = {
      definitions: index.footnotes.definitions.map((definition) => ({
        ...definition,
        from: map(definition.from),
        to: map(definition.to),
      })),
      references: index.footnotes.references.map((reference) => ({
        ...reference,
        from: map(reference.from),
        to: map(reference.to),
        definitionFrom: reference.definitionFrom === null ? null : map(reference.definitionFrom),
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
  const frontmatterRange = index.frontmatterRange === null ? null : {
    from: map(index.frontmatterRange.from),
    to: map(index.frontmatterRange.to),
  };
  return finalizedLiveProjectionIndex(
    transaction.state.doc,
    index.literals.excluded.map((range) => ({from: map(range.from), to: map(range.to)})),
    index.literals.codeBlocks.map((range) => ({
      from: map(range.from),
      to: map(range.to),
      fenced: range.fenced,
    })),
    footnotes,
    tables,
    callouts,
    frontmatterRange,
    index.hasUnclosedFrontmatter,
    recomputeFirstBody
      ? firstSemanticBodyLineFrom(transaction.state.doc, frontmatterRange?.to ?? 0)
      : map(index.firstBodyLineFrom),
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
    const indexedRanges: ProjectionSourceRange[] = [
      ...previous.commandProtectedRanges,
      ...previous.structuralRanges,
    ];
    const structuralMarker = /[\r\n`~<>%$\[\]!*_|^:]/;
    if (indexedRanges.length === 0
        && !transactionMayCreateProjection(transaction, structuralMarker)) {
      return mapLiveProjectionIndex(previous, transaction);
    }
    return transactionCanMapProjection(transaction, structuralMarker, indexedRanges)
      ? mapLiveProjectionIndex(previous, transaction)
      : buildLiveProjectionIndex(transaction.state);
  },
});

function liveProjectionIndexForState(state: EditorState) {
  return state.field(liveProjectionIndexField, false) ?? buildLiveProjectionIndex(state);
}

function semanticLiteralRanges(state: EditorState): SemanticLiteralRanges {
  return liveProjectionIndexForState(state).literals;
}

function visibleMathExpressions(
  view: EditorView,
  coveredRanges: readonly ProjectionSourceRange[],
  index: LiveProjectionIndex,
): MathProjection[] {
  if (!editingDialect || coveredRanges.length === 0) return [];
  const doc = view.state.doc;
  let from = Math.min(...coveredRanges.map((range) => range.from));
  const to = Math.max(...coveredRanges.map((range) => range.to));
  if (index.frontmatterRange) {
    if (to <= index.frontmatterRange.to) return [];
    from = Math.max(from, index.frontmatterRange.to);
  }
  const expressions: MathProjection[] = [];
  syntaxTree(view.state).iterate({
    from,
    to,
    enter(node) {
      if (node.name !== "InlineMath" && node.name !== "BlockMath") return undefined;
      // A syntax node may enclose the queried viewport. Do not materialize a
      // very large one-line expression unless its exact source is fully
      // contained by the bounded projection window.
      if (node.from < from || node.to > to) return false;
      const raw = doc.sliceString(node.from, node.to);
      let delimiterLength = 0;
      while (raw.charCodeAt(delimiterLength) === 0x24) delimiterLength += 1;
      if (delimiterLength === 0) return false;
      if (node.name === "InlineMath") {
        const contentFrom = node.from + delimiterLength;
        const contentTo = node.to - delimiterLength;
        const sourceContent = doc.sliceString(contentFrom, contentTo);
        const content = sourceContent.length > 2
          && /^\s/.test(sourceContent) && /\s$/.test(sourceContent) && /\S/.test(sourceContent)
          ? sourceContent.slice(1, -1)
          : sourceContent;
        expressions.push({
          kind: "inline", content, delimiterLength,
          from: node.from, to: node.to, contentFrom, contentTo,
        });
        return false;
      }
      const firstBreak = raw.indexOf("\n");
      const lastBreak = raw.lastIndexOf("\n");
      if (firstBreak < 0 || lastBreak < firstBreak) return false;
      const contentFrom = node.from + firstBreak + 1;
      const contentTo = node.from + lastBreak + 1;
      expressions.push({
        kind: "display",
        content: doc.sliceString(contentFrom, contentTo).replace(/^[\r\n]+|[\r\n]+$/g, ""),
        delimiterLength,
        from: node.from, to: node.to, contentFrom, contentTo,
      });
      return false;
    },
  });
  return expressions;
}

function firstSemanticBodyLineFrom(doc: Text, knownBodyFrom?: number) {
  const bodyFrom = knownBodyFrom ?? frontmatterBodyOffset(doc);
  let line = doc.lineAt(bodyFrom);
  while (line.text.trim().length === 0 && line.number < doc.lines) {
    line = doc.line(line.number + 1);
  }
  return line.from;
}

interface LiveBlockProjectionState {
  decorations: DecorationSet;
  hasConstructs: boolean;
}

interface LiveTableProjectionState extends LiveBlockProjectionState {
  presentations: readonly TablePresentation[];
}

function annotateProjectedSourceOffsets(root: HTMLElement, source: string, sourceFrom: number) {
  root.dataset.sourceOffset = String(sourceFrom);
  let searchFrom = 0;
  const candidates = root.querySelectorAll<HTMLElement>([
    ".scholium-callout-title",
    ".scholium-callout-content p",
    ".scholium-callout-content li",
    ".scholium-callout-content blockquote",
    ".scholium-callout-content h1",
    ".scholium-callout-content h2",
    ".scholium-callout-content h3",
    ".scholium-callout-content h4",
    ".scholium-callout-content h5",
    ".scholium-callout-content h6",
    ".scholium-callout-content code",
  ].join(","));
  for (const candidate of candidates) {
    const text = candidate.textContent?.trim() ?? "";
    if (!text) continue;
    const localOffset = source.indexOf(text, searchFrom);
    if (localOffset < 0) continue;
    candidate.dataset.sourceOffset = String(sourceFrom + localOffset);
    searchFrom = localOffset + text.length;
  }
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
  const anchor = event.shiftKey ? view.state.selection.main.anchor : sourceOffset;
  view.dispatch({selection: {anchor, head: sourceOffset}, scrollIntoView: true});
  view.focus();
  let frame: number | null = null;
  let latest: MouseEvent | null = null;
  const move = (moveEvent: MouseEvent) => {
    latest = moveEvent;
    if (frame !== null) return;
    frame = window.requestAnimationFrame(() => {
      frame = null;
      const current = latest;
      latest = null;
      if (!current) return;
      const head = view.posAtCoords({x: current.clientX, y: current.clientY});
      if (head !== null) view.dispatch({selection: {anchor, head}});
    });
  };
  const finish = () => {
    if (frame !== null) window.cancelAnimationFrame(frame);
    window.removeEventListener("mousemove", move, true);
    window.removeEventListener("mouseup", finish, true);
  };
  window.addEventListener("mousemove", move, true);
  window.addEventListener("mouseup", finish, true);
}

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

  get estimatedHeight() {
    return Math.max(44, (this.presentation.body.length + 1) * 34);
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

  get estimatedHeight() {
    return Math.max(72, this.presentation.source.split("\n").length * 30);
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
  const sourceHead = presentation.to;
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
        if (head !== null) view.dispatch({selection: {anchor, head}});
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
      inclusiveStart: false,
      inclusiveEnd: false,
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
      && other.reference.definitionFrom === this.reference.definitionFrom;
    if (equal) liveWidgetReuseCounts.footnote += 1;
    return equal;
  }

  toDOM(view: EditorView) {
    const wrapper = document.createElement("sup");
    wrapper.className = "footnote-reference-wrap cm-live-footnote-reference-widget";
    wrapper.dataset.scholiumProtected = "footnote";
    const button = document.createElement("button");
    button.type = "button";
    button.className = "footnote-reference";
    button.dataset.footnote = String(this.reference.ordinal);
    button.dataset.footnotePreviewId = this.reference.identifier.slice(0, 240);
    button.dataset.scholiumProtected = "footnote-preview-anchor";
    button.setAttribute("aria-label", `Footnote ${this.reference.ordinal}`);
    button.tabIndex = -1;
    button.textContent = String(this.reference.ordinal);
    if (this.reference.definitionFrom === null) {
      button.setAttribute("aria-disabled", "true");
      button.classList.add("footnote-reference-missing");
    }
    footnoteReferencePresentations.set(wrapper, this.reference);
    wrapper.addEventListener("mousedown", (event) => {
      event.preventDefault();
      const reference = footnoteReferencePresentations.get(wrapper);
      if (!reference) return;
      const rect = button.getBoundingClientRect();
      selectedFootnotePreviewTarget = {
        identifier: reference.identifier,
        from: reference.from,
        rect: {left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom},
      };
      view.dispatch({selection: {anchor: reference.from}, scrollIntoView: true});
      view.focus();
    });
    wrapper.append(button);
    return wrapper;
  }

  updateDOM(dom: HTMLElement) {
    const previous = footnoteReferencePresentations.get(dom);
    const sameContent = previous
      && previous.identifier === this.reference.identifier
      && previous.ordinal === this.reference.ordinal
      && previous.occurrence === this.reference.occurrence
      && (previous.definitionFrom === null) === (this.reference.definitionFrom === null);
    if (!sameContent) return false;
    footnoteReferencePresentations.set(dom, this.reference);
    liveWidgetReuseCounts.footnote += 1;
    return true;
  }

  ignoreEvent() { return true; }
}

const footnoteSectionPresentations = new WeakMap<HTMLElement, readonly FootnoteDefinitionPresentation[]>();
const footnoteDefinitionPresentations = new WeakMap<HTMLElement, FootnoteDefinitionPresentation>();

class FootnoteSectionWidget extends WidgetType {
  constructor(readonly definitions: readonly FootnoteDefinitionPresentation[]) { super(); }

  eq(other: FootnoteSectionWidget) {
    const equal = other.definitions.length === this.definitions.length
      && other.definitions.every((definition, index) => {
        const current = this.definitions[index];
        return definition.identifier === current.identifier
          && definition.ordinal === current.ordinal
          && definition.content === current.content
          && definition.from === current.from
          && definition.to === current.to;
      });
    if (equal) liveWidgetReuseCounts.footnote += 1;
    return equal;
  }

  get estimatedHeight() {
    return Math.max(72, this.definitions.length * 52);
  }

  toDOM(view: EditorView) {
    const section = document.createElement("section");
    section.className = "footnotes cm-live-footnotes-widget";
    section.dataset.scholiumProtected = "footnotes";
    section.setAttribute("aria-label", "Footnotes");
    section.append(document.createElement("hr"));
    const list = document.createElement("ol");
    footnoteSectionPresentations.set(section, this.definitions);
    for (const definition of this.definitions) {
      const item = document.createElement("li");
      item.dataset.footnote = String(definition.ordinal);
      item.dataset.sourceOffset = String(definition.from);
      footnoteDefinitionPresentations.set(item, definition);
      const content = document.createElement("div");
      content.className = "footnote-content";
      appendMarkdownBlocks(definition.content, content, {
        mathematics: editingDialect?.mathematics,
        resolveCallout: calloutDefinition,
      });
      const back = document.createElement("button");
      back.type = "button";
      back.className = "footnote-return";
      back.tabIndex = -1;
      back.textContent = "↩";
      back.setAttribute("aria-label", `Edit footnote ${definition.ordinal}`);
      const revealSource = (event: MouseEvent) => {
        event.preventDefault();
        const current = footnoteDefinitionPresentations.get(item);
        if (!current) return;
        view.dispatch({selection: {anchor: current.from}, scrollIntoView: true});
        view.focus();
      };
      item.addEventListener("mousedown", revealSource);
      item.append(content, back);
      list.append(item);
    }
    section.append(list);
    return section;
  }

  updateDOM(dom: HTMLElement) {
    const previous = footnoteSectionPresentations.get(dom);
    const sameContent = previous?.length === this.definitions.length
      && this.definitions.every((definition, index) => {
        const prior = previous[index];
        return definition.identifier === prior.identifier
          && definition.ordinal === prior.ordinal
          && definition.content === prior.content
          && definition.isInline === prior.isInline;
      });
    if (!sameContent) return false;
    const items = [...dom.querySelectorAll<HTMLElement>("li[data-footnote]")];
    if (items.length !== this.definitions.length) return false;
    items.forEach((item, index) => {
      const definition = this.definitions[index];
      item.dataset.sourceOffset = String(definition.from);
      footnoteDefinitionPresentations.set(item, definition);
    });
    footnoteSectionPresentations.set(dom, this.definitions);
    liveWidgetReuseCounts.footnote += 1;
    return true;
  }

  ignoreEvent() { return true; }
}

interface LiveFootnoteProjectionState extends LiveBlockProjectionState {
  presentation: FootnotePresentation;
  ranges: readonly Readonly<ProjectionSourceRange>[];
}

function liveFootnoteDecorations(
  state: EditorState,
  presentation: FootnotePresentation,
) {
  const decorations: Range<Decoration>[] = [];
  const active = (from: number, to: number) => state.selection.ranges.some((range) =>
    selectionIntersectsProjection(range, {from, to}),
  );
  const activeDefinitionIdentifiers = new Set<string>();

  for (const definition of presentation.definitions) {
    if (definition.isInline) continue;
    if (active(definition.from, definition.to)) {
      activeDefinitionIdentifiers.add(definition.identifier);
      decorations.push(Decoration.mark({
        class: "cm-live-footnote-definition-source",
      }).range(definition.from, definition.to));
    } else {
      decorations.push(Decoration.replace({block: true}).range(definition.from, definition.to));
    }
  }

  for (const reference of presentation.references) {
    const containedByDefinition = presentation.definitions.some((definition) =>
      !definition.isInline && definition.from <= reference.from && definition.to >= reference.to,
    );
    if (containedByDefinition || active(reference.from, reference.to)) continue;
    decorations.push(Decoration.replace({
      widget: new FootnoteReferenceWidget(reference),
    }).range(reference.from, reference.to));
  }

  const displayedDefinitions = presentation.definitions.filter((definition) =>
    definition.ordinal !== null && !activeDefinitionIdentifiers.has(definition.identifier)
      && !(definition.isInline && active(definition.from, definition.to)),
  );
  if (displayedDefinitions.length > 0) {
    decorations.push(Decoration.widget({
      widget: new FootnoteSectionWidget(displayedDefinitions),
      block: true,
      side: 1,
    }).range(state.doc.length));
  }
  return Decoration.set(decorations, true);
}

function buildLiveFootnoteDecorations(state: EditorState): LiveFootnoteProjectionState {
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
    decorations: liveFootnoteDecorations(state, presentation),
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
    })),
    references: presentation.references.map((reference) => ({
      ...reference,
      from: map(reference.from),
      to: map(reference.to),
      definitionFrom: reference.definitionFrom === null ? null : map(reference.definitionFrom),
    })),
  };
}

const liveFootnoteField = StateField.define<LiveFootnoteProjectionState>({
  create: buildLiveFootnoteDecorations,
  update(previous, transaction) {
    const syntaxTreeChanged = transactionChangedSyntaxTree(transaction);
    if (!transaction.docChanged && syntaxTreeChanged) {
      return buildLiveFootnoteDecorations(transaction.state);
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
        decorations: liveFootnoteDecorations(transaction.state, previous.presentation),
      };
    }
    if (transactionCanMapProjection(transaction, /[\[\]\^:]/, previous.ranges)) {
      const presentation = mapFootnotePresentation(previous.presentation, transaction);
      const ranges = immutableProjectionRanges([
        ...presentation.definitions,
        ...presentation.references,
      ].map(({from, to}) => ({from, to})));
      return {
        decorations: liveFootnoteDecorations(transaction.state, presentation),
        hasConstructs: true,
        presentation,
        ranges,
      };
    }
    return buildLiveFootnoteDecorations(transaction.state);
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
  const selection = view.state.selection.main;
  const firstBodyLineFrom = index.firstBodyLineFrom;
  const semanticLiterals = index.literals;
  const parsedProjection = semanticProjectionRanges(view.state, coveredRanges, 0);
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
  const mathExpressions = visibleMathExpressions(view, coveredRanges, index);

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
    if (expression.kind === "inline") {
      addAtomicReplacement(Decoration.replace({
        widget: new MathWidget(expression),
      }), expression.from, expression.to);
      continue;
    }

    const firstLine = doc.lineAt(expression.from);
    const lastLine = doc.lineAt(expression.to);
    decorations.push(Decoration.widget({
      widget: new MathWidget(expression),
      side: -1,
    }).range(expression.from));
    decorations.push(Decoration.line({
      attributes: {class: "cm-live-math-display-line"},
    }).range(firstLine.from));
    for (let lineNumber = firstLine.number; lineNumber <= lastLine.number; lineNumber += 1) {
      const mathLine = doc.line(lineNumber);
      addHidden(
        Math.max(expression.from, mathLine.from),
        Math.min(expression.to, mathLine.to),
      );
      if (lineNumber > firstLine.number) {
        decorations.push(Decoration.line({
          attributes: {class: "cm-live-math-collapsed-line"},
        }).range(mathLine.from));
      }
    }
  }

  literals.sort((left, right) => left.from - right.from || left.to - right.to);

  for (const visible of coveredRanges) {
    let line = doc.lineAt(visible.from);
    const lastLine = doc.lineAt(visible.to).number;
    while (line.from <= visible.to) {
      const scanFrom = Math.max(line.from, visible.from);
      const scanTo = Math.min(line.to, visible.to);
      const text = doc.sliceString(scanFrom, scanTo);
      const linePrefix = doc.sliceString(line.from, Math.min(line.to, line.from + 512));
      const lineFullyScanned = scanFrom === line.from && scanTo === line.to;
      const lineQueryTo = Math.min(doc.length, scanTo + 1);
      const activeLine = selection.head >= line.from && selection.head <= line.to
        || view.composing && view.state.selection.ranges.some(
          (range) => range.from < lineQueryTo && range.to >= line.from,
        );
      const excluded = [...rangesIntersecting(literals, scanFrom, lineQueryTo)];

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
        if (semanticCodeBlock || isIndentedCodeLine(linePrefix)) {
          decorations.push(Decoration.line({ attributes: { class: "cm-live-codeblock" } }).range(line.from));
          const fenceLine = semanticCodeBlock
            ? isFencedDelimiterLine(doc, semanticCodeBlock, line.from)
            : false;
          if (fenceLine && !activeLine) addHidden(line.from, line.to);
          else if (!fenceLine) addMark(scanFrom, scanTo, "cm-live-code");
          if (line.to === doc.length) break;
          line = doc.line(line.number + 1);
          continue;
        }

        const headingLevel = parsedProjection.headingLevelByLineFrom.get(line.from);
        const heading = headingLevel ? /^(\uFEFF?)(#{1,6})\s+/.exec(linePrefix) : null;
        if (heading && heading[2].length === headingLevel) {
          const isDocumentTitle = headingLevel === 1 && line.from === firstBodyLineFrom;
          decorations.push(
            Decoration.line({
              attributes: {
                class: `cm-live-heading cm-live-h${heading[2].length}${isDocumentTitle ? " cm-live-document-title" : ""}`,
              },
            }).range(line.from),
          );
          if (!activeLine) addHidden(line.from, line.from + heading[0].length);
        }

        const parsedCallout = rangesIntersecting(
          parsedProjection.callouts,
          scanFrom,
          lineQueryTo,
        )[0];
        const parsedParagraph = rangesIntersecting(
          parsedProjection.paragraphs,
          scanFrom,
          lineQueryTo,
        )[0];
        if (parsedParagraph && !parsedCallout && !heading) {
          const paragraphClasses = ["cm-live-paragraph"];
          if (line.from <= parsedParagraph.from) paragraphClasses.push("cm-live-paragraph-start");
          if (line.to >= parsedParagraph.to) paragraphClasses.push("cm-live-paragraph-end");
          decorations.push(Decoration.line({
            attributes: {class: paragraphClasses.join(" ")},
          }).range(line.from));
        }
        const quote = /^(\s*>\s?)/.exec(linePrefix);
        if (quote && !parsedCallout) {
          decorations.push(
            Decoration.line({
              attributes: { class: "cm-live-quote" },
            }).range(line.from),
          );
          if (!activeLine) addHidden(line.from, line.from + quote[0].length);
        }
        // An active Callout is exact editable Markdown. The block widget is
        // removed by liveCalloutField, and no Callout line styling, role
        // widget, marker hiding, or quote projection is permitted here.

        const rule = lineFullyScanned
          ? /^\s{0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$/.exec(text)
          : null;
        if (rule && !activeLine) {
          addHidden(line.from, line.to);
          decorations.push(
            Decoration.line({ attributes: { class: "cm-live-rule" } }).range(line.from),
          );
        }

        const list = /^(\s*)([-+*]|\d+[.)])(\s+)/.exec(linePrefix);
        if (list) {
          decorations.push(Decoration.line({ attributes: { class: "cm-live-list" } }).range(line.from));
          if (!activeLine) {
            const markerFrom = line.from + list[1].length;
            const markerTo = markerFrom + list[2].length;
            addAtomicReplacement(
              Decoration.replace({widget: new ListMarkerWidget(list[2])}),
              markerFrom,
              markerTo,
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

        const relation = /^(\s*-\s*)`([^`]+)`(\s*->\s*)/.exec(linePrefix);
        if (relation) {
          const predicateFrom = line.from + relation[1].length + 1;
          const predicateTo = predicateFrom + relation[2].length;
          excluded.push({ from: predicateFrom - 1, to: predicateTo + 1 });
          decorations.push(Decoration.line({ attributes: { class: "cm-live-relation" } }).range(line.from));
          if (!activeLine) {
            addHidden(predicateFrom - 1, predicateFrom);
            addMark(predicateFrom, predicateTo, "cm-live-relation-predicate");
            addHidden(predicateTo, predicateTo + 1);
            addMark(predicateTo + 1, predicateTo + 1 + relation[3].length, "cm-live-relation-arrow");
          }
        }

        for (const match of text.matchAll(/(`+)([^\n]*?)\1/g)) {
          const from = scanFrom + match.index;
          const to = from + match[0].length;
          excluded.push({ from, to });
          if (!activeLine) {
            const markerLength = match[1].length;
            addHidden(from, from + markerLength);
            addMark(from + markerLength, to - markerLength, "cm-live-code");
            addHidden(to - markerLength, to);
          }
        }

        // Wikilinks remain one exact source construct. Outside the active
        // construct, replace its punctuation with a semantic SF Symbol mask;
        // moving the caret into it removes every projection decoration.
        for (const match of text.matchAll(/(!?)\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g)) {
          const from = scanFrom + match.index;
          const to = from + match[0].length;
          const embed = match[1] === "!";
          const wikiIndex = match.index + (embed ? 1 : 0);
          if (isEscapedAt(text, match.index) || overlaps(excluded, from, to)) continue;

          const kind = embed ? "neutral" : vectorLinkKindAt(text, wikiIndex);
          const hasVectorMarker = !embed && kind !== "neutral";
          const fullFrom = hasVectorMarker ? from - 1 : from;
          if (fullFrom < line.from
            || overlaps(excluded, fullFrom, to)
            || !parsedProjection.wikilinks.has(rangeKey(fullFrom, to))) continue;
          excluded.push({ from: fullFrom, to });

          const activeConstruct = view.state.selection.ranges.some((selected) =>
            selectionIntersectsProjection(selected, {from: fullFrom, to}),
          );
          if (activeConstruct) continue;

          const target = match[2];
          const alias = match[3];
          const openingEnd = from + (embed ? 3 : 2);
          const annotationStart = alias === undefined ? null : openingEnd + target.length + 1;
          const presentation = wikilinkPresentation(openingEnd, target, annotationStart, alias);
          if (embed) {
            addHidden(from, openingEnd);
          } else {
            addAtomicReplacement(
              Decoration.replace({widget: new VectorLinkIconWidget(kind)}),
              fullFrom,
              openingEnd,
            );
          }

          const linkClass = embed
            ? "cm-live-embed"
            : presentation.isLegacyRelationship && kind === "neutral"
              ? "cm-live-vector-link cm-live-vector-neutral cm-live-vector-legacy"
              : `cm-live-vector-link cm-live-vector-${kind.replaceAll("_", "-")}`;
          addHidden(openingEnd, presentation.displayStart);
          const previewIndex = linkPreviewIndexByRange.get(rangeKey(fullFrom, to));
          if (previewIndex === undefined) {
            addMark(presentation.displayStart, presentation.displayEnd, linkClass);
          } else {
            addPreviewMark(presentation.displayStart, presentation.displayEnd, linkClass, previewIndex);
          }
          addHidden(presentation.displayEnd, to - 2);
          addHidden(to - 2, to);
        }

        if (!activeLine) {
          for (const match of text.matchAll(/\[([^\]\n]+)\]\(([^)\n]+)\)/g)) {
            const from = scanFrom + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to) || !parsedProjection.links.has(rangeKey(from, to))) continue;
            addHidden(from, from + 1);
            addMark(from + 1, from + 1 + match[1].length, "cm-live-link");
            addHidden(from + 1 + match[1].length, to);
          }

          for (const match of text.matchAll(/\*\*([^*\n]+)\*\*/g)) {
            const from = scanFrom + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to) || !parsedProjection.strong.has(rangeKey(from, to))) continue;
            addHidden(from, from + 2);
            addMark(from + 2, to - 2, "cm-live-strong");
            addHidden(to - 2, to);
          }

          for (const match of text.matchAll(/~~([^~\n]+)~~/g)) {
            const from = scanFrom + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to) || !parsedProjection.strikethrough.has(rangeKey(from, to))) continue;
            addHidden(from, from + 2);
            addMark(from + 2, to - 2, "cm-live-strike");
            addHidden(to - 2, to);
          }

          for (const match of text.matchAll(/==([^=\n]+)==/g)) {
            const from = scanFrom + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to) || !parsedProjection.highlights.has(rangeKey(from, to))) continue;
            addHidden(from, from + 2);
            addMark(from + 2, to - 2, "cm-live-highlight");
            addHidden(to - 2, to);
          }

          for (const match of text.matchAll(/(?<!\*)\*([^*\n]+)\*(?!\*)/g)) {
            const from = scanFrom + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to) || !parsedProjection.emphasis.has(rangeKey(from, to))) continue;
            addHidden(from, from + 1);
            addMark(from + 1, to - 1, "cm-live-emphasis");
            addHidden(to - 1, to);
          }
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
    if (update.docChanged || viewportNeedsProjection || explicitlyRefreshed || syntaxTreeChanged) {
      const projection = buildLiveDecorations(update.view);
      this.decorations = projection.decorations;
      this.atomicRanges = projection.atomicRanges;
      this.coveredRanges = projection.coveredRanges;
    } else if (update.selectionSet
        && !update.startState.selection.eq(update.state.selection)) {
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
      "Live Preview is unavailable because YAML frontmatter is not closed. Use Source mode to finish the frontmatter.",
    );

    const title = document.createElement("strong");
    title.textContent = "Live Preview unavailable";
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
  const hiddenFrontmatter = Decoration.set([
    Decoration.replace({block: true}).range(0, bodyFrom),
  ]);
  return {decorations: hiddenFrontmatter, atomicRanges: hiddenFrontmatter};
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

const livePreviewMode = [
  syntaxHighlighting(livePreviewHighlightStyle),
  liveFrontmatterGuardField,
  liveBlockActivationField,
  liveTableField,
  liveCalloutField,
  liveFootnoteField,
  livePreview,
  EditorView.lineWrapping,
];
const sourceMode = [
  syntaxHighlighting(defaultHighlightStyle, {fallback: true}),
  lineNumbers(),
  highlightActiveLineGutter(),
  foldGutter(),
  highlightActiveLine(),
];

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
  if (update.selectionSet
      && selectedFootnotePreviewTarget?.from !== update.state.selection.main.head) {
    selectedFootnotePreviewTarget = null;
  }
  const isProgrammatic = update.transactions.some(
    (transaction) => transaction.annotation(programmaticDocumentChange) === true,
  );
  if (isProgrammatic) return;
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
    update.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
      changes.push({ from: fromA, to: toA, insert: inserted.toString() });
    });
    const updatedExactSource = applyNormalizedChangesToExactSource(exactSource, changes);
    if (updatedExactSource === null
        || normalizedDocumentText(updatedExactSource)
            !== normalizedDocumentText(update.state.doc.toString())) {
      post({
        type: "editorError",
        message: "The editor could not preserve the exact source line endings.",
      });
      return;
    }
    exactSource = updatedExactSource;
    post({ type: "documentChanged", baseGeneration, resultingGeneration: documentVersion, changes });
  }

  scheduleEditorInteractionReport();

  if (update.docChanged) {
    if (idleTimer !== null) window.clearTimeout(idleTimer);
    idleTimer = window.setTimeout(() => post({ type: "idle", dirty }), 500);
  }
});

const researcherCommentActivation = EditorView.domEventHandlers({
  click(event) {
    if (event.metaKey) {
      const position = editor.posAtCoords({x: event.clientX, y: event.clientY});
      const target = position === null ? null : linkTargetAt(editor.state.doc.toString(), position);
      if (target) {
        post({type: "linkActivated", target});
        event.preventDefault();
        return true;
      }
    }
    const target = event.target instanceof Element
      ? event.target.closest<HTMLElement>("[data-comment-id]")
      : null;
    const commentID = target?.dataset.commentId;
    if (!commentID) return false;
    post({ type: "commentActivated", commentID });
    // Let CodeMirror place the caret normally. The comments toolbar remains
    // the keyboard-accessible route, while clicking an existing annotation
    // opens that exact record without making the editor text inert.
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
      continueList(view.state.doc.toString(), editorSelections()),
      "input.scholium.continueList",
    ),
  },
  {
    key: "Tab",
    run: (view) => {
      if (view.state.selection.ranges.length !== 1) {
        return applyInteraction(indentList(view.state.doc.toString(), editorSelections(), false), "input.scholium.indentList");
      }
      return applyInteraction(
        tableTabAction(view.state.doc.toString(), view.state.selection.main.head, false)
          ?? indentList(view.state.doc.toString(), editorSelections(), false),
        "input.scholium.structuralTab",
      );
    },
  },
  {
    key: "Shift-Tab",
    run: (view) => {
      if (view.state.selection.ranges.length !== 1) {
        return applyInteraction(indentList(view.state.doc.toString(), editorSelections(), true), "input.scholium.outdentList");
      }
      return applyInteraction(
        tableTabAction(view.state.doc.toString(), view.state.selection.main.head, true)
          ?? indentList(view.state.doc.toString(), editorSelections(), true),
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
  if (currentMode !== "livePreview" || view.composing) return false;
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
    : isCallout
      ? projection.to
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
  if (currentMode !== "livePreview" || view.composing) return false;
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

const editorExtensions = [
      highlightSpecialChars(),
      history(),
      drawSelection(),
      dropCursor(),
      EditorState.allowMultipleSelections.of(true),
      indentOnInput(),
      bracketMatching(),
      closeBrackets(),
      autocompletion({ override: [calloutCompletionSource, wikilinkCompletionSource] }),
      rectangularSelection(),
      highlightSelectionMatches(),
      scholiumNoteLanguage,
      liveProjectionNavigationKeymap,
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
      researcherCommentField,
      researcherCommentActivation,
      lineSeparatorCompartment.of(EditorState.lineSeparator.of("\n")),
      liveProjectionIndexField,
      modeCompartment.of(livePreviewMode),
      EditorView.contentAttributes.of(editorAccessibilityAttributes("livePreview")),
      EditorView.theme({
        "&": { height: "100%" },
        ".cm-scroller": { overflow: "auto" },
      }),
];
const editor = createMarkdownEditor(document.getElementById("editor")!, editorExtensions);
// The first document request may arrive on a later native bridge turn. Give
// the empty editor its canonical initial mode immediately so an accidentally
// exposed startup frame can never resemble Source mode.
editor.dom.classList.add("scholium-live-mode");
editor.scrollDOM.classList.add("scholium-live-scroller");
editor.contentDOM.addEventListener("keydown", () => { pendingKeyStartedAt = performance.now(); }, {capture: true});

const previewPopover = document.createElement("aside");
previewPopover.id = "scholium-preview-popover";
previewPopover.className = "scholium-preview-popover";
previewPopover.dataset.scholiumProtected = "preview-popover";
previewPopover.setAttribute("role", "tooltip");
previewPopover.setAttribute("aria-live", "polite");
previewPopover.hidden = true;
const previewTitle = document.createElement("h2");
previewTitle.className = "scholium-preview-title";
const previewMetadata = document.createElement("p");
previewMetadata.className = "scholium-preview-metadata";
const previewBody = document.createElement("div");
previewBody.className = "scholium-preview-body";
previewBody.setAttribute("role", "group");
previewBody.setAttribute("aria-label", "Preview content");
previewPopover.append(previewTitle, previewMetadata, previewBody);
document.body.append(previewPopover);

const relationshipLabels: Record<VectorLinkKind, string> = {
  neutral: "Related note",
  supports_target: "Supports",
  supported_by_target: "Supported by",
  incompatible: "Incompatible with",
};
let previewTimer: number | undefined;
let pendingPreviewAnchor: HTMLElement | null = null;
type PreviewAnchorRect = Pick<DOMRect, "left" | "right" | "top" | "bottom">;

function hidePreview() {
  window.clearTimeout(previewTimer);
  previewTimer = undefined;
  pendingPreviewAnchor = null;
  previewPopover.hidden = true;
  previewPopover.style.visibility = "";
  previewTitle.textContent = "";
  previewMetadata.textContent = "";
  previewBody.replaceChildren();
}

function positionPreview(anchor: PreviewAnchorRect, startedAt: number) {
  previewPopover.style.visibility = "hidden";
  previewPopover.hidden = false;
  const inset = 12;
  const gap = 8;
  editor.requestMeasure({
    read: () => ({
      measured: previewPopover.getBoundingClientRect(),
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
    }),
    write: ({measured, viewportWidth, viewportHeight}) => {
      if (previewPopover.hidden) return;
      const left = Math.max(inset, Math.min(anchor.left, viewportWidth - measured.width - inset));
      const below = anchor.bottom + gap;
      const top = below + measured.height <= viewportHeight - inset
        ? below
        : Math.max(inset, anchor.top - measured.height - gap);
      previewPopover.style.left = `${left}px`;
      previewPopover.style.top = `${top}px`;
      previewPopover.style.visibility = "visible";
      window.requestAnimationFrame(() => recordEditorMetric("cached-preview", startedAt, {
        documentLength: editor.state.doc.length,
      }));
    },
  });
}

function removeInteractivePreviewContent(root: HTMLElement) {
  root.querySelectorAll("script, style, iframe, object, embed, form, input, button").forEach((node) => node.remove());
  root.querySelectorAll<HTMLElement>("*").forEach((node) => {
    for (const attribute of Array.from(node.attributes)) {
      if (attribute.name.toLowerCase().startsWith("on")) node.removeAttribute(attribute.name);
    }
    node.removeAttribute("href");
    node.removeAttribute("contenteditable");
    node.tabIndex = -1;
  });
}

function showLinkPreview(preview: LinkPreview, anchor: PreviewAnchorRect, startedAt: number) {
  previewTitle.textContent = preview.title;
  const relationship = preview.relationship ? relationshipLabels[preview.relationship] : "Related note";
  previewMetadata.textContent = preview.fragment
    ? `${relationship} · ${preview.fragment}`
    : relationship;
  previewBody.innerHTML = preview.htmlBody;
  removeInteractivePreviewContent(previewBody);
  recordEditorMetric("cached-preview-work", startedAt, {
    documentLength: editor.state.doc.length,
  });
  positionPreview(anchor, startedAt);
}

function showFootnotePreview(identifier: string, anchor: PreviewAnchorRect, startedAt: number) {
  const source = editor.state.doc.toString();
  const content = footnotePreviewContent(
    source,
    identifier,
    semanticLiteralRanges(editor.state).excluded,
    editingDialect?.footnotes,
  );
  if (!content) {
    announceEditorMessage(editor.contentDOM, "The referenced footnote is unavailable.");
    hidePreview();
    return false;
  }
  previewTitle.textContent = `Footnote ${identifier}`;
  previewMetadata.textContent = "Referenced footnote";
  previewBody.replaceChildren();
  appendMarkdownBlocks(content, previewBody, {
    mathematics: editingDialect?.mathematics,
    resolveCallout: calloutDefinition,
  });
  recordEditorMetric("cached-preview-work", startedAt, {
    documentLength: editor.state.doc.length,
  });
  positionPreview(anchor, startedAt);
  return true;
}

function showPreviewAtSelection() {
  const startedAt = performance.now();
  if (currentMode !== "livePreview") return false;
  const head = editor.state.selection.main.head;
  if (selectedFootnotePreviewTarget?.from === head) {
    return showFootnotePreview(
      selectedFootnotePreviewTarget.identifier,
      selectedFootnotePreviewTarget.rect,
      startedAt,
    );
  }
  const coords = editor.coordsAtPos(head);
  if (!coords) return false;
  const preview = linkPreviews.find((candidate) => head >= candidate.from && head < candidate.to);
  if (preview) {
    showLinkPreview(preview, coords, startedAt);
    return true;
  }
  const identifier = footnoteReferenceAt(
    editor.state.doc.toString(),
    head,
    semanticLiteralRanges(editor.state).excluded,
    editingDialect?.footnotes,
  );
  if (identifier) return showFootnotePreview(identifier, coords, startedAt);
  announceEditorMessage(editor.contentDOM, "No preview is available at the insertion point.");
  return false;
}

function showPreviewAtPoint(x: number, y: number) {
  const startedAt = performance.now();
  if (currentMode !== "livePreview") return false;
  const anchor = document.elementFromPoint(x, y)?.closest<HTMLElement>(
    "[data-link-preview-index], [data-footnote-preview-id]",
  );
  if (!anchor) return showPreviewAtSelection();
  const previewIndex = Number(anchor.dataset.linkPreviewIndex);
  if (Number.isInteger(previewIndex) && linkPreviews[previewIndex]) {
    showLinkPreview(linkPreviews[previewIndex], anchor.getBoundingClientRect(), startedAt);
    return true;
  }
  const identifier = anchor.dataset.footnotePreviewId;
  if (identifier) {
    return showFootnotePreview(identifier, anchor.getBoundingClientRect(), startedAt);
  }
  return showPreviewAtSelection();
}

function previewAnchorAtEvent(event: PointerEvent): HTMLElement | null {
  if (!event.metaKey || currentMode !== "livePreview" || !(event.target instanceof Element)) return null;
  return event.target.closest<HTMLElement>("[data-link-preview-index], [data-footnote-preview-id]");
}

document.addEventListener("pointermove", (event) => {
  const anchor = previewAnchorAtEvent(event);
  if (!anchor) {
    if (pendingPreviewAnchor || !previewPopover.hidden) hidePreview();
    return;
  }
  if (anchor === pendingPreviewAnchor) return;
  hidePreview();
  pendingPreviewAnchor = anchor;
  previewTimer = window.setTimeout(() => {
    if (pendingPreviewAnchor !== anchor) return;
    const startedAt = performance.now();
    const previewIndex = Number(anchor.dataset.linkPreviewIndex);
    if (Number.isInteger(previewIndex) && linkPreviews[previewIndex]) {
      showLinkPreview(linkPreviews[previewIndex], anchor.getBoundingClientRect(), startedAt);
      return;
    }
    const identifier = anchor.dataset.footnotePreviewId;
    if (identifier) showFootnotePreview(identifier, anchor.getBoundingClientRect(), startedAt);
  }, 300);
}, {passive: true});
document.addEventListener("keyup", (event) => {
  if (event.key === "Meta") hidePreview();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !previewPopover.hidden) hidePreview();
});

function currentEditorScrollAnchor(): EditorScrollAnchor {
  const extent = Math.max(0, editor.scrollDOM.scrollHeight - editor.scrollDOM.clientHeight);
  const fallbackFraction = extent > 0
    ? Math.max(0, Math.min(1, editor.scrollDOM.scrollTop / extent))
    : 0;
  const probeHeight = Math.max(0, editor.scrollDOM.scrollTop + 8);
  const block = editor.lineBlockAtHeight(probeHeight);
  const relativeBlockPosition = block.height > 0
    ? Math.max(0, Math.min(1, (probeHeight - block.top) / block.height))
    : 0;
  return {
    sourceUTF16Offset: block.from,
    blockUTF16LowerBound: block.from,
    blockUTF16UpperBound: block.to,
    relativeBlockPosition,
    fallbackFraction,
  };
}

function postCurrentScrollPosition() {
  const scrollAnchor = currentEditorScrollAnchor();
  post({type: "scrollChanged", scrollFraction: scrollAnchor.fallbackFraction, scrollAnchor});
}

let scrollReportTimer: number | undefined;
let scrollSessionStartedAt: number | null = null;
let previousScrollFrameAt: number | null = null;
let scrollMeasurementFrame: number | null = null;
let scrollSessionFrameCount = 0;
let scrollSessionLongestFrame = 0;
let scrollSessionDroppedFrameCount = 0;
editor.scrollDOM.addEventListener("scroll", () => {
  if (scrollSessionStartedAt === null) scrollSessionStartedAt = performance.now();
  if (scrollMeasurementFrame === null) {
    scrollMeasurementFrame = window.requestAnimationFrame(() => {
      scrollMeasurementFrame = null;
      const now = performance.now();
      scrollSessionFrameCount += 1;
      if (previousScrollFrameAt !== null) {
        const duration = Math.max(0, now - previousScrollFrameAt);
        scrollSessionLongestFrame = Math.max(scrollSessionLongestFrame, duration);
        if (duration > 20) scrollSessionDroppedFrameCount += 1;
      }
      previousScrollFrameAt = now;
    });
  }
  window.clearTimeout(scrollReportTimer);
  scrollReportTimer = window.setTimeout(() => {
    postCurrentScrollPosition();
    if (scrollSessionStartedAt !== null) {
      recordEditorMetric("scroll-session", scrollSessionStartedAt, {
        frameCount: scrollSessionFrameCount,
        longestFrameMilliseconds: scrollSessionLongestFrame,
        droppedFrameCount: scrollSessionDroppedFrameCount,
      });
    }
    scrollSessionStartedAt = null;
    previousScrollFrameAt = null;
    scrollSessionFrameCount = 0;
    scrollSessionLongestFrame = 0;
    scrollSessionDroppedFrameCount = 0;
  }, 120);
}, { passive: true });

const allCommands = [
  "bold", "emphasis", "strikethrough", "highlight", "inlineCode",
  "standardLink", "wikilink", "vectorSupportsTarget", "vectorSupportedByTarget", "vectorIncompatible",
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
    updateEditorAccessibility(editor.contentDOM, currentMode, context);
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
    editorOperations.setMode(operation.mode);
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
  case "setMode": editorOperations.setMode(operation.mode); break;
  case "setPresentationCSS": editorOperations.setPresentationCSS(operation.value); break;
  case "setUserCSS": editorOperations.setUserCSS(operation.value); break;
  case "setLinkCompletions": editorOperations.setLinkCompletions(operation.value as LinkCandidate[]); break;
  case "setLinkPreviews": editorOperations.setLinkPreviews(operation.value); break;
  case "setResearcherComments": editorOperations.setResearcherComments(operation.value as ResearcherCommentAnnotation[]); break;
  case "showPreview": showPreviewAtSelection(); break;
  case "showPreviewAt": showPreviewAtPoint(operation.x, operation.y); break;
  case "announceStatus": announceEditorMessage(editor.contentDOM, operation.value); break;
  case "goToLine": editorOperations.goToLine(operation.line); break;
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
    scrollAnchor: currentEditorScrollAnchor(),
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
          // document before reconstruction; `exactSource` remains untouched.
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
    editor.setState(recoveredState);
    exactSource = snapshot.source;
    editorOperations.setMode(currentMode);
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

let dynamicStyleMeasureScheduled = false;
function scheduleDynamicStyleMeasure() {
  if (dynamicStyleMeasureScheduled) return;
  dynamicStyleMeasureScheduled = true;
  queueMicrotask(() => {
    dynamicStyleMeasureScheduled = false;
    const documentSnapshot = editor.state.doc;
    editor.requestMeasure({
      read: () => editor.state.doc === documentSnapshot,
      write: (isCurrentDocument) => {
        if (isCurrentDocument && editor.state.doc === documentSnapshot) postCurrentScrollPosition();
      },
    });
  });
}

function setDynamicStyle(id: string, css: string) {
  const style = document.getElementById(id);
  if (!style || style.textContent === css) return;
  style.textContent = css;
  scheduleDynamicStyleMeasure();
  void document.fonts.ready.then(scheduleDynamicStyleMeasure);
}

const editorOperations = {
  /** @param {string} text @param {string} sessionID @param {string} documentID */
  setDocument(text: string, sessionID: string, documentID: string, startingFingerprint: string) {
    hidePreview();
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
    exactSource = text;
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
  setMode(mode: string) {
    const startedAt = performance.now();
    hidePreview();
    const scrollSnapshot = editor.scrollSnapshot();
    const nextMode = mode === "livePreview" ? "livePreview" : "source";
    let selection: EditorSelection | undefined;
    if (nextMode === "livePreview") {
      const bodyFrom = frontmatterBodyOffset(editor.state.doc);
      if (bodyFrom > 0 && editor.state.selection.ranges.some((range) => range.from < bodyFrom)) {
        if (currentMode === "source") {
          hiddenFrontmatterSourceSelection = {
            documentVersion,
            selection: editor.state.selection,
          };
        }
        selection = EditorSelection.create([EditorSelection.cursor(bodyFrom)]);
      }
    } else if (nextMode === "source" && currentMode === "livePreview"
        && hiddenFrontmatterSourceSelection?.documentVersion === documentVersion) {
      selection = hiddenFrontmatterSourceSelection.selection;
      hiddenFrontmatterSourceSelection = null;
    }
    editor.dispatch({
      selection,
      effects: [
        modeCompartment.reconfigure(nextMode === "livePreview" ? livePreviewMode : sourceMode),
        scrollSnapshot,
      ],
    });
    editor.dom.classList.toggle("scholium-live-mode", nextMode === "livePreview");
    editor.dom.classList.toggle("scholium-source-mode", nextMode !== "livePreview");
    editor.scrollDOM.classList.toggle("scholium-live-scroller", nextMode === "livePreview");
    editor.scrollDOM.classList.toggle("scholium-source-scroller", nextMode !== "livePreview");
    currentMode = nextMode;
    updateEditorAccessibility(editor.contentDOM, currentMode, currentEditorContext());
    scheduleEditorInteractionReport(true);
    recordEditorMetric("mode-toggle-work", startedAt, {
      documentLength: editor.state.doc.length,
    });
    editor.requestMeasure({
      read: () => editor.state.doc.length,
      write: (documentLength) => window.requestAnimationFrame(() => recordEditorMetric(
        "mode-toggle",
        startedAt,
        {documentLength},
      )),
    });
    window.setTimeout(postCurrentScrollPosition, 0);
  },

  /** @param {string} css */
  setPresentationCSS(css: string) {
    setDynamicStyle("scholium-presentation-css", css);
  },

  /** @param {string} css */
  setUserCSS(css: string) {
    setDynamicStyle("scholium-user-css", css);
  },

  /** @param {{label: string, insertion: string, detail: string, path: string}[]} candidates */
  setLinkCompletions(candidates: LinkCandidate[]) {
    linkCandidates = Array.isArray(candidates) ? candidates.slice(0, 20000) : [];
  },

  setLinkPreviews(value: unknown) {
    linkPreviews = validatedLinkPreviews(value, editor.state.doc.length);
    linkPreviewIndexByRange = new Map(
      linkPreviews.map((preview, index) => [rangeKey(preview.from, preview.to), index]),
    );
    editor.dispatch({effects: refreshLivePreviewEffect.of(null)});
  },

  setResearcherComments(comments: ResearcherCommentAnnotation[]) {
    const normalized = Array.isArray(comments)
      ? comments.slice(0, 10000).flatMap((comment) => {
        const id = typeof comment?.id === "string" ? comment.id : "";
        const from = Number.isInteger(comment?.from) ? comment.from : -1;
        const to = Number.isInteger(comment?.to) ? comment.to : -1;
        if (!id || from < 0 || to <= from || to > editor.state.doc.length) return [];
        return [{
          id,
          from,
          to,
          comment: typeof comment.comment === "string" ? comment.comment.slice(0, 500) : "",
          resolved: comment.resolved === true,
        }];
      })
      : [];
    editor.dispatch({ effects: setResearcherCommentsEffect.of(normalized) });
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

  setScrollFraction(requestedFraction: number) {
    const fraction = Number.isFinite(requestedFraction)
      ? Math.max(0, Math.min(1, requestedFraction))
      : 0;
    const extent = Math.max(0, editor.scrollDOM.scrollHeight - editor.scrollDOM.clientHeight);
    editor.scrollDOM.scrollTop = extent * fraction;
  },

  setScrollAnchor(anchor: EditorScrollAnchor) {
    const documentLength = editor.state.doc.length;
    const valid = Number.isSafeInteger(anchor.sourceUTF16Offset)
      && anchor.sourceUTF16Offset >= 0
      && anchor.sourceUTF16Offset <= documentLength
      && Number.isSafeInteger(anchor.blockUTF16LowerBound)
      && Number.isSafeInteger(anchor.blockUTF16UpperBound)
      && anchor.blockUTF16LowerBound >= 0
      && anchor.blockUTF16LowerBound <= anchor.sourceUTF16Offset
      && anchor.blockUTF16UpperBound >= anchor.sourceUTF16Offset
      && anchor.blockUTF16UpperBound <= documentLength;
    if (!valid) {
      this.setScrollFraction(anchor.fallbackFraction);
      return;
    }
    const documentSnapshot = editor.state.doc;
    const relativePosition = Math.max(0, Math.min(1, anchor.relativeBlockPosition));
    const blockProbe = anchor.sourceUTF16Offset === anchor.blockUTF16LowerBound
      && anchor.blockUTF16UpperBound > anchor.blockUTF16LowerBound
      ? anchor.blockUTF16LowerBound + 1
      : anchor.sourceUTF16Offset;
    const requestedScrollTop = () => {
      // CodeMirror positions at a newline boundary may associate with the
      // preceding line. A validated semantic block range lets restoration
      // probe one UTF-16 unit inside the intended block without changing the
      // authoritative source offset stored in the anchor.
      const block = editor.lineBlockAt(blockProbe);
      return Math.max(0, block.top + block.height * relativePosition - 4);
    };
    const applyMeasuredAnchor = () => {
      if (editor.state.doc !== documentSnapshot) return;
      editor.requestMeasure({
        read: () => editor.state.doc === documentSnapshot ? requestedScrollTop() : null,
        write: (scrollTop) => {
          if (scrollTop === null || editor.state.doc !== documentSnapshot) return;
          editor.scrollDOM.scrollTop = scrollTop;
          postCurrentScrollPosition();
        },
      });
    };
    const applyScrollEffect = () => {
      if (editor.state.doc !== documentSnapshot) return;
      editor.dispatch({
        effects: EditorView.scrollIntoView(blockProbe, {y: "start", yMargin: 4}),
      });
    };
    // `lineBlockAt` supplies estimated geometry even while the retained
    // WebView is offscreen, so restore immediately. A measured pass and a
    // local-font-ready pass then correct any line-box change without allowing
    // a late callback to target a replacement document.
    editor.scrollDOM.scrollTop = requestedScrollTop();
    postCurrentScrollPosition();
    applyScrollEffect();
    applyMeasuredAnchor();
    void document.fonts.ready.then(applyMeasuredAnchor);
    window.requestAnimationFrame(() => {
      applyScrollEffect();
      applyMeasuredAnchor();
    });
    window.setTimeout(() => {
      applyScrollEffect();
      applyMeasuredAnchor();
    }, 80);
  },

  synchronizeCommittedText(expectedText: string, committedText: string, startingFingerprint: string) {
    if (exactSource !== expectedText
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
    exactSource = committedText;
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
    hidePreview();
    editor.contentDOM.blur();
  },
};

webkitWindow.scholiumEditor = {
  dispatch: dispatchEditorRequest,
  resolveLinkCompletionQuery,
};

recordEditorMetric("startup", editorStartupStartedAt, {documentLength: editor.state.doc.length});
post({ type: "ready" });
