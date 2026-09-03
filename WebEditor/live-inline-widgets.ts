import {Transaction} from "@codemirror/state";
import {EditorView, WidgetType} from "@codemirror/view";
import type {MathProjection} from "./math";
import {localized, localizedTemplate} from "./localization";
import {populatePreviewDocument} from "./preview-popover";
import type {LinkPreview} from "./previews";
import {systemSymbolElement} from "./system-symbols";
import {toggledTaskMarker} from "./transformations";
import {appendMarkdownBlocks} from "./markdown-fragment";

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

  class LinkAnnotationWidget extends WidgetType {
    constructor(
      readonly markdown: string,
      readonly target: string,
    ) { super(); }

    eq(other: LinkAnnotationWidget) {
      return other.markdown === this.markdown && other.target === this.target;
    }

    toDOM() {
      const wrapper = document.createElement("sup");
      wrapper.className = "scholium-link-annotation-disclosure";
      wrapper.dataset.scholiumProtected = "link-annotation";
      const button = document.createElement("button");
      button.type = "button";
      button.className = "scholium-link-annotation-button";
      button.dataset.linkAnnotation = "true";
      button.dataset.linkAnnotationTarget = this.target;
      button.setAttribute("aria-expanded", "false");
      button.setAttribute("aria-controls", "scholium-preview-popover");
      button.setAttribute("aria-label", `${localized("Show Link Annotation")} ${this.target}`);
      button.append(systemSymbolElement("text-bubble", "scholium-link-annotation-icon"));
      const template = document.createElement("template");
      template.className = "scholium-link-annotation-template";
      const content = document.createElement("span");
      content.className = "scholium-link-annotation-content";
      appendMarkdownBlocks(this.markdown, content);
      template.content.append(content);
      button.addEventListener("mousedown", (event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        event.stopPropagation();
      });
      wrapper.append(button, template);
      return wrapper;
    }

    ignoreEvent(event: Event) {
      const target = event.target instanceof Element ? event.target : null;
      return Boolean(target?.closest(".scholium-link-annotation-disclosure"));
    }
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
      open.className = "cm-live-wiki-link scholium-embedded-note-open";
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

  return {
    embeddedNote: (preview: LinkPreview, target: string, sourceCaret: number) =>
      new EmbeddedNoteWidget(preview, target, sourceCaret),
    listIndent,
    listMarker: (value: ListMarkerOptions) => new ListMarkerWidget(value),
    math: (expression: MathProjection) => new MathWidget(expression),
    linkAnnotation: (markdown: string, target: string) =>
      new LinkAnnotationWidget(markdown, target),
  };
}
