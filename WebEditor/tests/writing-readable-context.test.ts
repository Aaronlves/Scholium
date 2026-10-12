import {EditorState, Transaction} from "@codemirror/state";
import {ensureSyntaxTree, syntaxTree} from "@codemirror/language";
import {describe, expect, it} from "vitest";
import {scholiumMarkdownContentLanguage, scholiumNoteLanguage} from "../language";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {exactSourceState, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";
import {writingCaretIsReadable} from "../writing-readable-context";

function fixture(marked: string) {
  const position = normalizedDocumentText(marked.slice(0, marked.indexOf("¦"))).length;
  const source = marked.replace("¦", "");
  const controller = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
  const state = EditorState.create({doc: normalizedDocumentText(source),
    extensions: [scholiumNoteLanguage, controller.extension, exactSourceState]})
    .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
  expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
  return {state, index: controller.index(state), position, source, controller};
}

describe("writing readable caret admission", () => {
  it.each([
    "Ordinary res¦earch", "# Heading res¦", "Heading res¦\n===",
    "And I don’t think that ¦", "Ordinary res\t¦", "# Heading res ¦", "- List res ¦",
    "> Quote res  ¦", "> [!state] Callout res ¦", "[^note]: Footnote res ¦",
    "| Header | Other |\n| --- | --- |\n| Cell res ¦| value |",
    "- Listed res¦", "1. Listed res¦", "- [x] Listed res¦",
    "> Quoted res¦", "> [!state] Authored res¦\n> Body",
    "> [!state] Title\n> Body res¦",
    "| Heading res¦ | Other |\n| --- | --- |\n| Body | Other |",
    "| Header | Other |\n| --- | --- |\n| Body res¦ | Other |",
    "[^note]: Intro\n\n  ```md\n  literal\n  ```\n\n  Later prose res¦",
    "[^note]: Definition res¦", "[^note]: First line\n  Continued res¦",
    "^[Inline res¦]", "**Strong res¦**", "*Emphasis res¦*", "~~Strike res¦~~", "==Highlight res¦==",
    "[Readable res¦](https://example.test/target)", "[Readable res¦]()",
    "[Readable res¦][id]\n\n[id]: https://example.test",
    "![Authored alt res¦](image.png)", "![Authored alt res¦][id]\n\n[id]: image.png",
    "[[Target|Readable res¦]]", "![[Target|Readable res¦]]",
    "A \\$ literal res¦", "A \\` literal res¦", "Before `code` after res¦",
    "Before <!-- hidden --> after res¦", "Before %% hidden %% after res¦",
    "Before $x$ after res¦", "Before [[Target]] after res¦",
    "\uFEFF# 中文 😀 e\u0301 res¦\r\nFollowing.",
  ])("admits only the readable caret in %s", marked => {
    const f = fixture(marked);
    expect(writingCaretIsReadable(f.state, f.index, f.position)).toBe(true);
    expect(f.state.field(exactSourceState).text).toBe(f.source);
    expect(f.controller.index(f.state)).toBe(f.index);
  });

  it.each([
    "---\nkey: res¦\n---\nBody", "---\nkey: res¦",
    "[^note]: Intro\n\n  ```md\n  code res¦\n  ```",
    "[^note]: Intro\n\n  ```md\n  code res¦",
    "`code res¦`", "```md\ncode res¦\n```", "    code res¦",
    "$math res¦$", "$$\nmath res¦\n$$", "$$\nmath res¦",
    "<span title='res¦'>text</span>", "<!-- comment res¦ -->",
    "%% comment res¦ %%", "%% unclosed res¦",
    "[label](https://example.test/res¦)", "<https://example.test/res¦>",
    "[[Target res¦]]", "[[Target res¦|Label]]", "![[Target res¦]]",
    "[label][id res¦]\n\n[id res]: target", "[id]: target res¦",
    "[id]: target¦", "[id]: target \"Authored title\"¦",
    "> [id]: target res¦",
    "[^identifier res¦]", "[^identifier res¦]: Definition",
    "#¦ Heading", "-¦ Listed", "- [¦x] Listed", "> [!sta¦te] Title",
    "| Header | Other |\n| --¦- | --- |\n| Body | Other |",
    "Paragraph ^identifier¦",
    "Unclosed `code res¦", "Unclosed $math res¦", "Unclosed [[target res¦",
    "Unclosed [label](target res¦", "Unclosed ![alt](target res¦",
    "Unclosed <span title='res¦", "Unclosed [^identifier res¦",
    "[[Target|Alias $math res¦]]", "^[Inline `code res¦]",
    "[Label `code res¦`](target)", "[Label $math res¦$](target)",
  ])("rejects literal, structural or unproved syntax in %s", marked => {
    const f = fixture(marked);
    expect(writingCaretIsReadable(f.state, f.index, f.position)).toBe(false);
    expect(f.state.field(exactSourceState).text).toBe(f.source);
  });

  it("uses the ready parser context while the published tree still covers only the initial viewport", () => {
    const source = "First paragraph.\n\n".repeat(700) + "[Readable res](target)";
    const controller = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
    const state = EditorState.create({doc: source,
      extensions: [scholiumMarkdownContentLanguage, controller.extension]});
    const published = syntaxTree(state);
    expect(published.length).toBeLessThan(state.doc.length);
    expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
    const position = source.lastIndexOf("res]") + 3;
    expect(writingCaretIsReadable(state, controller.index(state), position)).toBe(true);
    expect(syntaxTree(state)).toBe(published);
    expect(state.doc.toString()).toBe(source);
  });

  it("does not grant body authority without the note language", () => {
    const controller = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
    const state = EditorState.create({doc: "Ordinary prose", extensions: controller.extension});
    expect(writingCaretIsReadable(state, controller.index(state), state.doc.length)).toBe(false);
  });

  it("rejects invalid offsets and a surrogate pair split", () => {
    const f = fixture("中文 😀 res¦");
    for (const position of [-1, Number.NaN, 1.5, f.state.doc.length + 1, f.source.indexOf("😀") + 1]) {
      expect(writingCaretIsReadable(f.state, f.index, position)).toBe(false);
    }
  });

  it("reclassifies the current source after structural edits without touching exact bytes", () => {
    const f = fixture("Readable res¦");
    const fenced = f.state.update({changes: [
      {from: 0, insert: "```md\n"}, {from: f.state.doc.length, insert: "\n```"},
    ]}).state;
    const position = f.position + "```md\n".length;
    expect(writingCaretIsReadable(fenced, f.controller.index(fenced), position)).toBe(false);
    const restored = fenced.update({changes: [
      {from: 0, to: "```md\n".length},
      {from: fenced.doc.length - "\n```".length, to: fenced.doc.length},
    ]}).state;
    expect(writingCaretIsReadable(restored, f.controller.index(restored), f.position)).toBe(true);
    expect(restored.field(exactSourceState).text).toBe(f.source);
  });
});
