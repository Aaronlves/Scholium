import {localized} from "./localization";

export function sanitizePreviewDocument(body: HTMLElement) {
  // Native preview HTML cannot carry the original diagram's isolated shadow
  // tree. The detached clone must expose its existing exact-source fallback.
  body.querySelectorAll<HTMLElement>(".scholium-mermaid-rendered").forEach(wrapper => {
    if (!wrapper.querySelector(":scope > .scholium-mermaid-source")) return;
    wrapper.classList.remove("scholium-mermaid-rendered");
    wrapper.querySelectorAll(":scope > .scholium-mermaid-output, :scope > .scholium-mermaid-accessible-source")
      .forEach(node => node.remove());
  });
  body.querySelectorAll("script, style, iframe, object, embed, form, button")
    .forEach((node) => node.remove());
  body.querySelectorAll("input").forEach(node => {
    if (!node.matches('input.scholium-task-checkbox[type="checkbox"][disabled]')) node.remove();
  });
  body.querySelectorAll<HTMLElement>("*").forEach((node) => {
    for (const attribute of Array.from(node.attributes)) {
      if (attribute.name.toLowerCase().startsWith("on")) node.removeAttribute(attribute.name);
      if (attribute.name.toLowerCase().startsWith("data-source-")) {
        node.removeAttribute(attribute.name);
      }
    }
    node.removeAttribute("href");
    node.removeAttribute("contenteditable");
    node.removeAttribute("id");
    node.removeAttribute("for");
    node.removeAttribute("aria-describedby");
    node.removeAttribute("aria-labelledby");
    node.removeAttribute("aria-owns");
    node.tabIndex = -1;
  });
}

/** Renders only the reader's inert, source-backed mathematics nodes in Editor previews. */
export function renderPreviewMathNodes(root: Document | HTMLElement) {
  const ownerDocument = root.nodeType === 9 ? root as Document : (root as HTMLElement).ownerDocument;
  const runtime = ownerDocument.defaultView?.scholiumMath;
  if (runtime?.version !== 1) return;
  root.querySelectorAll<HTMLElement>(
    ".scholium-math[data-math-source][data-math-kind]:not(.scholium-math-rendered):not(.scholium-math-error)",
  ).forEach((element) => {
    try {
      const encodedSource = element.dataset.mathSource;
      const kind = element.dataset.mathKind;
      if (!encodedSource || (kind !== "inline" && kind !== "display")) return;
      const source = new TextDecoder().decode(
        Uint8Array.from(atob(encodedSource), character => character.charCodeAt(0)),
      );
      const result = runtime.render({source, kind});
      if (!result.ok) {
        element.classList.add("scholium-math-error");
        element.setAttribute("aria-label", localized("Mathematics could not be rendered. Source is shown."));
        return;
      }
      const fallback = element.querySelector(".scholium-math-source");
      const rendered = ownerDocument.createElement("span");
      rendered.className = "scholium-math-output";
      rendered.innerHTML = result.html;
      fallback?.before(rendered);
      element.classList.add("scholium-math-rendered");
    } catch (_) {
      element.classList.add("scholium-math-error");
    }
  });
}

