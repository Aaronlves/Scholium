import {inlineCodeMarkers} from "./transformations";

export interface ClipboardPayload { plainText: string; html?: string }
const maximumClipboardLength = 2_000_000;

function escapeHTML(value: string) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

export function sanitizeClipboardHTML(html: string) {
  if (html.length > maximumClipboardLength) throw new RangeError("Clipboard HTML exceeds its size limit.");
  let safe = html;
  safe = safe.replace(/<!--([\s\S]*?)-->/g, "");
  safe = safe.replace(/<(script|style|iframe|object|embed|svg|math|canvas|template)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, "");
  safe = safe.replace(/<(script|style|iframe|object|embed|svg|math|canvas|template)\b[^>]*\/?\s*>/gi, "");
  safe = safe.replace(/<img\b([^>]*)>/gi, (_match, attributes: string) => {
    const alt = /\balt\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(attributes);
    if (!alt) return "";
    // Decode once in attribute context, where ambiguous named references
    // differ from text context. Only this inert span reaches the parser;
    // resource-bearing image markup never does.
    const raw = (alt[1] ?? alt[2] ?? alt[3] ?? "")
      .replaceAll('"', "&quot;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
    const parsed = new DOMParser().parseFromString(`<span data-alt="${raw}"></span>`, "text/html");
    return escapeHTML(parsed.querySelector("span")?.getAttribute("data-alt") ?? "");
  });
  safe = safe.replace(/<(?:video|audio|source|track|picture|link|meta)\b[^>]*\/?\s*>/gi, "");
  safe = safe.replace(/\s(?:src|srcset|poster|background|style|formaction)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, "");
  safe = safe.replace(/\son[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, "");
  return safe;
}

function escapeMarkdownText(value: string) {
  return value.replace(/([\\`*_[\]<>~])/g, "\\$1");
}

function safeLinkDestination(value: string) {
  const trimmed = value.trim();
  if (/^(https?:|mailto:)/i.test(trimmed)) return trimmed.replace(/[()\s]/g, (character) => encodeURIComponent(character));
  return "";
}

function collapseBlankLines(value: string) {
  const lines: string[] = [];
  let fence: string | null = null;
  for (const line of value.split("\n")) {
    // Only the converter emits unescaped fences; its enclosing list/quote
    // prefixes contain these characters. Keep recognition linear in line size.
    const marker = /^[ \t>*+\-.\d]*(`{3,})[ \t]*$/.exec(line)?.[1];
    if (fence !== null) {
      lines.push(line);
      if (marker === fence) fence = null;
    } else if (marker) {
      fence = marker;
      lines.push(line);
    } else {
      const trimmed = line.replace(/[ \t]+$/, "");
      if (trimmed || lines.at(-1) !== "") lines.push(trimmed);
    }
  }
  return lines.join("\n").trim();
}

function renderChildren(node: Node): string {
  return Array.from(node.childNodes).map(renderNode).join("");
}

function literalCodeText(node: Node): string {
  if (node.nodeType === 3) return node.nodeValue ?? "";
  if (node.nodeType === 1 && (node as Element).tagName.toLowerCase() === "br") return "\n";
  return Array.from(node.childNodes).map(literalCodeText).join("");
}

function renderList(node: Element, ordered: boolean) {
  let index = 1;
  return "\n" + Array.from(node.children).flatMap((child) => {
    if (child.tagName.toLowerCase() !== "li") return [];
    const prefix = ordered ? `${index++}. ` : "- ";
    const content = collapseBlankLines(renderChildren(child)).replaceAll("\n", `\n${" ".repeat(prefix.length)}`);
    return [`${prefix}${content}\n`];
  }).join("") + "\n";
}

function renderTable(node: Element) {
  const cells = Array.from(node.querySelectorAll("tr"))
    .filter(row => row.closest("table") === node)
    .map(row => Array.from(row.children).filter(cell => ["td", "th"].includes(cell.tagName.toLowerCase())));
  const rows = cells.map(row => row.map(cell =>
    collapseBlankLines(renderChildren(cell)).replaceAll("|", "\\|").replaceAll("\n", " ")));
  if (rows.length === 0 || rows[0].length < 2 || rows.some(row => row.length !== rows[0].length)
      || cells.some(row => row.some(cell => cell.hasAttribute("rowspan") || cell.hasAttribute("colspan")))) {
    return `${rows.map(row => row.join("\t")).join("\n")}\n\n`;
  }
  const line = (row: string[]) => `| ${row.join(" | ")} |`;
  return `${line(rows[0])}\n${line(rows[0].map(() => "---"))}\n${rows.slice(1).map(line).join("\n")}\n\n`;
}

function renderNode(node: Node): string {
  if (node.nodeType === 3) return escapeMarkdownText(node.nodeValue ?? "");
  if (node.nodeType !== 1) return "";
  const element = node as Element;
  const tag = element.tagName.toLowerCase();
  const content = () => renderChildren(element);
  if (/^h[1-6]$/.test(tag)) return `${"#".repeat(Number(tag[1]))} ${collapseBlankLines(content())}\n\n`;
  if (["p", "div", "section", "article", "header", "footer"].includes(tag)) return `${collapseBlankLines(content())}\n\n`;
  if (["strong", "b"].includes(tag)) return `**${content()}**`;
  if (["em", "i"].includes(tag)) return `*${content()}*`;
  if (["del", "s", "strike"].includes(tag)) return `~~${content()}~~`;
  if (tag === "code" && element.parentElement?.tagName.toLowerCase() !== "pre") {
    const text = literalCodeText(element).replace(/\r\n?|\n/g, " ");
    if (!text) return "";
    const {opening, closing} = inlineCodeMarkers(text);
    return opening + text + closing;
  }
  if (tag === "pre") {
    const raw = literalCodeText(element);
    const run = Math.max(3, ...Array.from(raw.matchAll(/`+/g), (match) => match[0].length + 1));
    const fence = "`".repeat(run);
    return `${fence}\n${raw}${raw.endsWith("\n") ? "" : "\n"}${fence}\n\n`;
  }
  if (tag === "blockquote") return `${collapseBlankLines(content()).split("\n").map((line) => `> ${line}`).join("\n")}\n\n`;
  if (tag === "ul") return renderList(element, false);
  if (tag === "ol") return renderList(element, true);
  if (tag === "a") {
    const label = content();
    const destination = safeLinkDestination(element.getAttribute("href") ?? "");
    return destination ? `[${label}](${destination})` : label;
  }
  if (tag === "br") return "\n";
  if (tag === "table") return renderTable(element);
  return content();
}

export function convertClipboardHTML(html: string) {
  const inertSource = sanitizeClipboardHTML(html);
  const document = new DOMParser().parseFromString(`<html><body>${inertSource}</body></html>`, "text/html");
  return collapseBlankLines(renderChildren(document.body));
}

export function pasteAsMarkdown(payload: ClipboardPayload) {
  if (payload.html?.trim()) {
    try {
      const converted = convertClipboardHTML(payload.html);
      if (converted) return converted;
    } catch { /* readable plain-text fallback below */ }
  }
  return payload.plainText;
}

export function decodeClipboardPayload(argument: string | undefined): ClipboardPayload | undefined {
  if (!argument) return undefined;
  try {
    const value = JSON.parse(argument) as Partial<ClipboardPayload>;
    if (typeof value.plainText === "string" && value.plainText.length <= maximumClipboardLength
        && (value.html === undefined || typeof value.html === "string")) {
      return {plainText: value.plainText,
        html: value.html && value.html.length <= maximumClipboardLength ? value.html : undefined};
    }
  } catch { /* malformed clipboard payload */ }
  return undefined;
}

export function isSingleSafeURL(value: string) {
  const trimmed = value.trim();
  return /^(https?:\/\/|mailto:)[^\s]+$/i.test(trimmed) ? trimmed : null;
}
