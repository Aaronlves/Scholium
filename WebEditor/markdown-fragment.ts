import {markdownLanguage} from "@codemirror/lang-markdown";
import {scanMath, type MathDialect, type MathProjection} from "./math";
import {
  tablePresentation,
  type TablePresentation,
  type TablePresentationCell,
} from "./table-presentation";

export interface MarkdownFragmentCallout {
  identifier: string;
  label: string;
  meaning: string;
}

export interface MarkdownFragmentOptions {
  mathematics?: MathDialect;
  resolveCallout?: (rawKind: string) => MarkdownFragmentCallout;
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

function appendInlineMarkdownNode(
  cursor: MarkdownTreeCursor,
  source: string,
  parent: HTMLElement | DocumentFragment,
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
    const link = /^\[([\s\S]*?)\]\([\s\S]*\)$/.exec(raw);
    const span = document.createElement("span");
    span.className = "cm-live-link";
    span.dir = "auto";
    span.textContent = link?.[1] ?? raw;
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
      appendInlineMarkdownNode(cursor, source, destination);
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

function appendInlineMarkdownPlain(source: string, parent: HTMLElement) {
  const tree = markdownLanguage.parser.parse(source);
  const cursor = tree.cursor() as MarkdownTreeCursor;
  appendInlineMarkdownNode(cursor, source, parent);
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

export function appendInlineMarkdown(
  source: string,
  parent: HTMLElement,
  options: MarkdownFragmentOptions = {},
) {
  const expressions = options.mathematics
    ? scanMath(source, options.mathematics).filter((expression) => expression.kind === "inline")
    : [];
  if (expressions.length === 0) {
    appendInlineMarkdownPlain(source, parent);
    return;
  }
  let position = 0;
  for (const expression of expressions) {
    if (position < expression.from) {
      appendInlineMarkdownPlain(source.slice(position, expression.from), parent);
    }
    appendMath({...expression, from: 0, to: expression.to - expression.from}, parent);
    position = expression.to;
  }
  if (position < source.length) appendInlineMarkdownPlain(source.slice(position), parent);
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
  element.dataset.sourceOffset = String(cell.sourceOffset);
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
  table.setAttribute("aria-label", "Markdown table");
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
  const lines = raw.replaceAll("\r\n", "\n").split("\n");
  const match = /^\s*>\s*\[!([^\]]+)\]([+-])?\s*(.*)$/.exec(lines[0] ?? "");
  if (!match) return null;
  return {
    definition: options.resolveCallout(match[1]),
    rawKind: match[1],
    fold: match[2] === "+" ? "expanded" : match[2] === "-" ? "collapsed" : "fixed",
    title: match[3].trim(),
    body: lines.slice(1).map((line) => line.replace(/^\s*> ?/, "")).join("\n").trim(),
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
  role.className = "scholium-callout-role";
  role.dir = "auto";
  role.title = parts.definition.meaning;
  role.textContent = parts.definition.label;
  heading.append(role);
  if (parts.title) {
    const title = document.createElement("span");
    title.className = "scholium-callout-title";
    title.dir = "auto";
    appendInlineMarkdown(parts.title, title, options);
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
  appendMarkdownBlocks(parts.body, destination, options);
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
  case "Blockquote": {
    const callout = calloutParts(raw, options);
    if (callout) {
      appendCallout(callout, parent, options);
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
    appendInlineMarkdown(
      raw.replace(/^\s*#{1,6}\s+/, "").replace(/\s+#+\s*$/, ""),
      heading,
      options,
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
        appendMarkdownBlocks(source.slice(position, expression.from), parent, options);
      }
      appendMath(expression, parent);
      position = expression.to;
    }
    if (position < source.length) appendMarkdownBlocks(source.slice(position), parent, options);
    return;
  }
  const tree = markdownLanguage.parser.parse(source);
  const cursor = tree.cursor() as MarkdownTreeCursor;
  appendBlockChildren(cursor, source, parent, options);
}
