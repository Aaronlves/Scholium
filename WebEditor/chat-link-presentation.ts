import {attachmentSymbol} from "./attachment-presentation";
import type {WebSystemSymbolKey} from "./system-symbols";

const noteID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A small local identity catalog; no page or icon URL is loaded by the reader. */
export function chatWebsiteIconKey(href: string): "openai" | null {
  let url: URL;
  try { url = new URL(href); } catch { return null; }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  const host = url.hostname.toLowerCase();
  return host === "openai.com" || host.endsWith(".openai.com")
    || host === "chatgpt.com" || host.endsWith(".chatgpt.com") ? "openai" : null;
}

/** A presentation hint for destinations Chat can actually open. It never reads a URL. */
export function chatLinkSymbol(href: string): WebSystemSymbolKey | null {
  let destination = href;
  if (href.toLowerCase().startsWith("scholium-note:") && !href.toLowerCase().startsWith("scholium-note://")) {
    try { destination = decodeURIComponent(href.slice("scholium-note:".length)); }
    catch { return null; }
  }
  let url: URL;
  try { url = new URL(destination); } catch { return null; }
  const scheme = url.protocol.toLowerCase();
  if (scheme === "scholium-note:") {
    return noteID.test(url.hostname) && (url.pathname === "" || url.pathname === "/")
      && !url.username && !url.password && !url.hash ? "doc-text" : null;
  }
  if (scheme === "zotero:") return "books-vertical";
  if (scheme !== "https:" && scheme !== "http:") return null;
  if (!url.hostname) return null;
  if (/\.(?:md|markdown)$/i.test(url.pathname)) return "doc-text";
  const fileSymbol = attachmentSymbol(url.pathname);
  return fileSymbol && fileSymbol !== "paperclip" ? fileSymbol : "globe";
}

/** CSS-only symbols leave link text, child nodes, source ranges and focus untouched. */
export function decorateChatReplyLinks(root: ParentNode): void {
  root.querySelectorAll<HTMLAnchorElement>("a").forEach(anchor => {
    const embedded = anchor.matches(".scholium-embed")
      || anchor.closest(".scholium-embedded-note") !== null;
    const symbol = embedded ? null : chatLinkSymbol(anchor.getAttribute("href") ?? "");
    if (symbol) {
      anchor.dataset.scholiumChatLinkSymbol = symbol;
      anchor.classList.add("scholium-chat-link");
      const websiteIcon = symbol === "globe" ? chatWebsiteIconKey(anchor.getAttribute("href") ?? "") : null;
      if (websiteIcon) anchor.dataset.scholiumChatWebsiteIcon = websiteIcon;
      else delete anchor.dataset.scholiumChatWebsiteIcon;
    } else {
      delete anchor.dataset.scholiumChatLinkSymbol;
      delete anchor.dataset.scholiumChatWebsiteIcon;
      anchor.classList.remove("scholium-chat-link");
    }
    // Shared document attachment hints describe filenames, including paths
    // that Chat intentionally cannot open. Chat's actual route owns its icon.
    anchor.classList.remove("scholium-attachment-link");
    delete anchor.dataset.scholiumAttachmentSymbol;
  });
}
