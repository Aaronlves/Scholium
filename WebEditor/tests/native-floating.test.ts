import {parseHTML} from "linkedom";
import {previewSurface} from "../native-floating";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createNativeFloatingPorts, type NativeFloatingEvent} from "../native-floating";
import {sanitizePreviewDocument} from "../preview-document";

afterEach(() => vi.unstubAllGlobals());

describe("typed native floating ports", () => {
  const suggestions = {
    left: 20, top: 30, bottom: 44,
    items: [{label: "Date", detail: "", disabled: false}], selected: 0,
  };

  it("keeps large current-Note rasters out of HTML while retaining peer-owned inline images", () => {
    const {document} = parseHTML('<html><head><style>.proof {color:red}</style></head><body></body></html>');
    vi.stubGlobal('document', document);
    const root = document.createElement('aside');
    const large = `data:image/png;base64,${'A'.repeat(533336)}`;
    root.innerHTML = `<img class="scholium-embedded-image" data-scholium-image-resource="a%25&amp;b.png" src="${large}" alt="Authored">`
      + '<img class="scholium-embedded-image" data-scholium-image-resource="a%25&amp;b.png">'
      + '<img class="scholium-embedded-image" src="data:image/png;base64,AQID" alt="Peer same name">'
      + '<section class="scholium-embedded-note"><img class="scholium-embedded-image" data-scholium-image-resource="a%25&amp;b.png" src="data:image/png;base64,PEER"></section>';
    const surface = previewSurface({left: 2, top: 3, bottom: 4}, root);
    expect(surface.html.length).toBeLessThan(1000);
    expect(surface.html).not.toContain(large);
    expect(surface.imageResourceKeys).toEqual(['a%25&b.png']);
    expect(surface.html).toContain('src="data:image/png;base64,AQID"');
    expect(surface.html).toContain('src="data:image/png;base64,PEER"');
    expect(surface.html).toContain('alt="Authored"');
  });

  it("serializes a cloned rendered Mermaid as complete read-only source without changing its original shadow diagram", () => {
    const {document} = parseHTML('<html><head><style>.scholium-mermaid-rendered > .scholium-mermaid-source {display:none}</style></head><body></body></html>');
    vi.stubGlobal('document', document);
    const original = document.createElement('div');
    original.innerHTML = '<figure class="scholium-mermaid scholium-mermaid-rendered" id="original-diagram"><div class="scholium-mermaid-output"></div><pre class="scholium-mermaid-source"><code class="language-mermaid"></code></pre></figure>';
    const source = 'flowchart LR\r\naccTitle: 图 e\u0301\r\naccDescr: Complete original source.\r\n  A[Start] --> B[Finish]\r\n';
    original.querySelector('code')!.textContent = source;
    const output = original.querySelector<HTMLElement>('.scholium-mermaid-output')!;
    const shadow = output.attachShadow({mode: 'open'});
    shadow.innerHTML = '<style>#diagram path {marker-end:url(#arrow)}</style><svg id="diagram"><defs><marker id="arrow"></marker></defs><path marker-end="url(#arrow)"></path></svg>';
    const originalHTML = original.innerHTML;
    const originalShadowHTML = shadow.innerHTML;
    const clone = original.cloneNode(true) as HTMLElement;
    expect(clone.querySelector('.scholium-mermaid-output')!.shadowRoot).toBeNull();

    sanitizePreviewDocument(clone);
    const surface = previewSurface({left: 2, top: 3, bottom: 4}, clone);
    const serialized = document.createElement('aside');
    serialized.innerHTML = surface.html;
    expect(serialized.querySelector('.scholium-mermaid-rendered > .scholium-mermaid-source')).toBeNull();
    expect(serialized.querySelector('.scholium-mermaid-output')).toBeNull();
    expect(serialized.querySelector('code')!.textContent).toBe(source);
    expect(serialized.querySelector('input, button, script, style, [contenteditable]')).toBeNull();
    expect(serialized.querySelector('code')!.tabIndex).toBe(-1);
    expect(original.innerHTML).toBe(originalHTML);
    expect(output.shadowRoot).toBe(shadow);
    expect(shadow.innerHTML).toBe(originalShadowHTML);
    expect(original.querySelector('.scholium-mermaid-rendered')!.id).toBe('original-diagram');
  });

  it("reports bounded size failures instead of silently losing a valid preview request", () => {
    vi.stubGlobal('window', {});
    const sent: NativeFloatingEvent[] = [];
    const dismiss = vi.fn();
    const ports = createNativeFloatingPorts(event => sent.push(event));
    const id = ports.preview.show({left: 20, top: 30, bottom: 44,
      html: 'x'.repeat(500_001), css: '', imageResourceKeys: []}, {dismiss});
    expect(sent).toEqual([{type: 'previewFailure', id, reason: 'size'}]);
    expect(dismiss).toHaveBeenCalledOnce();
    const invoke = (window as unknown as Window & {scholiumNativeFloatingEvent: Function}).scholiumNativeFloatingEvent;
    expect(invoke(id, 'enter', 0)).toBe(false);
  });

  it.each([
    {name: 'duplicate', keys: ['a', 'a']}, {name: 'long', keys: ['x'.repeat(16_385)]},
    {name: 'empty', keys: ['']}, {name: 'count', keys: Array.from({length: 8193}, (_, i) => String(i))},
  ])("reports $name resource-key bounds instead of sending a silently rejected projection", ({keys}) => {
    vi.stubGlobal('window', {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    ports.preview.show({left: 1, top: 2, bottom: 3, html: '<p>Preview</p>', css: '', imageResourceKeys: keys}, {dismiss() {}});
    expect(sent[0]).toMatchObject({type: 'previewFailure', reason: 'size'});
  });

  it("rejects stale and out-of-range suggestion activation", () => {
    vi.stubGlobal("window", {});
    const choose = vi.fn(), select = vi.fn(), dismiss = vi.fn();
    const ports = createNativeFloatingPorts(() => {});
    const oldID = ports.suggestions.show(suggestions, {choose, select, dismiss});
    const newID = ports.suggestions.show(suggestions, {choose, select, dismiss});
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(oldID, "choose", 0)).toBe(false);
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(newID, "choose", 1)).toBe(false);
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(newID, "choose", 0)).toBe(true);
    expect(choose).toHaveBeenCalledExactlyOnceWith(0);
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(oldID, "select", 0)).toBe(false);
    for (const index of [-1, 1, 0.5, NaN]) {
      expect((window as Window & {scholiumNativeFloatingEvent?: Function})
        .scholiumNativeFloatingEvent?.(newID, "select", index)).toBe(false);
    }
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(newID, "select", 0)).toBe(true);
    expect(select).toHaveBeenCalledExactlyOnceWith(0);
    expect(choose).toHaveBeenCalledTimes(1);
    expect(dismiss).not.toHaveBeenCalled();
  });

  it("accepts only the selection action's bounded inquiry", () => {
    vi.stubGlobal("window", {});
    const choose = vi.fn((_index: number) => true);
    const ports = createNativeFloatingPorts(() => {});
    const id = ports.selection.show({left: 20, top: 30, bottom: 44, utf16Count: 8}, {choose, dismiss() {}});
    const event = (window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent!;
    for (const index of [-1, 1, 2, 3, 4, 0.5, NaN]) expect(event(id, "choose", index)).toBe(false);
    expect(event(id, "choose", 0)).toBe(true);
    expect(choose.mock.calls.map(call => call[0])).toEqual([0]);
    ports.selection.hide(id);
    expect(event(id, "choose", 1)).toBe(false);
  });

  it("uses typed dismissal events instead of an empty universal payload", () => {
    vi.stubGlobal("window", {});
    const sent: NativeFloatingEvent[] = [];
    const ports = createNativeFloatingPorts(event => sent.push(event));
    const first = ports.suggestions.show(suggestions, {dismiss() {}});
    const second = ports.suggestions.show(suggestions, {dismiss() {}});
    ports.suggestions.hide(first);
    expect(sent).toHaveLength(2);
    ports.suggestions.hide(second);
    expect(sent.at(-1)).toEqual({type: "dismissSurface", kind: "suggestions", id: second});
    expect((window as Window & {scholiumNativeFloatingEvent?: Function})
      .scholiumNativeFloatingEvent?.(second, "choose", 0)).toBe(false);
  });

  it("keeps an unavailable Note inspectable but refuses pointer acceptance", () => {
    vi.stubGlobal("window", {});
    const choose = vi.fn(), select = vi.fn();
    const ports = createNativeFloatingPorts(() => {});
    const id = ports.suggestions.show({...suggestions, items: [{label: "A#draft", detail: "Cannot insert this filename", disabled: true}]},
      {choose, select, dismiss() {}});
    const event = (window as Window & {scholiumNativeFloatingEvent?: Function}).scholiumNativeFloatingEvent!;
    expect(event(id, "select", 0)).toBe(true);
    expect(select).toHaveBeenCalledExactlyOnceWith(0);
    expect(event(id, "choose", 0)).toBe(false);
    expect(choose).not.toHaveBeenCalled();
  });

  it("dismisses the previous contextual owner when another typed port opens", () => {
    vi.stubGlobal("window", {});
    const dismiss = vi.fn();
    const ports = createNativeFloatingPorts(() => {});
    ports.suggestions.show(suggestions, {dismiss});
    ports.preview.show(
      {left: 20, top: 30, bottom: 44, html: "<p>Preview</p>", css: "", imageResourceKeys: []},
      {dismiss() {}},
    );
    expect(dismiss).toHaveBeenCalledOnce();
  });
});
