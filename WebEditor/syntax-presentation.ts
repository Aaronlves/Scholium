import {Decoration, EditorView, ViewPlugin, type ViewUpdate} from "@codemirror/view";
import {
  readLiveCursorGeometry,
  writeLiveCursorGeometry,
  type LiveCursorGeometry,
} from "./live-cursor-geometry";

/** Only short, single-line delimiters may displace prose. Destinations,
 * annotations and technical source retain ordinary wrapping instead. */
export function canDisplaceSyntax(source: string): boolean {
  return /^(?:[*_~`=]{1,2}|#{1,6} ?|(?:> ?){1,3}|!?\[|\]|\(|\))$/.test(source);
}

export function canRetainSyntax(source: string): boolean {
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
      "data-syntax-displace": String(canDisplaceSyntax(source)),
      ...(exposed ? {} : {"aria-hidden": "true"}),
      "data-syntax-length": String(source.length),
    },
  });
}

interface TokenFrame {
  color: string;
  opacity: number;
  open: boolean;
}

interface TokenTransition {
  node: HTMLElement;
  animation: Animation;
  fromOpacity: number;
  toOpacity: number;
}

interface LayoutAnchor {
  from: number;
  top: number;
  scrollTop: number;
  epoch: number;
}

interface FrontmatterFrame {
  opacity: number;
  open: boolean;
}

interface FrontmatterTransition {
  animation: Animation;
  fromOpacity: number;
  toOpacity: number;
}

export function prefixNeedsMargin(textWidth: number, tokenWidth: number,
  measure: number, availableMargin: number): boolean {
  return textWidth > measure && textWidth - tokenWidth <= measure
    && tokenWidth + 4 <= availableMargin;
}

function lineElementAt(view: EditorView, position: number): HTMLElement | null {
  for (const assoc of [1, -1] as const) {
    try {
      const point = view.domAtPos(position, assoc);
      const element = point.node.nodeType === Node.ELEMENT_NODE
        ? point.node as Element
        : point.node.parentElement;
      const line = element?.closest<HTMLElement>(".cm-line");
      if (line) return line;
    } catch {
      // A line can leave the viewport between the block and DOM measurements.
    }
  }
  return null;
}

function captureLayoutAnchor(view: EditorView, epoch: number): LayoutAnchor | null {
  const scroll = view.scrollDOM;
  const rect = scroll.getBoundingClientRect();
  // `viewportLineBlocks` exposes the already-measured view state and is safe
  // during ViewPlugin.update. `lineBlockAtHeight` calls readMeasured(), which
  // CodeMirror rejects while it is applying a state update. Both the probe and
  // block tops use documentTop-relative coordinates, so adding scrollTop here
  // would count the scroll offset twice.
  const probeHeight = Math.max(0, rect.top + 1 - view.documentTop);
  const blocks = view.viewportLineBlocks;
  if (!blocks.length) return null;
  const containing = blocks.findIndex(candidate =>
    candidate.top <= probeHeight && candidate.bottom > probeHeight);
  const firstAfter = blocks.findIndex(candidate => candidate.bottom > probeHeight);
  const start = containing >= 0
    ? containing
    : firstAfter >= 0 ? firstAfter : blocks.length - 1;
  const candidates = blocks.slice(start).concat(blocks.slice(0, start));
  for (const candidate of candidates) {
    const line = lineElementAt(view, candidate.from);
    if (line) {
      return {
        from: candidate.from,
        top: line.getBoundingClientRect().top,
        scrollTop: scroll.scrollTop,
        epoch,
      };
    }
  }
  return null;
}

function applyLayoutAnchor(view: EditorView, anchor: LayoutAnchor): number {
  const line = lineElementAt(view, anchor.from);
  if (!line) return 0;
  const delta = line.getBoundingClientRect().top - anchor.top;
  if (Math.abs(delta) < 0.25) return 0;
  const scroll = view.scrollDOM;
  const maximum = Math.max(0, scroll.scrollHeight - scroll.clientHeight);
  const before = scroll.scrollTop;
  const after = Math.max(0, Math.min(maximum, before + delta));
  if (Math.abs(after - before) >= 0.25) scroll.scrollTop = after;
  return after - before;
}

/** Presentation only: never dispatches a source/selection transaction. A
 * retained mark carries exact text in both states, so exit can reverse entry.
 * Input, composition, scrolling and resizing finish motion immediately. */
export const syntaxPresentation = ViewPlugin.fromClass(class {
  private frames = new Map<string, TokenFrame>();
  private frontmatterFrames = new Map<string, FrontmatterFrame>();
  private borrowed = new Set<string>();
  private transitions = new Map<string, TokenTransition>();
  private frontmatterTransitions = new Map<string, FrontmatterTransition>();
  private animations: Animation[] = [];
  private objects = new Set<HTMLElement>();
  private destroyed = false;
  private layoutEpoch = 0;
  private reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  private resize: ResizeObserver;
  private inlineSize = 0;

  constructor(readonly view: EditorView) {
    this.reduced.addEventListener("change", this.invalidateLayoutAnchor);
    this.resize = new ResizeObserver(entries => {
      const width = entries[0]?.contentRect.width ?? 0;
      if (width === this.inlineSize) return;
      this.inlineSize = width;
      this.invalidateLayoutAnchor();
      this.borrowed.clear();
      this.frames.clear();
      this.frontmatterFrames.clear();
      this.measure(false);
    });
    view.scrollDOM.addEventListener("scroll", this.invalidateLayoutAnchor, {passive: true});
    this.resize.observe(view.scrollDOM);
    this.measure(false);
  }

  readonly stop = () => {
    for (const animation of this.animations) animation.cancel();
    this.animations = [];
    this.transitions.clear();
    this.frontmatterTransitions.clear();
  };

  readonly invalidateLayoutAnchor = () => {
    this.layoutEpoch += 1;
    this.stop();
  };

  private scheduleLayoutAnchor(anchor: LayoutAnchor) {
    queueMicrotask(() => {
      if (this.destroyed || anchor.epoch !== this.layoutEpoch || this.view.composing) return;
      const scroll = this.view.scrollDOM;
      if (Math.abs(scroll.scrollTop - anchor.scrollTop) >= 0.25) return;
      const scrollCorrection = applyLayoutAnchor(this.view, anchor);
      if (scrollCorrection === 0) return;
      const cursor = readLiveCursorGeometry(this.view);
      writeLiveCursorGeometry(this.view, cursor && {
        ...cursor,
        top: cursor.top - scrollCorrection,
        bottom: cursor.bottom - scrollCorrection,
      });
    });
  }

  update(update: ViewUpdate) {
    if (!update.docChanged && !update.selectionSet && update.transactions.length === 0) return;
    this.layoutEpoch += 1;
    const animate = !update.docChanged
      && !this.view.composing
      && update.state.selection.main.empty && !this.reduced.matches;
    const layoutAnchor = !update.docChanged && update.selectionSet
      && !this.view.composing
      && update.transactions.every(transaction =>
        !transaction.scrollIntoView && transaction.effects.length === 0)
      ? captureLayoutAnchor(this.view, this.layoutEpoch)
      : null;
    for (const [key, transition] of this.transitions) {
      const frame = this.frames.get(key);
      const progress = transition.animation.effect?.getComputedTiming().progress;
      if (frame && typeof progress === "number") {
        frame.color = getComputedStyle(transition.node).color || frame.color;
        frame.opacity = transition.fromOpacity
          + (transition.toOpacity - transition.fromOpacity) * progress;
      }
    }
    for (const [key, transition] of this.frontmatterTransitions) {
      const frame = this.frontmatterFrames.get(key);
      const progress = transition.animation.effect?.getComputedTiming().progress;
      if (frame && typeof progress === "number") {
        frame.opacity = transition.fromOpacity
          + (transition.toOpacity - transition.fromOpacity) * progress;
      }
    }
    this.transitions.clear();
    this.frontmatterTransitions.clear();
    this.stop();
    this.measure(animate, layoutAnchor);
  }

  private measure(animate: boolean, layoutAnchor: LayoutAnchor | null = null) {
    this.view.requestMeasure({
      key: this,
      read: () => ({
        objects: [...this.view.contentDOM.querySelectorAll<HTMLElement>(
          // Technical projections own their fade-only entry in CSS. Keeping
          // them out of this generic object pulse avoids two animation owners
          // competing while a widget is exchanged for its exact source.
          ".cm-live-table-widget, .cm-live-table, .cm-live-footnote-reference-widget, .cm-live-embed")],
        cursor: readLiveCursorGeometry(this.view),
        frontmatter: [...this.view.contentDOM.querySelectorAll<HTMLElement>(
          ".scholium-frontmatter-delimiter-line[data-scholium-yaml-delimiter]")]
        .map((node, index) => {
          const style = getComputedStyle(node);
          return {
            node,
            key: node.dataset.scholiumYamlDelimiter ?? String(index),
            opacity: Number.parseFloat(style.opacity) || 0,
            open: node.classList.contains("scholium-frontmatter-delimiter-line-active"),
          };
        }),
        tokens: [...this.view.contentDOM.querySelectorAll<HTMLElement>(".cm-syntax-token")]
        .map(node => {
          const key = node.dataset.syntaxKey!;
          const open = node.dataset.syntaxOpen === "true";
          const width = node.getBoundingClientRect().width;
          const line = node.closest<HTMLElement>(".cm-line");
          const displace = node.dataset.syntaxDisplace === "true"
            && !line?.matches(".cm-live-callout, .cm-live-codeblock, .cm-live-rule, .scholium-frontmatter-line");
          let borrow = open && this.borrowed.has(key);
          if (borrow && node.getBoundingClientRect().left
            < this.view.scrollDOM.getBoundingClientRect().left + 4) borrow = false;
          if (displace && open && !this.frames.get(key)?.open && node.dataset.syntaxKind === "prefix"
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
          const style = getComputedStyle(node);
          return {node, key, open, width, borrow,
            activeColor: style.getPropertyValue("--scholium-syntax-active-ink").trim(),
            secondaryColor: style.getPropertyValue("--scholium-color-secondary-text").trim(),
            opacity: Number.parseFloat(style.opacity) || 0};
        })}),
      write: ({tokens, objects, cursor, frontmatter}: {
        tokens: readonly {
          node: HTMLElement;
          key: string;
          open: boolean;
          width: number;
          activeColor: string;
          secondaryColor: string;
          borrow: boolean;
          opacity: number;
        }[];
        objects: readonly HTMLElement[];
        cursor: LiveCursorGeometry | null;
        frontmatter: readonly {
          node: HTMLElement;
          key: string;
          opacity: number;
          open: boolean;
          }[];
      }) => {
        if (this.destroyed) return;
        for (const object of objects) {
          if (animate && this.objects.size && !this.objects.has(object) && typeof object.animate === "function") {
            this.animations.push(object.animate([{opacity: .65}, {opacity: 1}],
              {duration: 100, easing: "ease-out"}));
          }
        }
        this.objects = new Set(objects);
        const nextFrontmatter = new Map<string, FrontmatterFrame>();
        for (const {node, key, opacity, open} of frontmatter) {
          const previous = this.frontmatterFrames.get(key);
          nextFrontmatter.set(key, {opacity, open});
          if (!animate || !previous || previous.open === open || typeof node.animate !== "function") continue;
          const fromOpacity = open ? 0 : previous.opacity;
          const toOpacity = open ? opacity : 0;
          const animation = node.animate([
            {opacity: fromOpacity},
            {opacity: toOpacity},
          ], {duration: 140, easing: "cubic-bezier(.2, 0, .2, 1)", fill: "both"});
          this.animations.push(animation);
          this.frontmatterTransitions.set(key, {
            animation,
            fromOpacity,
            toOpacity,
          });
        }
        this.frontmatterFrames = nextFrontmatter;
        const next = new Map<string, TokenFrame>();
        let marginChanged = false;
        for (const {node, key, open, width, borrow, activeColor, secondaryColor} of tokens) {
          const previous = this.frames.get(key);
          if (borrow) this.borrowed.add(key); else this.borrowed.delete(key);
          const targetMargin = borrow ? -width : 0;
          if (targetMargin === 0) {
            if (node.style.marginInlineStart) {
              node.style.removeProperty("margin-inline-start");
              marginChanged = true;
            }
          } else if (node.style.marginInlineStart !== `${targetMargin}px`) {
            // Prefix borrowing is a layout decision, not a transition. Commit
            // it before any visual pulse so the line never crosses a wrap
            // threshold during the animation.
            node.style.marginInlineStart = `${targetMargin}px`;
            marginChanged = true;
          }
          const targetOpacity = open ? 1 : 0;
          next.set(key, {
            open,
            color: open ? activeColor : secondaryColor,
            opacity: targetOpacity,
          });
          if (!animate || !previous || previous.open === open || typeof node.animate !== "function") continue;
          const animation = node.animate([
            {opacity: previous.opacity, color: previous.color},
            {opacity: targetOpacity, color: open ? activeColor : secondaryColor},
          ], {duration: 140, easing: "cubic-bezier(.2, 0, .2, 1)", fill: "both"});
          this.animations.push(animation);
          this.transitions.set(key, {
            node,
            animation,
            fromOpacity: previous.opacity,
            toOpacity: targetOpacity,
          });
        }
        this.frames = next;
        for (const key of this.borrowed) if (!next.has(key)) this.borrowed.delete(key);
        // Geometry is already in its final state. If prefix borrowing changed
        // the line, re-read the cursor after that synchronous commit. Defer
        // the custom anchor correction until CodeMirror finishes this measure
        // cycle, so its own scroll anchoring remains the first and only
        // correction in this cycle.
        const measuredCursor = marginChanged ? readLiveCursorGeometry(this.view) : cursor;
        if (layoutAnchor) this.scheduleLayoutAnchor(layoutAnchor);
        writeLiveCursorGeometry(this.view, measuredCursor);
      },
    });
  }

  destroy() {
    this.destroyed = true;
    this.stop();
    this.reduced.removeEventListener("change", this.invalidateLayoutAnchor);
    this.view.scrollDOM.removeEventListener("scroll", this.invalidateLayoutAnchor);
    this.resize.disconnect();
  }
}, {eventHandlers: {
  compositionstart() { this.invalidateLayoutAnchor(); },
  mousedown() { this.invalidateLayoutAnchor(); },
}});
