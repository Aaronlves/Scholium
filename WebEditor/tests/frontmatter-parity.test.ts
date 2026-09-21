import {EditorState} from "@codemirror/state";
import {ensureSyntaxTree} from "@codemirror/language";
import {readFileSync} from "node:fs";
import {describe, expect, it} from "vitest";
import {
  frontmatterFallbackClass,
  frontmatterKeyHasSeparator,
  frontmatterTokenClass,
} from "../frontmatter-presentation";
import {scholiumNoteLanguage} from "../language";

interface FixtureLine {
  text: string;
  role: "blank" | "comment" | "mapping" | "value";
  valueKind: "value" | "string" | "collection" | "scalar";
  editorClasses: string[];
}

interface Fixture {
  name: string;
  frontmatter: string;
  lines: FixtureLine[];
}

function editorClassesByLine(frontmatter: string): string[][] {
  const payload = frontmatter.endsWith("\n") ? frontmatter : `${frontmatter}\n`;
  const source = `---\n${payload}---\n`;
  const payloadStart = 4;
  const payloadEnd = payloadStart + frontmatter.length;
  const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
  const tree = ensureSyntaxTree(state, state.doc.length, 5_000);
  if (!tree) throw new Error("Could not complete the frontmatter syntax tree.");

  const lines = frontmatter.split("\n");
  if (lines.at(-1) === "") lines.pop();
  const classes = lines.map(() => new Set<string>());
  const ancestors: string[] = [];
  tree.iterate({
    enter(node) {
      const keyHasSeparator = node.name !== "Key"
        || frontmatterKeyHasSeparator(
          state.sliceDoc(node.to, Math.min(node.to + 2, state.doc.length)),
        );
      const className = keyHasSeparator
        ? frontmatterTokenClass(node.name, ancestors.at(-1))
        : undefined;
      if (className && node.name !== "DashLine" && node.to > payloadStart && node.from < payloadEnd) {
        const from = Math.max(node.from, payloadStart);
        const to = Math.min(node.to, payloadEnd);
        const firstLine = state.doc.lineAt(from).number;
        const lastLine = state.doc.lineAt(Math.max(from, to - 1)).number;
        for (let line = firstLine; line <= lastLine; line++) {
          const index = line - 2;
          if (index >= 0 && index < classes.length) classes[index].add(className);
        }
      }
      ancestors.push(node.name);
    },
    leave() {
      ancestors.pop();
    },
  });

  for (let line = 1; line <= lines.length; line++) {
    const fallbackClass = frontmatterFallbackClass(
      state.doc.line(line + 1).text,
      false,
      classes[line - 1].size > 0,
    );
    if (fallbackClass) classes[line - 1].add(fallbackClass);
  }
  return classes.map(line => [...line].sort());
}

describe("Review and Edit frontmatter presentation parity fixtures", () => {
  const fixtures = JSON.parse(readFileSync(
    new URL("../../Tests/ScholiumContractsTests/Fixtures/frontmatter-presentation-fixtures.json", import.meta.url),
    "utf8",
  )) as Fixture[];

  for (const fixture of fixtures) {
    it(fixture.name, () => {
      expect(editorClassesByLine(fixture.frontmatter)).toEqual(
        fixture.lines.map(line => [...line.editorClasses].sort()),
      );
    });
  }
});
