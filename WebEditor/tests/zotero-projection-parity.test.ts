import {EditorSelection, EditorState, StateEffect} from "@codemirror/state";
import {history, redo, undo} from "@codemirror/commands";
import {ensureSyntaxTree} from "@codemirror/language";
import {DOMParser} from "linkedom";
import {describe, expect, it, vi} from "vitest";
import {createMarkdownDocumentState} from "../bootstrap";
import {exactSourceHistory, exactSourceState} from "../exact-source-history";
import {scholiumMarkdownContentLanguage, scholiumNoteLanguage} from "../language";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {citationHistory, citationState, setCitationData, type ZoteroCitationData} from "../zotero-citation-state";
import {encodeDocumentData, encodeField, markdownVisibleText, projectFields, projectFieldsForState, vendorTextToMarkdown, type FieldInput} from "../zotero-fields";
import {normalizedDocumentText} from "../state";
import * as sourceMapping from "../state";

vi.stubGlobal("DOMParser", DOMParser);
const citation: FieldInput = {id: "cite_a", kind: "citation", code: "ITEM CSL_CITATION synthetic", text: "Author 中文 😀 e\u0301"};
const bibliography: FieldInput = {id: "bib_a", kind: "bibliography", code: "BIBL synthetic CSL_BIBLIOGRAPHY", text: "Author. *Book*."};
const companion: ZoteroCitationData = {schemaVersion: 1, fields: [citation, bibliography],
  acceptedFields: [citation, bibliography].map(({id, code}) => ({id, code}))};
const compact = `[${citation.text}](cite:${citation.id})`;
function initial(source: string, managed = true, language = true, data = companion) {
  return createMarkdownDocumentState(source,
    [history(), exactSourceHistory, citationHistory, ...(language ? [scholiumNoteLanguage] : [])],
    managed ? {citationSnapshot: {noteID: "11111111-1111-1111-1111-111111111111",
      vaultID: "22222222-2222-2222-2222-222222222222", status: "available", data,
      sourceFingerprint: {sha256: "a".repeat(64), byteCount: new TextEncoder().encode(source).byteLength}}} : undefined);
}
function expectProjection(state: EditorState, managed = true) {
  const source = state.field(exactSourceState).text;
  const projection = projectFieldsForState(state);
  expect(projection).toEqual(projectFields(source, managed ? state.field(citationState)?.data ?? null : undefined));
  for (const field of projection.fields) {
    expect(source.slice(field.fallbackRange.from, field.fallbackRange.to)).not.toBe("");
    expect(source.slice(field.range.from, field.range.to)).toContain(field.kind === "citation" ? "](" : "<!--");
  }
  return projection;
}

describe("citation projection shares complete editor syntax", () => {
  it.each([
    "Author 中文 😀 e\u0301", "<i>Author</i> &amp; <b>Work</b>",
    "<i><i>Nested</i></i><i>Adjacent</i>",
    '<div class="csl-bib-body"><div class="csl-entry">First <i>work</i>.</div><div class="csl-entry">Second &amp; third.</div></div>',
  ])("reuses validated vendor text only for identical generated Markdown: %s", html => {
    const field: FieldInput = {...citation, text: html};
    const kind = html.startsWith("<div") ? "bibliography" : "citation";
    field.kind = kind;
    for (const newline of ["\n", "\r\n"]) {
      const source = encodeField(field, newline);
      const projection = projectFields(source);
      expect(projection.diagnostics).toEqual([]);
      const projected = projection.fields[0];
      const fallback = source.slice(projected.fallbackRange.from, projected.fallbackRange.to);
      expect(projected.text).toBe(markdownVisibleText(fallback));
      expect(projected.manualTextChanged).toBe(false);
      expect(projected.cachedText).toBe(html);
      expect(projected.code).toBe(field.code);
    }
  });

  it("avoids duplicate rendering while still parsing every manually changed fallback", () => {
    const field: FieldInput = {...citation, text: "Author &amp; <i>work</i>"};
    const generated = vendorTextToMarkdown(field.text);
    for (const fallback of [generated, "Handwritten **different** text", generated.replace("\\&", "&")]) {
      const parser = vi.spyOn(DOMParser.prototype, "parseFromString");
      let projection;
      try {
        projection = projectFields(`[${fallback}](cite:${field.id})`, {schemaVersion: 1, fields: [field]});
        expect(parser.mock.calls).toHaveLength(fallback === generated ? 2 : 3);
      } finally { parser.mockRestore(); }
      expect(projection.diagnostics).toEqual([]);
      expect(projection.fields[0].text).toBe(markdownVisibleText(fallback));
      expect(projection.fields[0].manualTextChanged).toBe(fallback !== generated);
    }
    const unsupported = projectFields(`[Readable](cite:${field.id})`, {
      schemaVersion: 1, fields: [{...field, text: "<i>Unclosed vendor text"}],
    });
    expect(unsupported.fields).toEqual([]);
    expect(unsupported.diagnostics.map(value => value.kind)).toContain("unsupported-text");
  });

  it("reuses successful vendor rendering across ordinary body input without retaining an old source catalog", () => {
    const field = {...citation, text: "Author <i>work</i>"};
    const source = `\ufeffLead 中文 😀 e\u0301.\r\n\r\n[${vendorTextToMarkdown(field.text)}](cite:${field.id})`;
    const controller = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
    let state = initial(source, true, true, {schemaVersion: 1, fields: [field]});
    expect(ensureSyntaxTree(state, state.doc.length, 1_000)).not.toBeNull();
    state = state.update({effects: StateEffect.appendConfig.of(controller.extension)}).state;
    const original = controller.index(state).zoteroFields;
    expect(original.fields).toHaveLength(1);
    const parser = vi.spyOn(DOMParser.prototype, "parseFromString");
    try {
      for (const insert of ["x", "文", "e\u0301"]) {
        const transaction = state.update({changes: {from: 3, insert}, userEvent: "input.type"});
        state = transaction.state;
        expect(controller.topologyWasMapped(transaction)).toBe(true);
        const projection = controller.index(state).zoteroFields;
        expect(projection).not.toBe(original);
        expect(projection.source).toBe(state.field(exactSourceState).text);
        expect(projection.fields[0].text).toBe("Author work");
      }
      expect(parser).not.toHaveBeenCalled();
    } finally { parser.mockRestore(); }
    expectProjection(state);
    expect(original.source).toBe(source);
  });

  it("revalidates exact vendor text changes on the same field object and never reuses success for invalid HTML", () => {
    const field = {...citation, text: "Cafe\u0301"};
    const source = `Lead.\n\n[${field.text}](cite:${field.id})`;
    let state = initial(source, true, true, {schemaVersion: 1, fields: [field]});
    expectProjection(state);
    const parser = vi.spyOn(DOMParser.prototype, "parseFromString");
    try {
      for (const text of ["Café", "<script>Invalid</script>", "Cafe\u0301"]) {
        field.text = text;
        state = state.update({changes: {from: 2, insert: "x"}}).state;
        const projection = projectFieldsForState(state);
        if (text.startsWith("<script>")) {
          expect(projection.fields).toEqual([]);
          expect(projection.diagnostics.map(value => value.kind)).toContain("unsupported-text");
        } else {
          expect(parser.mock.calls).toHaveLength(text === "Café" ? 3 : 2);
          expect(projection.fields[0]).toMatchObject({cachedText: text, text: "Cafe\u0301", manualTextChanged: text === "Café"});
        }
        expectProjection(state);
        parser.mockClear();
      }
    } finally { parser.mockRestore(); }
  });

  it("rechecks current fallback and newly formed bare reserved tokens after vendor rendering has been reused", () => {
    const field = {...citation, text: "Author <i>work</i>"};
    const source = `Lead scholium-zoter:1:AAAA.\n\n[${vendorTextToMarkdown(field.text)}](cite:${field.id})`;
    let state = initial(source, true, true, {schemaVersion: 1, fields: [field]});
    const initialProjection = expectProjection(state), range = initialProjection.fields[0].fallbackRange;
    state = state.update({changes: {from: range.from, to: range.to, insert: "Handwritten **different** text"}}).state;
    const parser = vi.spyOn(DOMParser.prototype, "parseFromString");
    try {
      const projection = projectFieldsForState(state);
      expect(parser.mock.calls).toHaveLength(1);
      expect(projection.fields[0]).toMatchObject({text: "Handwritten different text", manualTextChanged: true});
    } finally { parser.mockRestore(); }
    expectProjection(state);
    const from = state.doc.toString().indexOf("zoter:") + "zoter".length;
    state = state.update({changes: {from, insert: "o"}}).state;
    expect(expectProjection(state).diagnostics.map(value => value.kind)).toContain("malformed-envelope");
  });

  it("scans a closed-YAML body's reserved tokens once and keeps unclosed metadata inert", () => {
    const source = "\ufeff---\r\nexample: 'cite:missing'\r\n---\r\n\r\n" + "Lead 中文.\r\n\r\n".repeat(256) + compact;
    const state = initial(source);
    expect(ensureSyntaxTree(state, state.doc.length, 1_000)).not.toBeNull();
    const completeScan = vi.spyOn(state.doc, "iter"), bodyScan = vi.spyOn(state.doc, "iterRange");
    try {
      expect(projectFieldsForState(state).fields.map(field => field.id)).toEqual([citation.id]);
      expect(completeScan).not.toHaveBeenCalled();
      expect(bodyScan).toHaveBeenCalledTimes(1);
    } finally {completeScan.mockRestore(); bodyScan.mockRestore();}
    for (const source of ["---\nexample: 'cite:missing'\n---\nBody", "---\nexample: 'keep'\n" + compact]) {
      const state = initial(source);
      expect(expectProjection(state).fields).toEqual([]);
    }
  });

  it.each(["\n", "\r\n", "mixed"])("admits exact citation ranges after input and Undo/Redo without normalizing long prefixes: %j", newline => {
    for (const managed of [true, false]) {
      const carrier = managed ? compact : encodeField(citation);
      let source = `\ufeff---\nunknown: keep\n---\n\n${"Lead 中文 😀 e\u0301.\n\n".repeat(256)}${carrier}\nTail`;
      source = newline === "mixed" ? source.replaceAll("\n\n", "\r\n\n") : source.replaceAll("\n", newline);
      const controller = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
      let state = initial(source, managed);
      expect(ensureSyntaxTree(state, state.doc.length, 1_000)).not.toBeNull();
      state = state.update({effects: StateEffect.appendConfig.of(controller.extension)}).state;
      const expectAdmission = () => {
        const projection = expectProjection(state, managed);
        const expected = projection.fields.filter(field => field.kind === "citation").map(field => ({
          from: normalizedDocumentText(projection.source.slice(0, field.range.from)).length,
          to: normalizedDocumentText(projection.source.slice(0, field.range.to)).length,
        }));
        expect(controller.index(state).syntax.inlines.filter(inline => inline.kind === "citation")
          .map(({from, to}) => ({from, to}))).toEqual(expected);
        expect(expected).toHaveLength(1);
      };
      expectAdmission();
      const from = normalizedDocumentText(source).indexOf("Lead") + 2;
      state = state.update({selection: {anchor: from}}).state;
      const normalization = vi.spyOn(sourceMapping, "normalizedDocumentText");
      try {
        const insert = "文😀e\u0301";
        const transaction = state.update({changes: {from, insert}, selection: {anchor: from + insert.length}, userEvent: "input.type"});
        state = transaction.state;
        expect(controller.topologyWasMapped(transaction)).toBe(true);
        // A citation near EOF must not cause prefix-sized normalizations on
        // each ordinary edit. Small inserted/vendor fragments remain valid.
        expect(normalization.mock.calls.filter(([text]) => text.length > source.length / 2)).toHaveLength(0);
      } finally { normalization.mockRestore(); }
      expectAdmission();
      expect(undo({state, dispatch: transaction => {state = transaction.state;}})).toBe(true);
      expect(state.field(exactSourceState).text).toBe(source);
      expectAdmission();
      expect(redo({state, dispatch: transaction => {state = transaction.state;}})).toBe(true);
      expectAdmission();
    }
  });

  it("admits embedded citations in normalized states without an exact-source field", () => {
    const carrier = encodeField(citation), source = "\ufeffLead 中文 😀.\n\n" + carrier;
    const controller = createLiveProjectionIndexController({editingDialect: () => null, recordMetric: () => {}});
    const state = EditorState.create({doc: source, extensions: [scholiumNoteLanguage, controller.extension]});
    const admitted = controller.index(state).syntax.inlines.filter(inline => inline.kind === "citation");
    expect(admitted.map(({from, to}) => ({from, to}))).toEqual([{from: source.indexOf(carrier), to: source.length}]);
  });

  it("compares accepted occurrence signatures by values regardless of JSON object key order", () => {
    const data: ZoteroCitationData = {schemaVersion: 1, fields: [citation],
      acceptedFields: [{code: citation.code, id: citation.id}]};
    expect(projectFields(compact, data).citationStateStale).toBe(false);
    expect(projectFields(compact, {...data, acceptedFields: [{code: "changed", id: citation.id}]}).citationStateStale).toBe(true);
    const second = {...citation, id: "cite_b"};
    expect(projectFields(compact + "\n\n" + compact.replace("cite_a", "cite_b"), {
      schemaVersion: 1, fields: [citation, second],
      acceptedFields: [second, citation].map(({id, code}) => ({code, id})),
    }).citationStateStale).toBe(true);
  });

  it.each(["\n", "\r\n", "mixed"])("preserves exact locators across managed and embedded metadata: %j", newline => {
    for (const managed of [true, false]) {
      const citationSource = managed ? compact : encodeField(citation);
      const bibliographySource = managed ? `<!--cite-bibliography:bib_a-->\n\nAuthor. *Book*.\n\n<!--/cite-bibliography-->` : encodeField(bibliography);
      const documentSource = managed ? "" : encodeDocumentData("<data />", undefined, [citation, bibliography].map(({id, code}) => ({id, code}))) + "\n\n";
      let source = `\ufeff---\nunknown: '[Ignored](cite:missing)' # authored\n---\n\n${documentSource}Lead 中文 😀 e\u0301.\n\n${citationSource}\n\n${bibliographySource}\nTail`;
      source = newline === "mixed" ? source.replaceAll("\n\n", "\r\n\n") : source.replaceAll("\n", newline);
      const state = initial(source, managed);
      expect(ensureSyntaxTree(state, state.doc.length, 1_000)).not.toBeNull();
      const projection = expectProjection(state, managed);
      expect(projection.diagnostics).toEqual([]);
      expect(projection.fields.map(field => field.id)).toEqual(["cite_a", "bib_a"]);
      expect(source.slice(projection.fields[0].range.from, projection.fields[0].range.to)).toBe(citationSource);
    }
  });

  it.each([
    "`FIELD`", "```markdown\nFIELD\n```", "    FIELD", "<!-- example FIELD -->", "%% FIELD %%",
    "<div>\nFIELD\n</div>", "Before <span>FIELD</span> after.", "Before <span>FIELD</div> after.",
    "# FIELD", "- FIELD", "> FIELD", "[^a]: FIELD", "^[FIELD]", "| X |\n| - |\n| FIELD |",
    "---\nexample: 'FIELD'\n---\nBody", "---\nexample: 'FIELD'\nBody",
    "FIELD\n\nFIELD", "[Unknown](cite:missing)", "[Broken](scholium-zotero:2:AAAA)",
    " <!--cite-bibliography:bib_a-->\n\nAuthor.\n\n<!--/cite-bibliography-->",
  ])("keeps literal, unsupported and malformed authority unchanged: %s", template => {
    const source = template.replaceAll("FIELD", compact), state = initial(source);
    expect(ensureSyntaxTree(state, state.doc.length, 1_000)).not.toBeNull();
    expectProjection(state);
  });

  it("does not reparse the complete Markdown when the current editor tree is complete", () => {
    const source = "Ordinary prose 中文 😀 e\u0301.\n\n".repeat(128) + compact;
    const state = initial(source);
    expect(ensureSyntaxTree(state, state.doc.length, 1_000)).not.toBeNull();
    const parsers = [vi.spyOn(scholiumMarkdownContentLanguage.language.parser, "parse"),
      vi.spyOn(scholiumNoteLanguage.language.parser, "parse")];
    try {
      const projection = projectFieldsForState(state);
      expect(projection.fields[0].id).toBe(citation.id);
      for (const parser of parsers) {
        expect(parser.mock.calls.some(([input]) => typeof input === "string" && input.length >= state.doc.length)).toBe(false);
      }
      expect(projectFieldsForState(state.update({selection: {anchor: 7}}).state)).toBe(projection);
    } finally { for (const parser of parsers) parser.mockRestore(); }
  });

  it("retains complete-source validation without an available editor parser", () => {
    const source = "Lead.\n\n" + compact, state = initial(source, true, false);
    expect(ensureSyntaxTree(state, state.doc.length, 0)).toBeNull();
    const parser = vi.spyOn(scholiumNoteLanguage.language.parser, "parse");
    try {
      expectProjection(state);
      expect(parser.mock.calls.some(([input]) => input === source)).toBe(true);
    } finally { parser.mockRestore(); }
  });

  it.each(["'<span>'", "'</div>'", "|\n  ```markdown", "|\n  <!-- unclosed"])(
    "keeps closed YAML inert to body citation parsing: %s", value => {
      const source = `---\nexample: ${value}\n---\n\n${compact}`;
      const state = initial(source);
      expect(ensureSyntaxTree(state, state.doc.length, 1_000)).not.toBeNull();
      const projection = expectProjection(state);
      expect(projection.fields.map(field => field.id)).toEqual([citation.id]);
      expect(projection.diagnostics).toEqual([]);
    },
  );

  it("rechecks reserved diagnostics and companion changes through exact-source Undo/Redo", () => {
    const source = `\ufeffLead scholium-zoter o:1:AAAA 中文 😀 e\u0301.\r\n\r\n${compact}`;
    let state = initial(source);
    expect(ensureSyntaxTree(state, state.doc.length, 1_000)).not.toBeNull();
    expect(expectProjection(state).diagnostics).toEqual([]);
    const space = normalizedDocumentText(source).indexOf("zoter o") + 5;
    state = state.update({selection: EditorSelection.single(space)}).state;
    state = state.update({changes: {from: space, to: space + 1}, selection: {anchor: space}, userEvent: "delete.backward"}).state;
    expect(expectProjection(state).diagnostics.map(diagnostic => diagnostic.kind)).toContain("malformed-envelope");
    const changed = state.field(exactSourceState).text;
    expect(undo({state, dispatch: transaction => {state = transaction.state;}})).toBe(true);
    expect(state.field(exactSourceState).text).toBe(source);
    expect(expectProjection(state).diagnostics).toEqual([]);
    expect(redo({state, dispatch: transaction => {state = transaction.state;}})).toBe(true);
    expect(state.field(exactSourceState).text).toBe(changed);
    expectProjection(state);
    state = state.update({effects: setCitationData.of({...companion, fields: [bibliography]})}).state;
    expect(expectProjection(state).fields).toEqual([]);
    expect(projectFieldsForState(state).diagnostics.length).toBeGreaterThan(0);
  });
});
