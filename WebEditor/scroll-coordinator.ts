import {EditorView} from "@codemirror/view";
import type {EditorScrollAnchor} from "./protocol";
import {recordEditorMetric} from "./performance";

export interface EditorScrollCoordinator {
  currentAnchor(): EditorScrollAnchor;
  postCurrent(): void;
  scheduleGeometryReport(): void;
  setAnchor(anchor: EditorScrollAnchor): void;
  setFraction(fraction: number): void;
}

/** Owns scroll observation, metrics, and restoration for one retained view. */
export function createEditorScrollCoordinator(
  editor: EditorView,
  options: {
    post(anchor: EditorScrollAnchor): void;
    onScroll(): void;
    flushPresentationGeometry(): void;
  },
): EditorScrollCoordinator {
  function currentAnchor(): EditorScrollAnchor {
    const extent = Math.max(0, editor.scrollDOM.scrollHeight - editor.scrollDOM.clientHeight);
    const fallbackFraction = extent > 0
      ? Math.max(0, Math.min(1, editor.scrollDOM.scrollTop / extent))
      : 0;
    const probeHeight = Math.max(0, editor.scrollDOM.scrollTop + 8);
    const block = editor.lineBlockAtHeight(probeHeight);
    const relativeBlockPosition = block.height > 0
      ? Math.max(0, Math.min(1, (probeHeight - block.top) / block.height))
      : 0;
    return {
      sourceUTF16Offset: block.from,
      blockUTF16LowerBound: block.from,
      blockUTF16UpperBound: block.to,
      relativeBlockPosition,
      fallbackFraction,
    };
  }

  function postCurrent() {
    options.post(currentAnchor());
  }

  let reportTimer: number | undefined;
  let sessionStartedAt: number | null = null;
  let previousFrameAt: number | null = null;
  let measurementFrame: number | null = null;
  let sessionFrameCount = 0;
  let sessionLongestFrame = 0;
  let sessionDroppedFrameCount = 0;
  editor.scrollDOM.addEventListener("scroll", () => {
    options.onScroll();
    if (sessionStartedAt === null) sessionStartedAt = performance.now();
    if (measurementFrame === null) {
      measurementFrame = window.requestAnimationFrame(() => {
        measurementFrame = null;
        const now = performance.now();
        sessionFrameCount += 1;
        if (previousFrameAt !== null) {
          const duration = Math.max(0, now - previousFrameAt);
          sessionLongestFrame = Math.max(sessionLongestFrame, duration);
          if (duration > 20) sessionDroppedFrameCount += 1;
        }
        previousFrameAt = now;
      });
    }
    window.clearTimeout(reportTimer);
    reportTimer = window.setTimeout(() => {
      postCurrent();
      if (sessionStartedAt !== null) {
        recordEditorMetric("scroll-session", sessionStartedAt, {
          frameCount: sessionFrameCount,
          longestFrameMilliseconds: sessionLongestFrame,
          droppedFrameCount: sessionDroppedFrameCount,
        });
      }
      sessionStartedAt = null;
      previousFrameAt = null;
      sessionFrameCount = 0;
      sessionLongestFrame = 0;
      sessionDroppedFrameCount = 0;
    }, 120);
  }, {passive: true});

  let geometryReportScheduled = false;
  function scheduleGeometryReport() {
    if (geometryReportScheduled) return;
    geometryReportScheduled = true;
    queueMicrotask(() => {
      geometryReportScheduled = false;
      const documentSnapshot = editor.state.doc;
      editor.requestMeasure({
        read: () => editor.state.doc === documentSnapshot,
        write: (isCurrentDocument) => {
          if (isCurrentDocument && editor.state.doc === documentSnapshot) postCurrent();
        },
      });
    });
  }

  function setFraction(requestedFraction: number) {
    options.flushPresentationGeometry();
    const fraction = Number.isFinite(requestedFraction)
      ? Math.max(0, Math.min(1, requestedFraction))
      : 0;
    const extent = Math.max(0, editor.scrollDOM.scrollHeight - editor.scrollDOM.clientHeight);
    editor.scrollDOM.scrollTop = extent * fraction;
  }

  function setAnchor(anchor: EditorScrollAnchor) {
    options.flushPresentationGeometry();
    const documentLength = editor.state.doc.length;
    const valid = Number.isSafeInteger(anchor.sourceUTF16Offset)
      && anchor.sourceUTF16Offset >= 0
      && anchor.sourceUTF16Offset <= documentLength
      && Number.isSafeInteger(anchor.blockUTF16LowerBound)
      && Number.isSafeInteger(anchor.blockUTF16UpperBound)
      && anchor.blockUTF16LowerBound >= 0
      && anchor.blockUTF16LowerBound <= anchor.sourceUTF16Offset
      && anchor.blockUTF16UpperBound >= anchor.sourceUTF16Offset
      && anchor.blockUTF16UpperBound <= documentLength;
    if (!valid) {
      setFraction(anchor.fallbackFraction);
      return;
    }
    const documentSnapshot = editor.state.doc;
    const relativePosition = Math.max(0, Math.min(1, anchor.relativeBlockPosition));
    const blockProbe = anchor.sourceUTF16Offset === anchor.blockUTF16LowerBound
      && anchor.blockUTF16UpperBound > anchor.blockUTF16LowerBound
      ? anchor.blockUTF16LowerBound + 1
      : anchor.sourceUTF16Offset;
    const requestedScrollTop = () => {
      const block = editor.lineBlockAt(blockProbe);
      return Math.max(0, block.top + block.height * relativePosition - 4);
    };
    const applyMeasuredAnchor = () => {
      if (editor.state.doc !== documentSnapshot) return;
      editor.requestMeasure({
        read: () => editor.state.doc === documentSnapshot ? requestedScrollTop() : null,
        write: (scrollTop) => {
          if (scrollTop === null || editor.state.doc !== documentSnapshot) return;
          editor.scrollDOM.scrollTop = scrollTop;
          postCurrent();
        },
      });
    };
    const applyScrollEffect = () => {
      if (editor.state.doc !== documentSnapshot) return;
      editor.dispatch({effects: EditorView.scrollIntoView(blockProbe, {y: "start", yMargin: 4})});
    };
    editor.scrollDOM.scrollTop = requestedScrollTop();
    postCurrent();
    applyScrollEffect();
    applyMeasuredAnchor();
    void document.fonts.ready.then(applyMeasuredAnchor);
    window.requestAnimationFrame(() => {
      applyScrollEffect();
      applyMeasuredAnchor();
    });
    window.setTimeout(() => {
      applyScrollEffect();
      applyMeasuredAnchor();
    }, 80);
  }

  return {currentAnchor, postCurrent, scheduleGeometryReport, setAnchor, setFraction};
}
