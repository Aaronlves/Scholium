import {
  type ReadCommentAnchor,
  validatedReadCommentAnchors,
} from "./reader-configuration";

type Localize = (key: string, replacements?: Record<string, unknown>) => string;

interface ReviewCommentAnchorPresentation {
  setAnchors(value: unknown): boolean;
  testingSnapshot(): Record<string, unknown>;
}

interface SourceLocatedBlock {
  element: HTMLElement;
  startLine: number;
  endLine: number;
  depth: number;
}

function sourceLocatedBlocks(root: HTMLElement): SourceLocatedBlock[] {
  const blocks: SourceLocatedBlock[] = [];
  for (const element of root.querySelectorAll<HTMLElement>("[data-source-line]")) {
    if (element.closest(".scholium-embedded-note-body, .scholium-preview-body")) continue;
    if (element.closest('[data-scholium-protected="mermaid"]')) continue;
    const style = getComputedStyle(element);
    if (style.display === "inline" || style.display === "contents"
        || style.display === "none" || style.visibility === "hidden") continue;
    const startLine = Number(element.dataset.sourceLine);
    const endLine = Number(element.dataset.sourceEndLine || element.dataset.sourceLine);
    if (!Number.isSafeInteger(startLine) || startLine < 1
        || !Number.isSafeInteger(endLine) || endLine < startLine) continue;
    let depth = 0;
    let parent = element.parentElement;
    while (parent && parent !== root) {
      depth += 1;
      parent = parent.parentElement;
    }
    blocks.push({element, startLine, endLine, depth});
  }
  return blocks;
}

function blocksForAnchor(
  blocks: SourceLocatedBlock[],
  anchor: ReadCommentAnchor,
): SourceLocatedBlock[] {
  const overlapping = blocks.filter(block =>
    block.startLine <= anchor.endLine && block.endLine >= anchor.startLine
  );
  const leaves = overlapping.filter(candidate => !overlapping.some(other =>
    other !== candidate && candidate.element.contains(other.element)
  ));
  return (leaves.length ? leaves : overlapping).sort((left, right) => {
    const order = left.element.compareDocumentPosition(right.element);
    if (order & Node.DOCUMENT_POSITION_FOLLOWING) return -1;
    if (order & Node.DOCUMENT_POSITION_PRECEDING) return 1;
    const leftSpan = left.endLine - left.startLine;
    const rightSpan = right.endLine - right.startLine;
    return leftSpan - rightSpan || right.depth - left.depth;
  });
}

function markerLabel(anchor: ReadCommentAnchor, localized: Localize): string {
  if (anchor.commentCount === 1) {
    return anchor.startLine === anchor.endLine
      ? localized("Open comment at line {start}", {start: anchor.startLine})
      : localized("Open comment at lines {start} through {end}", {
        start: anchor.startLine,
        end: anchor.endLine,
      });
  }
  return anchor.startLine === anchor.endLine
    ? localized("Open {count} comments at line {start}", {
      count: anchor.commentCount,
      start: anchor.startLine,
    })
    : localized("Open {count} comments at lines {start} through {end}", {
      count: anchor.commentCount,
      start: anchor.startLine,
      end: anchor.endLine,
    });
}

export function createReviewCommentAnchorPresentation(
  root: HTMLElement,
  localized: Localize,
  commentSymbol: string,
  activate: (anchorID: string) => void,
): ReviewCommentAnchorPresentation {
  let anchors: ReadCommentAnchor[] = [];
  let resizeObserver: ResizeObserver | undefined;
  let layoutFrame = 0;

  const clear = () => {
    cancelAnimationFrame(layoutFrame);
    layoutFrame = 0;
    for (const marker of root.querySelectorAll<HTMLElement>(
      ":scope > [data-scholium-comment-anchor]",
    )) marker.remove();
    for (const block of root.querySelectorAll<HTMLElement>(
      ".scholium-review-comment-range, .scholium-review-comment-range-active",
    )) {
      block.classList.remove(
        "scholium-review-comment-range",
        "scholium-review-comment-range-active",
      );
      delete block.dataset.scholiumCommentAnchorTarget;
    }
    root.classList.remove("scholium-has-comment-anchors");
  };

  const layout = () => {
    layoutFrame = 0;
    const rootBounds = root.getBoundingClientRect();
    const rootStyle = getComputedStyle(root);
    const contentLeft = Number.parseFloat(rootStyle.paddingLeft) || 0;
    const contentRight = rootBounds.width - (Number.parseFloat(rootStyle.paddingRight) || 0);
    let priorMarkerBottom = -Infinity;
    for (const marker of root.querySelectorAll<HTMLElement>(
      ":scope > [data-scholium-comment-anchor]",
    )) {
      const anchorID = marker.dataset.scholiumCommentAnchor;
      const target = anchorID
        ? root.querySelector<HTMLElement>(
          `[data-scholium-comment-anchor-target~="${CSS.escape(anchorID)}"]`,
        )
        : null;
      if (!target) {
        marker.hidden = true;
        continue;
      }
      marker.hidden = false;
      const targetBounds = target.getBoundingClientRect();
      const markerBounds = marker.getBoundingClientRect();
      const markerWidth = Math.max(20, markerBounds.width);
      const markerHeight = Math.max(20, markerBounds.height);
      const preferredLeft = rootStyle.direction === "rtl"
        ? contentLeft - markerWidth - 4
        : contentRight + 4;
      const left = Math.max(
        2,
        Math.min(preferredLeft, rootBounds.width - markerWidth - 2),
      );
      const top = Math.max(
        0,
        targetBounds.top - rootBounds.top,
        priorMarkerBottom + 3,
      );
      marker.style.left = `${left}px`;
      marker.style.top = `${top}px`;
      priorMarkerBottom = top + markerHeight;
    }
  };

  const scheduleLayout = () => {
    cancelAnimationFrame(layoutFrame);
    layoutFrame = requestAnimationFrame(layout);
  };

  const setActive = (anchorID: string, active: boolean) => {
    for (const block of root.querySelectorAll<HTMLElement>(
      `[data-scholium-comment-anchor-target~="${CSS.escape(anchorID)}"]`,
    )) block.classList.toggle("scholium-review-comment-range-active", active);
  };

  const render = () => {
    clear();
    if (!anchors.length) return;
    const blocks = sourceLocatedBlocks(root);
    for (const anchor of [...anchors].sort((left, right) =>
      left.startLine - right.startLine
        || left.endLine - right.endLine
        || left.id.localeCompare(right.id)
    )) {
      const located = blocksForAnchor(blocks, anchor);
      if (!located.length) continue;
      for (const block of located) {
        block.element.classList.add("scholium-review-comment-range");
        const existing = block.element.dataset.scholiumCommentAnchorTarget;
        block.element.dataset.scholiumCommentAnchorTarget = existing
          ? `${existing} ${anchor.id}`
          : anchor.id;
      }
      const marker = document.createElement("button");
      marker.type = "button";
      marker.className = "scholium-review-comment-anchor scholium-selection-control";
      marker.dataset.scholiumCommentAnchor = anchor.id;
      marker.dataset.commentCount = String(anchor.commentCount);
      const label = markerLabel(anchor, localized);
      marker.setAttribute("aria-label", label);
      marker.title = label;
      marker.style.setProperty("--scholium-comment-symbol", `url("${commentSymbol}")`);
      marker.addEventListener("pointerenter", () => setActive(anchor.id, true));
      marker.addEventListener("pointerleave", () => setActive(anchor.id, false));
      marker.addEventListener("focusin", () => setActive(anchor.id, true));
      marker.addEventListener("focusout", () => setActive(anchor.id, false));
      marker.addEventListener("click", () => activate(anchor.id));
      const firstTopLevel = (() => {
        let element = located[0].element;
        while (element.parentElement && element.parentElement !== root) {
          element = element.parentElement;
        }
        return element;
      })();
      root.insertBefore(marker, firstTopLevel);
    }
    root.classList.add("scholium-has-comment-anchors");
    scheduleLayout();
  };

  window.addEventListener("resize", scheduleLayout);
  if (typeof ResizeObserver !== "undefined") {
    resizeObserver = new ResizeObserver(scheduleLayout);
    resizeObserver.observe(root);
  }

  return {
    setAnchors(value: unknown) {
      const validated = validatedReadCommentAnchors(value);
      if (!validated) return false;
      anchors = validated;
      render();
      return true;
    },
    testingSnapshot() {
      return {
        anchorCount: anchors.length,
        markerCount: root.querySelectorAll(
          ":scope > [data-scholium-comment-anchor]",
        ).length,
        highlightedBlockCount: root.querySelectorAll(
          ".scholium-review-comment-range",
        ).length,
        resizeObserverInstalled: Boolean(resizeObserver),
      };
    },
  };
}
