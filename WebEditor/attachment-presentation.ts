import type {WebSystemSymbolKey} from "./system-symbols";

const attachmentSymbols: Readonly<Record<string, WebSystemSymbolKey>> = {
  pdf: "doc-richtext",
  doc: "doc-text", docx: "doc-text", odt: "doc-text", rtf: "doc-text", txt: "doc-text",
  xls: "tablecells", xlsx: "tablecells", ods: "tablecells", numbers: "tablecells",
  csv: "tablecells", tsv: "tablecells",
  ppt: "rectangle-on-rectangle", pptx: "rectangle-on-rectangle",
  odp: "rectangle-on-rectangle", key: "rectangle-on-rectangle",
  png: "photo", jpg: "photo", jpeg: "photo", gif: "photo", webp: "photo",
  heic: "photo", heif: "photo", avif: "photo", tiff: "photo", tif: "photo",
  bmp: "photo", svg: "photo", ico: "photo",
  zip: "doc-zipper", gz: "doc-zipper", gzip: "doc-zipper", tar: "doc-zipper",
  tgz: "doc-zipper", bz2: "doc-zipper", xz: "doc-zipper", "7z": "doc-zipper", rar: "doc-zipper",
};

/** A filename hint only: it neither reads a file nor establishes availability. */
export function attachmentSymbol(destination: string): WebSystemSymbolKey | null {
  if (/[\u0000-\u001f\u007f]/.test(destination)) return null;
  let path = destination.trim();
  // Lezer's URL child includes Markdown's optional destination delimiters.
  if (path.startsWith("<") && path.endsWith(">")) path = path.slice(1, -1);
  else if (path.startsWith("<") || path.endsWith(">")) return null;
  if (!path || path.startsWith("#")) return null;
  if (/^scholium-note:/i.test(path)) {
    path = path.slice("scholium-note:".length);
  }
  const scheme = /^([a-z][a-z\d+.-]*):/i.exec(path)?.[1].toLowerCase();
  if (scheme === "file") {
    try {
      const url = new URL(path);
      if (url.hostname && url.hostname !== "localhost") return null;
      path = url.pathname;
    } catch { return null; }
  } else if (scheme) {
    return null;
  }
  // Strip URL locators before decoding, so escaped # and ? remain filename bytes.
  path = path.split(/[?#]/, 1)[0];
  try { path = decodeURIComponent(path); } catch { return null; }
  // Review encodes the whole authored destination in its scholium-note URL,
  // including note fragments. Conservatively leave those and anchors unlabelled.
  if (path.startsWith("#") || /\.(?:md|markdown)[?#]/i.test(path)) return null;
  if (!path || /[\u0000-\u001f\u007f]/.test(path)
      || path.startsWith("//") || path.endsWith("/")
      || /^[a-z][a-z\d+.-]*:/i.test(path)) return null;
  const filename = path.slice(path.lastIndexOf("/") + 1);
  const dot = filename.lastIndexOf(".");
  if (dot <= 0 || dot === filename.length - 1) return null;
  const extension = filename.slice(dot + 1).toLowerCase();
  if (extension === "md" || extension === "markdown") return null;
  return Object.hasOwn(attachmentSymbols, extension) ? attachmentSymbols[extension] : "paperclip";
}

/** Decorate links without adding text nodes or changing selection/source offsets. */
export function decorateAttachmentLinks(root: ParentNode): void {
  root.querySelectorAll<HTMLAnchorElement>("a").forEach(anchor => {
    const excluded = anchor.matches(".wiki-link, .scholium-embed")
      || anchor.closest(".scholium-embedded-note") !== null;
    const symbol = excluded ? null : attachmentSymbol(anchor.getAttribute("href") ?? "");
    if (symbol) {
      anchor.classList.add("scholium-attachment-link");
      anchor.dataset.scholiumAttachmentSymbol = symbol;
    } else {
      if (anchor.classList.contains("scholium-attachment-link")) {
        anchor.classList.remove("scholium-attachment-link");
      }
      delete anchor.dataset.scholiumAttachmentSymbol;
    }
  });
}
