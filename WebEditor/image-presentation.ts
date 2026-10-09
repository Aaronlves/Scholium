import {StateField, Transaction, type EditorState, type Extension, type Range} from "@codemirror/state";
import {Decoration, EditorView, WidgetType, type DecorationSet} from "@codemirror/view";
import {syntaxTree} from "@codemirror/language";
import type {LiveProjectionIndexController} from "./live-projection-index";
import type {LiveSelectionController} from "./live-selection";
import {selectionActivatesSyntax, transactionChangedSyntaxTree} from "./projection-update";
import {preserveLivePresentationLayout} from "./live-presentation-layout";
import {projectedPointerSelection} from "./projected-pointer-selection";
import {semanticProjectionRanges, type SemanticInlineProjection, type SemanticProjectionRanges} from "./semantic-projection";

function markdownDestination(source: string): string {
  let destination = source;
  if (destination.startsWith("<") && destination.endsWith(">")) destination = destination.slice(1, -1);
  // Native cmark cleans a parsed URL by decoding character references before
  // one pass of Markdown punctuation escapes. Never decode the result again.
  destination = destination.replace(/&(?:#[xX][\da-fA-F]{1,8}|#\d{1,8}|[a-zA-Z][\da-zA-Z]{1,31});/g, reference => {
    if (reference.startsWith("&#")) {
      const hexadecimal = /^&#[xX]/.test(reference);
      const value = Number.parseInt(reference.slice(hexadecimal ? 3 : 2, -1), hexadecimal ? 16 : 10);
      return String.fromCodePoint(value === 0 || value >= 0x110000 || value >= 0xd800 && value < 0xe000
        ? 0xfffd : value);
    }
    // A bounded entity spelling cannot introduce HTML. Attribute context also
    // leaves unknown names intact instead of partially decoding legacy names.
    const decoder = document.createElement("span");
    decoder.innerHTML = `<span data-destination="${reference}"></span>`;
    return decoder.firstElementChild?.getAttribute("data-destination") ?? reference;
  });
  destination = destination.replace(/\\([!"#$%&'()*+,\-./:;<=>?@[\]\\^_`{|}~])/g, "$1");
  return destination;
}

export function imageDestination(source: string): string | null {
  const destination = markdownDestination(source);
  if (!destination || destination.startsWith("//") || /[?#\u0000-\u001f\u007f]/.test(destination)
      || /^[a-z][a-z\d+.-]*:/i.test(destination)) return null;
  // Percent decoding produces a native-admitted filesystem key. Reserved
  // characters encoded in the URL can be literal local filename characters.
  try { return decodeURIComponent(destination); } catch { return null; }
}

interface ImagePresentation {
  readonly from: number;
  readonly to: number;
  readonly sourceFrom: number;
  readonly sourceTo: number;
  readonly resource: string;
  readonly alt: string;
  readonly block: boolean;
  readonly activation: {readonly target: string; readonly isImage: boolean} | null;
}

export function imagePresentation(state: EditorState, image: SemanticInlineProjection,
  resources: Readonly<Record<string, string>>, syntax?: SemanticProjectionRanges): ImagePresentation | null {
  if (image.kind !== "image" || !image.targetRange) return null;
  const destination = imageDestination(state.doc.sliceString(image.targetRange.from, image.targetRange.to));
  const resource = destination === null || !Object.hasOwn(resources, destination)
    ? undefined : resources[destination];
  if (!resource) return null;
  const outerLink = syntax?.inlines.find(inline => inline.kind === "link"
    && inline.from < image.from && inline.to > image.to);
  const label = outerLink?.visibleRanges.length === 1 ? outerLink.visibleRanges[0] : null;
  const imageOnlyLabel = label && label.from <= image.from && label.to >= image.to
    && /^\s*$/.test(state.doc.sliceString(label.from, image.from))
    && /^\s*$/.test(state.doc.sliceString(image.to, label.to));
  const owner = imageOnlyLabel ? outerLink! : image;
  const firstLine = state.doc.lineAt(owner.from);
  const lastLine = state.doc.lineAt(owner.to);
  const block = /^\s*$/.test(state.doc.sliceString(firstLine.from, owner.from))
    && /^\s*$/.test(state.doc.sliceString(owner.to, lastLine.to));
  let linked = false;
  for (let node = syntaxTree(state).resolveInner(image.from, 1); node; node = node.parent!) {
    if (node.name === "Link") { linked = true; break; }
  }
  const targetRange = outerLink?.targetRange ?? (linked ? null : image.targetRange);
  return {
    from: block ? firstLine.from : image.from,
    to: block ? lastLine.to : image.to,
    sourceFrom: image.from,
    sourceTo: image.to,
    resource,
    alt: imageAlternativeText(state, image, syntax),
    block,
    activation: targetRange ? {
      target: markdownDestination(state.doc.sliceString(targetRange.from, targetRange.to)),
      isImage: !linked,
    } : null,
  };
}

/** Readable accessibility text comes from parsed label content, while source
 * activation continues to use the complete, unchanged authored image range. */
function imageAlternativeText(state: EditorState, image: SemanticInlineProjection,
  syntax = semanticProjectionRanges(state, image.visibleRanges, 0)): string {
  const hidden = [...syntax.literals];
  for (const child of syntax.inlines) {
    if (child === image || child.from === image.from && child.to === image.to
        || !image.visibleRanges.some(range => child.from >= range.from && child.to <= range.to)) continue;
    let from = child.from;
    for (const visible of child.visibleRanges) {
      if (from < visible.from) hidden.push({from, to: visible.from, nodeName: "ImageLabelSyntax"});
      from = Math.max(from, visible.to);
    }
    if (from < child.to) hidden.push({from, to: child.to, nodeName: "ImageLabelSyntax"});
  }
  hidden.sort((a, b) => a.from - b.from || a.to - b.to);
  const readable: Array<{from: number; to: number}> = [];
  for (const range of image.visibleRanges) {
    let from = range.from;
    for (const excluded of hidden) {
      if (excluded.to <= from || excluded.from >= range.to) continue;
      if (from < excluded.from) readable.push({from, to: excluded.from});
      from = Math.max(from, excluded.to);
    }
    if (from < range.to) readable.push({from, to: range.to});
  }
  return readable.map(range => {
    let from = range.from, result = "";
    syntaxTree(state).iterate({from: range.from, to: range.to, enter(node) {
      if (node.from < range.from || node.to > range.to
          || node.name !== "Escape" && node.name !== "Entity") return;
      result += state.doc.sliceString(from, node.from);
      const source = state.doc.sliceString(node.from, node.to);
      if (node.name === "Escape") result += source.slice(1);
      else {
        // Decode only a parser-proven character reference in an unattached
        // native text element; authored HTML never enters this boundary.
        const decoder = document.createElement("span");
        decoder.innerHTML = source;
        result += decoder.textContent ?? source;
      }
      from = node.to;
      return false;
    }});
    return result + state.doc.sliceString(from, range.to);
  }).join("");
}

class ImageWidget extends WidgetType {
  constructor(readonly presentation: ImagePresentation,
    readonly activateLink: (target: string, isImage: boolean) => void) { super(); }
  eq(other: ImageWidget) {
    const a = this.presentation, b = other.presentation;
    return a.from === b.from && a.to === b.to
      && a.sourceFrom === b.sourceFrom && a.sourceTo === b.sourceTo
      && a.resource === b.resource && a.alt === b.alt && a.block === b.block
      && a.activation?.target === b.activation?.target && a.activation?.isImage === b.activation?.isImage;
  }
  toDOM(view: EditorView) {
    const shell: HTMLElement = document.createElement(this.presentation.block ? "div" : "span");
    shell.className = this.presentation.block ? "cm-live-image cm-live-image-block" : "cm-live-image";
    shell.dataset.scholiumProtected = "image";
    shell.dataset.scholiumSourceFrom = String(this.presentation.sourceFrom);
    shell.dataset.scholiumSourceTo = String(this.presentation.sourceTo);
    const image = document.createElement("img");
    image.className = this.presentation.block
      ? "scholium-embedded-image scholium-embedded-image-block" : "scholium-embedded-image";
    image.alt = this.presentation.alt;
    image.draggable = false;
    // WebKit decodes even local data URLs asynchronously. CodeMirror owns the
    // height map; loading changes only its measurement, never source/history.
    const measure = () => {
      if (image.naturalWidth > 0 && image.naturalHeight > 0) {
        image.style.setProperty("--scholium-image-aspect-ratio", String(image.naturalWidth / image.naturalHeight));
      }
      if (shell.isConnected) view.requestMeasure();
    };
    image.addEventListener("load", measure);
    image.addEventListener("error", measure);
    image.src = this.presentation.resource;
    shell.append(image);
    let pending: {doc: EditorState["doc"]; x: number; y: number} | null = null;
    const opensImage = (event: MouseEvent) => event.button === 0
      && event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
    shell.addEventListener("mousedown", event => {
      pending = null;
      if (event.button !== 0 || view.compositionStarted) return;
      event.preventDefault();
      event.stopPropagation();
      if (event.target === image && opensImage(event)) {
        pending = {doc: view.state.doc, x: event.clientX, y: event.clientY};
        return;
      }
      const rect = image.getBoundingClientRect();
      const position = event.clientX <= rect.left + rect.width / 2
        ? this.presentation.sourceFrom : this.presentation.sourceTo;
      if (position > view.state.doc.length) return;
      view.dispatch({selection: projectedPointerSelection(view.state, event, position),
        scrollIntoView: true, annotations: Transaction.userEvent.of("select.pointer")});
      view.focus();
    });
    shell.addEventListener("mousemove", event => {
      if (pending && Math.hypot(event.clientX - pending.x, event.clientY - pending.y) > 4) pending = null;
    });
    shell.addEventListener("mouseleave", () => { pending = null; });
    shell.addEventListener("dragstart", event => { pending = null; event.preventDefault(); });
    shell.addEventListener("pointercancel", () => { pending = null; });
    shell.addEventListener("click", event => {
      const started = pending;
      pending = null;
      if (event.target !== image || !opensImage(event)) return;
      event.preventDefault();
      event.stopPropagation();
      const activation = this.presentation.activation;
      if (!started || view.compositionStarted || view.state.doc !== started.doc
        || Math.hypot(event.clientX - started.x, event.clientY - started.y) > 4
        || !shell.isConnected || !activation) return;
      this.activateLink(activation.target, activation.isImage);
    });
    return shell;
  }
  ignoreEvent(event: Event) { return event.type === "mousedown"; }
}

/** Direct decorations own image line geometry, including multiline syntax.
 * A viewport plugin cannot safely introduce a block or replace line breaks. */
export function createImageProjection(options: {
  selection: LiveSelectionController;
  projections: LiveProjectionIndexController;
  bodyIsActive(): boolean;
  shouldRefresh(transaction: Transaction): boolean;
  activateLink(target: string, isImage: boolean): void;
}): {extension: Extension;
  blockPresentations(state: EditorState): readonly {from: number; to: number}[];
  imageTargetAt(state: EditorState, selection: {from: number; to: number}): string | null;
  contextPositionAtEvent(state: EditorState, event: MouseEvent): number | null;
  setResources(resources: Readonly<Record<string, string>>, view?: EditorView): void} {
  let resources: Readonly<Record<string, string>> = Object.create(null);
  const refresh = StateField.define<DecorationSet>({
    create: build,
    update(previous, transaction) {
      if (transaction.docChanged || transactionChangedSyntaxTree(transaction)
          || options.selection.changed(transaction.startState, transaction.state)
          || options.shouldRefresh(transaction)
          || transaction.effects.some(effect => effect.is(preserveLivePresentationLayout))) {
        return build(transaction.state);
      }
      return previous;
    },
    provide: field => [
      EditorView.decorations.from(field),
      EditorView.atomicRanges.of(view => view.state.field(field)),
    ],
  });
  function build(state: EditorState): DecorationSet {
    const index = options.projections.index(state);
    if (index.hasUnclosedFrontmatter) return Decoration.none;
    const ranges: Range<Decoration>[] = [];
    let outerImageTo = -1;
    for (const image of index.syntax.inlines) {
      if (image.kind !== "image") continue;
      // The semantic catalog orders outer nodes before their contained nodes.
      // An image owns its whole caption even when denied or revealed as source,
      // so a nested image never installs an independent replacement inside it.
      if (image.to <= outerImageTo) continue;
      outerImageTo = image.to;
      // Complete table and footnote projections already own their contained
      // DOM; never install a competing replacement inside those objects.
      if ([...index.tables, ...index.footnoteRanges].some(range =>
        image.from >= range.from && image.to <= range.to)) continue;
      const presentation = imagePresentation(state, image, resources, index.syntax);
      if (!presentation) continue;
      if (options.bodyIsActive() && options.selection.selection(state).ranges.some(range =>
        selectionActivatesSyntax(range, presentation))) continue;
      ranges.push(Decoration.replace({widget: new ImageWidget(presentation, options.activateLink), block: presentation.block})
        .range(presentation.from, presentation.to));
    }
    return Decoration.set(ranges, true);
  }
  return {
    extension: refresh,
    blockPresentations(state) {
      const result: Array<{from: number; to: number}> = [];
      state.field(refresh, false)?.between(0, state.doc.length, (from, to, decoration) => {
        if (decoration.spec.block === true) result.push({from, to});
      });
      return result;
    },
    imageTargetAt(state, selection) {
      const index = options.projections.index(state);
      if (index.hasUnclosedFrontmatter) return null;
      let outerImageTo = -1;
      for (const image of index.syntax.inlines) {
        if (image.kind !== "image" || image.to <= outerImageTo) continue;
        outerImageTo = image.to;
        if (selection.from < image.from || selection.to > image.to || selection.from >= image.to) continue;
        if (!imagePresentation(state, image, resources, index.syntax) || !image.targetRange) return null;
        return markdownDestination(state.doc.sliceString(image.targetRange.from, image.targetRange.to));
      }
      return null;
    },
    contextPositionAtEvent(state, event) {
      const target = event.target instanceof Element ? event.target : null;
      const shell = target?.closest<HTMLElement>(".cm-live-image[data-scholium-protected='image']");
      const from = Number(shell?.dataset.scholiumSourceFrom);
      const to = Number(shell?.dataset.scholiumSourceTo);
      if (!shell || !Number.isSafeInteger(from) || !Number.isSafeInteger(to)
        || from < 0 || to <= from || to > state.doc.length) return null;
      const index = options.projections.index(state);
      if (!index.syntax.inlines.some(image => image.kind === "image" && image.from === from && image.to === to)
        || !this.imageTargetAt(state, {from, to})) return null;
      // Menus address the image itself. Ordinary clicks still choose either
      // source edge, while a block's trailing edge is outside this image.
      return from;
    },
    setResources(value, view) {
      resources = value;
      if (view?.state.field(refresh, false)) view.dispatch({effects:
        preserveLivePresentationLayout.of({from: 0, to: view.state.doc.length})});
    },
  };
}
