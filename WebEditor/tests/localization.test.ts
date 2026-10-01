import {afterEach, describe, expect, test} from "vitest";
import {
  createInterfaceLocalizer,
  interfaceLocalizationFromBase64,
  localizationTesting,
  supportedInterfaceLanguage,
  validatedInterfaceLocalization,
  webInterfaceLocalizationKeys,
} from "../localization";
import {calloutDefinition} from "../callout-presentation";
import {parseHTML} from "linkedom";
import {appendMarkdownBlocks} from "../markdown-fragment";
import {editorAccessibilityAttributes} from "../accessibility";

afterEach(() => localizationTesting.reset());

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

  test("canonicalizes shipped language families without inferring a Traditional Chinese translation", () => {
    for (const language of ["zh", "zh-Hans", "zh-Hans-CN", "zh_CN", "zh-SG"]) {
      expect(supportedInterfaceLanguage(language)).toBe("zh-Hans");
    }
    for (const language of ["en", "en-GB", "fr", "zh-Hant", "zh-TW", "zh-Hansfake", "zh-Hans-", "zh--CN"]) {
      expect(supportedInterfaceLanguage(language)).toBe("en");
    }
    expect(validatedInterfaceLocalization({languageTag: "zh-Hant", strings: {"Note title": "筆記標題"}}))
      .toEqual({languageTag: "en", strings: {}});
  });

  test("rejects malformed payload containers and ignores unregistered or invalid translations", () => {
    for (const value of [null, [], {languageTag: "zh-Hans", strings: []}, {strings: {}},
      {languageTag: "zh<script>", strings: {}}, {languageTag: "x".repeat(65), strings: {}}]) {
      expect(validatedInterfaceLocalization(value)).toBeNull();
    }
    const strings = Object.assign(Object.create({Copy: "Inherited"}), {
      "Note title": " ",
      "Markdown editor, Edit mode": "x".repeat(4_097),
      "Embedded note {title}": "嵌入笔记 {missing}",
      "Footnote {ordinal}": "脚注 {ordinal} {ordinal}",
      "unregistered source": "研究者原文",
      "YAML frontmatter": "YAML 文档头",
    });
    expect(validatedInterfaceLocalization({languageTag: "zh-CN", strings})).toEqual({
      languageTag: "zh-Hans", strings: {"YAML frontmatter": "YAML 文档头"},
    });
  });

  test("decodes bounded inert metadata and falls back safely on malformed UTF-8 or JSON", () => {
    const payload = {languageTag: "zh-Hans", strings: {"Note title": "笔记标题"}};
    const encoded = Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
    expect(interfaceLocalizationFromBase64(encoded)).toEqual(payload);
    for (const malformed of ["!not-base64!", Buffer.from("{").toString("base64"),
      Buffer.from([0xc3, 0x28]).toString("base64"), "A".repeat(2_796_205)]) {
      expect(interfaceLocalizationFromBase64(malformed)).toEqual({languageTag: "en", strings: {}});
    }
  });

  test("Edit and independent Review surfaces share template rules while replacements stay literal", () => {
    const chinese = {languageTag: "zh-CN", strings: {
      "Show Link Annotation for {title}": "显示“{title}”的链接注释",
      "Callout: {title}": "语义块：{title}",
    }} as const;
    const title = "来源 {title} <script> $& e\u0301 理由.md";
    const review = createInterfaceLocalizer(chinese);
    const englishReview = createInterfaceLocalizer({languageTag: "en", strings: {}});
    localizationTesting.install(chinese);
    expect(review("Show Link Annotation for {title}", {title})).toBe(`显示“${title}”的链接注释`);
    expect(localizationTesting.resolve(chinese, "Callout: {title}", {title})).toBe(`语义块：${title}`);
    expect(englishReview("Callout: {title}", {title})).toBe(`Callout: ${title}`);
    expect(title).toBe("来源 {title} <script> $& e\u0301 理由.md");
  });

  test("neutral callout labels resolve from the active language at presentation time", () => {
    localizationTesting.install({languageTag: "zh-Hans", strings: {
      Note: "笔记",
      "Preserves an unsupported callout without assigning a research role.": "保留未知语义块，不赋予研究角色。",
    }});
    expect(calloutDefinition(null, "researcher-role")).toEqual({
      identifier: "neutral", label: "笔记", meaning: "保留未知语义块，不赋予研究角色。",
    });
    localizationTesting.install({languageTag: "en", strings: {}});
    expect(calloutDefinition(null, "researcher-role").label).toBe("Note");
  });

  test("localized editor and fragment accessibility chrome retains authored link and table content", () => {
    localizationTesting.install({languageTag: "zh-Hans", strings: {
      "Markdown editor, Edit mode": "Markdown 编辑器，编辑模式",
      "Markdown source editor": "Markdown 源文本编辑器",
      "Show Link Annotation for {title}": "显示“{title}”的链接注释",
      "Markdown table": "Markdown 表格",
    }});
    const {document} = parseHTML("<html><body><div id='root'></div></body></html>");
    const root = document.querySelector<HTMLElement>("#root")!;
    appendMarkdownBlocks("[[Value Theory.md|Reasons 理由]]{{Exact **quotation**.}}\n\n| 原文 | Original |\n| --- | --- |\n| e\u0301 | A |", root);
    expect(editorAccessibilityAttributes("livePreview")["aria-label"]).toBe("Markdown 编辑器，编辑模式");
    expect(editorAccessibilityAttributes("source")["aria-label"]).toBe("Markdown 源文本编辑器");
    expect(root.querySelector("button")?.getAttribute("aria-label")).toBe("显示“Reasons 理由”的链接注释");
    expect(root.querySelector(".cm-live-wiki-link")?.textContent).toBe("Reasons 理由");
    expect(root.querySelector<HTMLTemplateElement>("template")?.content
      .querySelector(".scholium-link-annotation-content")?.textContent).toBe("Exact quotation.");
    expect(root.querySelector("table")?.getAttribute("aria-label")).toBe("Markdown 表格");
    expect([...root.querySelectorAll("th")].map(cell => cell.textContent)).toEqual(["原文", "Original"]);
    expect(root.querySelector("td")?.textContent).toBe("e\u0301");
  });
});
