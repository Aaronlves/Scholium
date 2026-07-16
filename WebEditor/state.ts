import type {Text} from "@codemirror/state";

export function normalizedDocumentText(text: string) {
  return text.replace(/\r\n/g, "\n");
}

export function replacementChange(currentText: string, requestedText: string) {
  const targetText = normalizedDocumentText(requestedText);
  let prefix = 0;
  const sharedLength = Math.min(currentText.length, targetText.length);
  while (prefix < sharedLength && currentText.charCodeAt(prefix) === targetText.charCodeAt(prefix)) prefix += 1;
  let currentSuffix = currentText.length;
  let targetSuffix = targetText.length;
  while (currentSuffix > prefix && targetSuffix > prefix
      && currentText.charCodeAt(currentSuffix - 1) === targetText.charCodeAt(targetSuffix - 1)) {
    currentSuffix -= 1;
    targetSuffix -= 1;
  }
  return {from: prefix, to: currentSuffix, insert: targetText.slice(prefix, targetSuffix)};
}

export function frontmatterEndLine(doc: Text) {
  if (doc.lines < 2 || doc.line(1).text.trim() !== "---") return 0;
  for (let number = 2; number <= doc.lines; number += 1) {
    if (doc.line(number).text.trim() === "---") return number;
  }
  return 0;
}
