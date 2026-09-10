import {describe, expect, it} from "vitest";
import {cjkPresentationRanges, languageForText} from "../text-language";

describe("presentation-only text language hints", () => {
  it("distinguishes Chinese and mixed Han/Latin prose from English", () => {
    expect(languageForText("中文排版")).toBe("zh-Hans");
    expect(languageForText("中文 English")).toBe("zh-Hans");
    expect(languageForText("English typography")).toBe("en");
  });

  it("does not mislabel kana or Hangul as Simplified Chinese", () => {
    expect(languageForText("日本語かな")).toBeUndefined();
    expect(languageForText("한국어")).toBeUndefined();
  });

  it("does not guess a language for punctuation, emoji, or mathematical symbols", () => {
    expect(languageForText("—— 🧭 ∫²")).toBeUndefined();
  });

  it("returns only the CJK presentation runs for mixed-script styling", () => {
    expect(cjkPresentationRanges("中文 English：楷体")).toEqual([
      {from: 0, to: 2},
      {from: 10, to: 13},
    ]);
  });
});
