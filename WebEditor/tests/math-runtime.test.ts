import {describe, expect, it} from "vitest";
import {renderMath, scholiumMathRuntime} from "../math-runtime";

describe("shared mathematics runtime", () => {
  it("renders accessible inline and display mathematics", () => {
    const inline = renderMath({source: "x^2 + y^2", kind: "inline"});
    const display = renderMath({source: String.raw`\\int_0^1 x\\,dx`, kind: "display"});

    expect(inline.ok).toBe(true);
    expect(display.ok).toBe(true);
    if (inline.ok && display.ok) {
      expect(inline.html).toContain("katex-mathml");
      expect(inline.html).toContain("katex-html");
      expect(display.html).toContain("katex-display");
    }
  });

  it("fails closed for malformed or oversized requests", () => {
    expect(renderMath({source: String.raw`\\notacommand{`, kind: "inline"})).toEqual({
      ok: false,
      reason: "unsupported-mathematics",
    });
    expect(renderMath({source: "x".repeat(16_385), kind: "display"})).toEqual({
      ok: false,
      reason: "invalid-source",
    });
  });

  it("publishes one versioned mode-neutral contract", () => {
    expect(scholiumMathRuntime.version).toBe(1);
    expect(scholiumMathRuntime.render({source: "x", kind: "inline"}).ok).toBe(true);
  });
});
