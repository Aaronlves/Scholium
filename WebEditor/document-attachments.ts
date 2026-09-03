import {systemSymbolElement} from "./system-symbols";

export interface DocumentAttachmentPresentation {
  readonly id: string;
  readonly filename: string;
  readonly available: boolean;
}

interface DocumentAttachmentRailOptions {
  readonly localized: (key: "Attachments" | "Add Document" | "Preview attached document {title}" | "Attached document unavailable {title}") => string;
  readonly requestPreview: (attachmentID: string) => void;
  readonly requestMenu: (anchor: DOMRect) => void;
  readonly revealInitially: boolean;
}

function filenameParts(filename: string) {
  const characters = Array.from(filename);
  if (characters.length <= 18) return {leading: filename, trailing: ""};
  const trailingCount = Math.min(12, Math.max(7, Math.floor(characters.length / 3)));
  return {
    leading: characters.slice(0, -trailingCount).join(""),
    trailing: characters.slice(-trailingCount).join(""),
  };
}

function localizedTemplate(
  localized: DocumentAttachmentRailOptions["localized"],
  key: "Preview attached document {title}" | "Attached document unavailable {title}",
  title: string,
) {
  return localized(key).replace("{title}", title);
}

const attachmentRailByTitle = new WeakMap<HTMLElement, HTMLElement>();

function revealRailAddControl(rail: HTMLElement) {
  rail.classList.add("scholium-document-attachment-add-visible");
  (rail.ownerDocument.defaultView ?? window).setTimeout(() => {
    if (!rail.matches(":hover") && !rail.matches(":focus-within")) {
      rail.classList.remove("scholium-document-attachment-add-visible");
    }
  }, 1800);
}

export function revealDocumentAttachmentAddControl(ownerDocument: Document) {
  const rail = ownerDocument.querySelector<HTMLElement>(
    ".scholium-document-attachment-rail",
  );
  if (!rail) return false;
  revealRailAddControl(rail);
  return true;
}

function bindTitleRegionVisibility(rail: HTMLElement) {
  const title = rail.parentElement?.querySelector<HTMLElement>(".scholium-note-title")
    ?? rail.closest(".cm-content")?.querySelector<HTMLElement>(".scholium-note-title")
    ?? rail.ownerDocument.querySelector<HTMLElement>(".scholium-note-title");
  if (!title) return;
  attachmentRailByTitle.set(title, rail);
  if (title.dataset.scholiumAttachmentVisibilityBound === "true") return;
  title.dataset.scholiumAttachmentVisibilityBound = "true";
  const show = () => attachmentRailByTitle.get(title)?.classList.add(
    "scholium-document-attachment-add-visible",
  );
  const hide = () => attachmentRailByTitle.get(title)?.classList.remove(
    "scholium-document-attachment-add-visible",
  );
  title.addEventListener("pointerenter", show);
  title.addEventListener("pointerleave", hide);
  title.addEventListener("focusin", show);
  title.addEventListener("focusout", hide);
}

export function createDocumentAttachmentRail(
  ownerDocument: Document,
  attachments: readonly DocumentAttachmentPresentation[],
  options: DocumentAttachmentRailOptions,
) {
  const rail = ownerDocument.createElement("div");
  rail.className = "scholium-document-attachment-rail";
  rail.dataset.scholiumProtected = "document-attachments";
  rail.setAttribute("role", "group");
  rail.setAttribute("aria-label", options.localized("Attachments"));

  const strip = ownerDocument.createElement("div");
  strip.className = "scholium-document-attachment-strip";
  for (const attachment of attachments) {
    const button = ownerDocument.createElement("button");
    button.type = "button";
    button.className = "scholium-document-attachment-capsule";
    button.dataset.attachmentID = attachment.id;
    button.dataset.available = attachment.available ? "true" : "false";
    button.title = attachment.filename;
    const label = localizedTemplate(
      options.localized,
      attachment.available
        ? "Preview attached document {title}"
        : "Attached document unavailable {title}",
      attachment.filename,
    );
    button.setAttribute("aria-label", label);
    button.setAttribute("aria-disabled", attachment.available ? "false" : "true");
    button.append(systemSymbolElement("paperclip", "scholium-document-attachment-icon", ownerDocument));
    const text = ownerDocument.createElement("span");
    text.className = "scholium-document-attachment-name";
    const parts = filenameParts(attachment.filename);
    const leading = ownerDocument.createElement("span");
    leading.className = "scholium-document-attachment-name-leading";
    leading.textContent = parts.leading;
    const trailing = ownerDocument.createElement("span");
    trailing.className = "scholium-document-attachment-name-trailing";
    trailing.textContent = parts.trailing;
    text.append(leading, trailing);
    button.append(text);
    button.addEventListener("pointerdown", (event) => event.preventDefault());
    button.addEventListener("click", (event) => {
      event.preventDefault();
      if (attachment.available) options.requestPreview(attachment.id);
    });
    strip.append(button);
  }

  const add = ownerDocument.createElement("button");
  add.type = "button";
  add.className = "scholium-document-attachment-add";
  add.setAttribute("aria-label", options.localized("Add Document"));
  add.title = options.localized("Add Document");
  add.append(systemSymbolElement("paperclip", "scholium-document-attachment-icon", ownerDocument));
  const addLabel = ownerDocument.createElement("span");
  addLabel.textContent = options.localized("Add Document");
  add.append(addLabel);
  add.addEventListener("pointerdown", (event) => event.preventDefault());
  add.addEventListener("click", (event) => {
    event.preventDefault();
    options.requestMenu(add.getBoundingClientRect());
  });
  strip.append(add);
  rail.append(strip);

  if (options.revealInitially) {
    revealRailAddControl(rail);
  }
  rail.addEventListener("pointerenter", () => {
    rail.classList.add("scholium-document-attachment-add-visible");
  });
  rail.addEventListener("pointerleave", () => {
    if (!rail.matches(":focus-within")) {
      rail.classList.remove("scholium-document-attachment-add-visible");
    }
  });
  rail.addEventListener("focusin", () => {
    rail.classList.add("scholium-document-attachment-add-visible");
  });
  rail.addEventListener("focusout", () => {
    if (!rail.matches(":hover")) {
      rail.classList.remove("scholium-document-attachment-add-visible");
    }
  });
  queueMicrotask(() => bindTitleRegionVisibility(rail));
  return rail;
}
