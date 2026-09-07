/** Presentation only: one brief arrival marker per rendered Document. */
export const arrivalDuration = 1400;
export const arrivalClass = "scholium-arrival-target";

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
  return {reveal, clear, destroy};
}
