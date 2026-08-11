import {describe, expect, test} from "vitest";
import {
  localizationTesting,
  webInterfaceLocalizationKeys,
} from "../localization";

describe("WebKit interface localization", () => {
  test("declares unique keys and keeps English as the bounded fallback", () => {
    expect(new Set(webInterfaceLocalizationKeys).size).toBe(webInterfaceLocalizationKeys.length);
    expect(localizationTesting.resolve(
      {languageTag: "en", strings: {}},
      "Markdown editor, Edit mode",
    )).toBe("Markdown editor, Edit mode");
  });

  test("resolves Simplified Chinese accessible names and templates without touching document text", () => {
    const strings = {
      "Markdown editor, Edit mode": "Markdown 编辑器，编辑模式",
      "Embedded note {title}": "嵌入笔记“{title}”",
    } as const;
    expect(localizationTesting.resolve(
      {languageTag: "zh-Hans", strings},
      "Markdown editor, Edit mode",
    )).toBe("Markdown 编辑器，编辑模式");
    expect(localizationTesting.resolve(
      {languageTag: "zh-Hans", strings},
      "Embedded note {title}",
      {title: "价值理论.md"},
    )).toBe("嵌入笔记“价值理论.md”");
  });
});
