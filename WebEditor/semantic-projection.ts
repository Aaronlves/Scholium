import type {EditorState, Text} from "@codemirror/state";
import {syntaxTree} from "@codemirror/language";

export type BaseBlockKind =
  | "paragraph"
  | "heading"
  | "blockQuote"
  | "code"
  | "unorderedList"
  | "orderedList"
  | "listItem"
  | "table"
  | "thematicBreak"
  | "html";

export type BaseInlineKind =
  | "strong"
  | "emphasis"
  | "strikethrough"
  | "highlight"
  | "code"
  | "link"
  | "image";

export type PresentationBlockKind = BaseBlockKind
  | "callout"
  | "footnoteDefinition"
  | "displayMath"
  | "comment";

export type PresentationInlineKind = BaseInlineKind
  | "wikilink"
  | "vectorLink"
  | "inlineMath"
  | "footnoteReference"
  | "inlineFootnote"
  | "comment";

export interface SemanticSourceRange { from: number; to: number }

export interface SemanticBlockProjection extends SemanticSourceRange {
  kind: PresentationBlockKind;
  nodeName: string;
  depth: number;
  parent: {kind: PresentationBlockKind; from: number; to: number} | null;
  headingLevel: number | null;
  listDepth: number | null;
  markerRanges: SemanticSourceRange[];
  taskMarkerRange: SemanticSourceRange | null;
}

export interface SemanticInlineProjection extends SemanticSourceRange {
  kind: PresentationInlineKind;
  nodeName: string;
  markerRanges: SemanticSourceRange[];
  visibleRanges: SemanticSourceRange[];
  targetRange: SemanticSourceRange | null;
  aliasRange: SemanticSourceRange | null;
}

export interface SemanticProjectionRanges {
  blocks: SemanticBlockProjection[];
  inlines: SemanticInlineProjection[];
  literals: Array<SemanticSourceRange & {nodeName: string}>;
  headingLevelByLineFrom: Map<number, number>;
  paragraphs: Array<{from: number; to: number}>;
  strong: Set<string>;
  emphasis: Set<string>;
  links: Set<string>;
  wikilinks: Set<string>;
  strikethrough: Set<string>;
  highlights: Set<string>;
  tables: Array<{from: number; to: number}>;
  callouts: Array<{from: number; to: number}>;
}

function projectionRangesFromCatalog(
  state: EditorState,
  blocks: SemanticBlockProjection[],
  inlines: SemanticInlineProjection[],
  literals: Array<SemanticSourceRange & {nodeName: string}>,
): SemanticProjectionRanges {
  const result: SemanticProjectionRanges = {
    blocks,
    inlines,
    literals,
    headingLevelByLineFrom: new Map(),
    paragraphs: [],
    strong: new Set(),
    emphasis: new Set(),
    links: new Set(),
    wikilinks: new Set(),
    strikethrough: new Set(),
    highlights: new Set(),
    tables: [],
    callouts: [],
  };
  for (const block of blocks) {
    if (block.kind === "heading" && block.headingLevel !== null) {
      result.headingLevelByLineFrom.set(state.doc.lineAt(block.from).from, block.headingLevel);
    }
    if (block.kind === "paragraph") result.paragraphs.push({from: block.from, to: block.to});
    if (block.kind === "table") result.tables.push({from: block.from, to: block.to});
    if (block.kind === "callout") result.callouts.push({from: block.from, to: block.to});
  }
  for (const inline of inlines) {
    const key = rangeKey(inline.from, inline.to);
    if (inline.kind === "strong") result.strong.add(key);
    if (inline.kind === "emphasis") result.emphasis.add(key);
    if (inline.kind === "link") result.links.add(key);
    if (inline.kind === "wikilink" || inline.kind === "vectorLink") result.wikilinks.add(key);
    if (inline.kind === "strikethrough") result.strikethrough.add(key);
    if (inline.kind === "highlight") result.highlights.add(key);
  }
  return result;
}

export function mapSemanticProjectionRanges(
  previous: SemanticProjectionRanges,
  state: EditorState,
  mapPosition: (position: number) => number,
) {
  const mapRange = (range: SemanticSourceRange) => ({
    from: mapPosition(range.from),
    to: mapPosition(range.to),
  });
  const blocks = previous.blocks.map((block): SemanticBlockProjection => ({
    ...block,
    from: mapPosition(block.from),
    to: mapPosition(block.to),
    parent: block.parent ? {
      kind: block.parent.kind,
      from: mapPosition(block.parent.from),
      to: mapPosition(block.parent.to),
    } : null,
    markerRanges: block.markerRanges.map(mapRange),
    taskMarkerRange: block.taskMarkerRange ? mapRange(block.taskMarkerRange) : null,
  }));
  const inlines = previous.inlines.map((inline): SemanticInlineProjection => ({
    ...inline,
    from: mapPosition(inline.from),
    to: mapPosition(inline.to),
    markerRanges: inline.markerRanges.map(mapRange),
    visibleRanges: inline.visibleRanges.map(mapRange),
    targetRange: inline.targetRange ? mapRange(inline.targetRange) : null,
    aliasRange: inline.aliasRange ? mapRange(inline.aliasRange) : null,
  }));
  const literals = previous.literals.map((literal) => ({
    ...literal,
    from: mapPosition(literal.from),
    to: mapPosition(literal.to),
  }));
  return projectionRangesFromCatalog(state, blocks, inlines, literals);
}

interface ProjectionSyntaxNode {
  readonly name: string;
  readonly from: number;
  readonly to: number;
  readonly firstChild: ProjectionSyntaxNode | null;
  readonly nextSibling: ProjectionSyntaxNode | null;
}

const blockKinds = new Map<string, PresentationBlockKind>([
  ["Paragraph", "paragraph"],
  ["Blockquote", "blockQuote"],
  ["FencedCode", "code"],
  ["CodeBlock", "code"],
  ["BulletList", "unorderedList"],
  ["OrderedList", "orderedList"],
  ["ListItem", "listItem"],
  ["Table", "table"],
  ["HorizontalRule", "thematicBreak"],
  ["HTMLBlock", "html"],
  ["Callout", "callout"],
  ["FootnoteDefinition", "footnoteDefinition"],
  ["BlockMath", "displayMath"],
  ["ObsidianCommentBlock", "comment"],
  ["UnclosedObsidianCommentBlock", "comment"],
]);

const inlineKinds = new Map<string, PresentationInlineKind>([
  ["StrongEmphasis", "strong"],
  ["Emphasis", "emphasis"],
  ["Strikethrough", "strikethrough"],
  ["InlineCode", "code"],
  ["Link", "link"],
  ["Autolink", "link"],
  ["Image", "image"],
  ["Highlight", "highlight"],
  ["WikiLink", "wikilink"],
  ["VectorLink", "vectorLink"],
  ["InlineMath", "inlineMath"],
  ["FootnoteReference", "footnoteReference"],
  ["InlineFootnote", "inlineFootnote"],
  ["ObsidianComment", "comment"],
]);

function childRanges(
  root: ProjectionSyntaxNode,
  names: ReadonlySet<string>,
  stopAt: ReadonlySet<string> = new Set(),
) {
  const ranges: SemanticSourceRange[] = [];
  const visit = (node: ProjectionSyntaxNode) => {
    if (names.has(node.name)) ranges.push({from: node.from, to: node.to});
    if (node !== root && stopAt.has(node.name)) return;
    for (let child = node.firstChild; child; child = child.nextSibling) visit(child);
  };
  visit(root);
  return ranges.sort((left, right) => left.from - right.from || left.to - right.to);
}

function complementRanges(
  from: number,
  to: number,
  excluded: readonly SemanticSourceRange[],
) {
  const visible: SemanticSourceRange[] = [];
  let position = from;
  for (const range of excluded) {
    if (range.from > position) visible.push({from: position, to: range.from});
    position = Math.max(position, range.to);
  }
  if (position < to) visible.push({from: position, to});
  return visible;
}

function presentationBlockMarkerRanges(
  state: EditorState,
  node: ProjectionSyntaxNode,
  kind: PresentationBlockKind,
  markerNames: ReadonlySet<string>,
  stopAt: ReadonlySet<string>,
) {
  const ranges = childRanges(node, markerNames, stopAt);
  if (kind !== "heading" || !node.name.startsWith("ATXHeading")) return ranges;

  // Lezer's HeaderMark covers only the `#` run. In rendered Markdown, the
  // required separator after an opening ATX marker is syntax too: HTML
  // collapses it at the start of the heading, whereas CodeMirror preserves it
  // under `white-space: break-spaces`. Keep that separator in the catalog's
  // exact presentation marker range so both adapters start the visible title
  // at the same source boundary. A trailing closing HeaderMark is untouched.
  return ranges.map((range) => {
    if (range.from !== node.from) return range;
    let to = range.to;
    while (to < node.to) {
      const character = state.doc.sliceString(to, to + 1);
      if (character !== " " && character !== "\t") break;
      to += 1;
    }
    return {from: range.from, to};
  });
}

function inlinePresentation(
  node: ProjectionSyntaxNode,
  kind: PresentationInlineKind,
): SemanticInlineProjection {
  const markerNames = new Set<string>();
  switch (kind) {
  case "strong":
  case "emphasis": markerNames.add("EmphasisMark"); break;
  case "strikethrough": markerNames.add("StrikethroughMark"); break;
  case "code": markerNames.add("CodeMark"); break;
  case "link":
  case "image": markerNames.add("LinkMark"); break;
  case "highlight": markerNames.add("HighlightMark"); break;
  case "wikilink":
  case "vectorLink":
    markerNames.add("WikiLinkOpenMark");
    markerNames.add("WikiEmbedMark");
    markerNames.add("VectorLinkMark");
    markerNames.add("WikiLinkAliasMark");
    markerNames.add("WikiLinkCloseMark");
    break;
  case "inlineMath": markerNames.add("MathMark"); break;
  case "footnoteReference":
    markerNames.add("FootnoteOpenMark");
    markerNames.add("FootnoteCloseMark");
    break;
  case "inlineFootnote":
    markerNames.add("InlineFootnoteOpenMark");
    markerNames.add("FootnoteCloseMark");
    break;
  case "comment": break;
  }
  const markerRanges = childRanges(node, markerNames);
  let targetRange: SemanticSourceRange | null = null;
  let aliasRange: SemanticSourceRange | null = null;
  let visibleRanges = complementRanges(node.from, node.to, markerRanges);
  if (kind === "link" || kind === "image") {
    const explicitVisible = childRanges(node, new Set(["URL"]));
    if (node.name === "Autolink") {
      visibleRanges = explicitVisible;
    } else {
      const linkMarks = markerRanges;
      visibleRanges = linkMarks.length >= 2
        ? [{from: linkMarks[0].to, to: linkMarks[1].from}]
        : [];
    }
  } else if (kind === "wikilink" || kind === "vectorLink") {
    const alias = childRanges(node, new Set(["WikiLinkAlias"]));
    const target = childRanges(node, new Set(["WikiLinkTarget"]));
    targetRange = target[0] ?? null;
    aliasRange = alias[0] ?? null;
    visibleRanges = alias.length > 0 ? alias : target;
  } else if (kind === "inlineMath") {
    visibleRanges = childRanges(node, new Set(["MathContent"]));
  } else if (kind === "footnoteReference") {
    visibleRanges = childRanges(node, new Set(["FootnoteIdentifier"]));
  } else if (kind === "inlineFootnote") {
    visibleRanges = childRanges(node, new Set(["FootnoteContent"]));
  } else if (kind === "comment") {
    visibleRanges = [];
  }
  return {
    kind,
    nodeName: node.name,
    from: node.from,
    to: node.to,
    markerRanges,
    visibleRanges,
    targetRange,
    aliasRange,
  };
}

export function rangeKey(from: number, to: number) {
  return `${from}:${to}`;
}

/**
 * Returns only the syntax-bearing start of the physical line containing
 * `position`. Interaction reporting must never materialize an arbitrarily
 * long `Line.text` merely to recognize a short block marker.
 */
export function boundedLinePrefix(doc: Text, position: number, limit = 512) {
  const line = doc.lineAt(Math.max(0, Math.min(position, doc.length)));
  return doc.sliceString(line.from, Math.min(line.to, line.from + limit));
}

export function boundedProjectionRanges(
  documentLength: number,
  visibleRanges: readonly {from: number; to: number}[],
  margin = 2_000,
) {
  const expanded = visibleRanges.map((range) => ({
    from: Math.max(0, range.from - margin),
    to: Math.min(documentLength, range.to + margin),
  })).sort((left, right) => left.from - right.from || left.to - right.to);
  const merged: Array<{from: number; to: number}> = [];
  for (const range of expanded) {
    const previous = merged.at(-1);
    if (previous && range.from <= previous.to) previous.to = Math.max(previous.to, range.to);
    else merged.push({...range});
  }
  return merged;
}

export function semanticProjectionRanges(
  state: EditorState,
  visibleRanges: readonly {from: number; to: number}[],
  margin = 2_000,
  tree: ReturnType<typeof syntaxTree> = syntaxTree(state),
): SemanticProjectionRanges {
  const result: SemanticProjectionRanges = {
    blocks: [],
    inlines: [],
    literals: [],
    headingLevelByLineFrom: new Map(),
    paragraphs: [],
    strong: new Set(),
    emphasis: new Set(),
    links: new Set(),
    wikilinks: new Set(),
    strikethrough: new Set(),
    highlights: new Set(),
    tables: [],
    callouts: [],
  };
  if (visibleRanges.length === 0) return result;
  const from = Math.max(0, Math.min(...visibleRanges.map((range) => range.from)) - margin);
  const to = Math.min(state.doc.length, Math.max(...visibleRanges.map((range) => range.to)) + margin);
  const blockStack: SemanticBlockProjection[] = [];
  tree.iterate({
    from,
    to,
    enter(reference) {
      const node = reference.node as unknown as ProjectionSyntaxNode;
      const heading = /^(?:ATX|Setext)Heading([1-6])$/.exec(node.name);
      const kind = heading ? "heading" : blockKinds.get(node.name);
      if (kind) {
        const parent = blockStack.at(-1) ?? null;
        const markerNames = new Set<string>();
        if (kind === "heading") markerNames.add("HeaderMark");
        if (kind === "blockQuote") markerNames.add("QuoteMark");
        if (kind === "listItem") {
          markerNames.add("ListMark");
          markerNames.add("TaskMarker");
        }
        if (kind === "code") markerNames.add("CodeMark");
        if (kind === "callout") markerNames.add("CalloutQuoteMark");
        if (kind === "displayMath") markerNames.add("MathMark");
        const markerRanges = presentationBlockMarkerRanges(
          state,
          node,
          kind,
          markerNames,
          kind === "listItem" ? new Set(["ListItem"]) : new Set(),
        );
        const block: SemanticBlockProjection = {
          kind,
          nodeName: node.name,
          from: node.from,
          to: node.to,
          depth: blockStack.length,
          parent: parent ? {kind: parent.kind, from: parent.from, to: parent.to} : null,
          headingLevel: heading ? Number(heading[1]) : null,
          listDepth: kind === "listItem"
            ? blockStack.filter((block) => block.kind === "listItem").length
            : null,
          markerRanges,
          taskMarkerRange: kind === "listItem"
            ? markerRanges.find((range) => state.doc.sliceString(range.from, range.to).startsWith("[")) ?? null
            : null,
        };
        result.blocks.push(block);
        blockStack.push(block);
      }

      if (node.name === "Task") {
        const taskMarker = childRanges(node, new Set(["TaskMarker"]))[0];
        if (taskMarker) {
          let contentFrom = taskMarker.to;
          while (contentFrom < node.to) {
            const character = state.doc.sliceString(contentFrom, contentFrom + 1);
            if (character !== " " && character !== "\t") break;
            contentFrom += 1;
          }
          if (contentFrom < node.to) {
            const parent = blockStack.at(-1) ?? null;
            const paragraph: SemanticBlockProjection = {
              kind: "paragraph",
              nodeName: "TaskContent",
              from: contentFrom,
              to: node.to,
              depth: blockStack.length,
              parent: parent ? {kind: parent.kind, from: parent.from, to: parent.to} : null,
              headingLevel: null,
              listDepth: null,
              markerRanges: [],
              taskMarkerRange: null,
            };
            result.blocks.push(paragraph);
          }
        }
      }

      const inlineKind = inlineKinds.get(node.name);
      if (inlineKind) {
        const inline = inlinePresentation(node, inlineKind);
        result.inlines.push(inline);
      }
      if ([
        "HTMLTag", "CommentBlock", "Comment", "ObsidianComment",
        "UnclosedObsidianComment",
      ].includes(node.name)) {
        result.literals.push({from: node.from, to: node.to, nodeName: node.name});
        return false;
      }
    },
    leave(reference) {
      const node = reference.node as unknown as ProjectionSyntaxNode;
      const heading = /^(?:ATX|Setext)Heading([1-6])$/.test(node.name);
      if (!heading && !blockKinds.has(node.name)) return;
      const current = blockStack.at(-1);
      if (current?.from === node.from && current.to === node.to && current.nodeName === node.name) {
        blockStack.pop();
      }
    },
  });
  result.blocks.sort((left, right) => left.from - right.from || right.to - left.to || left.kind.localeCompare(right.kind));
  result.inlines.sort((left, right) => left.from - right.from || right.to - left.to || left.kind.localeCompare(right.kind));
  result.literals.sort((left, right) => left.from - right.from || right.to - left.to);
  return projectionRangesFromCatalog(state, result.blocks, result.inlines, result.literals);
}
