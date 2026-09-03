import {scanMath, type MathDialect, type MathProjection} from "./math";
import {scholiumMarkdownContentLanguage} from "./language";
import {
  tablePresentation,
  type TablePresentation,
  type TablePresentationCell,
} from "./table-presentation";
import {systemSymbolElement} from "./system-symbols";
import {localized} from "./localization";
import {linkAnnotationAfter} from "./link-annotation";

export interface MarkdownFragmentCallout {
  identifier: string;
  label: string;
  meaning: string;
}

export interface MarkdownFragmentOptions {
  mathematics?: MathDialect;
  resolveCallout?: (rawKind: string) => MarkdownFragmentCallout;
  sourceOffset?: (fragmentOffset: number) => number;
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
  "EmphasisMark", "CodeMark", "LinkMark", "URL", "StrikethroughMark",
]);

function documentFor(parent: Node): Document {
  if (parent.nodeType === 9) return parent as Document;
  const owner = parent.ownerDocument;
  if (!owner) throw new Error("Markdown fragments require an owning document.");
  return owner;
}

function locatedOffset(options: MarkdownFragmentOptions, offset: number) {
  return options.sourceOffset?.(offset) ?? offset;
}

function optionsAt(options: MarkdownFragmentOptions, offset: number): MarkdownFragmentOptions {
  return {
    ...options,
    sourceOffset: (nestedOffset) => locatedOffset(options, offset + nestedOffset),
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
  };
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
  if (cursor.name === "InlineCode") {
    const code = document.createElement("code");
    code.dir = "ltr";
    const opening = raw.match(/^`+/)?.[0] ?? "";
    const closing = raw.endsWith(opening) ? opening.length : 0;
    code.textContent = raw.slice(opening.length, raw.length - closing);
    parent.append(code);
    return;
  }
  if (cursor.name === "Link") {
    const link = /^\[([\s\S]*?)\]\(([\s\S]*?)\)$/.exec(raw);
    const span = document.createElement("span");
    span.className = "cm-live-link";
    span.dir = "auto";
    span.textContent = link?.[1] ?? raw;
    if (link) {
      identifyProjectedLink(
        span,
        link[2].trim().replace(/^<|>$/g, ""),
        cursor.from,
        cursor.to,
        cursor.from + 1,
        options,
      );
    }
    parent.append(span);
    return;
  }
  if (cursor.name === "WikiLink") {
    const link = /^(!?)\[\[([^\]|]+)(?:\|([^\]]+))?\]\]$/.exec(raw);
    if (!link) {
      parent.append(document.createTextNode(raw));
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
    span.append(document.createTextNode(alias || target));
    // A rendered Wikilink behaves as one projected object on first entry.
    // Its exact half-open source end is the stable insertion point after `]]`;
    // one subsequent backward move can then reveal and enter the syntax.
    identifyProjectedLink(span, target, cursor.from, cursor.to, cursor.to, options);
    parent.append(span);
    return;
  }
  if (cursor.name === "Escape") {
    parent.append(document.createTextNode(raw.startsWith("\\") ? raw.slice(1) : raw));
    return;
  }

  const wrapperName = cursor.name === "StrongEmphasis" ? "strong"
    : cursor.name === "Emphasis" ? "em"
      : cursor.name === "Strikethrough" ? "del"
        : null;
  const destination = wrapperName ? document.createElement(wrapperName) : parent;
  let position = cursor.from;
  if (cursor.firstChild()) {
    do {
      if (cursor.from > position) {
        destination.append(document.createTextNode(source.slice(position, cursor.from)));
      }
      appendInlineMarkdownNode(cursor, source, destination, options);
      position = cursor.to;
    } while (cursor.nextSibling());
    cursor.parent();
    if (position < cursor.to) {
      destination.append(document.createTextNode(source.slice(position, cursor.to)));
    }
  } else if (!wrapperName) {
    destination.append(document.createTextNode(raw));
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
) {
  const document = documentFor(parent);
  const element = document.createElement(expression.kind === "display" ? "div" : "span");
  element.className = `scholium-math scholium-math-${expression.kind} scholium-math-fragment`;
  element.dir = "ltr";
  element.dataset.scholiumProtected = "math";
  const runtime = document.defaultView?.scholiumMath;
  const rendered = runtime?.version === 1
    ? runtime.render({source: expression.content, kind: expression.kind})
    : null;
  if (rendered?.ok) {
    element.classList.add("scholium-math-rendered");
    element.innerHTML = rendered.html;
  } else {
    element.classList.add("scholium-math-error");
    const exact = document.createElement("code");
    exact.className = "scholium-math-source";
    exact.dir = "ltr";
    const delimiter = "$".repeat(expression.delimiterLength);
    exact.textContent = expression.kind === "display"
      ? `${delimiter}\n${expression.content}\n${delimiter}`
      : `${delimiter}${expression.content}${delimiter}`;
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
  button.setAttribute("aria-controls", "scholium-preview-popover");
  button.setAttribute("aria-label", `${localized("Show Link Annotation")} ${alias || target}`);
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
    appendMath({...expression, from: 0, to: expression.to - expression.from}, parent);
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
  if (header) element.setAttribute("scope", "col");
  if (cell.alignment) element.classList.add(`scholium-table-align-${cell.alignment}`);
  element.dataset.sourceOffset = String(locatedOffset(options, cell.sourceOffset));
  appendInlineMarkdown(cell.source, element, options);
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
  const orientationTitleBecomesBody = parts.definition.identifier === "orient"
    && parts.title.length > 0
    && parts.body.trim().length === 0;
  const role = document.createElement("span");
  role.className = "scholium-callout-role";
  role.dir = "auto";
  role.title = parts.definition.meaning;
  role.textContent = parts.definition.label;
  heading.append(role);
  if (parts.title && !orientationTitleBecomesBody) {
    const title = document.createElement("span");
    title.className = "scholium-callout-title";
    title.dir = "auto";
    appendInlineMarkdown(parts.title, title, optionsAt(options, parts.titleFrom));
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
  const signature = document.createElement("span");
  signature.className = "scholium-callout-signature";
  signature.setAttribute("aria-hidden", "true");
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
  if (orientationTitleBecomesBody) {
    const paragraph = document.createElement("p");
    paragraph.className = "scholium-callout-orient-title-body";
    paragraph.dir = "auto";
    appendInlineMarkdown(parts.title, paragraph, optionsAt(options, parts.titleFrom));
    destination.append(paragraph);
  } else {
    appendMarkdownBlocks(parts.body, destination, optionsWithMap(options, parts.bodyOffsets));
  }
  body.append(signature, content);
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
    appendInlineMarkdown(raw, paragraph, options);
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
  case "HTMLBlock": {
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
    if (presentation) parent.append(createTableDOM(presentation, document, options));
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
      appendMath(expression, parent);
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
