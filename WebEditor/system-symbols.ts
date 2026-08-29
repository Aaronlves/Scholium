export const webSystemSymbolKeys = [
  "textformat",
  "bold",
  "italic",
  "strikethrough",
  "highlighter",
  "link",
  "ellipsis",
  "chevron-down",
  "checkmark",
  "curlybraces",
  "curlybraces-square",
  "eye-slash",
  "list-bullet",
  "list-number",
  "checklist",
  "text-quote",
  "text-bubble",
  "plus",
  "plus-circle",
  "minus-circle",
  "xmark-circle",
  "doc-text",
  "calendar",
  "function",
  "flowchart",
  "tablecells",
  "textformat-superscript",
  "minus",
  "xmark",
] as const;

export type WebSystemSymbolKey = typeof webSystemSymbolKeys[number];

/**
 * Creates a DOM mask backed by the native SF Symbol CSS variables injected by
 * Swift. Callers retain their own size, semantics, and interaction ownership.
 */
export function systemSymbolElement(
  key: WebSystemSymbolKey,
  className = "",
  ownerDocument: Document = document,
) {
  const symbol = ownerDocument.createElement("span");
  symbol.className = `scholium-system-symbol ${className}`.trim();
  symbol.dataset.scholiumSystemSymbol = key;
  symbol.style.setProperty(
    "--scholium-system-symbol-image",
    `var(--scholium-system-symbol-${key})`,
  );
  symbol.setAttribute("aria-hidden", "true");
  return symbol;
}
