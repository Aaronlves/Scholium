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
  foldKeymap,
  indentOnInput,
  syntaxTree,
  syntaxHighlighting,
} from "@codemirror/language";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
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
  type MarkdownEditingDialect,
  type RecoverySnapshot,
  encodedByteLength,
  isEditorRequest,
  rejected,
} from "./protocol";
import {applySourceChanges, transformMarkdown} from "./transformations";
import {continueList, indentList} from "./interaction";
import {tableAt, tableTabAction} from "./tables";
import {decodeClipboardPayload, isSingleSafeURL, pasteAsMarkdown} from "./clipboard";
import {linkTargetAt} from "./projection";
import {rangeKey, semanticProjectionRanges} from "./semantic-projection";
import {
  applyNormalizedChangesToExactSource,
  frontmatterEndLine,
  normalizedDocumentText,
  replacementChange,
} from "./state";
import {
  announceEditorMessage,
  editorAccessibilityAttributes,
  unsupportedFilePasteMessage,
  updateEditorAccessibility,
} from "./accessibility";
import {CompositionRequestGate} from "./composition";
import {createMarkdownEditor} from "./bootstrap";
import {recordEditorMetric, sampleEditorMemory} from "./performance";

const editorStartupStartedAt = performance.now();

interface ScholiumWindow extends Window {
  webkit?: { messageHandlers?: { scholium?: { postMessage(message: unknown): void } } };
  scholiumEditor?: ScholiumEditorAPI;
}
interface LinkCandidate { label: string; insertion: string; detail: string; path: string; isAmbiguous: boolean }
interface ResearcherCommentAnnotation { id: string; from: number; to: number; comment: string; resolved: boolean }
interface SourceDelta { from: number; to: number; insert: string }
interface CalloutContext { role: string; depth: number; isHeader?: boolean; isEnd?: boolean }
type VectorLinkKind = "neutral" | "supports_target" | "supported_by_target" | "incompatible";
interface FenceState { character: "`" | "~"; openingLength: number }
interface WikilinkPresentation { displayStart: number; displayEnd: number; isLegacyRelationship: boolean }
interface SemanticLiteralRanges {
  excluded: {from: number; to: number}[];
  codeBlocks: {from: number; to: number}[];
}
interface ScholiumEditorAPI {
  dispatch(request: unknown): Promise<EditorCommandResult>;
}

const webkitWindow = window as ScholiumWindow;
const nativeHandler = webkitWindow.webkit?.messageHandlers?.scholium;
let bridgeSessionID = "";
let bridgeDocumentID = "";
let bridgeFingerprint = "";
let documentVersion = 0;
let exactSource = "";
let linkCandidates: LinkCandidate[] = [];
let editingDialect: MarkdownEditingDialect | null = null;
let currentMode: "livePreview" | "source" = "livePreview";
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

/** @param {import("@codemirror/state").Text} doc */
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

/** @param {string} rawKind */
function calloutRole(rawKind: string): string {
  return calloutDefinition(rawKind).identifier;
}

/** @param {string} text */
function quoteDepth(text: string): number {
  const prefix = /^(\s*(?:>\s*)+)/.exec(text)?.[1] || "";
  return (prefix.match(/>/g) || []).length;
}

/** @param {string} text */
function calloutHeader(text: string): RegExpExecArray | null {
  return /^(\s*(?:>\s*)+)\[!([^\]]+)\]([+-])?\s*(.*)$/.exec(text);
}

/** @param {import("@codemirror/state").Text} doc @param {number} firstLine @param {number} lastLine */
function calloutContexts(doc: Text, firstLine: number, lastLine: number): Map<number, CalloutContext> {
  let scanStart = firstLine;
  while (scanStart > 1 && quoteDepth(doc.line(scanStart).text) > 0 && quoteDepth(doc.line(scanStart - 1).text) > 0) {
    scanStart -= 1;
  }

  const activeByDepth = new Map<number, CalloutContext>();
  const contexts = new Map<number, CalloutContext>();
  for (let number = scanStart; number <= lastLine; number += 1) {
    const text = doc.line(number).text;
    const depth = quoteDepth(text);
    if (depth === 0) {
      activeByDepth.clear();
      continue;
    }
    for (const activeDepth of [...activeByDepth.keys()]) {
      if (activeDepth > depth) activeByDepth.delete(activeDepth);
    }
    const header = calloutHeader(text);
    if (header) activeByDepth.set(depth, { role: calloutRole(header[2]), depth });
    const active = [...activeByDepth.values()]
      .filter((value) => value.depth <= depth)
      .sort((left, right) => right.depth - left.depth)[0];
    if (active && number >= firstLine) {
      const nextDepth = number < doc.lines ? quoteDepth(doc.line(number + 1).text) : 0;
      contexts.set(number, {
        role: active.role,
        depth: active.depth,
        isHeader: Boolean(header),
        isEnd: nextDepth < active.depth,
      });
    }
  }
  return contexts;
}

class CalloutRoleWidget extends WidgetType {
  readonly role: string;
  constructor(role: string) {
    super();
    this.role = role;
  }

  /** @param {CalloutRoleWidget} other */
  eq(other: CalloutRoleWidget) { return other.role === this.role; }

  toDOM() {
    const semantics = calloutDefinition(this.role);
    const span = document.createElement("span");
    span.className = "cm-live-callout-role";
    span.textContent = semantics.label;
    span.title = semantics.meaning;
    span.setAttribute("aria-label", `${semantics.label}. ${semantics.meaning}`);
    return span;
  }

  ignoreEvent() { return true; }
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

function openingFence(text: string): FenceState | null {
  const match = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(text);
  if (!match) return null;
  const run = match[1];
  // CommonMark does not allow a backtick in the info string of a backtick
  // fence. Treat such a line as ordinary source instead of starting a
  // projection that could hide unrelated Markdown below it.
  if (run[0] === "`" && match[2].includes("`")) return null;
  return { character: run[0] as "`" | "~", openingLength: run.length };
}

function isClosingFence(text: string, opening: FenceState): boolean {
  const match = /^ {0,3}(`+|~+)[ \t]*$/.exec(text);
  if (!match) return false;
  const run = match[1];
  return run[0] === opening.character && run.length >= opening.openingLength;
}

function fencedCodeLines(doc: Text, lastLine: number): Map<number, {fence: boolean}> {
  const result = new Map<number, {fence: boolean}>();
  let opening: FenceState | null = null;
  for (let number = 1; number <= lastLine; number += 1) {
    const text = doc.line(number).text;
    if (opening === null) {
      const candidate = openingFence(text);
      if (!candidate) continue;
      opening = candidate;
      result.set(number, { fence: true });
      continue;
    }

    const closes = isClosingFence(text, opening);
    result.set(number, { fence: closes });
    if (closes) opening = null;
  }
  return result;
}

function isIndentedCodeLine(text: string): boolean {
  // A tab in the first four columns reaches a CommonMark code indentation
  // stop. Four or more literal spaces are the equivalent source form.
  return /^(?: {4,}| {0,3}\t)/.test(text);
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

function literalCommentRanges(doc: Text): {from: number; to: number}[] {
  const source = doc.sliceString(0, doc.length);
  return Array.from(source.matchAll(/<!--[\s\S]*?-->|%%[\s\S]*?%%/g), (match) => ({
    from: match.index,
    to: match.index + match[0].length,
  }));
}

function semanticLiteralRanges(view: EditorView): SemanticLiteralRanges {
  const excluded: {from: number; to: number}[] = [];
  const codeBlocks: {from: number; to: number}[] = [];
  syntaxTree(view.state).iterate({
    enter(node) {
      if (node.name === "FencedCode" || node.name === "CodeBlock") {
        const range = { from: node.from, to: node.to };
        excluded.push(range);
        codeBlocks.push(range);
        return false;
      }
      // These are the CodeMirror counterparts of the Swift Markdown literal
      // nodes excluded by MarkdownSemanticDocument. Obsidian %% comments are
      // added separately because the CommonMark grammar does not name them.
      if (["InlineCode", "HTMLBlock", "HTMLTag", "CommentBlock"].includes(node.name)) {
        excluded.push({ from: node.from, to: node.to });
        return false;
      }
      return undefined;
    },
  });
  return { excluded, codeBlocks };
}

/** @param {EditorView} view */
function buildLiveDecorations(view: EditorView) {
  const projectionStartedAt = performance.now();
  const decorations: Range<Decoration>[] = [];
  const doc = view.state.doc;
  const selection = view.state.selection.main;
  const yamlEnd = frontmatterEndLine(doc);
  const semanticLiterals = semanticLiteralRanges(view);
  const parsedProjection = semanticProjectionRanges(view.state, view.visibleRanges);
  const literals = [...semanticLiterals.excluded, ...literalCommentRanges(doc)];

  /** @param {number} from @param {number} to */
  const addHidden = (from: number, to: number) => {
    if (to > from) decorations.push(hiddenSyntax.range(from, to));
  };
  /** @param {number} from @param {number} to @param {string} className */
  const addMark = (from: number, to: number, className: string) => {
    if (to > from) decorations.push(liveMark(className).range(from, to));
  };

  for (const visible of view.visibleRanges) {
    let line = doc.lineAt(visible.from);
    const lastLine = doc.lineAt(visible.to).number;
    const calloutContext = calloutContexts(doc, line.number, lastLine);
    const codeContext = fencedCodeLines(doc, lastLine);
    while (line.from <= visible.to) {
      const text = line.text;
      const activeLine = selection.head >= line.from && selection.head <= line.to
        || view.composing && view.state.selection.ranges.some(
          (range) => range.from <= line.to && range.to >= line.from,
        );
      const excluded: {from: number; to: number}[] = literals.filter(
        (literal) => literal.from <= line.to && literal.to >= line.from,
      );

      if (yamlEnd > 0 && line.number <= yamlEnd) {
        decorations.push(
          Decoration.line({ attributes: { class: "cm-live-frontmatter" } }).range(line.from),
        );
        if (!activeLine && (line.number === 1 || line.number === yamlEnd)) {
          addHidden(line.from, line.to);
        }
      } else {
        const codeLine = codeContext.get(line.number);
        const semanticCodeLine = semanticLiterals.codeBlocks.some(
          (range) => range.from <= line.to && range.to >= line.from,
        );
        if (codeLine || semanticCodeLine || isIndentedCodeLine(text)) {
          decorations.push(Decoration.line({ attributes: { class: "cm-live-codeblock" } }).range(line.from));
          if (codeLine?.fence && !activeLine) addHidden(line.from, line.to);
          else if (!codeLine?.fence) addMark(line.from, line.to, "cm-live-code");
          if (line.to === doc.length) break;
          line = doc.line(line.number + 1);
          continue;
        }

        const headingLevel = parsedProjection.headingLevelByLineFrom.get(line.from);
        const heading = headingLevel ? /^(#{1,6})\s+/.exec(text) : null;
        if (heading && heading[1].length === headingLevel) {
          decorations.push(
            Decoration.line({
              attributes: { class: `cm-live-heading cm-live-h${heading[1].length}` },
            }).range(line.from),
          );
          if (!activeLine) addHidden(line.from, line.from + heading[0].length);
        }

        const callout = calloutHeader(text);
        const context = calloutContext.get(line.number);
        const quote = /^(\s*>\s?)/.exec(text);
        if (quote) {
          const contextClasses = context
            ? `cm-live-callout cm-live-callout-${context.role}${context.isHeader ? " cm-live-callout-header" : ""}${context.isEnd ? " cm-live-callout-end" : ""}`
            : "cm-live-quote";
          decorations.push(
            Decoration.line({
              attributes: { class: contextClasses },
            }).range(line.from),
          );
          if (!activeLine) addHidden(line.from, line.from + quote[0].length);
        }
        if (callout && !activeLine) {
          const markerStart = line.from + callout[1].length;
          const kindStart = markerStart + 2;
          const kindEnd = kindStart + callout[2].length;
          addHidden(markerStart, kindStart);
          decorations.push(
            Decoration.replace({ widget: new CalloutRoleWidget(calloutRole(callout[2])) }).range(kindStart, kindEnd),
          );
          const closingEnd = kindEnd + 1 + (callout[3]?.length || 0);
          addHidden(kindEnd, closingEnd);
          if (callout[4]) addMark(line.to - callout[4].length, line.to, "cm-live-callout-title");
        }

        const rule = /^\s{0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$/.exec(text);
        if (rule && !activeLine) {
          addHidden(line.from, line.to);
          decorations.push(
            Decoration.line({ attributes: { class: "cm-live-rule" } }).range(line.from),
          );
        }

        const list = /^(\s*)([-+*]|\d+[.)])(\s+)/.exec(text);
        if (list) {
          decorations.push(Decoration.line({ attributes: { class: "cm-live-list" } }).range(line.from));
          if (!activeLine) {
            const markerFrom = line.from + list[1].length;
            const markerTo = markerFrom + list[2].length;
            decorations.push(Decoration.replace({ widget: new ListMarkerWidget(list[2]) }).range(markerFrom, markerTo));
          }
        }

        const parsedTableLine = parsedProjection.tables.some((range) => range.from <= line.to && range.to >= line.from);
        if (parsedTableLine) {
          decorations.push(Decoration.line({ attributes: { class: "cm-live-table" } }).range(line.from));
          if (!activeLine) {
            for (const match of text.matchAll(/\|/g)) addMark(line.from + match.index, line.from + match.index + 1, "cm-live-table-separator");
          }
        }

        const relation = /^(\s*-\s*)`([^`]+)`(\s*->\s*)/.exec(text);
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
          const from = line.from + match.index;
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
          const from = line.from + match.index;
          const to = from + match[0].length;
          const embed = match[1] === "!";
          const wikiIndex = match.index + (embed ? 1 : 0);
          if (isEscapedAt(text, match.index) || overlaps(excluded, from, to)) continue;

          const kind = embed ? "neutral" : vectorLinkKindAt(text, wikiIndex);
          const hasVectorMarker = !embed && kind !== "neutral";
          const fullFrom = hasVectorMarker ? from - 1 : from;
          if (fullFrom < line.from || overlaps(excluded, fullFrom, to)) continue;
          excluded.push({ from: fullFrom, to });

          const activeConstruct = view.state.selection.ranges.some((selected) =>
            selected.from <= to && selected.to >= fullFrom,
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
            decorations.push(
              Decoration.replace({ widget: new VectorLinkIconWidget(kind) }).range(fullFrom, openingEnd),
            );
          }

          const linkClass = embed
            ? "cm-live-embed"
            : presentation.isLegacyRelationship && kind === "neutral"
              ? "cm-live-vector-link cm-live-vector-neutral cm-live-vector-legacy"
              : `cm-live-vector-link cm-live-vector-${kind.replaceAll("_", "-")}`;
          addHidden(openingEnd, presentation.displayStart);
          addMark(presentation.displayStart, presentation.displayEnd, linkClass);
          addHidden(presentation.displayEnd, to - 2);
          addHidden(to - 2, to);
        }

        if (!activeLine) {
          const footnoteDefinition = /^(\s*)\[\^([^\]]+)\]:(\s*)/.exec(text);
          if (footnoteDefinition) {
            const from = line.from + footnoteDefinition[1].length;
            const contentFrom = from + footnoteDefinition[0].length - footnoteDefinition[1].length;
            addHidden(from, contentFrom);
            addMark(contentFrom, line.to, "cm-live-footnote-definition");
          } else {
            for (const match of text.matchAll(/\[\^([^\]]+)\]/g)) {
              const from = line.from + match.index;
              const to = from + match[0].length;
              if (overlaps(excluded, from, to)) continue;
              addHidden(from, from + 2);
              addMark(from + 2, to - 1, "cm-live-footnote-reference");
              addHidden(to - 1, to);
            }
          }

          for (const match of text.matchAll(/\^\[([^\]\n]+)\]/g)) {
            const from = line.from + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to)) continue;
            addHidden(from, from + 2);
            addMark(from + 2, to - 1, "cm-live-footnote-definition");
            addHidden(to - 1, to);
          }

          for (const match of text.matchAll(/\[([^\]\n]+)\]\(([^)\n]+)\)/g)) {
            const from = line.from + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to) || !parsedProjection.links.has(rangeKey(from, to))) continue;
            addHidden(from, from + 1);
            addMark(from + 1, from + 1 + match[1].length, "cm-live-link");
            addHidden(from + 1 + match[1].length, to);
          }

          for (const match of text.matchAll(/\*\*([^*\n]+)\*\*/g)) {
            const from = line.from + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to) || !parsedProjection.strong.has(rangeKey(from, to))) continue;
            addHidden(from, from + 2);
            addMark(from + 2, to - 2, "cm-live-strong");
            addHidden(to - 2, to);
          }

          for (const match of text.matchAll(/~~([^~\n]+)~~/g)) {
            const from = line.from + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to) || !parsedProjection.strikethrough.has(rangeKey(from, to))) continue;
            addHidden(from, from + 2);
            addMark(from + 2, to - 2, "cm-live-strike");
            addHidden(to - 2, to);
          }

          for (const match of text.matchAll(/==([^=\n]+)==/g)) {
            const from = line.from + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to)) continue;
            addHidden(from, from + 2);
            addMark(from + 2, to - 2, "cm-live-highlight");
            addHidden(to - 2, to);
          }

          for (const match of text.matchAll(/(?<!\*)\*([^*\n]+)\*(?!\*)/g)) {
            const from = line.from + match.index;
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
  recordEditorMetric("projection", projectionStartedAt, {
    documentLength: doc.length,
    visibleRangeCount: view.visibleRanges.length,
    decorationCount: decorations.length,
  });
  return result;
}

class LivePreviewPlugin {
  decorations;
  constructor(view: EditorView) {
    this.decorations = buildLiveDecorations(view);
  }
  update(update: ViewUpdate) {
    if (update.docChanged || update.selectionSet || update.viewportChanged) {
      this.decorations = buildLiveDecorations(update.view);
    }
  }
}
const livePreview = ViewPlugin.fromClass(LivePreviewPlugin, {
  decorations: (value: LivePreviewPlugin) => value.decorations,
});
const livePreviewMode = [livePreview, EditorView.lineWrapping];
const sourceMode = [
  lineNumbers(),
  highlightActiveLineGutter(),
  foldGutter(),
  highlightActiveLine(),
];

let dirty = false;
let pendingKeyStartedAt: number | null = null;
/** @type {number | null} */
let idleTimer: number | null = null;

const stateReporter = EditorView.updateListener.of((update) => {
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

  const head = update.state.selection.main.head;
  const line = update.state.doc.lineAt(head);
  post({
    type: "stateChanged",
    dirty,
    line: line.number,
    column: head - line.from + 1,
    lineCount: update.state.doc.lines,
  });
  publishEditorContext();

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

/** @param {import("@codemirror/autocomplete").CompletionContext} context */
function wikilinkCompletionSource(context: CompletionContext) {
  const match = context.matchBefore(/\[\[[^\]\n]*/);
  if (!match) return null;
  const typed = match.text.slice(2).toLocaleLowerCase();
  const options = linkCandidates
    .filter((candidate) => !typed || candidate.label.toLocaleLowerCase().includes(typed) || candidate.path.toLocaleLowerCase().includes(typed))
    .slice(0, 100)
    .map((candidate) => ({
      label: candidate.label,
      detail: candidate.detail,
      type: "text",
      apply: candidate.isAmbiguous
        ? () => undefined
        : candidate.insertion + "]]",
    }));
  return { from: match.from + 2, options, filter: false };
}

/** @param {import("@codemirror/autocomplete").CompletionContext} context */
function calloutCompletionSource(context: CompletionContext) {
  const line = context.state.doc.lineAt(context.pos);
  const beforeCursor = line.text.slice(0, context.pos - line.from);
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
      syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
      bracketMatching(),
      closeBrackets(),
      autocompletion({ override: [calloutCompletionSource, wikilinkCompletionSource] }),
      rectangularSelection(),
      highlightSelectionMatches(),
      markdown({base: markdownLanguage}),
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
      modeCompartment.of(livePreviewMode),
      EditorView.contentAttributes.of(editorAccessibilityAttributes("source")),
      EditorView.theme({
        "&": { height: "100%" },
        ".cm-scroller": { overflow: "auto" },
      }),
];
const editor = createMarkdownEditor(document.getElementById("editor")!, editorExtensions);
editor.contentDOM.addEventListener("keydown", () => { pendingKeyStartedAt = performance.now(); }, {capture: true});

let scrollReportTimer: number | undefined;
let previousScrollFrameAt: number | null = null;
editor.scrollDOM.addEventListener("scroll", () => {
  window.requestAnimationFrame(() => {
    const now = performance.now();
    if (previousScrollFrameAt !== null) recordEditorMetric("scroll-frame", previousScrollFrameAt);
    previousScrollFrameAt = now;
  });
  window.clearTimeout(scrollReportTimer);
  scrollReportTimer = window.setTimeout(() => {
    const extent = Math.max(0, editor.scrollDOM.scrollHeight - editor.scrollDOM.clientHeight);
    const fraction = extent > 0 ? Math.max(0, Math.min(1, editor.scrollDOM.scrollTop / extent)) : 0;
    post({ type: "scrollChanged", scrollFraction: fraction });
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
  const ranges = semanticLiteralRanges(editor).excluded.concat(literalCommentRanges(editor.state.doc));
  const yamlEnd = frontmatterEndLine(editor.state.doc);
  if (yamlEnd > 0) ranges.push({from: 0, to: editor.state.doc.line(yamlEnd).to});
  return ranges;
}

function currentEditorContext(): EditorContext {
  const inline = new Set<string>();
  const block = new Set<string>();
  for (const selection of editor.state.selection.ranges) {
    for (let node = syntaxTree(editor.state).resolveInner(selection.head, -1); node; node = node.parent!) {
      if (["Emphasis", "StrongEmphasis", "InlineCode", "Link"].includes(node.name)) inline.add(node.name);
      if (["ATXHeading1", "ATXHeading2", "ATXHeading3", "ATXHeading4", "ATXHeading5", "ATXHeading6", "Blockquote", "BulletList", "OrderedList", "FencedCode", "Table"].includes(node.name)) block.add(node.name);
      if (!node.parent) break;
    }
    if (calloutHeader(editor.state.doc.lineAt(selection.head).text)) block.add("Callout");
  }
  const protectedSelection = editor.state.selection.ranges.some((selection) =>
    protectedCommandRanges().some((range) => selection.from < range.to && selection.to > range.from),
  );
  const currentTable = editor.state.selection.ranges.length === 1
    ? tableAt(editor.state.doc.toString(), editor.state.selection.main.head)
    : null;
  const tableOnlyCommands = new Set([
    "tableInsertRowBefore", "tableInsertRowAfter", "tableDeleteRow",
    "tableInsertColumnBefore", "tableInsertColumnAfter", "tableDeleteColumn",
    "tableAlignLeft", "tableAlignCenter", "tableAlignRight",
  ]);
  const availableCommands = allCommands.filter((command) => {
    if (tableOnlyCommands.has(command)) return currentTable !== null;
    if (command === "toggleTask") {
      return editor.state.selection.ranges.every((selection) => {
        const line = editor.state.doc.lineAt(selection.head).text;
        return /^\s*-\s+\[[ xX]\]/.test(line);
      });
    }
    if (command === "linkSelectedText") return editor.state.selection.ranges.every((selection) => !selection.empty);
    return true;
  });
  return {
    selections: editorSelections(),
    activeInlineConstructs: [...inline],
    activeBlockConstructs: [...block],
    tablePosition: currentTable?.position,
    composing: editor.composing,
    availableCommands: editor.composing || protectedSelection ? [] : availableCommands,
    undoLabel: undoDepth(editor.state) > 0 ? lastUndoLabel || "Undo Editing" : undefined,
    redoLabel: redoDepth(editor.state) > 0 ? lastRedoLabel || "Redo Editing" : undefined,
  };
}

function publishEditorContext() {
  const context = currentEditorContext();
  updateEditorAccessibility(editor.contentDOM, currentMode, context);
  post({type: "contextChanged", context});
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
  case "setUserCSS": editorOperations.setUserCSS(operation.value); break;
  case "setLinkCompletions": editorOperations.setLinkCompletions(operation.value as LinkCandidate[]); break;
  case "setResearcherComments": editorOperations.setResearcherComments(operation.value as ResearcherCommentAnnotation[]); break;
  case "announceStatus": announceEditorMessage(editor.contentDOM, operation.value); break;
  case "goToLine": editorOperations.goToLine(operation.line); break;
  case "setScrollFraction": editorOperations.setScrollFraction(operation.fraction); break;
  case "queryText": return {...successfulResult(request.requestID), text: exactEditorSource()};
  case "querySelection": {
    const snapshot = {documentID: bridgeDocumentID, fingerprint: bridgeFingerprint, generation: documentVersion, ranges: editorSelections()};
    return {...successfulResult(request.requestID), selection: snapshot};
  }
  case "queryContext": return {...successfulResult(request.requestID), context: currentEditorContext()};
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
        || new TextEncoder().encode(snapshot.source).byteLength > MAX_SOURCE_UTF8_BYTES) {
      return rejected(request.requestID, documentVersion, "stale recovery snapshot");
    }
    let restoredHistory = false;
    if (snapshot.stateJSON && new TextEncoder().encode(snapshot.stateJSON).byteLength <= MAX_INBOUND_BYTES) {
      try {
        const restored = EditorState.fromJSON(
          JSON.parse(snapshot.stateJSON),
          {extensions: editorExtensions},
          {history: historyField},
        );
        if (normalizedDocumentText(restored.doc.toString())
            === normalizedDocumentText(snapshot.source)) {
          editor.setState(restored);
          exactSource = snapshot.source;
          restoredHistory = true;
        }
      } catch { restoredHistory = false; }
    }
    if (!restoredHistory) {
      editor.dispatch({
        changes: replacementChange(editor.state.doc.toString(), snapshot.source),
        selection: EditorSelection.create(snapshot.ranges.map((range) => EditorSelection.range(range.anchor, range.head))),
        annotations: [Transaction.addToHistory.of(false), programmaticDocumentChange.of(true)],
      });
      exactSource = snapshot.source;
    }
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
  if ((editor.composing || compositionGate.active)
      && (value.operation.type === "setMode" || value.operation.type === "command")) {
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

const editorOperations = {
  /** @param {string} text @param {string} sessionID @param {string} documentID */
  setDocument(text: string, sessionID: string, documentID: string, startingFingerprint: string) {
    compositionGate.rejectAll((pending) => rejected(
      pending.requestID,
      documentVersion,
      "editor identity changed during composition",
    ));
    bridgeSessionID = sessionID;
    bridgeDocumentID = documentID;
    bridgeFingerprint = startingFingerprint;
    documentVersion = 0;
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
    post({ type: "stateChanged", dirty: false, line: 1, column: 1, lineCount: editor.state.doc.lines });
  },

  /** @param {string} mode */
  setMode(mode: string) {
    editor.dispatch({
      effects: modeCompartment.reconfigure(mode === "livePreview" ? livePreviewMode : sourceMode),
    });
    editor.dom.classList.toggle("scholium-live-mode", mode === "livePreview");
    editor.dom.classList.toggle("scholium-source-mode", mode !== "livePreview");
    currentMode = mode === "livePreview" ? "livePreview" : "source";
    updateEditorAccessibility(editor.contentDOM, currentMode, currentEditorContext());
  },

  /** @param {string} css */
  setUserCSS(css: string) {
    const style = document.getElementById("scholium-user-css");
    if (style) style.textContent = css;
  },

  /** @param {{label: string, insertion: string, detail: string, path: string}[]} candidates */
  setLinkCompletions(candidates: LinkCandidate[]) {
    linkCandidates = Array.isArray(candidates) ? candidates.slice(0, 20000) : [];
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
    window.requestAnimationFrame(() => {
      const extent = Math.max(0, editor.scrollDOM.scrollHeight - editor.scrollDOM.clientHeight);
      editor.scrollDOM.scrollTop = extent * fraction;
    });
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
    post({
      type: "stateChanged",
      dirty: false,
      line: editor.state.doc.lineAt(editor.state.selection.main.head).number,
      column: editor.state.selection.main.head - editor.state.doc.lineAt(editor.state.selection.main.head).from + 1,
      lineCount: editor.state.doc.lines,
    });
    return true;
  },

  markClean() {
    dirty = false;
    post({ type: "stateChanged", dirty: false });
  },

  focus() {
    editor.focus();
  },
};

webkitWindow.scholiumEditor = {dispatch: dispatchEditorRequest};

recordEditorMetric("startup", editorStartupStartedAt, {documentLength: editor.state.doc.length});
post({ type: "ready" });
