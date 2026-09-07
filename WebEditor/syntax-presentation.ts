import {Decoration, EditorView, ViewPlugin, type ViewUpdate} from "@codemirror/view";

/** Only short, single-line delimiters may displace prose. Destinations,
 * annotations and technical source retain ordinary wrapping instead. */
export function canDisplaceSyntax(source: string): boolean {
  return source.length > 0 && source.length <= 24 && /^[\x20-\x7e]+$/.test(source);
}

export function syntaxToken(source: string, from: number, to: number, exposed: boolean,
  kind: "inline" | "prefix" = "inline", className = "") {
  return Decoration.mark({
    class: `cm-syntax-token ${exposed ? className : ""}`.trim(),
    attributes: {
      "data-syntax-key": `${from}:${to}`,
      "data-syntax-open": String(exposed),
      "data-syntax-kind": kind,
      ...(exposed ? {} : {"aria-hidden": "true"}),
      "data-syntax-length": String(source.length),
    },
  });
}

interface TokenFrame { width: number; height: number; open: boolean; multiline: boolean }

export function prefixNeedsMargin(textWidth: number, tokenWidth: number,
  measure: number, availableMargin: number): boolean {
  return textWidth > measure && textWidth - tokenWidth <= measure
    && tokenWidth + 4 <= availableMargin;
}

/** Presentation only: never dispatches a source/selection transaction. A
 * retained mark carries exact text in both states, so exit can reverse entry.
 * Input, composition, scrolling and resizing finish motion immediately. */
export const syntaxPresentation = ViewPlugin.fromClass(class {
  private frames = new Map<string, TokenFrame>();
  private borrowed = new Set<string>();
  private placements = new Map<string, {node: HTMLElement; width: number; animation: Animation}>();
  private transitions = new Map<string, {animation: Animation; from: number; to: number}>();
  private animations: Animation[] = [];
  private objects = new Set<HTMLElement>();
  private frame = 0;
  private destroyed = false;
  private reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  private resize: ResizeObserver;
  private inlineSize = 0;

  constructor(readonly view: EditorView) {
    this.reduced.addEventListener("change", this.stop);
    this.resize = new ResizeObserver(entries => {
      const width = entries[0]?.contentRect.width ?? 0;
      if (width === this.inlineSize) return;
      this.inlineSize = width;
      this.stop();
      for (const placement of this.placements.values()) placement.animation.cancel();
      this.placements.clear();
      this.borrowed.clear();
      this.frames.clear();
      this.measure(false);
    });
    this.resize.observe(view.scrollDOM);
    this.measure(false);
  }

  readonly stop = () => {
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    for (const animation of this.animations) animation.cancel();
    this.animations = [];
  };

  update(update: ViewUpdate) {
    if (!update.docChanged && !update.selectionSet && update.transactions.length === 0) return;
    const animate = !update.docChanged && !update.viewportChanged
      && !this.view.composing
      && update.state.selection.main.empty && !this.reduced.matches;
    for (const [key, transition] of this.transitions) {
      const frame = this.frames.get(key);
      const progress = transition.animation.effect?.getComputedTiming().progress;
      if (frame && typeof progress === "number") {
        frame.width = transition.from + (transition.to - transition.from) * progress;
      }
    }
    this.transitions.clear();
    this.stop();
    this.measure(animate);
  }

  private measure(animate: boolean) {
    this.view.requestMeasure({
      key: this,
      read: () => ({
        objects: [...this.view.contentDOM.querySelectorAll<HTMLElement>(
          ".cm-live-table-widget, .cm-live-table, .cm-live-math, .cm-live-math-source, .cm-live-mermaid-widget, .cm-live-footnote-reference-widget, .cm-live-embed")],
        tokens: [...this.view.contentDOM.querySelectorAll<HTMLElement>(".cm-syntax-token")]
        .map(node => {
          const key = node.dataset.syntaxKey!;
          const open = node.dataset.syntaxOpen === "true";
          const width = node.getBoundingClientRect().width;
          const height = node.getBoundingClientRect().height;
          const line = node.closest<HTMLElement>(".cm-line");
          const multiline = height > parseFloat(getComputedStyle(node).lineHeight) + 1;
          let borrow = open && this.borrowed.has(key);
          if (borrow && node.getBoundingClientRect().left
            < this.view.scrollDOM.getBoundingClientRect().left + 4) borrow = false;
          if (open && !this.frames.get(key)?.open && node.dataset.syntaxKind === "prefix"
            && line && getComputedStyle(line).direction === "ltr") {
            const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
            let textWidth = 0;
            while (walker.nextNode()) {
              const text = walker.currentNode;
              if (text.parentElement?.closest('[data-syntax-open="false"]')) continue;
              const range = document.createRange();
              range.selectNodeContents(text);
              for (const rect of range.getClientRects()) textWidth += rect.width;
            }
            const style = getComputedStyle(line);
            const measure = line.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
            // Borrow only for a true leading prefix, never from preceding prose.
            borrow = node.offsetLeft <= parseFloat(style.paddingLeft) + 1
              && prefixNeedsMargin(textWidth, width, measure,
                node.getBoundingClientRect().left - this.view.scrollDOM.getBoundingClientRect().left);
          }
          const parentStyle = getComputedStyle(node.parentElement!);
          return {node, key, open, width, height, multiline, borrow,
            fontSize: parentStyle.fontSize, lineHeight: parentStyle.lineHeight};
        })}),
      write: ({tokens, objects}) => {
        if (this.destroyed) return;
        for (const object of objects) {
          if (animate && this.objects.size && !this.objects.has(object) && typeof object.animate === "function") {
            this.animations.push(object.animate([{opacity: .65}, {opacity: 1}],
              {duration: 100, easing: "ease-out"}));
          }
        }
        this.objects = new Set(objects);
        const next = new Map<string, TokenFrame>();
        for (const {node, key, open, width, height, multiline, borrow, fontSize, lineHeight} of tokens) {
          const previous = this.frames.get(key);
          const wasBorrowed = this.borrowed.has(key);
          if (borrow) this.borrowed.add(key); else this.borrowed.delete(key);
          const placement = this.placements.get(key);
          if (!borrow || placement?.node !== node || placement.width !== width) {
            placement?.animation.cancel();
            this.placements.delete(key);
            if (borrow && typeof node.animate === "function") {
              // Web Animations do not mutate CodeMirror-owned DOM attributes.
              const animation = node.animate([{marginInlineStart: `${-width}px`}],
                {duration: 0, fill: "forwards"});
              this.placements.set(key, {node, width, animation});
            }
          }
          next.set(key, {open, width, height, multiline});
          if (!animate || !previous || previous.open === open || previous.multiline || multiline || typeof node.animate !== "function") continue;
          const motionHeight = open ? height : previous.height;
          const animation = node.animate([
            {width: `${previous.width}px`, height: `${motionHeight}px`, fontSize, lineHeight, whiteSpace: "pre", marginInlineStart: `${wasBorrowed ? -previous.width : 0}px`, opacity: open ? .15 : 1},
            {width: `${width}px`, height: `${motionHeight}px`, fontSize, lineHeight, whiteSpace: "pre", marginInlineStart: `${borrow ? -width : 0}px`, opacity: open ? 1 : 0},
          ], {duration: 120, easing: "cubic-bezier(.2, 0, .2, 1)"});
          this.animations.push(animation);
          this.transitions.set(key, {animation, from: previous.width, to: width});
        }
        this.frames = next;
        for (const key of this.borrowed) if (!next.has(key)) this.borrowed.delete(key);
        for (const [key, placement] of this.placements) if (!next.has(key)) {
          placement.animation.cancel();
          this.placements.delete(key);
        }
        if (this.animations.length) this.tick();
      },
    });
  }

  private tick() {
    this.frame = requestAnimationFrame(() => {
      if (this.destroyed) return;
      this.view.requestMeasure();
      if (this.animations.some(animation => animation.playState === "running")) this.tick();
      else this.stop();
    });
  }

  destroy() {
    this.destroyed = true;
    this.stop();
    for (const placement of this.placements.values()) placement.animation.cancel();
    this.placements.clear();
    this.reduced.removeEventListener("change", this.stop);
    this.resize.disconnect();
  }
}, {eventHandlers: {
  compositionstart() { this.stop(); },
  mousedown() { this.stop(); },
}});
