import {Range, StateField, type EditorState, type Extension} from "@codemirror/state";
import {Decoration, DecorationSet, EditorView, WidgetType} from "@codemirror/view";
import {appendMarkdownBlocks, createTableDOM} from "./markdown-fragment";
import {calloutDefinition} from "./callout-presentation";
import type {MarkdownEditingDialect} from "./protocol";
import {
  activeProjectionSignature,
  selectionActivatesCallout,
  selectionIntersectsProjection,
  transactionChangedSyntaxTree,
  type ProjectionSourceRange,
} from "./projection-update";
import type {TablePresentation} from "./table-presentation";
import type {
  CalloutPresentation,
  LiveProjectionIndexController,
} from "./live-projection-index";
import type {LiveSelectionController} from "./live-selection";
import type {ProjectedWidgetRegistry} from "./projected-widget-registry";

interface LiveBlockProjectionState {
  readonly decorations: DecorationSet;
  readonly hasConstructs: boolean;
}

interface LiveTableProjectionState extends LiveBlockProjectionState {
  readonly presentations: readonly TablePresentation[];
}

interface RawHTMLPresentation extends ProjectionSourceRange {
  readonly source: string;
}

interface LiveRawHTMLProjectionState extends LiveBlockProjectionState {
  readonly presentations: readonly RawHTMLPresentation[];
}

interface LiveCalloutProjectionState extends LiveBlockProjectionState {
  readonly presentations: readonly CalloutPresentation[];
  readonly active: boolean;
}

export interface LiveWidgetReuseCounts {
  table: number;
  callout: number;
  footnote: number;
}

export function createLiveStructuredBlockProjections(options: {
  selection: LiveSelectionController;
  projections: LiveProjectionIndexController;
  widgets: ProjectedWidgetRegistry;
  editingDialect(): MarkdownEditingDialect | null;
  reuseCounts: LiveWidgetReuseCounts;
}): {
  tableExtension: Extension;
  rawHTMLExtension: Extension;
  calloutExtension: Extension;
} {
  const resolveCallout = (rawKind: string) =>
    calloutDefinition(options.editingDialect(), rawKind);
  const resolveVectorLink = (marker: string) =>
    options.editingDialect()?.vectorLinkOperators.find(
      (candidate) => candidate.marker === marker,
    )?.kind ?? "neutral";

  class TableWidget extends WidgetType {
    constructor(readonly presentation: TablePresentation) { super(); }

    eq(other: TableWidget) {
      const equal = other.presentation.from === this.presentation.from
        && other.presentation.to === this.presentation.to
        && other.presentation.source === this.presentation.source;
      if (equal) options.reuseCounts.table += 1;
      return equal;
    }

    toDOM() {
      const scroller = createTableDOM(this.presentation, document, {
        mathematics: options.editingDialect()?.mathematics,
        resolveCallout,
        resolveVectorLink,
      });
      scroller.classList.add("cm-live-table-widget");
      options.widgets.setTable(scroller, this.presentation);
      return scroller;
    }

    updateDOM(dom: HTMLElement) {
      const previous = options.widgets.table(dom);
      if (!previous || previous.source !== this.presentation.source) return false;
      const elements = [...dom.querySelectorAll<HTMLElement>("[data-source-offset]")];
      const previousOffsets = [...previous.header, ...previous.body.flat()]
        .map((cell) => cell.sourceOffset);
      const nextOffsets = [...this.presentation.header, ...this.presentation.body.flat()]
        .map((cell) => cell.sourceOffset);
      if (elements.length !== previousOffsets.length || elements.length !== nextOffsets.length) {
        return false;
      }
      elements.forEach((element, index) => {
        element.dataset.sourceOffset = String(nextOffsets[index]);
      });
      options.widgets.setTable(dom, this.presentation);
      options.reuseCounts.table += 1;
      return true;
    }

    ignoreEvent(event: Event) { return event.type !== "mousedown"; }
  }

  function tableDecorations(
    state: EditorState,
    presentations: readonly TablePresentation[],
  ) {
    return Decoration.set(presentations.flatMap((presentation): Range<Decoration>[] => {
      const active = options.selection.selection(state).ranges.some((range) =>
        selectionIntersectsProjection(range, presentation));
      if (active) return [];
      return [Decoration.replace({
        widget: new TableWidget(presentation),
        block: true,
      }).range(presentation.from, presentation.to)];
    }), true);
  }

  function buildTable(state: EditorState): LiveTableProjectionState {
    const index = options.projections.index(state);
    if (index.hasUnclosedFrontmatter) {
      return {decorations: Decoration.none, hasConstructs: true, presentations: []};
    }
    return {
      decorations: tableDecorations(state, index.tables),
      hasConstructs: index.tables.length > 0,
      presentations: index.tables,
    };
  }

  const tableField = StateField.define<LiveTableProjectionState>({
    create: buildTable,
    update(previous, transaction) {
      if (transaction.docChanged || transactionChangedSyntaxTree(transaction)) {
        return buildTable(transaction.state);
      }
      if (!options.selection.changed(transaction.startState, transaction.state)) return previous;
      if (activeProjectionSignature(
        options.selection.selection(transaction.startState).ranges,
        previous.presentations,
      ) === activeProjectionSignature(
        options.selection.selection(transaction.state).ranges,
        previous.presentations,
      )) return previous;
      return {
        ...previous,
        decorations: tableDecorations(transaction.state, previous.presentations),
      };
    },
    provide: (field) => [
      EditorView.decorations.from(field, (value) => value.decorations),
      EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
    ],
  });

  class RawHTMLWidget extends WidgetType {
    constructor(readonly presentation: RawHTMLPresentation) { super(); }
    eq(other: RawHTMLWidget) { return other.presentation.source === this.presentation.source; }
    toDOM() {
      const pre = document.createElement("pre");
      pre.className = [
        "raw-html",
        "cm-live-raw-html",
        "cm-live-raw-html-start",
        "cm-live-raw-html-end",
        "cm-live-raw-html-widget",
      ].join(" ");
      pre.dataset.scholiumProtected = "raw-html";
      pre.textContent = this.presentation.source;
      return pre;
    }
    ignoreEvent() { return false; }
  }

  function rawHTMLDecorations(
    state: EditorState,
    presentations: readonly RawHTMLPresentation[],
  ) {
    return Decoration.set(presentations.flatMap((presentation): Range<Decoration>[] => {
      const active = options.selection.selection(state).ranges.some((range) =>
        selectionIntersectsProjection(range, presentation));
      if (active) return [];
      return [Decoration.replace({
        widget: new RawHTMLWidget(presentation),
        block: true,
      }).range(presentation.from, presentation.to)];
    }), true);
  }

  function buildRawHTML(state: EditorState): LiveRawHTMLProjectionState {
    const index = options.projections.index(state);
    if (index.hasUnclosedFrontmatter) {
      return {decorations: Decoration.none, hasConstructs: true, presentations: []};
    }
    const presentations = index.syntax.blocks
      .filter((block) => block.kind === "html")
      .map((block): RawHTMLPresentation => ({
        from: block.from,
        to: block.to,
        source: state.doc.sliceString(block.from, block.to),
      }));
    return {
      decorations: rawHTMLDecorations(state, presentations),
      hasConstructs: presentations.length > 0,
      presentations,
    };
  }

  const rawHTMLField = StateField.define<LiveRawHTMLProjectionState>({
    create: buildRawHTML,
    update(previous, transaction) {
      if (transaction.docChanged || transactionChangedSyntaxTree(transaction)) {
        return buildRawHTML(transaction.state);
      }
      if (!options.selection.changed(transaction.startState, transaction.state)) return previous;
      if (activeProjectionSignature(
        options.selection.selection(transaction.startState).ranges,
        previous.presentations,
      ) === activeProjectionSignature(
        options.selection.selection(transaction.state).ranges,
        previous.presentations,
      )) return previous;
      return {
        ...previous,
        decorations: rawHTMLDecorations(transaction.state, previous.presentations),
      };
    },
    provide: (field) => [
      EditorView.decorations.from(field, (value) => value.decorations),
      EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
    ],
  });

  class CalloutWidget extends WidgetType {
    constructor(readonly presentation: CalloutPresentation) { super(); }

    eq(other: CalloutWidget) {
      const equal = other.presentation.from === this.presentation.from
        && other.presentation.to === this.presentation.to
        && other.presentation.source === this.presentation.source;
      if (equal) options.reuseCounts.callout += 1;
      return equal;
    }

    toDOM(view: EditorView) {
      const slot = document.createElement("div");
      slot.className = "cm-live-callout-slot";
      appendMarkdownBlocks(this.presentation.source, slot, {
        mathematics: options.editingDialect()?.mathematics,
        resolveCallout,
        resolveVectorLink,
        sourceOffset: (offset) => this.presentation.from + offset,
      });
      const callout = slot.firstElementChild;
      if (!(callout instanceof HTMLElement) || !callout.classList.contains("scholium-callout")) {
        const fallback = document.createElement("pre");
        fallback.className = "cm-live-callout-widget cm-live-callout-widget-fallback";
        fallback.textContent = this.presentation.source;
        slot.replaceChildren(fallback);
        return slot;
      }
      slot.replaceChildren(callout);
      callout.classList.add("cm-live-callout-widget");
      options.widgets.setCallout(slot, this.presentation);
      if (callout instanceof HTMLDetailsElement) {
        let measurePending = false;
        callout.addEventListener("toggle", () => {
          if (measurePending) return;
          measurePending = true;
          queueMicrotask(() => {
            measurePending = false;
            view.requestMeasure();
          });
        });
      }
      return slot;
    }

    updateDOM(dom: HTMLElement) {
      const previous = options.widgets.callout(dom);
      if (!previous || previous.source !== this.presentation.source) return false;
      options.widgets.setCallout(dom, this.presentation);
      options.reuseCounts.callout += 1;
      return true;
    }

    ignoreEvent(event: Event) {
      const foldMark = event.target instanceof Element
        && event.target.closest(".scholium-callout-fold-mark");
      return foldMark !== null || event.type !== "mousedown";
    }
  }

  function calloutDecorations(
    state: EditorState,
    presentations: readonly CalloutPresentation[],
  ) {
    const selections = options.selection.selection(state).ranges;
    return Decoration.set(presentations.flatMap((presentation): Range<Decoration>[] => {
      const active = selections.some((range) => selectionActivatesCallout(range, presentation));
      if (active) return [];
      return [Decoration.replace({
        widget: new CalloutWidget(presentation),
        block: true,
      }).range(presentation.from, presentation.to)];
    }), true);
  }

  function buildCallout(state: EditorState): LiveCalloutProjectionState {
    const index = options.projections.index(state);
    if (index.hasUnclosedFrontmatter) {
      return {
        decorations: Decoration.none,
        hasConstructs: true,
        presentations: [],
        active: false,
      };
    }
    const active = index.callouts.some((presentation) =>
      options.selection.selection(state).ranges.some((range) =>
        selectionActivatesCallout(range, presentation)));
    return {
      decorations: calloutDecorations(state, index.callouts),
      hasConstructs: index.callouts.length > 0,
      presentations: index.callouts,
      active,
    };
  }

  const calloutField = StateField.define<LiveCalloutProjectionState>({
    create: buildCallout,
    update(previous, transaction) {
      if (transaction.docChanged || transactionChangedSyntaxTree(transaction)) {
        return buildCallout(transaction.state);
      }
      if (!options.selection.changed(transaction.startState, transaction.state)) return previous;
      return buildCallout(transaction.state);
    },
    provide: (field) => [
      EditorView.decorations.from(field, (value) => value.decorations),
      EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
      EditorView.editorAttributes.from(field, (value): Record<string, string> => value.active
        ? {"data-scholium-active-live-block": "callout"}
        : {}),
    ],
  });

  return {
    tableExtension: tableField,
    rawHTMLExtension: rawHTMLField,
    calloutExtension: calloutField,
  };
}
