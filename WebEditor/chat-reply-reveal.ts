// Paint-only progressive disclosure. Received text and DOM selection stay intact.
// In particular, this never reparses Markdown or schedules synthetic model tokens.
export const replyRevealDuration = 280;
export const replyRevealHighlight = 'scholium-reply-pending';
const excluded = 'pre, table, button, script, style, .scholium-mermaid, .scholium-math, .katex, .scholium-reply-controls';

export function replyTextNodes(root: Node): Text[] {
  const nodes: Text[] = [];
  const visit = (node: Node) => {
    if (node.nodeType === 3) {
      if (node.textContent?.trim() && !node.parentElement?.closest(excluded)) nodes.push(node as Text);
      return;
    }
    for (const child of node.childNodes) visit(child);
  };
  visit(root);
  return nodes;
}

export function replyRevealBoundaries(previous: string, current: string): number[] {
  // A Markdown reinterpretation or correction is not an appended response.
  if (!current.startsWith(previous) || current.length <= previous.length || current.length > 65_536) return [];
  const segments = new Intl.Segmenter(undefined, {granularity: 'grapheme'});
  const ends = [...segments.segment(current)].map(part => part.index + part.segment.length);
  // An appended combining mark/ZWJ can extend the last visible grapheme.
  // Show that correction immediately instead of masking part of one glyph.
  if (previous.length && !ends.includes(previous.length)) return [];
  return ends.filter(end => end > previous.length);
}

export function installReplyReveal(root: HTMLElement, previousHTML: string | undefined) {
  const owner = root.ownerDocument.defaultView! as Window & typeof globalThis;
  let frame = 0;
  let finished = false;
  const motion = owner.matchMedia('(prefers-reduced-motion: reduce)');
  const contrast = owner.matchMedia('(prefers-contrast: more)');
  const finish = () => {
    finished = true;
    owner.cancelAnimationFrame(frame);
    owner.CSS?.highlights?.delete(replyRevealHighlight);
  };
  const adapted = () => { if (motion.matches || contrast.matches) finish(); };
  const selected = () => {
    const selection = owner.getSelection();
    if (selection && !selection.isCollapsed) finish();
  };
  const hidden = () => { if (root.ownerDocument.hidden) finish(); };
  const destroy = () => {
    finish();
    motion.removeEventListener('change', adapted);
    contrast.removeEventListener('change', adapted);
    root.removeEventListener('pointerdown', finish);
    root.removeEventListener('keydown', finish);
    root.removeEventListener('copy', finish);
    root.ownerDocument.removeEventListener('selectionchange', selected);
    root.ownerDocument.removeEventListener('visibilitychange', hidden);
    owner.removeEventListener('blur', finish);
  };
  if (previousHTML === undefined || motion.matches || contrast.matches || root.ownerDocument.hidden
      || !owner.CSS?.highlights || !owner.Highlight) return {finish, destroy};

  const template = root.ownerDocument.createElement('template');
  // This is the previous native-sanitized projection, kept inert and detached.
  template.innerHTML = previousHTML;
  const previous = replyTextNodes(template.content).map(node => node.data).join('');
  const nodes = replyTextNodes(root);
  const current = nodes.map(node => node.data).join('');
  const boundaries = replyRevealBoundaries(previous, current);
  if (!boundaries.length) return {finish, destroy};

  const paint = (visible: number) => {
    const ranges: Range[] = [];
    let offset = 0;
    for (const node of nodes) {
      const end = offset + node.length;
      if (end > visible) {
        const range = root.ownerDocument.createRange();
        range.setStart(node, Math.max(0, visible - offset));
        range.setEnd(node, node.length);
        ranges.push(range);
      }
      offset = end;
    }
    // Replace the highlight rather than mutating a registered range in place.
    owner.CSS.highlights.set(replyRevealHighlight, new owner.Highlight(...ranges));
  };
  paint(previous.length);
  const started = owner.performance.now();
  const duration = Math.min(replyRevealDuration, Math.max(60, boundaries.length * 16));
  const tick = (now: number) => {
    if (finished) return;
    const count = Math.floor(boundaries.length * Math.min(1, (now - started) / duration));
    if (count >= boundaries.length) { finish(); return; }
    paint(count ? boundaries[count - 1] : previous.length);
    frame = owner.requestAnimationFrame(tick);
  };
  frame = owner.requestAnimationFrame(tick);
  motion.addEventListener('change', adapted);
  contrast.addEventListener('change', adapted);
  root.addEventListener('pointerdown', finish);
  root.addEventListener('keydown', finish);
  root.addEventListener('copy', finish);
  root.ownerDocument.addEventListener('selectionchange', selected);
  root.ownerDocument.addEventListener('visibilitychange', hidden);
  owner.addEventListener('blur', finish);
  return {finish, destroy};
}
