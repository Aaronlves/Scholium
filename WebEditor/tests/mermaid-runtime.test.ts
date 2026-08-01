import {DOMParser as LinkedomDOMParser, parseHTML} from "linkedom";
import {describe, expect, it} from "vitest";
import {
  mermaidThemeFromStyle,
  sanitizeMermaidSVG,
  scholiumMermaidRuntime,
  validateMermaidSource,
} from "../mermaid-runtime";

describe("shared Mermaid runtime boundary", () => {
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
    expect(isolatedStyle).toContain("max-block-size: min(70vh, 42rem) !important");
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
      ["--scholium-color-accent", "#9d4114"],
      ["--scholium-color-separator", "#c5c0b5"],
    ]);
    const style = {getPropertyValue: (name: string) => colors.get(name) ?? ""};
    const theme = mermaidThemeFromStyle(style);
    expect(theme).toMatchObject({
      darkMode: false,
      variables: {
        background: "#fef8ed",
        primaryColor: "#f4eee3",
        primaryTextColor: "#28241d",
        primaryBorderColor: "#9d4114",
        lineColor: "#c5c0b5",
        secondaryColor: "#fef8ed",
        secondaryTextColor: "#28241d",
        secondaryBorderColor: "#c5c0b5",
        tertiaryColor: "#f4eee3",
        tertiaryTextColor: "#28241d",
        tertiaryBorderColor: "#c5c0b5",
        mainBkg: "#f4eee3",
        nodeBkg: "#f4eee3",
        nodeBorder: "#9d4114",
        clusterBkg: "#fef8ed",
        clusterBorder: "#c5c0b5",
        edgeLabelBackground: "#fef8ed",
        noteBkgColor: "#f4eee3",
        noteTextColor: "#28241d",
        noteBorderColor: "#c5c0b5",
      },
    });
    for (let index = 0; index < 12; index += 1) {
      expect(theme?.variables[`cScale${index}`]).toBe(index % 2 === 0 ? "#f4eee3" : "#fef8ed");
      expect(theme?.variables[`cScaleLabel${index}`]).toBe("#28241d");
      expect(theme?.variables[`cScaleInv${index}`]).toBe("#c5c0b5");
      expect(theme?.variables[`lineColor${index}`]).toBe("#9d4114");
    }
    colors.set("--scholium-color-accent", "url(https://example.invalid/accent)");
    expect(mermaidThemeFromStyle(style)).toBeNull();
  });

  it("publishes one versioned asynchronous mode-neutral contract", async () => {
    expect(scholiumMermaidRuntime.version).toBe(2);
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
