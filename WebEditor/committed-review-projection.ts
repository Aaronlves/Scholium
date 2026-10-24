import type {NativeFloatingPorts} from "./native-floating";
import {EditorState, Prec, StateEffect, StateField, type Extension} from "@codemirror/state";
import {Decoration, EditorView, WidgetType, type DecorationSet} from "@codemirror/view";
import {initializeReader, type ReaderPreparationPhase, type ReaderWindow} from "./reader-runtime";
import type {ExactSourceMirror} from "./state";
import {mapReviewAnchor, readLinkPreviewsEqual, reviewConfigurationSharesDOM, scopedReviewCSS, wrapReviewCSS, type CommittedReviewProjection} from "./committed-review-contract";
import {committedReviewRhythmCSS, projectCommittedReviewCalloutRhythm} from "./committed-review-rhythm";
import {bindCommittedReviewImageResources} from "./committed-review-images";
import {recordEditorMetric} from "./performance";
export {reviewProjectionMatches} from "./committed-review-contract";

interface ReviewProjectionOptions {
  projection(): CommittedReviewProjection | null;
  mirror(): ExactSourceMirror;
  imageResources(): Readonly<Record<string, string>>;
  nativeFloating: NativeFloatingPorts;
  postMessage(message: Record<string, unknown>): void;
}

export function createCommittedReviewProjection(options: ReviewProjectionOptions) {
  const setProjection = StateEffect.define<CommittedReviewProjection | null>();
  let root: HTMLElement | null = null;
  let scrollDOM: HTMLElement | null = null;
  let ready: Promise<void> | null = null;
  let mountedProjection: CommittedReviewProjection | null = null;
  let mountedAbort: AbortController | null = null;
  let mountedView: EditorView | null = null;
  let mountRevision = 0;

  function reportFailure(projection: CommittedReviewProjection, abort: AbortController) {
    if (abort.signal.aborted || mountedProjection !== projection) return;
    options.postMessage({version: projection.configuration.version,
      documentID: projection.configuration.documentID, fingerprint: projection.configuration.fingerprint,
      loadGeneration: projection.configuration.loadGeneration, type: "renderingFailed"});
  }

  class ReviewWidget extends WidgetType {
    constructor(readonly projection: CommittedReviewProjection | null) { super(); }
    eq(other: ReviewWidget) { return this.projection === other.projection; }
    toDOM(view: EditorView) {
      const shell = document.createElement("div");
      shell.className = "scholium-review-projection";
      shell.setAttribute("contenteditable", "false");
      shell.style.cssText = "white-space:normal;position:relative;min-height:100%;font-family:var(--scholium-document-body-font-family);font-size:var(--scholium-document-prose-font-size);line-height:var(--scholium-rhythm-prose-line-height);";
      if (!this.projection) { shell.setAttribute("aria-busy", "true"); return shell; }
      const projection = this.projection;
      const style = document.createElement("style");
      style.textContent = scopedReviewCSS(projection.css);
      shell.append(style);
      const presentationStyle = document.createElement("style");
      presentationStyle.dataset.scholiumReviewStyle = "presentation";
      const userStyle = document.createElement("style");
      userStyle.dataset.scholiumReviewStyle = "user";
      const rhythmStyle = document.createElement("style");
      rhythmStyle.textContent = wrapReviewCSS(committedReviewRhythmCSS);
      shell.append(presentationStyle, rhythmStyle, userStyle);
      const content = document.createElement("div");
      // Only native sanitized HTML reaches this boundary. It cannot write source.
      const insertionStartedAt = performance.now();
      content.innerHTML = projection.htmlBody;
      recordEditorMetric("review-html-insertion", insertionStartedAt, {review: 1, htmlUTF16Length: projection.htmlBody.length});
      shell.append(content);
      const main = content.querySelector<HTMLElement>("main#scholium-document");
      const popover = content.querySelector<HTMLElement>("#scholium-preview-popover");
      if (!main || !popover) throw new Error("Invalid committed Review document shell");
      bindCommittedReviewImageResources(main, options.imageResources());
      projectCommittedReviewCalloutRhythm(main, options.mirror(), view.state.doc);
      main.tabIndex = -1;
      const abort = new AbortController();
      main.addEventListener("keydown", event => {
        if ((event.metaKey || event.ctrlKey) && !event.altKey && event.key.toLowerCase() === "a") {
          event.preventDefault();
          const range = document.createRange(); range.selectNodeContents(main);
          const selection = window.getSelection(); selection?.removeAllRanges(); selection?.addRange(range);
        }
      }, {signal: abort.signal});
      mountedAbort?.abort();
      mountedAbort = abort;
      mountedProjection = projection;
      mountedView = view;
      root = main;
      scrollDOM = view.scrollDOM;
      const revision = ++mountRevision;
      // Widget construction precedes insertion. Install reading behavior after
      // CodeMirror has attached the same DOM and has finished its update.
      ready = Promise.resolve().then(async () => {
        if (abort.signal.aborted || revision !== mountRevision) throw new Error("stale Review mount");
        const initializationStartedAt = performance.now();
        let completed = false;
        try {
          await initializeReader(projection.configuration, {
            root: main, scrollDOM: view.scrollDOM, popover, signal: abort.signal, nativeFloating: options.nativeFloating,
            presentationStyle, userStyle,
            scopeStyles: {presentation: css => scopedReviewCSS(css, "local"), user: wrapReviewCSS},
            postMessage: options.postMessage, recordMetric: recordEditorMetric,
          });
          completed = !abort.signal.aborted && revision === mountRevision;
        } finally {
          recordEditorMetric("review-reader-initialization", initializationStartedAt, {review: 1, completed: completed ? 1 : 0});
        }
        if (abort.signal.aborted || revision !== mountRevision) throw new Error("stale Review mount");
        view.requestMeasure();
        options.postMessage({version: projection.configuration.version,
          documentID: projection.configuration.documentID, fingerprint: projection.configuration.fingerprint,
          loadGeneration: projection.configuration.loadGeneration, type: "ready"});
      }).catch(error => {
        reportFailure(projection, abort);
        throw error;
      });
      (window as ReaderWindow).scholiumReadReady = ready;
      // Native preparation observes the rejection; avoid an unhandled rejection
      // when navigation cancels a not-yet-prepared surface.
      void ready.catch(() => {});
      return shell;
    }
    ignoreEvent() { return true; }
    destroy(dom: HTMLElement) {
      if (!root || !dom.contains(root)) return;
      mountedAbort?.abort(); mountedAbort = null;
      mountedProjection = null; mountedView = null; root = null; scrollDOM = null; ready = null; mountRevision++;
    }
  }

  const decorations = (state: EditorState, projection: CommittedReviewProjection | null): DecorationSet => {
    const widget = new ReviewWidget(projection);
    return Decoration.set([state.doc.length
      ? Decoration.replace({widget, block: true, inclusive: true}).range(0, state.doc.length)
      : Decoration.widget({widget, block: true, side: -1}).range(0)]);
  };
  const field = StateField.define<DecorationSet>({
    create: state => decorations(state, options.projection()),
    update(value, transaction) {
      if (transaction.docChanged) throw new Error("Review cannot mutate committed source");
      const update = transaction.effects.find(effect => effect.is(setProjection));
      return update ? decorations(transaction.state, update.value) : value;
    },
    provide: field => EditorView.decorations.from(field),
  });
  const extension: Extension = [field, EditorState.readOnly.of(true),
    Prec.highest(EditorView.editable.of(false)),
    // Review's DOM Selection belongs to the reader. CodeMirror can otherwise
    // map selectionchange from the replacement widget to the document end and
    // overwrite the writable selection retained for the next editing entry.
    EditorState.transactionFilter.of(transaction => transaction.docChanged || transaction.selection ? [] : transaction),
    EditorView.theme({
      "&.scholium-review-mode .cm-scroller": {display: "block", fontFamily: "inherit"},
      "&.scholium-review-mode .cm-selectionLayer, &.scholium-review-mode .cm-cursorLayer": {display: "none"},
      ".scholium-review-projection": {width: "100%"},
    }),
  ];
  return {
    extension, setProjection,
    refreshImageResources() {
      if (!root || !mountedView || !mountedAbort || mountedAbort.signal.aborted) return;
      const changed = bindCommittedReviewImageResources(root, options.imageResources());
      const reader = window as ReaderWindow;
      for (const image of changed) reader.scholiumReviewImages?.refreshImage(image);
      if (changed.length) {
        reader.scholiumDismissPreview?.();
        mountedView.requestMeasure();
      }
    },
    updateInPlace(projection: CommittedReviewProjection | null) {
      const previous = mountedProjection;
      if (!previous || !projection || !root || !mountedView || !ready || !mountedAbort || mountedAbort.signal.aborted
          || previous.documentID !== projection.documentID || previous.sourceFingerprint !== projection.sourceFingerprint
          || previous.htmlBody !== projection.htmlBody || previous.css !== projection.css) return false;
      if (!reviewConfigurationSharesDOM(previous.configuration, projection.configuration)) return false;
      const abort = mountedAbort;
      const view = mountedView;
      mountedProjection = projection;
      ready = ready.then(async () => {
        if (abort.signal.aborted) throw new Error("stale Review update");
        const reader = window as ReaderWindow;
        // Previews are source-bound inert projections; appearance retains the
        // existing DOM Selection and source anchor in the reader owner.
        if (!readLinkPreviewsEqual(previous.configuration.linkPreviews, projection.configuration.linkPreviews)) {
          reader.scholiumSetLinkPreviews?.(projection.configuration.linkPreviews);
        }
        if (previous.configuration.presentationCSS !== projection.configuration.presentationCSS
            || previous.configuration.userCSS !== projection.configuration.userCSS) {
          await reader.scholiumSetPresentationCSS?.(projection.configuration.presentationCSS, projection.configuration.userCSS);
        }
        if (abort.signal.aborted) throw new Error("stale Review update");
        view.requestMeasure();
      }).catch(error => {
        reportFailure(projection, abort);
        throw error;
      });
      (window as ReaderWindow).scholiumReadReady = ready;
      void ready.catch(() => {});
      return true;
    },
    async prepare(expiresAt: number, phase: ReaderPreparationPhase) {
      const expected = mountedProjection;
      if (!ready || !expected) throw new Error("Committed Review projection is unavailable");
      let timeout: ReturnType<typeof setTimeout> | undefined;
      try {
        await Promise.race([ready, new Promise<never>((_resolve, reject) => {
          timeout = setTimeout(() => reject(new Error("Review preparation expired")), Math.max(0, expiresAt - Date.now()));
        })]);
      } catch (error) {
        if (mountedAbort) reportFailure(expected, mountedAbort);
        throw error;
      } finally { clearTimeout(timeout); }
      const reader = window as ReaderWindow;
      if (expected !== mountedProjection || !reader.scholiumReadPreparation) throw new Error("stale Review preparation");
      const config = expected.configuration;
      try {
        return await reader.scholiumReadPreparation.settle(config.documentID, config.fingerprint, config.loadGeneration, expiresAt, phase);
      } catch (error) {
        if (mountedAbort) reportFailure(expected, mountedAbort);
        throw error;
      }
    },
    focus() { root?.focus({preventScroll: true}); },
    selectAll() {
      if (!root) return false;
      const range = document.createRange(); range.selectNodeContents(root);
      const selection = window.getSelection(); selection?.removeAllRanges(); selection?.addRange(range);
      return Boolean(selection);
    },
    currentAnchor() {
      if (!scrollDOM) return null;
      const extent = Math.max(0, scrollDOM.scrollHeight - scrollDOM.clientHeight);
      const anchor = (window as ReaderWindow).scholiumReadScroll?.current(extent > 0 ? scrollDOM.scrollTop / extent : 0);
      return anchor ? mapReviewAnchor(anchor, options.mirror(), "normalized") : null;
    },
    setAnchor(anchor: Parameters<NonNullable<ReaderWindow['scholiumReadScroll']>['restore']>[0]) {
      const mapped = mapReviewAnchor(anchor, options.mirror(), "exact");
      return mapped ? (window as ReaderWindow).scholiumReadScroll?.restore(mapped) ?? false : false;
    },
    setFraction(fraction: number) {
      if (!scrollDOM) return;
      scrollDOM.scrollTop = Math.max(0, Math.min(1, fraction)) * Math.max(0, scrollDOM.scrollHeight - scrollDOM.clientHeight);
    },
  };
}
