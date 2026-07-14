import {
  Annotation,
  Compartment,
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
import { markdown } from "@codemirror/lang-markdown";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
} from "@codemirror/commands";
import {
  CompletionContext,
  autocompletion,
  closeBrackets,
  closeBracketsKeymap,
  completionKeymap,
} from "@codemirror/autocomplete";
import {
  closeSearchPanel,
  findNext as moveToNextSearchMatch,
  findPrevious as moveToPreviousSearchMatch,
  highlightSelectionMatches,
  openSearchPanel,
  searchKeymap,
} from "@codemirror/search";

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
  setDocument(text: string, sessionID: string, documentID: string, startingFingerprint: string): void;
  setMode(mode: string): void;
  setUserCSS(css: string): void;
  setLinkCompletions(candidates: LinkCandidate[]): void;
  setResearcherComments(comments: ResearcherCommentAnnotation[]): void;
  goToLine(requestedLine: number): void;
  setScrollFraction(fraction: number): void;
  getText(): string;
  getSelection(): {
    startLine: number;
    endLine: number;
    excerpt: string;
    utf16LowerBound: number;
    utf16UpperBound: number;
    contextBefore: string;
    contextAfter: string;
  } | null;
  synchronizeCommittedText(expectedText: string, committedText: string, startingFingerprint: string): boolean;
  openFind(): boolean;
  findNext(): boolean;
  findPrevious(): boolean;
  closeFind(): boolean;
  markClean(): void;
  focus(): void;
}

const webkitWindow = window as ScholiumWindow;
const nativeHandler = webkitWindow.webkit?.messageHandlers?.scholium;
let bridgeSessionID = "";
let bridgeDocumentID = "";
let bridgeFingerprint = "";
let documentVersion = 0;
let linkCandidates: LinkCandidate[] = [];
const post = (message: Record<string, unknown>) => nativeHandler?.postMessage({
  bridgeVersion: 1,
  sessionID: bridgeSessionID,
  documentID: bridgeDocumentID,
  startingFingerprint: bridgeFingerprint,
  documentVersion,
  ...message,
});

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

function normalizedDocumentText(text: string) {
  return text.replace(/\r\n/g, "\n");
}

function replacementChange(currentText: string, requestedText: string) {
  const targetText = normalizedDocumentText(requestedText);
  let prefix = 0;
  const sharedLength = Math.min(currentText.length, targetText.length);
  while (prefix < sharedLength && currentText.charCodeAt(prefix) === targetText.charCodeAt(prefix)) {
    prefix += 1;
  }

  let currentSuffix = currentText.length;
  let targetSuffix = targetText.length;
  while (
    currentSuffix > prefix
    && targetSuffix > prefix
    && currentText.charCodeAt(currentSuffix - 1) === targetText.charCodeAt(targetSuffix - 1)
  ) {
    currentSuffix -= 1;
    targetSuffix -= 1;
  }

  return {
    from: prefix,
    to: currentSuffix,
    insert: targetText.slice(prefix, targetSuffix),
  };
}

const hiddenSyntax = Decoration.replace({});
const liveMark = (className: string) => Decoration.mark({ class: className });

/** @param {{from: number, to: number}[]} ranges @param {number} from @param {number} to */
function overlaps(ranges: {from: number; to: number}[], from: number, to: number) {
  return ranges.some((range) => range.from < to && range.to > from);
}

/** @param {import("@codemirror/state").Text} doc */
function frontmatterEndLine(doc: Text) {
  if (doc.lines < 2 || doc.line(1).text.trim() !== "---") return 0;
  for (let number = 2; number <= doc.lines; number += 1) {
    if (doc.line(number).text.trim() === "---") return number;
  }
  return 0;
}

const calloutRoles: Record<string, {label: string; purpose: string}> = {
  orient: { label: "Orientation", purpose: "Introduces the note's purpose, scope, and route." },
  cite: { label: "Source", purpose: "Records source entries that anchor the note without implying support for every claim." },
  connect: { label: "Connections", purpose: "Routes the reader to a curated set of neighboring knowledge objects." },
  state: { label: "Statement", purpose: "Isolates a claim-like object without endorsing it." },
  illustrate: { label: "Illustration", purpose: "Presents a scenario, example, thought experiment, or test case." },
  quote: { label: "Quotation", purpose: "Preserves source-specific wording with attribution." },
  flag: { label: "Caution", purpose: "Marks a limitation, unresolved dependency, source restriction, or warning." },
  neutral: { label: "Note", purpose: "Preserves an unsupported callout without assigning a research role." },
};

/** @param {string} rawKind */
function calloutRole(rawKind: string): string {
  const kind = rawKind.toLowerCase().replace(/:+$/, "").trim();
  if (kind === "mini") return "orient";
  if (["bibli", "bibliography", "cited"].includes(kind)) return "cite";
  if (kind === "project") return "connect";
  if (["definition", "principle", "theorem", "argument", "objection", "reply"].includes(kind)) return "state";
  if (["example", "case", "dialogue"].includes(kind)) return "illustrate";
  if (["quotation", "author", "long-quote"].includes(kind)) return "quote";
  if (["warning", "caution", "source-warning", "torn", "question"].includes(kind)) return "flag";
  return Object.hasOwn(calloutRoles, kind) ? kind : "neutral";
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
    const semantics = calloutRoles[this.role] || calloutRoles.neutral;
    const span = document.createElement("span");
    span.className = "cm-live-callout-role";
    span.textContent = semantics.label;
    span.title = semantics.purpose;
    span.setAttribute("aria-label", `${semantics.label}. ${semantics.purpose}`);
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
  const kind: VectorLinkKind | undefined = marker === "+"
    ? "supports_target"
    : marker === "-"
      ? "supported_by_target"
      : marker === "?"
        ? "incompatible"
        : undefined;
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
  const decorations: Range<Decoration>[] = [];
  const doc = view.state.doc;
  const selection = view.state.selection.main;
  const yamlEnd = frontmatterEndLine(doc);
  const semanticLiterals = semanticLiteralRanges(view);
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
      const activeLine = selection.head >= line.from && selection.head <= line.to;
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

        const heading = /^(#{1,6})\s+/.exec(text);
        if (heading) {
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

        const adjacentTableSeparator = (number: number) => number >= 1 && number <= doc.lines
          && /^\s*\|?\s*:?-{3,}/.test(doc.line(number).text);
        if (text.includes("|") && (adjacentTableSeparator(line.number) || adjacentTableSeparator(line.number + 1))) {
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
            if (overlaps(excluded, from, to)) continue;
            addHidden(from, from + 1);
            addMark(from + 1, from + 1 + match[1].length, "cm-live-link");
            addHidden(from + 1 + match[1].length, to);
          }

          for (const match of text.matchAll(/\*\*([^*\n]+)\*\*/g)) {
            const from = line.from + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to)) continue;
            addHidden(from, from + 2);
            addMark(from + 2, to - 2, "cm-live-strong");
            addHidden(to - 2, to);
          }

          for (const match of text.matchAll(/~~([^~\n]+)~~/g)) {
            const from = line.from + match.index;
            const to = from + match[0].length;
            if (overlaps(excluded, from, to)) continue;
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
            if (overlaps(excluded, from, to)) continue;
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

  return Decoration.set(decorations, true);
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

let dirty = false;
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
    documentVersion += 1;
    /** @type {{from: number, to: number, insert: string}[]} */
    const changes: SourceDelta[] = [];
    update.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
      changes.push({ from: fromA, to: toA, insert: inserted.toString() });
    });
    post({ type: "documentChanged", changes });
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

  if (update.docChanged) {
    if (idleTimer !== null) window.clearTimeout(idleTimer);
    idleTimer = window.setTimeout(() => post({ type: "idle", dirty }), 500);
  }
  if (update.docChanged || update.selectionSet) {
    window.requestAnimationFrame(refreshEditorAccessibilityValue);
  }
});

const researcherCommentActivation = EditorView.domEventHandlers({
  click(event) {
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
  const options = ["orient", "cite", "connect", "state", "illustrate", "quote", "flag"]
    .filter((identifier) => !typed || identifier.startsWith(typed))
    .map((identifier) => ({
      label: identifier,
      detail: `${calloutRoles[identifier].label} — ${calloutRoles[identifier].purpose}`,
      type: "keyword",
      apply: `${identifier}] `,
    }));
  return { from: context.pos - match[2].length, options, filter: false };
}

const editor = new EditorView({
  parent: document.getElementById("editor")!,
  state: EditorState.create({
    doc: "",
    extensions: [
      lineNumbers(),
      highlightActiveLineGutter(),
      highlightSpecialChars(),
      history(),
      foldGutter(),
      drawSelection(),
      dropCursor(),
      EditorState.allowMultipleSelections.of(true),
      indentOnInput(),
      syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
      bracketMatching(),
      closeBrackets(),
      autocompletion({ override: [calloutCompletionSource, wikilinkCompletionSource] }),
      rectangularSelection(),
      highlightActiveLine(),
      highlightSelectionMatches(),
      markdown(),
      keymap.of([
        ...closeBracketsKeymap,
        ...defaultKeymap,
        ...searchKeymap,
        ...historyKeymap,
        ...foldKeymap,
        ...completionKeymap,
        indentWithTab,
      ]),
      saveKeymap,
      stateReporter,
      researcherCommentField,
      researcherCommentActivation,
      lineSeparatorCompartment.of(EditorState.lineSeparator.of("\n")),
      modeCompartment.of(livePreview),
      EditorView.contentAttributes.of({
        "aria-label": "Markdown source editor",
        role: "textbox",
        "aria-multiline": "true",
        spellcheck: "true",
        autocapitalize: "sentences",
      }),
      EditorView.theme({
        "&": { height: "100%" },
        ".cm-scroller": { overflow: "auto" },
      }),
    ],
  }),
});

function refreshEditorAccessibilityValue() {
  if (editor.dom.classList.contains("scholium-live-mode")) {
    // CodeMirror exposes the underlying document as AXValue even when live
    // decorations hide YAML and Markdown syntax from the rendered surface.
    // Keep assistive technology aligned with what the researcher can read.
    const projectedText = editor.contentDOM.innerText || editor.contentDOM.textContent || "";
    editor.contentDOM.setAttribute("aria-valuetext", projectedText);
  } else {
    editor.contentDOM.removeAttribute("aria-valuetext");
  }
}

let scrollReportTimer: number | undefined;
editor.scrollDOM.addEventListener("scroll", () => {
  window.clearTimeout(scrollReportTimer);
  scrollReportTimer = window.setTimeout(() => {
    const extent = Math.max(0, editor.scrollDOM.scrollHeight - editor.scrollDOM.clientHeight);
    const fraction = extent > 0 ? Math.max(0, Math.min(1, editor.scrollDOM.scrollTop / extent)) : 0;
    post({ type: "scrollChanged", scrollFraction: fraction });
  }, 120);
}, { passive: true });

webkitWindow.scholiumEditor = {
  /** @param {string} text @param {string} sessionID @param {string} documentID */
  setDocument(text: string, sessionID: string, documentID: string, startingFingerprint: string) {
    bridgeSessionID = sessionID;
    bridgeDocumentID = documentID;
    bridgeFingerprint = startingFingerprint;
    documentVersion = 0;
    const separator = text.includes("\r\n") ? "\r\n" : "\n";
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
      effects: modeCompartment.reconfigure(mode === "livePreview" ? livePreview : []),
    });
    editor.dom.classList.toggle("scholium-live-mode", mode === "livePreview");
    editor.dom.classList.toggle("scholium-source-mode", mode !== "livePreview");
    editor.contentDOM.setAttribute(
      "aria-label",
      mode === "livePreview" ? "Markdown live preview editor" : "Markdown source editor",
    );
    window.requestAnimationFrame(refreshEditorAccessibilityValue);
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

  getText() {
    return editor.state.sliceDoc();
  },

  getSelection() {
    const selection = editor.state.selection.main;
    if (selection.empty) return null;
    const from = Math.min(selection.from, selection.to);
    const to = Math.max(selection.from, selection.to);
    return {
      startLine: editor.state.doc.lineAt(from).number,
      endLine: editor.state.doc.lineAt(to).number,
      excerpt: editor.state.sliceDoc(from, Math.min(to, from + 2000)),
      utf16LowerBound: from,
      utf16UpperBound: to,
      contextBefore: editor.state.sliceDoc(Math.max(0, from - 48), from),
      contextAfter: editor.state.sliceDoc(to, Math.min(editor.state.doc.length, to + 48)),
    };
  },

  synchronizeCommittedText(expectedText: string, committedText: string, startingFingerprint: string) {
    if (editor.state.sliceDoc() !== expectedText) return false;

    bridgeFingerprint = startingFingerprint;
    documentVersion = 0;
    const separator = committedText.includes("\r\n") ? "\r\n" : "\n";
    editor.dispatch({
      changes: replacementChange(editor.state.doc.toString(), committedText),
      effects: lineSeparatorCompartment.reconfigure(EditorState.lineSeparator.of(separator)),
      annotations: [
        Transaction.addToHistory.of(false),
        programmaticDocumentChange.of(true),
      ],
    });
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

  openFind() {
    return openSearchPanel(editor);
  },

  findNext() {
    return moveToNextSearchMatch(editor);
  },

  findPrevious() {
    return moveToPreviousSearchMatch(editor);
  },

  closeFind() {
    const closed = closeSearchPanel(editor);
    editor.focus();
    return closed;
  },

  markClean() {
    dirty = false;
    post({ type: "stateChanged", dirty: false });
  },

  focus() {
    editor.focus();
  },
};

post({ type: "ready" });
