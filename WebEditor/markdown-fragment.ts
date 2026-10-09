import {scanMath, type MathDialect, type MathProjection} from "./math";
import {scholiumMarkdownContentLanguage} from "./language";
import {
  tablePresentation,
  type TablePresentation,
  type TablePresentationCell,
} from "./table-presentation";
import {systemSymbolElement} from "./system-symbols";
import {localized, localizedTemplate} from "./localization";
import {linkAnnotationAfter} from "./link-annotation";
import {cjkPresentationRanges, languageForText} from "./text-language";
import {citationLinkSource, compactCitationLinkSource, isCitationDestination} from "./zotero-field-envelope";

export interface MarkdownFragmentCallout {
  identifier: string;
  label: string;
  meaning: string;
}

export interface MarkdownFragmentOptions {
  mathematics?: MathDialect;
  resolveCallout?: (rawKind: string) => MarkdownFragmentCallout;
  sourceOffset?: (fragmentOffset: number) => number;
  /** Exact authored slices when a fragment applies a display-only transform. */
  sourceText?: (from: number, to: number) => string;
}

interface MarkdownTreeCursor {
  readonly name: string;
  readonly from: number;
  readonly to: number;
  firstChild(): boolean;
  nextSibling(): boolean;
  parent(): boolean;
}

const inlineMarkerNodes = new Set([
  "EmphasisMark", "CodeMark", "LinkMark", "URL", "LinkTitle", "StrikethroughMark", "HighlightMark",
]);

// Rendered text is disposable, but its caret locations must come from the
// parser's exact slices, never a search for matching visible characters.
const renderedTextLocations = new WeakMap<Node, {at(offset: number): number; shift: number}>();

export function renderedTextSourceOffset(node: Node, offset: number): number | null {
  const location = renderedTextLocations.get(node);
  return location ? location.at(Math.max(0, Math.min(offset, node.textContent?.length ?? 0))) + location.shift : null;
}

/** Rebind an unchanged table DOM after an edit before its source range. */
export function rebaseRenderedSourceLocations(root: HTMLElement, delta: number) {
  const visit = (node: Node) => {
    const location = renderedTextLocations.get(node);
    if (location) location.shift += delta;
    for (const child of node.childNodes) visit(child);
  };
  visit(root);
  for (const element of root.querySelectorAll<HTMLElement>("[data-scholium-source-caret]")) {
    for (const key of ["scholiumSourceFrom", "scholiumSourceTo", "scholiumSourceCaret"] as const) {
      const value = element.dataset[key];
      if (value !== undefined && Number.isSafeInteger(Number(value))) element.dataset[key] = String(Number(value) + delta);
    }
  }
}

function appendLocatedText(text: string, parent: HTMLElement | DocumentFragment,
  options: MarkdownFragmentOptions, from = 0) {
  const node = documentFor(parent).createTextNode(text);
  renderedTextLocations.set(node, {at: offset => locatedOffset(options, from + offset), shift: 0});
  parent.append(node);
}

function documentFor(parent: Node): Document {
  if (parent.nodeType === 9) return parent as Document;
  const owner = parent.ownerDocument;
  if (!owner) throw new Error("Markdown fragments require an owning document.");
  return owner;
}

function applyTextLanguage(element: HTMLElement, text: string) {
  const language = languageForText(text);
  if (language) element.lang = language;
}

/** Adds only presentation language spans; the Markdown source remains intact. */
function appendTextWithLanguage(
  text: string,
  parent: HTMLElement | DocumentFragment,
  options: MarkdownFragmentOptions = {},
  from = 0,
) {
  const ranges = cjkPresentationRanges(text);
  if (ranges.length === 0) {
    appendLocatedText(text, parent, options, from);
    return;
  }
  let position = 0;
  const document = documentFor(parent);
  for (const range of ranges) {
    if (range.from > position) {
      appendLocatedText(text.slice(position, range.from), parent, options, from + position);
    }
    const cjk = document.createElement("span");
    cjk.lang = "zh-Hans";
    appendLocatedText(text.slice(range.from, range.to), cjk, options, from + range.from);
    parent.append(cjk);
    position = range.to;
  }
  if (position < text.length) appendLocatedText(text.slice(position), parent, options, from + position);
}

function locatedOffset(options: MarkdownFragmentOptions, offset: number) {
  return options.sourceOffset?.(offset) ?? offset;
}

function optionsAt(options: MarkdownFragmentOptions, offset: number): MarkdownFragmentOptions {
  return {
    ...options,
    sourceOffset: (nestedOffset) => locatedOffset(options, offset + nestedOffset),
    sourceText: options.sourceText && ((from, to) => options.sourceText!(offset + from, offset + to)),
  };
}

function optionsWithMap(
  options: MarkdownFragmentOptions,
  offsets: readonly number[],
): MarkdownFragmentOptions {
  return {
    ...options,
    sourceOffset: (nestedOffset) => locatedOffset(
      options,
      offsets[Math.max(0, Math.min(nestedOffset, offsets.length - 1))] ?? 0,
    ),
    sourceText: options.sourceText && ((from, to) => options.sourceText!(
      offsets[Math.max(0, Math.min(from, offsets.length - 1))] ?? 0,
      offsets[Math.max(0, Math.min(to, offsets.length - 1))] ?? 0,
    )),
  };
}

function directChildren(cursor: MarkdownTreeCursor) {
  const children: Array<{name: string; from: number; to: number}> = [];
  if (cursor.firstChild()) {
    do { children.push({name: cursor.name, from: cursor.from, to: cursor.to}); }
    while (cursor.nextSibling());
    cursor.parent();
  }
  return children;
}

function exactFragmentSource(source: string, from: number, to: number, options: MarkdownFragmentOptions) {
  return options.sourceText?.(from, to) ?? source.slice(from, to);
}

function parsedMath(cursor: MarkdownTreeCursor, source: string, kind: MathProjection["kind"]) {
  const children = directChildren(cursor);
  const content = children.find(child => child.name === "MathContent");
  const opening = children.find(child => child.name === "MathMark");
  if (!content || !opening) return null;
  const raw = source.slice(content.from, content.to);
  return {
    kind, from: cursor.from, to: cursor.to, contentFrom: content.from, contentTo: content.to,
    delimiterLength: opening.to - opening.from,
    content: kind === "display" ? raw.replace(/^[\r\n]+|[\r\n]+$/g, "")
      : raw.length > 2 && /^\s/.test(raw) && /\s$/.test(raw) && /\S/.test(raw) ? raw.slice(1, -1) : raw,
  } satisfies MathProjection;
}

function identifyProjectedLink(
  element: HTMLElement,
  target: string,
  from: number,
  to: number,
  caret: number,
  options: MarkdownFragmentOptions,
) {
  element.dataset.scholiumLinkTarget = target;
  element.dataset.scholiumSourceFrom = String(locatedOffset(options, from));
  element.dataset.scholiumSourceTo = String(locatedOffset(options, to));
  element.dataset.scholiumSourceCaret = String(locatedOffset(options, caret));
}

function appendInlineMarkdownNode(
  cursor: MarkdownTreeCursor,
  source: string,
  parent: HTMLElement | DocumentFragment,
  options: MarkdownFragmentOptions,
) {
  const document = documentFor(parent);
  const raw = source.slice(cursor.from, cursor.to);
  if (inlineMarkerNodes.has(cursor.name)) return;
  if (cursor.name === "InlineMath") {
    const expression = parsedMath(cursor, source, "inline");
    if (expression) appendMath(expression, parent, options,
      exactFragmentSource(source, cursor.from, cursor.to, options));
    else appendTextWithLanguage(raw, parent, options, cursor.from);
    return;
  }
  if (cursor.name === "InlineCode") {
    const code = document.createElement("code");
    code.dir = "ltr";
    const opening = raw.match(/^`+/)?.[0] ?? "";
    const closing = raw.endsWith(opening) ? opening.length : 0;
    let text = "";
    let offsets: number[] = [];
    for (let position = opening.length; position < raw.length - closing; position++) {
      offsets.push(cursor.from + position);
      const character = raw[position];
      text += /[\r\n]/.test(character) ? " " : character;
      if (character === "\r" && raw[position + 1] === "\n") position++;
    }
    offsets.push(cursor.to - closing);
    if (text.startsWith(" ") && text.endsWith(" ") && /[^ ]/.test(text)) {
      text = text.slice(1, -1);
      offsets = offsets.slice(1, -1);
    }
    appendLocatedText(text, code, optionsWithMap(options, offsets));
    parent.append(code);
    return;
  }
  if (cursor.name === "Link") {
    const children = directChildren(cursor);
    const opening = children.find(child => child.name === "LinkMark" && source.slice(child.from, child.to) === "[");
    const closing = children.find(child => child.name === "LinkMark" && source.slice(child.from, child.to) === "]");
    const url = children.find(child => child.name === "URL");
    const target = url ? source.slice(url.from, url.to).replace(/^<|>$/g, "") : null;
    if (target && isCitationDestination(target)) {
      try {
        const citation = compactCitationLinkSource(raw) ?? citationLinkSource(raw);
        if (!citation) throw new Error("Invalid citation carrier.");
        const span = document.createElement("span");
        span.className = "cm-live-citation";
        span.dir = "auto";
        appendInlineMarkdownPlain(raw.slice(citation.fallbackRange.from, citation.fallbackRange.to), span,
          optionsAt(options, cursor.from + citation.fallbackRange.from));
        parent.append(span);
      } catch {
        // Malformed managed metadata remains inspectable and cannot become an
        // ordinary application URL or projected link.
        appendTextWithLanguage(raw, parent, options, cursor.from);
      }
      return;
    }
    // A reference without an available destination remains exact source.
    // Nested label syntax and optional titles never define the URL boundary.
    if (!opening || !closing || target === null) {
      appendTextWithLanguage(raw, parent, options, cursor.from);
      return;
    }
    const span = document.createElement("span");
    span.className = "cm-live-link";
    span.dir = "auto";
    appendInlineMarkdown(source.slice(opening.to, closing.from), span, optionsAt(options, opening.to));
    identifyProjectedLink(span, target, cursor.from, cursor.to, opening.to, options);
    parent.append(span);
    return;
  }
  if (cursor.name === "WikiLink") {
    const link = /^(!?)\[\[([^\]|]+)(?:\|([^\]]+))?\]\]$/.exec(raw);
    if (!link) {
      appendLocatedText(raw, parent, options, cursor.from);
      return;
    }
    const span = document.createElement("span");
    const embed = link[1] === "!";
    span.className = embed
      ? "cm-live-embed"
      : "cm-live-wiki-link";
    span.dir = "auto";
    const target = link[2].trim();
    const alias = link[3]?.trim();
    const labelSource = alias ? link[3] : link[2];
    const labelFrom = (alias ? raw.indexOf("|") + 1 : embed ? 3 : 2)
      + labelSource.length - labelSource.trimStart().length;
    appendTextWithLanguage(alias || target, span, options, cursor.from + labelFrom);
    // A rendered Wikilink behaves as one projected object on first entry.
    // Its exact half-open source end is the stable insertion point after `]]`;
    // one subsequent backward move can then reveal and enter the syntax.
    identifyProjectedLink(span, target, cursor.from, cursor.to, cursor.to, options);
    parent.append(span);
    return;
  }
  if (cursor.name === "Escape") {
    appendTextWithLanguage(raw.startsWith("\\") ? raw.slice(1) : raw, parent, options,
      cursor.from + (raw.startsWith("\\") ? 1 : 0));
    return;
  }
  if (cursor.name === "Entity") {
    const entity = document.createElement("span");
    entity.innerHTML = raw;
    const text = entity.textContent ?? "";
    appendTextWithLanguage(text, parent, optionsWithMap(options,
      Array.from({length: text.length + 1}, (_, index) => index === text.length ? cursor.to : cursor.from)));
    return;
  }

  const wrapperName = cursor.name === "StrongEmphasis" ? "strong"
    : cursor.name === "Emphasis" ? "em"
      : cursor.name === "Strikethrough" ? "del"
        : cursor.name === "Highlight" ? "mark"
        : null;
  const destination = wrapperName ? document.createElement(wrapperName) : parent;
  let position = cursor.from;
  if (cursor.firstChild()) {
    do {
      if (cursor.from > position) {
        appendTextWithLanguage(source.slice(position, cursor.from), destination, options, position);
      }
      appendInlineMarkdownNode(cursor, source, destination, options);
      position = cursor.to;
    } while (cursor.nextSibling());
    cursor.parent();
    if (position < cursor.to) {
      appendTextWithLanguage(source.slice(position, cursor.to), destination, options, position);
    }
  } else if (!wrapperName) {
    appendTextWithLanguage(raw, destination, options, cursor.from);
  }
  if (wrapperName) parent.append(destination);
}

function appendInlineMarkdownPlain(
  source: string,
  parent: HTMLElement,
  options: MarkdownFragmentOptions,
) {
  const tree = scholiumMarkdownContentLanguage.language.parser.parse(source);
  const cursor = tree.cursor() as MarkdownTreeCursor;
  appendInlineMarkdownNode(cursor, source, parent, options);
}

function appendMath(
  expression: MathProjection,
  parent: HTMLElement | DocumentFragment,
  options: MarkdownFragmentOptions,
  source: string,
) {
  const document = documentFor(parent);
  const element = document.createElement(expression.kind === "display" ? "div" : "span");
  element.className = `scholium-math scholium-math-${expression.kind} scholium-math-fragment`;
  element.dir = "ltr";
  element.dataset.scholiumProtected = "math";
  element.dataset.scholiumSourceCaret = String(locatedOffset(options, expression.from));
  element.dataset.mathSource = btoa(Array.from(new TextEncoder().encode(expression.content),
    byte => String.fromCharCode(byte)).join(""));
  element.dataset.mathKind = expression.kind;
  const runtime = document.defaultView?.scholiumMath;
  const rendered = runtime?.version === 1
    ? runtime.render({source: expression.content, kind: expression.kind})
    : null;
  if (rendered?.ok) {
    element.classList.add("scholium-math-rendered");
    element.innerHTML = rendered.html;
  } else {
    // An unavailable runtime is pending, not a rendering failure. The shared
    // preview hydrator admits this exact source when the runtime arrives.
    if (rendered) {
      element.classList.add("scholium-math-error");
      element.setAttribute("aria-label", localized("Mathematics could not be rendered. Source is shown."));
    }
    const exact = document.createElement("code");
    exact.className = "scholium-math-source";
    exact.dir = "ltr";
    exact.textContent = source;
    element.append(exact);
  }
  parent.append(element);
}

function firstAnnotatedWikilink(source: string) {
  const expression = /\[\[([^\]\r\n]+)\]\]/g;
  for (const match of source.matchAll(expression)) {
    const from = match.index;
    let backslashes = 0;
    for (let cursor = from - 1; cursor >= 0 && source[cursor] === "\\"; cursor -= 1) backslashes += 1;
    if (backslashes % 2 === 1 || source[from - 1] === "!") continue;
    const linkTo = from + match[0].length;
    const annotation = linkAnnotationAfter(source, linkTo);
    if (annotation) return {from, linkTo, raw: match[0], annotation};
  }
  return null;
}

function appendAnnotatedWikilink(
  rawLink: string,
  annotationMarkdown: string,
  parent: HTMLElement,
  options: MarkdownFragmentOptions,
) {
  const parsed = /^\[\[([^\]|]+)(?:\|([^\]]+))?\]\]$/.exec(rawLink);
  if (!parsed) {
    parent.append(documentFor(parent).createTextNode(`${rawLink}{{${annotationMarkdown}}}`));
    return;
  }
  const document = documentFor(parent);
  const wrapper = document.createElement("span");
  wrapper.className = "scholium-annotated-link";
  wrapper.dataset.scholiumProtected = "link-annotation";
  const link = document.createElement("span");
  link.className = "cm-live-wiki-link";
  link.dir = "auto";
  const target = parsed[1].trim();
  const alias = parsed[2]?.trim();
  link.textContent = alias || target;
  identifyProjectedLink(link, target, 0, rawLink.length, rawLink.length, options);

  const marker = document.createElement("sup");
  marker.className = "scholium-link-annotation-marker";
  const button = document.createElement("button");
  button.type = "button";
  button.className = "scholium-link-annotation-button";
  button.dataset.linkAnnotation = "true";
  button.dataset.linkAnnotationTarget = alias || target;
  button.setAttribute("aria-expanded", "false");
  button.setAttribute("aria-label", localizedTemplate("Show Link Annotation for {title}", {title: alias || target}));
  button.append(systemSymbolElement("text-bubble", "scholium-link-annotation-icon", document));
  const template = document.createElement("template");
  template.className = "scholium-link-annotation-template";
  const content = document.createElement("span");
  content.className = "scholium-link-annotation-content";
  appendMarkdownBlocks(annotationMarkdown, content, optionsAt(options, rawLink.length + 2));
  template.content.append(content);
  button.addEventListener("mousedown", (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    event.stopPropagation();
  });
  marker.append(button, template);
  wrapper.append(link, marker);
  parent.append(wrapper);
}

export function appendInlineMarkdown(
  source: string,
  parent: HTMLElement,
  options: MarkdownFragmentOptions = {},
) {
  const annotated = firstAnnotatedWikilink(source);
  if (annotated) {
    if (annotated.from > 0) {
      appendInlineMarkdown(source.slice(0, annotated.from), parent, options);
    }
    appendAnnotatedWikilink(
      annotated.raw,
      annotated.annotation.markdown,
      parent,
      optionsAt(options, annotated.from),
    );
    if (annotated.annotation.to < source.length) {
      appendInlineMarkdown(
        source.slice(annotated.annotation.to),
        parent,
        optionsAt(options, annotated.annotation.to),
      );
    }
    return;
  }
  const expressions = options.mathematics
    ? scanMath(source, options.mathematics).filter((expression) => expression.kind === "inline")
    : [];
  if (expressions.length === 0) {
    appendInlineMarkdownPlain(source, parent, options);
    return;
  }
  let position = 0;
  for (const expression of expressions) {
    if (position < expression.from) {
      appendInlineMarkdownPlain(
        source.slice(position, expression.from),
        parent,
        optionsAt(options, position),
      );
    }
    appendMath(expression, parent, options, exactFragmentSource(source, expression.from, expression.to, options));
    position = expression.to;
  }
  if (position < source.length) {
    appendInlineMarkdownPlain(source.slice(position), parent, optionsAt(options, position));
  }
}

function appendBlockChildren(
  cursor: MarkdownTreeCursor,
  source: string,
  parent: HTMLElement | DocumentFragment,
  options: MarkdownFragmentOptions,
) {
  if (!cursor.firstChild()) return;
  do {
    appendMarkdownBlockNode(cursor, source, parent, options);
  } while (cursor.nextSibling());
  cursor.parent();
}

function tableCellDOM(
  cell: TablePresentationCell,
  header: boolean,
  document: Document,
  options: MarkdownFragmentOptions,
) {
  const element = document.createElement(header ? "th" : "td");
  element.dir = "auto";
  applyTextLanguage(element, cell.source);
  if (header) element.setAttribute("scope", "col");
  if (cell.alignment) element.classList.add(`scholium-table-align-${cell.alignment}`);
  element.dataset.sourceOffset = String(locatedOffset(options, cell.sourceOffset));
  // GFM removes an escaped pipe even inside code spans. Preserve a boundary
  // map while applying that display rule so subsequent text never shifts left.
  let source = "";
  const offsets: number[] = [];
  for (let position = 0; position < cell.source.length; position++) {
    if (cell.source[position] === "\\" && cell.source[position + 1] === "|") position++;
    offsets.push(cell.sourceOffset + position);
    source += cell.source[position];
  }
  offsets.push(cell.sourceOffset + cell.source.length);
  appendInlineMarkdown(source, element, optionsWithMap({
    ...options,
    sourceText: options.sourceText ?? ((from, to) => cell.source.slice(
      from - cell.sourceOffset, to - cell.sourceOffset)),
  }, offsets));
  return element;
}

export function createTableDOM(
  presentation: TablePresentation,
  document: Document,
  options: MarkdownFragmentOptions = {},
) {
  const scroller = document.createElement("div");
  scroller.className = "scholium-table-scroll";
  scroller.dataset.scholiumProtected = "table";
  const table = document.createElement("table");
  table.className = "scholium-table";
  table.setAttribute("aria-label", localized("Markdown table"));
  const head = document.createElement("thead");
  const headRow = document.createElement("tr");
  headRow.append(...presentation.header.map((cell) => tableCellDOM(cell, true, document, options)));
  head.append(headRow);
  const body = document.createElement("tbody");
  for (const row of presentation.body) {
    const rowElement = document.createElement("tr");
    rowElement.append(...row.map((cell) => tableCellDOM(cell, false, document, options)));
    body.append(rowElement);
  }
  table.append(head, body);
  scroller.append(table);
  return scroller;
}

function calloutParts(raw: string, options: MarkdownFragmentOptions) {
  if (!options.resolveCallout) return null;
  const lines: Array<{text: string; from: number}> = [];
  let lineFrom = 0;
  while (lineFrom <= raw.length) {
    const lineFeed = raw.indexOf("\n", lineFrom);
    const rawTo = lineFeed < 0 ? raw.length : lineFeed;
    const lineTo = rawTo > lineFrom && raw.charCodeAt(rawTo - 1) === 0x0d
      ? rawTo - 1
      : rawTo;
    lines.push({text: raw.slice(lineFrom, lineTo), from: lineFrom});
    if (lineFeed < 0) break;
    lineFrom = lineFeed + 1;
  }
  const match = /^\s*>\s*\[!([^\]]+)\]([+-])?\s*(.*)$/.exec(lines[0]?.text ?? "");
  if (!match) return null;
  const rawTitle = match[3];
  const title = rawTitle.trim();
  const titleInMatch = match[0].length - rawTitle.length
    + Math.max(0, rawTitle.indexOf(title));
  let body = "";
  const bodyOffsets: number[] = [];
  for (const [index, line] of lines.slice(1).entries()) {
    const content = /^(\s*> ?)(.*)$/.exec(line.text);
    const prefixLength = content?.[1].length ?? 0;
    const text = content?.[2] ?? line.text;
    if (index > 0) {
      body += "\n";
      bodyOffsets.push(line.from);
    }
    const contentFrom = line.from + prefixLength;
    if (bodyOffsets.length === 0) bodyOffsets.push(contentFrom);
    else bodyOffsets[bodyOffsets.length - 1] = contentFrom;
    body += text;
    for (let offset = 1; offset <= text.length; offset += 1) {
      bodyOffsets.push(contentFrom + offset);
    }
  }
  return {
    definition: options.resolveCallout(match[1]),
    rawKind: match[1],
    fold: match[2] === "+" ? "expanded" : match[2] === "-" ? "collapsed" : "fixed",
    title,
    titleFrom: titleInMatch,
    body,
    bodyOffsets,
  };
}

function appendCallout(
  parts: NonNullable<ReturnType<typeof calloutParts>>,
  parent: HTMLElement | DocumentFragment,
  options: MarkdownFragmentOptions,
) {
  const document = documentFor(parent);
  const callout = document.createElement(parts.fold === "fixed" ? "aside" : "details");
  callout.className = `scholium-callout scholium-callout-${parts.definition.identifier}`;
  callout.dataset.callout = parts.definition.identifier;
  callout.dataset.calloutSource = parts.rawKind;
  callout.dataset.calloutFold = parts.fold;
  callout.dataset.scholiumProtected = "callout";
  if (parts.fold === "expanded") (callout as HTMLDetailsElement).open = true;
  const headingContainer = document.createElement(parts.fold === "fixed" ? "header" : "summary");
  const heading = document.createElement("span");
  heading.className = "scholium-callout-heading";
  heading.setAttribute("role", "heading");
  heading.setAttribute("aria-level", "2");
  const role = document.createElement("span");
  role.className = "scholium-callout-role scholium-callout-role-context";
  role.dir = "auto";
  role.title = parts.definition.meaning;
  role.textContent = parts.definition.label;
  heading.append(role);
  if (parts.title) {
    const title = document.createElement("span");
    title.className = "scholium-callout-title";
    title.dir = "auto";
    appendInlineMarkdown(parts.title, title, optionsAt(options, parts.titleFrom));
    heading.append(title);
  } else {
    const title = document.createElement("span");
    title.className = "scholium-callout-title scholium-callout-default-title";
    title.dir = "auto";
    title.textContent = parts.definition.label;
    heading.append(title);
  }
  headingContainer.append(heading);
  if (parts.fold !== "fixed") {
    const marker = document.createElement("span");
    marker.className = "scholium-callout-fold-mark";
    marker.setAttribute("aria-hidden", "true");
    headingContainer.append(marker);
  }
  const body = document.createElement("div");
  body.className = "scholium-callout-body";
  const content = document.createElement("div");
  content.className = "scholium-callout-content";
  const destination = parts.definition.identifier === "quote"
    ? document.createElement("blockquote")
    : content;
  if (destination !== content) {
    destination.className = "scholium-callout-quotation";
    destination.dir = "auto";
    content.append(destination);
  }
  appendMarkdownBlocks(parts.body, destination, optionsWithMap(options, parts.bodyOffsets));
  body.append(content);
  callout.append(headingContainer, body);
  parent.append(callout);
}

function fencedCode(raw: string): {language: string; code: string} {
  const lines = raw.replaceAll("\r\n", "\n").split("\n");
  const opening = /^\s*(`{3,}|~{3,})\s*([^\s`]*)?.*$/.exec(lines[0] ?? "");
  const language = opening?.[2] ?? "";
  const fence = opening?.[1] ?? "```";
  const closing = new RegExp(`^\\s*${fence[0]}{${fence.length},}\\s*$`);
  if (lines.length > 1 && closing.test(lines.at(-1) ?? "")) lines.pop();
  lines.shift();
  return {language, code: lines.join("\n")};
}

function appendMarkdownBlockNode(
  cursor: MarkdownTreeCursor,
  source: string,
  parent: HTMLElement | DocumentFragment,
  options: MarkdownFragmentOptions,
) {
  const document = documentFor(parent);
  const raw = source.slice(cursor.from, cursor.to);
  switch (cursor.name) {
  case "Paragraph": {
    const paragraph = document.createElement("p");
    paragraph.dir = "auto";
    applyTextLanguage(paragraph, raw);
    appendInlineMarkdown(raw, paragraph, optionsAt(options, cursor.from));
    parent.append(paragraph);
    return;
  }
  case "BulletList": {
    const list = document.createElement("ul");
    appendBlockChildren(cursor, source, list, options);
    parent.append(list);
    return;
  }
  case "OrderedList": {
    const list = document.createElement("ol");
    const start = /^\s*(\d+)[.)]\s/.exec(raw)?.[1];
    if (start && start !== "1") list.setAttribute("start", start);
    appendBlockChildren(cursor, source, list, options);
    parent.append(list);
    return;
  }
  case "ListItem": {
    const item = document.createElement("li");
    item.dir = "auto";
    applyTextLanguage(item, raw);
    appendBlockChildren(cursor, source, item, options);
    parent.append(item);
    return;
  }
  case "Callout":
  case "Blockquote": {
    const calloutOptions = optionsAt(options, cursor.from);
    const callout = calloutParts(raw, calloutOptions);
    if (callout) {
      appendCallout(callout, parent, calloutOptions);
      return;
    }
    const quote = document.createElement("blockquote");
    quote.dir = "auto";
    applyTextLanguage(quote, raw);
    appendBlockChildren(cursor, source, quote, options);
    parent.append(quote);
    return;
  }
  case "FencedCode": {
    const projection = fencedCode(raw);
    const pre = document.createElement("pre");
    pre.dir = "ltr";
    const code = document.createElement("code");
    code.dir = "ltr";
    if (projection.language) code.className = `language-${projection.language}`;
    code.textContent = projection.code;
    pre.append(code);
    parent.append(pre);
    return;
  }
  case "CodeBlock": {
    const pre = document.createElement("pre");
    pre.dir = "ltr";
    const code = document.createElement("code");
    code.dir = "ltr";
    for (const child of directChildren(cursor)) {
      if (child.name === "CodeText") appendLocatedText(source.slice(child.from, child.to), code, options, child.from);
    }
    pre.append(code);
    parent.append(pre);
    return;
  }
  case "Task": {
    const marker = directChildren(cursor).find(child => child.name === "TaskMarker");
    if (!marker) return;
    const checked = /^\[[xX]\]$/.test(source.slice(marker.from, marker.to));
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.className = "scholium-task-checkbox";
    checkbox.disabled = true;
    checkbox.checked = checked;
    // Preview content is serialized into a native WebView. The live checked
    // property alone does not survive that HTML boundary.
    if (checked) checkbox.setAttribute("checked", "");
    checkbox.setAttribute("aria-label", localized(checked ? "Completed task" : "Incomplete task"));
    if (parent.nodeType === 1) (parent as HTMLElement).classList.add("scholium-task-list-item");
    parent.append(checkbox);
    const paragraph = document.createElement("p");
    let from = marker.to;
    while (from < cursor.to && /[ \t]/.test(source[from])) from++;
    appendInlineMarkdown(source.slice(from, cursor.to), paragraph, optionsAt(options, from));
    parent.append(paragraph);
    return;
  }
  case "BlockMath": {
    const expression = parsedMath(cursor, source, "display");
    if (expression) appendMath(expression, parent, options,
      exactFragmentSource(source, cursor.from, cursor.to, options));
    return;
  }
  case "HTMLBlock":
  case "CommentBlock": {
    const pre = document.createElement("pre");
    pre.className = "raw-html";
    pre.dir = "ltr";
    const code = document.createElement("code");
    code.dir = "ltr";
    code.textContent = raw;
    pre.append(code);
    parent.append(pre);
    return;
  }
  case "Table": {
    const presentation = tablePresentation(raw, 0, raw.length);
    if (presentation) parent.append(createTableDOM(presentation, document, optionsAt(options, cursor.from)));
    else {
      // The editing table model deliberately admits fewer shapes than the
      // Markdown parser. A rejected shape remains complete authored source.
      const pre = document.createElement("pre");
      const code = document.createElement("code");
      appendLocatedText(raw, code, options, cursor.from);
      pre.append(code);
      parent.append(pre);
    }
    return;
  }
  case "ATXHeading1":
  case "ATXHeading2":
  case "ATXHeading3":
  case "ATXHeading4":
  case "ATXHeading5":
  case "ATXHeading6": {
    const level = Number(cursor.name.at(-1));
    const heading = document.createElement(`h${level}`);
    heading.dir = "auto";
    applyTextLanguage(heading, raw);
    const opening = /^\s*#{1,6}\s+/.exec(raw)?.[0].length ?? 0;
    const trailing = /\s+#+\s*$/.exec(raw.slice(opening));
    const contentTo = trailing ? opening + trailing.index : raw.length;
    appendInlineMarkdown(
      raw.slice(opening, contentTo),
      heading,
      optionsAt(options, cursor.from + opening),
    );
    parent.append(heading);
    return;
  }
  case "SetextHeading1":
  case "SetextHeading2": {
    const marker = directChildren(cursor).find(child => child.name === "HeaderMark");
    if (!marker) return;
    const content = source.slice(cursor.from, marker.from).replace(/[\r\n]+$/, "");
    const heading = document.createElement(`h${cursor.name.at(-1)}`);
    heading.dir = "auto";
    applyTextLanguage(heading, content);
    appendInlineMarkdown(content, heading, optionsAt(options, cursor.from));
    parent.append(heading);
    return;
  }
  case "HorizontalRule":
    parent.append(document.createElement("hr"));
    return;
  case "ListMark":
  case "QuoteMark":
  case "HeaderMark":
  case "CodeMark":
  case "CodeInfo":
  case "CodeText":
    return;
  default:
    appendBlockChildren(cursor, source, parent, options);
  }
}

/** Render a safe, non-authoritative Markdown fragment for a Live widget. */
export function appendMarkdownBlocks(
  source: string,
  parent: HTMLElement,
  options: MarkdownFragmentOptions = {},
) {
  const displays = options.mathematics
    ? scanMath(source, options.mathematics).filter((expression) => expression.kind === "display")
    : [];
  if (displays.length > 0) {
    let position = 0;
    for (const expression of displays) {
      if (position < expression.from) {
        appendMarkdownBlocks(
          source.slice(position, expression.from),
          parent,
          optionsAt(options, position),
        );
      }
      appendMath(expression, parent, options, exactFragmentSource(source, expression.from, expression.to, options));
      position = expression.to;
    }
    if (position < source.length) {
      appendMarkdownBlocks(source.slice(position), parent, optionsAt(options, position));
    }
    return;
  }
  const tree = scholiumMarkdownContentLanguage.language.parser.parse(source);
  const cursor = tree.cursor() as MarkdownTreeCursor;
  appendBlockChildren(cursor, source, parent, options);
}
