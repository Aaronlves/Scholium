import {EditorState} from "@codemirror/state";
import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {projectCommittedReviewCalloutRhythm} from "../committed-review-rhythm";
import {ExactSourceMirror} from "../state";
import {readerSourceRangeCandidate} from "../arrival-highlight";
import {installReviewFind} from "../review-find";
import {boundedReviewRangeText} from "../review-selection-text";
import {calloutSourceGapCSS} from "../callout-presentation";

const fixtureSource = "> [!state] FirstBoundary\n> FirstBody.\n\n> [!cite] SingleBoundary\n> SingleBody.\n\n\n\n> [!connect] MultipleBoundary\n> MultipleBody.\n\nBeforeZeroBoundary.\n> [!flag] FinalBoundary\n> FinalBody.\n";

function fixture(source: string) {
  const {document} = parseHTML('<html><body><main class="scholium-document"></main></body></html>');
  const root = document.querySelector("main")!;
  for (const [title, body, role] of [["FirstBoundary", "FirstBody.", "state"],
    ["SingleBoundary", "SingleBody.", "cite"], ["MultipleBoundary", "MultipleBody.", "connect"],
    ["BeforeZeroBoundary.", "BeforeZeroBoundary.", null], ["FinalBoundary", "FinalBody.", "flag"]]) {
    const block = document.createElement(role ? "aside" : "p");
    const from = role ? source.indexOf(`> [!${role}]`) : source.indexOf(title!);
    const to = source.indexOf(body!, from) + body!.length;
    block.dataset.sourceUtf16Start = String(from);
    block.dataset.sourceUtf16End = String(to);
    if (role) {
      block.className = `scholium-callout scholium-callout-${role}`;
      block.innerHTML = `<header><span class="scholium-callout-title">${title}</span></header><div class="scholium-callout-body"><p>${body}</p></div>`;
    } else block.textContent = title;
    root.append(block);
  }
  return {root, mirror: new ExactSourceMirror(source), doc: EditorState.create({doc: source}).doc};
}

describe("exact-source Callout separation in the committed Review adapter", () => {
  afterEach(() => vi.unstubAllGlobals());
  it.each(["\n", "\r\n"])("shares 0/1/multiple authored separator rows without adding source or reading text (%j)", newline => {
    const source = "\uFEFF😀" + newline + newline + fixtureSource.replaceAll("\n", newline);
    const f = fixture(source);
    const content = f.root.textContent;
    const childNodes = Array.from(f.root.childNodes);
    const descendants = (node: Node): Node[] => [node, ...Array.from(node.childNodes).flatMap(descendants)];
    const textNodes = descendants(f.root).filter(node => node.nodeType === 3);
    const text = textNodes.map(node => node.textContent);
    const blocks = Array.from(f.root.children);
    const sourceObjects = f.root.querySelectorAll("[data-source-utf16-start]").length;
    projectCommittedReviewCalloutRhythm(f.root, f.mirror, f.doc);
    const boundaries = Array.from(f.root.querySelectorAll<HTMLElement>("[data-scholium-review-gap-before]"));
    expect(boundaries.map(block => block.dataset.scholiumReviewSourceGap)).toEqual(["1", "3", "1", "0"]);
    expect(boundaries.map(block => block.style.getPropertyValue("--scholium-review-boundary-callout-gap"))).toEqual([
      `max(${calloutSourceGapCSS("state")}, ${calloutSourceGapCSS("cite")})`,
      `max(${calloutSourceGapCSS("cite")}, ${calloutSourceGapCSS("connect")})`,
      calloutSourceGapCSS("connect"), calloutSourceGapCSS("flag"),
    ]);
    expect(blocks[0].hasAttribute("data-scholium-review-gap-before")).toBe(false);
    expect(blocks.at(-1)!.hasAttribute("data-scholium-review-gap-after")).toBe(false);
    expect(blocks[3].hasAttribute("data-scholium-review-gap-before")).toBe(true);
    expect(blocks[3].hasAttribute("data-scholium-review-gap-after")).toBe(true);
    expect(f.root.querySelector(".scholium-review-source-gap")).toBeNull();
    expect(Array.from(f.root.childNodes)).toEqual(childNodes);
    childNodes.forEach((node, index) => expect(f.root.childNodes[index]).toBe(node));
    const afterTextNodes = descendants(f.root).filter(node => node.nodeType === 3);
    expect(afterTextNodes).toHaveLength(textNodes.length);
    textNodes.forEach((node, index) => expect(afterTextNodes[index]).toBe(node));
    expect(afterTextNodes.map(node => node.textContent)).toEqual(text);
    expect(f.root.querySelectorAll("[data-source-utf16-start]")).toHaveLength(sourceObjects);
    expect(f.root.textContent).toBe(content);
    expect(f.mirror.text).toBe(source);
    expect(f.doc.toString()).toBe(source.replaceAll("\r\n", "\n"));
  });

  it("keeps unsupported intervening elements, missing source and nonwhitespace gaps in their native layout", () => {
    const f = fixture(fixtureSource);
    const blocks = Array.from(f.root.children);
    const list = f.root.ownerDocument.createElement("ul");
    list.textContent = "Unsupported intervening list";
    f.root.insertBefore(list, blocks[1]);
    blocks[2].removeAttribute("data-source-utf16-end");
    // This range omits visible source text before the final Callout. The
    // adapter cannot authorize geometry across that unrepresented passage.
    blocks[3].setAttribute("data-source-utf16-end", String(fixtureSource.indexOf("BeforeZeroBoundary.") + 1));
    projectCommittedReviewCalloutRhythm(f.root, f.mirror, f.doc);
    expect(f.root.querySelector(".scholium-review-source-gap")).toBeNull();
    expect(f.root.querySelector("[data-scholium-review-gap-before]")).toBeNull();
    expect(list.textContent).toBe("Unsupported intervening list");
  });

  it("retains native reading selection text, Find ranges and source candidates without spacer objects", () => {
    const f = fixture(fixtureSource);
    const document = f.root.ownerDocument;
    f.root.querySelectorAll("p").forEach(paragraph => { paragraph.scrollIntoView = () => {}; });
    vi.stubGlobal("document", document);
    vi.stubGlobal("Text", document.defaultView!.Text);
    vi.stubGlobal("NodeFilter", {SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2});
    const highlights = new Map<string, {ranges: Range[]}>();
    vi.stubGlobal("CSS", {highlights});
    // Use the same actual Find walker and node/offset mapping as the reader.
    vi.stubGlobal("Highlight", class { ranges: Range[]; constructor(...ranges: Range[]) { this.ranges = ranges; } });
    vi.stubGlobal("Range", class {
      startContainer?: Node; endContainer?: Node; startOffset = 0; endOffset = 0;
      setStart(node: Node, offset: number) { this.startContainer = node; this.startOffset = offset; }
      setEnd(node: Node, offset: number) { this.endContainer = node; this.endOffset = offset; }
    });
    const first = f.root.querySelector(".scholium-callout-title")!.firstChild!;
    const last = f.root.querySelectorAll(".scholium-callout-body p")[3].firstChild!;
    const selection = {startContainer: first, startOffset: 0, endContainer: last,
      endOffset: last.textContent!.length, intersectsNode: () => true} as unknown as Range;
    const selectedText = boundedReviewRangeText(selection, f.root, 32000);
    const candidate = () => readerSourceRangeCandidate(f.root, fixtureSource.indexOf("SingleBody."), fixtureSource.indexOf("SingleBody.") + 6);
    const sourceCandidate = candidate();
    const find = installReviewFind(f.root);
    const query = {query: "Body.", caseSensitive: true, wholeWord: false, action: "update" as const};
    expect(find.perform(query).total).toBe(4);
    const ranges = [...highlights.values()].flatMap(value => value.ranges);
    projectCommittedReviewCalloutRhythm(f.root, f.mirror, f.doc);
    expect(boundedReviewRangeText(selection, f.root, 32000)).toBe(selectedText);
    expect(candidate()).toEqual(sourceCandidate);
    expect(find.perform(query).total).toBe(4);
    expect([...highlights.values()].flatMap(value => value.ranges)).toEqual(ranges);
    find.destroy();
    f.root.replaceChildren();
    expect(() => projectCommittedReviewCalloutRhythm(f.root, f.mirror, f.doc)).not.toThrow();
    expect(f.root.childNodes).toHaveLength(0);
  });
});
