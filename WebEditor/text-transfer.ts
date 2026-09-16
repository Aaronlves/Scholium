import {isolateHistory} from "@codemirror/commands";
import {EditorSelection, EditorState, type SelectionRange, type Text, type TransactionSpec} from "@codemirror/state";
import {EditorView, ViewPlugin} from "@codemirror/view";
import {normalizedDocumentText} from "./state";
import {transformMarkdown} from "./transformations";
import {containsCompleteHeading, lineContentStart} from "./text-transfer-ranges";
import {exactInsertionEffects, exactSourceFitsChanges, exactSourceState} from "./exact-source-history";

interface EditorTextTransferOptions {
  documentIdentity: () => unknown;
  compositionActive: () => boolean;
  protection: (state: EditorState) => readonly {from: number; to: number}[];
  unsupportedFile: () => void;
  didInsert: (undoLabel: string) => void;
  projectedPosition?: (view: EditorView, event: DragEvent) => number | null;
}

/** One retained editor owns selection-drag admission, source protection and drops. */
export function createEditorTextTransfer(options: EditorTextTransferOptions) {
  const handlers = createTextDropHandlers(options);
  const resolve = (view: EditorView, event: DragEvent) => handlers.dropPosition(view, event);
  return [
    transferDropCursor(resolve, handlers.dragend),
    EditorView.domEventHandlers({
      mousedown: handlers.dragend,
      dragend: handlers.dragend,
      drop: handlers.drop,
      dragstart(event, view) {
        handlers.dragend();
        const selection = view.contentDOM.ownerDocument.getSelection();
        // Admit only the native selected-text source. Links and widgets outside
        // that range must not acquire permission to delete retained source.
        if (!event.dataTransfer || view.composing || options.compositionActive()
            || !selection || selection.isCollapsed || selection.rangeCount !== 1
            || !view.contentDOM.contains(selection.anchorNode)
            || !view.contentDOM.contains(selection.focusNode)
            || !Array.from(selection.getRangeAt(0).getClientRects()).some(rect =>
              event.clientX >= rect.left && event.clientX <= rect.right
              && event.clientY >= rect.top && event.clientY <= rect.bottom)) return false;
        return handlers.dragstart(event, view);
      },
    }),
  ];
}

type TextDropView = Pick<EditorView, "state" | "composing" | "focus"> & {dispatch: (transaction: TransactionSpec) => void};
type DropEvent = Pick<DragEvent, "clientX" | "clientY"> & Partial<Pick<DragEvent, "altKey" | "ctrlKey" | "defaultPrevented">> & {
  dataTransfer: {
    files: ArrayLike<File>;
    items: ArrayLike<Pick<DataTransferItem, "kind">>;
    getData: (type: string) => string;
  } | null;
};
type DropView = TextDropView & {posAtCoords(coords: {x: number; y: number}, precise?: boolean): number | null};

/** Move the authoritative slice in one transaction; never serialize projection. */
export function moveSelectedText(view: TextDropView, range: SelectionRange, position: number,
  copy: boolean, linewise: boolean, protection: EditorTextTransferOptions["protection"]) {
  const state = view.state;
  if (!acceptsDropTarget(view, position, false) || range.empty
      || (!copy && position >= range.from && position <= range.to)) return null;
  const target = state.update({selection: {anchor: position}}).state;
  if (protection(target).some(({from, to}) => position > from && position < to)
      || (!copy && protection(state).some(({from, to}) => range.from < to && range.to > from))) return null;
  const mirror = state.field(exactSourceState, false);
  let exact = mirror?.slice(range.from, range.to) ?? state.sliceDoc(range.from, range.to);
  const ending = mirror?.usesCRLF ? "\r\n" : "\n";
  // A complete last line has no terminator to carry. At a new boundary add
  // only the necessary separator; never reconstruct its Markdown content.
  if (linewise) {
    if (position > lineContentStart(state, position)
        && state.sliceDoc(position - 1, position) !== "\n") exact = ending + exact;
    if (position < state.doc.length && !exact.endsWith("\n")) exact += ending;
  }
  const insert = normalizedDocumentText(exact);
  const specs = [...(copy ? [] : [{from: range.from, to: range.to, insert: "", exactInsert: ""}]),
    {from: position, to: position, insert, exactInsert: exact}];
  if (!exactSourceFitsChanges(state, specs)) return null;
  const changes = state.changes(specs);
  const from = changes.mapPos(position, -1);
  view.dispatch({changes, selection: EditorSelection.single(from, from + insert.length),
    effects: exactInsertionEffects(exact, from),
    userEvent: copy ? "input.drop" : "move.drop", annotations: isolateHistory.of("full"),
    scrollIntoView: true});
  view.focus();
  return copy ? "Paste" : "Move";
}

/** One resolver supplies both preview and commit. Like CodeMirror's cursor,
 * this is a measured overlay and never adds document geometry or history.
 */
function transferDropCursor(resolve: (view: EditorView, event: DragEvent) => number | null, ended: () => void) {
  return ViewPlugin.fromClass(class {
    cursor: HTMLElement | null = null;
    event: DragEvent | null = null;
    constructor(readonly view: EditorView) {}
    clear() { this.event = null; this.cursor?.remove(); this.cursor = null; }
    readonly measure = {
      read: () => {
        if (!this.event) return null;
        const pos = resolve(this.view, this.event);
        const rect = pos === null ? null : this.view.coordsAtPos(pos);
        if (!rect) return null;
        const outer = this.view.scrollDOM.getBoundingClientRect();
        return {left: (rect.left - outer.left) / this.view.scaleX + this.view.scrollDOM.scrollLeft,
          top: (rect.top - outer.top) / this.view.scaleY + this.view.scrollDOM.scrollTop,
          height: (rect.bottom - rect.top) / this.view.scaleY};
      },
      write: (rect: {left: number; top: number; height: number} | null) => {
        if (!this.event || !rect) { this.cursor?.remove(); this.cursor = null; return; }
        if (!this.cursor) {
          this.cursor = this.view.scrollDOM.appendChild(document.createElement("div"));
          this.cursor.className = "cm-dropCursor";
          this.cursor.setAttribute("aria-hidden", "true");
          this.cursor.style.pointerEvents = "none";
        }
        Object.assign(this.cursor.style, {left: `${rect.left}px`, top: `${rect.top}px`, height: `${rect.height}px`});
      },
    };
    update() { if (this.event) this.view.requestMeasure(this.measure); }
    destroy() { this.clear(); ended(); }
  }, {eventObservers: {
    dragover(event) { this.event = event; this.view.requestMeasure(this.measure); },
    dragleave(event) {
      if (!this.view.contentDOM.contains(event.relatedTarget as Node | null)) this.clear();
    },
    dragend() { this.clear(); },
    drop() { this.clear(); },
  }});
}

function acceptsDropTarget(view: TextDropView, position: number | null, compositionActive: boolean) {
  return !view.state.readOnly && view.state.facet(EditorView.editable) && !view.composing && !compositionActive
    && position !== null && Number.isInteger(position) && position >= 0 && position <= view.state.doc.length;
}

/** Register with CodeMirror so its drop observers clean up before admission. */
export function createTextDropHandlers(options: EditorTextTransferOptions) {
  let localDrag: {document: unknown; doc: Text; range: SelectionRange; linewise: boolean} | null = null;
  const rawPosition = (view: DropView, event: DropEvent) => {
    if (localDrag && localDrag.document === options.documentIdentity() && localDrag.linewise) {
      const editor = view as EditorView;
      const block = editor.lineBlockAtHeight(event.clientY - editor.documentTop);
      const before = event.clientY - editor.documentTop <= (block.top + block.bottom) / 2;
      const line = view.state.doc.lineAt(before ? block.from : block.to);
      return before ? lineContentStart(view.state, line.from) : Math.min(view.state.doc.length, line.to + 1);
    }
    return options.projectedPosition?.(view as EditorView, event as DragEvent)
      ?? view.posAtCoords({x: event.clientX, y: event.clientY}, false);
  };
  const moves = (view: TextDropView, event: DropEvent) => {
    const policy = view.state.facet(EditorView.dragMovesSelection);
    return policy.length ? policy[0](event as DragEvent) : !event.altKey;
  };
  const hasFiles = (event: DropEvent) => !!event.dataTransfer
    && (Array.from(event.dataTransfer.files).length > 0
      || Array.from(event.dataTransfer.items).some(item => item.kind === "file"));
  const dropPosition = (view: DropView, event: DropEvent) => {
    if (hasFiles(event)) return null;
    const receipt = localDrag?.document === options.documentIdentity() ? localDrag : null;
    if (receipt && receipt.doc !== view.state.doc) return null;
    const position = rawPosition(view, event);
    if (!acceptsDropTarget(view, position, options.compositionActive())) return null;
    if (receipt && moves(view, event)
        && position! >= receipt.range.from && position! <= receipt.range.to) return null;
    const target = view.state.update({selection: {anchor: position!}}).state;
    if (options.protection(target).some(({from, to}) => position! > from && position! < to)) return null;
    return position;
  };
  return {
    dropPosition,
    dragstart(event: DropEvent, view: TextDropView) {
      const range = view.state.selection.main;
      localDrag = range.empty || view.state.selection.ranges.length !== 1 ? null
        : {document: options.documentIdentity(), doc: view.state.doc, range,
          linewise: containsCompleteHeading(view.state, range)};
      const receipt = localDrag;
      // A later listener may cancel dragstart without a subsequent dragend.
      // Check after dispatch, without clearing a newer native drag receipt.
      setTimeout(() => {
        if (event.defaultPrevented && localDrag === receipt) localDrag = null;
      }, 0);
      // CodeMirror retains the native drag lifecycle and exact source payload.
      // This owner's immutable receipt validates the eventual source mutation.
      return false;
    },
    dragend() {
      localDrag = null;
      return false;
    },
    drop(event: DropEvent, view: DropView) {
      const receipt = localDrag;
      const internal = receipt !== null && receipt.document === options.documentIdentity();
      const position = dropPosition(view, event);
      localDrag = null;
      const transfer = event.dataTransfer;
      if (!transfer) return true;
      if (hasFiles(event)) {
        options.unsupportedFile();
        return true;
      }
      if (!acceptsDropTarget(view, position, options.compositionActive())) return true;
      if (internal) {
        // A source edit during the system drag invalidates its receipt. Never
        // delete an old range from a newer document or silently fall back.
        if (receipt.doc !== view.state.doc) return true;
        const move = moves(view, event);
        const label = moveSelectedText(view, receipt.range, position!, !move,
          receipt.linewise, options.protection);
        if (label) options.didInsert(label);
        return true;
      }
      const label = insertDroppedText(view, transfer.getData("text/plain"), position,
        options.compositionActive(), options.protection);
      if (label) options.didInsert(label);
      // Consume rejections too; native fallback must not insert at an old caret.
      return true;
    },
  };
}

/** A drop inserts at its verified target without replacing the retained selection. */
export function insertDroppedText(
  view: TextDropView,
  text: string,
  position: number | null,
  compositionActive: boolean,
  protection: (state: EditorState) => readonly {from: number; to: number}[],
) {
  const state = view.state;
  if (position === null || !acceptsDropTarget(view, position, compositionActive)) return null;
  const insert = normalizedDocumentText(text);
  if (!insert) return null;
  // Derive command availability at the drop target without first moving the live
  // selection. Rejection must preserve the complete pre-drop editor state.
  const targetState = state.update({selection: {anchor: position}}).state;
  const source = state.doc.toString();
  const transformed = transformMarkdown(source, [{anchor: position, head: position}], "pastePlain", {
    argument: insert,
    protectedRanges: protection(targetState),
  });
  if (!transformed || !exactSourceFitsChanges(state, transformed.changes)) return null;
  view.dispatch({
    changes: transformed.changes,
    selection: EditorSelection.create(transformed.selections.map(range => EditorSelection.range(range.anchor, range.head))),
    userEvent: "input.drop",
    annotations: isolateHistory.of("full"),
    scrollIntoView: true,
  });
  view.focus();
  return transformed.undoLabel;
}
