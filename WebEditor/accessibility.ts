import type {EditorMode} from "./protocol";

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

export function announceEditorMessage(content: HTMLElement, message: string) {
  content.setAttribute("aria-description", message);
  window.setTimeout(() => {
    if (content.getAttribute("aria-description") === message) content.removeAttribute("aria-description");
  }, 4_000);
}
