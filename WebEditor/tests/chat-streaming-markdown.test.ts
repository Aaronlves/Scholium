import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {describe, expect, it} from "vitest";
import {completeStreamingMarkdown} from "../chat-streaming-markdown";

describe("display-only streaming Markdown completion", () => {
  it("uses the exact reviewed dependency without a second renderer", () => {
    const metadata = JSON.parse(readFileSync(fileURLToPath(
      new URL("../node_modules/remend/package.json", import.meta.url)), "utf8"));
    expect(metadata.version).toBe("1.4.0");
    expect(metadata.license).toBe("Apache-2.0");
    expect(metadata.dependencies ?? {}).toEqual({});
  });

  it.each([
    ["A **stable phrase", "A **stable phrase**"],
    ["A **stable phrase*", "A **stable phrase**"],
    ["A *stable phrase", "A *stable phrase*"],
    ["A _stable phrase", "A _stable phrase_"],
    ["A ***stable phrase", "A ***stable phrase***"],
    ["A ~~stable phrase", "A ~~stable phrase~~"],
    ["Use `source", "Use `source`"],
    ["Use ``a ` marker", "Use ``a ` marker``"],
    ["[Source", "[Source](streamdown:incomplete-link)"],
    ["[Source](https://exam", "[Source](streamdown:incomplete-link)"],
    ["[Source](https://example.org \"Ti", "[Source](streamdown:incomplete-link)"],
  ])("presents incomplete syntax without exposing closing-token churn: %s", (source, expected) => {
    expect(completeStreamingMarkdown(source)).toBe(expected);
    expect(completeStreamingMarkdown(source)).toBe(expected);
  });

  it.each([
    "Plain 中文😀e\u0301 prose.",
    "A **complete** and *emphasized* phrase.",
    "[Source](https://example.org/path_(one))",
    "\\*literal star and snake_case",
    "`**literal** [label](partial`",
    "```text\r\n**raw _markers_ [label](pending\r\n```",
    "~~~text\n**raw _markers_ [label](pending",
    "Cost $25 and $50",
    "$$\nx_i = y_j ** k\n",
    "Possible $25 **literal",
    "\\(x_i ** k",
    "\\[x_i ** k",
    "20~25°C",
    "- > 25",
    "<private-tag",
    "'); throw new Error('source-is-data'); //",
  ])("preserves literal content and independently owned dialects: %s", source => {
    expect(completeStreamingMarkdown(source)).toBe(source);
  });

  it("is independent of snapshot ordering and uses only the source argument", () => {
    const partial = "A **中文😀e\u0301 phrase";
    expect(completeStreamingMarkdown(partial)).toBe(partial + "**");
    expect(completeStreamingMarkdown("Unrelated final text.")).toBe("Unrelated final text.");
    expect(completeStreamingMarkdown(partial)).toBe(partial + "**");
    expect(completeStreamingMarkdown("")).toBe("");
    expect(Object.getOwnPropertyDescriptor(globalThis, "scholiumCompleteStreamingMarkdown")?.value)
      .toBe(completeStreamingMarkdown);
  });

  it.each([
    ["\uFEFF**Cafe\u0301 中文😀\r\n", "\uFEFF**Cafe\u0301 中文😀**\r\n"],
    ["**phrase ", "**phrase** "],
    ["**phrase  ", "**phrase**  "],
    ["**phrase\t\r\n", "**phrase**\t\r\n"],
    ["**phrase\u00a0", "**phrase**\u00a0"],
    ["*phrase\n", "*phrase*\n"],
    ["__phrase\r", "__phrase__\r"],
    ["~~phrase\r\n", "~~phrase~~\r\n"],
    ["[Source](https://exam\r\n", "[Source](streamdown:incomplete-link)\r\n"],
    ["Use `source ", "Use `source `"],
    ["Use ``a ` marker \t", "Use ``a ` marker \t``"],
    ["Use `source\r\n", "Use `source\r\n`"],
    ["Use `source\n\n", "Use `source\n\n"],
  ])("keeps received whitespace at the native CommonMark boundary: %s", (source, expected) => {
    expect(completeStreamingMarkdown(source)).toBe(expected);
  });

  it.each([
    "Plain text ", "Plain text  \r\n", "\t \r\n", "\uFEFF",
    "`already closed ` \r\n",
    "```text\r\n**raw _markers_ [label](pending \t\r\n",
    "```text\r\n**raw _markers_ [label](pending\r\n``` \r\n",
    "~~~text\n**raw literal \t\r\n",
    "$$\nx_i ** y_j \t\r\n", "\\(x_i ** y_j \t\r\n",
  ])("preserves trailing whitespace on unchanged or literal content: %s", source => {
    expect(completeStreamingMarkdown(source)).toBe(source);
  });
});
