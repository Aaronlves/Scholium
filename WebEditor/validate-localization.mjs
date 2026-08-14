import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const editorRoot = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.dirname(editorRoot);
const localizationSourcePath = path.join(editorRoot, "localization.ts");
const catalogPath = path.join(
  repositoryRoot,
  "Scholium",
  "Resources",
  "WebKitInterface.xcstrings",
);
const reviewSourcePath = path.join(
  repositoryRoot,
  "Scholium",
  "Views",
  "Note",
  "SafeMarkdownReadWebView.swift",
);

const source = fs.readFileSync(localizationSourcePath, "utf8");
const keyBlock = source.match(/webInterfaceLocalizationKeys = \[([\s\S]*?)\] as const/);
if (!keyBlock) throw new Error("Web interface localization key registry is missing.");
const keys = [...keyBlock[1].matchAll(/^\s*("(?:[^"\\]|\\.)*"),?$/gm)]
  .map((match) => JSON.parse(match[1]));
if (new Set(keys).size !== keys.length) {
  throw new Error("Web interface localization keys are not unique.");
}

const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
const catalogKeys = Object.keys(catalog.strings);
const missing = keys.filter((key) => !catalogKeys.includes(key));
const extra = catalogKeys.filter((key) => !keys.includes(key));
if (missing.length || extra.length) {
  throw new Error(`WebKitInterface.xcstrings key mismatch. Missing: ${missing.join(", ")} Extra: ${extra.join(", ")}`);
}

const placeholderNames = (value) => [...value.matchAll(/\{([A-Za-z]+)\}/g)]
  .map((match) => match[1])
  .sort();
for (const key of keys) {
  const entry = catalog.strings[key];
  const english = entry?.localizations?.en?.stringUnit?.value;
  const chinese = entry?.localizations?.["zh-Hans"]?.stringUnit;
  if (english !== key || chinese?.state !== "translated" || typeof chinese.value !== "string") {
    throw new Error(`Web interface localization is incomplete for: ${key}`);
  }
  if (placeholderNames(english).join("\0") !== placeholderNames(chinese.value).join("\0")) {
    throw new Error(`Web interface localization changed template placeholders for: ${key}`);
  }
}

const directUISinkPatterns = [
  /setAttribute\(\s*["']aria-label["']\s*,\s*["'`]\s*[A-Z]/g,
  /\.textContent\s*=\s*["'`]\s*[A-Z]/g,
  /(?:createToolbarButton|addMenuItem|addSubmenuItem)\(\s*["'`]\s*[A-Z]/g,
  /\b(?:label|meaning)\s*:\s*["'`]\s*[A-Z]/g,
  /announceEditorMessage\([\s\S]{0,160}?,\s*["'`]\s*[A-Z]/g,
];
const editorUISources = [
  "accessibility.ts",
  "editor.ts",
  "input-suggestions.ts",
  "markdown-fragment.ts",
  "preview-popover.ts",
  "selection-actions.ts",
];
for (const relativePath of editorUISources) {
  const text = fs.readFileSync(path.join(editorRoot, relativePath), "utf8");
  for (const pattern of directUISinkPatterns) {
    pattern.lastIndex = 0;
    if (pattern.test(text)) {
      throw new Error(`${relativePath} contains app-authored English in a user-facing sink.`);
    }
  }
}

const reviewSource = fs.readFileSync(reviewSourcePath, "utf8");
const directReviewPatterns = [
  /setAttribute\(\s*'aria-label'\s*,\s*'\s*[A-Z]/g,
  /\.textContent\s*=\s*'\s*[A-Z]/g,
  /mermaidDiagnostic\([\s\S]{0,160}?,\s*'\s*[A-Z]/g,
  /defaultCommentHelpText\s*=\s*'\s*[A-Z]/g,
];
for (const pattern of directReviewPatterns) {
  if (pattern.test(reviewSource)) {
    throw new Error("SafeMarkdownReadWebView contains app-authored English in a Review user-facing sink.");
  }
}

console.log(`WebKit interface localization validation passed (${keys.length} keys).`);
