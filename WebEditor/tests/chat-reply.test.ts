import {parseHTML} from 'linkedom';
import {afterEach, describe, expect, it, vi} from 'vitest';
import {installChatReply} from '../chat-reply';
import {createReplyProjection} from '../chat-reply-projection';

afterEach(() => vi.unstubAllGlobals());

function fixture(html: string) {
  const {window, document} = parseHTML('<html><body><article></article></body></html>');
  window.getSelection = () => null;
  vi.stubGlobal('window', window);
  vi.stubGlobal('document', document);
  vi.stubGlobal('HTMLElement', window.HTMLElement);
  vi.stubGlobal('ResizeObserver', class { observe() {} disconnect() {} });
  const root = document.querySelector('article') as unknown as HTMLElement;
  root.innerHTML = html;
  const post = vi.fn();
  return {root, post};
}

describe('renderer-owned reply object identity', () => {
  it('reports each table and escaped HTML/code fallback using its renderer ID', () => {
    const {root, post} = fixture(`
      <div class="scholium-table-scroll"><table data-scholium-object="table-a"><tr><td>A</td></tr></table></div>
      <div class="scholium-table-scroll"><table data-scholium-object="table-b"><tr><td>B</td></tr></table></div>
      <pre data-scholium-object="raw"><code>&lt;div&gt;HTML&lt;/div&gt;</code></pre>
      <pre data-scholium-object="code"><code>print(42)</code></pre>`);
    const dispose = installChatReply(root, post);
    const report = post.mock.calls.at(-1)![1];
    expect(report.objects.map((value: {identity: string}) => value.identity)).toEqual(['table-a', 'table-b', 'raw', 'code']);
    expect(report.objects.every((value: object) => !('index' in value))).toBe(true);
    expect(root.querySelectorAll('.scholium-reply-object').length).toBe(4);
    expect(root.querySelectorAll('.scholium-table-scroll .scholium-reply-controls').length).toBe(0);
    dispose();
  });

  it('authorizes no extra object for a Mermaid fallback or arbitrary untagged pre', () => {
    const {root, post} = fixture(`
      <figure class="scholium-mermaid" data-scholium-object="diagram">
        <pre class="scholium-mermaid-source" data-scholium-object="diagram"><code>A --&gt; B</code></pre>
      </figure><pre><code>untagged</code></pre>`);
    const dispose = installChatReply(root, post);
    dispose.refresh();
    expect(root.querySelectorAll('.scholium-reply-object').length).toBe(1);
    expect(post.mock.calls.at(-1)![1].objects.map((value: {identity: string}) => value.identity)).toEqual(['diagram']);
    dispose();
  });

  it('retains decorated content across append and replaces a changed descriptor', () => {
    const original = '<pre data-scholium-object="first"><code>first</code></pre>';
    const {root, post} = fixture(original);
    const projection = createReplyProjection(root);
    const dispose = installChatReply(root, post);
    projection.commit();
    const wrapper = root.firstElementChild;
    projection.apply(original + '<p>Appended.</p>');
    dispose.refresh();
    projection.commit();
    expect(root.firstElementChild).toBe(wrapper);
    projection.apply('<pre data-scholium-object="replacement"><code>changed</code></pre><p>Appended.</p>');
    dispose.refresh();
    expect(root.firstElementChild).not.toBe(wrapper);
    expect(post.mock.calls.at(-1)![1].objects[0].identity).toBe('replacement');
    dispose();
  });
});
