const frontmatterTokenClassByNodeName: Readonly<Record<string, string>> = {
  Key: "cm-live-yaml-key",
  QuotedLiteral: "cm-live-yaml-string",
  BlockLiteralHeader: "cm-live-yaml-scalar",
  BlockLiteralContent: "cm-live-yaml-scalar",
  FlowSequence: "cm-live-yaml-collection",
  FlowMapping: "cm-live-yaml-collection",
  Comment: "cm-live-yaml-comment",
};

/** Returns the shared CSS role for one YAML syntax node. */
export function frontmatterTokenClass(nodeName: string, parentName?: string): string | undefined {
  if (nodeName === "Literal" && parentName !== "Key") return "cm-live-yaml-value";
  return frontmatterTokenClassByNodeName[nodeName];
}

/**
 * Lezer accepts a bare YAML key with an implicit null value. Review's bounded
 * lexical projection treats that line as an ordinary value, so Edit only
 * presents a Key node when the authored separator is actually present.
 */
export function frontmatterKeyHasSeparator(followingText: string): boolean {
  if (followingText[0] !== ":") return false;
  const next = followingText[1];
  return next === undefined || next === " " || next === "\t" || next === "\r" || next === "\n";
}

/** Supplies Review's value role for an otherwise unclassified nonempty line. */
export function frontmatterFallbackClass(
  lineText: string,
  isDelimiterLine: boolean,
  hasTokenClass: boolean,
): string | undefined {
  const trimmed = lineText.trim();
  if (isDelimiterLine || hasTokenClass || trimmed === "" || trimmed.startsWith("#")) return undefined;
  return "cm-live-yaml-value";
}
