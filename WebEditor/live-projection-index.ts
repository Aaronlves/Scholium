import {
  StateField,
  type EditorState,
  type Extension,
  type Text,
  type Transaction,
} from "@codemirror/state";
import {ensureSyntaxTree, syntaxTree} from "@codemirror/language";
import {
  footnotePresentation,
  type FootnotePresentation,
} from "./footnote-presentation";
import type {MathProjection} from "./math";
import type {MarkdownEditingDialect} from "./protocol";
import {
  commandProtectionRanges,
  immutableProjectionRanges,
} from "./projection-index";
import {
  transactionCanMapProjectionTopology,
  transactionChangedSyntaxTree,
  transactionMayCreateProjection,
  type ProjectionSourceRange,
} from "./projection-update";
import {
  mapSemanticProjectionRanges,
  rangeKey,
  semanticProjectionRanges,
  type SemanticProjectionRanges,
} from "./semantic-projection";
import {frontmatterBoundary} from "./state";
import {
  tablePresentation,
  type TablePresentation,
} from "./table-presentation";

export interface SemanticCodeBlockRange extends ProjectionSourceRange {
  readonly fenced: boolean;
  readonly markerRanges: readonly ProjectionSourceRange[];
}

interface SemanticLiteralRanges {
  readonly excluded: readonly Readonly<ProjectionSourceRange>[];
  readonly codeBlocks: readonly Readonly<SemanticCodeBlockRange>[];
}

export interface CalloutPresentation extends ProjectionSourceRange {
  readonly source: string;
}

export interface LiveBlockProjectionRange extends ProjectionSourceRange {
  readonly kind: "table" | "callout" | "footnote" | "math";
}

interface IndexedTablePositionRange extends ProjectionSourceRange {
  readonly position: {row: number; column: number; rowCount: number; columnCount: number};
}

export interface LiveProjectionIndex {
  /** Stable only while local Markdown topology is proven unchanged. */
  readonly topologyIdentity: object;
  readonly syntax: SemanticProjectionRanges;
  readonly literals: SemanticLiteralRanges;
  readonly inlineRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly footnotes: FootnotePresentation;
  readonly tables: readonly TablePresentation[];
  readonly callouts: readonly CalloutPresentation[];
  readonly mathExpressions: readonly MathProjection[];
  readonly frontmatterRange: Readonly<ProjectionSourceRange> | null;
  readonly commandProtectedRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly structuralRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly mutationSensitiveRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly blockRanges: readonly Readonly<LiveBlockProjectionRange>[];
  readonly footnoteRanges: readonly Readonly<ProjectionSourceRange>[];
  readonly tablePositionRanges: readonly Readonly<IndexedTablePositionRange>[];
  readonly hasUnclosedFrontmatter: boolean;
}

export interface LiveProjectionIndexController {
  readonly extension: Extension;
  index(state: EditorState): LiveProjectionIndex;
  topologyWasMapped(transaction: Transaction): boolean;
  visibleInlineMathExpressions(
    state: EditorState,
    coveredRanges: readonly ProjectionSourceRange[],
    index: LiveProjectionIndex,
  ): MathProjection[];
}

interface LiveProjectionIndexOptions {
  editingDialect(): MarkdownEditingDialect | null;
  recordMetric(
    name: string,
    startedAt: number,
    observed?: Record<string, number>,
  ): void;
}

function indexedTablePositionRanges(
  doc: Text,
  tables: readonly TablePresentation[],
) {
  const ranges: IndexedTablePositionRange[] = [];
  for (const table of tables) {
    const rows = [table.header, ...table.body];
    const rowCount = rows.length;
    const columnCount = table.header.length;
    rows.forEach((cells, row) => {
      const first = cells[0];
      if (!first) return;
      const line = doc.lineAt(first.sourceOffset);
      cells.forEach((cell, column) => {
        const next = cells[column + 1];
        ranges.push({
          from: column === 0 ? line.from : cell.sourceOffset,
          to: next?.sourceOffset ?? line.to + 1,
          position: {row, column, rowCount, columnCount},
        });
      });
    });
  }
  return immutableProjectionRanges(ranges);
}

function finalizedLiveProjectionIndex(
  doc: Text,
  topologyIdentity: object,
  syntax: SemanticProjectionRanges,
  excluded: readonly ProjectionSourceRange[],
  codeBlocks: readonly SemanticCodeBlockRange[],
  inlineRanges: readonly ProjectionSourceRange[],
  footnotes: FootnotePresentation,
  tables: readonly TablePresentation[],
  callouts: readonly CalloutPresentation[],
  mathExpressions: readonly MathProjection[],
  frontmatterRange: ProjectionSourceRange | null,
  hasUnclosedFrontmatter: boolean,
): LiveProjectionIndex {
  const immutableExcluded = immutableProjectionRanges(excluded);
  const immutableCodeBlocks = immutableProjectionRanges(codeBlocks);
  const immutableFrontmatter = frontmatterRange === null
    ? null
    : Object.freeze({...frontmatterRange});
  const immutableTables = Object.freeze([...tables]);
  const immutableCallouts = Object.freeze([...callouts]);
  const immutableMathExpressions = Object.freeze([...mathExpressions]);
  const footnoteRanges = immutableProjectionRanges(
    footnotes.references.map(({from, to}) => ({from, to})),
  );
  const immutableCommandProtectedRanges = commandProtectionRanges(
    immutableExcluded,
    immutableFrontmatter ?? undefined,
  );
  const immutableStructuralRanges = immutableProjectionRanges([
    ...immutableTables,
    ...immutableCallouts,
    ...footnotes.definitions,
    ...footnotes.references,
    // Both inline and display mathematics cache source content for KaTeX.
    // Editing inside either expression must rebuild that presentation even
    // when the surrounding Markdown topology is otherwise unchanged.
    ...immutableMathExpressions,
  ].map(({from, to}) => ({from, to})));
  return Object.freeze({
    topologyIdentity,
    syntax,
    literals: Object.freeze({
      excluded: immutableExcluded,
      codeBlocks: immutableCodeBlocks,
    }),
    inlineRanges: immutableProjectionRanges(inlineRanges),
    footnotes,
    tables: immutableTables,
    callouts: immutableCallouts,
    mathExpressions: immutableMathExpressions,
    frontmatterRange: immutableFrontmatter,
    commandProtectedRanges: immutableCommandProtectedRanges,
    structuralRanges: immutableStructuralRanges,
    mutationSensitiveRanges: immutableProjectionRanges([
      ...immutableCommandProtectedRanges,
      ...immutableStructuralRanges,
    ]),
    blockRanges: immutableProjectionRanges([
      ...immutableTables.map(({from, to}) => ({from, to, kind: "table" as const})),
      ...immutableCallouts.map(({from, to}) => ({from, to, kind: "callout" as const})),
      ...immutableMathExpressions.flatMap(({from, to, kind}) =>
        kind === "display" ? [{from, to, kind: "math" as const}] : []),
    ]),
    footnoteRanges,
    tablePositionRanges: indexedTablePositionRanges(doc, immutableTables),
    hasUnclosedFrontmatter,
  });
}

function mathExpressionsFromCatalog(
  state: EditorState,
  syntax: SemanticProjectionRanges,
): MathProjection[] {
  const expressions: MathProjection[] = [];
  for (const inline of syntax.inlines.filter((candidate) => candidate.kind === "inlineMath")) {
    const contentRange = inline.visibleRanges[0];
    const opening = inline.markerRanges[0];
    if (!contentRange || !opening) continue;
    const sourceContent = state.doc.sliceString(contentRange.from, contentRange.to);
    const content = sourceContent.length > 2
      && /^\s/.test(sourceContent) && /\s$/.test(sourceContent) && /\S/.test(sourceContent)
      ? sourceContent.slice(1, -1)
      : sourceContent;
    expressions.push({
      kind: "inline",
      content,
      delimiterLength: opening.to - opening.from,
      from: inline.from,
      to: inline.to,
      contentFrom: contentRange.from,
      contentTo: contentRange.to,
    });
  }
  for (const block of syntax.blocks.filter((candidate) => candidate.kind === "displayMath")) {
    const opening = block.markerRanges[0];
    const closing = block.markerRanges.at(-1);
    if (!opening || !closing || opening === closing) continue;
    const openingLine = state.doc.lineAt(opening.from);
    const closingLine = state.doc.lineAt(closing.from);
    const contentFrom = openingLine.number < state.doc.lines
      ? state.doc.line(openingLine.number + 1).from
      : openingLine.to;
    const contentTo = closingLine.from;
    expressions.push({
      kind: "display",
      content: state.doc.sliceString(contentFrom, contentTo).replace(/^[\r\n]+|[\r\n]+$/g, ""),
      delimiterLength: opening.to - opening.from,
      from: block.from,
      to: block.to,
      contentFrom,
      contentTo,
    });
  }
  return expressions.sort((left, right) => left.from - right.from || left.to - right.to);
}

function buildLiveProjectionIndex(
  state: EditorState,
  dialect: MarkdownEditingDialect | null,
  recordMetric: LiveProjectionIndexOptions["recordMetric"],
): LiveProjectionIndex {
  const startedAt = performance.now();
  // LanguageState initially parses only the editor viewport. This index owns
  // whole-note topology, so give CodeMirror's incremental parser its bounded
  // completion opportunity before reading the catalog. Oversized documents
  // retain the current tree and are rebuilt by the later parser transaction.
  const tree = ensureSyntaxTree(state, state.doc.length) ?? syntaxTree(state);
  const syntax = semanticProjectionRanges(
    state,
    [{from: 0, to: state.doc.length}],
    0,
    tree,
  );
  const codeBlocks: SemanticCodeBlockRange[] = syntax.blocks
    .filter((block) => block.kind === "code")
    .map((block) => ({
      from: block.from,
      to: block.to,
      fenced: block.nodeName === "FencedCode",
      markerRanges: block.markerRanges,
    }));
  const excluded: ProjectionSourceRange[] = [
    ...codeBlocks,
    ...syntax.blocks
      .filter((block) => block.kind === "html" || block.kind === "comment")
      .map(({from, to}) => ({from, to})),
    ...syntax.inlines
      .filter((inline) => inline.kind === "code")
      .map(({from, to}) => ({from, to})),
    ...syntax.literals.map(({from, to}) => ({from, to})),
  ];
  const inlineRanges = syntax.inlines.map(({from, to}) => ({from, to}));
  const namedDefinitionStarts = new Set(syntax.blocks
    .filter((block) => block.kind === "footnoteDefinition")
    .map((block) => block.from));
  const inlineDefinitionRanges = new Set<string>();
  const referenceRanges = new Set(syntax.inlines
    .filter((inline) => inline.kind === "footnoteReference" || inline.kind === "inlineFootnote")
    .map((inline) => rangeKey(inline.from, inline.to)));
  for (const inline of syntax.inlines.filter((candidate) => candidate.kind === "inlineFootnote")) {
    inlineDefinitionRanges.add(rangeKey(inline.from, inline.to));
  }
  const tableRanges = syntax.blocks
    .filter((block) => block.kind === "table")
    .map(({from, to}) => ({from, to}));
  const calloutRanges = syntax.blocks
    .filter((block) => block.kind === "callout")
    .map(({from, to}) => ({from, to}));
  const yamlBoundary = frontmatterBoundary(state.doc);
  const yamlBodyFrom = yamlBoundary.endLine === 0
    ? 0
    : yamlBoundary.endLine < state.doc.lines
      ? state.doc.line(yamlBoundary.endLine + 1).from
      : state.doc.line(yamlBoundary.endLine).to;
  const frontmatterRange = yamlBodyFrom > 0 ? {from: 0, to: yamlBodyFrom} : null;
  const footnoteExcluded = [...excluded];
  if (frontmatterRange) footnoteExcluded.push(frontmatterRange);
  let completeSource: string | null = null;
  const source = () => completeSource ??= state.doc.toString();
  let footnotes: FootnotePresentation = {definitions: [], references: []};
  if (namedDefinitionStarts.size > 0 || inlineDefinitionRanges.size > 0 || referenceRanges.size > 0) {
    const projectedFootnotes = footnotePresentation(
      source(),
      footnoteExcluded,
      dialect?.footnotes,
    );
    footnotes = {
      definitions: projectedFootnotes.definitions.filter((definition) =>
        definition.isInline
          ? inlineDefinitionRanges.has(rangeKey(definition.from, definition.to))
          : namedDefinitionStarts.has(definition.from)),
      references: projectedFootnotes.references.filter((reference) =>
        referenceRanges.has(rangeKey(reference.from, reference.to))),
    };
  }
  const tables = tableRanges.flatMap((range): TablePresentation[] => {
    const presentation = tablePresentation(source(), range.from, range.to);
    return presentation ? [presentation] : [];
  });
  const callouts = calloutRanges.map((range): CalloutPresentation => ({
    ...range,
    source: state.doc.sliceString(range.from, range.to),
  }));
  const mathExpressions = mathExpressionsFromCatalog(state, syntax);
  const index = finalizedLiveProjectionIndex(
    state.doc,
    Object.freeze({}),
    syntax,
    excluded,
    codeBlocks,
    inlineRanges,
    footnotes,
    tables,
    callouts,
    mathExpressions,
    frontmatterRange,
    yamlBoundary.unclosed,
  );
  recordMetric("projection-index", startedAt, {
    documentLength: state.doc.length,
    literalCount: excluded.length,
    tableCount: tables.length,
    calloutCount: callouts.length,
    footnoteCount: footnotes.definitions.length + footnotes.references.length,
  });
  return index;
}

function mapLiveProjectionIndex(
  index: LiveProjectionIndex,
  transaction: Transaction,
): LiveProjectionIndex {
  const map = (position: number) => transaction.changes.mapPos(position);
  const syntax = mapSemanticProjectionRanges(index.syntax, transaction.state, map);
  const footnotes: FootnotePresentation = {
    definitions: index.footnotes.definitions.map((definition) => ({
      ...definition,
      from: map(definition.from),
      to: map(definition.to),
      contentFrom: map(definition.contentFrom),
    })),
    references: index.footnotes.references.map((reference) => ({
      ...reference,
      from: map(reference.from),
      to: map(reference.to),
      definitionFrom: reference.definitionFrom === null ? null : map(reference.definitionFrom),
      definitionContentFrom: reference.definitionContentFrom === null
        ? null
        : map(reference.definitionContentFrom),
    })),
  };
  const tables = index.tables.map((presentation) => ({
    ...presentation,
    from: map(presentation.from),
    to: map(presentation.to),
    header: presentation.header.map((cell) => ({...cell, sourceOffset: map(cell.sourceOffset)})),
    body: presentation.body.map((row) =>
      row.map((cell) => ({...cell, sourceOffset: map(cell.sourceOffset)}))),
  }));
  const callouts = index.callouts.map((presentation) => ({
    ...presentation,
    from: map(presentation.from),
    to: map(presentation.to),
  }));
  const mathExpressions = index.mathExpressions.map((expression) => ({
    ...expression,
    from: map(expression.from),
    to: map(expression.to),
    contentFrom: map(expression.contentFrom),
    contentTo: map(expression.contentTo),
  }));
  const frontmatterRange = index.frontmatterRange === null ? null : {
    from: map(index.frontmatterRange.from),
    to: map(index.frontmatterRange.to),
  };
  return finalizedLiveProjectionIndex(
    transaction.state.doc,
    index.topologyIdentity,
    syntax,
    index.literals.excluded.map((range) => ({from: map(range.from), to: map(range.to)})),
    index.literals.codeBlocks.map((range) => ({
      from: map(range.from),
      to: map(range.to),
      fenced: range.fenced,
      markerRanges: range.markerRanges.map((marker) => ({
        from: map(marker.from),
        to: map(marker.to),
      })),
    })),
    index.inlineRanges.map((range) => ({from: map(range.from), to: map(range.to)})),
    footnotes,
    tables,
    callouts,
    mathExpressions,
    frontmatterRange,
    index.hasUnclosedFrontmatter,
  );
}

export function createLiveProjectionIndexController(
  options: LiveProjectionIndexOptions,
): LiveProjectionIndexController {
  const build = (state: EditorState) => buildLiveProjectionIndex(
    state,
    options.editingDialect(),
    options.recordMetric,
  );
  const field = StateField.define<LiveProjectionIndex>({
    create: build,
    update(previous, transaction) {
      if (!transaction.docChanged) {
        return transactionChangedSyntaxTree(transaction)
          ? build(transaction.state)
          : previous;
      }
      const structuralMarker = /[\r\n`~<>%$\[\]!*_|^:]/;
      if (previous.mutationSensitiveRanges.length === 0
          && !transactionMayCreateProjection(transaction, structuralMarker)) {
        return mapLiveProjectionIndex(previous, transaction);
      }
      return transactionCanMapProjectionTopology(
        transaction,
        structuralMarker,
        previous.mutationSensitiveRanges,
        previous.syntax,
      )
        ? mapLiveProjectionIndex(previous, transaction)
        : build(transaction.state);
    },
  });
  const index = (state: EditorState) => state.field(field, false) ?? build(state);
  return {
    extension: field,
    index,
    topologyWasMapped(transaction) {
      return index(transaction.startState).topologyIdentity
        === index(transaction.state).topologyIdentity;
    },
    visibleInlineMathExpressions(state, coveredRanges, currentIndex) {
      if (!options.editingDialect() || coveredRanges.length === 0) return [];
      return currentIndex.mathExpressions.filter((expression) =>
        expression.kind === "inline"
          && coveredRanges.some((range) =>
            range.from <= expression.from && range.to >= expression.to)
          && (!currentIndex.frontmatterRange
            || expression.from >= currentIndex.frontmatterRange.to)
          && expression.to <= state.doc.length);
    },
  };
}
