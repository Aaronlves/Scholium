import {StateEffect, StateField} from "@codemirror/state";
import {EditorView, panels, showPanel, type PanelConstructor} from "@codemirror/view";
import {localized} from "./localization";

interface DocumentTitleOptions {
  /** Existing attachment identity; this feature never owns another generation. */
  attachment(): number;
  isSuspended(): boolean;
  requestID(): string;
  dispatch(effect: StateEffect<null>): void;
  requestRename(request: {requestID: string; expectedTitle: string; requestedTitle: string}): void;
  focusChanged(): void;
  /** These enter/leave the editor's shared composition gate. */
  beginComposition(): void;
  endComposition(): void;
}

/** Owns the filename control and its pending rename, never Markdown or history. */
export function createDocumentTitle(options: DocumentTitleOptions) {
  const refreshDocumentTitleEffect = StateEffect.define<null>();
  let documentTitle = "";
  let documentTitleDraft: string | null = null;
  let documentTitleError: string | null = null;
  let documentTitleRenameRequest: {
    requestID: string;
    requestedTitle: string;
  } | null = null;
  let documentTitlePresentationRevision = 0;

  function createTitleControl() {
    const attachment = options.attachment();
    const wrapper = document.createElement("div");
    wrapper.className = "cm-live-note-title scholium-note-title";
    wrapper.setAttribute("role", "heading");
    wrapper.setAttribute("aria-level", "1");
    wrapper.setAttribute("aria-label", documentTitleDraft ?? documentTitle);
    wrapper.setAttribute("dir", "auto");
    wrapper.setAttribute("data-scholium-protected", "note-title");

    const input = document.createElement("textarea");
    input.className = "scholium-note-title-input";
    input.value = documentTitleDraft ?? documentTitle;
    input.rows = 1;
    input.wrap = "soft";
    input.spellcheck = false;
    input.maxLength = 1_024;
    input.setAttribute("aria-label", localized("Note title"));
    input.setAttribute("data-scholium-title-input", "true");
    input.disabled = documentTitleRenameRequest !== null;
    if (documentTitleRenameRequest) input.setAttribute("aria-busy", "true");
    if (documentTitleError) {
      input.setAttribute("aria-invalid", "true");
      input.setAttribute("aria-describedby", "scholium-note-title-error");
    }

    const resize = () => {
      input.style.height = "0";
      input.style.height = `${input.scrollHeight}px`;
    };
    let composing = false;
    let commitAfterComposition = false;
    const clearError = () => {
      documentTitleError = null;
      input.removeAttribute("aria-invalid");
      input.removeAttribute("aria-describedby");
      wrapper.querySelector(".scholium-note-title-error")?.remove();
    };
    const normalizeInput = () => {
      if (attachment !== options.attachment()) return;
      if (composing) {
        documentTitleDraft = input.value;
        wrapper.setAttribute("aria-label", input.value || documentTitle);
        resize();
        return;
      }
      const normalized = input.value.replace(/[\r\n]+/g, " ");
      if (normalized !== input.value) input.value = normalized;
      documentTitleDraft = input.value;
      wrapper.setAttribute("aria-label", input.value || documentTitle);
      clearError();
      resize();
    };
    const commit = () => {
      if (attachment !== options.attachment() || options.isSuspended()) return;
      if (documentTitleRenameRequest) return;
      const requestedTitle = input.value.replace(/[\r\n]+/g, " ");
      documentTitleDraft = requestedTitle;
      if (requestedTitle === documentTitle) {
        documentTitleDraft = null;
        documentTitleError = null;
        return;
      }
      const requestID = options.requestID();
      documentTitleRenameRequest = {
        requestID,
        requestedTitle,
      };
      input.disabled = true;
      input.setAttribute("aria-busy", "true");
      options.requestRename({
        requestID,
        expectedTitle: documentTitle,
        requestedTitle,
      });
    };
    let cancelling = false;
    input.addEventListener("input", normalizeInput);
    input.addEventListener("focus", () => {
      if (attachment !== options.attachment()) return;
      options.focusChanged();
    });
    input.addEventListener("compositionstart", () => {
      if (attachment !== options.attachment()) return;
      composing = true;
      options.beginComposition();
    });
    input.addEventListener("compositionend", () => {
      if (attachment !== options.attachment()) return;
      composing = false;
      options.endComposition();
      normalizeInput();
      if (commitAfterComposition) {
        commitAfterComposition = false;
        commit();
      }
    });
    input.addEventListener("keydown", (event) => {
      if (attachment !== options.attachment()) return;
      if (composing || event.isComposing) return;
      if (event.key === "Enter") {
        event.preventDefault();
        commit();
      } else if (event.key === "Escape") {
        event.preventDefault();
        cancelling = true;
        documentTitleDraft = null;
        clearError();
        input.value = documentTitle;
        wrapper.setAttribute("aria-label", documentTitle);
        resize();
        input.blur();
      }
    });
    input.addEventListener("blur", () => {
      if (attachment !== options.attachment()) return;
      if (cancelling) {
        cancelling = false;
        return;
      }
      if (composing) {
        commitAfterComposition = true;
        return;
      }
      commit();
    });
    // The filename title is a native text control outside authoritative
    // Markdown. Keep its pointer stream out of CodeMirror's editor-level
    // selection and selection-action tracking so native forward and backward
    // drags remain owned by the textarea.
    const stopEditorPointerHandling = (event: Event) => event.stopPropagation();
    input.addEventListener("pointerdown", stopEditorPointerHandling);
    input.addEventListener("mousedown", stopEditorPointerHandling);
    wrapper.addEventListener("pointerdown", (event) => {
      if (event.target === input || input.disabled) return;
      event.preventDefault();
      input.focus();
      input.setSelectionRange(input.value.length, input.value.length);
    });
    wrapper.append(input);

    if (documentTitleError) {
      const error = document.createElement("div");
      error.id = "scholium-note-title-error";
      error.className = "scholium-note-title-error";
      error.setAttribute("role", "alert");
      error.textContent = documentTitleError;
      wrapper.append(error);
    }
    queueMicrotask(resize);
    return wrapper;
  }

  // The filename is a separate text control, not a character or an embedded
  // object in the Markdown textbox. A public panel container keeps it in the
  // same scrolling flow while WebKit exposes each control's own text range.
  const titleContainer = document.createElement("div");
  titleContainer.className = "scholium-note-title-container";
  const titlePanel: PanelConstructor = view => {
    const dom = document.createElement("div");
    dom.className = "scholium-note-title-panel";
    dom.append(createTitleControl());
    let renderedRevision = documentTitlePresentationRevision;
    let renderedAttachment = options.attachment();
    return {
      dom,
      top: true,
      mount() {
        view.scrollDOM.insertBefore(titleContainer, view.contentDOM);
        view.scrollDOM.classList.add("scholium-note-title-scroll");
        view.requestMeasure();
      },
      update() {
        if (renderedRevision === documentTitlePresentationRevision
            && renderedAttachment === options.attachment()) return;
        renderedRevision = documentTitlePresentationRevision;
        renderedAttachment = options.attachment();
        dom.replaceChildren(createTitleControl());
        view.requestMeasure();
      },
      destroy() {
        titleContainer.remove();
        titleContainer.className = "scholium-note-title-container";
        view.scrollDOM.classList.remove("scholium-note-title-scroll");
      },
    };
  };

  function resolveDocumentTitleRename(
    requestID: string,
    accepted: boolean,
    title: string,
    error: string,
  ) {
    if (!documentTitleRenameRequest
        || requestID !== documentTitleRenameRequest.requestID
        || typeof accepted !== "boolean"
        || typeof title !== "string" || title.length > 1_024
        || typeof error !== "string" || error.length > 4_096) return;
    const requestedTitle = documentTitleRenameRequest.requestedTitle;
    documentTitleRenameRequest = null;
    if (accepted) {
      documentTitle = title;
      documentTitleDraft = null;
      documentTitleError = null;
    } else {
      documentTitleDraft = requestedTitle;
      documentTitleError = error;
    }
    documentTitlePresentationRevision += 1;
    options.dispatch(refreshDocumentTitleEffect.of(null));
    if (!accepted) {
      const attachment = options.attachment();
      queueMicrotask(() => {
        if (attachment !== options.attachment()) return;
        const input = document.querySelector<HTMLTextAreaElement>(
          ".scholium-note-title-input",
        );
        input?.focus();
        input?.setSelectionRange(input.value.length, input.value.length);
      });
    }
  }

  const liveDocumentTitle = StateField.define<number>({
    create: () => documentTitlePresentationRevision,
    update: (revision, transaction) => {
      const titleChanged = transaction.effects.some((effect) =>
        effect.is(refreshDocumentTitleEffect));
      return titleChanged ? documentTitlePresentationRevision : revision;
    },
    provide: field => showPanel.from(field, () => documentTitle ? titlePanel : null),
  });

  return {
    extension: [
      liveDocumentTitle,
      panels({topContainer: titleContainer}),
      EditorView.theme({
        ".cm-scroller.scholium-note-title-scroll": {flexDirection: "column"},
        ".scholium-note-title-container": {
          boxSizing: "border-box",
          // Custom panel containers receive the editor's theme classes too;
          // the root's full-viewport height must not size this flow item.
          height: "auto",
          flex: "none",
          inlineSize: "100%",
          paddingBlockStart: "calc(var(--scholium-document-content-top-inset) + var(--scholium-document-toolbar-inset, 0px))",
          paddingInline: "max(var(--scholium-rhythm-inline-source), calc(50% - var(--scholium-document-half-line-width)))",
          fontSize: "var(--scholium-document-text-scale)",
        },
        ".scholium-note-title-container .cm-panels": {
          position: "static", border: "0", backgroundColor: "transparent", color: "inherit", zIndex: "auto",
        },
        ".cm-scroller.scholium-note-title-scroll .cm-content": {paddingBlockStart: "0", minHeight: "0"},
      }),
    ],
    resolveRename: resolveDocumentTitleRename,
    // The native detachment transaction consults this before capturing source.
    // Filename drafts live in this control and are not source recovery data.
    allowsDetachment: () => documentTitleRenameRequest === null
      && (documentTitleDraft === null || documentTitleDraft === documentTitle),
    ownsCompositionEvent: (event: Event) => event.target instanceof Element
      && event.target.closest("[data-scholium-title-input]") !== null,
    resetDocument() {
      documentTitle = "";
      documentTitleDraft = null;
      documentTitleError = null;
      documentTitleRenameRequest = null;
      documentTitlePresentationRevision += 1;
    },
    setTitle(value: string) {
      if (documentTitle === value
          && documentTitleDraft === null
          && documentTitleError === null
          && documentTitleRenameRequest === null) return;
      documentTitle = value;
      documentTitleDraft = null;
      documentTitleError = null;
      documentTitleRenameRequest = null;
      documentTitlePresentationRevision += 1;
      options.dispatch(refreshDocumentTitleEffect.of(null));
    },

    focus(options?: FocusOptions) {
      const input = document.querySelector<HTMLTextAreaElement>(
        ".scholium-note-title-input",
      );
      if (!input || input.disabled) return false;
      input.focus(options);
      input.setSelectionRange(input.value.length, input.value.length);
      return true;
    },

  };
}
