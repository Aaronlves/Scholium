import type {EditorContext, EditorMode} from "./protocol";

export const unsupportedFilePasteMessage = "File and image paste is not supported in Editor 1.0.";

export function editorAccessibilityAttributes(mode: EditorMode) {
  return {
    "aria-label": mode === "livePreview" ? "Markdown live preview editor" : "Markdown source editor",
    role: "textbox",
    "aria-multiline": "true",
    spellcheck: "true",
    autocapitalize: "sentences",
  } as const;
}

export function activeConstructAccessibilityDescription(context: EditorContext): string | undefined {
  const heading = context.activeBlockConstructs.find((construct) => /^ATXHeading[1-6]$/.test(construct));
  if (heading) return `Heading level ${heading.at(-1)}`;
  if (context.activeInlineConstructs.includes("Link")) return "Link";
  if (context.activeBlockConstructs.includes("Callout")) return "Callout";
  if (context.activeBlockConstructs.includes("Blockquote")) return "Quotation";
  if (context.activeBlockConstructs.includes("Table")) return "Table";
  if (context.activeBlockConstructs.includes("BulletList")) return "Bulleted list";
  if (context.activeBlockConstructs.includes("OrderedList")) return "Numbered list";
  if (context.activeInlineConstructs.includes("StrongEmphasis")) return "Bold text";
  if (context.activeInlineConstructs.includes("Emphasis")) return "Emphasized text";
  if (context.activeInlineConstructs.includes("InlineCode")) return "Inline code";
  return undefined;
}

export function updateEditorAccessibility(
  content: HTMLElement,
  mode: EditorMode,
  context?: EditorContext,
) {
  const attributes = editorAccessibilityAttributes(mode);
  for (const [name, value] of Object.entries(attributes)) {
    if (content.getAttribute(name) !== value) content.setAttribute(name, value);
  }
  const description = mode === "livePreview" && context
    ? activeConstructAccessibilityDescription(context)
    : mode === "source"
      ? "Exact Markdown and YAML source"
      : undefined;
  if (description) {
    if (content.getAttribute("aria-description") !== description) {
      content.setAttribute("aria-description", description);
    }
  } else if (content.hasAttribute("aria-description")) {
    content.removeAttribute("aria-description");
  }
}

export function announceEditorMessage(content: HTMLElement, message: string) {
  const previous = content.getAttribute("aria-description");
  content.setAttribute("aria-description", message);
  window.setTimeout(() => {
    if (content.getAttribute("aria-description") !== message) return;
    if (previous) content.setAttribute("aria-description", previous);
    else content.removeAttribute("aria-description");
  }, 4_000);
}
