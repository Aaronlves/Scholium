import {describe, expect, it, vi} from 'vitest';
import {parseHTML} from 'linkedom';
import {beginDocumentPreparation} from '../document-preparation';

function rect(left: number, top: number, width: number, height: number): DOMRect {
  return {left, top, width, height, right: left + width, bottom: top + height} as DOMRect;
}

function fixture() {
  const {document, window} = parseHTML('<html><body><main><p>中文 😀 exact body</p><img src="data:image/png;base64,AA=="></main></body></html>');
  const root = document.querySelector('main')! as unknown as HTMLElement;
  const paragraph = root.querySelector('p')!;
  const image = root.querySelector('img')!;
  const mediaListeners = new Set<() => void>();
  const media = {
    matches: false,
    addEventListener: (_name: string, listener: () => void) => mediaListeners.add(listener),
    removeEventListener: (_name: string, listener: () => void) => mediaListeners.delete(listener),
  };
  const selection = vi.fn();
  const scroll = vi.fn();
  Object.assign(window, {innerWidth: 400, innerHeight: 240,
    matchMedia: () => media, getSelection: selection, scrollTo: scroll});
  const textRects = [rect(-10, -4, 150, 20), rect(28, 40, 180, 18), rect(20, 500, 300, 18)];
  paragraph.getBoundingClientRect = () => rect(0, 0, 350, 520);
  document.createRange = (() => ({selectNodeContents: () => {}, getClientRects: () => textRects})) as unknown as typeof document.createRange;
  image.getBoundingClientRect = () => rect(300, 200, 180, 90);
  const hitTest = vi.fn(() => { throw new Error('Inert content cannot be discovered by hit-testing.'); });
  document.elementsFromPoint = hitTest as unknown as typeof document.elementsFromPoint;
  return {root, window, media, mediaListeners, textRects, hitTest, selection, scroll};
}

describe('document preparation paint', () => {
  it('masks measured text and objects within the real viewport without changing source or selection', () => {
    const {root, selection, scroll} = fixture();
    const original = root.innerHTML;
    const preparation = beginDocumentPreparation(root);
    const mask = root.ownerDocument.querySelector<HTMLElement>('.scholium-document-preparation')!;
    const shapes = mask.querySelectorAll<HTMLElement>('.scholium-document-preparation-shape');
    expect(shapes.length).toBe(3);
    expect([shapes[0].style.left, shapes[0].style.top, shapes[0].style.width, shapes[0].style.height])
      .toEqual(['0px', '0px', '140px', '16px']);
    expect([shapes[2].style.left, shapes[2].style.top, shapes[2].style.width, shapes[2].style.height])
      .toEqual(['300px', '200px', '100px', '40px']);
    expect(mask.getAttribute('aria-hidden')).toBe('true');
    expect(mask.textContent).toBe('');
    expect(root.innerHTML).toBe(original);
    expect(selection).not.toHaveBeenCalled();
    expect(scroll).not.toHaveBeenCalled();
    preparation.finish();
    expect(root.innerHTML).toBe(original);
  });

  it('refreshes from changed real geometry and makes Reduce Motion immediately static', () => {
    const {root, textRects, media, mediaListeners} = fixture();
    const preparation = beginDocumentPreparation(root);
    const mask = root.ownerDocument.querySelector('.scholium-document-preparation')!;
    expect(mask.classList.contains('scholium-document-preparation-static')).toBe(false);
    media.matches = true;
    for (const listener of mediaListeners) listener();
    expect(mask.classList.contains('scholium-document-preparation-static')).toBe(true);
    textRects[0] = rect(37, 12, 90, 25);
    preparation.refresh();
    expect(mask.querySelector<HTMLElement>('.scholium-document-preparation-shape')!.style.left).toBe('37px');
    preparation.finish();
    expect(mediaListeners.size).toBe(0);
  });

  it('replaces an old preparation once and restores the original accessibility state', () => {
    const {root, window, hitTest} = fixture();
    root.setAttribute('aria-hidden', 'false');
    const old = beginDocumentPreparation(root);
    const current = beginDocumentPreparation(root);
    old.finish();
    expect(root.ownerDocument.querySelectorAll('.scholium-document-preparation').length).toBe(1);
    expect(root.getAttribute('aria-hidden')).toBe('true');
    current.finish();
    current.finish();
    expect(root.getAttribute('aria-hidden')).toBe('false');
    const calls = hitTest.mock.calls.length;
    window.dispatchEvent(new window.Event('scroll'));
    expect(hitTest.mock.calls.length).toBe(calls);
    expect(root.ownerDocument.querySelector('.scholium-document-preparation')).toBeNull();
  });

  it('bounds paint for a dense visible document without adding source nodes', () => {
    const {root, textRects} = fixture();
    textRects.splice(0, textRects.length, ...Array.from({length: 1000}, (_, index) =>
      rect(20 + index % 4, index / 5, 80, 12)));
    const source = root.innerHTML;
    const preparation = beginDocumentPreparation(root);
    expect(root.ownerDocument.querySelectorAll('.scholium-document-preparation-shape').length).toBe(384);
    expect(root.innerHTML).toBe(source);
    preparation.finish();
  });
});
