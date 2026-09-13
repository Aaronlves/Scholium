import {afterEach, describe, expect, it, vi} from "vitest";
import {parseHTML} from "linkedom";
import {EditorState} from "@codemirror/state";
import {arrivalClass, arrivalDuration, createReaderArrival} from "../arrival-highlight";
import {editorArrivalState, showEditorArrival} from "../editor-arrival-highlight";

function fixture() {
  const {document, window} = parseHTML('<html><body><article><p data-source-line="2" data-source-end-line="4">中文 😀 passage</p><p data-source-line="7" data-source-end-line="7">Second passage</p></article></body></html>');
  const root = document.querySelector('article')! as unknown as HTMLElement;
  const rect = {left: 20, top: 100, width: 300, height: 18};
  for (const element of root.querySelectorAll<HTMLElement>('p')) {
    element.scrollIntoView = vi.fn(() => { Object.assign(window, {scrollY: 100}); });
    element.getBoundingClientRect = () => ({...rect, top: rect.top - window.scrollY, height: 160} as DOMRect);
  }
  Object.assign(window, {scrollX: 0, scrollY: 0, innerHeight: 600, getComputedStyle: () => ({lineHeight: '24px'})});
  Object.defineProperty(document.documentElement, "scrollHeight", {value: 1000});
  document.createRange = (() => ({selectNodeContents: () => {}, getClientRects: () => [rect]})) as unknown as typeof document.createRange;
  return {root, navigation: createReaderArrival(root)};
}
afterEach(() => vi.useRealTimers());

describe("arrival feedback", () => {
  it("highlights a containing paragraph, expires, and changes no content", async () => {
    vi.useFakeTimers();
    const {root, navigation} = fixture();
    const original = root.textContent;
    expect(await navigation.reveal(3)).toBe(true);
    expect(root.querySelector<HTMLElement>("[data-source-line=\"2\"]")?.scrollIntoView)
      .toHaveBeenCalledWith({block: "start", behavior: "smooth"});
    expect(root.ownerDocument.querySelector<HTMLElement>('.' + arrivalClass)?.style.height).toBe('24px');
    vi.advanceTimersByTime(arrivalDuration);
    expect(root.ownerDocument.querySelector('.' + arrivalClass)).toBeNull();
    expect(root.textContent).toBe(original);
  });
  it("bounds distant navigation to one viewport without changing its destination", async () => {
    const {root, navigation} = fixture();
    const owner = root.ownerDocument.defaultView!;
    const scrollTo = vi.fn(({top}: ScrollToOptions) => Object.assign(owner, {scrollY: top}));
    Object.assign(owner, {innerHeight: 40, scrollTo});
    const original = root.textContent;
    expect(await navigation.reveal(2)).toBe(true);
    expect(scrollTo).toHaveBeenCalledWith({top: 60, behavior: "auto"});
    expect(owner.scrollY).toBe(100);
    expect(root.textContent).toBe(original);
    navigation.destroy();
  });

  it("reduced motion goes straight to a distant destination", async () => {
    const {root, navigation} = fixture();
    const owner = root.ownerDocument.defaultView!;
    const scrollTo = vi.fn();
    Object.assign(owner, {innerHeight: 40, scrollTo, matchMedia: () => ({matches: true})});
    expect(await navigation.reveal(2)).toBe(true);
    expect(scrollTo).not.toHaveBeenCalled();
    expect(root.querySelector<HTMLElement>("p")?.scrollIntoView)
      .toHaveBeenCalledWith({block: "start", behavior: "auto"});
    navigation.destroy();
  });

  it("repeated activation renews one marker and another target replaces it", async () => {
    vi.useFakeTimers();
    const {root, navigation} = fixture();
    await navigation.reveal(2);
    vi.advanceTimersByTime(arrivalDuration - 10);
    await navigation.reveal(2);
    vi.advanceTimersByTime(20);
    expect(root.ownerDocument.querySelectorAll('.' + arrivalClass).length).toBe(1);
    await navigation.reveal(7);
    expect(root.ownerDocument.querySelectorAll('.' + arrivalClass).length).toBe(1);
    expect(root.ownerDocument.querySelector<HTMLElement>('.' + arrivalClass)?.dataset.arrivalLine).toBe('7');
    navigation.clear();
    expect(vi.getTimerCount()).toBe(0);
  });
  it("an unresolved line never highlights the preceding or first paragraph", async () => {
    const {root, navigation} = fixture();
    for (const line of [0, 1, 5, 99, NaN, 2.5]) expect(await navigation.reveal(line)).toBe(false);
    expect(root.ownerDocument.querySelector('.' + arrivalClass)).toBeNull();
  });
  it("confirms smooth arrival only at its destination and cancels superseded navigation", async () => {
    vi.useFakeTimers();
    const {root, navigation} = fixture();
    for (const element of root.querySelectorAll<HTMLElement>('p')) element.scrollIntoView = vi.fn();
    const first = navigation.reveal(2);
    const second = navigation.reveal(7);
    let completed = false;
    void second.then(() => { completed = true; });
    await vi.advanceTimersByTimeAsync(32);
    expect(completed).toBe(false);
    expect(await first).toBe(false);
    expect(root.ownerDocument.querySelector('.' + arrivalClass)).toBeNull();
    Object.assign(root.ownerDocument.defaultView!, {scrollY: 100});
    await vi.advanceTimersByTimeAsync(16);
    expect(await second).toBe(true);
    expect(root.ownerDocument.querySelector<HTMLElement>('.' + arrivalClass)?.dataset.arrivalLine).toBe('7');
    navigation.destroy();
    expect(vi.getTimerCount()).toBe(0);
  });
  it("retains immediate reduced-motion navigation and accepts a bottom-clamped destination", async () => {
    vi.useFakeTimers();
    const {root, navigation} = fixture();
    const owner = root.ownerDocument.defaultView!;
    Object.assign(owner, {matchMedia: () => ({matches: true})});
    expect(await navigation.reveal(2)).toBe(true);
    const target = root.querySelector<HTMLElement>('[data-source-line="7"]')!;
    target.getBoundingClientRect = () => ({top: 900 - owner.scrollY, left: 20, width: 300, height: 160} as DOMRect);
    target.scrollIntoView = vi.fn(() => { Object.assign(owner, {scrollY: 400}); });
    expect(await navigation.reveal(7)).toBe(true);
    expect(target.scrollIntoView).toHaveBeenCalledWith({block: "start", behavior: "auto"});
    navigation.destroy();
    expect(vi.getTimerCount()).toBe(0);
  });
  it("does not report a stalled or destroyed scroll as reached", async () => {
    vi.useFakeTimers();
    const {root, navigation} = fixture();
    for (const element of root.querySelectorAll<HTMLElement>('p')) element.scrollIntoView = vi.fn();
    const stalled = navigation.reveal(2);
    await vi.advanceTimersByTimeAsync(2016);
    expect(await stalled).toBe(false);
    const departed = navigation.reveal(7);
    navigation.destroy();
    await vi.advanceTimersByTimeAsync(16);
    expect(await departed).toBe(false);
    expect(root.ownerDocument.querySelector('.' + arrivalClass)).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });
  it("editor feedback preserves exact text and selection and clears on a source change", () => {
    const source = '\uFEFF中文 😀\r\nSecond passage';
    let state = EditorState.create({doc: source, selection: {anchor: 2, head: 4}, extensions: [editorArrivalState, EditorState.lineSeparator.of('\r\n')]});
    state = state.update({effects: showEditorArrival.of(state.doc.line(2).from)}).state;
    expect(state.field(editorArrivalState).size).toBe(1);
    expect(state.selection.main.from).toBe(2);
    expect(state.selection.main.to).toBe(4);
    expect(state.sliceDoc()).toBe(source);
    state = state.update({changes: {from: 0, insert: 'x'}}).state;
    expect(state.field(editorArrivalState).size).toBe(0);
  });
  it("editor feedback explicitly clears without moving the caret", () => {
    let state = EditorState.create({doc: 'First\nSecond', selection: {anchor: 3}, extensions: [editorArrivalState]});
    state = state.update({effects: showEditorArrival.of(6)}).state;
    state = state.update({effects: showEditorArrival.of(null)}).state;
    expect(state.field(editorArrivalState).size).toBe(0);
    expect(state.selection.main.head).toBe(3);
  });
});
