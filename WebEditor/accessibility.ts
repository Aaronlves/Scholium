import type {EditorContext, EditorMode} from "./protocol";
import {localized, localizedTemplate} from "./localization";

export function unsupportedFilePasteMessage() {
  return localized("File and image paste is not supported in Editor 1.0.");
}

export function editorAccessibilityAttributes(mode: EditorMode) {
  return {
    "aria-label": mode === "livePreview"
      ? localized("Markdown editor, Edit mode")
      : localized("Markdown source editor"),
    role: "textbox",
    "aria-multiline": "true",
    spellcheck: "true",
    autocapitalize: "sentences",
  } as const;
}

export function activeConstructAccessibilityDescription(context: EditorContext): string | undefined {
  const heading = context.activeBlockConstructs.find((construct) => /^ATXHeading[1-6]$/.test(construct));
  if (heading) return localizedTemplate("Heading level {level}", {level: heading.at(-1) ?? ""});
  if (context.activeInlineConstructs.includes("Link")) return localized("Link");
  if (context.activeBlockConstructs.includes("Callout")) return localized("Callout");
  if (context.activeBlockConstructs.includes("Blockquote")) return localized("Quotation");
  if (context.activeBlockConstructs.includes("Table")) return localized("Table");
  if (context.activeBlockConstructs.includes("BulletList")) return localized("Bulleted list");
  if (context.activeBlockConstructs.includes("OrderedList")) return localized("Numbered list");
  if (context.activeInlineConstructs.includes("StrongEmphasis")) return localized("Bold text");
  if (context.activeInlineConstructs.includes("Emphasis")) return localized("Emphasized text");
  if (context.activeInlineConstructs.includes("InlineCode")) return localized("Inline code");
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
      ? localized("Exact Markdown and YAML source")
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
