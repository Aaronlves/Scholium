import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {installReviewFind} from "../review-find";

function reviewFind(source: string, options: {folded?: boolean; highlights?: boolean} = {}) {
  const {document, window} = parseHTML("<html><head></head><body><main><p data-source-line='1'></p></main></body></html>");
  const paragraph = document.querySelector("p")!;
  paragraph.textContent = source;
  const scroll = vi.fn();
  paragraph.scrollIntoView = scroll;
  if (options.folded) {
    const details = document.createElement("details");
    paragraph.replaceWith(details);
    details.append(paragraph);
  }
  vi.stubGlobal("document", document);
  vi.stubGlobal("Text", window.Text);
  vi.stubGlobal("NodeFilter", {SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2});
  const highlights = new Map<string, {ranges: Range[]}>();
  vi.stubGlobal("CSS", options.highlights === false ? {} : {highlights});
  vi.stubGlobal("Highlight", class {
    ranges: Range[];
    constructor(...ranges: Range[]) { this.ranges = ranges; }
  });
  vi.stubGlobal("Range", class {
    startContainer?: Node;
    startOffset = 0;
    endOffset = 0;
    setStart(node: Node, offset: number) { this.startContainer = node; this.startOffset = offset; }
    setEnd(_node: Node, offset: number) { this.endOffset = offset; }
  });
  return {find: installReviewFind(), document, scroll, highlights};
}

describe("Review find Unicode word boundaries", () => {
  afterEach(() => vi.unstubAllGlobals());

  it.each([
    ["𐐀word word word𐐀", "word", 1],
    ["e\u0301 e e\u0300", "e", 1],
    ["e\u0301 e\u0301x", "e\u0301", 1],
    ["中文word word中文 word", "word", 1],
  ])("matches complete words in %j", (source, query, total) => {
    const {find} = reviewFind(source);
    expect(find.perform({query, caseSensitive: true, wholeWord: true, action: "present"}).total).toBe(total);
  });
  it("shares Edit's canonical-equivalence matching and maps the complete decomposed range", () => {
    const {find, highlights} = reviewFind("é e\u0301 É E\u0301");
    expect(find.perform({query: "é", caseSensitive: true, wholeWord: true, action: "present"}).total).toBe(2);
    expect(highlights.get("scholium-review-find")?.ranges)
      .toEqual([expect.objectContaining({startOffset: 2, endOffset: 4})]);
    expect(find.perform({query: "É", caseSensitive: false, wholeWord: true, action: "present"}).total).toBe(4);
  });
  it.each([true, false])("reveals a folded matching passage when navigating, with highlights=%s", highlights => {
    const {find, document, scroll} = reviewFind("Matching passage", {folded: true, highlights});
    expect(find.perform({query: "passage", caseSensitive: false, wholeWord: true, action: "present"}).total).toBe(1);
    expect(document.querySelector("details")!.hasAttribute("open")).toBe(false);
    expect(scroll).not.toHaveBeenCalled();
    find.perform({query: "passage", caseSensitive: false, wholeWord: true, action: "next"});
    expect(document.querySelector("details")!.hasAttribute("open")).toBe(true);
    expect(scroll).toHaveBeenCalledOnce();
  });
});
