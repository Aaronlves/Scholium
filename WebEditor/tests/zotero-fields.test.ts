import {EditorState, Transaction} from "@codemirror/state";
import {history, redo, undo, undoDepth} from "@codemirror/commands";
import {DOMParser} from "linkedom";
import {readFileSync} from "node:fs";
import {describe, expect, it, vi} from "vitest";
import {exactSourceHistory, exactSourceState, setExactSource} from "../exact-source-history";
import {scholiumNoteLanguage} from "../language";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {appendMarkdownBlocks} from "../markdown-fragment";
import {normalizedDocumentText} from "../state";
import {citationLinkSource, encodeOpaque, maximumEnvelopeLength} from "../zotero-field-envelope";
import {encodeDocumentData, encodeField, fieldMetadataRanges, fieldOperationTransaction, isCompletedFieldCode,
  citationInsertionContextSupported, markdownVisibleText, projectFields, projectFieldsForState, stageFieldOperation, vendorTextToMarkdown,
  type FieldInput} from "../zotero-fields";
import {renderedFormatting, unrepresentableVendorBlocks, unrepresentableVendorFormatting, vendorFormattingFixtures} from "./zotero-formatting-fixtures";

vi.stubGlobal("DOMParser", DOMParser);
const code = (id: number, plain = "(Fang, 2026)") => `ITEM CSL_CITATION {"citationID":"vendor-${id}","citationItems":[{"id":${id},"uris":["http://zotero.org/users/1/items/ABCDEFGH"]}],"properties":{"plainCitation":${JSON.stringify(plain)}}}`;
const bibCode = 'BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY';
const citation: FieldInput = {id: "cite_a", kind: "citation", code: code(1), text: "(Fang, 2026)"};
const bibliography: FieldInput = {id: "bib_a", kind: "bibliography", code: bibCode,
  text: '<div class="csl-bib-body"><div class="csl-entry">Fang. <i>Book.</i></div><div class="csl-entry">Other.</div></div>'};
const style = {firstLineIndent: -720, indent: 720, lineSpacing: 480, entrySpacing: 240, tabStops: [720]};
function initial(source: string) {
  return EditorState.create({doc: normalizedDocumentText(source), selection: {anchor: 3},
    extensions: [history(), exactSourceHistory, scholiumNoteLanguage, EditorState.lineSeparator.of("\n")]})
    .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
}
function perform(state: EditorState, command: typeof undo) {
  let next = state;
  expect(command({state, dispatch: transaction => {next = transaction.state;}})).toBe(true);
  return next;
}
function acceptedSource(fields: FieldInput[]) {
  return encodeDocumentData("<data unknown='keep'>\r\n😀</data>", style, fields.map(({id, code}) => ({id, code})))
    + "\n\n" + fields.map(field => encodeField(field)).join("\n\n");
}

describe("source-owned Zotero Markdown fields", () => {
  it("reads a paragraph-leading ordinary Markdown label without custom link navigation", () => {
    const source = encodeField({...citation, text: "<i>Fang</i> &amp; <b>Li</b> [2026]"});
    const projection = projectFields(source);
    expect(projection.diagnostics).toEqual([]);
    expect(projection.fields[0]).toMatchObject({id: "cite_a", text: "Fang & Li [2026]", cachedText: "<i>Fang</i> &amp; <b>Li</b> [2026]", manualTextChanged: false});
    expect(source.slice(projection.fields[0].fallbackRange.from, projection.fields[0].fallbackRange.to)).toBe("*Fang* \\& **Li** \\[2026\\]");
    const document = new DOMParser().parseFromString("<html><body></body></html>", "text/html");
    appendMarkdownBlocks(source, document.body);
    expect(document.body.textContent).toBe("Fang & Li [2026]");
    expect(document.querySelector(".cm-live-citation")).not.toBeNull();
    expect(document.querySelector("[data-scholium-link-target],a")).toBeNull();
  });

  it("returns the current rendered fallback and separately reports changes from the vendor cache", () => {
    const original = encodeField({...citation, text: "Original"});
    const changed = original.replace("[Original]", "[Manual **change** &amp; 😀]");
    const field = projectFields(changed).fields[0];
    expect(field).toMatchObject({text: "Manual change & 😀", cachedText: "Original", manualTextChanged: true});
    const source = encodeDocumentData("<data />", null, [{id: field.id, code: field.code}]) + "\n\n" + changed;
    expect(projectFields(source).citationStateStale).toBe(false);
    expect(stageFieldOperation(projectFields(source), {acceptCurrentFields: true}).source).toBe(source);
  });

  it("preserves exact opaque Unicode, mixed newline bytes, BOM and unchanged spans in one Undo", () => {
    const field = {...citation, code: code(1) + "\n", text: "<i>作者</i> é 😀"};
    const source = "\uFEFF---\r\nunknown: 'keep' # comment\n---\r\nArgument " + encodeField(field)
      + "\r\n\nTail é 😀 with no final newline";
    const state = initial(source), before = projectFields(source);
    expect(before.fields[0].code).toBe(field.code);
    expect(before.fields[0].cachedText).toBe(field.text);
    const staged = stageFieldOperation(before, {updates: [{id: field.id, code: code(2), text: "(Updated, 2025)"}],
      documentData: "\r\n<data vendor='opaque'>😀 é</data>\n", bibliographyStyle: style, acceptCurrentFields: true});
    expect(staged.source.startsWith("\uFEFF---\r\nunknown: 'keep' # comment\n---\r\n")).toBe(true);
    expect(staged.source.endsWith("\r\n\nTail é 😀 with no final newline")).toBe(true);
    expect(projectFields(staged.source).citationStateStale).toBe(false);
    let current = state.update(fieldOperationTransaction(state, staged)!).state;
    expect(current.field(exactSourceState).text).toBe(staged.source);
    expect(undoDepth(current)).toBe(1);
    current = perform(current, undo);
    expect(current.field(exactSourceState).text).toBe(source);
    expect(current.selection.eq(state.selection)).toBe(true);
    current = perform(current, redo);
    expect(current.field(exactSourceState).text).toBe(staged.source);
  });

  it("retains bibliography vendor strings and styles alongside separated readable paragraphs", () => {
    const source = acceptedSource([citation, bibliography]), projection = projectFields(source);
    expect(projection.diagnostics).toEqual([]);
    expect(projection.fields.map(field => field.text)).toEqual(["(Fang, 2026)", "Fang. Book.Other."]);
    expect(projection.fields[1].cachedText).toBe(bibliography.text);
    expect(projection.bibliographyStyle).toEqual(style);
    expect(projection.acceptedFields).toEqual([citation, bibliography].map(({id, code}) => ({id, code})));
    expect(projection.citationStateStale).toBe(false);
    expect(fieldMetadataRanges(projection)).toHaveLength(3);
  });

  it("sets new document preferences after frontmatter-only source without replacing its original bytes", () => {
    const data = "<data><style id='synthetic' /><prefs fieldType='Http' /></data>";
    for (const newline of ["\n", "\r\n"]) for (const bom of ["", "\uFEFF"]) {
      const source = bom + ["---", "unknown: 'keep' # authored comment", "---"].join(newline);
      const staged = stageFieldOperation(projectFields(source), {documentData: data, bibliographyStyle: style, acceptCurrentFields: true});
      const marker = encodeDocumentData(data, style, []), projected = projectFields(staged.source);
      expect(staged.source).toBe(source + newline + marker + newline + newline);
      expect(staged.changes).toEqual([{from: source.length, to: source.length, expected: "", insert: newline + marker + newline + newline}]);
      expect(projected).toMatchObject({documentData: data, bibliographyStyle: style, acceptedFields: [], citationStateStale: false, diagnostics: []});
      expect(projected.documentRange).toEqual({from: source.length + newline.length, to: source.length + newline.length + marker.length});
    }
  });

  it("requires canonical metadata-only lines and admits a separate initial BOM", () => {
    const marker = encodeDocumentData("<data />", null, []);
    expect(projectFields("\uFEFF" + marker).documentRange).toEqual({from: 1, to: marker.length + 1});
    for (const source of [" " + marker, "   " + marker, marker + " ", marker + "\t"]) {
      const projection = projectFields(source);
      expect(projection.documentRange).toBeNull();
      expect(projection.diagnostics.length).toBeGreaterThan(0);
      expect(fieldMetadataRanges(projection)).toEqual([]);
      expect(() => stageFieldOperation(projection, {documentData: "<new />"})).toThrow(/diagnostics/);
    }
  });

  it.each(["\n", "\r\n"])("keeps extra edge blank lines inside the exact bibliography fallback (%j)", newline => {
    const source = encodeField(bibliography, newline).replace("-->" + newline + newline, "-->" + newline.repeat(3))
      .replace(newline + newline + "<!--/", newline.repeat(3) + "<!--/");
    const projection = projectFields(source), field = projection.fields[0];
    expect(projection.diagnostics).toEqual([]);
    expect(source.slice(field.fallbackRange.from, field.fallbackRange.to))
      .toBe(newline + vendorTextToMarkdown(bibliography.text, newline) + newline);
    expect(field.text).toBe("Fang. Book.Other.");
    expect(field.manualTextChanged).toBe(true);
  });

  it("exposes stale membership, order and code, including removing every field", () => {
    const other = {...citation, id: "cite_b", code: code(2), text: "(Li, 2025)"};
    const marker = encodeDocumentData("<data />", null, [citation, other].map(({id, code}) => ({id, code})));
    for (const body of [encodeField(other) + " " + encodeField(citation), encodeField(citation),
      encodeField({...citation, code: code(3)}) + " " + encodeField(other), "No fields remain."]) {
      expect(projectFields(marker + "\n\n" + body).citationStateStale).toBe(true);
    }
    expect(projectFields(encodeField(citation)).citationStateStale).toBe(true);
    expect(projectFields(encodeDocumentData("<data />", null, [])).citationStateStale).toBe(false);
  });

  it.each(["", " ", "\t", "\n", "\r\n", "\n\n", "\u00a0"])(
    "reports adjacency only to the immediately touching next citation (%j)", separator => {
      const source = [citation, {...citation, id: "cite_b", code: code(2)}, {...citation, id: "cite_c", code: code(3)}]
        .map(field => encodeField(field)).join(separator);
      const projection = projectFields(source);
      expect(projection.diagnostics).toEqual([]);
      expect(projection.fields.map(field => field.adjacent)).toEqual(separator === "" ? [true, true, false] : [false, false, false]);
    });

  it("never reports a bibliography as the previous or next adjacent citation", () => {
    const source = [citation, bibliography, {...citation, id: "cite_b", code: code(2)}].map(field => encodeField(field)).join("\n\n");
    const projection = projectFields(source);
    expect(projection.diagnostics).toEqual([]);
    expect(projection.fields.map(field => field.adjacent)).toEqual([false, false, false]);
  });

  it("makes copied occurrence IDs inert and blocks all mutation and metadata hiding", () => {
    const source = encodeField(citation) + " " + encodeField(citation), projection = projectFields(source);
    expect(projection.fields).toEqual([]);
    expect(projection.diagnostics.map(diagnostic => diagnostic.kind)).toEqual(["duplicate-id", "duplicate-id"]);
    expect(fieldMetadataRanges(projection)).toEqual([]);
    expect(() => stageFieldOperation(projection, {documentData: "<data />"})).toThrow(/diagnostics/);
  });

  it("refuses duplicate document authority", () => {
    const marker = encodeDocumentData("<data />");
    const projection = projectFields(marker + "\n\n" + marker + "\n\n" + encodeField(citation));
    expect(projection.documentData).toBeNull();
    expect(projection.documentRange).toBeNull();
    expect(projection.diagnostics.some(diagnostic => diagnostic.kind === "duplicate-document")).toBe(true);
    expect(fieldMetadataRanges(projection)).toEqual([]);
  });

  it.each(["`FIELD`", "```markdown\nFIELD\n```", "    FIELD", "---\nexample: 'FIELD'\n---\nBody",
    "<!-- example FIELD -->", "%% FIELD %%", "<div>\nFIELD\n</div>", "Before <span>FIELD</span> after."])(
    "never gains authority from literal or raw HTML context: %s", template => {
      const source = template.replace("FIELD", encodeField(citation));
      expect(projectFields(source).fields).toEqual([]);
      const at = source.indexOf("scholium-zotero:");
      expect(() => stageFieldOperation(projectFields(source), {insertions: [{at, field: {...citation, id: "new_a"}}]})).toThrow();
    });

  it.each(["# FIELD", "- FIELD", "> FIELD", "[^a]: FIELD", "^[FIELD]", "| X |\n| - |\n| FIELD |"])(
    "rejects unsupported semantic container: %s", template => {
      const projection = projectFields(template.replace("FIELD", encodeField(citation)));
      expect(projection.fields).toEqual([]);
      expect(projection.diagnostics.length).toBeGreaterThan(0);
    });

  it.each(["[Visible](scholium-zotero:2:AAAA)", "[Visible](scholium-zotero:1:AAAA)", "<!--/scholium-zotero-field-->"])(
    "diagnoses malformed and unsupported carriers without URL authority: %s", source => {
      const projection = projectFields(source);
      expect(projection.fields).toEqual([]);
      expect(projection.diagnostics.length).toBeGreaterThan(0);
      expect(() => stageFieldOperation(projection, {documentData: "<data />"})).toThrow();
    });

  it("keeps ordinary prose mentioning the reserved name and ordinary links nonauthorizing", () => {
    const source = "[About scholium-zotero:](https://example.com)";
    expect(projectFields(source).fields).toEqual([]);
    expect(projectFields(source).diagnostics).toEqual([]);
    const document = new DOMParser().parseFromString("<html><body></body></html>", "text/html");
    appendMarkdownBlocks(source, document.body);
    expect(document.querySelector(".cm-live-citation")).toBeNull();
  });

  it("rejects nested, unseparated and raw-HTML overlapping bibliography blocks", () => {
    const valid = encodeField(bibliography);
    for (const source of [valid.replace("-->\n\n", "-->\n"), valid.replace("\n\n<!--/", "\n<!--/"),
      valid.replace("Fang\\.", encodeDocumentData("<nested />") + "\n\nFang\\."), valid.replace("Fang\\.", "<div>Fang\\.")]) {
      const projection = projectFields(source);
      expect(projection.fields).toEqual([]);
      expect(projection.diagnostics.length).toBeGreaterThan(0);
    }
  });

  it("converts only representable vendor HTML and rejects style loss", () => {
    expect(vendorTextToMarkdown("<p>A &amp; B</p><p><i>Book</i> <b>Title</b></p>"))
      .toBe("A \\& B\n\n*Book* **Title**");
    expect(markdownVisibleText("&amp; &nbsp; &#x1F600; &copy; &unknownentity;"))
      .toBe("& \u00a0 😀 © &unknownentity;");
    for (const html of ["<span style='font-variant:small-caps'>Caps</span>", "<sup>1</sup>", "<sub>2</sub>",
      '<a href="https://example.com">Link</a>', "<i> leading</i>", "<i>unclosed", "<i>bad</b>",
      '<div class="csl-left-margin">1.</div>', '<div class="CSL-ENTRY">Entry.</div>', "<p><p>nested</p></p>"]) {
      expect(() => vendorTextToMarkdown(html)).toThrow();
    }
  });

  it.each(vendorFormattingFixtures)("preserves the actual Markdown projection of $name", ({html, kind, paragraphs}) => {
    const markdown = vendorTextToMarkdown(html);
    expect(renderedFormatting(markdown)).toEqual(paragraphs);
    const field = {...citation, kind, code: kind === "citation" ? citation.code : bibCode, text: html};
    const source = encodeField(field), projection = projectFields(source);
    expect(projection.diagnostics).toEqual([]);
    expect(projection.fields[0]).toMatchObject({cachedText: html, manualTextChanged: false});
    expect(renderedFormatting(source)).toEqual(paragraphs);
  });

  it.each([
    ...unrepresentableVendorFormatting.map(html => ({html, field: citation})),
    ...unrepresentableVendorBlocks.map(html => ({html, field: bibliography})),
  ])("refuses vendor text, emphasis or paragraph loss ($html)", ({html, field}) => {
    expect(() => vendorTextToMarkdown(html)).toThrow(/formatting fidelity/);
    const source = acceptedSource([field]);
    expect(() => stageFieldOperation(projectFields(source), {updates: [{id: field.id, text: html}], acceptCurrentFields: true}))
      .toThrow(/formatting fidelity/);
    expect(projectFields(source).citationStateStale).toBe(false);
  });

  it("keeps code-only refresh from erasing manual text, and unlink keeps the exact authored fallback", () => {
    const source = encodeField({...citation, text: "Original"}).replace("[Original]", "[Manual **text** &amp; 😀]");
    const staged = stageFieldOperation(projectFields(source), {updates: [{id: citation.id, code: code(2)}]});
    expect(projectFields(staged.source).fields[0].text).toBe("Manual text & 😀");
    const unlinked = stageFieldOperation(projectFields(staged.source), {updates: [{id: citation.id, unlink: true}]});
    expect(unlinked.source).toBe("Manual **text** &amp; 😀");
    expect(stageFieldOperation(projectFields(source), {updates: [{id: citation.id, delete: true}]}).source).toBe("");
  });

  it("supports ordered kind changes from the actual callback code prefixes", () => {
    const source = "Before " + encodeField(citation) + " after.";
    const block = stageFieldOperation(projectFields(source), {updates: [{id: citation.id, code: bibCode}]});
    expect(projectFields(block.source).fields[0].kind).toBe("bibliography");
    const updated = stageFieldOperation(projectFields(block.source), {updates: [{id: citation.id, text: bibliography.text}]});
    expect(projectFields(updated.source).fields[0].text).toBe("Fang. Book.Other.");
    const codeFirst = stageFieldOperation(projectFields(updated.source), {updates: [{id: citation.id, code: code(2)}]});
    expect(projectFields(codeFirst.source).fields[0].kind).toBe("bibliography");
    const back = stageFieldOperation(projectFields(codeFirst.source), {updates: [{id: citation.id, text: "(Li, 2025)"}]});
    expect(projectFields(back.source).fields[0]).toMatchObject({kind: "citation", text: "(Li, 2025)"});
  });

  it("consumes only the exact approved source query and preserves all outside bytes", () => {
    const source = "\uFEFFArgument @作者 é 😀 tail.\r\n", query = "@作者 é 😀", at = source.indexOf(query);
    const staged = stageFieldOperation(projectFields(source), {insertions: [{at, replacement: {to: at + query.length, expected: query}, field: citation}]});
    expect(staged.source.startsWith("\uFEFFArgument ")).toBe(true);
    expect(staged.source.endsWith(" tail.\r\n")).toBe(true);
    expect(source).toContain(query);
    expect(() => stageFieldOperation(projectFields(source), {insertions: [{at, replacement: {to: at + query.length, expected: "@changed"}, field: citation}]})).toThrow(/query/);
    expect(() => stageFieldOperation(projectFields("😀"), {insertions: [{at: 1, field: citation}]})).toThrow(/boundary/);
    expect(() => stageFieldOperation(projectFields("a\r\nb"), {insertions: [{at: 2, field: citation}]})).toThrow(/boundary/);
  });

  it("rejects stale or forged exact-source patches and oversized opaque state", () => {
    const source = "Argument", state = initial(source);
    const staged = stageFieldOperation(projectFields(source), {insertions: [{at: source.length, field: citation}]});
    expect(fieldOperationTransaction(state.update({changes: {from: 0, insert: "Changed "}}).state, staged)).toBeNull();
    expect(fieldOperationTransaction(state, {...staged, source: staged.source + "forged"})).toBeNull();
    expect(fieldOperationTransaction(state, {...staged, changes: [{...staged.changes[0], expected: "wrong"}]})).toBeNull();
    expect(() => encodeOpaque("x".repeat(maximumEnvelopeLength))).toThrow(/size/);
    expect(() => encodeOpaque("\ud800")).toThrow(/surrogate/);
  });

  it("reuses the exact-source catalog across caret changes and handles split rope tokens", () => {
    const source = acceptedSource([citation]), state = initial(source);
    const catalog = projectFieldsForState(state);
    expect(projectFieldsForState(state.update({selection: {anchor: 5}}).state)).toBe(catalog);
    const carrier = encodeField(citation), split = carrier.indexOf("scholium-zotero:") + 8;
    // Exercise the chunk scanner without relying on rope implementation details.
    const fake = {doc: {iter: function* () {yield carrier.slice(0, split); yield carrier.slice(split);}, toString: () => carrier},
      field: () => undefined} as unknown as EditorState;
    expect(projectFieldsForState(fake).fields[0].id).toBe(citation.id);
    expect(citationLinkSource(carrier)?.field.id).toBe(citation.id);
  });

  it("uses complete catalog identity and context validity for live editor projection", () => {
    const controller = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
    for (const source of [encodeField(citation) + " " + encodeField(citation),
      "Before <span>" + encodeField(citation) + "</span> after.", encodeField(citation) + "\n\n[Broken](scholium-zotero:2:AAAA)"]) {
      const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage, controller.extension]});
      expect(controller.index(state).syntax.inlines.filter(inline => inline.kind === "citation")).toEqual([]);
    }
    const state = EditorState.create({doc: encodeField(citation), extensions: [scholiumNoteLanguage, controller.extension]});
    expect(controller.index(state).syntax.inlines.filter(inline => inline.kind === "citation")).toHaveLength(1);
  });

  it.each([
    ["Paragraph TARGET text.", true], ["# TARGET heading", false], ["- TARGET item", false],
    ["[^a]: TARGET definition", false], ["^[TARGET footnote]", false], ["[TARGET label](https://example.com)", false],
  ] as const)("owns the bounded citation insertion affordance for %s", (source, supported) => {
    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage]});
    expect(citationInsertionContextSupported(state, source.indexOf("TARGET") + 3)).toBe(supported);
  });

  it("shares exact source/range/plain-text/freshness fixtures with native Contracts", () => {
    const fixture = JSON.parse(readFileSync(new URL("../../Tests/ScholiumContractsTests/Fixtures/zotero-field-source-fixtures.json", import.meta.url), "utf8"));
    for (const row of fixture.cases) {
      const projection = projectFields(row.source);
      expect(projection.fields.map(field => field.id), row.name).toEqual(row.ids);
      expect(projection.fields.map(field => field.text), row.name).toEqual(row.plainTexts);
      expect(projection.fields.map(field => field.range), row.name).toEqual(row.fieldRanges);
      expect(projection.fields.map(field => field.fallbackRange), row.name).toEqual(row.fallbackRanges);
      expect(projection.citationStateStale, row.name).toBe(row.stateStale);
      if (row.documentRange !== undefined) expect(projection.documentRange, row.name).toEqual(row.documentRange);
      if (row.diagnosticKinds !== undefined) expect([...new Set(projection.diagnostics.map(diagnostic => diagnostic.kind))].sort(), row.name).toEqual(row.diagnosticKinds);
      if (row.mutationBlocked !== undefined) expect(projection.diagnostics.length > 0, row.name).toBe(row.mutationBlocked);
    }
    for (const row of fixture.completedCodes) expect(isCompletedFieldCode(row), row.code).toBe(row.completed);
  });
});
