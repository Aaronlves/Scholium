import {DOMParser as LinkedomDOMParser, parseHTML} from "linkedom";
import {existsSync, readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {afterEach, describe, expect, it, vi} from "vitest";
import {
  mermaidThemeFromStyle,
  copyMermaidSVG,
  sanitizeMermaidSVG,
  scholiumMermaidRuntime,
  validateMermaidSource,
} from "../mermaid-runtime";

describe("shared Mermaid runtime boundary", () => {
  it("revalidates independent SVG copies and never copies consumed or untrusted nodes", () => {
    const parser = new LinkedomDOMParser() as unknown as DOMParser;
    const original = sanitizeMermaidSVG(
      '<svg xmlns="http://www.w3.org/2000/svg" aria-labelledby="title" aria-describedby="description"><title id="title">Reasons</title><desc id="description">A supports B.</desc><defs><marker id="arrow"><path d="M0 0L1 1"/></marker></defs><path marker-end="url(#arrow)"/></svg>', parser,
    )!;
    const copy = copyMermaidSVG(original, parser)!;
    expect(copy).not.toBeNull();
    expect(copy).not.toBe(original);
    expect(copy.outerHTML).toBe(original.outerHTML);
    const {document} = parseHTML('<div id="one"></div><div id="two"></div><div id="three"></div>');
    const one = document.getElementById("one") as unknown as HTMLElement;
    const two = document.getElementById("two") as unknown as HTMLElement;
    expect(scholiumMermaidRuntime.mount(one, original)).toBe(true);
    expect(scholiumMermaidRuntime.mount(two, copy)).toBe(true);
    expect(one.shadowRoot).not.toBe(two.shadowRoot);
    expect(one.shadowRoot?.querySelector("svg")).toBe(original);
    expect(two.shadowRoot?.querySelector("svg")).toBe(copy);
    expect(scholiumMermaidRuntime.mount(document.getElementById("three") as unknown as HTMLElement, copy)).toBe(false);
    expect(copyMermaidSVG(original, parser)).toBeNull();
    expect(copyMermaidSVG(copy, parser)).toBeNull();
    const mutated = sanitizeMermaidSVG('<svg xmlns="http://www.w3.org/2000/svg"/>', parser)!;
    mutated.setAttribute("onload", "private authored script");
    expect(copyMermaidSVG(mutated, parser)).toBeNull();
    const untrusted = parser.parseFromString('<svg xmlns="http://www.w3.org/2000/svg"/>', "image/svg+xml").documentElement as unknown as SVGSVGElement;
    expect(copyMermaidSVG(untrusted, parser)).toBeNull();
  });

  afterEach(() => vi.unstubAllGlobals());

  function renderFixture(source: string, signal?: AbortSignal) {
    const {document} = parseHTML("<html><body></body></html>");
    const colors = new Map([
      ["--scholium-color-document-background", "#ffffff"],
      ["--scholium-color-surface-background", "#eeeeee"],
      ["--scholium-color-primary-text", "#111111"],
      ["--scholium-color-accent", "#0066cc"],
      ["--scholium-color-separator", "#777777"],
      ["--scholium-document-body-font-family", "system-ui"],
    ]);
    vi.stubGlobal("getComputedStyle", () => ({getPropertyValue: (name: string) => colors.get(name) ?? ""}));
    vi.stubGlobal("DOMParser", LinkedomDOMParser);
    return scholiumMermaidRuntime.render({source, signal, themeRoot: document.documentElement as unknown as Element});
  }

  it("uses only pinned Pele and retires Mermaid.js and its sanitizer dependency", () => {
    const packageURL = new URL("../node_modules/pele/package.json", import.meta.url);
    expect(JSON.parse(readFileSync(fileURLToPath(packageURL), "utf8")).version).toBe("1.6.0");
    expect(existsSync(new URL("../node_modules/mermaid/package.json", import.meta.url))).toBe(false);
    expect(existsSync(new URL("../node_modules/dompurify/package.json", import.meta.url))).toBe(false);
  });

  it("settles upstream adversarial input without prototype writes or unbounded output", async () => {
    const architecture = await renderFixture(
      "architecture-beta\n  group mermaidPrototypePollutionMarker(cloud)[Marker]\n  service a(server)[A] in __proto__\n  service b(server)[B] in mermaidPrototypePollutionMarker\n  a:R -- L:b");
    expect(architecture.ok).toBe(false);
    expect(Object.hasOwn(Object.prototype, "mermaidPrototypePollutionMarker")).toBe(false);
    for (const source of [
      "xychart\n  x-axis 1 --> 1\n  line [1, 2]",
      "radar-beta\n  axis a, b\n  curve c {1, 1}\n  ticks 1000000000",
    ]) {
      const result = await renderFixture(source);
      expect(result.ok).toBe(true);
      if (result.ok) expect(result.svg.outerHTML.length).toBeLessThan(2_000_000);
    }
  });

  it("renders mixed-script labels, authored accessibility and local references through Pele", async () => {
    const source = "flowchart LR\naccTitle: 理由 Reasons\naccDescr: 中文 😀 and English.\nsubgraph premise[前提]\n A[理由] --> B[结论]\nend";
    const result = await renderFixture(source);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.kind).toBe("flowchart");
    expect(result.accessibilityWarning).toBe(false);
    expect(result.svg.classList.contains("pele")).toBe(true);
    expect(result.svg.querySelector("title")?.textContent).toBe("理由 Reasons");
    expect(result.svg.querySelector("desc")?.textContent).toBe("中文 😀 and English.");
    expect(result.svg.textContent).toContain("结论");
    for (const attribute of ["aria-labelledby", "aria-describedby"]) {
      const id = result.svg.getAttribute(attribute)!;
      expect(result.svg.querySelector(`[id="${id}"]`)).not.toBeNull();
    }
    expect(result.svg.style.getPropertyValue("--pele-surface")).toBe("#eeeeee");
    expect(result.svg.style.getPropertyValue("--pele-series-1")).toBe("#111111");
  });

  it("keeps otherwise admitted sequence links and Markdown resource labels inert", async () => {
    for (const source of [
      'sequenceDiagram\nparticipant A\nparticipant B\nlink A: Website @ https://example.invalid\nA->>B: Reason',
      'flowchart LR\nA["`[label](https://example.invalid)`"] --> B["`![image](https://example.invalid/image.png)`"]',
    ]) {
      expect(validateMermaidSource(source).ok).toBe(true);
      const result = await renderFixture(source);
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.svg.querySelector("a, image, script, foreignObject, use")).toBeNull();
        expect(result.svg.querySelector("[href], [onclick]")).toBeNull();
      }
    }
  });

  it("preserves uncolored sequence grouping and rejects colored boxes", async () => {
    for (const boundary of ["\n", "; "]) {
      const source = (box: string) => ["sequenceDiagram", box, "participant A", "participant B", "end", "A->>B: Reason"].join(boundary);
      expect((await renderFixture(source("box Research group"))).ok).toBe(true);
      expect(await renderFixture(source("box red Research group"))).toEqual({ok: false, reason: "unsafe-syntax"});
    }
  });

  it("enforces source and edge limits and cancels before deferred rendering", async () => {
    const edges = Array.from({length: 513}, (_, i) => `A${i} --> A${i + 1}`).join("; ");
    expect((await renderFixture(`flowchart LR; ${edges}`)).ok).toBe(false);
    expect(validateMermaidSource(Array(513).fill("%% comment").join("\n")).ok).toBe(false);
    const controller = new AbortController();
    const pending = renderFixture("flowchart LR\nA --> B", controller.signal);
    controller.abort();
    expect(await pending).toEqual({ok: false, reason: "cancelled"});
  });

  it("admits every static built-in diagram family without a product-maintained type whitelist", () => {
    for (const source of [
      "flowchart LR\nA --> B",
      "mindmap\n  root((Question))\n    Reason",
      "sequenceDiagram\nA->>B: Reason",
      "stateDiagram-v2\n[*] --> Draft",
      "classDiagram\nClaim <|-- Objection",
      "erDiagram\nCLAIM ||--o{ REASON : has",
      "pie title Reasons\n\"For\" : 2\n\"Against\" : 1",
      "timeline\ntitle Development\n2026 : Revision",
    ]) {
      expect(validateMermaidSource(source).ok).toBe(true);
    }
  });

  it("requires bounded inert source while treating accessibility metadata as a diagnostic", () => {
    expect(validateMermaidSource("flowchart LR\nA --> B")).toEqual({
      ok: true,
      accessibilityWarning: true,
    });
    expect(validateMermaidSource("flowchart LR\naccTitle: Reasons\naccDescr: A reason supports a conclusion.\nA --> B")).toEqual({
      ok: true,
      accessibilityWarning: false,
    });
    expect(validateMermaidSource("flowchart LR\naccTitle: Reasons\naccDescr {\nA reason supports a conclusion.\n}\nA --> B")).toEqual({
      ok: true,
      accessibilityWarning: false,
    });
    expect(validateMermaidSource("flowchart LR\nclick A https://example.com")).toEqual({
      ok: false,
      reason: "unsafe-syntax",
    });
    expect(validateMermaidSource("%%{init: {'securityLevel': 'loose'}}%%\nflowchart LR\nA-->B")).toEqual({
      ok: false,
      reason: "unsafe-syntax",
    });
    expect(validateMermaidSource("flowchart LR\nclassDef claim fill:red")).toEqual({
      ok: false,
      reason: "unsafe-syntax",
    });
    expect(validateMermaidSource("flowchart LR; style A fill:red")).toEqual({
      ok: false,
      reason: "unsafe-syntax",
    });
    expect(validateMermaidSource("flowchart LR\nclass A animated")).toEqual({
      ok: false,
      reason: "unsafe-syntax",
    });
    expect(validateMermaidSource("flowchart LR\nA:::animated --> B")).toEqual({
      ok: false,
      reason: "unsafe-syntax",
    });
    expect(validateMermaidSource('flowchart LR\nA@{ img : "https://example.com/a.png" }')).toEqual({
      ok: false,
      reason: "unsafe-syntax",
    });
    expect(validateMermaidSource('flowchart LR\nA["<img src=https://example.com/a.png>"]')).toEqual({
      ok: false,
      reason: "unsafe-syntax",
    });
    expect(validateMermaidSource("gantt\ntodayMarker stroke:red")).toEqual({ok: false, reason: "unsafe-syntax"});
    expect(validateMermaidSource("gantt\ntodayMarker off").ok).toBe(true);
    expect(validateMermaidSource('C4Context\nPerson(p,"P")\nUpdateElementStyle(p,$bgColor="red")')).toEqual({ok: false, reason: "unsafe-syntax"});
    expect(validateMermaidSource('C4Context\nRel(a,b,"R")\nUpdateRelStyle(a,b,$textColor="red")')).toEqual({ok: false, reason: "unsafe-syntax"});
    expect(validateMermaidSource("sequenceDiagram\nrect red\nA->>B: Test\nend")).toEqual({ok: false, reason: "unsafe-syntax"});
    expect(validateMermaidSource("sequenceDiagram; rect red; A->>B: Test; end")).toEqual({ok: false, reason: "unsafe-syntax"});
    expect(validateMermaidSource("x".repeat(32_769))).toEqual({
      ok: false,
      reason: "invalid-source",
    });
  });

  it("keeps inert accessibility and local-fragment SVG while rejecting active output", () => {
    const parser = new LinkedomDOMParser() as unknown as DOMParser;
    const sanitized = sanitizeMermaidSVG(
      '<svg xmlns="http://www.w3.org/2000/svg"><title>Reasons</title><desc>A supports B.</desc><defs><marker id="arrow"><path d="M0 0L1 1"/></marker></defs><path marker-end="url(#arrow)"/></svg>',
      parser,
    );
    const markup = sanitized?.outerHTML ?? "";
    expect(markup).toContain('role="img"');
    expect(markup).toContain("<title>Reasons</title>");
    expect(markup).toContain("<desc>A supports B.</desc>");
    expect(markup).toContain('marker-end="url(#arrow)"');
    expect(sanitizeMermaidSVG(
      '<svg xmlns="http://www.w3.org/2000/svg" onload="attack()"><script>attack()</script></svg>',
      parser,
    )).toBeNull();
    expect(sanitizeMermaidSVG(
      '<svg xmlns="http://www.w3.org/2000/svg"><a href="#local"><text>Link</text></a></svg>',
      parser,
    )).toBeNull();
    expect(sanitizeMermaidSVG(
      '<svg xmlns="http://www.w3.org/2000/svg"><style>.x{fill:url(https://example.com/a)}</style></svg>',
      parser,
    )).toBeNull();
    expect(sanitizeMermaidSVG(
      '<svg xmlns="http://www.w3.org/2000/svg"><style>:host{position:fixed}</style></svg>',
      parser,
    )).toBeNull();
    expect(sanitizeMermaidSVG(
      '<svg xmlns="http://www.w3.org/2000/svg"><style>::slotted(*){display:none}</style></svg>',
      parser,
    )).toBeNull();
  });

  it("mounts only sanitized SVG in an isolated static shadow tree", () => {
    const parser = new LinkedomDOMParser() as unknown as DOMParser;
    const sanitized = sanitizeMermaidSVG(
      '<svg xmlns="http://www.w3.org/2000/svg"><style>#diagram{fill:red}</style><path d="M0 0L1 1"/></svg>',
      parser,
    );
    const {document} = parseHTML('<div id="host"></div><div id="other"></div>');
    const host = document.getElementById("host") as unknown as HTMLElement;
    const other = document.getElementById("other") as unknown as HTMLElement;
    expect(sanitized).not.toBeNull();
    expect(scholiumMermaidRuntime.mount(host, sanitized!)).toBe(true);
    expect(host.shadowRoot?.querySelector("svg")).toBe(sanitized);
    expect(document.querySelector("#host svg")).toBeNull();
    expect([...host.shadowRoot!.querySelectorAll("style")].some((style) =>
      style.textContent?.includes("animation: none !important"))).toBe(true);
    const isolatedStyle = [...host.shadowRoot!.querySelectorAll("style")]
      .map((style) => style.textContent ?? "")
      .join("\n");
    expect(isolatedStyle).toContain("min-inline-size: 0 !important");
    expect(isolatedStyle).toContain("max-inline-size: 100% !important");
    expect(isolatedStyle).toContain("max-block-size: var(--scholium-diagram-max-block-size, min(70vh, 42rem)) !important");
    expect(isolatedStyle).not.toContain("min-inline-size: min(100%, 32rem)");
    expect(scholiumMermaidRuntime.mount(host, sanitized!)).toBe(false);
    const untrusted = parser.parseFromString(
      '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
      "image/svg+xml",
    ).documentElement as unknown as SVGSVGElement;
    expect(scholiumMermaidRuntime.mount(other, untrusted)).toBe(false);
  });

  it("derives Mermaid colors only from the protected semantic palette", () => {
    const colors = new Map([
      ["--scholium-color-document-background", "#fef8ed"],
      ["--scholium-color-surface-background", "#f4eee3"],
      ["--scholium-color-primary-text", "#28241d"],
      ["--scholium-color-accent", "-apple-system-control-accent"],
      ["--scholium-color-separator", "#c5c0b5"],
      ["--scholium-document-body-font-family", "Alegreya, Georgia, serif"],
    ]);
    const style = {getPropertyValue: (name: string) => colors.get(name) ?? ""};
    const theme = mermaidThemeFromStyle(style);
    expect(theme).toMatchObject({
      fontFamily: "Alegreya, Georgia, serif",
      variables: {
        "--pele-bg": "#fef8ed",
        "--pele-fg": "#28241d",
        "--pele-surface": "#f4eee3",
        "--pele-border": "-apple-system-control-accent",
        "--pele-line": "#c5c0b5",
        "--pele-font": "Alegreya, Georgia, serif",
      },
    });
    for (let index = 1; index <= 8; index += 1) {
      expect(theme?.variables[`--pele-series-${index}`]).toBe("#28241d");
    }
    expect(mermaidThemeFromStyle(style, "#007aff")?.variables["--pele-border"]).toBe("#007aff");
    colors.set("--scholium-color-accent", "url(https://example.invalid/accent)");
    expect(mermaidThemeFromStyle(style)).toBeNull();
  });

  it("publishes one versioned asynchronous mode-neutral contract", async () => {
    expect(scholiumMermaidRuntime.version).toBe(3);
    await expect(scholiumMermaidRuntime.render({source: ""})).resolves.toEqual({
      ok: false,
      reason: "invalid-source",
    });
    const controller = new AbortController();
    controller.abort();
    await expect(scholiumMermaidRuntime.render({
      source: "flowchart LR\nA --> B",
      signal: controller.signal,
    })).resolves.toEqual({
      ok: false,
      reason: "cancelled",
    });
  });
});
