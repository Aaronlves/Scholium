import {EditorSelection, EditorState, StateEffect, StateField, Text} from "@codemirror/state";
import {history, isolateHistory, redo, undo} from "@codemirror/commands";
import {ensureSyntaxTree, syntaxTree} from "@codemirror/language";
import {EditorView} from "@codemirror/view";
import {describe, expect, it, vi} from "vitest";
import {scholiumNoteLanguage} from "../language";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {createLiveSemanticLayout} from "../live-semantic-layout";
import type {MarkdownEditingDialect} from "../protocol";
import {createMarkdownDocumentState} from "../bootstrap";
import {exactSourceHistory, exactSourceState, setExactSource} from "../exact-source-history";
import {normalizedDocumentText} from "../state";
import {transformMarkdown} from "../transformations";
import {citationHistory, setCitationData, setCitationSnapshot, type ZoteroCitationSnapshot} from "../zotero-citation-state";

const dialect: MarkdownEditingDialect = {
  version: 6,
  callouts: [
    {identifier: "state", label: "Statement", meaning: "Statement"},
  ],
  linkAnnotation: {
    openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\",
    allowsMultiline: true, allowsNesting: false,
  },
  footnotes: {
    namedReferenceOpening: "[^",
    namedReferenceClosing: "]",
    definitionSeparator: ":",
    inlineOpening: "^[",
    continuationIndentSpaces: 2,
    allowsTabContinuation: true,
    caseSensitiveIdentifiers: true,
    ordinalByFirstReference: true,
  },
  mathematics: {
    inlineDelimiter: "$",
    displayDelimiter: "$$",
    singleDollarInline: true,
  },
};

describe("live projection index component", () => {
  const linkedCallout = "Lead 中文 e\u0301 🧭.\n\n> [!cite]+ 来源与版本\n"
    + "> Example, A. (2026). A disposable source.\n>\n"
    + "> 书目来源：[来源 1](https://example.invalid/source)\n"
    + "> 所读书目原文：[PDF](</Users/fixture/Research Papers/Example source.pdf>)\n"
    + ">\n> > [!quote]- 嵌套引文\n> > Nested quotation.\n\nAfter.";

  function expectFreshIndex(state: EditorState, controller: ReturnType<typeof createLiveProjectionIndexController>) {
    const oracle = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const fresh = createMarkdownDocumentState(state.field(exactSourceState, false)?.text ?? state.doc.toString(),
      [scholiumNoteLanguage, exactSourceHistory, oracle.extension]);
    expect(controller.index(state)).toEqual(oracle.index(fresh));
  }

  it("projects many complete tables from the current rope without rebuilding or materializing the whole Note", () => {
    const tableSource = "| 中文 🦉 | e\u0301 |\n|:---|---:|\n| A \\| B | value |";
    const source = "\ufeffBefore.\r\n\r\n" + Array.from({length: 40}, () => tableSource.replaceAll("\n", "\r\n")).join("\r\n\r\n")
      + "\r\n\r\nAfter.";
    let state = createMarkdownDocumentState(source, [scholiumNoteLanguage, exactSourceHistory]);
    expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const textOf = vi.spyOn(Text, "of");
    const toString = vi.spyOn(state.doc, "toString");
    try {
      state = state.update({effects: StateEffect.appendConfig.of(controller.extension)}).state;
      const index = controller.index(state);
      expect(index.syntaxComplete).toBe(true);
      expect(index.tables).toHaveLength(40);
      for (const table of index.tables) {
        expect(state.doc.sliceString(table.from, table.to)).toBe(tableSource);
        expect(table.header.map(cell => cell.source)).toEqual(["中文 🦉", "e\u0301"]);
        expect(table.header.map(cell => cell.alignment)).toEqual(["left", "right"]);
        expect(state.doc.sliceString(table.body[0][0].sourceOffset, table.body[0][0].sourceOffset + 6)).toBe("A \\| B");
      }
      expect(textOf).not.toHaveBeenCalled();
      expect(toString).not.toHaveBeenCalled();
      expect(state.field(exactSourceState).text).toBe(source);
    } finally {
      textOf.mockRestore();
      toString.mockRestore();
    }
    expectFreshIndex(state, controller);
  });

  it("keeps nested quote depth through list ancestors and mapped prose input", () => {
    const source = "\ufeff> Outer\n> > Middle\n> > - item\n> >   > Nested in list.\n> >   > > Deepest.\n\nAfter.";
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    let state = createMarkdownDocumentState(source, [scholiumNoteLanguage, exactSourceHistory, controller.extension]);
    expect(controller.index(state).quoteRanges.map(range => range.depth)).toEqual([1, 2, 3, 4]);
    for (const passage of ["Nested in list.", "After."]) {
      const from = state.doc.toString().indexOf(passage) + 2;
      const transaction = state.update({changes: {from, insert: "中e\u0301"}});
      state = transaction.state;
      expect(controller.topologyWasMapped(transaction)).toBe(true);
      expect(controller.index(state).quoteRanges.map(range => range.depth)).toEqual([1, 2, 3, 4]);
      expectFreshIndex(state, controller);
    }
  });

  it("does not index paragraph ancestors for an absent quote feature after long prose input", () => {
    const source = "\ufeff" + "Ordinary 中文 😀 e\u0301 prose.\r\n\r\n".repeat(512);
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    let state = createMarkdownDocumentState(source, [scholiumNoteLanguage, exactSourceHistory]);
    expect(ensureSyntaxTree(state, state.doc.length, 1_000)).not.toBeNull();
    state = state.update({effects: StateEffect.appendConfig.of(controller.extension)}).state;
    expect(controller.index(state).quoteRanges).toEqual([]);
    const mapEntries = vi.spyOn(Map.prototype, "set");
    try {
      const transaction = state.update({changes: {from: 3, insert: "文"}});
      state = transaction.state;
      const index = controller.index(state);
      expect(controller.topologyWasMapped(transaction)).toBe(true);
      expect(index.syntax.blocks).toHaveLength(512);
      expect(index.quoteRanges).toEqual([]);
      const blocks = new Set<unknown>(index.syntax.blocks);
      expect(mapEntries.mock.calls.filter(([, value]) => blocks.has(value))).toHaveLength(0);
    } finally { mapEntries.mockRestore(); }
    expectFreshIndex(state, controller);
  });

  it.each(["所读书目原文", "Nested quotation"])(
    "maps repeated Callout prose input/deletion beside %j against a fresh parser", passage => {
      let builds = 0;
      const controller = createLiveProjectionIndexController({editingDialect: () => dialect,
        recordMetric: name => {if (name === "projection-index") builds++;}});
      const from = linkedCallout.indexOf(passage) + 2;
      let state = EditorState.create({doc: linkedCallout, selection: {anchor: from},
        extensions: [scholiumNoteLanguage, controller.extension]});
      const identity = controller.index(state).topologyIdentity;
      for (const insert of ["中", "文", " ", "e", "\u0301"]) {
        const inserted = state.update({changes: {from, insert}, selection: {anchor: from + insert.length}});
        state = inserted.state;
        expect(controller.topologyWasMapped(inserted)).toBe(true);
        expect(controller.index(state).topologyIdentity).toBe(identity);
        expect(state.doc.toString()).toBe(linkedCallout.slice(0, from) + insert + linkedCallout.slice(from));
        expect(state.selection.main.head).toBe(from + insert.length);
        expectFreshIndex(state, controller);
        const deleted = state.update({changes: {from, to: from + insert.length}, selection: {anchor: from}});
        state = deleted.state;
        expect(controller.topologyWasMapped(deleted)).toBe(true);
        expect(state.doc.toString()).toBe(linkedCallout);
        expect(state.selection.main.head).toBe(from);
        expectFreshIndex(state, controller);
      }
      expect(builds).toBe(1);
    },
  );

  it.each(["\n", "\r\n"])("preserves exact Callout source, selection, composition transactions and Undo with %j", newline => {
    const source = "\ufeff" + linkedCallout.replaceAll("\n", newline);
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const from = normalizedDocumentText(source).indexOf("所读书目原文") + 2;
    let state = createMarkdownDocumentState(source,
      [scholiumNoteLanguage, history(), exactSourceHistory, controller.extension],
      {selection: EditorSelection.single(from)});
    const beforeSelection = state.selection;
    const insert = "中文 e\u0301 🧭";
    state = state.update({changes: {from, insert}, selection: {anchor: from + insert.length},
      userEvent: "input.type.compose", annotations: isolateHistory.of("full")}).state;
    const changed = state;
    expectFreshIndex(state, controller);
    expect(state.field(exactSourceState).text).toBe(source.replace("所读书目原文", `所读${insert}书目原文`));
    expect(state.doc.toString()).toBe(normalizedDocumentText(state.field(exactSourceState).text));
    expect(undo({state, dispatch: transaction => {state = transaction.state;}})).toBe(true);
    expect(state.field(exactSourceState).text).toBe(source);
    expect(state.selection.eq(beforeSelection)).toBe(true);
    expectFreshIndex(state, controller);
    expect(redo({state, dispatch: transaction => {state = transaction.state;}})).toBe(true);
    expect(state.field(exactSourceState).text).toBe(changed.field(exactSourceState).text);
    expect(state.selection.eq(changed.selection)).toBe(true);
    expectFreshIndex(state, controller);
  });

  it.each([
    {needle: "来源与版本", insert: " 中"},
    {needle: "[!cite]", insert: "x"},
    {needle: "所读书目原文", insert: ">"},
    {needle: "所读书目原文", insert: "\n> "},
    {needle: "Nested quotation.", insert: "x", end: true},
    {needle: "After.", insert: "> "},
  ])("rechecks header, nested endpoints and structural changes against the parser: %j", ({needle, insert, end}) => {
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const from = linkedCallout.indexOf(needle) + (end ? needle.length : 0);
    const state = EditorState.create({doc: linkedCallout, extensions: [scholiumNoteLanguage, controller.extension]});
    const transaction = state.update({changes: {from, insert}});
    expectFreshIndex(transaction.state, controller);
    if (/[>\n]/.test(insert) || needle === "来源与版本" || needle === "[!cite]") {
      expect(controller.topologyWasMapped(transaction)).toBe(false);
    }
  });

  it("refreshes every body line when ordinary header text changes the Callout role", () => {
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const layout = createLiveSemanticLayout({projections: controller, editingDialect: () => dialect, selection: {
      extension: [], selection: state => state.selection, changed: (a, b) => !a.selection.eq(b.selection),
    }});
    const extensions = [scholiumNoteLanguage, controller.extension, layout.extension];
    const source = "> [!state] Heading\n> First\n> Second\n> Third\n> Distant body.";
    const state = EditorState.create({doc: source, extensions});
    const classes = (value: EditorState) => value.facet(EditorView.decorations).flatMap(set => {
      if (typeof set === "function") return [];
      const result: string[] = [];
      set.between(value.doc.line(5).from, value.doc.line(5).to, (_from, _to, decoration) => {
        if (decoration.spec.attributes?.class) result.push(decoration.spec.attributes.class);
      });
      return result;
    }).join(" ");
    expect(classes(state)).toContain("cm-live-callout-role-state");
    const transaction = state.update({changes: {from: source.indexOf("state"), insert: "x"}});
    expect(controller.topologyWasMapped(transaction)).toBe(false);
    expectFreshIndex(transaction.state, controller);
    expect(classes(transaction.state)).toContain("cm-live-callout-role-neutral");
    expect(classes(transaction.state)).toBe(classes(EditorState.create({doc: transaction.newDoc, extensions})));
  });

  it.each(["    ", "\t", "- ", "+ ", "1. ", "1) "])(
    "reclassifies a newly inserted structural prefix %j from the parser",
    prefix => {
      const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
      const state = EditorState.create({doc: "code", extensions: [scholiumNoteLanguage, controller.extension]});
      const transaction = state.update({changes: {from: 0, insert: prefix}});
      const changed = controller.index(transaction.state);
      const oracle = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
      const fresh = EditorState.create({doc: transaction.newDoc, extensions: [scholiumNoteLanguage, oracle.extension]});

      expect(controller.topologyWasMapped(transaction)).toBe(false);
      expect(changed).toEqual(oracle.index(fresh));
      if (prefix === "    " || prefix === "\t") {
        expect(changed.literals.codeBlocks).toHaveLength(1);
        expect(transformMarkdown(transaction.newDoc.toString(), [{anchor: prefix.length, head: transaction.newDoc.length}],
          "bold", {protectedRanges: changed.commandProtectedRanges})).toBeNull();
      } else {
        expect(changed.syntax.blocks.some(block => block.kind === "listItem")).toBe(true);
        expect(changed.listPrefixRanges).toEqual([{from: 0, to: prefix.length}]);
      }
    },
  );

  it("reclassifies indentation typed one space at a time without granting code formatting", () => {
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    let state = EditorState.create({doc: "code", extensions: [scholiumNoteLanguage, controller.extension]});
    for (let spaces = 1; spaces <= 4; spaces++) {
      state = state.update({changes: {from: 0, insert: " "}}).state;
      expect(controller.index(state).literals.codeBlocks.length).toBe(spaces === 4 ? 1 : 0);
    }
    expect(transformMarkdown(state.doc.toString(), [{anchor: 4, head: state.doc.length}], "bold",
      {protectedRanges: controller.index(state).commandProtectedRanges})).toBeNull();
    state = state.update({changes: {from: 0, to: 1}}).state;
    expect(controller.index(state).literals.codeBlocks).toHaveLength(0);
    expect(transformMarkdown(state.doc.toString(), [{anchor: 3, head: state.doc.length}], "bold",
      {protectedRanges: controller.index(state).commandProtectedRanges})).not.toBeNull();
  });

  it.each(["- root\n  - nested", "1. root\n   1. nested", "- [ ] Task", "> Outer\n> > Quote"])(
    "maps repeated mixed-script input and every container endpoint in %j",
    source => {
      let builds = 0;
      const controller = createLiveProjectionIndexController({editingDialect: () => dialect,
        recordMetric: name => { if (name === "projection-index") builds++; }});
      let state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage, controller.extension]});
      for (const insert of Array.from(" 中文 e\u0301 🧭")) {
        const transaction = state.update({changes: {from: state.doc.length, insert}});
        state = transaction.state;
        expect(controller.topologyWasMapped(transaction)).toBe(true);
        const oracle = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
        const fresh = EditorState.create({doc: state.doc, extensions: [scholiumNoteLanguage, oracle.extension]});
        expect(controller.index(state)).toEqual(oracle.index(fresh));
      }
      expect(builds).toBe(1);
    },
  );

  it("reuses a complete index when its already analyzed tree is subsequently published", () => {
    let builds = 0;
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect,
      recordMetric: name => { if (name === "projection-index") builds++; }});
    const source = "Plain paragraph 中文.\n\n".repeat(400) + "# Later heading\n\nAfter.";
    let now = 0;
    const deadline = vi.spyOn(Date, "now").mockImplementation(() => now += 100);
    let initialPublishedTree: ReturnType<typeof syntaxTree> | undefined;
    const releaseParseBudget = StateField.define({
      create(state) {
        // Force the language's initial budget exhaustion through the public
        // API, then let the index ensure a complete tree in the same state.
        initialPublishedTree = syntaxTree(state);
        deadline.mockRestore();
        return null;
      },
      update: value => value,
    });
    let state: EditorState;
    try {
      state = createMarkdownDocumentState(source,
        [scholiumNoteLanguage, exactSourceHistory, releaseParseBudget, controller.extension]);
    } finally {
      deadline.mockRestore();
    }
    const initial = controller.index(state);
    const ensured = ensureSyntaxTree(state, state.doc.length, 5_000);
    expect(initial.syntaxComplete).toBe(true);
    expect(ensured).not.toBeNull();
    expect(initialPublishedTree?.length).toBeLessThan(state.doc.length);
    expect(syntaxTree(state)).toBe(initialPublishedTree);
    expect(syntaxTree(state)).not.toBe(ensured);
    expect(builds).toBe(1);

    const published = state.update({});
    expect(published.docChanged).toBe(false);
    expect(published.effects).toHaveLength(0);
    state = published.state;
    expect(syntaxTree(state)).toBe(ensured);
    expect(controller.index(state)).toBe(initial);
    expect(builds).toBe(1);

    const next = state.update({changes: {from: state.doc.length, insert: "\n\n```ts\nnewly_protected\n```"}}).state;
    expect(controller.index(next)).not.toBe(initial);
    expect(builds).toBe(2);
    expect(syntaxTree(next)).not.toBe(ensured);
    const target = next.doc.toString().indexOf("newly_protected");
    expect(transformMarkdown(next.doc.toString(), [{anchor: target, head: target + 15}], "bold",
      {protectedRanges: controller.index(next).commandProtectedRanges})).toBeNull();
    expectFreshIndex(next, controller);
    expect(state.field(exactSourceState).text).toBe(source);
  });

  it.each(["source", "citation-data", "citation-baseline"])(
    "rebuilds for %s changes even when the published tree was already analyzed", change => {
      let builds = 0;
      const controller = createLiveProjectionIndexController({editingDialect: () => dialect,
        recordMetric: name => { if (name === "projection-index") builds++; }});
      const source = "# Claim\n\nPlain 中文 🦉.\n";
      const baseline: ZoteroCitationSnapshot = {
        noteID: "11111111-1111-1111-1111-111111111111", vaultID: "22222222-2222-2222-2222-222222222222",
        status: "absent",
      };
      let state = createMarkdownDocumentState(source,
        [scholiumNoteLanguage, exactSourceHistory, citationHistory, controller.extension], {citationSnapshot: baseline});
      expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
      state = state.update({}).state;
      const index = controller.index(state), tree = syntaxTree(state), before = builds;
      const draft = {schemaVersion: 1 as const, fields: [], documentData: "changed companion"};
      const effect = change === "source" ? setExactSource.of(source.replaceAll("\n", "\r\n"))
        : change === "citation-data" ? setCitationData.of(draft)
        : setCitationSnapshot.of({...baseline, status: "unresolved"});
      const changed = state.update({effects: effect}).state;
      expect(syntaxTree(changed)).toBe(tree);
      expect(changed.doc.toString()).toBe(state.doc.toString());
      expect(controller.index(changed)).not.toBe(index);
      expect(builds).toBe(before + 1);
      if (change === "source") {
        expect(index.zoteroFields.source).toBe(source);
        expect(controller.index(changed).zoteroFields.source).toBe(source.replaceAll("\n", "\r\n"));
      } else if (change === "citation-data") {
        expect(controller.index(changed).zoteroFields.companion).toEqual(draft);
      } else {
        expect(index.zoteroFields.diagnostics).toHaveLength(0);
        expect(controller.index(changed).zoteroFields.diagnostics.length).toBeGreaterThan(0);
      }
    },
  );

  it("withholds semantic commands during an incomplete parse and restores them after parse publication", () => {
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const source = "Plain paragraph.\n\n".repeat(400) + "```ts\nprotected_target\n```\n\nAfter.";
    let now = 0;
    // Advance the actual parser deadline on each read. This deterministically
    // exercises budget exhaustion without relying on document size or CPU speed.
    const deadline = vi.spyOn(Date, "now").mockImplementation(() => now += 100);
    let state: EditorState;
    try {
      state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage, controller.extension]});
    } finally {
      deadline.mockRestore();
    }
    const pending = controller.index(state);
    expect(pending.syntaxComplete).toBe(false);
    const target = source.indexOf("protected_target");
    for (const [anchor, head] of [[0, 5], [target, target + 16], [source.length, source.length]]) {
      expect(transformMarkdown(source, [{anchor, head}], "bold",
        {protectedRanges: pending.commandProtectedRanges})).toBeNull();
    }
    expect(ensureSyntaxTree(state, state.doc.length, 5_000)).not.toBeNull();
    state = state.update({selection: {anchor: target}}).state;
    const complete = controller.index(state);
    expect(complete.syntaxComplete).toBe(true);
    expect(complete.topologyIdentity).not.toBe(pending.topologyIdentity);
    expect(transformMarkdown(source, [{anchor: 0, head: 5}], "bold",
      {protectedRanges: complete.commandProtectedRanges})).not.toBeNull();
    expect(transformMarkdown(source, [{anchor: target, head: target + 16}], "bold",
      {protectedRanges: complete.commandProtectedRanges})).toBeNull();
    expect(state.doc.toString()).toBe(source);
  });

  it.each(["\n", "\r\n"])("maps successive mixed-script paragraph-end input with exact %j separators", newline => {
    let builds = 0;
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect,
      recordMetric: name => {if (name === "projection-index") builds++;}});
    let expected = ["# Earlier", "", "A *claim* with [[Target]] and 中文 e\u0301 🧭.", "", "sampletest9"].join(newline);
    let state = createMarkdownDocumentState(expected,
      [scholiumNoteLanguage, exactSourceHistory, controller.extension],
      {selection: EditorSelection.single(normalizedDocumentText(expected).length)});
    const topology = controller.index(state).topologyIdentity;
    for (const insert of Array.from("Latin中文 e\u0301 🧭")) {
      const end = state.doc.length;
      const transaction = state.update({changes: {from: end, insert}, selection: {anchor: end + insert.length}});
      state = transaction.state;
      expected += insert;
      expect(controller.topologyWasMapped(transaction)).toBe(true);
      expect(controller.index(state).topologyIdentity).toBe(topology);
      expect(state.doc.toString()).toBe(normalizedDocumentText(expected));
      expect(state.field(exactSourceState).text).toBe(expected);
      expect(state.selection.main.anchor).toBe(state.doc.length);
      expect(state.selection.main.head).toBe(state.doc.length);
      const oracle = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
      const fresh = createMarkdownDocumentState(expected,
        [scholiumNoteLanguage, exactSourceHistory, oracle.extension], {selection: state.selection});
      expect(ensureSyntaxTree(fresh, fresh.doc.length, 5_000)).not.toBeNull();
      expect(controller.index(state)).toEqual(oracle.index(fresh));
      expect(controller.index(state).syntax.blocks.at(-1)?.to).toBe(state.doc.length);
    }
    expect(builds).toBe(1);
  });

  it("reuses one semantic index for repeated reads in a Source state", () => {
    let builds = 0;
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect,
      recordMetric: name => { if (name === "projection-index") builds++; }});
    const state = EditorState.create({doc: "---\ntags: [draft]\n---\n# Body\n\n[[Target]] and $x$.",
      extensions: [scholiumNoteLanguage, controller.extension]});
    const index = controller.index(state);
    for (let read = 0; read < 8; read++) expect(controller.index(state)).toBe(index);
    expect(builds).toBe(1);
    expect(index.frontmatterRange).not.toBeNull();
    expect(index.syntax.blocks.some(block => block.kind === "heading")).toBe(true);
  });

  it("rebinds images after plain definition label edits while mapping unrelated prose", () => {
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const source = "![Image][figure]\n\n[figure]: Attachments/a.png\n\nUnrelated prose.";
    let state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage, controller.extension]});
    const initial = controller.index(state);
    expect(initial.syntax.inlines.filter(image => image.kind === "image")).toHaveLength(1);
    const definition = source.indexOf("[figure]:") + 1;
    const removed = state.update({changes: {from: definition, insert: "x"}});
    expect(controller.topologyWasMapped(removed)).toBe(false);
    expect(controller.index(removed.state).syntax.inlines.filter(image => image.kind === "image")).toHaveLength(0);
    const restored = removed.state.update({changes: {from: definition, to: definition + 1}});
    expect(controller.topologyWasMapped(restored)).toBe(false);
    expect(controller.index(restored.state).syntax.inlines.filter(image => image.kind === "image")).toHaveLength(1);
    state = restored.state;
    const prose = state.update({changes: {from: state.doc.toString().indexOf("prose"), insert: "ordinary "}});
    expect(controller.topologyWasMapped(prose)).toBe(true);
    const oracle = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const fresh = EditorState.create({doc: prose.state.doc, extensions: [scholiumNoteLanguage, oracle.extension]});
    expect(controller.index(prose.state)).toEqual(oracle.index(fresh));
  });

  it.each([false, true])("maps repeated mixed-script prose deletion to a fresh parse (line end: %s)", atLineEnd => {
    let builds = 0;
    const controller = createLiveProjectionIndexController({editingDialect: () => dialect,
      recordMetric: name => { if (name === "projection-index") builds++; }});
    const source = "# Heading\n\nAn ordinary argument 中文 e\u0301"
      + (atLineEnd ? "\n\nProse beside *emphasis* and [[Target]].\n\n" : " carries prose beside *emphasis* and [[Target]].\n\n")
      + "> [!state] Claim\n> Source owned content.\n\n"
      + "| A | B |\n| - | - |\n| x | y |\n\n"
      + "A reference [^note] and $x$.\n\n[^note]: Definition.\n";
    let state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage, controller.extension]});
    const initialIdentity = controller.index(state).topologyIdentity;
    const from = source.indexOf("argument");
    const length = "argument 中文 e\u0301".length;
    builds = 0;
    for (let remaining = length; remaining > 0; remaining--) {
      const transaction = state.update({changes: {from: from + remaining - 1, to: from + remaining}});
      state = transaction.state;
      const mapped = controller.index(state);
      expect(mapped.topologyIdentity).toBe(initialIdentity);
      const oracle = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
      const fresh = EditorState.create({doc: state.doc, extensions: [scholiumNoteLanguage, oracle.extension]});
      expect(mapped).toEqual(oracle.index(fresh));
      expect(state.doc.toString()).toBe(source.slice(0, from + remaining - 1) + source.slice(from + length));
    }
    expect(builds).toBe(0);
  });

  it("recognizes headings throughout incremental typing and marker deletion", () => {
    for (const level of [1, 2, 6]) {
      const controller = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
      let state = EditorState.create({doc: "", extensions: [scholiumNoteLanguage, controller.extension]});
      const prefix = "#".repeat(level) + " ";
      for (const character of prefix + "dd中文") {
        state = state.update({changes: {from: state.doc.length, insert: character}}).state;
        if (state.doc.length >= prefix.length) {
          expect(controller.index(state).syntax.blocks.find(block => block.kind === "heading")?.headingLevel).toBe(level);
        }
      }
      for (let remaining = level - 1; remaining >= 0; remaining--) {
        state = state.update({changes: {from: 0, to: 1}}).state;
        expect(controller.index(state).syntax.blocks.find(block => block.kind === "heading")?.headingLevel)
          .toBe(remaining || undefined);
      }
    }
  });

  it("owns catalog construction and maps only topology-safe prose edits", () => {
    const metrics: string[] = [];
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: (name) => metrics.push(name),
    });
    const source = "> [!state] Claim\n> Body.\n\nPlain prose with $x$.";
    const state = EditorState.create({
      doc: source,
      extensions: [scholiumNoteLanguage, controller.extension],
    });
    const initial = controller.index(state);
    expect(initial.callouts).toHaveLength(1);
    expect(initial.mathExpressions.map((expression) => expression.content)).toEqual(["x"]);

    const proseInsertion = source.indexOf("Plain") + "Plain".length;
    const proseTransaction = state.update({
      changes: {from: proseInsertion, insert: " ordinary"},
    });
    const mapped = controller.index(proseTransaction.state);
    expect(mapped.topologyIdentity).toBe(initial.topologyIdentity);
    expect(controller.topologyWasMapped(proseTransaction)).toBe(true);

    const structuralTransaction = proseTransaction.state.update({
      changes: {from: proseTransaction.state.doc.length, insert: "\n\n**New**"},
    });
    const rebuilt = controller.index(structuralTransaction.state);
    expect(rebuilt.topologyIdentity).not.toBe(mapped.topologyIdentity);
    expect(metrics).toContain("projection-index");
  });

  it("owns a complete syntax catalog beyond CodeMirror's initial viewport", () => {
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: () => {},
    });
    const source = `${"ordinary prose ".repeat(300)}\n\n$x$.`;
    const state = EditorState.create({
      doc: source,
      extensions: [scholiumNoteLanguage, controller.extension],
    });

    expect(controller.index(state).mathExpressions.map((expression) => expression.content))
      .toEqual(["x"]);
  });

  it("indexes exact list prefixes for marker-scoped source reveal", () => {
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: () => {},
    });
    const source = [
      "- root",
      "  - nested",
      "",
      "10. ordered",
      "",
      "- [ ] task",
      "* [x] alternate task",
    ].join("\n");
    const state = EditorState.create({
      doc: source,
      extensions: [scholiumNoteLanguage, controller.extension],
    });
    const initial = controller.index(state);

    expect(initial.listPrefixRanges.map((range) =>
      source.slice(range.from, range.to)))
      .toEqual(["- ", "  - ", "10. ", "- [ ] ", "* [x] "]);
    expect(initial.taskItemRanges.map((range) =>
      source.slice(range.markerFrom, range.markerTo)))
      .toEqual(["[ ]", "[x]"]);

    const insertionPoint = source.indexOf("nested") + "nested".length;
    const transaction = state.update({
      changes: {from: insertionPoint, insert: " prose"},
    });
    const mapped = controller.index(transaction.state);
    expect(mapped.topologyIdentity).toBe(initial.topologyIdentity);
    const oracle = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const fresh = EditorState.create({doc: transaction.newDoc, extensions: [scholiumNoteLanguage, oracle.extension]});
    expect(mapped).toEqual(oracle.index(fresh));
    expect(mapped.listPrefixRanges.map((range) =>
      transaction.state.doc.sliceString(range.from, range.to)))
      .toEqual(["- ", "  - ", "10. ", "- [ ] ", "* [x] "]);
    expect(mapped.taskItemRanges.map((range) =>
      transaction.state.doc.sliceString(range.markerFrom, range.markerTo)))
      .toEqual(["[ ]", "[x]"]);
  });

  it("keeps an empty or continued item prefix on its marker line", () => {
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: () => {},
    });
    const source = [
      "-",
      "  continued body",
      "",
      "- [ ]",
      "  continued task body",
    ].join("\n");
    const state = EditorState.create({
      doc: source,
      extensions: [scholiumNoteLanguage, controller.extension],
    });
    const ranges = controller.index(state).listPrefixRanges;

    expect(ranges.map((range) => source.slice(range.from, range.to)))
      .toEqual(["-", "- "]);
    expect(ranges.every((range) => range.to <= state.doc.lineAt(range.from).to))
      .toBe(true);
  });

  it("leaves parent block markers outside nested list prefixes", () => {
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: () => {},
    });
    const source = [
      "> - quoted item",
      "",
      "> [!state] Callout",
      "> - callout item",
      "",
      "[^1]: - footnote item",
    ].join("\n");
    const state = EditorState.create({
      doc: source,
      extensions: [scholiumNoteLanguage, controller.extension],
    });
    const prefixes = controller.index(state).listPrefixRanges.map((range) => ({
      text: source.slice(range.from, range.to),
      line: state.doc.lineAt(range.from),
      from: range.from,
    }));

    expect(prefixes.map((prefix) => prefix.text)).toEqual([" - ", " - ", " - "]);
    expect(prefixes.every((prefix) => prefix.from > prefix.line.from)).toBe(true);
  });

  it("extends a proven Callout across its trailing quote-only edit line", () => {
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: () => {},
    });
    const source = "> [!state] Claim\n> ";
    const state = EditorState.create({
      doc: source,
      extensions: [scholiumNoteLanguage, controller.extension],
    });
    const index = controller.index(state);

    expect(index.syntax.blocks.find((block) => block.kind === "callout")?.to)
      .toBeLessThan(source.length);
    expect(index.callouts).toEqual([{from: 0, to: source.length}]);
  });

  it("rebuilds Callout topology when Return appends a quote-only line", () => {
    const controller = createLiveProjectionIndexController({
      editingDialect: () => dialect,
      recordMetric: () => {},
    });
    const source = "> [!state] Claim";
    const state = EditorState.create({
      doc: source,
      selection: {anchor: source.length},
      extensions: [scholiumNoteLanguage, controller.extension],
    });
    const initial = controller.index(state);
    const continued = source + "\n> ";
    const transaction = state.update({
      changes: {from: source.length, insert: "\n> "},
      selection: {anchor: continued.length},
    });
    const next = controller.index(transaction.state);

    expect(next.topologyIdentity).not.toBe(initial.topologyIdentity);
    expect(next.callouts).toEqual([{from: 0, to: continued.length}]);
    expect(next.syntax.blocks.find((block) => block.kind === "callout")?.markerRanges
      .map((range) => continued.slice(range.from, range.to)))
      .toEqual([">", "[!state]", ">"]);
  });
});
