import {
  Range,
  StateField,
  type EditorState,
  type Extension,
  type StateEffectType,
} from "@codemirror/state";
import {Decoration, DecorationSet, EditorView, WidgetType} from "@codemirror/view";
import {localized, localizedTemplate} from "./localization";
import {mermaidPresentation, type MermaidPresentation} from "./mermaid-presentation";
import {
  activeProjectionSignature,
  selectionIntersectsProjection,
  transactionChangedSyntaxTree,
} from "./projection-update";
import type {LiveProjectionIndexController} from "./live-projection-index";
import type {LiveSelectionController} from "./live-selection";
import type {ProjectedWidgetRegistry} from "./projected-widget-registry";

interface LiveMermaidProjectionState {
  readonly decorations: DecorationSet;
  readonly hasConstructs: boolean;
  readonly presentations: readonly MermaidPresentation[];
  readonly themeRevision: number;
}

function appendDiagnostic(wrapper: HTMLElement, message: string) {
  const diagnostic = document.createElement("p");
  diagnostic.className = "scholium-mermaid-diagnostic";
  diagnostic.textContent = message;
  wrapper.append(diagnostic);
}

export function createLiveMermaidProjection(options: {
  selection: LiveSelectionController;
  projections: LiveProjectionIndexController;
  widgets: ProjectedWidgetRegistry;
  ensureRuntime(): Promise<NonNullable<typeof window.scholiumMermaid> | null>;
  currentThemeRevision(): number;
  refreshThemeEffect: StateEffectType<number>;
}): {extension: Extension; presentations(state: EditorState): readonly MermaidPresentation[]} {
  const abortControllers = new WeakMap<HTMLElement, AbortController>();

  class MermaidWidget extends WidgetType {
    constructor(
      readonly presentation: MermaidPresentation,
      readonly themeRevision: number,
    ) { super(); }

    eq(other: MermaidWidget) {
      return other.presentation.source === this.presentation.source
        && other.themeRevision === this.themeRevision;
    }

    toDOM(view: EditorView) {
      const slot = document.createElement("div");
      slot.className = "cm-live-mermaid-slot cm-live-mermaid-widget";
      options.widgets.setMermaid(slot, this.presentation);
      const wrapper = document.createElement("figure");
      wrapper.className = "scholium-mermaid";
      wrapper.dataset.scholiumProtected = "mermaid";
      const fallback = document.createElement("pre");
      fallback.className = "scholium-mermaid-source";
      const code = document.createElement("code");
      code.textContent = this.presentation.source;
      fallback.append(code);
      wrapper.append(fallback);
      slot.append(wrapper);
      const abortController = new AbortController();
      abortControllers.set(slot, abortController);

      void options.ensureRuntime().then(async (runtime) => {
        if (abortController.signal.aborted || !slot.isConnected) return;
        if (!runtime) {
          wrapper.classList.add("scholium-mermaid-error");
          appendDiagnostic(
            wrapper,
            localized("Diagram rendering is unavailable. Mermaid source is shown."),
          );
          view.requestMeasure();
          return;
        }
        const result = await runtime.render({
          source: this.presentation.content,
          themeRoot: document.documentElement,
          signal: abortController.signal,
        });
        if (abortController.signal.aborted
            || !slot.isConnected
            || (!result.ok && result.reason === "cancelled")) return;
        if (!result.ok) {
          wrapper.classList.add("scholium-mermaid-error");
          appendDiagnostic(
            wrapper,
            localized("This Mermaid diagram is unsupported or could not be rendered. Source is shown."),
          );
          view.requestMeasure();
          return;
        }
        const output = document.createElement("div");
        output.className = "scholium-mermaid-output";
        if (!runtime.mount(output, result.svg)) {
          wrapper.classList.add("scholium-mermaid-error");
          appendDiagnostic(
            wrapper,
            localized("This Mermaid diagram could not be isolated safely. Source is shown."),
          );
          view.requestMeasure();
          return;
        }
        wrapper.prepend(output);
        wrapper.classList.add("scholium-mermaid-rendered");
        if (result.accessibilityWarning) {
          const accessibleSource = document.createElement("span");
          accessibleSource.className = "scholium-mermaid-accessible-source";
          accessibleSource.textContent = localizedTemplate(
            "Mermaid source: {source}",
            {source: this.presentation.content},
          );
          wrapper.append(accessibleSource);
          appendDiagnostic(
            wrapper,
            localized("Add accTitle and accDescr to provide a concise nonvisual account of this diagram."),
          );
        }
        view.requestMeasure();
      }).catch(() => {
        if (abortController.signal.aborted || !slot.isConnected) return;
        wrapper.classList.add("scholium-mermaid-error");
        appendDiagnostic(
          wrapper,
          localized("This Mermaid diagram could not be rendered. Source is shown."),
        );
        view.requestMeasure();
      });
      return slot;
    }

    destroy(dom: HTMLElement) {
      abortControllers.get(dom)?.abort();
      abortControllers.delete(dom);
    }

    ignoreEvent(event: Event) { return event.type !== "mousedown"; }
  }

  function decorations(
    state: EditorState,
    presentations: readonly MermaidPresentation[],
    themeRevision: number,
  ) {
    return Decoration.set(presentations.flatMap((presentation): Range<Decoration>[] => {
      const active = options.selection.selection(state).ranges.some((range) =>
        selectionIntersectsProjection(range, presentation));
      if (active) return [];
      return [Decoration.replace({
        widget: new MermaidWidget(presentation, themeRevision),
        block: true,
      }).range(presentation.from, presentation.to)];
    }), true);
  }

  function build(
    state: EditorState,
    themeRevision = options.currentThemeRevision(),
  ): LiveMermaidProjectionState {
    const index = options.projections.index(state);
    if (index.hasUnclosedFrontmatter) {
      return {decorations: Decoration.none, hasConstructs: true, presentations: [], themeRevision};
    }
    const presentations = index.literals.codeBlocks.flatMap((block) => {
      const presentation = mermaidPresentation(state.doc, block);
      return presentation ? [presentation] : [];
    });
    return {
      decorations: decorations(state, presentations, themeRevision),
      hasConstructs: presentations.length > 0,
      presentations,
      themeRevision,
    };
  }

  const field = StateField.define<LiveMermaidProjectionState>({
    create: build,
    update(previous, transaction) {
      const refreshedTheme = transaction.effects.find((effect) =>
        effect.is(options.refreshThemeEffect));
      if (transaction.docChanged || transactionChangedSyntaxTree(transaction) || refreshedTheme) {
        return build(
          transaction.state,
          refreshedTheme?.value ?? options.currentThemeRevision(),
        );
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
        decorations: decorations(
          transaction.state,
          previous.presentations,
          previous.themeRevision,
        ),
      };
    },
    provide: (field) => [
      EditorView.decorations.from(field, (value) => value.decorations),
      EditorView.atomicRanges.of((view) => view.state.field(field).decorations),
    ],
  });

  return {
    extension: field,
    presentations: (state) => state.field(field).presentations,
  };
}
