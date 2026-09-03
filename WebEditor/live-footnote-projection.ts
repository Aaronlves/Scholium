import {Range, StateField, type EditorState, type Extension} from "@codemirror/state";
import {Decoration, DecorationSet, EditorView, WidgetType} from "@codemirror/view";
import type {
  FootnotePresentation,
  FootnoteReferencePresentation,
} from "./footnote-presentation";
import {localizedTemplate} from "./localization";
import {
  activeProjectionSignature,
  selectionIntersectsProjection,
  transactionChangedSyntaxTree,
  type ProjectionSourceRange,
} from "./projection-update";
import type {LiveProjectionIndexController} from "./live-projection-index";
import type {LiveSelectionController} from "./live-selection";
import type {ProjectedWidgetRegistry} from "./projected-widget-registry";

interface LiveFootnoteReferenceState {
  readonly decorations: DecorationSet;
  readonly atomicRanges: DecorationSet;
  readonly hasConstructs: boolean;
  readonly presentation: FootnotePresentation;
  readonly ranges: readonly Readonly<ProjectionSourceRange>[];
}

const footnoteTrailingPunctuation = new Set(
  Array.from(".,;:!?，。！？；：、…）》】」』’”\""),
);

function trailingFootnotePunctuation(state: EditorState, from: number) {
  let value = "";
  for (const character of state.doc.sliceString(from, Math.min(state.doc.length, from + 16))) {
    if (!footnoteTrailingPunctuation.has(character)) break;
    value += character;
  }
  return value;
}

export function createLiveFootnoteProjection(options: {
  selection: LiveSelectionController;
  projections: LiveProjectionIndexController;
  widgets: ProjectedWidgetRegistry;
  reuseCounts: {footnote: number};
}): {extension: Extension} {
  class FootnoteReferenceWidget extends WidgetType {
    constructor(
      readonly reference: FootnoteReferencePresentation,
      readonly trailingPunctuation: string,
    ) { super(); }

    eq(other: FootnoteReferenceWidget) {
      const equal = other.reference.identifier === this.reference.identifier
        && other.reference.ordinal === this.reference.ordinal
        && other.reference.occurrence === this.reference.occurrence
        && other.reference.from === this.reference.from
        && other.reference.definitionFrom === this.reference.definitionFrom
        && other.reference.definitionContentFrom === this.reference.definitionContentFrom
        && other.trailingPunctuation === this.trailingPunctuation;
      if (equal) options.reuseCounts.footnote += 1;
      return equal;
    }

    toDOM() {
      const cluster = document.createElement("span");
      cluster.className = "footnote-reference-cluster cm-live-footnote-reference-widget";
      cluster.dataset.scholiumProtected = "footnote";
      cluster.dataset.scholiumTrailingPunctuation = this.trailingPunctuation;
      const wrapper = document.createElement("sup");
      wrapper.className = "footnote-reference-wrap";
      const marker = document.createElement("button");
      marker.type = "button";
      marker.className = "footnote-reference";
      marker.dataset.footnote = String(this.reference.ordinal);
      marker.dataset.footnoteIdentifier = this.reference.identifier;
      marker.dataset.footnoteOccurrence = String(this.reference.occurrence);
      marker.dataset.scholiumProtected = "footnote-marker";
      marker.setAttribute("aria-controls", "scholium-preview-popover");
      marker.setAttribute("aria-expanded", "false");
      marker.setAttribute(
        "aria-label",
        localizedTemplate("Footnote {ordinal}", {ordinal: this.reference.ordinal}),
      );
      marker.textContent = String(this.reference.ordinal);
      if (this.reference.definitionFrom === null) {
        marker.setAttribute("aria-disabled", "true");
        marker.classList.add("footnote-reference-missing");
      }
      wrapper.append(marker);
      cluster.append(wrapper, this.trailingPunctuation);
      options.widgets.setFootnote(cluster, this.reference);
      return cluster;
    }

    updateDOM(dom: HTMLElement) {
      const previous = options.widgets.footnote(dom);
      const sameContent = previous
        && previous.identifier === this.reference.identifier
        && previous.ordinal === this.reference.ordinal
        && previous.occurrence === this.reference.occurrence
        && previous.definitionFrom === this.reference.definitionFrom
        && previous.definitionContentFrom === this.reference.definitionContentFrom
        && dom.dataset.scholiumTrailingPunctuation === this.trailingPunctuation;
      if (!sameContent) return false;
      options.widgets.setFootnote(dom, this.reference);
      options.reuseCounts.footnote += 1;
      return true;
    }

    ignoreEvent(event: Event) { return event.type !== "mousedown"; }
  }

  function decorations(state: EditorState, presentation: FootnotePresentation) {
    const decorationRanges: Range<Decoration>[] = [];
    const atomicDecorationRanges: Range<Decoration>[] = [];
    const projectionRanges: ProjectionSourceRange[] = [];
    const active = (from: number, to: number) =>
      options.selection.selection(state).ranges.some((range) =>
        selectionIntersectsProjection(range, {from, to}));
    for (const reference of presentation.references) {
      const containedByDefinition = presentation.definitions.some((definition) =>
        !definition.isInline && definition.from <= reference.from && definition.to >= reference.to);
      const trailing = trailingFootnotePunctuation(state, reference.to);
      const projectionTo = reference.to + trailing.length;
      projectionRanges.push({from: reference.from, to: projectionTo});
      if (containedByDefinition || active(reference.from, projectionTo)) continue;
      const replacement = Decoration.replace({
        widget: new FootnoteReferenceWidget(reference, trailing),
      }).range(reference.from, projectionTo);
      decorationRanges.push(replacement);
      atomicDecorationRanges.push(Decoration.mark({}).range(reference.from, reference.to));
    }
    return {
      decorations: Decoration.set(decorationRanges, true),
      atomicRanges: Decoration.set(atomicDecorationRanges, true),
      ranges: projectionRanges,
    };
  }

  function build(state: EditorState): LiveFootnoteReferenceState {
    const index = options.projections.index(state);
    if (index.hasUnclosedFrontmatter) {
      return {
        decorations: Decoration.none,
        atomicRanges: Decoration.none,
        hasConstructs: true,
        presentation: {definitions: [], references: []},
        ranges: [],
      };
    }
    return {
      ...decorations(state, index.footnotes),
      hasConstructs: index.footnotes.definitions.length > 0
        || index.footnotes.references.length > 0,
      presentation: index.footnotes,
    };
  }

  const field = StateField.define<LiveFootnoteReferenceState>({
    create: build,
    update(previous, transaction) {
      if (transaction.docChanged || transactionChangedSyntaxTree(transaction)) {
        return build(transaction.state);
      }
      if (!options.selection.changed(transaction.startState, transaction.state)) return previous;
      if (activeProjectionSignature(
        options.selection.selection(transaction.startState).ranges,
        previous.ranges,
      ) === activeProjectionSignature(
        options.selection.selection(transaction.state).ranges,
        previous.ranges,
      )) return previous;
      return {
        ...previous,
        ...decorations(transaction.state, previous.presentation),
      };
    },
    provide: (field) => [
      EditorView.decorations.from(field, (value) => value.decorations),
      EditorView.atomicRanges.of((view) => view.state.field(field).atomicRanges),
    ],
  });

  return {extension: field};
}
