import {EditorState, Text, Transaction, type TransactionSpec} from "@codemirror/state";
import {isolateHistory} from "@codemirror/commands";
import {syntaxTree} from "@codemirror/language";
import {scholiumMarkdownContentLanguage} from "./language";
import {appendMarkdownBlocks} from "./markdown-fragment";
import {exactInsertionEffects, exactSourceFitsChanges, exactSourceState} from "./exact-source-history";
import {exactOffsetForNormalizedOffset, frontmatterBoundary, normalizedDocumentText} from "./state";
import {exactSourceFits} from "./source-capacity";
import {bibliographyPrefix, bibliographyClose, documentPrefix, maximumFallbackLength, maximumFields,
  citationLinkSource, decodeFieldPayload, decodeDocumentPayload, fieldPayload, encodeDocumentData, isCitationDestination, isCompletedFieldCode,
  type SourceRange, type FieldKind, type FieldInput, type BibliographyStyle, type FieldSignature} from "./zotero-field-envelope";
export {encodeDocumentData, isCompletedFieldCode} from "./zotero-field-envelope";
export type {SourceRange, FieldKind, FieldInput, BibliographyStyle, FieldSignature} from "./zotero-field-envelope";

export interface ProjectedField extends FieldInput {
  cachedText: string;
  noteIndex: 0;
  adjacent: boolean;
  range: SourceRange;
  fallbackRange: SourceRange;
  manualTextChanged: boolean;
}
export interface ProjectionDiagnostic extends SourceRange {
  kind: "malformed-envelope" | "unsupported-envelope" | "duplicate-id" | "duplicate-document" | "unsupported-text" | "unsupported-context";
  message: string;
}
export interface FieldProjection {
  source: string;
  fields: readonly ProjectedField[];
  documentData: string | null;
  bibliographyStyle: BibliographyStyle | null;
  acceptedFields: readonly FieldSignature[] | null;
  citationStateStale: boolean;
  documentRange: SourceRange | null;
  diagnostics: readonly ProjectionDiagnostic[];
}
export interface SourceReplacement extends SourceRange {expected: string; insert: string}
export interface FieldOperation {
  updates?: readonly {id: string; code?: string; text?: string; delete?: boolean; unlink?: boolean}[];
  insertions?: readonly {at: number; field: FieldInput; replacement?: {to: number; expected: string}}[];
  documentData?: string;
  bibliographyStyle?: BibliographyStyle;
  acceptCurrentFields?: boolean;
}
export interface StagedFieldOperation {expectedSource: string; source: string; changes: readonly SourceReplacement[]}
const markdownParser = scholiumMarkdownContentLanguage.language.parser;
const literalNodeNames = new Set(["FencedCode", "CodeBlock", "InlineCode", "ObsidianComment", "ObsidianCommentBlock",
  "UnclosedObsidianComment", "UnclosedObsidianCommentBlock", "UnclosedBlockMath", "HTMLBlock"]);
const unsupportedNodeNames = new Set(["FootnoteDefinition", "InlineFootnote", "WikiLink", "LinkReference", "Autolink", "Image",
  "InlineMath", "BlockMath", "Table", "Blockquote", "Callout", "BulletList", "OrderedList", "ATXHeading1", "ATXHeading2",
  "ATXHeading3", "ATXHeading4", "ATXHeading5", "ATXHeading6", "SetextHeading1", "SetextHeading2"]);
const htmlDocument = (html: string) => new DOMParser().parseFromString(`<html><body>${html}</body></html>`, "text/html");

/** Bounded caret affordance; a staged command still validates complete exact source. */
export function citationInsertionContextSupported(state: EditorState, position: number): boolean {
  if (!Number.isSafeInteger(position) || position < 0 || position > state.doc.length) return false;
  for (let node = syntaxTree(state).resolveInner(position, -1); node; node = node.parent!) {
    if (literalNodeNames.has(node.name) || unsupportedNodeNames.has(node.name)
      || ["Link", "HTMLTag", "Comment", "CommentBlock", "Escape"].includes(node.name)) return false;
    if (!node.parent) break;
  }
  return true;
}

function escapeMarkdown(text: string) {
  // All CommonMark ASCII punctuation is escaped, including Scholium additions.
  return text.replace(/[!-/:-@[-`{-~]/g, "\\$&");
}

interface FormattedText {text: string; emphasis: number}
function formattingProjection(root: Element, vendor = false): FormattedText[][] {
  const result: FormattedText[][] = [];
  const inline = (node: Node, paragraph: FormattedText[], emphasis: number) => {
    if (node.nodeType === 3) {
      const text = node.textContent ?? "", previous = paragraph.at(-1);
      if (!text) return;
      if (previous?.emphasis === emphasis) previous.text += text;
      else paragraph.push({text, emphasis});
      return;
    }
    const element = node as Element;
    if (["p", "div"].includes(element.localName)) throw new Error("Unsupported HTML block context; formatting fidelity is unproven.");
    if (["i", "em"].includes(element.localName)) emphasis |= 1;
    if (["b", "strong"].includes(element.localName)) emphasis |= 2;
    for (const child of Array.from(node.childNodes)) inline(child, paragraph, emphasis);
  };
  const appendParagraph = (element: Element) => {
    if (vendor && element.localName !== "body" && !element.textContent?.trim()) {
      throw new Error("Unsupported HTML empty block; formatting fidelity is unproven.");
    }
    const paragraph: FormattedText[] = [];
    for (const child of Array.from(element.childNodes)) inline(child, paragraph, 0);
    if (paragraph.length) result.push(paragraph);
  };
  const container = (element: Element) => {
    const children = Array.from(element.childNodes);
    if (!children.some(child => child.nodeType === 1 && ["p", "div"].includes((child as Element).localName))) {
      appendParagraph(element);
      return;
    }
    for (const child of children) {
      if (child.nodeType === 3 && !child.textContent?.trim()) continue;
      if (child.nodeType !== 1) throw new Error("Unsupported HTML mixed block context; formatting fidelity is unproven.");
      const block = child as Element;
      if (block.localName === "p" || (vendor && block.className === "csl-entry")) appendParagraph(block);
      else if (vendor && block.className === "csl-bib-body") container(block);
      else throw new Error("Unsupported HTML mixed block context; formatting fidelity is unproven.");
    }
  };
  container(root);
  return result;
}

function normalizeEmphasis(element: Element, inherited = 0) {
  const emphasis = element.localName === "i" ? 1 : element.localName === "b" ? 2 : 0;
  for (const child of Array.from(element.children)) normalizeEmphasis(child, inherited | emphasis);
  // Repeated HTML emphasis has one effective style; repeated Markdown delimiters do not.
  if (emphasis && (inherited & emphasis)) {
    element.replaceWith(...Array.from(element.childNodes));
    return;
  }
  for (const child of Array.from(element.children)) {
    if (!["i", "b"].includes(child.localName)) continue;
    let following = child.nextSibling, merged = false;
    while (following?.nodeType === 1 && (following as Element).localName === child.localName) {
      const adjacent = following as Element;
      child.append(...Array.from(adjacent.childNodes));
      adjacent.remove();
      merged = true;
      following = child.nextSibling;
    }
    if (merged) normalizeEmphasis(child, inherited | emphasis);
  }
}

/** Bounded structural HTML subset. Original vendor strings remain opaque. */
export function vendorTextToMarkdown(html: string, newline = "\n"): string {
  if (html.length > maximumFallbackLength) throw new Error("The citation render cache exceeds the supported size.");
  const stack: Array<{name: string; className?: string}> = [];
  let cursor = 0;
  for (const match of html.matchAll(/<[^>]*>/g)) {
    if (html.slice(cursor, match.index).includes("<")) throw new Error("Malformed HTML text.");
    const tag = /^<(\/?)(p|i|b|div)(?: class="(csl-bib-body|csl-entry)")?[ \t]*>$/i.exec(match[0]);
    if (!tag || (tag[3] && (tag[1] || tag[2].toLowerCase() !== "div"
      || !["csl-bib-body", "csl-entry"].includes(tag[3])))) {
      throw new Error("Unsupported HTML or attributes; formatting fidelity is unproven.");
    }
    const name = tag[2].toLowerCase();
    if (tag[1]) {
      if (stack.pop()?.name !== name) throw new Error("Unbalanced HTML text.");
    } else {
      if (name === "div" && !tag[3]) throw new Error("Unsupported HTML block wrapper.");
      if (["p", "div"].includes(name) && (stack.some(value => value.name !== "div" || value.className === "csl-entry")
        || (tag[3] === "csl-bib-body" && stack.length))) {
        throw new Error("Unsupported HTML nested block context; formatting fidelity is unproven.");
      }
      stack.push({name, className: tag[3]});
    }
    cursor = match.index! + match[0].length;
  }
  if (stack.length || html.slice(cursor).includes("<")) throw new Error("Unbalanced HTML text.");
  const document = htmlDocument(html);
  for (const element of Array.from(document.body.querySelectorAll("i,b"))) {
    if (!element.textContent || /^\s|\s$/.test(element.textContent)) throw new Error("Unsupported HTML emphasis boundary.");
  }
  const expected = formattingProjection(document.body, true);
  normalizeEmphasis(document.body);
  const render = (node: Node): string => {
    if (node.nodeType === 3) return escapeMarkdown(node.textContent ?? "");
    if (node.nodeType !== 1) throw new Error("Unsupported HTML node.");
    const element = node as Element;
    const children = Array.from(node.childNodes);
    const hasBlockChildren = children.some(child => child.nodeType === 1 && ["p", "div"].includes((child as Element).localName));
    const content = children.map(child => {
      if ((element.localName === "body" || element.className === "csl-bib-body")
        && hasBlockChildren && child.nodeType === 3 && !child.textContent?.trim()) return "";
      return render(child);
    }).join("");
    switch (element.localName) {
    case "body": return content;
    case "p": return `${content}\n\n`;
    case "div": return element.className === "csl-entry" ? `${content}\n\n` : content;
    case "i":
    case "b":
      if (!content || /^\s|\s$/.test(content)) throw new Error("Unsupported HTML emphasis boundary.");
      return element.localName === "i" ? `*${content}*` : `**${content}**`;
    default: throw new Error("Unsupported HTML node.");
    }
  };
  const markdown = render(document.body).replace(/\n\n$/, "");
  // Delimiter admission alone cannot establish text or effective emphasis fidelity.
  const rendered = renderVisibleMarkdown(markdown);
  if (JSON.stringify(formattingProjection(rendered)) !== JSON.stringify(expected)) {
    throw new Error("Unsupported HTML paragraph or emphasis boundary; Markdown formatting fidelity is unproven.");
  }
  return markdown.replaceAll("\n", newline);
}

function renderVisibleMarkdown(markdown: string): HTMLElement {
  const normalized = normalizedDocumentText(markdown);
  markdownParser.parse(normalized).iterate({enter(node) {
    if (["Document", "Paragraph", "Emphasis", "StrongEmphasis", "EmphasisMark", "Escape", "Entity"].includes(node.name)) return;
    throw new Error(`Unsupported visible Markdown: ${node.name}.`);
  }});
  const document = htmlDocument("");
  const rendered = document.createElement("div");
  appendMarkdownBlocks(normalized, rendered);
  return rendered;
}

/** Uses the actual Markdown fragment renderer, never the stored vendor cache. */
export function markdownVisibleText(markdown: string): string {
  return renderVisibleMarkdown(markdown).textContent ?? "";
}

function fieldEnvelope(field: FieldInput, fallback: string, newline = "\n") {
  if (fallback.length > maximumFallbackLength) throw new Error("The citation fallback exceeds the supported size.");
  const payload = fieldPayload(field);
  if (field.kind === "citation") {
    if (/[\r\n]/.test(fallback)) throw new Error("Citation fields require inline Markdown.");
    return `[${fallback}](scholium-zotero:1:${payload})`;
  }
  return `${bibliographyPrefix}1:${payload}-->${newline}${newline}${fallback}${newline}${newline}${bibliographyClose}`;
}
export function encodeField(field: FieldInput, newline = "\n") {
  return fieldEnvelope(field, vendorTextToMarkdown(field.text, newline), newline);
}

interface ParserContexts {
  ignored: SourceRange[];
  unsupported: SourceRange[];
  escaped: SourceRange[];
  links: SourceRange[];
  comments: SourceRange[];
}
function parserContexts(source: string): ParserContexts {
  const normalized = normalizedDocumentText(source);
  const result: ParserContexts = {ignored: [], unsupported: [], escaped: [], links: [], comments: []};
  const map = (range: SourceRange) => ({from: exactOffsetForNormalizedOffset(source, range.from)!, to: exactOffsetForNormalizedOffset(source, range.to)!});
  const doc = Text.of(normalized.split("\n")), metadata = frontmatterBoundary(doc);
  if (metadata.unclosed) result.ignored.push({from: 0, to: source.length});
  else if (metadata.endLine) result.ignored.push(map({from: 0, to: Math.min(doc.length, doc.line(metadata.endLine).to + 1)}));
  const htmlStack: Array<{name: string; from: number}> = [];
  markdownParser.parse(normalized).iterate({enter(node) {
    if (literalNodeNames.has(node.name)) {
      result.ignored.push(map(node)); return false;
    }
    if (node.name === "Escape") { result.escaped.push(map(node)); return false; }
    if (["Comment", "CommentBlock"].includes(node.name)) {
      const raw = normalized.slice(node.from, node.to);
      if (raw.startsWith(bibliographyPrefix) || raw.startsWith(documentPrefix) || raw.startsWith(bibliographyClose)) result.comments.push(map(node));
      else result.ignored.push(map(node));
      return false;
    }
    if (node.name === "HTMLTag") {
      const tag = /^<(\/?)([A-Za-z][A-Za-z0-9-]*)\b/.exec(normalized.slice(node.from, node.to));
      if (tag) {
        const name = tag[2].toLowerCase();
        if (tag[1]) {
          const opening = htmlStack.pop();
          if (opening) result.ignored.push(map({from: opening.from, to: node.to}));
          if (opening?.name !== name) result.ignored.push(map({from: node.from, to: normalized.length}));
        } else if (!/\/\s*>$/.test(normalized.slice(node.from, node.to)) && !["br", "hr", "img", "input", "meta", "link", "wbr"].includes(name)) htmlStack.push({name, from: node.from});
      }
      result.ignored.push(map(node)); return false;
    }
    if (node.name === "Link") {
      let reserved = false;
      for (let child = node.node.firstChild; child; child = child.nextSibling) {
        if (child.name === "URL" && isCitationDestination(normalized.slice(child.from, child.to).replace(/^<|>$/g, ""))) reserved = true;
      }
      if (reserved) result.links.push(map(node));
      else { result.unsupported.push(map(node)); result.ignored.push(map(node)); return false; }
      return;
    }
    if (unsupportedNodeNames.has(node.name)) {
      result.unsupported.push(map(node)); return false;
    }
  }});
  for (const opening of htmlStack) result.ignored.push(map({from: opening.from, to: normalized.length}));
  return result;
}
function intersects(left: SourceRange, right: SourceRange) { return left.from < right.to && left.to > right.from; }
function markerOnly(source: string, range: SourceRange) {
  const lineFrom = source.lastIndexOf("\n", range.from - 1) + 1;
  const following = source.indexOf("\n", range.to);
  const lineTo = following < 0 ? source.length : following;
  const prefix = source.slice(lineFrom, range.from), suffix = source.slice(range.to, lineTo);
  // Generated metadata is one exact marker at column zero. A file's initial
  // BOM is a preserved prefix, while horizontal whitespace is never metadata.
  return (prefix === "" || (lineFrom === 0 && prefix === "\uFEFF"))
    && (suffix === "" || (following >= 0 && suffix === "\r"));
}

/** Exact source is the sole authority; this parsed projection grants no mutation. */
export function projectFields(source: string): FieldProjection {
  const fields: ProjectedField[] = [], diagnostics: ProjectionDiagnostic[] = [];
  let documentData: string | null = null, documentRange: SourceRange | null = null;
  let bibliographyStyle: BibliographyStyle | null = null, acceptedFields: readonly FieldSignature[] | null = null;
  const contexts = parserContexts(source);
  const diagnose = (kind: ProjectionDiagnostic["kind"], range: SourceRange, message: string) => diagnostics.push({...range, kind, message});
  const protectedField = (range: SourceRange) => [...contexts.ignored, ...contexts.unsupported].some(other => intersects(range, other));
  const append = (field: FieldInput, range: SourceRange, fallbackRange: SourceRange) => {
    if (fields.length >= maximumFields) throw new Error("Too many source citation fields.");
    if (protectedField(range)) { diagnose("unsupported-context", range, "The complete field overlaps a protected source context."); return; }
    const fallback = source.slice(fallbackRange.from, fallbackRange.to);
    const generated = vendorTextToMarkdown(field.text);
    fields.push({...field, text: markdownVisibleText(fallback), cachedText: field.text, noteIndex: 0, adjacent: false,
      range, fallbackRange, manualTextChanged: normalizedDocumentText(fallback) !== generated});
  };
  const malformed = (range: SourceRange, error: unknown) => diagnose(error instanceof Error && /HTML|Markdown|render cache|render.*size/.test(error.message)
    ? "unsupported-text" : error instanceof Error && /version/.test(error.message) ? "unsupported-envelope" : "malformed-envelope",
    range, error instanceof Error ? error.message : "Invalid source field.");
  for (const range of contexts.links) {
    if (contexts.ignored.some(other => intersects(range, other))) continue;
    try {
      const parsed = citationLinkSource(source.slice(range.from, range.to));
      if (!parsed) throw new Error("Invalid citation link carrier.");
      append(parsed.field, range, {from: range.from + parsed.fallbackRange.from, to: range.from + parsed.fallbackRange.to});
    } catch (error) { malformed(range, error); }
  }
  const consumed: SourceRange[] = [];
  for (const comment of contexts.comments) {
    if (contexts.ignored.some(other => intersects(comment, other)) || consumed.some(other => intersects(comment, other))) continue;
    const raw = source.slice(comment.from, comment.to);
    if (!markerOnly(source, comment) || !/^<!--[^\r\n]*-->$/.test(raw)) {
      diagnose("malformed-envelope", comment, "Document and bibliography markers require metadata-only lines."); continue;
    }
    try {
      if (raw.startsWith(documentPrefix)) {
        const match = /^<!--scholium-zotero-document:1:([A-Za-z0-9+/=]*)-->$/.exec(raw);
        if (!match) throw new Error("Unknown document envelope version.");
        if (documentRange) { diagnose("duplicate-document", comment, "More than one source-owned document state."); continue; }
        if (protectedField(comment)) { diagnose("unsupported-context", comment, "Document state is inside a protected source context."); continue; }
        const data = decodeDocumentPayload(match[1]);
        documentData = data.data; bibliographyStyle = data.bibliographyStyle ?? null; acceptedFields = data.acceptedFields ?? null; documentRange = comment;
      } else if (raw === bibliographyClose) {
        diagnose("malformed-envelope", comment, "Bibliography close marker has no matching opening marker.");
      } else {
        const match = /^<!--scholium-zotero-field:1:([A-Za-z0-9+/=]*)-->$/.exec(raw);
        if (!match) throw new Error("Unknown bibliography envelope version.");
        const field = decodeFieldPayload(match[1], "bibliography");
        const close = contexts.comments.find(other => other.from > comment.to && source.slice(other.from, other.to) === bibliographyClose);
        if (!close || !markerOnly(source, close)) throw new Error("Missing bibliography close marker.");
        const nested = contexts.comments.some(other => other.from > comment.to && other.from < close.from);
        if (nested) throw new Error("Nested metadata markers cannot confer bibliography authority.");
        const middle = source.slice(comment.to, close.from);
        const start = /^(?:\r\n|\n){2}/.exec(middle), end = /(?:\r\n|\n){2}$/.exec(middle);
        if (!start || !end || start[0].length + end[0].length > middle.length) throw new Error("Bibliography fallback requires blank-line separators.");
        const range = {from: comment.from, to: close.to};
        consumed.push(range);
        append(field, range, {from: comment.to + start[0].length, to: close.from - end[0].length});
      }
    } catch (error) { malformed(comment, error); }
  }
  // Reserved source tokens not owned by proved carrier syntax are diagnostics,
  // never alternate regex authority or ordinary external links.
  const covered = [...contexts.links, ...contexts.comments, ...consumed];
  for (const match of source.matchAll(/scholium-zotero:|<!--scholium-zotero-(?:field|document):/gi)) {
    const from = match.index!, range = {from, to: from + match[0].length};
    if ([...contexts.ignored, ...contexts.escaped, ...covered].some(other => from >= other.from && from < other.to)) continue;
    const unsupported = contexts.unsupported.find(other => from >= other.from && from < other.to);
    diagnose(unsupported ? "unsupported-context" : "malformed-envelope", unsupported ?? range,
      "Citation metadata is not in a supported parser-owned carrier.");
  }
  fields.sort((left, right) => left.range.from - right.range.from);
  const counts = new Map<string, number>();
  for (const field of fields) counts.set(field.id, (counts.get(field.id) ?? 0) + 1);
  for (const field of fields) {
    if (counts.get(field.id)! > 1) diagnose("duplicate-id", field.range, `Copied host occurrence ID ${field.id} requires explicit resolution.`);
  }
  for (let index = fields.length - 1; index >= 0; index--) {
    if (counts.get(fields[index].id)! > 1) fields.splice(index, 1);
  }
  if (diagnostics.some(diagnostic => diagnostic.kind === "duplicate-document")) {
    documentData = null; documentRange = null; bibliographyStyle = null; acceptedFields = null;
  }
  for (let index = 0; index < fields.length; index++) {
    const field = fields[index];
    const previous = fields[index - 1], next = fields[index + 1];
    field.adjacent = !!((previous && source.slice(previous.range.to, field.range.from).trim() === "")
      || (next && source.slice(field.range.to, next.range.from).trim() === ""));
  }
  const current = fields.map(({id, code}) => ({id, code}));
  const citationStateStale = acceptedFields === null ? fields.length > 0 : JSON.stringify(acceptedFields) !== JSON.stringify(current);
  return {source, fields, documentData, bibliographyStyle, acceptedFields, citationStateStale, documentRange, diagnostics};
}

const stateCatalogs = new WeakMap<object, FieldProjection>();
/** Same immutable exact-source owner means the same catalog across caret/focus changes. */
export function projectFieldsForState(state: EditorState): FieldProjection {
  const mirror = state.field(exactSourceState, false), owner = mirror ?? state.doc;
  const existing = stateCatalogs.get(owner);
  if (existing) return existing;
  let reserved = false, carry = "";
  for (const chunk of state.doc.iter()) {
    const scanned = carry + chunk;
    if (/scholium-zotero/i.test(scanned)) { reserved = true; break; }
    carry = scanned.slice(-14);
  }
  const projection: FieldProjection = reserved
    ? projectFields(mirror?.text ?? state.doc.toString())
    : {
      get source() { return mirror?.text ?? state.doc.toString(); },
      fields: [], documentData: null, bibliographyStyle: null, acceptedFields: null,
      citationStateStale: false, documentRange: null, diagnostics: [],
    };
  stateCatalogs.set(owner, projection);
  return projection;
}

/** Exact metadata spans admitted by the complete source catalog; never guessed in a viewport. */
export function fieldMetadataRanges(projection: FieldProjection): readonly SourceRange[] {
  if (projection.diagnostics.length) return [];
  const ranges: SourceRange[] = projection.documentRange ? [projection.documentRange] : [];
  for (const field of projection.fields) {
    if (field.kind !== "bibliography") continue;
    ranges.push({from: field.range.from, to: projection.source.indexOf("-->", field.range.from) + 3});
    ranges.push({from: field.range.to - bibliographyClose.length, to: field.range.to});
  }
  return ranges;
}
function boundary(source: string, offset: number) {
  if (!Number.isSafeInteger(offset) || offset < 0 || offset > source.length) return false;
  if (offset === 0 || offset === source.length) return true;
  const before = source.charCodeAt(offset - 1), after = source.charCodeAt(offset);
  return !(before === 13 && after === 10) && !(before >= 0xD800 && before <= 0xDBFF && after >= 0xDC00 && after <= 0xDFFF);
}
function preferredNewline(source: string, at = 0) {
  const following = /\r\n|\n/.exec(source.slice(at));
  return following?.[0] ?? (/\r\n|\n/.exec(source)?.[0] ?? "\n");
}

function blockInsertion(source: string, range: SourceRange, insert: string, newline: string) {
  const before = source.slice(0, range.from), after = source.slice(range.to);
  const prefix = before.length === 0 || before === "\uFEFF" || /(?:\r\n|\n){2}$/.test(before) ? ""
    : /(?:\r\n|\n)$/.test(before) ? newline : newline + newline;
  const suffix = after.length === 0 || /^(?:\r\n|\n){2}/.test(after) ? ""
    : /^(?:\r\n|\n)/.test(after) ? newline : newline + newline;
  return prefix + insert + suffix;
}

/** Pure staging against one immutable source; caller owns command/lifecycle authority. */
export function stageFieldOperation(projection: FieldProjection, operation: FieldOperation): StagedFieldOperation {
  if (projection.diagnostics.length) throw new Error("The source contains unresolved citation field diagnostics.");
  const source = projection.source, changes: SourceReplacement[] = [], touched = new Set<string>();
  const replace = (range: SourceRange, insert: string, first = false) => {
    const expected = source.slice(range.from, range.to);
    if (expected !== insert) {
      const change = {...range, expected, insert};
      if (first) changes.unshift(change); else changes.push(change);
    }
  };
  for (const update of operation.updates ?? []) {
    if (touched.has(update.id)) throw new Error("A field was updated twice in one operation.");
    touched.add(update.id);
    const field = projection.fields.find(field => field.id === update.id);
    if (!field) throw new Error("The addressed citation field no longer exists.");
    if ((update.delete || update.unlink) && (update.code !== undefined || update.text !== undefined || (update.delete && update.unlink))) {
      throw new Error("Field deletion and unlinking cannot also replace code or text.");
    }
    if (update.delete || update.unlink) {
      replace(field.range, update.unlink ? source.slice(field.fallbackRange.from, field.fallbackRange.to) : "");
      continue;
    }
    const code = update.code ?? field.code, cachedText = update.text ?? field.cachedText;
    const newline = preferredNewline(source, field.fallbackRange.from);
    const fallback = update.text === undefined ? source.slice(field.fallbackRange.from, field.fallbackRange.to)
      : vendorTextToMarkdown(update.text, newline);
    let kind: FieldKind = code.startsWith("BIBL ") ? "bibliography"
      : code.startsWith("ITEM CSL_CITATION ") ? "citation" : field.kind;
    // A code callback may precede the text callback during a kind conversion.
    // Keep the representable block until its inline text arrives; finish rejects
    // an incomplete code/kind pairing rather than committing that intermediate.
    if (kind === "citation" && /[\r\n]/.test(fallback) && update.text === undefined) kind = field.kind;
    let encoded = fieldEnvelope({id: field.id, kind, code, text: cachedText}, fallback, newline);
    if (field.kind !== "bibliography" && kind === "bibliography") encoded = blockInsertion(source, field.range, encoded, newline);
    replace(field.range, encoded);
  }
  const contexts = parserContexts(source), ids = new Set(projection.fields.map(field => field.id));
  for (const insertion of operation.insertions ?? []) {
    if (ids.has(insertion.field.id)) throw new Error("Insertion would duplicate a host occurrence ID.");
    ids.add(insertion.field.id);
    const range = {from: insertion.at, to: insertion.replacement?.to ?? insertion.at};
    if (!boundary(source, range.from) || !boundary(source, range.to) || range.to < range.from) throw new Error("Insertion is not a whole-source boundary.");
    if (insertion.replacement && source.slice(range.from, range.to) !== insertion.replacement.expected) throw new Error("Citation insertion query no longer matches its source range.");
    const protectedRanges = [...contexts.ignored, ...contexts.escaped, ...contexts.unsupported];
    if (protectedRanges.some(other => range.from >= other.from && range.from < other.to
      || (range.to > range.from && intersects(range, other)))) throw new Error("Insertion is in a protected source context.");
    if (projection.fields.some(field => intersects(range, field.range) || range.from > field.range.from && range.from < field.range.to)
      || (projection.documentRange && (intersects(range, projection.documentRange)
        || range.from > projection.documentRange.from && range.from < projection.documentRange.to))) throw new Error("Insertion would split source-owned field metadata.");
    const newline = preferredNewline(source, range.from);
    let encoded = encodeField(insertion.field, newline);
    if (insertion.field.kind === "bibliography") encoded = blockInsertion(source, range, encoded, newline);
    replace(range, encoded);
  }
  const apply = (patches: readonly SourceReplacement[]) => {
    let candidate = source;
    for (const patch of [...patches].reverse()) candidate = candidate.slice(0, patch.from) + patch.insert + candidate.slice(patch.to);
    return candidate;
  };
  changes.sort((a, b) => a.from - b.from || a.to - b.to);
  const candidateFields = projectFields(apply(changes));
  if (candidateFields.diagnostics.length) throw new Error("The staged source contains unresolved citation diagnostics.");
  const expectedIDs = projection.fields.filter(field => !(operation.updates ?? []).some(update => update.id === field.id && (update.delete || update.unlink))).map(field => field.id);
  expectedIDs.push(...(operation.insertions ?? []).map(insertion => insertion.field.id));
  if (expectedIDs.length !== candidateFields.fields.length || expectedIDs.some(id => !candidateFields.fields.some(field => field.id === id))) throw new Error("The candidate field is not recognized in its source context.");
  let accepted = projection.acceptedFields;
  if (operation.acceptCurrentFields) {
    if (candidateFields.fields.some(field => !isCompletedFieldCode(field))) throw new Error("The Zotero command left incomplete citation field code.");
    accepted = candidateFields.fields.map(({id, code}) => ({id, code}));
  }
  const data = operation.documentData ?? projection.documentData;
  const style = operation.bibliographyStyle ?? projection.bibliographyStyle;
  if ((operation.documentData !== undefined && operation.documentData !== projection.documentData)
    || (operation.bibliographyStyle !== undefined && JSON.stringify(style) !== JSON.stringify(projection.bibliographyStyle))
    || (operation.acceptCurrentFields && JSON.stringify(accepted) !== JSON.stringify(projection.acceptedFields))) {
    if (data === null) throw new Error("Citation acceptance and bibliography style require source-owned Zotero document data.");
    const encoded = encodeDocumentData(data, style, accepted);
    if (projection.documentRange) replace(projection.documentRange, encoded);
    else {
      const doc = Text.of(normalizedDocumentText(source).split("\n")), metadata = frontmatterBoundary(doc);
      const at = metadata.endLine ? exactOffsetForNormalizedOffset(source, Math.min(doc.length, doc.line(metadata.endLine).to + 1))!
        : (source.charCodeAt(0) === 0xFEFF ? 1 : 0);
      const newline = preferredNewline(source, at);
      const separator = metadata.endLine && at === source.length && !source.endsWith("\n") ? newline : "";
      replace({from: at, to: at}, separator + encoded + newline + newline, true);
    }
  }
  changes.sort((a, b) => a.from - b.from || a.to - b.to);
  const merged: SourceReplacement[] = [];
  for (const change of changes) {
    if (!boundary(source, change.from) || !boundary(source, change.to) || change.to < change.from) throw new Error("Invalid source change boundary.");
    const previous = merged.at(-1);
    if (previous && previous.from === previous.to && previous.from === change.from) {
      previous.to = change.to; previous.expected = change.expected; previous.insert += change.insert;
    } else {
      if (previous && change.from < previous.to) throw new Error("Overlapping citation source changes.");
      merged.push({...change});
    }
  }
  const candidate = apply(merged);
  if (!exactSourceFits(candidate)) throw new Error("The citation command exceeds the supported Markdown source size.");
  const projected = projectFields(candidate);
  if (projected.diagnostics.length || projected.fields.length !== candidateFields.fields.length) throw new Error("The final source is not a valid citation projection.");
  if (operation.documentData !== undefined && projected.documentData !== operation.documentData) throw new Error("The document state is not recognized in its source context.");
  if (operation.bibliographyStyle !== undefined && JSON.stringify(projected.bibliographyStyle) !== JSON.stringify(operation.bibliographyStyle)) throw new Error("The bibliography style is not recognized in its source context.");
  if (operation.acceptCurrentFields && projected.citationStateStale) throw new Error("The citation acceptance signature does not match source.");
  return {expectedSource: source, source: candidate, changes: merged};
}

/** One checked event owns visible text and every opaque metadata replacement. */
export function fieldOperationTransaction(state: EditorState, operation: StagedFieldOperation): TransactionSpec | null {
  const source = state.field(exactSourceState).text;
  if (source !== operation.expectedSource) return null;
  let candidate = source, previous = -1;
  for (const change of operation.changes) {
    if (!boundary(source, change.from) || !boundary(source, change.to) || change.from < previous || change.to < change.from) return null;
    previous = change.to;
  }
  for (const change of [...operation.changes].reverse()) candidate = candidate.slice(0, change.from) + change.insert + candidate.slice(change.to);
  if (candidate !== operation.source) return null;
  let shift = 0;
  const effects = [], changes = [];
  for (const change of operation.changes) {
    if (source.slice(change.from, change.to) !== change.expected) return null;
    const from = normalizedDocumentText(source.slice(0, change.from)).length;
    const to = normalizedDocumentText(source.slice(0, change.to)).length;
    const insert = normalizedDocumentText(change.insert);
    changes.push({from, to, insert, exactInsert: change.insert});
    effects.push(...exactInsertionEffects(change.insert, from + shift));
    shift += insert.length - (to - from);
  }
  if (!exactSourceFitsChanges(state, changes)) return null;
  return {changes, effects, annotations: [Transaction.userEvent.of("input.scholium.zotero"), isolateHistory.of("full")]};
}
