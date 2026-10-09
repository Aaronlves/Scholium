import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createTableDOM, rebaseRenderedSourceLocations} from "../markdown-fragment";
import {createProjectedWidgetRegistry} from "../projected-widget-registry";
import {tablePresentation} from "../table-presentation";

function tableFixture(body: string) {
  const source = `Previous prose.\n\n| Header | Value |\n| --- | --- |\n| p | ${body.replace(/^\|\s*/, "")}`;
  const presentation = tablePresentation(source, source.indexOf("| Header"), source.length)!;
  const {document, window} = parseHTML("<html><body></body></html>");
  vi.stubGlobal("document", document);
  vi.stubGlobal("Element", window.Element);
  vi.stubGlobal("NodeFilter", {SHOW_TEXT: 4});
  const dom = createTableDOM(presentation, document, {mathematics: {
    inlineDelimiter: "$", displayDelimiter: "$$", singleDollarInline: true,
  }});
  dom.classList.add("cm-live-table-widget");
  document.body.append(dom);
  const registry = createProjectedWidgetRegistry();
  registry.setTable(dom, presentation);
  const cell = dom.querySelector("td:last-child")!;
  const textNodes: Node[] = [];
  const visit = (node: Node) => {
    if (node.nodeType === 3) textNodes.push(node);
    for (const child of node.childNodes) visit(child);
  };
  visit(cell);
  const click = (text: string, offset: number, target: Element = cell) => {
    const node = textNodes.find(node => node.textContent === text);
    expect(node, `Rendered text ${JSON.stringify(text)}`).toBeDefined();
    Object.assign(document, {
      caretRangeFromPoint: () => ({startContainer: node, startOffset: offset}),
      elementsFromPoint: () => [target],
    });
    return registry.sourceOffset({target, clientX: 0, clientY: 0} as unknown as MouseEvent);
  };
  return {source, presentation, dom, cell, document, registry, textNodes, click};
}

describe("projected table caret source locations", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("maps formatted, escaped, entity, code and mixed-script text to exact source", () => {
    const f = tableFixture("| **bold** a \\| b &amp; ` c\\|d ` 中文 😀 é |");
    expect(f.click("bold", 2)).toBe(f.source.indexOf("bold") + 2);
    expect(f.click(" a | b ", 6)).toBe(f.source.indexOf(" b ") + 2);
    expect(f.click("&", 1)).toBe(f.source.indexOf("&amp;") + 5);
    expect(f.click("c|d", 2)).toBe(f.source.indexOf("d `"));
    expect(f.click("中文", 1)).toBe(f.source.indexOf("中文") + 1);
    expect(f.click(" 😀 é", 3)).toBe(f.source.indexOf("😀") + 2);
  });

  it("maps link objects relative to their cell and rebinds reused DOM after a source shift", () => {
    const f = tableFixture("| **bold** [[Note]] |");
    const link = f.cell.querySelector(".cm-live-wiki-link")!;
    const at = () => f.registry.sourceOffset({target: link} as unknown as MouseEvent);
    expect(at()).toBe(f.source.indexOf("[[Note]]") + "[[Note]]".length);
    rebaseRenderedSourceLocations(f.dom, 7);
    f.registry.setTable(f.dom, {...f.presentation, from: f.presentation.from + 7, to: f.presentation.to + 7});
    expect(at()).toBe(f.source.indexOf("[[Note]]") + "[[Note]]".length + 7);
    expect(f.click("bold", 2)).toBe(f.source.indexOf("bold") + 9);
  });

  it("allows the insertion point after the final character without a trailing table pipe", () => {
    const f = tableFixture("last");
    expect(f.click("last", 4)).toBe(f.source.length);
  });

  it("keeps a table formula source-owned, including its exact failure fallback", () => {
    const f = tableFixture("| before $ invalid $ after |");
    const formula = f.cell.querySelector<HTMLElement>(".scholium-math")!;
    expect(formula.textContent).toBe("$ invalid $");
    expect(f.registry.sourceOffset({target: formula} as unknown as MouseEvent))
      .toBe(f.source.indexOf("$ invalid $"));
  });

  it("uses complete graphemes when a cell padding point has no native text caret", () => {
    const f = tableFixture("| 😀é |");
    const measured: [number, number][] = [];
    Object.assign(f.document, {
      caretRangeFromPoint: () => null,
      elementsFromPoint: () => [f.cell],
      createRange: () => {
        let from = 0, to = 0;
        return {
          setStart: (_node: Node, offset: number) => { from = offset; },
          setEnd: (_node: Node, offset: number) => { to = offset; },
          getBoundingClientRect: () => {
            measured.push([from, to]);
            return {left: from * 10, right: to * 10, top: 0, bottom: 10, width: (to - from) * 10, height: 10};
          },
        };
      },
    });
    expect(f.registry.sourceOffset({target: f.cell, clientX: 18, clientY: 5} as unknown as MouseEvent))
      .toBe(f.source.indexOf("😀") + 2);
    expect(measured).toEqual([[0, 2], [2, 4]]);
  });

  it("does not split a Han base from its combining mark or variation selector", () => {
    const f = tableFixture("| 中́文󠄀 |");
    expect(f.textNodes.map(node => node.textContent)).toEqual(["中́文󠄀"]);
    expect(f.click("中́文󠄀", 2)).toBe(f.source.indexOf("中́") + 2);
  });
});
