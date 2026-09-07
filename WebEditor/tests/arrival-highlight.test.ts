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
    element.scrollIntoView = vi.fn();
    element.getBoundingClientRect = () => ({...rect, height: 160} as DOMRect);
  }
  Object.assign(window, {scrollX: 0, scrollY: 0, getComputedStyle: () => ({lineHeight: '24px'})});
  document.createRange = (() => ({selectNodeContents: () => {}, getClientRects: () => [rect]})) as unknown as typeof document.createRange;
  return {root, navigation: createReaderArrival(root)};
}
afterEach(() => vi.useRealTimers());

describe("arrival feedback", () => {
  it("highlights a containing paragraph, expires, and changes no content", () => {
    vi.useFakeTimers();
    const {root, navigation} = fixture();
    const original = root.textContent;
    expect(navigation.reveal(3)).toBe(true);
    expect(root.ownerDocument.querySelector<HTMLElement>('.' + arrivalClass)?.style.height).toBe('24px');
    vi.advanceTimersByTime(arrivalDuration);
    expect(root.ownerDocument.querySelector('.' + arrivalClass)).toBeNull();
    expect(root.textContent).toBe(original);
  });
  it("repeated activation renews one marker and another target replaces it", () => {
    vi.useFakeTimers();
    const {root, navigation} = fixture();
    navigation.reveal(2);
    vi.advanceTimersByTime(arrivalDuration - 10);
    navigation.reveal(2);
    vi.advanceTimersByTime(20);
    expect(root.ownerDocument.querySelectorAll('.' + arrivalClass).length).toBe(1);
    navigation.reveal(7);
    expect(root.ownerDocument.querySelectorAll('.' + arrivalClass).length).toBe(1);
    expect(root.ownerDocument.querySelector<HTMLElement>('.' + arrivalClass)?.dataset.arrivalLine).toBe('7');
    navigation.clear();
    expect(vi.getTimerCount()).toBe(0);
  });
  it("an unresolved line never highlights the preceding or first paragraph", () => {
    const {root, navigation} = fixture();
    for (const line of [0, 1, 5, 99, NaN, 2.5]) expect(navigation.reveal(line)).toBe(false);
    expect(root.ownerDocument.querySelector('.' + arrivalClass)).toBeNull();
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
