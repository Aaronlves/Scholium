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
  width: number;
  height: number;
  opacity: number;
  marginInlineStart: number;
  open: boolean;
  multiline: boolean;
}

interface TokenTransition {
  node: HTMLElement;
  animation: Animation;
  fromWidth: number;
  toWidth: number;
  fromOpacity: number;
  toOpacity: number;
  fromMarginInlineStart: number;
  toMarginInlineStart: number;
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

/** Presentation only: never dispatches a source/selection transaction. A
 * retained mark carries exact text in both states, so exit can reverse entry.
 * Input, composition, scrolling and resizing finish motion immediately. */
export const syntaxPresentation = ViewPlugin.fromClass(class {
  private frames = new Map<string, TokenFrame>();
  private frontmatterFrames = new Map<string, FrontmatterFrame>();
  private borrowed = new Set<string>();
  private placements = new Map<string, {node: HTMLElement; width: number; animation: Animation}>();
  private transitions = new Map<string, TokenTransition>();
  private frontmatterTransitions = new Map<string, FrontmatterTransition>();
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
      this.frontmatterFrames.clear();
      this.measure(false);
    });
    view.scrollDOM.addEventListener("scroll", this.stop, {passive: true});
    this.resize.observe(view.scrollDOM);
    this.measure(false);
  }

  readonly stop = () => {
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    for (const animation of this.animations) animation.cancel();
    this.animations = [];
    this.transitions.clear();
    this.frontmatterTransitions.clear();
  };

  update(update: ViewUpdate) {
    if (!update.docChanged && !update.selectionSet && update.transactions.length === 0) return;
    const animate = !update.docChanged
      && !this.view.composing
      && update.state.selection.main.empty && !this.reduced.matches;
    for (const [key, transition] of this.transitions) {
      const frame = this.frames.get(key);
      const progress = transition.animation.effect?.getComputedTiming().progress;
      if (frame && typeof progress === "number") {
        frame.color = getComputedStyle(transition.node).color || frame.color;
        frame.width = transition.fromWidth
          + (transition.toWidth - transition.fromWidth) * progress;
        frame.opacity = transition.fromOpacity
          + (transition.toOpacity - transition.fromOpacity) * progress;
        frame.marginInlineStart = transition.fromMarginInlineStart
          + (transition.toMarginInlineStart - transition.fromMarginInlineStart) * progress;
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
    this.measure(animate);
  }

  private measure(animate: boolean) {
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
          const height = node.getBoundingClientRect().height;
          const line = node.closest<HTMLElement>(".cm-line");
          const multiline = height > parseFloat(getComputedStyle(node).lineHeight) + 1;
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
          const parentStyle = getComputedStyle(node.parentElement!);
          const style = getComputedStyle(node);
          return {node, key, open, width, height, multiline, borrow, displace,
            activeColor: style.getPropertyValue("--scholium-syntax-active-ink").trim(),
            secondaryColor: style.getPropertyValue("--scholium-color-secondary-text").trim(),
            opacity: Number.parseFloat(style.opacity) || 0,
            marginInlineStart: borrow ? -width : 0,
            fontSize: parentStyle.fontSize, lineHeight: parentStyle.lineHeight};
        })}),
      write: ({tokens, objects, cursor, frontmatter}: {
        tokens: readonly {
          node: HTMLElement;
          key: string;
          open: boolean;
          width: number;
          height: number;
          multiline: boolean;
          displace: boolean;
          activeColor: string;
          secondaryColor: string;
          borrow: boolean;
          opacity: number;
          marginInlineStart: number;
          fontSize: string;
          lineHeight: string;
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
        writeLiveCursorGeometry(this.view, cursor);
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
        for (const {node, key, open, width, height, multiline, borrow, fontSize, lineHeight, displace, activeColor, secondaryColor} of tokens) {
          const previous = this.frames.get(key);
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
          const targetOpacity = open ? 1 : 0;
          const targetMarginInlineStart = borrow ? -width : 0;
          next.set(key, {
            open,
            color: open ? activeColor : secondaryColor,
            width,
            height,
            opacity: targetOpacity,
            marginInlineStart: targetMarginInlineStart,
            multiline,
          });
          if (!animate || !previous || previous.open === open || previous.multiline || multiline || typeof node.animate !== "function") continue;
          const motionHeight = open ? height : previous.height;
          const geometryFrames = [
            {
              width: `${previous.width}px`,
              height: `${motionHeight}px`,
              fontSize,
              lineHeight,
              whiteSpace: "pre",
              marginInlineStart: `${previous.marginInlineStart}px`,
              opacity: previous.opacity,
            },
            {
              width: `${width}px`,
              height: `${motionHeight}px`,
              fontSize,
              lineHeight,
              whiteSpace: "pre",
              marginInlineStart: `${targetMarginInlineStart}px`,
              opacity: targetOpacity,
            },
          ];
          const colorFrames = [
            {opacity: previous.opacity, color: previous.color},
            {opacity: targetOpacity, color: open ? activeColor : secondaryColor},
          ];
          const frames = displace
            ? geometryFrames.map((frame, index) => ({...frame, ...colorFrames[index]}))
            : colorFrames;
          const animation = node.animate(frames,
            {duration: 140, easing: "cubic-bezier(.2, 0, .2, 1)", fill: "both"});
          this.animations.push(animation);
          this.transitions.set(key, {
            node,
            animation,
            fromWidth: previous.width,
            toWidth: width,
            fromOpacity: previous.opacity,
            toOpacity: targetOpacity,
            fromMarginInlineStart: previous.marginInlineStart,
            toMarginInlineStart: targetMarginInlineStart,
          });
        }
        this.frames = next;
        for (const key of this.borrowed) if (!next.has(key)) this.borrowed.delete(key);
        for (const [key, placement] of this.placements) if (!next.has(key)) {
          placement.animation.cancel();
          this.placements.delete(key);
        }
        if (this.animations.some(animation => animation.playState === "running")) {
          this.tick();
        } else {
          this.stop();
        }
      },
    });
  }

  private tick() {
    this.frame = requestAnimationFrame(() => {
      if (this.destroyed) return;
      this.measure(false);
    });
  }

  destroy() {
    this.destroyed = true;
    this.stop();
    for (const placement of this.placements.values()) placement.animation.cancel();
    this.placements.clear();
    this.reduced.removeEventListener("change", this.stop);
    this.view.scrollDOM.removeEventListener("scroll", this.stop);
    this.resize.disconnect();
  }
}, {eventHandlers: {
  compositionstart() { this.stop(); },
  mousedown() { this.stop(); },
}});
