import {
  Range,
  StateField,
  type EditorState,
  type Extension,
  type Text,
  type Transaction,
} from "@codemirror/state";
import {Decoration, DecorationSet, EditorView, WidgetType} from "@codemirror/view";
import type {MarkdownEditingDialect} from "./protocol";
import {
  immutableProjectionRanges,
  projectionRangesIntersecting,
} from "./projection-index";
import {
  selectionActivatesSyntax,
  selectionAffectedProjectionRanges,
  transactionChangedSyntaxTree,
  type ProjectionSelectionRange,
  type ProjectionSourceRange,
} from "./projection-update";
import type {SemanticBlockProjection} from "./semantic-projection";
import type {LiveSelectionController} from "./live-selection";
import {
  codeBlockActivationRange,
  type CalloutPresentation,
  type LiveProjectionIndex,
  type LiveProjectionIndexController,
  type SemanticCodeBlockRange,
} from "./live-projection-index";
import {calloutDefinition, calloutHeader} from "./callout-presentation";
import {bodyHeadingAccessibilityLevel} from "./heading-accessibility";

interface SemanticPhysicalLine {
  readonly from: number;
  readonly to: number;
  readonly length: number;
  readonly number: number;
  readonly text: string;
}

interface SemanticLinePresentation {
  readonly classes: readonly string[];
  readonly codeBlock: Readonly<SemanticCodeBlockRange> | null;
  readonly headingLevel: number | null;
  readonly displayMath: SemanticBlockProjection | null;
  readonly paragraph: SemanticBlockProjection | null;
  readonly calloutPresentation: CalloutPresentation | null;
  readonly quoteDepth: number;
  readonly html: SemanticBlockProjection | null;
  readonly comment: SemanticBlockProjection | null;
  readonly list: SemanticBlockProjection | null;
}

interface LiveSemanticLineState {
  readonly decorations: DecorationSet;
}

interface LiveSemanticBlockSpacingState {
  readonly decorations: DecorationSet;
}

type SemanticBlockSpacing = "none" | "half" | "paragraph" | "standard" | "callout";

function isFencedDelimiterLine(
  doc: Text,
  block: SemanticCodeBlockRange,
  lineFrom: number,
) {
  if (!block.fenced) return false;
  return block.markerRanges.some((range) => doc.lineAt(range.from).from === lineFrom);
}

function affectedProjectionAndCodeBlockRanges(
  indexController: LiveProjectionIndexController,
  state: EditorState,
  previousSelections: readonly ProjectionSelectionRange[],
  nextSelections: readonly ProjectionSelectionRange[],
) {
  const changedCodeBlocks = indexController.index(state).literals.codeBlocks.filter((block) => {
    const wasActive = previousSelections.some((selection) =>
      selectionActivatesSyntax(selection, codeBlockActivationRange(state.doc, block)));
    const isActive = nextSelections.some((selection) =>
      selectionActivatesSyntax(selection, codeBlockActivationRange(state.doc, block)));
    return wasActive !== isActive;
  });
  return immutableProjectionRanges([
    ...selectionAffectedProjectionRanges(
      state.doc.length,
      previousSelections,
      nextSelections,
    ),
    ...changedCodeBlocks,
  ]);
}

function semanticBlockSpacing(
  block: SemanticBlockProjection,
): SemanticBlockSpacing {
  switch (block.kind) {
  case "unorderedList":
  case "orderedList":
  case "blockQuote":
  case "code":
  case "html": return "standard";
  case "table":
  case "displayMath": return "paragraph";
  case "callout": return "callout";
  case "comment": return "standard";
  case "thematicBreak": return "half";
  default: return "none";
  }
}

class SemanticBlockGapWidget extends WidgetType {
  constructor(
    readonly previous: SemanticBlockSpacing,
    readonly next: SemanticBlockSpacing,
  ) { super(); }

  eq(other: SemanticBlockGapWidget) {
    return other.previous === this.previous && other.next === this.next;
  }

  toDOM() {
    const gap = document.createElement("div");
    gap.className = [
      "cm-live-semantic-gap",
      `cm-live-semantic-gap-after-${this.previous}`,
      `cm-live-semantic-gap-before-${this.next}`,
    ].join(" ");
    gap.setAttribute("aria-hidden", "true");
    return gap;
  }

  ignoreEvent() { return true; }
}

export function createLiveSemanticLayout(options: {
  selection: LiveSelectionController;
  projections: LiveProjectionIndexController;
  editingDialect(): MarkdownEditingDialect | null;
}): {extension: Extension} {
  const {selection, projections} = options;

  function semanticLinePresentation(
    state: EditorState,
    line: SemanticPhysicalLine,
    index: LiveProjectionIndex,
  ): SemanticLinePresentation {
    const lineQueryTo = Math.min(state.doc.length, line.to + 1);
    const active = selection.selection(state).ranges.some((range) =>
      range.head >= line.from && range.head <= line.to
        || !range.empty && range.from < lineQueryTo && range.to >= line.from);
    const ownsCollapsedCaret = selection.selection(state).ranges.some((range) =>
      range.empty && range.head >= line.from && range.head <= line.to);
    const outsideFrontmatter = !index.frontmatterRange || line.from >= index.frontmatterRange.to;
    const followsFrontmatter = index.frontmatterRange !== null
      && index.frontmatterRange.to < state.doc.length
      && line.from === index.frontmatterRange.to
      && !/^\s*$/.test(line.text);
    const blocks = projectionRangesIntersecting(index.syntax.blocks, line.from, lineQueryTo);
    const codeBlock = projectionRangesIntersecting(
      index.literals.codeBlocks,
      line.from,
      lineQueryTo,
    )[0] ?? null;
    const codeBlockActive = codeBlock !== null && selection.selection(state).ranges.some((range) =>
      selectionActivatesSyntax(range, codeBlockActivationRange(state.doc, codeBlock)));
    const heading = blocks.find((block) => block.kind === "heading") ?? null;
    const headingLevel = heading?.headingLevel ?? null;
    const headingMarkers = heading?.markerRanges.filter((range) =>
      range.from < lineQueryTo && range.to > line.from) ?? [];
    const setextMarkerLine = heading?.nodeName.startsWith("SetextHeading") && headingMarkers.some((range) =>
      range.from <= line.from && range.to >= line.to);
    const paragraph = blocks.find((block) => block.kind === "paragraph") ?? null;
    const calloutPresentation = projectionRangesIntersecting(
      index.callouts,
      line.from,
      lineQueryTo,
    )[0] ?? null;
    const opening = calloutPresentation
      ? calloutHeader(calloutPresentation.source.split(/\r?\n/, 1)[0] ?? "")
      : null;
    const calloutIdentifier = opening
      ? calloutDefinition(options.editingDialect(), opening[2]).identifier
      : null;
    const displayMath = blocks.find((block) => block.kind === "displayMath") ?? null;
    const quoteBlocks = calloutPresentation
      ? []
      : blocks.filter((block) => block.kind === "blockQuote");
    const quoteRanges = calloutPresentation
      ? []
      : projectionRangesIntersecting(index.quoteRanges, line.from, lineQueryTo);
    const quote = quoteBlocks[0] ?? null;
    const quoteDepth = quoteRanges.reduce(
      (maximum, range) => Math.max(maximum, range.depth),
      0,
    );
    const rule = blocks.find((block) => block.kind === "thematicBreak") ?? null;
    const html = blocks.find((block) => block.kind === "html") ?? null;
    const blockComment = blocks.find((block) => block.kind === "comment") ?? null;
    const inlineComment = projectionRangesIntersecting(
      index.syntax.inlines,
      line.from,
      lineQueryTo,
    ).find((inline) => inline.kind === "comment") ?? null;
    const comment = blockComment ?? (inlineComment ? {
      kind: "comment" as const,
      nodeName: inlineComment.nodeName,
      from: inlineComment.from,
      to: inlineComment.to,
      depth: 0,
      parent: null,
      headingLevel: null,
      listDepth: null,
      markerRanges: inlineComment.markerRanges,
      taskMarkerRange: null,
    } : null);
    const list = blocks
      .filter((block) => block.kind === "listItem")
      .filter((block) => block.markerRanges.some((range) =>
        range.from >= line.from && range.from <= line.to))
      .sort((left, right) => (right.listDepth ?? 0) - (left.listDepth ?? 0))[0] ?? null;
    const listMarker = list?.markerRanges.find((range) =>
      range.from >= line.from
        && range.from <= line.to
        && !state.doc.sliceString(range.from, range.to).startsWith("[")) ?? null;
    const classes = new Set<string>();
    if (followsFrontmatter) classes.add("cm-live-frontmatter-body-start");
    if (/^\s*$/.test(state.doc.sliceString(line.from, line.to))
        && outsideFrontmatter && !codeBlock) {
      classes.add("cm-live-blank-line");
      if (ownsCollapsedCaret) classes.add("cm-live-blank-line-active");
    }
    if (calloutPresentation) {
      classes.add("cm-live-callout");
      classes.add(`cm-live-callout-role-${calloutIdentifier ?? "neutral"}`);
      classes.add(active ? "cm-live-callout-active-line" : "cm-live-callout-projected-line");
      if (state.doc.lineAt(calloutPresentation.from).number === line.number) {
        classes.add("cm-live-callout-start");
        classes.add("cm-live-callout-header");
        classes.add(`cm-live-callout-role-${calloutIdentifier ?? "neutral"}`);
      } else {
        classes.add("cm-live-callout-body-line");
      }
      if (state.doc.lineAt(calloutPresentation.to).number === line.number) {
        classes.add("cm-live-callout-end");
      }
    }
    if (displayMath) {
      classes.add("cm-live-math-source");
      const firstMathLine = state.doc.lineAt(displayMath.from).number;
      const lastMathLine = state.doc.lineAt(displayMath.to).number;
      if (line.number === firstMathLine) classes.add("cm-live-math-source-start");
      if (line.number === lastMathLine) classes.add("cm-live-math-source-end");
    }
    if (blocks.some(block => block.kind === "footnoteDefinition")) classes.add("cm-live-footnote-source");
    if (codeBlock) {
      classes.add("cm-live-codeblock");
      if (codeBlockActive) classes.add("cm-live-codeblock-active");
      if (!codeBlockActive && isFencedDelimiterLine(state.doc, codeBlock, line.from)) {
        classes.add("cm-live-code-fence-line");
      } else {
        const firstContentLine = codeBlock.fenced && codeBlock.markerRanges.length > 0
          ? Math.min(
              state.doc.lines,
              state.doc.lineAt(codeBlock.markerRanges[0].from).number + 1,
            )
          : state.doc.lineAt(codeBlock.from).number;
        const lastContentLine = codeBlock.fenced && codeBlock.markerRanges.length > 1
          ? Math.max(
              firstContentLine,
              state.doc.lineAt(codeBlock.markerRanges.at(-1)!.from).number - 1,
            )
          : state.doc.lineAt(codeBlock.to).number;
        const firstStyledLine = codeBlockActive && codeBlock.fenced
          ? state.doc.lineAt(codeBlock.markerRanges[0].from).number
          : firstContentLine;
        const lastStyledLine = codeBlockActive && codeBlock.fenced
            && codeBlock.markerRanges.length > 1
          ? state.doc.lineAt(codeBlock.markerRanges.at(-1)!.from).number
          : lastContentLine;
        if (line.number === firstStyledLine) classes.add("cm-live-codeblock-start");
        if (line.number === lastStyledLine) classes.add("cm-live-codeblock-end");
      }
    } else if (blockComment) {
      classes.add("cm-live-raw-html");
      if (line.from <= blockComment.from) classes.add("cm-live-raw-html-start");
      if (line.to >= blockComment.to) classes.add("cm-live-raw-html-end");
    } else if (comment) {
      classes.add("cm-live-paragraph");
      classes.add("cm-live-paragraph-start");
      classes.add("cm-live-paragraph-end");
    } else if (html) {
      classes.add("cm-live-raw-html");
      if (line.from <= html.from) classes.add("cm-live-raw-html-start");
      if (line.to >= html.to) classes.add("cm-live-raw-html-end");
    } else {
      if (headingLevel !== null) {
        if (setextMarkerLine) {
          classes.add("cm-live-heading-marker-line");
        } else {
          classes.add("cm-live-heading");
          classes.add(`cm-live-h${headingLevel}`);
        }
      }
      if (paragraph && !calloutPresentation && headingLevel === null) {
        classes.add("cm-live-paragraph");
        if (line.from <= paragraph.from) classes.add("cm-live-paragraph-start");
        if (line.to >= paragraph.to) classes.add("cm-live-paragraph-end");
      }
      if (quote) {
        classes.add("cm-live-quote");
        if (quoteDepth > 1) classes.add("cm-live-quote-nested");
      }
      if (rule && outsideFrontmatter && !active) classes.add("cm-live-rule");
      if (list && listMarker) {
        classes.add("cm-live-list");
        if (list.taskMarkerRange) classes.add("cm-live-task-list");
      }
    }
    return {
      classes: [...classes],
      codeBlock,
      headingLevel,
      displayMath,
      paragraph,
      calloutPresentation,
      quoteDepth,
      html,
      comment,
      list,
    };
  }

  function semanticLineDecorationRanges(
    state: EditorState,
    from = 0,
    to = state.doc.length,
  ): Range<Decoration>[] {
    const index = projections.index(state);
    if (index.hasUnclosedFrontmatter) return [];
    const ranges: Range<Decoration>[] = [];
    // The frontmatter field owns its closed source envelope. Markdown-looking
    // YAML must not acquire headings, list rhythm or thematic-break geometry.
    const scanFrom = Math.max(index.frontmatterRange?.to ?? 0, Math.min(from, state.doc.length));
    const scanTo = Math.min(to, state.doc.length);
    if (scanTo < scanFrom) return [];
    let line = state.doc.lineAt(scanFrom);
    while (line.from <= scanTo) {
      const presentation = semanticLinePresentation(state, line, index);
      const direction = presentation.codeBlock || presentation.displayMath || presentation.html
        ? "ltr"
        : presentation.headingLevel !== null
            || presentation.paragraph
            || presentation.calloutPresentation
            || presentation.quoteDepth > 0
            || presentation.list
            || presentation.comment
          ? "auto"
          : null;
      if (presentation.classes.length > 0 || direction) {
        const attributes: Record<string, string> = {};
        if (presentation.classes.length > 0) {
          attributes.class = presentation.classes.join(" ");
        }
        if (presentation.calloutPresentation) {
          attributes["data-scholium-callout-from"] = String(
            presentation.calloutPresentation.from,
          );
        }
        if (presentation.quoteDepth > 0) {
          // The depth is parser-owned data transported as a CSS custom
          // property. The stylesheet can therefore paint every ancestor rail
          // from one semantic track, including depths not present in a
          // hard-coded selector list.
          attributes.style = `--scholium-live-quote-depth: ${presentation.quoteDepth};`;
        }
        if (direction) attributes.dir = direction;
        if (presentation.headingLevel !== null) {
          attributes.role = "heading";
          attributes["aria-level"] = String(
            bodyHeadingAccessibilityLevel(presentation.headingLevel),
          );
        }
        ranges.push(Decoration.line({attributes}).range(line.from));
      }
      if (line.number >= state.doc.lines) break;
      line = state.doc.line(line.number + 1);
    }
    return ranges;
  }

  function expandedPhysicalLineRanges(
    state: EditorState,
    sourceRanges: readonly ProjectionSourceRange[],
  ) {
    const expanded = sourceRanges.map((range) => {
      const from = Math.max(0, Math.min(range.from, state.doc.length));
      const to = Math.max(from, Math.min(range.to, state.doc.length));
      return {
        from: state.doc.lineAt(from).from,
        to: state.doc.lineAt(to).to,
      };
    }).sort((left, right) => left.from - right.from || left.to - right.to);
    const merged: ProjectionSourceRange[] = [];
    for (const range of expanded) {
      const previous = merged.at(-1);
      if (previous && range.from <= previous.to + 1) {
        previous.to = Math.max(previous.to, range.to);
      } else {
        merged.push({...range});
      }
    }
    return merged;
  }

  function replacingLineDecorationsInRanges(
    existing: DecorationSet,
    state: EditorState,
    affected: readonly ProjectionSourceRange[],
  ) {
    let decorations = existing;
    for (const range of expandedPhysicalLineRanges(state, affected)) {
      decorations = decorations.update({
        filter: (from) => from < range.from || from > range.to,
        add: semanticLineDecorationRanges(state, range.from, range.to),
        sort: true,
      });
    }
    return decorations;
  }

  function mergedChangedLineRanges(transaction: Transaction) {
    const ranges: ProjectionSourceRange[] = [];
    transaction.changes.iterChangedRanges((_fromA, _toA, fromB, toB) => {
      const startLine = transaction.state.doc.lineAt(Math.min(fromB, transaction.state.doc.length));
      const endLine = transaction.state.doc.lineAt(Math.min(toB, transaction.state.doc.length));
      const expandedStart = transaction.state.doc.line(Math.max(1, startLine.number - 1)).from;
      const expandedEnd = transaction.state.doc.line(
        Math.min(transaction.state.doc.lines, endLine.number + 1),
      ).to;
      const previous = ranges.at(-1);
      if (previous && expandedStart <= previous.to) {
        previous.to = Math.max(previous.to, expandedEnd);
      } else {
        ranges.push({from: expandedStart, to: expandedEnd});
      }
    });
    return ranges;
  }

  function buildLineState(state: EditorState): LiveSemanticLineState {
    return {decorations: Decoration.set(semanticLineDecorationRanges(state), true)};
  }

  const lineField = StateField.define<LiveSemanticLineState>({
    create: buildLineState,
    update(previous, transaction) {
      if (transactionChangedSyntaxTree(transaction)) return buildLineState(transaction.state);
      if (transaction.docChanged) {
        if (!projections.topologyWasMapped(transaction)) return buildLineState(transaction.state);
        const mapped = previous.decorations.map(transaction.changes);
        return {
          decorations: replacingLineDecorationsInRanges(
            mapped,
            transaction.state,
            mergedChangedLineRanges(transaction),
          ),
        };
      }
      if (selection.changed(transaction.startState, transaction.state)) {
        const affected = affectedProjectionAndCodeBlockRanges(
          projections,
          transaction.state,
          selection.selection(transaction.startState).ranges,
          selection.selection(transaction.state).ranges,
        );
        return {
          decorations: replacingLineDecorationsInRanges(
            previous.decorations,
            transaction.state,
            affected,
          ),
        };
      }
      return previous;
    },
    provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
  });

  function semanticBlockGapRanges(state: EditorState): Range<Decoration>[] {
    const index = projections.index(state);
    if (index.hasUnclosedFrontmatter) return [];
    const spacingPriority: Partial<Record<SemanticBlockProjection["kind"], number>> = {
      callout: 100,
      displayMath: 90,
      table: 80,
      code: 70,
      html: 60,
      orderedList: 50,
      unorderedList: 50,
      blockQuote: 40,
      thematicBreak: 30,
      heading: 20,
      paragraph: 10,
    };
    const rawTopLevelBlocks = index.syntax.blocks
      .filter((block) => block.parent === null)
      .filter((block) => block.to > (index.frontmatterRange?.to ?? 0));
    const topLevelBlocks = rawTopLevelBlocks
      .filter((candidate) => !rawTopLevelBlocks.some((owner) =>
        owner !== candidate
          && owner.from <= candidate.from
          && owner.to >= candidate.to
          && (spacingPriority[owner.kind] ?? 0) > (spacingPriority[candidate.kind] ?? 0)))
      .sort((left, right) => left.from - right.from || left.to - right.to);
    const ranges: Range<Decoration>[] = [];
    let previous: SemanticBlockProjection | null = null;
    for (const current of topLevelBlocks) {
      const previousSpacing = previous
        ? semanticBlockSpacing(previous)
        : "none";
      const nextSpacing = semanticBlockSpacing(current);
      const previousLineNumber = previous
        ? state.doc.lineAt(Math.min(previous.to, state.doc.length)).number
        : 0;
      const currentLineNumber = state.doc.lineAt(current.from).number;
      let authoredSeparatorLine: number | null = null;
      for (let number = currentLineNumber - 1; number > previousLineNumber; number -= 1) {
        const line = state.doc.line(number);
        if (/^\s*$/.test(line.text)) {
          authoredSeparatorLine = line.from;
          break;
        }
      }
      if (authoredSeparatorLine !== null) {
        // The selected source line carries only the spacing this semantic
        // boundary actually needs. A heading already owns its before/after
        // padding, while a paragraph contributes its trailing manuscript gap.
        ranges.push(Decoration.line({
          attributes: {
            class: [
              "cm-live-semantic-blank-gap",
              `cm-live-semantic-gap-after-${previousSpacing}`,
              `cm-live-semantic-gap-before-${nextSpacing}`,
            ].join(" "),
            "data-scholium-blank-source-offset": String(authoredSeparatorLine),
          },
        }).range(authoredSeparatorLine));
      } else if (previousSpacing !== "none" || nextSpacing !== "none") {
        ranges.push(Decoration.widget({
          widget: new SemanticBlockGapWidget(previousSpacing, nextSpacing),
          block: true,
          side: -1,
        }).range(current.from));
      }
      previous = current;
    }
    if (previous) {
      const spacing = semanticBlockSpacing(previous);
      if (spacing !== "none") {
        ranges.push(Decoration.widget({
          widget: new SemanticBlockGapWidget(spacing, "none"),
          block: true,
          side: 1,
        }).range(previous.to));
      }
    }
    return ranges;
  }

  function buildSpacingState(state: EditorState): LiveSemanticBlockSpacingState {
    return {decorations: Decoration.set(semanticBlockGapRanges(state), true)};
  }

  const spacingField = StateField.define<LiveSemanticBlockSpacingState>({
    create: buildSpacingState,
    update(previous, transaction) {
      if (!transaction.docChanged && !transactionChangedSyntaxTree(transaction)) return previous;
      if (transactionChangedSyntaxTree(transaction)) return buildSpacingState(transaction.state);
      return projections.topologyWasMapped(transaction)
        ? {decorations: previous.decorations.map(transaction.changes)}
        : buildSpacingState(transaction.state);
    },
    provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
  });

  return {extension: [lineField, spacingField]};
}
