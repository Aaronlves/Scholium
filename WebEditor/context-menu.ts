import {EditorSelection, Transaction, type Extension} from "@codemirror/state";
import {EditorView, ViewPlugin} from "@codemirror/view";
import type {EditorContext, EditorMode} from "./protocol";

export interface EditorContextMenuRequest {
  readonly clientX: number;
  readonly clientY: number;
  readonly mode: EditorMode;
  readonly context: EditorContext;
}

/**
 * Secondary click preserves an existing selected passage. Outside that
 * passage it moves CodeMirror's one authoritative selection to the clicked
 * source position before any menu command is evaluated.
 */
export function selectionForContextClick(
  selection: EditorSelection,
  position: number,
): EditorSelection {
  const belongsToSelection = selection.ranges.some(
    (range) => !range.empty && position >= range.from && position < range.to,
  );
  return belongsToSelection ? selection : EditorSelection.single(position);
}

/**
 * WebKit's default macOS menu is suppressed only after the DOM context-menu
 * event has reached CodeMirror. Native AppKit then presents one compact menu
 * from this finalized selection. No native event monitor, private descendant
 * view, or second selection owner participates.
 */
export function createEditorContextMenuExtension(options: {
  context(view: EditorView): EditorContext;
  mode(view: EditorView): EditorMode;
  positionAtEvent?(view: EditorView, event: MouseEvent): number | null;
  request(value: EditorContextMenuRequest): void;
}): Extension {
  return ViewPlugin.define((view) => {
    const handleContextMenu = (event: MouseEvent) => {
      event.preventDefault();
      event.stopImmediatePropagation();

      const isPointerInvocation = event.button === 2
        || (event.button === 0 && event.ctrlKey)
        || event.detail > 0;
      if (isPointerInvocation) {
        const position = options.positionAtEvent?.(view, event)
          ?? view.posAtCoords({x: event.clientX, y: event.clientY});
        if (position !== null) {
          const selection = selectionForContextClick(view.state.selection, position);
          if (!selection.eq(view.state.selection)) {
            view.dispatch({
              selection,
              annotations: Transaction.userEvent.of("select.pointer.context-menu"),
            });
          }
        }
      }

      view.focus();
      const caretBounds = view.coordsAtPos(view.state.selection.main.head);
      options.request({
        clientX: isPointerInvocation
          ? event.clientX
          : caretBounds?.left ?? event.clientX,
        clientY: isPointerInvocation
          ? event.clientY
          : caretBounds?.bottom ?? event.clientY,
        mode: options.mode(view),
        context: options.context(view),
      });
    };

    // Capture at the editor root so semantic projection widgets cannot route
    // a secondary click around CodeMirror's finalized-selection menu path.
    // This also prevents WebKit from substituting its generic Reload or text
    // menu for a click on a non-editable projected construct.
    view.dom.addEventListener("contextmenu", handleContextMenu, {capture: true});
    return {
      destroy() {
        view.dom.removeEventListener("contextmenu", handleContextMenu, {capture: true});
      },
    };
  });
}
