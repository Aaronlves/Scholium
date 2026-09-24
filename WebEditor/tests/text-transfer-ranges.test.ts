import {EditorSelection, EditorState} from '@codemirror/state';
import {ensureSyntaxTree} from '@codemirror/language';
import {describe, expect, it} from 'vitest';
import {scholiumNoteLanguage} from '../language';
import {ExactSourceMirror, normalizedDocumentText} from '../state';
import {completeHeadingSelection, containsCompleteHeading, isCompleteLineSelection} from '../text-transfer-ranges';

function fixture(exact: string) {
  const source = normalizedDocumentText(exact);
  const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
  if (!ensureSyntaxTree(state, state.doc.length, 5_000)) throw new Error('Incomplete fixture syntax tree');
  function select(text: string, reverse = false) {
    const from = source.indexOf(text);
    if (from < 0) throw new Error('Missing fixture selection');
    const to = from + text.length;
    return EditorSelection.single(reverse ? to : from, reverse ? from : to);
  }
  return {state, source, select};
}

describe('complete heading source transfer ranges', () => {
  it.each([false, true])('includes ATX opening/closing markers, inline source, and one newline (reverse=%s)', reverse => {
    const f = fixture('## **Café 😀 e\u0301** ###   \nNext paragraph.');
    const selection = completeHeadingSelection(f.state, f.select('Café 😀 e\u0301', reverse));
    expect(f.state.sliceDoc(selection.main.from, selection.main.to)).toBe('## **Café 😀 e\u0301** ###   \n');
    expect(selection.main.anchor > selection.main.head).toBe(reverse);
    expect(containsCompleteHeading(f.state, selection.main)).toBe(true);
    expect(f.state.doc.toString()).toBe(f.source);
  });

  it('uses the original link destination and emphasis markers rather than rebuilding rendered text', () => {
    const f = fixture('## [*Visible*](target.md "Title")\nTail');
    const selection = completeHeadingSelection(f.state, f.select('Visible'));
    expect(f.state.sliceDoc(selection.main.from, selection.main.to)).toBe('## [*Visible*](target.md "Title")\n');
  });

  it.each(['%%prefix%% Title', 'Title %%suffix%%', '%%prefix%% Title %%suffix%%'])
  ('includes hidden inline source outside the selected visible title: %s', title => {
    const f = fixture(`## ${title}\nTail`);
    const selection = completeHeadingSelection(f.state, f.select('Title'));
    expect(f.state.sliceDoc(selection.main.from, selection.main.to)).toBe(`## ${title}\n`);
    expect(containsCompleteHeading(f.state, selection.main)).toBe(true);
    const partial = f.select('Tit');
    expect(completeHeadingSelection(f.state, partial)).toBe(partial);
  });

  it('includes a Setext underline and preserves multiline heading source', () => {
    const f = fixture('*First*\nsecond\n======\nBody');
    const selection = completeHeadingSelection(f.state, f.select('First*\nsecond'));
    expect(f.state.sliceDoc(selection.main.from, selection.main.to)).toBe('*First*\nsecond\n======\n');
  });

  it('keeps a heading and complete following paragraph together through the last newline', () => {
    const f = fixture('## Heading\n\nBody paragraph.\nNext');
    const selection = completeHeadingSelection(f.state, f.select('Heading\n\nBody paragraph.', true));
    expect(f.state.sliceDoc(selection.main.from, selection.main.to)).toBe('## Heading\n\nBody paragraph.\n');
    expect(selection.main.anchor > selection.main.head).toBe(true);
    expect(containsCompleteHeading(f.state, selection.main)).toBe(true);
  });

  it('does not extend partial heading text or a range starting partway through the heading', () => {
    const f = fixture('## Heading\n\nBody paragraph.\nNext');
    for (const text of ['Head', 'ading\n\nBody paragraph.', 'ading\n\nBody']) {
      const before = f.select(text);
      expect(completeHeadingSelection(f.state, before)).toBe(before);
      expect(containsCompleteHeading(f.state, before.main)).toBe(false);
    }
  });

  it('does not claim a partially selected final paragraph as a complete block', () => {
    const f = fixture('## Heading\n\nBody paragraph.\nNext');
    const selection = completeHeadingSelection(f.state, f.select('Heading\n\nBody'));
    expect(f.state.sliceDoc(selection.main.from, selection.main.to)).toBe('## Heading\n\nBody');
    expect(containsCompleteHeading(f.state, selection.main)).toBe(false);
  });

  it('does not add an extra blank line when the selected range already includes its newline', () => {
    const f = fixture('## Heading\n\nNext');
    const selection = completeHeadingSelection(f.state, f.select('Heading\n'));
    expect(f.state.sliceDoc(selection.main.from, selection.main.to)).toBe('## Heading\n');
  });

  it('supports EOF and preserves ordinary complete-line text selections', () => {
    const f = fixture('Paragraph.\n\n## Final');
    const heading = completeHeadingSelection(f.state, f.select('Final'));
    expect(f.state.sliceDoc(heading.main.from, heading.main.to)).toBe('## Final');
    expect(isCompleteLineSelection(f.state, heading.main)).toBe(true);
    const paragraph = f.select('Paragraph.');
    expect(isCompleteLineSelection(f.state, paragraph.main)).toBe(true);
    expect(completeHeadingSelection(f.state, paragraph)).toBe(paragraph);
    expect(containsCompleteHeading(f.state, paragraph.main)).toBe(false);
  });

  it('keeps YAML and code-fence heading-like text outside structural transfers', () => {
    for (const source of ['---\ntitle: "## Heading"\n---\nBody', '---\nkey: value\n## Heading', '```md\n## Heading\n```']) {
      const f = fixture(source);
      const before = f.select('Heading');
      expect(completeHeadingSelection(f.state, before)).toBe(before);
      expect(containsCompleteHeading(f.state, before.main)).toBe(false);
    }
    const f = fixture('---\ntitle: Fixture\n---\n## Heading\n');
    const heading = completeHeadingSelection(f.state, f.select('Heading'));
    expect(f.state.sliceDoc(heading.main.from, heading.main.to)).toBe('## Heading\n');
    const spanning = EditorSelection.single(0, heading.main.to);
    expect(completeHeadingSelection(f.state, spanning)).toBe(spanning);
    expect(containsCompleteHeading(f.state, spanning.main)).toBe(false);
  });

  it('returns normalized UTF-16 offsets whose exact source slice retains CRLF, BOM, emoji and combining characters', () => {
    const exact = '\uFEFFPreamble\r\n\r\n## 😀 e\u0301\r\nTail';
    const f = fixture(exact);
    const selection = completeHeadingSelection(f.state, f.select('😀 e\u0301'));
    expect(new ExactSourceMirror(exact).slice(selection.main.from, selection.main.to)).toBe('## 😀 e\u0301\r\n');
    expect(f.state.doc.toString()).toBe(f.source);
    expect(selection.main.from).toBe(f.source.indexOf('##'));
    expect(f.state.doc.sliceString(0, 1)).toBe('\uFEFF');
  });
});
