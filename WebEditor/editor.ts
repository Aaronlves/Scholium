import {
  Annotation,
  Compartment,
  EditorSelection,
  EditorState,
  Facet,
  Prec,
  Range,
  RangeSet,
  StateEffect,
  StateField,
  Text,
  Transaction,
} from "@codemirror/state";
import {
  Decoration,
  DecorationSet,
  EditorView,
  GutterMarker,
  ViewPlugin,
  WidgetType,
  ViewUpdate,
  drawSelection,
  dropCursor,
  gutterLineClass,
  highlightSpecialChars,
  keymap,
  lineNumbers,
  rectangularSelection,
} from "@codemirror/view";
import {
  bidiIsolates,
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
  closeBrackets,
  closeBracketsKeymap,
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
import {
  applySourceChanges,
  toggledTaskMarker,
  transformMarkdown,
} from "./transformations";
import {continueCallout, continueList, indentList} from "./interaction";
import {tableTabAction} from "./tables";
import {decodeClipboardPayload, isSingleSafeURL, pasteAsMarkdown} from "./clipboard";
import {linkTargetAt} from "./projection";
import {scholiumNoteLanguage} from "./language";
import {
  boundedProjectionRanges,
  boundedLinePrefix,
  rangeKey,
  type SemanticInlineProjection,
} from "./semantic-projection";
import {
  activeProjectionSignature,
  selectionAffectedProjectionRanges,
  selectionActivatesCallout,
  selectionIntersectsProjection,
  selectionProjectionSignature,
  transactionChangedSyntaxTree,
  type ProjectionSelectionRange,
  type ProjectionSourceRange,
} from "./projection-update";
import {
  ExactSourceMirror,
  frontmatterBodyOffset,
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
import {
  editorPerformanceSamples,
  recordEditorMetric,
  sampleEditorMemory,
  scheduleAfterNextPaint,
} from "./performance";
import {createPreviewPopoverController, populatePreviewDocument} from "./preview-popover";
import {createEditorScrollCoordinator} from "./scroll-coordinator";
import {createEditorContextMenuExtension} from "./context-menu";
import {createEditorInputSuggestions} from "./input-suggestions";
import {
  createSelectionActionsController,
  selectionActionCommands,
  type SelectionActionCommand,
} from "./selection-actions";
import {systemSymbolElement} from "./system-symbols";
import {
  AnimationFrameCoalescer,
  interactionAvailabilitySignature,
} from "./interaction-reporting";
import {
  immutableProjectionRanges,
  projectionRangeAtBoundary,
  projectionRangeContaining,
  projectionRangesIntersecting as rangesIntersecting,
  projectionSelectionOverlaps,
} from "./projection-index";
import type {MathProjection} from "./math";
import {localized, localizedTemplate} from "./localization";
import {
  calloutDefinition as resolveCalloutDefinition,
  calloutHeader,
} from "./callout-presentation";
import {
  vectorLinkSemantics,
} from "./markdown-fragment";
import {validatedLinkPreviews, type LinkPreview, type VectorLinkKind} from "./previews";
import {
  createLiveSelectionController,
  textSelectionPresentation,
} from "./live-selection";
import {createLiveSemanticLayout} from "./live-semantic-layout";
import {createProjectedWidgetRegistry} from "./projected-widget-registry";
import {createLiveMermaidProjection} from "./live-mermaid-projection";
import {createLiveStructuredBlockProjections} from "./live-structured-block-projections";
import {createLiveDisplayMathProjection} from "./live-display-math-projection";
import {createLiveFootnoteProjection} from "./live-footnote-projection";
import {sourceTextDirection} from "./source-direction";
import {
  createLiveProjectionIndexController,
  type SemanticCodeBlockRange,
} from "./live-projection-index";
import {
  clearDocumentFind,
  documentFindExtension,
  performDocumentFind,
} from "./document-find";

const editorStartupStartedAt = performance.now();

interface ScholiumWindow extends Window {
  webkit?: { messageHandlers?: { scholium?: { postMessage(message: unknown): void } } };
  scholiumEditor?: ScholiumEditorAPI;
  scholiumPerformanceMetric?: "editor_key_to_paint" | "editor_cached_preview"
    | "editor_visible_projection";
}
interface SourceDelta { from: number; to: number; insert: string }
interface WikilinkPresentation { displayStart: number; displayEnd: number; isLegacyRelationship: boolean }
interface ScholiumEditorAPI {
  dispatch(request: unknown): Promise<EditorCommandResult>;
  resolveLinkCompletionQuery(requestID: string, candidates: unknown): void;
  refreshMathRuntime(): boolean;
}

const webkitWindow = window as ScholiumWindow;
const nativeHandler = webkitWindow.webkit?.messageHandlers?.scholium;
let bridgeSessionID = "";
let bridgeDocumentID = "";
let bridgeFingerprint = "";
let documentVersion = 0;
const exactSourceMirror = new ExactSourceMirror();
let linkPreviews: LinkPreview[] = [];
let linkPreviewIndexByRange = new Map<string, number>();
let editingDialect: MarkdownEditingDialect | null = null;
const liveProjectionIndex = createLiveProjectionIndexController({
  editingDialect: () => editingDialect,
  recordMetric: recordEditorMetric,
});
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

function postConfiguredPerformanceSample(
  metric: "editor_cached_preview" | "editor_visible_projection",
  durationMilliseconds: number,
) {
  if (webkitWindow.scholiumPerformanceMetric !== metric
      || !Number.isFinite(durationMilliseconds)
      || durationMilliseconds <= 0) return;
  post({type: "performanceSample", metric, durationMilliseconds});
}

let mermaidRuntimePromise: Promise<NonNullable<typeof window.scholiumMermaid> | null> | null = null;

function ensureMermaidRuntime() {
  const current = window.scholiumMermaid;
  if (current?.version === 2) return Promise.resolve(current);
  if (!nativeHandler) return Promise.resolve(null);
  if (mermaidRuntimePromise) return mermaidRuntimePromise;
  mermaidRuntimePromise = new Promise((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timeout);
      window.scholiumMermaidRuntimeDidLoad = undefined;
      const loaded = window.scholiumMermaid;
      if (loaded?.version !== 2) mermaidRuntimePromise = null;
      resolve(loaded?.version === 2 ? loaded : null);
    };
    const timeout = window.setTimeout(finish, 8_000);
    window.scholiumMermaidRuntimeDidLoad = finish;
    post({type: "requestMermaidRuntime"});
  });
  return mermaidRuntimePromise;
}

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
const refreshMermaidThemeEffect = StateEffect.define<number>();
let mermaidThemeRevision = 0;

function configuredEditorMode(state: EditorState): EditorMode {
  return state.facet(editorModeFacet);
}

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

function calloutDefinition(rawKind: string) {
  return resolveCalloutDefinition(editingDialect, rawKind);
}

class ListMarkerWidget extends WidgetType {
  readonly marker: string;
  readonly markerFrom: number;
  readonly markerTo: number;
  readonly ordered: boolean;
  readonly depth: number;
  readonly task: boolean;
  readonly taskMarkerFrom: number | null;
  readonly taskMarkerTo: number | null;
  readonly taskChecked: boolean;
  constructor(
    marker: string,
    markerFrom: number,
    markerTo: number,
    ordered: boolean,
    depth: number,
    task: boolean,
    taskMarkerFrom: number | null,
    taskMarkerTo: number | null,
    taskChecked: boolean,
  ) {
    super();
    this.marker = marker;
    this.markerFrom = markerFrom;
    this.markerTo = markerTo;
    this.ordered = ordered;
    this.depth = depth;
    this.task = task;
    this.taskMarkerFrom = taskMarkerFrom;
    this.taskMarkerTo = taskMarkerTo;
    this.taskChecked = taskChecked;
  }
  eq(other: ListMarkerWidget) {
    return other.marker === this.marker
      && other.markerFrom === this.markerFrom
      && other.markerTo === this.markerTo
      && other.ordered === this.ordered
      && other.depth === this.depth
      && other.task === this.task
      && other.taskMarkerFrom === this.taskMarkerFrom
      && other.taskMarkerTo === this.taskMarkerTo
      && other.taskChecked === this.taskChecked;
  }
  toDOM(view: EditorView) {
    const span = document.createElement("span");
    span.className = [
      "cm-live-list-marker",
      this.ordered ? "cm-live-list-marker-ordered" : "cm-live-list-marker-unordered",
      this.task ? "cm-live-list-marker-task" : "",
    ].filter(Boolean).join(" ");
    const indent = listIndent(this.depth);
    if (indent) span.style.marginInlineStart = indent;
    const projected = this.task
      ? this.taskCheckbox(view)
      : document.createElement("span");
    projected.classList.add("cm-live-list-marker-projected");
    if (!this.task) {
      projected.textContent = this.ordered ? this.marker : this.depth > 0 ? "◦" : "•";
      span.addEventListener("mousedown", (event) => {
        if (event.button !== 0 || view.composing) return;
        event.preventDefault();
        event.stopPropagation();
        if (this.markerFrom < 0 || this.markerTo <= this.markerFrom
            || this.markerTo > view.state.doc.length) return;
        view.dispatch({
          selection: {anchor: this.markerFrom},
          scrollIntoView: true,
        });
        view.focus();
      });
    }
    span.append(projected);
    if (!this.task) span.setAttribute("aria-hidden", "true");
    return span;
  }

  private taskCheckbox(view: EditorView) {
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.className = "cm-live-task-checkbox";
    checkbox.checked = this.taskChecked;
    checkbox.tabIndex = -1;
    checkbox.setAttribute("aria-label", localized("Task item"));
    checkbox.addEventListener("mousedown", (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      event.stopPropagation();
    });
    checkbox.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.toggleTask(view);
    });
    return checkbox;
  }

  private toggleTask(view: EditorView) {
    if (view.composing || this.taskMarkerFrom === null || this.taskMarkerTo === null) return;
    const current = view.state.doc.sliceString(this.taskMarkerFrom, this.taskMarkerTo);
    const insert = toggledTaskMarker(current);
    if (insert === null) return;
    view.dispatch({
      changes: {
        from: this.taskMarkerFrom,
        to: this.taskMarkerTo,
        insert,
      },
      annotations: Transaction.userEvent.of("input.scholium.toggleTask"),
    });
    lastUndoLabel = "Toggle Task";
    lastRedoLabel = "Toggle Task";
    view.focus();
  }
  // Let CodeMirror own pointer placement at the exact source marker. If the
  // browser handles selection inside this replacement widget, a single click
  // can start a native DOM selection that spans unrelated projected prose.
  ignoreEvent(event: Event) {
    const target = event.target instanceof Element ? event.target : null;
    if (target?.closest(".cm-live-task-checkbox")) {
      return !(event instanceof MouseEvent) || event.button === 0;
    }
    if (target?.closest(".cm-live-list-marker") && event instanceof MouseEvent) {
      return event.button === 0;
    }
    return false;
  }
}

function listIndent(depth: number) {
  if (depth <= 0) return "";
  return `calc(${Array.from(
    {length: depth},
    () => "var(--scholium-list-indent)",
  ).join(" + ")})`;
}

class VectorLinkIconWidget extends WidgetType {
  readonly kind: VectorLinkKind;
  constructor(kind: VectorLinkKind) { super(); this.kind = kind; }
  eq(other: VectorLinkIconWidget) { return other.kind === this.kind; }
  toDOM() {
    const semantics = vectorLinkSemantics[this.kind];
    const span = systemSymbolElement(
      semantics.symbol,
      `cm-live-vector-icon cm-live-vector-icon-${this.kind.replaceAll("_", "-")}`,
    );
    span.title = semantics.label;
    return span;
  }
  // Let CodeMirror place the caret at this replacement when it is clicked so
  // the exact source marker becomes available for editing immediately.
  ignoreEvent() { return false; }
}

class EmbeddedNoteWidget extends WidgetType {
  readonly preview: LinkPreview;
  readonly target: string;
  readonly sourceCaret: number;

  constructor(preview: LinkPreview, target: string, sourceCaret: number) {
    super();
    this.preview = preview;
    this.target = target;
    this.sourceCaret = sourceCaret;
  }

  eq(other: EmbeddedNoteWidget) {
    return other.target === this.target
      && other.sourceCaret === this.sourceCaret
      && other.preview.title === this.preview.title
      && other.preview.htmlBody === this.preview.htmlBody;
  }

  toDOM() {
    const shell = document.createElement("section");
    shell.className = "scholium-embedded-note cm-live-embedded-note-widget";
    shell.dataset.scholiumProtected = "embedded-note";
    shell.dataset.scholiumSourceCaret = String(this.sourceCaret);
    shell.setAttribute("role", "group");
    shell.setAttribute(
      "aria-label",
      localizedTemplate("Embedded note {title}", {title: this.preview.title}),
    );

    const header = document.createElement("header");
    header.className = "scholium-embedded-note-header";
    const open = document.createElement("span");
    open.className = "cm-live-vector-link cm-live-vector-neutral scholium-embedded-note-open";
    open.dir = "auto";
    open.dataset.scholiumLinkTarget = this.target;
    open.dataset.scholiumSourceCaret = String(this.sourceCaret);
    open.setAttribute(
      "aria-label",
      localizedTemplate("Open embedded note {title}", {title: this.preview.title}),
    );
    open.append(document.createTextNode(this.preview.title));
    header.append(open);

    const viewport = document.createElement("div");
    viewport.className = "scholium-embedded-note-viewport";
    viewport.tabIndex = 0;
    viewport.setAttribute("role", "region");
    viewport.setAttribute(
      "aria-label",
      localizedTemplate("Embedded note content for {title}", {title: this.preview.title}),
    );
    const body = document.createElement("div");
    body.className = "scholium-embedded-note-body scholium-document";
    populatePreviewDocument(body, this.preview);
    viewport.append(body);
    shell.append(header, viewport);
    return shell;
  }

  ignoreEvent(event: Event) {
    const target = event.target instanceof Element ? event.target : null;
    if (target?.closest(".scholium-embedded-note-viewport")) return true;
    return event.type !== "mousedown";
  }
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
    if (runtime?.version !== 1) post({type: "requestMathRuntime"});
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
      element.setAttribute(
        "aria-label",
        localized("Mathematics could not be rendered. Source is shown."),
      );
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

function selectionAffectedProjectionAndCodeBlockRanges(
  state: EditorState,
  previousSelections: readonly ProjectionSelectionRange[],
  nextSelections: readonly ProjectionSelectionRange[],
) {
  const changedCodeBlocks = liveProjectionIndex.index(state).literals.codeBlocks.filter((block) => {
    const wasActive = previousSelections.some((selection) =>
      selectionIntersectsProjection(selection, block));
    const isActive = nextSelections.some((selection) =>
      selectionIntersectsProjection(selection, block));
    return wasActive !== isActive;
  });
  return immutableProjectionRanges([
    ...selectionAffectedProjectionRanges(
      state.doc.length,
      previousSelections,
      nextSelections,
    ),
    ...changedCodeBlocks,
  ]);
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

function dispatchProjectedPointerSelection(
  view: EditorView,
  event: MouseEvent,
  sourceOffset: number,
) {
  const head = Math.max(0, Math.min(sourceOffset, view.state.doc.length));
  const anchor = event.shiftKey ? view.state.selection.main.anchor : head;
  view.dispatch({
    selection: {anchor, head},
    scrollIntoView: true,
    annotations: Transaction.userEvent.of("select.pointer"),
  });
  view.focus();
}

function modifiedProjectedLink(view: EditorView, event: MouseEvent) {
  if (!event.metaKey && !event.ctrlKey) return false;
  const targetElement = event.target instanceof Element ? event.target : null;
  const fragmentLink = targetElement?.closest<HTMLElement>("[data-scholium-link-target]");
  let target = fragmentLink?.dataset.scholiumLinkTarget?.trim() ?? "";
  const position = view.posAtCoords({x: event.clientX, y: event.clientY});
  if (!target) target = position === null ? "" : linkTargetAt(view.state.doc, position) ?? "";
  if (!target) return false;
  post({type: "linkActivated", target});
  event.preventDefault();
  return true;
}

const projectedWidgets = createProjectedWidgetRegistry();

function projectedWidgetSourceOffset(event: MouseEvent) {
  return projectedWidgets.sourceOffset(event);
}

function projectedWidgetPointerStart(view: EditorView, event: MouseEvent) {
  const sourceOffset = projectedWidgetSourceOffset(event);
  if (sourceOffset === null) return false;
  event.preventDefault();
  dispatchProjectedPointerSelection(view, event, sourceOffset);
  return true;
}

const liveSelection = createLiveSelectionController({
  handleModifiedLink: modifiedProjectedLink,
  handleProjectedPointerStart: projectedWidgetPointerStart,
});

const liveMermaidProjection = createLiveMermaidProjection({
  selection: liveSelection,
  projections: liveProjectionIndex,
  widgets: projectedWidgets,
  ensureRuntime: ensureMermaidRuntime,
  currentThemeRevision: () => mermaidThemeRevision,
  refreshThemeEffect: refreshMermaidThemeEffect,
});
const liveStructuredBlockProjections = createLiveStructuredBlockProjections({
  selection: liveSelection,
  projections: liveProjectionIndex,
  widgets: projectedWidgets,
  editingDialect: () => editingDialect,
  reuseCounts: liveWidgetReuseCounts,
});
const liveDisplayMathProjection = createLiveDisplayMathProjection({
  selection: liveSelection,
  projections: liveProjectionIndex,
  widget: (expression) => new MathWidget(expression),
});
const liveFootnoteProjection = createLiveFootnoteProjection({
  selection: liveSelection,
  projections: liveProjectionIndex,
  widgets: projectedWidgets,
  reuseCounts: liveWidgetReuseCounts,
});

interface LiveInlineProjectionState {
  decorations: DecorationSet;
  atomicRanges: DecorationSet;
  coveredRanges: readonly ProjectionSourceRange[];
}

const liveSemanticLayout = createLiveSemanticLayout({
  selection: liveSelection,
  projections: liveProjectionIndex,
  editingDialect: () => editingDialect,
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
  const index = liveProjectionIndex.index(view.state);
  const projectionSelections = liveSelection.selection(view.state).ranges;
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
  const mathExpressions = liveProjectionIndex.visibleInlineMathExpressions(
    view.state,
    coveredRanges,
    index,
  );

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
  const addPreviewMark = (
    from: number,
    to: number,
    className: string,
    previewIndex: number,
    attributes: Record<string, string> = {},
  ) => {
    if (to <= from) return;
    decorations.push(Decoration.mark({
      class: className,
      attributes: {
        ...attributes,
        "data-link-preview-index": String(previewIndex),
        "data-scholium-protected": "link-preview-anchor",
      },
    }).range(from, to));
  };
  for (const expression of mathExpressions) {
    literals.push({from: expression.from, to: expression.to});
    const activeConstruct = projectionSelections.some((range) =>
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
      const activeLine = projectionSelections.some((range) =>
        range.head >= line.from && range.head <= line.to
        || !range.empty && range.from < lineQueryTo && range.to >= line.from,
      ) || view.composing && projectionSelections.some(
        (range) => range.from < lineQueryTo && range.to >= line.from,
      );
      const inlineConstructIsActive = (from: number, to: number) =>
        projectionSelections.some((range) =>
          selectionIntersectsProjection(range, {from, to}),
        );
      const excluded = [...rangesIntersecting(literals, scanFrom, lineQueryTo)];
      const structuralInlineExclusions: ProjectionSourceRange[] = [];
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
          const codeBlockActive = projectionSelections.some((range) =>
            selectionIntersectsProjection(range, semanticCodeBlock));
          if (fenceLine && !codeBlockActive) {
            addHidden(line.from, line.to);
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
          index.callouts,
          scanFrom,
          lineQueryTo,
        )[0];
        const semanticCallout = semanticBlocksOnLine.find((block) => block.kind === "callout");
        const activeCallout = parsedCallout && projectionSelections.some((range) =>
          selectionActivatesCallout(range, parsedCallout));
        if (activeCallout) {
          const semanticLineMarkers = semanticCallout?.markerRanges.filter((range) =>
            range.from < lineQueryTo && range.to > line.from) ?? [];
          const pendingPrefix = semanticLineMarkers.length === 0
            ? /^\s*>[ \t]*/.exec(doc.sliceString(line.from, line.to))?.[0] ?? ""
            : "";
          const lineMarkers: ProjectionSourceRange[] = semanticLineMarkers.length > 0
            ? semanticLineMarkers
            : pendingPrefix.length > 0
              ? [{from: line.from, to: line.from + pendingPrefix.length}]
              : [];
          // Callout markers remain excluded from inline semantics on every
          // line. Only the line owning the current caret exposes those exact
          // bytes; the rest of the block stays in its Live Preview shell.
          structuralInlineExclusions.push(...lineMarkers);
          if (!activeLine) {
            for (const marker of lineMarkers) {
              let markerTo = Math.min(line.to, marker.to);
              while (markerTo < line.to) {
                const code = doc.sliceString(markerTo, markerTo + 1);
                if (code !== " " && code !== "\t") break;
                markerTo += 1;
              }
              addHidden(Math.max(line.from, marker.from), markerTo);
            }
          }
          if (parsedCallout && parsedCallout.from === line.from) {
            const opening = calloutHeader(doc.sliceString(line.from, line.to));
            const authoredTitle = opening?.[4] ?? "";
            const roleIdentifier = opening
              ? calloutDefinition(opening[2]).identifier
              : "neutral";
            if (roleIdentifier !== "orient" && authoredTitle.length > 0) {
              const titleFrom = line.to - authoredTitle.length;
              addMark(
                Math.max(scanFrom, titleFrom),
                Math.min(scanTo, line.to),
                "scholium-callout-title",
              );
            }
          }
        }
        const quote = semanticBlocksOnLine.find((block) => block.kind === "blockQuote");
        if (quote && !parsedCallout) {
          if (!activeLine) {
            for (const marker of quote.markerRanges.filter((range) =>
              range.from < lineQueryTo && range.to > line.from)) {
              addHidden(Math.max(line.from, marker.from), Math.min(line.to, marker.to));
            }
          }
        }
        // Nested inline constructs retain their ordinary construct-scoped
        // projection. Activating a Callout is never a second all-source mode.

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
          const listDepth = list.listDepth ?? 0;
          const task = list.taskMarkerRange !== null;
          // Review parses task brackets as ListItem metadata rather than
          // prose. Keep the projected marker while the caret edits item prose;
          // reveal the exact prefix only when the selection reaches that
          // prefix. Both presentations use one fixed semantic marker track;
          // exact source hangs toward the start edge rather than moving prose.
          const listPrefix = rangesIntersecting(
            index.listPrefixRanges,
            line.from,
            lineQueryTo,
          ).find((range) => range.from <= listMarker.from && range.to >= listMarker.to);
          const replacementFrom = listPrefix?.from ?? listMarker.from;
          const replacementTo = listPrefix?.to
            ?? (task ? list.taskMarkerRange!.to : listMarker.to);
          const prefixIsActive = projectionSelections.some((range) =>
            selectionIntersectsProjection(range, {from: replacementFrom, to: replacementTo}));
          if (prefixIsActive) {
            const className = [
              "cm-live-list-source-prefix",
            ].join(" ");
            const indent = listIndent(listDepth);
            const attributes: Record<string, string> = {class: className};
            if (indent) attributes.style = `margin-inline-start: ${indent}`;
            const range = Decoration.mark({attributes}).range(replacementFrom, replacementTo);
            decorations.push(range);
          } else {
            const taskMarkerSource = list.taskMarkerRange
              ? doc.sliceString(list.taskMarkerRange.from, list.taskMarkerRange.to)
              : "";
            addAtomicReplacement(
              Decoration.replace({
                widget: new ListMarkerWidget(
                  marker,
                  listMarker.from,
                  listMarker.to,
                  ordered,
                  listDepth,
                  task,
                  list.taskMarkerRange?.from ?? null,
                  list.taskMarkerRange?.to ?? null,
                  /^\[[xX]\]$/.test(taskMarkerSource),
                ),
              }),
              replacementFrom,
              replacementTo,
            );
          }
        }

        const parsedTable = rangesIntersecting(
          parsedProjection.tables,
          scanFrom,
          lineQueryTo,
        )[0];
        const activeTable = parsedTable && projectionSelections.some((range) =>
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
              || overlaps(excluded, construct.from, construct.to)
              || overlaps(structuralInlineExclusions, construct.from, construct.to)) continue;
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
          const previewIndex = linkPreviewIndexByRange.get(rangeKey(construct.from, construct.to));
          const preview = previewIndex === undefined ? undefined : linkPreviews[previewIndex];
          if (embed && preview?.isEmbedded) {
            addAtomicReplacement(
              Decoration.replace({
                widget: new EmbeddedNoteWidget(preview, target, construct.to),
              }),
              construct.from,
              construct.to,
            );
            continue;
          }
          addHidden(construct.from, targetRange.from);

          const linkClass = embed
            ? "cm-live-embed"
            : presentation.isLegacyRelationship && kind === "neutral"
              ? "cm-live-vector-link cm-live-vector-neutral cm-live-vector-legacy"
              : `cm-live-vector-link cm-live-vector-${kind.replaceAll("_", "-")}`;
          const projectedLinkAttributes = {
            "data-scholium-link-target": target,
            "data-scholium-source-caret": String(construct.to),
            ...(embed ? {} : {
              "aria-label": `${vectorLinkSemantics[kind].label} ${alias || target}`,
            }),
          };
          addHidden(targetRange.from, presentation.displayStart);
          if (previewIndex === undefined) {
            decorations.push(Decoration.mark({
              class: linkClass,
              attributes: projectedLinkAttributes,
            }).range(presentation.displayStart, presentation.displayEnd));
          } else {
            addPreviewMark(
              presentation.displayStart,
              presentation.displayEnd,
              linkClass,
              previewIndex,
              projectedLinkAttributes,
            );
          }
          if (!embed) {
            decorations.push(Decoration.widget({
              widget: new VectorLinkIconWidget(kind),
              side: -1,
            }).range(presentation.displayEnd));
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
          if (overlaps(structuralInlineExclusions, construct.from, construct.to)) continue;
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
    } else if (liveSelection.changed(update.startState, update.state)) {
      const projectionIndex = liveProjectionIndex.index(update.state);
      const inlineRanges = projectionIndex.inlineRanges;
      const codeBlockActivationUnchanged = activeProjectionSignature(
        liveSelection.selection(update.startState).ranges,
        projectionIndex.literals.codeBlocks,
      ) === activeProjectionSignature(
        liveSelection.selection(update.state).ranges,
        projectionIndex.literals.codeBlocks,
      );
      if (!update.view.composing
          && codeBlockActivationUnchanged
          && selectionProjectionSignature(
            update.startState.doc,
            liveSelection.selection(update.startState).ranges,
            inlineRanges,
            projectionIndex.listPrefixRanges,
          ) === selectionProjectionSignature(
            update.state.doc,
            liveSelection.selection(update.state).ranges,
            inlineRanges,
            projectionIndex.listPrefixRanges,
          )) {
        return;
      }
      const affected = selectionAffectedProjectionAndCodeBlockRanges(
        update.state,
        liveSelection.selection(update.startState).ranges,
        liveSelection.selection(update.state).ranges,
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
      localized("Edit mode is unavailable because YAML frontmatter is not closed. Use Source mode to finish the frontmatter."),
    );

    const title = document.createElement("strong");
    title.textContent = localized("Edit mode unavailable");
    const detail = document.createElement("span");
    detail.textContent = localized(
      "Close the YAML frontmatter in Source mode to restore the visual projection.",
    );
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
  const index = liveProjectionIndex.index(state);
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

let dirty = false;
let pendingKeyDownStartedAt: number | null = null;
let pendingCommittedKeyStartedAt: number | null = null;
let pendingInputStartedAt: {startedAt: number; composing: boolean} | null = null;
let forceNextInteractionContext = true;
let lastInteractionAvailabilitySignature: string | null = null;
const interactionReporter = new AnimationFrameCoalescer(
  (callback) => window.requestAnimationFrame(callback),
  (identifier) => window.cancelAnimationFrame(identifier),
  (callback, delayMilliseconds) => window.setTimeout(callback, delayMilliseconds),
  (identifier) => window.clearTimeout(identifier),
);
/** @type {number | null} */

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
    const input = pendingInputStartedAt;
    pendingInputStartedAt = null;
    if (input !== null) {
      recordEditorMetric("input-to-state", input.startedAt, {
        composing: input.composing ? 1 : 0,
        documentLength: update.state.doc.length,
      });
    }
    const keyStartedAt = pendingCommittedKeyStartedAt;
    pendingCommittedKeyStartedAt = null;
    if (keyStartedAt !== null) {
      recordEditorMetric("key-to-state", keyStartedAt, {documentLength: update.state.doc.length});
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
        message: localized("The editor could not preserve the exact source line endings."),
      });
      return;
    }
    recordEditorMetric("exact-source-update", exactUpdateStartedAt, {
      changeCount: mirrorChanges.length,
      documentLength: update.state.doc.length,
    });
    // Register the paint endpoint before handing the delta to native
    // reconciliation. Messages remain ordered because documentChanged posts in
    // this task and the performance sample cannot post until a later frame and
    // task.
    if (input !== null || keyStartedAt !== null) {
      const paintedSessionID = bridgeSessionID;
      const paintedDocumentID = bridgeDocumentID;
      const paintedFingerprint = bridgeFingerprint;
      const paintedDocumentVersion = documentVersion;
      const paintedDocumentLength = update.state.doc.length;
      scheduleAfterNextPaint(() => {
        if (input !== null) {
          recordEditorMetric("input-to-paint", input.startedAt, {
            composing: input.composing ? 1 : 0,
            documentLength: paintedDocumentLength,
          });
        }
        if (keyStartedAt !== null) {
          recordEditorMetric("key-to-paint", keyStartedAt, {
            documentLength: paintedDocumentLength,
          });
        }
        // CodeMirror may commit deletion directly from keydown, while macOS
        // text services may commit text without a DOM keydown. Prefer the
        // physical-key boundary and fall back to non-composing beforeinput.
        const committedKeyStartedAt = keyStartedAt
          ?? (input !== null && !input.composing ? input.startedAt : null);
        if (committedKeyStartedAt !== null
            && webkitWindow.scholiumPerformanceMetric === "editor_key_to_paint"
            && bridgeSessionID === paintedSessionID
            && bridgeDocumentID === paintedDocumentID
            && bridgeFingerprint === paintedFingerprint
            && documentVersion === paintedDocumentVersion) {
          post({
            type: "performanceSample",
            metric: "editor_key_to_paint",
            durationMilliseconds: Math.max(0, performance.now() - committedKeyStartedAt),
          });
        }
      });
    }
    post({ type: "documentChanged", baseGeneration, resultingGeneration: documentVersion, changes });
  }

  scheduleEditorInteractionReport();

});

const linkActivation = EditorView.domEventHandlers({
  click(event) {
    if (event.metaKey || event.ctrlKey) {
      const targetElement = event.target instanceof Element ? event.target : null;
      const fragmentTarget = targetElement
        ?.closest<HTMLElement>("[data-scholium-link-target]")
        ?.dataset.scholiumLinkTarget;
      const position = editor.posAtCoords({x: event.clientX, y: event.clientY});
      const target = fragmentTarget?.trim()
        || (position === null ? null : linkTargetAt(editor.state.doc, position));
      if (target) {
        // Edit's high-priority pointer owner already activated this link on
        // mouse-down so CodeMirror never starts a selection gesture. Source
        // has no Live projection pointer owner and activates on the ordinary
        // click boundary here.
        if (configuredEditorMode(editor.state) !== "livePreview") {
          post({type: "linkActivated", target});
        }
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
      post({type: "requestDocumentFind", action: "present"});
      return true;
    },
  },
  {
    key: "Mod-g",
    preventDefault: true,
    run: () => {
      post({type: "requestDocumentFind", action: "next"});
      return true;
    },
  },
  {
    key: "Shift-Mod-g",
    preventDefault: true,
    run: () => {
      post({type: "requestDocumentFind", action: "previous"});
      return true;
    },
  },
  {
    key: "Mod-e",
    preventDefault: true,
    run: () => {
      post({type: "requestDocumentFind", action: "useSelection"});
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
    run: (view) => {
      const selections = editorSelections(view.state);
      return applyInteraction(
        (configuredEditorMode(view.state) === "livePreview"
          ? continueCallout(view.state.doc, selections)
          : null)
          ?? continueList(view.state.doc, selections),
        "input.scholium.continueStructure",
      );
    },
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

function liveNavigationBlockRanges(state: EditorState) {
  return [
    ...liveProjectionIndex.index(state).blockRanges,
    ...liveMermaidProjection.presentations(state).map(({from, to}) => ({
      from,
      to,
      kind: "mermaid" as const,
    })),
  ].sort((left, right) => left.from - right.from || left.to - right.to);
}

function liveHorizontalNavigationRangeAt(
  state: EditorState,
  offset: number,
  forward: boolean,
) {
  const index = liveProjectionIndex.index(state);
  const boundary = forward ? "start" : "end";
  const blockRange = projectionRangeAtBoundary(index.blockRanges, offset, boundary);
  const listPrefixRange = projectionRangeAtBoundary(
    index.listPrefixRanges,
    offset,
    boundary,
  );
  const mermaidRange = projectionRangeAtBoundary(
    liveMermaidProjection.presentations(state),
    offset,
    boundary,
  );
  const inlineLinkRange = projectionRangeAtBoundary(
    index.syntax.inlines.filter((candidate) =>
      candidate.kind === "wikilink" || candidate.kind === "vectorLink"),
    offset,
    boundary,
  );
  const candidates = [
    blockRange,
    listPrefixRange ? {...listPrefixRange, kind: "listPrefix" as const} : null,
    mermaidRange ? {...mermaidRange, kind: "mermaid" as const} : null,
    inlineLinkRange,
  ].filter((candidate) => candidate !== null);
  return candidates.sort((left, right) =>
    left.from - right.from || left.to - right.to,
  )[0] ?? null;
}

function revealProjectedBlockForVerticalMove(
  view: EditorView,
  forward: boolean,
  extend: boolean,
) {
  if (configuredEditorMode(view.state) !== "livePreview" || view.composing) return false;
  const selection = view.state.selection.main;
  const moved = view.moveVertically(selection, forward);
  const crossed = rangesIntersecting(
    liveNavigationBlockRanges(view.state),
    Math.min(selection.head, moved.head),
    Math.max(selection.head, moved.head) + 1,
  ).filter((candidate) => {
    const alreadyActive = view.state.selection.ranges.some((range) => candidate.kind === "callout"
      ? selectionActivatesCallout(range, candidate)
      : selectionIntersectsProjection(range, candidate));
    if (alreadyActive) return false;
    return forward
      ? selection.head <= candidate.from && moved.head >= candidate.to
      : selection.head >= candidate.to && moved.head <= candidate.from;
  });
  const projection = forward ? crossed[0] : crossed.at(-1);
  if (!projection) return false;

  const isCallout = projection.kind === "callout";
  const sourceHead = forward
    ? projection.from
    : isCallout ? projection.to : Math.max(projection.from, projection.to - 1);
  const originalCoords = view.coordsAtPos(selection.head);
  const desiredX = originalCoords?.left ?? originalCoords?.right ?? 0;
  const anchor = extend ? selection.anchor : sourceHead;
  view.dispatch({
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
  const projection = liveHorizontalNavigationRangeAt(
    view.state,
    selection.head,
    forward,
  );
  if (!projection) return false;
  const alreadyActive = projection.kind === "callout"
    ? selectionActivatesCallout(selection, projection)
    : selectionIntersectsProjection(selection, projection);
  const isProjectedLink = projection.kind === "wikilink" || projection.kind === "vectorLink";
  // The start boundary is ordinarily considered part of an inline construct.
  // For a projected Wikilink, however, the first forward keyboard move treats
  // the visible link as one object and lands after `]]`. A following backward
  // move from that exact end still enters the authored closing syntax.
  if (alreadyActive && !(isProjectedLink && forward && selection.head === projection.from)) {
    return false;
  }
  const head = forward
    ? isProjectedLink ? projection.to : projection.from
    : projection.kind === "callout" ? projection.to : Math.max(projection.from, projection.to - 1);
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
  requestImportImage: () => post({type: "requestImportImage"}),
  requestIndexImage: () => post({type: "requestIndexImage"}),
  selectionForPresentation: (view) => liveSelection.selection(view.state),
  presentationInteractionChanged: (update) => liveSelection.interactionChanged(
    update.startState,
    update.state,
  ),
  pointerSelectionIsComplete: (view) => liveSelection.pointerSelectionIsComplete(view.state),
  selectionIsAvailable: (view) => !view.state.selection.ranges.some((selection) =>
    projectionSelectionOverlaps(protectedCommandRanges(), selection)),
});

const previewPopover = createPreviewPopoverController({
  previews: () => linkPreviews,
  postPerformanceSample: postConfiguredPerformanceSample,
});

const sourceActiveLineDecoration = Decoration.line({class: "cm-activeLine"});
class SourceActiveLineGutterMarker extends GutterMarker {
  elementClass = "cm-activeLineGutter";
}
const sourceActiveLineGutterMarker = new SourceActiveLineGutterMarker();

function collapsedSelectionLineStarts(state: EditorState) {
  return state.selection.ranges
    .filter((range) => range.empty)
    .map((range) => state.doc.lineAt(range.head).from)
    .filter((lineStart, index, lineStarts) => lineStarts.indexOf(lineStart) === index)
    .sort((left, right) => left - right);
}

// A non-empty Source selection can end immediately after a line break (for
// example after a triple-click). That endpoint belongs to the selection, not
// to an active caret on the following logical line.
const sourceCollapsedActiveLine = [
  EditorView.decorations.compute(["selection"], (state) => Decoration.set(
    collapsedSelectionLineStarts(state).map((lineStart) =>
      sourceActiveLineDecoration.range(lineStart)),
  )),
  gutterLineClass.compute(["selection"], (state) => RangeSet.of(
    collapsedSelectionLineStarts(state).map((lineStart) =>
      sourceActiveLineGutterMarker.range(lineStart)),
  )),
];

const inputSuggestions = createEditorInputSuggestions({
  mode: configuredEditorMode,
  dialect: () => editingDialect,
  isComposing: () => editor.composing,
  protectedRanges: protectedCommandRanges,
  requestLinkCompletions: (requestID, completionKind, query) => {
    post({type: "linkCompletionQuery", requestID, completionKind, query});
  },
  didApply: (undoLabel) => {
    lastUndoLabel = undoLabel;
    lastRedoLabel = undoLabel;
  },
});

// One CodeMirror compartment is the complete presentation-mode boundary.
// Source contains no Live Preview state field, view plugin, widget provider,
// navigation keymap, formatting overlay, preview overlay, or semantic class.
const livePreviewMode = [
  editorModeFacet.of("livePreview"),
  EditorView.editorAttributes.of({class: "scholium-live-mode"}),
  EditorView.contentAttributes.of(editorAccessibilityAttributes("livePreview")),
  Prec.high(liveSelection.extension),
  liveProjectionIndex.extension,
  inputSuggestions.extension,
  liveSemanticLayout.extension,
  liveFrontmatterGuardField,
  liveMermaidProjection.extension,
  liveStructuredBlockProjections.tableExtension,
  liveDisplayMathProjection.extension,
  liveStructuredBlockProjections.rawHTMLExtension,
  liveStructuredBlockProjections.calloutExtension,
  liveFootnoteProjection.extension,
  livePreview,
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
  sourceCollapsedActiveLine,
  foldGutter(),
  sourceTextDirection,
  EditorView.lineWrapping,
];
const editorContextMenu = createEditorContextMenuExtension({
  context: (view) => currentEditorContext(view),
  mode: (view) => configuredEditorMode(view.state),
  positionAtEvent: (view, event) => projectedWidgetSourceOffset(event)
    ?? view.posAtCoords({x: event.clientX, y: event.clientY}),
  request: (request) => post({type: "contextMenuRequested", ...request}),
});

const editorExtensions = [
      highlightSpecialChars(),
      history(),
      drawSelection({drawRangeCursor: false}),
      textSelectionPresentation,
      dropCursor(),
      EditorState.allowMultipleSelections.of(true),
      indentOnInput(),
      bidiIsolates(),
      closeBrackets(),
      rectangularSelection(),
      EditorView.perLineTextDirection.of(true),
      // Share Markdown's high precedence while preceding its generic list
      // continuation. Scholium must compose the Callout quote and nested list
      // prefixes before the base Markdown command can consume Return.
      Prec.high(structuralInteractionKeymap),
      scholiumNoteLanguage,
      keymap.of([
        ...closeBracketsKeymap,
        ...defaultKeymap,
        ...historyKeymap,
        ...foldKeymap,
      ]),
      saveKeymap,
      documentFindExtension,
      editorContextMenu,
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
editor.contentDOM.addEventListener("keydown", (event) => {
  const key = event.key;
  const canCommitText = !event.isComposing
    && !event.metaKey
    && !event.ctrlKey
    && !event.altKey
    && (key.length === 1 || key === "Backspace" || key === "Delete" || key === "Enter");
  pendingKeyDownStartedAt = canCommitText ? performance.now() : null;
  pendingCommittedKeyStartedAt = pendingKeyDownStartedAt;
}, {capture: true});
editor.contentDOM.addEventListener("keyup", () => {
  pendingKeyDownStartedAt = null;
  pendingCommittedKeyStartedAt = null;
}, {capture: true});
editor.contentDOM.addEventListener("beforeinput", (event) => {
  const input = event as InputEvent;
  pendingCommittedKeyStartedAt = input.isComposing || editor.composing
    ? null
    : pendingKeyDownStartedAt;
  pendingInputStartedAt = {
    startedAt: performance.now(),
    composing: input.isComposing || editor.composing,
  };
}, {capture: true});
const scrollCoordinator = createEditorScrollCoordinator(editor, {
  post: (scrollAnchor) => post({
    type: "scrollChanged",
    scrollFraction: scrollAnchor.fallbackFraction,
    scrollAnchor,
  }),
  onScroll: () => selectionActions.reposition(editor),
  flushPresentationGeometry: flushPresentationStyleAndGeometry,
});
for (const mediaQuery of [
  matchMedia("(prefers-color-scheme: dark)"),
  matchMedia("(prefers-contrast: more)"),
]) {
  mediaQuery.addEventListener("change", refreshMermaidTheme);
}

const allCommands = [
  ...selectionActionCommands,
  "thematicBreak",
  "calloutOrient", "calloutCite", "calloutConnect", "calloutState", "calloutIllustrate", "calloutQuote", "calloutFlag",
  "insertFootnote", "insertTable", "toggleTask", "tableInsertRowBefore", "tableInsertRowAfter", "tableDeleteRow",
  "tableInsertColumnBefore", "tableInsertColumnAfter", "tableDeleteColumn",
  "tableAlignLeft", "tableAlignCenter", "tableAlignRight", "pastePlain", "pasteMarkdown", "linkSelectedText",
] as const;

function editorSelections(state = editor.state) {
  return state.selection.ranges.map((range) => ({anchor: range.anchor, head: range.head}));
}

function protectedCommandRanges(state = editor.state) {
  return liveProjectionIndex.index(state).commandProtectedRanges;
}

function indexedTablePositionAt(state: EditorState, offset: number) {
  return projectionRangeContaining(
    liveProjectionIndex.index(state).tablePositionRanges,
    offset,
  )?.position;
}

function indexedTaskItemForSelection(
  state: EditorState,
  selection: {from: number; to: number},
) {
  const candidates = rangesIntersecting(
    liveProjectionIndex.index(state).taskItemRanges,
    Math.max(0, selection.from - 1),
    Math.max(selection.from + 1, selection.to + 1),
  );
  return candidates.findLast((range) =>
    selection.from >= range.from && selection.to <= range.to,
  ) ?? null;
}

function currentEditorContext(view = editor): EditorContext {
  const state = view.state;
  const inline = new Set<string>();
  const block = new Set<string>();
  for (const selection of state.selection.ranges) {
    const linePrefix = boundedLinePrefix(state.doc, selection.head);
    for (let node = syntaxTree(state).resolveInner(selection.head, -1); node; node = node.parent!) {
      if (["Emphasis", "StrongEmphasis", "InlineCode", "Link"].includes(node.name)) inline.add(node.name);
      if (["ATXHeading1", "ATXHeading2", "ATXHeading3", "ATXHeading4", "ATXHeading5", "ATXHeading6", "Blockquote", "Callout", "BlockMath", "FootnoteDefinition", "BulletList", "OrderedList", "FencedCode", "Table"].includes(node.name)) block.add(node.name);
      if (!node.parent) break;
    }
    if (calloutHeader(linePrefix)) block.add("Callout");
  }
  const protectedRanges = protectedCommandRanges(state);
  const protectedSelection = state.selection.ranges.some((selection) =>
    projectionSelectionOverlaps(protectedRanges, selection));
  const currentTablePosition = state.selection.ranges.length === 1
    ? indexedTablePositionAt(state, state.selection.main.head)
    : undefined;
  const tableOnlyCommands = new Set([
    "tableInsertRowBefore", "tableInsertRowAfter", "tableDeleteRow",
    "tableInsertColumnBefore", "tableInsertColumnAfter", "tableDeleteColumn",
    "tableAlignLeft", "tableAlignCenter", "tableAlignRight",
  ]);
  const availableCommands = allCommands.filter((command) => {
    if (tableOnlyCommands.has(command)) return currentTablePosition !== undefined;
    if (command === "toggleTask") {
      return state.selection.ranges.every((selection) =>
        indexedTaskItemForSelection(state, selection) !== null);
    }
    if (command === "linkSelectedText") return state.selection.ranges.every((selection) => !selection.empty);
    return true;
  });
  return {
    selections: editorSelections(state),
    activeInlineConstructs: [...inline],
    activeBlockConstructs: [...block],
    tablePosition: currentTablePosition,
    composing: view.composing,
    availableCommands: view.composing || protectedSelection ? [] : availableCommands,
    undoLabel: undoDepth(state) > 0 ? lastUndoLabel || "Undo Editing" : undefined,
    redoLabel: redoDepth(state) > 0 ? lastRedoLabel || "Redo Editing" : undefined,
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
    if (request.knownGeneration !== 0
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
    if (operation.initialSelection) {
      editorOperations.revealSourceRange(
        operation.initialSelection.anchor,
        operation.initialSelection.head,
        false,
      );
    }
    recordEditorMetric("document-load", loadStartedAt, {documentLength: editor.state.doc.length});
    sampleEditorMemory(editor.state.doc.length);
    return successfulResult(request.requestID);
  }
  if (request.sessionID !== bridgeSessionID || request.documentID !== bridgeDocumentID
      || request.startingFingerprint !== bridgeFingerprint) {
    return rejected(request.requestID, documentVersion, "stale editor identity");
  }
  switch (operation.type) {
  case "setMode": await editorOperations.setMode(operation.mode); break;
  case "setPresentationCSS": editorOperations.setPresentationCSS(operation.value); break;
  case "setUserCSS": editorOperations.setUserCSS(operation.value); break;
  case "setLinkPreviews": editorOperations.setLinkPreviews(operation.value); break;
  case "showPreview": previewPopover.showAtSelection(); break;
  case "measureVisibleProjection": {
    const startedAt = performance.now();
    editor.dispatch({effects: refreshLivePreviewEffect.of(null)});
    postConfiguredPerformanceSample(
      "editor_visible_projection",
      // WebKit may quantize two readings around a sub-millisecond synchronous
      // dispatch to the same value. Preserve that real below-clock-resolution
      // observation as a positive sample so the native collector does not
      // mistake it for a missing boundary.
      Math.max(Number.EPSILON, performance.now() - startedAt),
    );
    break;
  }
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
  case "acknowledgeCommittedSnapshot": {
    if (new TextEncoder().encode(operation.committedText).byteLength > MAX_SOURCE_UTF8_BYTES) {
      return rejected(request.requestID, documentVersion, "committed source is too large");
    }
    const superseded = editorOperations.acknowledgeCommittedSnapshot(
      operation.expectedText, operation.committedText, operation.committedFingerprint,
    );
    if (superseded === null) {
      return rejected(request.requestID, documentVersion, "editor source did not reconcile");
    }
    return {
      ...successfulResult(request.requestID),
      text: exactEditorSource(),
      commitSuperseded: superseded,
    };
  }
  case "command": {
    const argument = operation.command === "pasteMarkdown"
      ? pasteAsMarkdown(decodeClipboardPayload(operation.argument))
      : operation.argument;
    const transformed = transformMarkdown(editor.state.doc.toString(), editorSelections(), operation.command, {
      argument,
      protectedRanges: protectedCommandRanges(),
      taskItems: liveProjectionIndex.index(editor.state).taskItemRanges,
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
  case "documentFind": {
    const result = performDocumentFind(editor, operation.value);
    if (result.undoLabel) {
      lastUndoLabel = result.undoLabel;
      lastRedoLabel = result.undoLabel;
    }
    return {
      ...successfulResult(request.requestID, result.sourceChanged, result.undoLabel),
      find: {current: result.current, total: result.total},
    };
  }
  case "clearDocumentFind": clearDocumentFind(editor); break;
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

function pasteTransfer(
  transfer: DataTransfer,
  dropPosition?: number,
  requestNativeImageImport = false,
) {
  if (Array.from(transfer.files).length > 0
      || Array.from(transfer.items).some((item) => item.kind === "file")) {
    const image = Array.from(transfer.files).some((file) => file.type.startsWith("image/"))
      || Array.from(transfer.items).some((item) =>
        item.kind === "file" && item.type.startsWith("image/"));
    if (requestNativeImageImport && image) {
      post({type: "requestImagePaste"});
      return true;
    }
    announceEditorMessage(editor.contentDOM, unsupportedFilePasteMessage());
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
  if (pasteTransfer(event.clipboardData, undefined, true)) event.preventDefault();
}, {capture: true});
editor.contentDOM.addEventListener("drop", (event) => {
  if (!event.dataTransfer) return;
  const position = editor.posAtCoords({x: event.clientX, y: event.clientY});
  if (pasteTransfer(event.dataTransfer, position ?? undefined)) event.preventDefault();
}, {capture: true});

function refreshMermaidTheme() {
  mermaidThemeRevision += 1;
  if (configuredEditorMode(editor.state) === "livePreview") {
    editor.dispatch({effects: refreshMermaidThemeEffect.of(mermaidThemeRevision)});
  }
}

function setDynamicStyle(id: string, css: string) {
  const style = document.getElementById(id);
  if (!style || style.textContent === css) return false;
  style.textContent = css;
  scrollCoordinator.scheduleGeometryReport();
  void document.fonts.ready.then(scrollCoordinator.scheduleGeometryReport);
  return true;
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
    ".cm-live-mermaid-widget",
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
    if (setDynamicStyle("scholium-presentation-css", css)) refreshMermaidTheme();
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
  revealSourceRange(
    requestedFromUTF16: number,
    requestedToUTF16: number,
    focusesEditor = true,
  ) {
    const documentLength = editor.state.doc.length;
    const from = Math.max(0, Math.min(Math.trunc(requestedFromUTF16), documentLength));
    const to = Math.max(from, Math.min(Math.trunc(requestedToUTF16), documentLength));
    // An explicit native locator supersedes any pre-clamp Source selection
    // retained while entering Live Preview. Restoring that older selection on
    // a later Source request would move managed New Note back into its YAML.
    hiddenFrontmatterSourceSelection = null;
    editor.dispatch({
      selection: EditorSelection.single(from, to),
      effects: EditorView.scrollIntoView(EditorSelection.range(from, to), {y: "center"}),
      annotations: Transaction.addToHistory.of(false),
    });
    if (focusesEditor) editor.focus();
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

  acknowledgeCommittedSnapshot(expectedText: string, committedText: string, startingFingerprint: string) {
    const currentText = exactSourceMirror.text;
    const normalizedCurrent = normalizedDocumentText(editor.state.doc.toString());
    if (currentText !== expectedText) {
      // Typing is allowed to advance while the immutable snapshot is written.
      // When the repository committed that snapshot byte-for-byte, advance
      // only the disk base identity and keep the newer CodeMirror buffer dirty.
      if (committedText !== expectedText
          || normalizedCurrent !== normalizedDocumentText(currentText)) return null;
      bridgeFingerprint = startingFingerprint;
      dirty = true;
      scheduleEditorInteractionReport(true);
      return true;
    }
    if (normalizedCurrent !== normalizedDocumentText(expectedText)) return null;
    bridgeFingerprint = startingFingerprint;
    if (committedText !== currentText) {
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
    }
    dirty = false;
    scheduleEditorInteractionReport(true);
    return false;
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
  resolveLinkCompletionQuery: inputSuggestions.resolveLinkCompletionQuery,
  refreshMathRuntime() {
    editor.dispatch({effects: refreshLivePreviewEffect.of(null)});
    return true;
  },
};

recordEditorMetric("startup", editorStartupStartedAt, {documentLength: editor.state.doc.length});
post({ type: "ready" });
