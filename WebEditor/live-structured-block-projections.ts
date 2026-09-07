import {Range, StateEffect, StateField, type EditorState, type Extension} from "@codemirror/state";
import {Decoration, DecorationSet, EditorView, WidgetType} from "@codemirror/view";
import {createTableDOM} from "./markdown-fragment";
import {localized} from "./localization";
import {calloutDefinition, calloutHeader} from "./callout-presentation";
import type {MarkdownEditingDialect} from "./protocol";
import {
  activeProjectionSignature,
  selectionActivatesSyntax,
  transactionChangedSyntaxTree,
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

interface LiveCalloutProjectionState extends LiveBlockProjectionState {
  readonly presentations: readonly CalloutPresentation[];
  readonly active: boolean;
  readonly folds: ReadonlyMap<number, boolean>;
}

export function createLiveStructuredBlockProjections(options: {
  selection: LiveSelectionController;
  projections: LiveProjectionIndexController;
  widgets: ProjectedWidgetRegistry;
  editingDialect(): MarkdownEditingDialect | null;
  reuseCounts: {table: number};
}): {
  tableExtension: Extension;
  calloutExtension: Extension;
} {
  const resolveCallout = (rawKind: string) =>
    calloutDefinition(options.editingDialect(), rawKind);
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
        selectionActivatesSyntax(range, presentation));
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

  const setCalloutFold = StateEffect.define<{from: number; collapsed: boolean}>({
    map: (value, changes) => ({...value, from: changes.mapPos(value.from)}),
  });

  class CalloutHeadingWidget extends WidgetType {
    constructor(readonly from: number, readonly label: string, readonly title: string,
      readonly foldable: boolean, readonly collapsed: boolean) { super(); }
    eq(other: CalloutHeadingWidget) {
      return this.from === other.from && this.label === other.label && this.title === other.title
        && this.foldable === other.foldable && this.collapsed === other.collapsed;
    }
    toDOM(view: EditorView) {
      const root = document.createElement("span");
      root.className = "cm-live-callout-heading-control";
      root.dataset.calloutFrom = String(this.from);
      if (this.foldable) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "cm-live-callout-disclosure";
        button.textContent = this.collapsed ? "▸" : "▾";
        button.setAttribute("aria-expanded", String(!this.collapsed));
        button.setAttribute("aria-label", `${localized("Callout")}: ${this.title || this.label}`);
        button.addEventListener("mousedown", event => event.preventDefault());
        button.addEventListener("click", () => {
          const from = Number(root.dataset.calloutFrom);
          const collapsed = button.getAttribute("aria-expanded") === "true";
          view.dispatch({
            ...(collapsed ? {selection: {anchor: from}} : {}),
            effects: setCalloutFold.of({from, collapsed}),
          });
        });
        root.append(button);
      }
      if (this.label) {
        const label = document.createElement("span");
        label.className = "cm-live-callout-role-label";
        label.textContent = `${this.label} `;
        root.append(label);
      }
      return root;
    }
    updateDOM(root: HTMLElement) {
      const button = root.querySelector("button");
      const label = root.querySelector(".cm-live-callout-role-label");
      if (!!button !== this.foldable || !!label !== !!this.label) return false;
      root.dataset.calloutFrom = String(this.from);
      if (button) {
        button.textContent = this.collapsed ? "▸" : "▾";
        button.setAttribute("aria-expanded", String(!this.collapsed));
        button.setAttribute("aria-label", `${localized("Callout")}: ${this.title || this.label}`);
      }
      if (label) label.textContent = `${this.label} `;
      return true;
    }
    ignoreEvent() { return true; }
  }

  function calloutDecorations(state: EditorState,
    presentations: readonly CalloutPresentation[], folds: ReadonlyMap<number, boolean>) {
    const selections = options.selection.selection(state).ranges;
    const decorations: Range<Decoration>[] = [];
    for (const presentation of presentations) {
      const header = state.doc.lineAt(presentation.from);
      const opening = calloutHeader(header.text);
      if (!opening) continue;
      const foldable = !!opening[3];
      const bodyActive = selections.some(range => range.empty
        ? range.head > header.to && range.head <= presentation.to
        : range.from < presentation.to && range.to > header.to);
      const collapsed = foldable && !bodyActive
        && (folds.get(presentation.from) ?? opening[3] === "-");
      const label = resolveCallout(opening[2]).label;
      if (foldable || label) decorations.push(Decoration.widget({
        widget: new CalloutHeadingWidget(presentation.from, label, opening[4], foldable, collapsed),
        side: 1,
      }).range(header.to - opening[4].length));
      if (collapsed) decorations.push(Decoration.line({class: "cm-live-callout-end"}).range(header.from));
      if (collapsed && presentation.to > header.to) {
        decorations.push(Decoration.replace({}).range(header.to, presentation.to));
      }
    }
    return Decoration.set(decorations, true);
  }

  function buildCallout(state: EditorState, folds: ReadonlyMap<number, boolean> = new Map()): LiveCalloutProjectionState {
    const index = options.projections.index(state);
    if (index.hasUnclosedFrontmatter) {
      return {
        decorations: Decoration.none,
        hasConstructs: true,
        presentations: [],
        active: false,
        folds,
      };
    }
    const active = index.callouts.some((presentation) =>
      options.selection.selection(state).ranges.some((range) =>
        selectionActivatesSyntax(range, presentation)));
    return {
      decorations: calloutDecorations(state, index.callouts, folds),
      folds,
      hasConstructs: index.callouts.length > 0,
      presentations: index.callouts,
      active,
    };
  }

  const calloutField = StateField.define<LiveCalloutProjectionState>({
    create: buildCallout,
    update(previous, transaction) {
      let folds = new Map(previous.folds);
      if (transaction.docChanged) {
        const current = options.projections.index(transaction.state).callouts;
        folds = new Map([...folds].flatMap(([from, collapsed]) => {
          const mapped = transaction.changes.mapPos(from);
          const oldHeader = previous.presentations.find(item => item.from === from)?.source.split("\n", 1)[0];
          const newHeader = current.find(item => item.from === mapped)?.source.split("\n", 1)[0];
          // An authored header change supersedes a transient disclosure choice.
          return newHeader !== undefined && oldHeader === newHeader ? [[mapped, collapsed] as const] : [];
        }));
      }
      let foldChanged = false;
      for (const effect of transaction.effects) if (effect.is(setCalloutFold)) {
        folds.set(effect.value.from, effect.value.collapsed);
        foldChanged = true;
      }
      if (foldChanged || transaction.docChanged || transactionChangedSyntaxTree(transaction)
        || options.selection.changed(transaction.startState, transaction.state)) {
        return buildCallout(transaction.state, folds);
      }
      return previous;
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
    calloutExtension: calloutField,
  };
}
