import {describe, expect, it} from "vitest";
import {scanMath} from "../math";

const dialect = {
  inlineDelimiter: "$",
  displayDelimiter: "$$",
  singleDollarInline: true,
};

describe("math projection", () => {
  it("locates inline, multi-dollar inline, and display expressions", () => {
    const source = "Inline $x + 范围$ and $$C_L$$.\r\n\r\n$$\r\n\\int_0^1 x^2 \\, dx\r\n$$\r\n";
    expect(scanMath(source, dialect).map(({kind, content, delimiterLength}) => ({kind, content, delimiterLength}))).toEqual([
      {kind: "inline", content: "x + 范围", delimiterLength: 1},
      {kind: "inline", content: "C_L", delimiterLength: 2},
      {kind: "display", content: "\\int_0^1 x^2 \\, dx", delimiterLength: 2},
    ]);
  });

  it("does not project YAML, code, comments, or escaped dollars", () => {
    const source = "---\ntitle: $YAML$\n---\n\\$literal$ `code $ignored$`\n```md\n$fenced$\n```\n%% $comment$ %%\n<!-- $html$ -->\n\n<div>\n$raw$\n</div>";
    expect(scanMath(source, dialect)).toEqual([]);
  });

  it("requires an equal greedy closing run while allowing shorter runs inside", () => {
    expect(scanMath("$$x$ and $y$$", dialect).map(({content, delimiterLength}) => ({content, delimiterLength}))).toEqual([
      {content: "x$ and $y", delimiterLength: 2},
    ]);
    expect(scanMath("$x$$", dialect)).toEqual([]);
    expect(scanMath("$$x$", dialect)).toEqual([]);
  });
});
