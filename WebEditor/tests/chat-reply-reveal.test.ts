import {describe, expect, it, vi} from 'vitest';
import {parseHTML} from 'linkedom';
import {installReplyReveal, replyRevealBoundaries, replyRevealDuration, replyRevealHighlight, replyTextNodes} from '../chat-reply-reveal';

function fixture(previous = '<p>已有文字</p>\n', reduced = false) {
  const {document, window} = parseHTML('<html><body><article><p>已有文字，新回复 👩‍💻。</p>\n<pre>code()</pre><table><tr><td>Table</td></tr></table></article></body></html>');
  const root = document.querySelector('article')! as unknown as HTMLElement;
  let callback: FrameRequestCallback | undefined;
  const highlights = new Map<string, unknown>();
  const queries: {matches: boolean; addEventListener: ReturnType<typeof vi.fn>; removeEventListener: ReturnType<typeof vi.fn>}[] = [];
  Object.assign(window, {
    CSS: {highlights}, Highlight: class extends Set { constructor(...ranges: unknown[]) { super(ranges); } },
    performance: {now: () => 0},
    requestAnimationFrame: (value: FrameRequestCallback) => { callback = value; return 1; },
    cancelAnimationFrame: () => { callback = undefined; },
    matchMedia: () => {
      const value = {matches: reduced, addEventListener: vi.fn(), removeEventListener: vi.fn()};
      queries.push(value); return value;
    },
    getSelection: () => ({isCollapsed: true}),
  });
  document.createRange = (() => ({setStart: vi.fn(), setEnd: vi.fn()})) as unknown as typeof document.createRange;
  const html = root.innerHTML;
  const node = root.firstChild;
  const reveal = installReplyReveal(root, previous);
  return {root, window, highlights, queries, reveal, html, node, tick: (time: number) => callback?.(time)};
}

describe('Chat progressive text reveal', () => {
  it('only reveals appended prose at complete Unicode grapheme boundaries', () => {
    expect(replyRevealBoundaries('旧', '旧👩‍💻e\u0301中')).toEqual([6, 8, 9]);
    expect(replyRevealBoundaries('e', 'e\u0301')).toEqual([]);
    expect(replyRevealBoundaries('👩', '👩‍💻')).toEqual([]);
    expect(replyRevealBoundaries('old', 'corrected')).toEqual([]);
    expect(replyRevealBoundaries('same', 'same')).toEqual([]);
    expect(replyRevealBoundaries('', 'x'.repeat(65_537))).toEqual([]);
  });

  it('leaves existing nodes, source text, code and tables intact while only painting pending prose', () => {
    const f = fixture();
    expect(replyTextNodes(f.root).map(node => node.data).join('')).toBe('已有文字，新回复 👩‍💻。');
    expect(f.highlights.has(replyRevealHighlight)).toBe(true);
    f.tick(80);
    expect(f.highlights.has(replyRevealHighlight)).toBe(true);
    expect(f.root.innerHTML).toBe(f.html);
    expect(f.root.firstChild).toBe(f.node);
    f.tick(replyRevealDuration);
    expect(f.highlights.size).toBe(0);
    expect(f.root.innerHTML).toBe(f.html);
    f.reveal.destroy();
  });

  it('shows everything on interaction, policy change, stop or teardown without a later frame hiding it', () => {
    for (const event of ['pointerdown', 'keydown', 'copy']) {
      const f = fixture();
      f.root.dispatchEvent(new f.window.Event(event));
      f.tick(20);
      expect(f.highlights.size).toBe(0);
      f.reveal.destroy();
    }
    const f = fixture();
    f.queries[0].matches = true;
    f.queries[0].addEventListener.mock.calls[0][1]();
    expect(f.highlights.size).toBe(0);
    f.reveal.destroy();
    expect(f.queries[0].removeEventListener).toHaveBeenCalled();
  });

  it('never delays reduced-motion content, identical snapshots or corrections', () => {
    for (const f of [fixture('<p>已有文字</p>', true), fixture('<p>different</p>')]) {
      expect(f.highlights.size).toBe(0);
      expect(f.root.innerHTML).toBe(f.html);
      f.reveal.destroy();
    }
  });
});
