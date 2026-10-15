import {DOMParser as LinkedomDOMParser, parseHTML} from "linkedom";
import {describe, expect, it} from "vitest";
import {createReaderMermaidPass} from "../reader-mermaid-pass";
import {copyMermaidSVG, sanitizeMermaidSVG, scholiumMermaidRuntime} from "../mermaid-runtime";
import type {ScholiumMermaidRenderResult, ScholiumMermaidRuntime} from "../mermaid-runtime";

function harness() {
  const parser = new LinkedomDOMParser() as unknown as DOMParser;
  const {document} = parseHTML('<html><body></body></html>');
  const root = document.documentElement as unknown as Element;
  const calls: string[] = [];
  let copies = 0;
  const runtime: ScholiumMermaidRuntime = {
    version: 3,
    async render({source, themeRoot}) {
      expect(themeRoot).toBe(root);
      calls.push(source);
      const svg = sanitizeMermaidSVG('<svg xmlns="http://www.w3.org/2000/svg"><title>Fixture</title><path d="M0 0L1 1"/></svg>', parser)!;
      return {ok: true, svg, kind: "flowchart", accessibilityWarning: false};
    },
    copy(svg) {copies++; return copyMermaidSVG(svg, parser);},
    mount: scholiumMermaidRuntime.mount,
  };
  return {runtime, root, calls, get copies() {return copies;}, document};
}

describe("complete reader Mermaid passes", () => {
  it("renders mixed duplicate and unique exact sources in order and mounts independent copies once", async () => {
    const h = harness();
    const sources = ["A", "B", "A", "C", "B"];
    const render = createReaderMermaidPass(sources, h.root, () => 0);
    const nodes: SVGSVGElement[] = [];
    for (const source of sources) {
      const result = await render(h.runtime, source);
      expect(result.ok).toBe(true);
      if (!result.ok) throw new Error("Expected synthetic successful rendering");
      nodes.push(result.svg);
      const host = h.document.createElement("div") as unknown as HTMLElement;
      expect(h.runtime.mount(host, result.svg)).toBe(true);
      expect(h.runtime.mount(host, result.svg)).toBe(false);
      expect(host.shadowRoot?.querySelector("title")?.textContent).toBe("Fixture");
    }
    expect(h.calls).toEqual(["A", "B", "C"]);
    expect(new Set(nodes).size).toBe(5);
  });

  it("does no copying for distinct source bytes and retains whitespace distinctions", async () => {
    const h = harness();
    const sources = ["A", "A\n", "A\r\n", "a", "A "];
    const render = createReaderMermaidPass(sources, h.root, () => 0);
    for (const source of sources) await render(h.runtime, source);
    expect(h.calls).toEqual(sources);
    expect(h.copies).toBe(0);
  });

  it("never carries templates across a presentation change, an in-flight change or another complete pass", async () => {
    const h = harness();
    let revision = 0;
    const sources = ["A", "A", "A"];
    const render = createReaderMermaidPass(sources, h.root, () => revision);
    const original = h.runtime.render;
    let release!: () => void;
    const gate = new Promise<void>(resolve => {release = resolve;});
    h.runtime.render = async request => {await gate; return original(request);};
    const pending = render(h.runtime, "A");
    revision++;
    release();
    await pending;
    await render(h.runtime, "A");
    await render(h.runtime, "A");
    expect(h.calls).toEqual(["A", "A"]);
    revision++;
    await render(h.runtime, "A");
    expect(h.calls).toEqual(["A", "A", "A"]);
    const next = createReaderMermaidPass(sources, h.root, () => revision);
    await next(h.runtime, "A");
    await next(h.runtime, "A");
    expect(h.calls).toEqual(["A", "A", "A", "A"]);
  });

  it("preserves failures and falls back to rendering when copy admission fails", async () => {
    const h = harness();
    const sources = ["A", "A"];
    const original = h.runtime.render;
    h.runtime.render = async request => {
      await original(request);
      return {ok: false, reason: "unsafe-output"} as ScholiumMermaidRenderResult;
    };
    const failed = createReaderMermaidPass(sources, h.root, () => 0);
    expect(await failed(h.runtime, "A")).toEqual({ok: false, reason: "unsafe-output"});
    expect(await failed(h.runtime, "A")).toEqual({ok: false, reason: "unsafe-output"});
    h.runtime.render = original;
    h.runtime.copy = () => null;
    const denied = createReaderMermaidPass(sources, h.root, () => 0);
    await denied(h.runtime, "A");
    await denied(h.runtime, "A");
    expect(h.calls).toEqual(["A", "A", "A", "A"]);
  });
});
