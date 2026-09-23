import {parseHTML} from "linkedom";
import {describe, expect, it} from "vitest";
import {chatLinkSymbol, chatWebsiteIconKey, decorateChatReplyLinks} from "../chat-link-presentation";
import {decorateAttachmentLinks} from "../attachment-presentation";

describe("Chat reply link symbols", () => {
  it.each([
    ["https://example.org/article", "globe"],
    ["https://example.org/paper.pdf#page=2", "doc-richtext"],
    ["https://example.org/review.markdown", "doc-text"],
    ["https://example.org/data.csv", "tablecells"],
    ["https://example.org/image.png", "photo"],
    ["zotero://select/library/items/ABCD1234", "books-vertical"],
    ["scholium-note:scholium-note%3A%2F%2F123e4567-e89b-12d3-a456-426614174000", "doc-text"],
  ])("labels an openable %s", (href, symbol) => {
    expect(chatLinkSymbol(href)).toBe(symbol);
  });

  it.each([
    "../paper.pdf", "scholium-note:../paper.pdf", "scholium-note:Note.md",
    "mailto:reader@example.org", "javascript:alert(1)", "https://",
    "scholium-note:scholium-note%3A%2F%2Fnot-a-uuid", "#heading",
  ])("does not imply an openable target for %s", href => {
    expect(chatLinkSymbol(href)).toBeNull();
  });

  it("uses the bundled OpenAI identity only for its exact domains", () => {
    expect(chatWebsiteIconKey("https://openai.com/research")).toBe("openai");
    expect(chatWebsiteIconKey("https://developers.openai.com/docs")).toBe("openai");
    expect(chatWebsiteIconKey("https://chatgpt.com/")).toBe("openai");
    expect(chatWebsiteIconKey("https://fakeopenai.com/")).toBeNull();
    expect(chatWebsiteIconKey("https://openai.com.evil.test/")).toBeNull();
  });

  it("keeps exact link text, children, href and source mapping across updates", () => {
    const {document} = parseHTML('<article><p><a href="https://example.org" data-source-utf16-start="4"><em>Site</em> 中文</a> and <a href="scholium-note:../paper.pdf">File</a></p></article>');
    const root = document.querySelector("article")!;
    const [site, file] = [...root.querySelectorAll("a")];
    const sourceText = root.textContent;
    const siteChildren = [...site.childNodes];
    decorateAttachmentLinks(root);
    decorateChatReplyLinks(root);
    decorateChatReplyLinks(root);
    expect(site.dataset.scholiumChatLinkSymbol).toBe("globe");
    expect(site.dataset.scholiumChatWebsiteHost).toBe("example.org");
    expect(site.getAttribute("href")).toBe("https://example.org");
    expect(site.getAttribute("data-source-utf16-start")).toBe("4");
    expect([...site.childNodes]).toEqual(siteChildren);
    expect(file.classList.contains("scholium-attachment-link")).toBe(false);
    expect(file.dataset.scholiumChatLinkSymbol).toBeUndefined();
    expect(root.textContent).toBe(sourceText);

    site.setAttribute("href", "https://example.org/Paper.PDF");
    decorateChatReplyLinks(root);
    expect(site.dataset.scholiumChatLinkSymbol).toBe("doc-richtext");
    expect(site.dataset.scholiumChatWebsiteHost).toBeUndefined();
    site.removeAttribute("href");
    decorateChatReplyLinks(root);
    expect(site.dataset.scholiumChatLinkSymbol).toBeUndefined();
    expect(site.dataset.scholiumChatWebsiteHost).toBeUndefined();
  });

  it("adds a local site icon only to website pages, preserving linked documents", () => {
    const {document} = parseHTML('<article><a href="https://openai.com/research">Site</a><a href="https://openai.com/paper.pdf">PDF</a></article>');
    const root = document.querySelector("article")!;
    const [page, pdf] = [...root.querySelectorAll("a")];
    decorateChatReplyLinks(root);
    expect(page.dataset.scholiumChatWebsiteIcon).toBe("openai");
    expect(page.dataset.scholiumChatWebsiteHost).toBe("openai.com");
    expect(pdf.dataset.scholiumChatWebsiteIcon).toBeUndefined();
    expect(pdf.dataset.scholiumChatWebsiteHost).toBeUndefined();
    page.setAttribute("href", "https://elsewhere.example/page");
    decorateChatReplyLinks(root);
    expect(page.dataset.scholiumChatWebsiteIcon).toBeUndefined();
  });
});
