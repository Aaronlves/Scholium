import {Transaction} from "@codemirror/state";
import {EditorView, WidgetType} from "@codemirror/view";
import type {MathProjection} from "./math";
import {localized, localizedTemplate} from "./localization";
import {populatePreviewDocument} from "./preview-popover";
import type {LinkPreview, VectorLinkKind} from "./previews";
import {systemSymbolElement} from "./system-symbols";
import {toggledTaskMarker} from "./transformations";
import {vectorLinkSemantics} from "./markdown-fragment";

interface ListMarkerOptions {
  marker: string;
  markerFrom: number;
  markerTo: number;
  ordered: boolean;
  depth: number;
  task: boolean;
  taskMarkerFrom: number | null;
  taskMarkerTo: number | null;
  taskChecked: boolean;
}

interface WikilinkPresentation {
  displayStart: number;
  displayEnd: number;
  isLegacyRelationship: boolean;
}

const legacyRelationshipPredicates = new Set([
  "supports", "contradicts", "extends", "refines", "incompatible_with",
  "cites", "see_also", "connected", "answers", "subquestion_of", "premise_of",
  "concludes", "assumes", "pressures", "uses_concept", "has_commitment", "targets",
  "objects_to", "rebuts", "undercuts", "replies_to", "concedes", "depends_on",
  "supersedes", "qualifies", "elicits", "tests", "illustrates", "counterexample_to",
  "evidence_for", "attributes_to", "interprets", "derived_from", "is_case_for",
  "is_source_for", "is_background_for", "is_not_evidence_for",
]);

function isLegacyRelationshipPredicate(raw: string): boolean {
  const normalized = raw.trim().toLowerCase().replaceAll("-", "_");
  if (legacyRelationshipPredicates.has(normalized)) return true;
  return [
    "seealso", "objectsto", "repliesto", "dependson", "iscasefor", "issourcefor",
    "isbackgroundfor", "isnotevidencefor",
  ].includes(normalized);
}

export function createLiveInlineWidgets(options: {
  requestMathRuntime(): void;
  didToggleTask(): void;
}) {
  function listIndent(depth: number) {
    if (depth <= 0) return "";
    return `calc(${Array.from(
      {length: depth},
      () => "var(--scholium-list-indent)",
    ).join(" + ")})`;
  }

  class ListMarkerWidget extends WidgetType {
    constructor(readonly value: ListMarkerOptions) { super(); }

    eq(other: ListMarkerWidget) {
      return other.value.marker === this.value.marker
        && other.value.markerFrom === this.value.markerFrom
        && other.value.markerTo === this.value.markerTo
        && other.value.ordered === this.value.ordered
        && other.value.depth === this.value.depth
        && other.value.task === this.value.task
        && other.value.taskMarkerFrom === this.value.taskMarkerFrom
        && other.value.taskMarkerTo === this.value.taskMarkerTo
        && other.value.taskChecked === this.value.taskChecked;
    }

    toDOM(view: EditorView) {
      const span = document.createElement("span");
      span.className = [
        "cm-live-list-marker",
        this.value.ordered
          ? "cm-live-list-marker-ordered"
          : "cm-live-list-marker-unordered",
        this.value.task ? "cm-live-list-marker-task" : "",
      ].filter(Boolean).join(" ");
      const indent = listIndent(this.value.depth);
      if (indent) span.style.marginInlineStart = indent;
      const projected = this.value.task
        ? this.taskCheckbox(view)
        : document.createElement("span");
      projected.classList.add("cm-live-list-marker-projected");
      if (!this.value.task) {
        projected.textContent = this.value.ordered
          ? this.value.marker
          : this.value.depth > 0 ? "◦" : "•";
        span.addEventListener("mousedown", (event) => {
          if (event.button !== 0 || view.composing) return;
          event.preventDefault();
          event.stopPropagation();
          if (this.value.markerFrom < 0
              || this.value.markerTo <= this.value.markerFrom
              || this.value.markerTo > view.state.doc.length) return;
          view.dispatch({
            selection: {anchor: this.value.markerFrom},
            scrollIntoView: true,
          });
          view.focus();
        });
      }
      span.append(projected);
      if (!this.value.task) span.setAttribute("aria-hidden", "true");
      return span;
    }

    private taskCheckbox(view: EditorView) {
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "cm-live-task-checkbox";
      checkbox.checked = this.value.taskChecked;
      checkbox.tabIndex = -1;
      checkbox.setAttribute("aria-label", localized("Task item"));
      checkbox.addEventListener("mousedown", (event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        event.stopPropagation();
      });
      checkbox.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        this.toggleTask(view);
      });
      return checkbox;
    }

    private toggleTask(view: EditorView) {
      const {taskMarkerFrom, taskMarkerTo} = this.value;
      if (view.composing || taskMarkerFrom === null || taskMarkerTo === null) return;
      const current = view.state.doc.sliceString(taskMarkerFrom, taskMarkerTo);
      const insert = toggledTaskMarker(current);
      if (insert === null) return;
      view.dispatch({
        changes: {from: taskMarkerFrom, to: taskMarkerTo, insert},
        annotations: Transaction.userEvent.of("input.scholium.toggleTask"),
      });
      options.didToggleTask();
      view.focus();
    }

    ignoreEvent(event: Event) {
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest(".cm-live-task-checkbox")) {
        return !(event instanceof MouseEvent) || event.button === 0;
      }
      if (target?.closest(".cm-live-list-marker") && event instanceof MouseEvent) {
        return event.button === 0;
      }
      return false;
    }
  }

  class VectorLinkIconWidget extends WidgetType {
    constructor(readonly kind: VectorLinkKind) { super(); }
    eq(other: VectorLinkIconWidget) { return other.kind === this.kind; }
    toDOM() {
      const semantics = vectorLinkSemantics[this.kind];
      const span = systemSymbolElement(
        semantics.symbol,
        `cm-live-vector-icon cm-live-vector-icon-${this.kind.replaceAll("_", "-")}`,
      );
      span.title = semantics.label;
      return span;
    }
    ignoreEvent() { return false; }
  }

  class EmbeddedNoteWidget extends WidgetType {
    constructor(
      readonly preview: LinkPreview,
      readonly target: string,
      readonly sourceCaret: number,
    ) { super(); }

    eq(other: EmbeddedNoteWidget) {
      return other.target === this.target
        && other.sourceCaret === this.sourceCaret
        && other.preview.title === this.preview.title
        && other.preview.htmlBody === this.preview.htmlBody;
    }

    toDOM() {
      const shell = document.createElement("section");
      shell.className = "scholium-embedded-note cm-live-embedded-note-widget";
      shell.dataset.scholiumProtected = "embedded-note";
      shell.dataset.scholiumSourceCaret = String(this.sourceCaret);
      shell.setAttribute("role", "group");
      shell.setAttribute(
        "aria-label",
        localizedTemplate("Embedded note {title}", {title: this.preview.title}),
      );

      const header = document.createElement("header");
      header.className = "scholium-embedded-note-header";
      const open = document.createElement("span");
      open.className = "cm-live-vector-link cm-live-vector-neutral scholium-embedded-note-open";
      open.dir = "auto";
      open.dataset.scholiumLinkTarget = this.target;
      open.dataset.scholiumSourceCaret = String(this.sourceCaret);
      open.setAttribute(
        "aria-label",
        localizedTemplate("Open embedded note {title}", {title: this.preview.title}),
      );
      open.append(document.createTextNode(this.preview.title));
      header.append(open);

      const viewport = document.createElement("div");
      viewport.className = "scholium-embedded-note-viewport";
      viewport.tabIndex = 0;
      viewport.setAttribute("role", "region");
      viewport.setAttribute(
        "aria-label",
        localizedTemplate("Embedded note content for {title}", {title: this.preview.title}),
      );
      const body = document.createElement("div");
      body.className = "scholium-embedded-note-body scholium-document";
      populatePreviewDocument(body, this.preview);
      viewport.append(body);
      shell.append(header, viewport);
      return shell;
    }

    ignoreEvent(event: Event) {
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest(".scholium-embedded-note-viewport")) return true;
      return event.type !== "mousedown";
    }
  }

  class MathWidget extends WidgetType {
    constructor(readonly expression: MathProjection) { super(); }

    eq(other: MathWidget) {
      return other.expression.kind === this.expression.kind
        && other.expression.content === this.expression.content
        && other.expression.delimiterLength === this.expression.delimiterLength;
    }

    toDOM() {
      const element = document.createElement("span");
      element.className = `scholium-math scholium-math-${this.expression.kind} cm-live-math`;
      element.dataset.scholiumProtected = "math";

      const runtime = window.scholiumMath;
      if (runtime?.version !== 1) options.requestMathRuntime();
      const rendered = runtime?.version === 1
        ? runtime.render({source: this.expression.content, kind: this.expression.kind})
        : {ok: false as const, reason: "invalid-source" as const};
      if (rendered.ok) {
        element.classList.add("scholium-math-rendered");
        const output = document.createElement("span");
        output.className = "scholium-math-output";
        output.innerHTML = rendered.html;
        element.append(output);
      } else {
        const source = document.createElement("code");
        const delimiter = "$".repeat(this.expression.delimiterLength);
        source.className = "scholium-math-source";
        source.textContent = this.expression.kind === "display"
          ? `${delimiter}\n${this.expression.content}\n${delimiter}`
          : `${delimiter}${this.expression.content}${delimiter}`;
        element.classList.add("scholium-math-error");
        element.setAttribute(
          "aria-label",
          localized("Mathematics could not be rendered. Source is shown."),
        );
        element.append(source);
      }
      if (this.expression.kind === "display") {
        const slot = document.createElement("div");
        slot.className = "cm-live-math-slot";
        slot.append(element);
        return slot;
      }
      return element;
    }

    ignoreEvent() { return false; }
  }

  function wikilinkPresentation(
    targetStart: number,
    target: string,
    annotationStart: number | null,
    annotation: string | undefined,
  ): WikilinkPresentation {
    const targetPresentation = {
      displayStart: targetStart,
      displayEnd: targetStart + target.length,
      isLegacyRelationship: false,
    };
    if (annotationStart === null || annotation === undefined) return targetPresentation;

    const trimmed = annotation.trim();
    if (trimmed.startsWith(":") && isLegacyRelationshipPredicate(trimmed.slice(1))) {
      return {...targetPresentation, isLegacyRelationship: true};
    }
    const lastColon = trimmed.lastIndexOf(":");
    if (lastColon >= 0 && isLegacyRelationshipPredicate(trimmed.slice(lastColon + 1))) {
      const rawAlias = trimmed.slice(0, lastColon);
      const alias = rawAlias.trim();
      if (!alias) return {...targetPresentation, isLegacyRelationship: true};
      const trimmedOffset = annotation.indexOf(trimmed);
      const aliasOffset = rawAlias.indexOf(alias);
      const displayStart = annotationStart + trimmedOffset + aliasOffset;
      return {
        displayStart,
        displayEnd: displayStart + alias.length,
        isLegacyRelationship: true,
      };
    }
    return {
      displayStart: annotationStart,
      displayEnd: annotationStart + annotation.length,
      isLegacyRelationship: false,
    };
  }

  return {
    embeddedNote: (preview: LinkPreview, target: string, sourceCaret: number) =>
      new EmbeddedNoteWidget(preview, target, sourceCaret),
    listIndent,
    listMarker: (value: ListMarkerOptions) => new ListMarkerWidget(value),
    math: (expression: MathProjection) => new MathWidget(expression),
    vectorLinkIcon: (kind: VectorLinkKind) => new VectorLinkIconWidget(kind),
    wikilinkPresentation,
  };
}
