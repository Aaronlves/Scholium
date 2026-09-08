/** Presentation only: one brief arrival marker per rendered Document. */
export const arrivalDuration = 1400;
export const arrivalClass = "scholium-arrival-target";

function sourceRangeElement(root: HTMLElement, lower: number, upper: number): HTMLElement | undefined {
  if (!Number.isSafeInteger(lower) || !Number.isSafeInteger(upper) || lower < 0 || upper <= lower || upper - lower > 32000) return;
  return [...root.querySelectorAll<HTMLElement>('[data-source-utf16-start][data-source-utf16-end]')]
    .filter(element => Number(element.dataset.sourceUtf16Start) <= lower
      && Number(element.dataset.sourceUtf16End) >= upper
      && (element.textContent?.length ?? 0) <= 64000)
    .sort((a, b) => (Number(a.dataset.sourceUtf16End) - Number(a.dataset.sourceUtf16Start))
      - (Number(b.dataset.sourceUtf16End) - Number(b.dataset.sourceUtf16Start)))[0];
}

export function readerSourceRangeCandidate(root: HTMLElement, lower: number, upper: number) {
  const element = sourceRangeElement(root, lower, upper);
  return element ? {blockLower: Number(element.dataset.sourceUtf16Start),
    blockUpper: Number(element.dataset.sourceUtf16End), blockText: element.textContent ?? ''} : null;
}

export function createReaderArrival(root: HTMLElement) {
  let marker: HTMLElement | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const owner = root.ownerDocument.defaultView;
  function clear() {
    clearTimeout(timer);
    timer = undefined;
    marker?.remove();
    marker = null;
  }
  const span = (element: HTMLElement) => Number(element.dataset.sourceUtf16End ?? 0)
    - Number(element.dataset.sourceUtf16Start ?? 0);
  function reveal(line: number): boolean {
    clear();
    if (!Number.isSafeInteger(line) || line < 1 || !owner) return false;
    // Inline source locators identify the visual line within a wrapped block.
    // Prefer an exact start and the narrowest source span, not a large ancestor.
    const candidates = [...root.querySelectorAll<HTMLElement>('[data-source-line]')]
      .filter(element => Number(element.dataset.sourceLine) <= line
        && Number(element.dataset.sourceEndLine ?? element.dataset.sourceLine) >= line)
      .sort((a, b) => Number(Number(b.dataset.sourceLine) === line) - Number(Number(a.dataset.sourceLine) === line)
        || span(a) - span(b));
    const target = candidates[0];
    if (!target) return false;
    target.scrollIntoView({block: "start", behavior: "auto"});
    const range = root.ownerDocument.createRange();
    range.selectNodeContents(target);
    const rect = [...range.getClientRects()].find(rect => rect.width > 0 && rect.height > 0);
    if (!rect) return false;
    const block = target.closest<HTMLElement>('p, li, pre, td, th, h1, h2, h3, h4, h5, h6') ?? target;
    const bounds = block.getBoundingClientRect();
    const height = Math.max(rect.height, parseFloat(owner.getComputedStyle(block).lineHeight) || 0);
    marker = root.ownerDocument.createElement('div');
    marker.className = arrivalClass + ' scholium-reader-arrival';
    marker.setAttribute('aria-hidden', 'true');
    marker.dataset.arrivalLine = String(line);
    Object.assign(marker.style, {
      position: 'absolute', pointerEvents: 'none',
      left: `${bounds.left + owner.scrollX}px`, top: `${rect.top + owner.scrollY - (height - rect.height) / 2}px`,
      width: `${bounds.width}px`, height: `${height}px`,
    });
    root.ownerDocument.body.appendChild(marker);
    timer = setTimeout(clear, arrivalDuration);
    return true;
  }
  owner?.addEventListener('resize', clear);
  function destroy() { clear(); owner?.removeEventListener('resize', clear); }
  function revealRange(lower: number, upper: number, expected: NonNullable<ReturnType<typeof readerSourceRangeCandidate>>) {
    const target = sourceRangeElement(root, lower, upper);
    const candidate = readerSourceRangeCandidate(root, lower, upper);
    if (!owner || !target || !candidate || candidate.blockLower !== expected.blockLower
      || candidate.blockUpper !== expected.blockUpper || candidate.blockText !== expected.blockText) return false;
    const from = lower - candidate.blockLower, to = upper - candidate.blockLower;
    if (from < 0 || to > candidate.blockText.length) return false;
    const walker = root.ownerDocument.createTreeWalker(target, 4 /* SHOW_TEXT */);
    let offset = 0, start: [Node, number] | undefined, end: [Node, number] | undefined;
    while (walker.nextNode()) {
      const node = walker.currentNode, length = node.textContent?.length ?? 0;
      if (!start && from >= offset && from <= offset + length) start = [node, from - offset];
      if (!end && to >= offset && to <= offset + length) end = [node, to - offset];
      offset += length;
    }
    if (!start || !end) return false;
    const range = root.ownerDocument.createRange();
    range.setStart(...start); range.setEnd(...end);
    if (range.toString() !== candidate.blockText.slice(from, to)) return false;
    const selection = owner.getSelection();
    if (!selection) return false;
    clear(); selection.removeAllRanges(); selection.addRange(range);
    const rect = range.getBoundingClientRect();
    owner.scrollBy({top: rect.top - owner.innerHeight / 3, behavior: 'auto'});
    return true;
  }
  return {reveal, rangeCandidate: (lower: number, upper: number) => readerSourceRangeCandidate(root, lower, upper), revealRange, clear, destroy};
}
