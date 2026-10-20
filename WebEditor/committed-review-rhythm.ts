import type {Text} from "@codemirror/state";
import type {ExactSourceMirror} from "./state";

// This adapter only bridges source whitespace between adjacent top-level prose
// and Callouts. Native HTML remains the semantic/reading content authority.
// Registered lengths resolve on main before inheritance: body CSS overrides
// apply, while a receiving Callout's font scale cannot reinterpret lh/em.
// https://www.w3.org/TR/css-properties-values-api-1/#calculation
export const committedReviewRhythmCSS = `
@property --scholium-review-source-row {
  syntax: "<length>";
  inherits: true;
  initial-value: 0px;
}
@property --scholium-review-callout-gap {
  syntax: "<length>";
  inherits: true;
  initial-value: 0px;
}
.scholium-document {
  --scholium-review-source-row: 1lh;
  --scholium-review-callout-gap: var(--scholium-callout-block-gap);
}
.scholium-document > :where([data-scholium-review-gap-before]),
.scholium-document > p:where([data-scholium-review-gap-before]) {
  margin-block-start: var(--scholium-review-callout-gap);
}
.scholium-document > :where([data-scholium-review-gap-after]) { margin-block-end: 0; }
.scholium-document > p:where([data-scholium-review-gap-after]) { padding-block-end: 0; }
.scholium-document > :where([data-scholium-review-gap-before]:not([data-scholium-review-source-gap="0"])),
.scholium-document > p:where([data-scholium-review-gap-before]:not([data-scholium-review-source-gap="0"])) {
  margin-block-start: calc((var(--scholium-review-source-blank-lines) - 1) * var(--scholium-review-source-row) + max(var(--scholium-review-source-row), var(--scholium-review-callout-gap)));
}
`;

export function projectCommittedReviewCalloutRhythm(root: HTMLElement, mirror: ExactSourceMirror, source: Text): void {
  const callout = (element: Element) => element.matches("aside.scholium-callout, details.scholium-callout");
  const supported = (element: Element) => element.tagName.toLowerCase() === "p" || callout(element);
  const nextBlocks = new Set<Element>();
  for (const block of root.querySelectorAll(":scope > aside.scholium-callout, :scope > details.scholium-callout")) {
    if (block.previousElementSibling && supported(block.previousElementSibling)) nextBlocks.add(block);
    if (block.nextElementSibling && supported(block.nextElementSibling)) nextBlocks.add(block.nextElementSibling);
  }
  // Only visit Callout neighbors rather than walking every paragraph of a
  // long document. Geometry changes no nodes, text or native source objects.
  const boundaries = [...nextBlocks].map(current => ({previous: current.previousElementSibling!, current}));
  const range = (element: Element) => {
    const lower = element.getAttribute("data-source-utf16-start"), upper = element.getAttribute("data-source-utf16-end");
    if (lower === null || upper === null || !/^\d+$/.test(lower) || !/^\d+$/.test(upper)) return null;
    const from = mirror.normalizedOffset(Number(lower)), to = mirror.normalizedOffset(Number(upper));
    return from !== null && to !== null && from < to && to <= source.length ? {from, to} : null;
  };
  for (const {previous, current} of boundaries) {
    const before = range(previous), after = range(current);
    if (!before || !after || before.to > after.from
        || !/^[\t \n]*$/.test(source.sliceString(before.to, after.from))) continue;
    const lastLine = source.lineAt(Math.max(before.from, before.to - 1));
    const firstLine = source.lineAt(after.from);
    // Only already-proved source bounds and literal whitespace authorize this
    // geometry. A missing block, nested source or inline boundary stays native.
    if (firstLine.number <= lastLine.number
        || !/^[\t \n]*$/.test(source.sliceString(lastLine.to, firstLine.from))) continue;
    const blankLines = firstLine.number - lastLine.number - 1;
    const block = current as HTMLElement;
    block.dataset.scholiumReviewSourceGap = String(blankLines);
    block.style.setProperty("--scholium-review-source-blank-lines", String(blankLines));
    previous.setAttribute("data-scholium-review-gap-after", "");
    current.setAttribute("data-scholium-review-gap-before", "");
  }
}
