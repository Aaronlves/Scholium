import type {Extension} from "@codemirror/state";
import {EditorView, ViewPlugin, type ViewUpdate} from "@codemirror/view";

export type SelectionActionCommand = "bold" | "emphasis" | "inlineCode" | "standardLink";

export interface SelectionActionsController {
  readonly extension: Extension;
  hide(): void;
  update(view: EditorView): void;
}

/**
 * Owns the transient formatting toolbar and its DOM lifetime. Markdown
 * mutation remains with the editor composition root through `applyCommand`.
 */
export function createSelectionActionsController(options: {
  applyCommand(view: EditorView, command: SelectionActionCommand): void;
}): SelectionActionsController {
  let root: HTMLDivElement | null = null;
  let activeView: EditorView | null = null;

  function addButton(
    commandBar: HTMLDivElement,
    title: string,
    label: string,
    command: SelectionActionCommand,
  ) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = title;
    button.setAttribute("aria-label", label);
    button.title = label;
    button.addEventListener("mousedown", (event) => event.preventDefault());
    button.addEventListener("click", () => {
      if (activeView) options.applyCommand(activeView, command);
    });
    commandBar.append(button);
  }

  function mount(view: EditorView) {
    if (root) return;
    root = document.createElement("div");
    root.id = "scholium-selection-actions";
    root.className = "scholium-selection-actions";
    root.hidden = true;
    root.dataset.scholiumProtected = "selection-actions";

    const commandBar = document.createElement("div");
    commandBar.className = "scholium-selection-toolbar";
    commandBar.setAttribute("role", "toolbar");
    commandBar.setAttribute("aria-label", "Formatting actions");
    root.append(commandBar);
    addButton(commandBar, "B", "Bold", "bold");
    addButton(commandBar, "I", "Italic", "emphasis");
    addButton(commandBar, "</>", "Inline Code", "inlineCode");
    addButton(commandBar, "↗", "Link", "standardLink");
    document.body.append(root);
    update(view);
  }

  function unmount(view: EditorView) {
    if (activeView === view) activeView = null;
    root?.remove();
    root = null;
  }

  function hide() {
    if (root) root.hidden = true;
    activeView = null;
  }

  function update(view: EditorView) {
    if (!root) return;
    const selection = view.state.selection;
    const main = selection.main;
    if (view.composing || !view.hasFocus || selection.ranges.length !== 1 || main.empty) {
      hide();
      return;
    }
    const from = Math.min(main.anchor, main.head);
    const to = Math.max(main.anchor, main.head);
    const start = view.coordsAtPos(from);
    const end = view.coordsAtPos(to);
    if (!start || !end) {
      hide();
      return;
    }
    activeView = view;
    root.hidden = false;
    const measured = root.getBoundingClientRect();
    root.style.left = `${Math.max(12, Math.min(
      Math.min(start.left, end.left), window.innerWidth - measured.width - 12,
    ))}px`;
    root.style.top = `${Math.max(8, Math.min(start.top, end.top) - measured.height - 6)}px`;
  }

  const extension = ViewPlugin.define((view) => {
    mount(view);
    return {
      update(updateEvent: ViewUpdate) {
        if (updateEvent.docChanged || updateEvent.selectionSet || updateEvent.focusChanged) {
          update(updateEvent.view);
        }
      },
      destroy() {
        unmount(view);
      },
    };
  });

  return {
    extension,
    hide,
    update,
  };
}
