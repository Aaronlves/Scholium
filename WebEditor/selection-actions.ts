import type {Extension} from "@codemirror/state";
import {EditorView} from "@codemirror/view";

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
  mode(): "livePreview" | "source";
  applyCommand(view: EditorView, command: SelectionActionCommand): void;
}): SelectionActionsController {
  const root = document.createElement("div");
  root.id = "scholium-selection-actions";
  root.className = "scholium-selection-actions";
  root.hidden = true;
  root.dataset.scholiumProtected = "selection-actions";

  const commandBar = document.createElement("div");
  commandBar.className = "scholium-selection-toolbar";
  commandBar.setAttribute("role", "toolbar");
  commandBar.setAttribute("aria-label", "Formatting actions");
  root.append(commandBar);
  document.body.append(root);

  let activeView: EditorView | null = null;

  function addButton(title: string, label: string, command: SelectionActionCommand) {
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

  addButton("B", "Bold", "bold");
  addButton("I", "Italic", "emphasis");
  addButton("</>", "Inline Code", "inlineCode");
  addButton("↗", "Link", "standardLink");

  function hide() {
    root.hidden = true;
    activeView = null;
  }

  function update(view: EditorView) {
    const selection = view.state.selection;
    const main = selection.main;
    if (options.mode() !== "livePreview" || view.composing || !view.hasFocus
        || selection.ranges.length !== 1 || main.empty) {
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

  return {
    extension: EditorView.updateListener.of((updateEvent) => {
      if (updateEvent.docChanged || updateEvent.selectionSet || updateEvent.focusChanged) {
        update(updateEvent.view);
      }
    }),
    hide,
    update,
  };
}
