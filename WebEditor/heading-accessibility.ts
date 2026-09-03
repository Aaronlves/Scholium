export function bodyHeadingAccessibilityLevel(markdownLevel: number) {
  return Math.min(6, Math.max(1, markdownLevel) + 1);
}
