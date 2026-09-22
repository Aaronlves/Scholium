import {parseHTML} from "linkedom";
import {describe, expect, it} from "vitest";
import {attachmentSymbol, decorateAttachmentLinks} from "../attachment-presentation";

describe("attachment filename hints", () => {
  it.each([
    ["../Attachments/Paper.PDF", "doc-richtext"],
    ["<../Attachments/Paper with spaces.PDF>", "doc-richtext"],
    ["<file:///Users/Research/Paper%20one.pdf>", "doc-richtext"],
    ["scholium-note:../Attachments/%E8%AE%BA%E6%96%87%20draft%2EPdF", "doc-richtext"],
    ["/Users/Research/Paper.docx", "doc-text"],
    ["file:///Users/Research/Notes.rtf", "doc-text"],
    ["file://localhost/Users/Research/Notes.txt", "doc-text"],
    ["scholium-note:file:///Users/Research/Paper%20one.pdf", "doc-richtext"],
    ["SCHOLIUM-NOTE:FILE://localhost/Users/Research/Notes.rtf", "doc-text"],
    ["Data.XLSX", "tablecells"],
    ["Data.csv", "tablecells"],
    ["Slides.PPTX", "rectangle-on-rectangle"],
    ["Slides.key", "rectangle-on-rectangle"],
    ["Figure%20one.HEIC", "photo"],
    ["Figures/a.SvG", "photo"],
    ["archive.tar.gz", "doc-zipper"],
    ["archive.7z", "doc-zipper"],
    ["supplement.xyz", "paperclip"],
    ["supplement.constructor", "paperclip"],
    ["supplement.__proto__", "paperclip"],
    ["paper.pdf#page=4", "doc-richtext"],
    ["paper.pdf?view=1", "doc-richtext"],
    ["paper%23draft%3Ffinal.pdf", "doc-richtext"],
    ["scholium-note:paper%23draft.pdf", "doc-richtext"],
  ])("classifies local destination %s", (destination, symbol) => {
    expect(attachmentSymbol(destination)).toBe(symbol);
  });

  it.each([
    "", "#paper.pdf", "https://example.test/paper.pdf", "HTTP://example.test/a.docx",
    "<https://example.test/paper.pdf>", "<mailto:paper.pdf>", "<#paper.pdf>",
    "<Note.md>", "<incomplete.pdf", "incomplete.pdf>",
    "//example.test/paper.pdf", "mailto:paper.pdf", "zotero:paper.pdf",
    "data:paper.pdf", "javascript:paper.pdf", "file://remote-host/paper.pdf",
    "scholium-note:https://example.test/paper.pdf", "scholium-note:%2F%2Fexample.test/paper.pdf",
    "scholium-note:#paper.pdf", "https%3A%2F%2Fexample.test/paper.pdf", " https://example.test/a.pdf ",
    "scholium-note:%23part.pdf", "scholium-note:%23part%2Epdf", "%23part.pdf",
    "scholium-note:Note.md%23Section", "scholium-note:Note.MARKDOWN%23Section.pdf",
    "scholium-note:Note%2Emd%3FSection.pdf", "scholium-note:Note.md%23part%3Fview=1",
    "scholium-note:file://remote-host/paper.pdf", "scholium-note:scholium-note:paper.pdf",
    "Note.md", "Note.MARKDOWN#Section", "scholium-note:Note%2Emd", "Topics/Note",
    "Attachments/", "folder.pdf/Note", "folder.pdf/", ".hidden", "filename.",
    "bad%ZZ.pdf", "bad%00.pdf", "scholium-note:",
  ])("does not label a nonattachment or unsupported destination %s", destination => {
    expect(attachmentSymbol(destination)).toBeNull();
  });
});

describe("reader attachment decoration", () => {
  it("preserves exact text, href, children and source attributes", () => {
    const {document} = parseHTML('<article><a href="scholium-note:../Paper%20one.pdf" data-source-utf16-start="12"><em>Paper</em> 中文 😀</a></article>');
    const root = document.querySelector("article")!;
    const anchor = root.querySelector("a")!;
    const children = [...anchor.childNodes];
    const text = root.textContent;
    decorateAttachmentLinks(root);
    decorateAttachmentLinks(root);
    expect(anchor.classList.contains("scholium-attachment-link")).toBe(true);
    expect(anchor.dataset.scholiumAttachmentSymbol).toBe("doc-richtext");
    expect(root.textContent).toBe(text);
    expect(anchor.getAttribute("href")).toBe("scholium-note:../Paper%20one.pdf");
    expect(anchor.getAttribute("data-source-utf16-start")).toBe("12");
    expect([...anchor.childNodes]).toEqual(children);
  });

  it("leaves notes, wikilinks, embeds and web links undecorated", () => {
    const {document} = parseHTML('<article><a href="Note.md">Note</a><a class="wiki-link" href="scholium-note:Note.pdf">Wiki note</a><a class="scholium-embed" href="scholium-note:Note.pdf">Embed</a><section class="scholium-embedded-note"><a href="paper.pdf">Embedded content</a></section><a href="https://example.test/paper.pdf">Web</a></article>');
    const root = document.querySelector("article")!;
    const markup = root.innerHTML;
    decorateAttachmentLinks(root);
    expect(root.querySelector(".scholium-attachment-link")).toBeNull();
    expect(root.innerHTML).toBe(markup);
  });

  it("clears obsolete hints when a destination changes or disappears", () => {
    const {document} = parseHTML('<article><a href="Paper.pdf">Document</a></article>');
    const root = document.querySelector("article")!;
    const anchor = root.querySelector("a")!;
    decorateAttachmentLinks(root);
    anchor.setAttribute("href", "Note.md");
    decorateAttachmentLinks(root);
    expect(anchor.classList.contains("scholium-attachment-link")).toBe(false);
    expect(anchor.dataset.scholiumAttachmentSymbol).toBeUndefined();
    anchor.setAttribute("href", "Figure.png");
    decorateAttachmentLinks(root);
    expect(anchor.dataset.scholiumAttachmentSymbol).toBe("photo");
    anchor.removeAttribute("href");
    decorateAttachmentLinks(root);
    expect(anchor.dataset.scholiumAttachmentSymbol).toBeUndefined();
    expect(anchor.textContent).toBe("Document");
  });

  it("distinguishes encoded Review note fragments from wrapped local file URLs", () => {
    const {document} = parseHTML('<article><a href="scholium-note:Note.md%23Section.pdf">Section</a><a href="scholium-note:%23part.pdf">Anchor</a><a href="scholium-note:file:///Users/Research/Paper%20one.pdf">Paper</a></article>');
    const root = document.querySelector("article")!;
    decorateAttachmentLinks(root);
    const decorated = [...root.querySelectorAll<HTMLAnchorElement>(".scholium-attachment-link")];
    expect(decorated).toHaveLength(1);
    expect(decorated[0].textContent).toBe("Paper");
    expect(decorated[0].dataset.scholiumAttachmentSymbol).toBe("doc-richtext");
  });
});
