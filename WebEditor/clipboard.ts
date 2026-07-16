export interface ClipboardPayload { plainText: string; html?: string }

function escapeHTML(value: string) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

export function sanitizeClipboardHTML(html: string) {
  let safe = html.slice(0, 2_000_000);
  safe = safe.replace(/<!--([\s\S]*?)-->/g, "");
  safe = safe.replace(/<(script|style|iframe|object|embed|svg|math|canvas|template)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, "");
  safe = safe.replace(/<(script|style|iframe|object|embed|svg|math|canvas|template)\b[^>]*\/?\s*>/gi, "");
  safe = safe.replace(/<img\b([^>]*)>/gi, (_match, attributes: string) => {
    const alt = /\balt\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(attributes);
    return alt ? escapeHTML(alt[1] ?? alt[2] ?? alt[3] ?? "") : "";
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
  return value.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

function renderChildren(node: Node): string {
  return Array.from(node.childNodes).map(renderNode).join("");
}

function renderList(node: Element, ordered: boolean) {
  let index = 1;
  return Array.from(node.children).flatMap((child) => {
    if (child.tagName.toLowerCase() !== "li") return [];
    const prefix = ordered ? `${index++}. ` : "- ";
    const content = collapseBlankLines(renderChildren(child)).replaceAll("\n", "\n  ");
    return [`${prefix}${content}\n`];
  }).join("") + "\n";
}

function renderTable(node: Element) {
  const rows = Array.from(node.querySelectorAll("tr")).map((row) => Array.from(row.children).flatMap((cell) => {
    if (!["td", "th"].includes(cell.tagName.toLowerCase())
        || cell.hasAttribute("rowspan") || cell.hasAttribute("colspan")) return [];
    return [collapseBlankLines(renderChildren(cell)).replaceAll("|", "\\|").replaceAll("\n", " ")];
  }));
  if (rows.length === 0 || rows[0].length < 2 || rows.some((row) => row.length !== rows[0].length)) {
    return `${collapseBlankLines(renderChildren(node))}\n\n`;
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
  if (tag === "code" && element.parentElement?.tagName.toLowerCase() !== "pre") return `\`${content().replaceAll("`", "\\`")}\``;
  if (tag === "pre") {
    const raw = element.textContent ?? "";
    const run = Math.max(3, ...Array.from(raw.matchAll(/`+/g), (match) => match[0].length + 1));
    const fence = "`".repeat(run);
    return `${fence}\n${raw}\n${fence}\n\n`;
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

export function decodeClipboardPayload(argument: string | undefined): ClipboardPayload {
  if (!argument) return {plainText: ""};
  try {
    const value = JSON.parse(argument) as Partial<ClipboardPayload>;
    if (typeof value.plainText === "string" && (value.html === undefined || typeof value.html === "string")) {
      return {plainText: value.plainText.slice(0, 2_000_000), html: value.html?.slice(0, 2_000_000)};
    }
  } catch { /* legacy plain argument */ }
  return {plainText: argument.slice(0, 2_000_000)};
}

export function isSingleSafeURL(value: string) {
  const trimmed = value.trim();
  return /^(https?:\/\/|mailto:)[^\s]+$/i.test(trimmed) ? trimmed : null;
}
