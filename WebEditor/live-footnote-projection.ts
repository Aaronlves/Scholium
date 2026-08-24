import {Range, StateField, type EditorState, type Extension} from "@codemirror/state";
import {Decoration, DecorationSet, EditorView, WidgetType} from "@codemirror/view";
import type {
  FootnotePresentation,
  FootnoteReferencePresentation,
} from "./footnote-presentation";
import {localizedTemplate} from "./localization";
import {activeProjectionSignature, selectionIntersectsProjection} from "./projection-update";
import type {ProjectionSourceRange} from "./projection-update";
import {transactionChangedSyntaxTree} from "./projection-update";
import type {LiveProjectionIndexController} from "./live-projection-index";
import type {LiveSelectionController} from "./live-selection";
import type {ProjectedWidgetRegistry} from "./projected-widget-registry";
import type {LiveWidgetReuseCounts} from "./live-structured-block-projections";

interface LiveFootnoteReferenceState {
  readonly decorations: DecorationSet;
  readonly hasConstructs: boolean;
  readonly presentation: FootnotePresentation;
  readonly ranges: readonly Readonly<ProjectionSourceRange>[];
}

export function createLiveFootnoteProjection(options: {
  selection: LiveSelectionController;
  projections: LiveProjectionIndexController;
  widgets: ProjectedWidgetRegistry;
  reuseCounts: LiveWidgetReuseCounts;
}): {extension: Extension} {
  class FootnoteReferenceWidget extends WidgetType {
    constructor(readonly reference: FootnoteReferencePresentation) { super(); }

    eq(other: FootnoteReferenceWidget) {
      const equal = other.reference.identifier === this.reference.identifier
        && other.reference.ordinal === this.reference.ordinal
        && other.reference.occurrence === this.reference.occurrence
        && other.reference.from === this.reference.from
        && other.reference.definitionFrom === this.reference.definitionFrom
        && other.reference.definitionContentFrom === this.reference.definitionContentFrom;
      if (equal) options.reuseCounts.footnote += 1;
      return equal;
    }

    toDOM() {
      const wrapper = document.createElement("sup");
      wrapper.className = "footnote-reference-wrap cm-live-footnote-reference-widget";
      wrapper.dataset.scholiumProtected = "footnote";
      const marker = document.createElement("span");
      marker.className = "footnote-reference";
      marker.dataset.footnote = String(this.reference.ordinal);
      marker.dataset.scholiumProtected = "footnote-marker";
      marker.setAttribute(
        "aria-label",
        localizedTemplate("Footnote {ordinal}", {ordinal: this.reference.ordinal}),
      );
      marker.textContent = String(this.reference.ordinal);
      if (this.reference.definitionFrom === null) {
        marker.setAttribute("aria-disabled", "true");
        marker.classList.add("footnote-reference-missing");
      }
      options.widgets.setFootnote(wrapper, this.reference);
      wrapper.append(marker);
      return wrapper;
    }

    updateDOM(dom: HTMLElement) {
      const previous = options.widgets.footnote(dom);
      const sameContent = previous
        && previous.identifier === this.reference.identifier
        && previous.ordinal === this.reference.ordinal
        && previous.occurrence === this.reference.occurrence
        && previous.definitionFrom === this.reference.definitionFrom
        && previous.definitionContentFrom === this.reference.definitionContentFrom;
      if (!sameContent) return false;
      options.widgets.setFootnote(dom, this.reference);
      options.reuseCounts.footnote += 1;
      return true;
    }

    ignoreEvent(event: Event) { return event.type !== "mousedown"; }
  }

  function decorations(state: EditorState, presentation: FootnotePresentation) {
    const ranges: Range<Decoration>[] = [];
    const active = (from: number, to: number) =>
      options.selection.selection(state).ranges.some((range) =>
        selectionIntersectsProjection(range, {from, to}));
    for (const reference of presentation.references) {
      const containedByDefinition = presentation.definitions.some((definition) =>
        !definition.isInline && definition.from <= reference.from && definition.to >= reference.to);
      if (containedByDefinition || active(reference.from, reference.to)) continue;
      ranges.push(Decoration.replace({
        widget: new FootnoteReferenceWidget(reference),
      }).range(reference.from, reference.to));
    }
    return Decoration.set(ranges, true);
  }

  function build(state: EditorState): LiveFootnoteReferenceState {
    const index = options.projections.index(state);
    if (index.hasUnclosedFrontmatter) {
      return {
        decorations: Decoration.none,
        hasConstructs: true,
        presentation: {definitions: [], references: []},
        ranges: [],
      };
    }
    return {
      decorations: decorations(state, index.footnotes),
      hasConstructs: index.footnotes.definitions.length > 0
        || index.footnotes.references.length > 0,
      presentation: index.footnotes,
      ranges: index.footnoteRanges,
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
        decorations: decorations(transaction.state, previous.presentation),
      };
    },
    provide: (field) => [
      EditorView.decorations.from(field, (value) => value.decorations),
      EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
    ],
  });

  return {extension: field};
}
