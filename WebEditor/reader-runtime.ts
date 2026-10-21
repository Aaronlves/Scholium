import {createReplyProjection} from './chat-reply-projection';
import {decorateChatReplyLinks} from './chat-link-presentation';
import {installChatReply} from "./chat-reply";
import {createSelectionActions} from "./selection-actions";
import {createReaderArrival} from "./arrival-highlight";
import {createNativeFloatingPorts, previewSurface, type NativeFloatingPorts, type NativeFloatingEvent} from "./native-floating";
import {installReviewFind, type ReviewFindRequest, type ReviewFindResult} from "./review-find";
import {
  boundedReviewRangeText,
  reviewContextAfter,
  reviewContextBefore,
} from "./review-selection-text";
import {createReviewSelectionPresentation} from "./review-selection-presentation";
import {
  type ReadLinkPreview,
  validatedReaderConfiguration,
} from "./reader-configuration";
import {bodyHeadingAccessibilityLevel} from "./heading-accessibility";
import {AnimationFrameCoalescer} from "./interaction-reporting";
import {decorateAttachmentLinks} from "./attachment-presentation";
import {createInterfaceLocalizer} from "./localization";
import {localizeRenderedInterface} from "./rendered-interface-localization";
import {installReviewImageActivation} from "./review-image-activation";
import {awaitVisibleDocumentImages, createDocumentImageReadiness} from "./document-widget-readiness";
import {sanitizePreviewDocument, renderPreviewMathNodes} from "./preview-document";
import {createReaderMermaidPass, type ReaderMermaidPass} from "./reader-mermaid-pass";

interface ReaderMessageHandler {
  postMessage(message: Record<string, unknown>): void;
}

export interface ReaderScrollAnchor {
  sourceUTF16Offset: number;
  blockUTF16LowerBound: number;
  blockUTF16UpperBound: number;
  relativeBlockPosition: number;
  fallbackFraction: number;
}

interface ReaderScrollEntry {
  element: HTMLElement;
  lower: number;
  upper: number;
  span: number;
}

export type ReaderWindow = Window & {
  scholiumUpdateReply?: (value: unknown) => Promise<boolean>;
  webkit?: {messageHandlers?: {scholiumRead?: ReaderMessageHandler}};
  scholiumReadReady?: Promise<void>;
  scholiumReadPreparation?: {
    settle(documentID: string, fingerprint: string, loadGeneration: number, expiresAt: number): Promise<{
      settled: true; geometryChanged: boolean;
    }>;
  };
  scholiumReadNavigation?: ReturnType<typeof createReaderArrival>;
  scholiumRead?: {initialize(value: unknown): Promise<void>};
  scholiumReviewFind?: {perform(request: ReviewFindRequest): ReviewFindResult};
  scholiumReviewSelection?: ReturnType<typeof createReviewSelectionPresentation>;
  scholiumReviewImages?: ReturnType<typeof installReviewImageActivation>;
  scholiumMermaidReady?: Promise<void>;
  scholiumDismissPreview?: () => void;
  scholiumSetLinkPreviews?: (previews: ReadLinkPreview[]) => void;
  scholiumSetPresentationCSS?: (presentationCSS: string, userCSS: string) => Promise<boolean>;
  scholiumSetReviewSelectionSurfaceActive?: (active: boolean) => boolean;
  scholiumShowSelectionActions?: () => Promise<number | null>;
  scholiumReadScroll?: {
    restoreCount: number;
    recordRestoreAttempt(): void;
    current(fraction: number): ReaderScrollAnchor | null;
    restore(anchor: ReaderScrollAnchor): boolean;
    testingSnapshot(): Record<string, unknown>;
    fraction(): number;
    setFraction(fraction: number): void;
  };
};

export interface ReaderRuntimeHost {
  root: HTMLElement;
  scrollDOM: HTMLElement;
  presentationStyle: HTMLStyleElement;
  userStyle: HTMLStyleElement;
  scopeStyles?: {presentation(css: string): string; user(css: string): string};
  popover: HTMLElement;
  postMessage(message: Record<string, unknown>): void;
  signal: AbortSignal;
  nativeFloating: NativeFloatingPorts;
  recordMetric?: (name: "review-scroll-registry" | "review-layout-settle", startedAt: number, observed: {
    review: number;
    completed?: number;
    candidateCount?: number;
    registeredBlockCount?: number;
    styleReadCount?: number;
    measureCount?: number;
    mathWaitMilliseconds?: number;
    mermaidWaitMilliseconds?: number;
    fontsWaitMilliseconds?: number;
    imageWaitMilliseconds?: number;
    imageWaitCount?: number;
    geometryChanged?: number;
  }) => void;
}

/** One disposable reader installation, hosted by either a page or a CodeMirror widget. */
export async function initializeReader(value: unknown, host?: ReaderRuntimeHost): Promise<void> {
  const readerWindow = window as ReaderWindow;
  const signal = host?.signal;
  const cleanups: Array<() => void> = [];
  const alive = () => !signal?.aborted;
  const listenWindow = ((type: string, listener: EventListenerOrEventListenerObject, options?: boolean | AddEventListenerOptions) => {
    const target = type === 'scroll' && host ? host.scrollDOM : window;
    target.addEventListener(type, listener as EventListener, {
      ...(typeof options === 'boolean' ? {capture: options} : options), ...(signal ? {signal} : {}),
    });
  }) as Window['addEventListener'];
  const listenDocument = ((type: string, listener: EventListenerOrEventListenerObject, options?: boolean | AddEventListenerOptions) => {
    // Selection belongs to the document; pointer/key actions belong to this reader only.
    const target = type === 'selectionchange' || !host ? document : host.root;
    target.addEventListener(type, listener as EventListener, {
      ...(typeof options === 'boolean' ? {capture: options} : options), ...(signal ? {signal} : {}),
    });
  }) as Document['addEventListener'];
  function requiredElement<ElementType extends HTMLElement>(id: string): ElementType {
    const element = document.getElementById(id);
    if (!(element instanceof HTMLElement)) throw new Error(`Missing reader element: ${id}`);
    return element as ElementType;
  }
  const documentRoot = host?.root ?? requiredElement('scholium-document');
  const elementByID = (id: string): HTMLElement | null => {
    if (!host) return document.getElementById(id);
    return documentRoot.id === id ? documentRoot
      : documentRoot.querySelector<HTMLElement>(`[id="${CSS.escape(id)}"]`);
  };
  const scrollTop = () => host?.scrollDOM.scrollTop ?? window.scrollY;
  const scrollLeft = () => host?.scrollDOM.scrollLeft ?? window.scrollX;
  const viewportHeight = () => host?.scrollDOM.clientHeight ?? window.innerHeight;
  const viewportTop = () => host?.scrollDOM.getBoundingClientRect().top ?? 0;
  const viewportBounds = () => host?.scrollDOM.getBoundingClientRect()
    ?? {left: 0, right: window.innerWidth, top: 0, bottom: window.innerHeight};
  const outsideViewport = (rect: Pick<DOMRectReadOnly, 'top' | 'bottom'>) => {
    const bounds = viewportBounds();
    return rect.bottom < bounds.top || rect.top > bounds.bottom;
  };
  const scrollHeight = () => host?.scrollDOM.scrollHeight ?? document.documentElement.scrollHeight;
  const scrollTo = (options: ScrollToOptions) => host ? host.scrollDOM.scrollTo(options) : window.scrollTo(options);
  const dispose = () => {
    for (const cleanup of cleanups) cleanup();
    readerWindow.scholiumReadNavigation?.destroy();
    readerWindow.scholiumReviewImages?.destroy();
    readerWindow.scholiumReviewSelection?.clear();
    (host?.root.closest<HTMLElement>('.scholium-review-projection') ?? document.documentElement).classList.remove('scholium-review-custom-selection');
    for (const key of ['scholiumReadPreparation', 'scholiumReadNavigation', 'scholiumReviewFind',
      'scholiumReviewSelection', 'scholiumReviewImages', 'scholiumDismissPreview', 'scholiumSetLinkPreviews',
      'scholiumSetPresentationCSS', 'scholiumSetReviewSelectionSurfaceActive',
      'scholiumShowSelectionActions', 'scholiumReadScroll', 'scholiumReadReady', 'scholiumMermaidReady'] as const) {
      delete readerWindow[key];
    }
  };
  signal?.addEventListener('abort', dispose, {once: true});

  const config = validatedReaderConfiguration(value);
  if (!config) throw new Error("Invalid reader configuration.");
  const {
    version, documentID, loadGeneration,
    selectionEnabled, presentationCSS, userCSS, localization, linkPreviews,
    testingEnabled,
  } = config;
  let fingerprint = config.fingerprint;
  const presentationStyle = host?.presentationStyle ?? requiredElement<HTMLStyleElement>('scholium-presentation-css');
  const userStyle = host?.userStyle ?? requiredElement<HTMLStyleElement>('scholium-user-css');
  const setPresentationStyles = (presentationCSS: string, userCSS: string) => {
    const presentation = host?.scopeStyles?.presentation(presentationCSS) ?? presentationCSS;
    const user = host?.scopeStyles?.user(userCSS) ?? userCSS;
    if (presentationStyle.textContent !== presentation) presentationStyle.textContent = presentation;
    if (userStyle.textContent !== user) userStyle.textContent = user;
  };
  setPresentationStyles(presentationCSS, userCSS);
  const decodedImages = createDocumentImageReadiness();
  async function settleLayout(requireCurrent: () => void): Promise<{settled: true; geometryChanged: boolean}> {
    const recordMetric = host?.recordMetric;
    const startedAt = recordMetric ? performance.now() : 0;
    const phases = {mathWaitMilliseconds: 0, mermaidWaitMilliseconds: 0,
      fontsWaitMilliseconds: 0, imageWaitMilliseconds: 0, imageWaitCount: 0,
      measureCount: 0, geometryChanged: 0, completed: 0};
    try {
      requireCurrent();
      const before = documentRoot.getBoundingClientRect();
      phases.measureCount++;
      const previousHeight = scrollHeight();
      // Initialization itself may still be settling; never await its own ready promise.
      let phaseStartedAt = recordMetric ? performance.now() : 0;
      await mathReady;
      if (recordMetric) phases.mathWaitMilliseconds += performance.now() - phaseStartedAt;
      phaseStartedAt = recordMetric ? performance.now() : 0;
      if (readerWindow.scholiumMermaidReady) await readerWindow.scholiumMermaidReady;
      if (recordMetric) phases.mermaidWaitMilliseconds += performance.now() - phaseStartedAt;
      requireCurrent();
      documentRoot.getBoundingClientRect();
      phases.measureCount++;
      const awaitedFonts = document.fonts.status === 'loading';
      phaseStartedAt = recordMetric ? performance.now() : 0;
      await document.fonts.ready;
      if (recordMetric) phases.fontsWaitMilliseconds += performance.now() - phaseStartedAt;
      requireCurrent();
      phaseStartedAt = recordMetric ? performance.now() : 0;
      let decodedVisibleImages = false;
      while (await awaitVisibleDocumentImages(documentRoot, viewportBounds(),
        decodedImages, requireCurrent, image => readerWindow.scholiumReviewImages?.refreshImage(image))) {
        decodedVisibleImages = true;
        phases.imageWaitCount++;
        requireCurrent();
      }
      if (recordMetric) phases.imageWaitMilliseconds += performance.now() - phaseStartedAt;
      documentRoot.getBoundingClientRect();
      phases.measureCount++;
      phaseStartedAt = recordMetric ? performance.now() : 0;
      await document.fonts.ready;
      if (recordMetric) phases.fontsWaitMilliseconds += performance.now() - phaseStartedAt;
      requireCurrent();
      const after = documentRoot.getBoundingClientRect();
      phases.measureCount++;
      const geometryChanged = decodedVisibleImages || awaitedFonts
        || before.height !== after.height || before.width !== after.width
        || previousHeight !== scrollHeight();
      phases.geometryChanged = geometryChanged ? 1 : 0;
      phases.completed = 1;
      return {settled: true, geometryChanged};
    } finally {
      // Only the shared Review host opts into the editor's bounded ring.
      // measureCount counts this owner's root reads, excluding image helpers.
      recordMetric?.("review-layout-settle", startedAt, {review: 1, ...phases});
    }
  }
  const readPreparation: NonNullable<ReaderWindow['scholiumReadPreparation']> = {
    async settle(expectedDocumentID, expectedFingerprint, expectedGeneration, expiresAt) {
      const requireCurrent = () => {
        if (readerWindow.scholiumReadPreparation !== readPreparation || !documentRoot.isConnected
            || expectedDocumentID !== documentID || expectedFingerprint !== fingerprint
            || expectedGeneration !== loadGeneration || !Number.isFinite(expiresAt) || Date.now() >= expiresAt) {
          throw new Error('stale reader preparation');
        }
      };
      return await settleLayout(requireCurrent);
    },
  };
  readerWindow.scholiumReadPreparation = readPreparation;
  let presentationUpdateSequence = 0;
  let viewportInputRevision = 0;
  const viewportInputTarget = host?.scrollDOM ?? window;
  const abandonAppearanceRestoration = () => { viewportInputRevision++; };
  const viewportInputEvents = ['wheel', 'pointerdown', 'touchstart', 'keydown'];
  for (const type of viewportInputEvents) {
    viewportInputTarget.addEventListener(type, abandonAppearanceRestoration, {capture: true, passive: true});
  }
  const disposeViewportInput = () => {
    viewportInputRevision++;
    for (const type of viewportInputEvents) {
      viewportInputTarget.removeEventListener(type, abandonAppearanceRestoration, true);
    }
    window.removeEventListener('pagehide', disposeViewportInput);
  };
  cleanups.push(disposeViewportInput);
  window.addEventListener('pagehide', disposeViewportInput, {once: true});
  let mermaidThemeRevision = 0;
  const replyProjection = config.replyProjection ? createReplyProjection(documentRoot) : null;
  decorateAttachmentLinks(documentRoot);
  if (config.replyProjection) decorateChatReplyLinks(documentRoot);
  readerWindow.scholiumReadNavigation?.destroy();
  readerWindow.scholiumReadNavigation = createReaderArrival(documentRoot, host?.scrollDOM);
  listenWindow('pagehide', () => readerWindow.scholiumReadNavigation?.destroy(), {once: true});
  documentRoot.querySelectorAll<HTMLElement>('h1, h2, h3, h4, h5, h6').forEach(heading => {
    const level = Number(heading.tagName.slice(1));
    heading.setAttribute('role', 'heading');
    heading.setAttribute('aria-level', String(bodyHeadingAccessibilityLevel(level)));
  });
  const localized = createInterfaceLocalizer(localization);
  localizeRenderedInterface(documentRoot, localized);
  const handler = host ? {postMessage: host.postMessage} : readerWindow.webkit?.messageHandlers?.scholiumRead;
  const post = (type: string, extra: Record<string, unknown> = {}) => alive() && handler?.postMessage({
    version, documentID, fingerprint, loadGeneration, type, ...extra,
  });
  readerWindow.scholiumReviewImages?.destroy();
  readerWindow.scholiumReviewImages = installReviewImageActivation(documentRoot, config.imagePreviewsEnabled ? {
    label: name => localized('Preview image {name}', {name}),
    preview: target => post('imagePreview', {target}),
    contextMenu: (target, clientX, clientY) => post('imageContextMenu', {
      target, clientX, clientY, payloadFingerprint: fingerprint,
    }),
  } : null);
  listenWindow('pagehide', () => readerWindow.scholiumReviewImages?.destroy(), {once: true});

  const popover = host?.popover ?? requiredElement('scholium-preview-popover');
  popover.remove();
  const postFloating = (event: NativeFloatingEvent) => post('floatingSurface', {event});
  const nativeFloating = host?.nativeFloating.forOwner(postFloating) ?? createNativeFloatingPorts(postFloating);
  let nativePreviewID = 0;
  let activePreviewAnchor: HTMLElement | null = null;
  let previewRevision = 0;
  let nativePreviewHovered = false;
  const previewTitle = popover.querySelector<HTMLElement>('.scholium-preview-title')!;
  const previewMetadata = popover.querySelector<HTMLElement>('.scholium-preview-metadata')!;
  const previewBody = popover.querySelector<HTMLElement>('.scholium-preview-body')!;
  // Embedded Review uses CodeMirror's scroller. This window-only overlay
  // scrollbar adapter belongs exclusively to the standalone reader page.
  if (!host) {
    const viewportRoot = document.documentElement;
    const viewportResizeScrollBarClass = 'scholium-viewport-resize-suppresses-overlay-scrollbar';
    const viewportResizeSettleDelay = 80;
    // A fixed viewport-unit probe distinguishes a real WKWebView resize from
    // scrollbar presentation changes, including while frames are suspended.
    const viewportGeometryProbe = document.createElement('span');
    viewportGeometryProbe.setAttribute('aria-hidden', 'true');
    viewportGeometryProbe.style.cssText = 'position:fixed;inline-size:100vw;block-size:100vh;visibility:hidden;pointer-events:none';
    document.body.append(viewportGeometryProbe);
    const viewportGeometry = () => viewportGeometryProbe.getBoundingClientRect();
    let viewportResizeGeneration = 0;
    let viewportResizeTimer: ReturnType<typeof setTimeout> | undefined;
    let viewportRearmTimer: ReturnType<typeof setTimeout> | undefined;
    let viewportBounds = viewportGeometry();
    const viewportDidResize = () => {
      const nextBounds = viewportGeometry();
      if (Math.abs(nextBounds.width - viewportBounds.width) < 0.5
          && Math.abs(nextBounds.height - viewportBounds.height) < 0.5) return;
      viewportBounds = nextBounds;
      const overlayScrollBar = Math.abs(window.innerWidth - viewportRoot.clientWidth) < 1;
      if (!overlayScrollBar) {
        viewportRoot.classList.remove(viewportResizeScrollBarClass);
        return;
      }
      const generation = ++viewportResizeGeneration;
      viewportRoot.classList.add(viewportResizeScrollBarClass);
      clearTimeout(viewportResizeTimer);
      viewportResizeTimer = setTimeout(() => {
        if (generation === viewportResizeGeneration) {
          window.removeEventListener('resize', viewportDidResize);
          viewportRoot.classList.remove(viewportResizeScrollBarClass);
          viewportRearmTimer = setTimeout(() => {
            if (generation !== viewportResizeGeneration) return;
            viewportBounds = viewportGeometry();
            window.addEventListener('resize', viewportDidResize);
          }, 0);
        }
      }, viewportResizeSettleDelay);
    };
    const disposeViewportResize = () => {
      viewportResizeGeneration++;
      clearTimeout(viewportResizeTimer);
      clearTimeout(viewportRearmTimer);
      window.removeEventListener('resize', viewportDidResize);
      window.removeEventListener('pagehide', disposeViewportResize);
      viewportRoot.classList.remove(viewportResizeScrollBarClass);
      viewportGeometryProbe.remove();
    };
    cleanups.push(disposeViewportResize);
    window.addEventListener('pagehide', disposeViewportResize, {once: true});
    window.addEventListener('resize', viewportDidResize);
  }
  const reviewFind = installReviewFind(documentRoot);
  readerWindow.scholiumReviewFind = reviewFind;
  cleanups.push(() => reviewFind.destroy());
  const reviewSelectionPresentation = createReviewSelectionPresentation(
    selectionEnabled,
    testingEnabled, host?.root.closest<HTMLElement>('.scholium-review-projection') ?? undefined,
  );
  readerWindow.scholiumReviewSelection = reviewSelectionPresentation;
  let reviewPointerSelectionActive = false;
  let reviewSelectionSurfaceActive = true;
  let previewByRange = new Map(linkPreviews.map(preview => [
    preview.utf16LowerBound + ':' + preview.utf16UpperBound,
    preview
  ]));
  const origins = new Map();
  function renderMathNodes(root: HTMLElement = documentRoot) {
    renderPreviewMathNodes(root);
  }
  function hasMathNodes(root: ParentNode): boolean {
    if (root.querySelector('.scholium-math[data-math-source][data-math-kind]')) return true;
    return [...root.querySelectorAll<HTMLTemplateElement>('template')]
      .some(template => hasMathNodes(template.content));
  }
  renderMathNodes();
  let finishMath: (() => void) | undefined;
  let mathReady = Promise.resolve();
  function ensureMathRuntime(): Promise<void> {
    if (readerWindow.scholiumMath?.version === 1) return Promise.resolve();
    if (finishMath) return mathReady;
    mathReady = new Promise<void>(resolve => {
      const timeout = setTimeout(() => { finishMath?.(); }, 8000);
      finishMath = () => { clearTimeout(timeout); resolve(); };
      cleanups.push(() => finishMath?.());
      post('requestMathRuntime');
    });
    return mathReady;
  }
  // Inert annotation templates do not delay opening the document. Their
  // mathematics joins this same promise only when a preview is requested.
  if (documentRoot.querySelector('.scholium-math[data-math-source][data-math-kind]')) void ensureMathRuntime();
  listenWindow('scholium-math-runtime-settled', () => {
    if (!alive()) return;
    renderMathNodes();
    finishMath?.();
  });

  function mermaidDiagnostic(wrapper: HTMLElement, message: string) {
    const diagnostic = document.createElement('p');
    diagnostic.className = 'scholium-mermaid-diagnostic';
    diagnostic.textContent = message;
    wrapper.append(diagnostic);
  }

  function isMermaidCode(code: Element) {
    return [...code.classList].some(name => name.toLowerCase() === 'language-mermaid');
  }

  let mermaidRuntimePromise: Promise<NonNullable<typeof window.scholiumMermaid> | null> | null = null;
  function ensureMermaidRuntime() {
    const current = readerWindow.scholiumMermaid;
    if (current?.version === 3) return Promise.resolve(current);
    if (!handler) return Promise.resolve(null);
    if (mermaidRuntimePromise) return mermaidRuntimePromise;
    mermaidRuntimePromise = new Promise<NonNullable<typeof window.scholiumMermaid> | null>((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        readerWindow.scholiumMermaidRuntimeDidLoad = undefined;
        const loaded = readerWindow.scholiumMermaid;
        if (loaded?.version !== 3) mermaidRuntimePromise = null;
        resolve(loaded?.version === 3 ? loaded : null);
      };
      const timeout = setTimeout(finish, 8000);
      cleanups.push(finish);
      readerWindow.scholiumMermaidRuntimeDidLoad = finish;
      post('requestMermaidRuntime');
    });
    return mermaidRuntimePromise;
  }

  async function renderMermaidWrapper(wrapper: HTMLElement, source: string, render: ReaderMermaidPass) {
    for (const child of [...wrapper.children]) {
      if (child.classList.contains('scholium-mermaid-output')
          || child.classList.contains('scholium-mermaid-diagnostic')
          || child.classList.contains('scholium-mermaid-accessible-source')) {
        child.remove();
      }
    }
    wrapper.classList.remove('scholium-mermaid-rendered', 'scholium-mermaid-error');
    const runtime = await ensureMermaidRuntime();
    if (!alive()) return;
    if (!runtime) {
      wrapper.classList.add('scholium-mermaid-error');
      mermaidDiagnostic(
        wrapper,
        localized('Diagram rendering is unavailable. Mermaid source is shown.')
      );
      return;
    }
    try {
      const result = await render(runtime, source);
      if (!alive()) return;
      if (!result.ok) {
        wrapper.classList.add('scholium-mermaid-error');
        mermaidDiagnostic(
          wrapper,
          localized('This Mermaid diagram is unsupported or could not be rendered. Source is shown.')
        );
        return;
      }
      const output = document.createElement('div');
      output.className = 'scholium-mermaid-output';
      if (!runtime.mount(output, result.svg)) {
        wrapper.classList.add('scholium-mermaid-error');
        mermaidDiagnostic(
          wrapper,
          localized('This Mermaid diagram could not be isolated safely. Source is shown.')
        );
        return;
      }
      wrapper.prepend(output);
      wrapper.classList.add('scholium-mermaid-rendered');
      if (result.accessibilityWarning) {
        const accessibleSource = document.createElement('span');
        accessibleSource.className = 'scholium-mermaid-accessible-source';
        accessibleSource.textContent = localized('Mermaid source: {source}', {source});
        wrapper.append(accessibleSource);
        mermaidDiagnostic(
          wrapper,
          localized('Add accTitle and accDescr to provide a concise nonvisual account of this diagram.')
        );
      }
    } catch (_) {
      wrapper.classList.add('scholium-mermaid-error');
      mermaidDiagnostic(
        wrapper,
        localized('This Mermaid diagram could not be rendered. Source is shown.')
      );
    }
  }

  async function renderMermaidNodes() {
    const nodes = [...documentRoot.querySelectorAll('pre > code')]
      .filter(code => isMermaidCode(code) && !code.closest('.scholium-mermaid'));
    const render = createReaderMermaidPass(
      nodes.map(code => code.textContent || ''), documentRoot, () => mermaidThemeRevision);
    for (const code of nodes) {
      const original = code.parentElement;
      if (!original) continue;
      const source = code.textContent || '';
      const wrapper = document.createElement('figure');
      wrapper.className = 'scholium-mermaid';
      wrapper.dataset.scholiumProtected = 'mermaid';
      for (const name of ['data-source-utf16-start', 'data-source-utf16-end', 'data-source-start-line', 'data-source-end-line', 'data-scholium-object']) {
        const value = original.getAttribute(name);
        if (value !== null) wrapper.setAttribute(name, value);
      }
      const fallback = original.cloneNode(true) as HTMLElement;
      fallback.classList.add('scholium-mermaid-source');
      wrapper.append(fallback);
      original.replaceWith(wrapper);
      await renderMermaidWrapper(wrapper, source, render);
    }
  }

  async function refreshMermaidNodes() {
    const wrappers = [...documentRoot.querySelectorAll<HTMLElement>('.scholium-mermaid')];
    const render = createReaderMermaidPass(
      wrappers.map(wrapper => wrapper.querySelector('.scholium-mermaid-source > code')?.textContent || ''),
      documentRoot, () => mermaidThemeRevision);
    for (const wrapper of wrappers) {
      const source = wrapper.querySelector('.scholium-mermaid-source > code')?.textContent || '';
      await renderMermaidWrapper(wrapper, source, render);
    }
  }

  function scheduleMermaidRefresh() {
    mermaidThemeRevision++;
    const current = readerWindow.scholiumMermaidReady || Promise.resolve();
    readerWindow.scholiumMermaidReady = current.catch(() => {}).then(refreshMermaidNodes);
  }

  readerWindow.scholiumSetPresentationCSS = async (nextPresentationCSS, nextUserCSS) => {
    if (typeof nextPresentationCSS !== 'string' || typeof nextUserCSS !== 'string'
        || nextPresentationCSS.length > 8_000_000 || nextUserCSS.length > 8_000_000) {
      return false;
    }
    const sequence = ++presentationUpdateSequence;
    const inputRevision = viewportInputRevision;
    const extent = Math.max(0, scrollHeight() - viewportHeight());
    const fallbackTop = scrollTop();
    const fraction = extent > 0 ? Math.max(0, Math.min(1, fallbackTop / extent)) : 0;
    const anchor = currentReadScrollAnchor(fraction);
    setPresentationStyles(nextPresentationCSS, nextUserCSS);
    scheduleMermaidRefresh();
    // Preparing/hidden WebKit pages can suspend animation frames. Resource
    // completion and synchronous geometry, shared with initial preparation,
    // establish readiness without requiring an already visible paint.
    const isCurrent = () => sequence === presentationUpdateSequence
      && readerWindow.scholiumReadPreparation === readPreparation && documentRoot.isConnected;
    try {
      await settleLayout(() => { if (!isCurrent()) throw new Error('stale presentation update'); });
    } catch (error) {
      if (!isCurrent()) return false;
      throw error;
    }
    if (!isCurrent()) return false;
    // The appearance still applied successfully. Only its saved viewport
    // yields to the researcher's input while fonts/images were settling.
    if (inputRevision !== viewportInputRevision) return true;
    if (anchor) {
      restoreReadScrollAnchor(anchor);
    } else {
      scrollTo({top: Math.max(0, fallbackTop), behavior: 'auto'});
    }
    return true;
  };
  readerWindow.scholiumMermaidReady = renderMermaidNodes();
  await Promise.all([mathReady, readerWindow.scholiumMermaidReady]);
  if (!alive()) return;
  if (config.replyProjection === true) {
    const disposeReply = installChatReply(documentRoot, post);
    replyProjection!.commit();
    readerWindow.scholiumUpdateReply = async value => {
      if (!value || typeof value !== 'object') return false;
      const update = value as Record<string, unknown>;
      if (update.version !== version || update.documentID !== documentID || update.loadGeneration !== loadGeneration
          || update.previousFingerprint !== fingerprint || typeof update.fingerprint !== 'string'
          || !update.fingerprint || update.fingerprint.length > 256
          || typeof update.html !== 'string' || update.html.length > 16_777_216
          || typeof update.presentationCSS !== 'string' || typeof update.userCSS !== 'string') return false;
      const restoreSelection = replyProjection!.apply(update.html);
      localizeRenderedInterface(documentRoot, localized);
      decorateAttachmentLinks(documentRoot);
      decorateChatReplyLinks(documentRoot);
      readerWindow.scholiumReviewImages?.refresh();
      fingerprint = update.fingerprint;
      setPresentationStyles(update.presentationCSS, update.userCSS);
      renderMathNodes();
      readerWindow.scholiumMermaidReady = renderMermaidNodes();
      await readerWindow.scholiumMermaidReady;
      documentRoot.querySelectorAll<HTMLElement>('h1, h2, h3, h4, h5, h6').forEach(heading => {
        heading.setAttribute('role', 'heading');
        heading.setAttribute('aria-level', String(bodyHeadingAccessibilityLevel(Number(heading.tagName.slice(1)))));
      });
      disposeReply.refresh();
      replyProjection!.commit();
      restoreSelection();
      return true;
    };
    listenWindow('pagehide', disposeReply, {once: true});
  }
  for (const mediaQuery of [
    matchMedia('(prefers-color-scheme: dark)'),
    matchMedia('(prefers-contrast: more)')
  ]) {
    mediaQuery.addEventListener('change', scheduleMermaidRefresh, signal ? {signal} : undefined);
  }

  documentRoot.querySelectorAll<HTMLButtonElement>('button[data-link-annotation]').forEach(button => {
    const linkName = button.dataset.linkAnnotationTarget?.trim()
      || button.closest<HTMLElement>('.scholium-annotated-link')
        ?.querySelector('.wiki-link')?.textContent?.trim()
      || localized('linked note');
    button.dataset.linkAnnotationTarget = linkName;
    button.setAttribute(
      'aria-label',
      localized('Show Link Annotation for {title}', {title: linkName}),
    );
  });

  let popoverHideTimer: ReturnType<typeof setTimeout> | undefined;
  let activeAnnotationButton: HTMLButtonElement | null = null;
  let activeFootnoteButton: HTMLButtonElement | null = null;
  let pinnedAnnotationButton: HTMLButtonElement | null = null;
  function annotationTarget(button: HTMLButtonElement) {
    return button.dataset.linkAnnotationTarget?.trim() || localized('linked note');
  }
  function setAnnotationExpanded(button: HTMLButtonElement, expanded: boolean) {
    button.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    button.setAttribute(
      'aria-label',
      localized(expanded ? 'Hide Link Annotation for {title}' : 'Show Link Annotation for {title}',
        {title: annotationTarget(button)}),
    );
  }
  function setFootnoteExpanded(button: HTMLButtonElement, expanded: boolean) {
    button.setAttribute('aria-expanded', expanded ? 'true' : 'false');
  }
  function hidePopover() {
    activePreviewAnchor = null;
    previewRevision++;
    nativePreviewHovered = false;
    nativeFloating.preview.hide(nativePreviewID);
    clearTimeout(popoverHideTimer);
    popoverHideTimer = undefined;
    if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
    if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
    activeAnnotationButton = null;
    activeFootnoteButton = null;
    pinnedAnnotationButton = null;
    popover.hidden = true;
    previewTitle.textContent = '';
    previewMetadata.textContent = '';
    previewMetadata.hidden = true;
    previewBody.replaceChildren();
  }

  readerWindow.scholiumDismissPreview = hidePopover;

  function cancelPopoverHide() {
    clearTimeout(popoverHideTimer);
    popoverHideTimer = undefined;
  }

  function schedulePopoverHide() {
    if (nativePreviewHovered) return;
    if (pinnedAnnotationButton) return;
    clearTimeout(popoverHideTimer);
    popoverHideTimer = setTimeout(hidePopover, 180);
  }

  function normalizedPreviewTitle(value: string | null | undefined) {
    return String(value || '').trim().replace(/\s+/g, ' ').toLocaleLowerCase();
  }

  function sanitizeInertContent(container: HTMLElement) {
    sanitizePreviewDocument(container);
    localizeRenderedInterface(container, localized);
    renderMathNodes(container);
  }

  function installInertDocumentContent(container: HTMLElement, preview: ReadLinkPreview) {
    container.innerHTML = preview.htmlBody;
    sanitizeInertContent(container);
    const firstHeading = container.querySelector(':scope > h1:first-child');
    if (firstHeading
        && normalizedPreviewTitle(firstHeading.textContent) === normalizedPreviewTitle(preview.title)) {
      firstHeading.remove();
    }
  }

  function embeddedNoteFor(
    anchor: HTMLAnchorElement,
    preview: ReadLinkPreview,
    key: string,
  ) {
    const shell = document.createElement('section');
    shell.className = 'scholium-embedded-note';
    shell.dataset.scholiumProtected = 'embedded-note';
    shell.dataset.previewRange = key;
    shell.dataset.embedHref = anchor.getAttribute('href') || '';
    shell.dataset.embedLabel = (anchor.textContent || preview.title).trim();
    shell.setAttribute('role', 'group');
    shell.setAttribute(
      'aria-label',
      localized('Embedded note {title}', {title: preview.title})
    );
    for (const name of [
      'data-source-utf16-start', 'data-source-utf16-end',
      'data-source-start-line', 'data-source-end-line', 'data-source-line'
    ]) {
      const value = anchor.getAttribute(name);
      if (value !== null) shell.setAttribute(name, value);
    }

    const header = document.createElement('header');
    header.className = 'scholium-embedded-note-header';
    const open = document.createElement('a');
    open.className = 'wiki-link scholium-embedded-note-open';
    open.dir = 'auto';
    open.href = shell.dataset.embedHref ?? '';
    open.append(document.createTextNode(preview.title));
    open.setAttribute(
      'aria-label',
      localized('Open embedded note {title}', {title: preview.title})
    );
    open.title = localized('Open embedded note {title}', {title: preview.title});
    header.append(open);

    const viewport = document.createElement('div');
    viewport.className = 'scholium-embedded-note-viewport';
    viewport.tabIndex = 0;
    viewport.setAttribute('role', 'region');
    viewport.setAttribute(
      'aria-label',
      localized('Embedded note content for {title}', {title: preview.title})
    );
    const body = document.createElement('div');
    body.className = 'scholium-embedded-note-body scholium-document';
    installInertDocumentContent(body, preview);
    viewport.append(body);
    shell.append(header, viewport);
    return shell;
  }

  function restoreEmbeddedNoteFallback(shell: HTMLElement) {
    const fallback = document.createElement('a');
    fallback.className = 'wiki-link scholium-embed';
    fallback.dir = 'auto';
    fallback.href = shell.dataset.embedHref || '';
    fallback.textContent = shell.dataset.embedLabel || localized('Embedded note');
    fallback.dataset.scholiumProtected = 'embed';
    for (const name of [
      'data-source-utf16-start', 'data-source-utf16-end',
      'data-source-start-line', 'data-source-end-line', 'data-source-line'
    ]) {
      const value = shell.getAttribute(name);
      if (value !== null) fallback.setAttribute(name, value);
    }
    shell.replaceWith(fallback);
  }

  function renderEmbeddedNotes() {
    for (const shell of documentRoot.querySelectorAll<HTMLElement>(
      '.scholium-embedded-note[data-preview-range]',
    )) {
      if (shell.parentElement?.closest('.scholium-embedded-note')) continue;
      const previewRange = shell.dataset.previewRange;
      const preview = previewRange ? previewByRange.get(previewRange) : undefined;
      if (!preview || !preview.isEmbedded) {
        restoreEmbeddedNoteFallback(shell);
        continue;
      }
      const body = shell.querySelector<HTMLElement>('.scholium-embedded-note-body');
      const open = shell.querySelector<HTMLAnchorElement>('.scholium-embedded-note-open');
      if (body) installInertDocumentContent(body, preview);
      if (open) {
        const label = open.firstChild;
        if (label) label.textContent = preview.title;
        open.setAttribute(
          'aria-label',
          localized('Open embedded note {title}', {title: preview.title})
        );
        open.title = localized('Open embedded note {title}', {title: preview.title});
      }
      shell.setAttribute(
        'aria-label',
        localized('Embedded note {title}', {title: preview.title})
      );
    }
    const anchors = [...documentRoot.querySelectorAll<HTMLAnchorElement>('a.scholium-embed')]
      .filter(anchor => !anchor.parentElement?.closest('.scholium-embedded-note'));
    for (const anchor of anchors) {
      const key = anchor.dataset.sourceUtf16Start + ':' + anchor.dataset.sourceUtf16End;
      const preview = previewByRange.get(key);
      if (!preview || !preview.isEmbedded) continue;
      anchor.replaceWith(embeddedNoteFor(anchor, preview, key));
    }
    renderMathNodes();
    const current = readerWindow.scholiumMermaidReady || Promise.resolve();
    readerWindow.scholiumMermaidReady = current.catch(() => {}).then(renderMermaidNodes);
    readerWindow.scholiumReviewImages?.refresh();
  }

  readerWindow.scholiumSetLinkPreviews = (previews) => {
    previewByRange = new Map(previews.map(preview => [
      preview.utf16LowerBound + ':' + preview.utf16UpperBound,
      preview
    ]));
    hidePopover();
    renderEmbeddedNotes();
    return true;
  };

  function positionPopover(anchor: HTMLElement) {
    activePreviewAnchor = anchor;
    const revision = ++previewRevision;
    // Template mathematics uses the same lazy bundled runtime as the document.
    // Preparation may finish after pointer departure or a different target.
    if (!readerWindow.scholiumMath && hasMathNodes(previewBody)) {
      void ensureMathRuntime().then(() => {
        if (!alive() || activePreviewAnchor !== anchor || revision !== previewRevision) return;
        renderMathNodes(previewBody);
        publishPopover(anchor);
      });
      return;
    }
    publishPopover(anchor);
  }
  function publishPopover(anchor: HTMLElement) {
    popover.hidden = false;
    const surface = previewSurface(anchor.getBoundingClientRect(), popover);
    if (host) surface.html = `<div class="scholium-review-projection">${surface.html}</div>`;
    nativePreviewID = nativeFloating.preview.show(surface, {
      dismiss: hidePopover,
      enter: () => { nativePreviewHovered = true; cancelPopoverHide(); },
      leave: () => { nativePreviewHovered = false; schedulePopoverHide(); },
    });
  }

  function showFootnotePopover(button: HTMLElement) {
    const ordinal = button.dataset.footnote;
    if (!ordinal) { hidePopover(); return; }
    const definition = elementByID('fn-' + ordinal);
    const content = definition && definition.querySelector('.footnote-content');
    if (!content) { hidePopover(); return; }
    if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
    if (activeFootnoteButton && activeFootnoteButton !== button) {
      setFootnoteExpanded(activeFootnoteButton, false);
    }
    activeAnnotationButton = null;
    activeFootnoteButton = button as HTMLButtonElement;
    setFootnoteExpanded(activeFootnoteButton, true);
    previewTitle.textContent = localized('Footnote {ordinal}', {ordinal});
    previewMetadata.textContent = '';
    previewMetadata.hidden = true;
    previewBody.replaceChildren(content.cloneNode(true));
    sanitizeInertContent(previewBody);
    positionPopover(button);
  }

  function showLinkPopover(link: HTMLAnchorElement) {
    const key = link.dataset.sourceUtf16Start + ':' + link.dataset.sourceUtf16End;
    const preview = previewByRange.get(key);
    if (!preview) { hidePopover(); return; }
    if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
    if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
    activeAnnotationButton = null;
    activeFootnoteButton = null;
    previewTitle.textContent = preview.title;
    previewMetadata.textContent = preview.fragment || '';
    previewMetadata.hidden = !preview.fragment;
    installInertDocumentContent(previewBody, preview);
    positionPopover(link);
  }

  function showLinkAnnotationPopover(button: HTMLButtonElement) {
    if (activePreviewAnchor === button) return;
    const identifier = button.dataset.linkAnnotation;
    const marker = button.closest<HTMLElement>('.scholium-link-annotation-marker');
    const template = identifier
      ? elementByID(`${identifier}-template`) as HTMLTemplateElement | null
      : marker?.querySelector<HTMLTemplateElement>(':scope > template') ?? null;
    if (!template) { hidePopover(); return; }
    if (activeAnnotationButton && activeAnnotationButton !== button) {
      setAnnotationExpanded(activeAnnotationButton, false);
    }
    if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
    activeAnnotationButton = button;
    activeFootnoteButton = null;
    setAnnotationExpanded(button, true);
    previewTitle.textContent = annotationTarget(button);
    previewMetadata.textContent = localized('Link Annotation');
    previewMetadata.hidden = false;
    previewBody.replaceChildren(template.content.cloneNode(true));
    sanitizeInertContent(previewBody);
    positionPopover(button);
  }

  function previewAnchorFor(target: EventTarget | null): HTMLElement | null {
    if (!(target instanceof Element)) return null;
    if (target.closest('.scholium-embedded-note')) return null;
    return target.closest<HTMLElement>(
      '.scholium-link-annotation-button, .footnote-reference, a.wiki-link',
    );
  }

  function showPreviewFor(anchor: HTMLElement) {
    if (activePreviewAnchor === anchor) return;
    if (anchor.matches('.scholium-link-annotation-button')) {
      showLinkAnnotationPopover(anchor as HTMLButtonElement);
    } else if (anchor.matches('.footnote-reference')) {
      showFootnotePopover(anchor);
    } else if (anchor.matches('a.wiki-link')) {
      showLinkPopover(anchor as HTMLAnchorElement);
    }
  }

  function remainsInsidePreviewAnchor(anchor: Element, relatedTarget: EventTarget | null) {
    return relatedTarget instanceof Node && anchor.contains(relatedTarget);
  }

  listenDocument('pointerover', event => {
    const anchor = previewAnchorFor(event.target);
    if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
    if (pinnedAnnotationButton && anchor !== pinnedAnnotationButton) return;
    cancelPopoverHide();
    showPreviewFor(anchor);
  });
  listenDocument('focusin', event => {
    const anchor = previewAnchorFor(event.target);
    if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
    if (pinnedAnnotationButton && anchor !== pinnedAnnotationButton) return;
    cancelPopoverHide();
    showPreviewFor(anchor);
  });
  listenDocument('pointerout', event => {
    const anchor = previewAnchorFor(event.target);
    if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
    if (event.relatedTarget instanceof Node && popover.contains(event.relatedTarget)) {
      cancelPopoverHide();
    } else {
      schedulePopoverHide();
    }
  });
  listenDocument('focusout', event => {
    const anchor = previewAnchorFor(event.target);
    if (anchor && !remainsInsidePreviewAnchor(anchor, event.relatedTarget)) schedulePopoverHide();
  });
  popover.addEventListener('pointerenter', cancelPopoverHide);
  popover.addEventListener('pointerleave', schedulePopoverHide);
  listenWindow('scroll', hidePopover, {passive: true});
  listenWindow('resize', hidePopover);
  renderEmbeddedNotes();
  cleanups.push(hidePopover);

  listenDocument('click', event => {
    const eventElement = event.target instanceof Element ? event.target : null;
    const annotationButton = eventElement?.closest<HTMLButtonElement>(
      '.scholium-link-annotation-button',
    );
    if (annotationButton) {
      event.preventDefault();
      event.stopPropagation();
      if (pinnedAnnotationButton === annotationButton) {
        hidePopover();
        return;
      }
      pinnedAnnotationButton = annotationButton;
      cancelPopoverHide();
      showLinkAnnotationPopover(annotationButton);
      return;
    }
    if (pinnedAnnotationButton
        && !(event.target instanceof Node && popover.contains(event.target))) hidePopover();
    const reference = eventElement?.closest<HTMLButtonElement>('.footnote-reference');
    if (reference && !reference.disabled) {
      const ordinal = reference.dataset.footnote;
      const targetID = reference.dataset.target;
      const target = targetID ? elementByID(targetID) : null;
      if (target) {
        const origin = reference.closest('.footnote-reference-wrap') || reference;
        origins.set(ordinal, origin.id);
        target.tabIndex = -1;
        target.scrollIntoView({block: 'start', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'});
        target.focus({preventScroll: true});
      }
      hidePopover();
      event.preventDefault();
      return;
    }
    const back = eventElement?.closest<HTMLElement>('.footnote-return');
    if (back) {
      const ordinal = back.dataset.footnote;
      const originID = origins.get(ordinal) || 'fnref-' + ordinal + '-1';
      const origin = elementByID(originID);
      if (origin) {
        const focusTarget = origin.matches('.footnote-reference')
          ? origin
          : origin.querySelector<HTMLElement>('.footnote-reference');
        origin.scrollIntoView({block: 'center', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'});
        (focusTarget || origin).focus({preventScroll: true});
      }
      event.preventDefault();
      return;
    }
    const link = eventElement?.closest<HTMLAnchorElement>('a[href^="scholium-note:"]');
    if (link) {
      const encoded = link.getAttribute('href')?.slice('scholium-note:'.length) ?? '';
      post('internalLink', {target: decodeURIComponent(encoded)});
      event.preventDefault();
    }
  });

  listenDocument('keydown', event => {
    if (event.key === 'Escape') {
      hidePopover();
    }
  });

  readerWindow.scholiumSetReviewSelectionSurfaceActive = active => {
    const nextActive = Boolean(active);
    if (nextActive === reviewSelectionSurfaceActive) return true;
    reviewSelectionSurfaceActive = nextActive;
    reviewPointerSelectionActive = false;
    if (!nextActive) {
      reviewSelectionPresentation.clear();
      post('selectionChanged');
    }
    return true;
  };

  readerWindow.scholiumShowSelectionActions = async () => null;
  if (selectionEnabled) {
    const reviewDocument = documentRoot;
    const reviewMermaidElements = reviewDocument
      ? [...reviewDocument.querySelectorAll('[data-scholium-protected="mermaid"]')]
      : [];
    const isBodySelection = (range: Range) => {
      const frontmatter = reviewDocument?.querySelector('[data-scholium-protected="frontmatter"]');
      return !frontmatter || !range.intersectsNode(frontmatter);
    };
    const selectionActionRange = () => {
      const selection = window.getSelection();
      if (!reviewSelectionSurfaceActive || reviewPointerSelectionActive || !selection || selection.rangeCount !== 1
          || selection.isCollapsed || !reviewDocument) return null;
      const range = selection.getRangeAt(0);
      if (!reviewDocument.contains(range.startContainer) || !reviewDocument.contains(range.endContainer)
          || rangeIntersectsMermaid(range) || !isBodySelection(range)) return null;
      if (range.toString().length > 32_000) return null;
      const text = boundedReviewRangeText(range, reviewDocument, 32_000);
      if (!text) return null;
      const utf16Count = text.length;
      return {range, utf16Count};
    };
    const selectionNodeIDs = new WeakMap<Node, number>();
    let nextSelectionNodeID = 0;
    const selectionNodeID = (node: Node) => {
      let id = selectionNodeIDs.get(node);
      if (id === undefined) { id = ++nextSelectionNodeID; selectionNodeIDs.set(node, id); }
      return id;
    };
    const selectionActionKey = (selected = selectionActionRange()) => selected
      ? `${fingerprint}:${selectionNodeID(selected.range.startContainer)}:${selected.range.startOffset}:${selectionNodeID(selected.range.endContainer)}:${selected.range.endOffset}`
      : null;
    const selectionActions = createSelectionActions(nativeFloating.selection, () => {
      const selected = selectionActionRange();
      if (!selected) return null;
      const {range, utf16Count} = selected;
      const rect = range.getBoundingClientRect();
      if (outsideViewport(rect)) return null;
      return {key: selectionActionKey(selected)!,
        utf16Count,
        anchor: {left: rect.left + rect.width / 2, top: rect.top, bottom: rect.bottom}};
    }, selectionActionKey);
    cleanups.push(() => selectionActions.dismiss());
    let revealedSelectionScroll: {top: number; left: number} | null = null;
    listenWindow('scroll', () => {
      if (revealedSelectionScroll?.top === scrollTop() && revealedSelectionScroll.left === scrollLeft()) return;
      revealedSelectionScroll = null;
      selectionActions.dismissForScroll();
    }, {passive: true});
    for (const event of ['wheel', 'touchstart', 'pointerdown']) {
      listenWindow(event, () => {
        revealedSelectionScroll = null;
        selectionActions.dismiss();
      }, {capture: true, passive: true});
    }
    listenDocument('keydown', event => {
      const dismissed = selectionActions.dismissForKey(event);
      if (event.key === 'Escape' && !event.isComposing && dismissed) {
        event.preventDefault(); event.stopPropagation();
      }
    }, true);
    let passageSelection: Record<string, unknown> | null = null;
    const clearReviewSelection = () => {
      passageSelection = null;
      selectionActions.update();
      post('selectionChanged');
    };
    const nodeBelongsToMermaid = (node: Node) => {
      const element = node instanceof Element ? node : node.parentElement;
      if (element?.closest?.('[data-scholium-protected="mermaid"]')) return true;
      const root = node.getRootNode();
      const shadowHost = root instanceof ShadowRoot ? root.host : null;
      return Boolean(shadowHost?.closest?.('[data-scholium-protected="mermaid"]'));
    };
    const rangeIntersectsMermaid = (range: Range) => {
      if (nodeBelongsToMermaid(range.startContainer)
          || nodeBelongsToMermaid(range.endContainer)) return true;
      return reviewMermaidElements.some(element => {
        try {
          return range.intersectsNode(element);
        } catch (_) {
          return false;
        }
      });
    };
    const updateReviewSelection = () => {
      if (!reviewSelectionSurfaceActive) return;
      const selection = window.getSelection();
      const main = reviewDocument;
      reviewSelectionPresentation.update(selection, main);
      if (reviewPointerSelectionActive) return;
      if (!selection || selection.rangeCount !== 1 || selection.isCollapsed || !main) {
        clearReviewSelection();
        return;
      }
      const range = selection.getRangeAt(0);
      if (!main.contains(range.startContainer) || !main.contains(range.endContainer)) {
        clearReviewSelection();
        return;
      }
      if (rangeIntersectsMermaid(range) || !isBodySelection(range) || range.toString().length > 32_000) {
        clearReviewSelection();
        return;
      }
      const text = boundedReviewRangeText(range, main, 32_000);
      if (!text) {
        clearReviewSelection();
        return;
      }
      const sourceElement = (range.startContainer instanceof Element
        ? range.startContainer
        : range.startContainer.parentElement)?.closest<HTMLElement>('[data-source-line]') ?? null;
      const endSourceElement = (range.endContainer instanceof Element
        ? range.endContainer
        : range.endContainer.parentElement)?.closest<HTMLElement>('[data-source-line]') ?? null;
      const startLine = Number(sourceElement ? sourceElement.dataset.sourceLine : '1');
      const endLine = Number(endSourceElement
        ? (endSourceElement.dataset.sourceEndLine || endSourceElement.dataset.sourceLine)
        : String(startLine));
      const common = range.commonAncestorContainer;
      const block = (common instanceof Element ? common : common.parentElement)
        ?.closest<HTMLElement>('[data-source-utf16-start][data-source-utf16-end]');
      const beforeRange = document.createRange();
      let sourceMapping: Record<string, unknown> = {};
      if (block && block.textContent && block.textContent.length <= 64000) {
        beforeRange.selectNodeContents(block);
        beforeRange.setEnd(range.startContainer, range.startOffset);
        const selectionLower = beforeRange.toString().length;
        sourceMapping = {blockLower: Number(block.dataset.sourceUtf16Start),
          blockUpper: Number(block.dataset.sourceUtf16End), blockText: block.textContent,
          selectionLower, selectionUpper: selectionLower + range.toString().length};
      }
      const payload = {
        ...sourceMapping,
        text,
        contextBefore: reviewContextBefore(range, main, 80),
        contextAfter: reviewContextAfter(range, main, 80),
        startLine: Math.min(startLine, endLine),
        endLine: Math.max(startLine, endLine)
      };
      passageSelection = payload;
      post('selectionChanged', payload);
      selectionActions.update();
    };
    const showSelectionActions = async () => {
      const presentationRevision = selectionActions.presentationRevision;
      const selected = selectionActionRange();
      if (!selected) { selectionActions.presentCurrent(null); return null; }
      const expectedKey = selectionActionKey(selected);
      const range = selected.range.cloneRange();
      const rect = range.getBoundingClientRect();
      if (outsideViewport(rect)) {
        const target = range.endContainer instanceof Element ? range.endContainer : range.endContainer.parentElement;
        target?.scrollIntoView({block: "center", behavior: "auto"});
        // DOM geometry completes the synchronous reveal. A delayed scroll
        // notification describes this same completed presentation, so retain
        // it until user input or a different viewport supersedes it.
        range.getBoundingClientRect();
        revealedSelectionScroll = {top: scrollTop(), left: scrollLeft()};
      }
      // Publish the current checked-selection projection before presenting its
      // toolbar. The native source owner still validates any later inquiry.
      if (selectionActions.presentationRevision !== presentationRevision
          || readerWindow.scholiumShowSelectionActions !== showSelectionActions
          || selectionActionKey() !== expectedKey) return null;
      updateReviewSelection();
      if (selectionActions.presentationRevision !== presentationRevision) return null;
      return selectionActions.presentCurrent() ? selectionActions.surfaceID : null;
    };
    readerWindow.scholiumShowSelectionActions = showSelectionActions;
    reviewDocument?.addEventListener('contextmenu', event => {
      if (!reviewSelectionSurfaceActive) return;
      const target = event.target instanceof Element ? event.target : null;
      if (!target || target.closest('a, img, table, pre, .scholium-embedded-note, [data-scholium-protected]')) return;
      const paragraph = target.closest<HTMLElement>('p[data-source-utf16-start][data-source-utf16-end]');
      if (!paragraph) return;
      const selection = window.getSelection();
      const range = selection?.rangeCount === 1 && !selection.isCollapsed ? selection.getRangeAt(0) : null;
      const inSelection = range && ((event.button === 0 && event.detail === 0) || [...range.getClientRects()].some(rect =>
        event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom));
      if (!inSelection) {
        const selectedParagraph = document.createRange();
        selectedParagraph.selectNodeContents(paragraph);
        selection?.removeAllRanges();
        selection?.addRange(selectedParagraph);
      }
      updateReviewSelection();
      event.preventDefault();
      selectionActions.dismiss();
      post('passageContextMenu', {
        clientX: event.clientX, clientY: event.clientY,
        selection: inSelection ? passageSelection : null,
        paragraphLower: Number(paragraph.dataset.sourceUtf16Start),
        paragraphUpper: Number(paragraph.dataset.sourceUtf16End),
      });
    });
    listenDocument('selectionchange', updateReviewSelection);
    reviewDocument?.addEventListener('pointerdown', event => {
      if (!reviewSelectionSurfaceActive || event.button !== 0) return;
      reviewPointerSelectionActive = true;
    }, true);
    listenWindow('pointerup', event => {
      if (!reviewPointerSelectionActive || event.button !== 0) return;
      reviewPointerSelectionActive = false;
      queueMicrotask(updateReviewSelection);
    }, true);
    listenWindow('pointercancel', () => {
      reviewPointerSelectionActive = false;
    }, true);
    listenWindow('blur', () => {
      reviewPointerSelectionActive = false;
    });
  }

  const scrollBlockRegistry = (() => {
    const recordMetric = host?.recordMetric;
    const startedAt = recordMetric ? performance.now() : 0;
    const root = documentRoot;
    const entries: ReaderScrollEntry[] = [];
    const byElement = new WeakMap<HTMLElement, ReaderScrollEntry>();
    const byExactRange = new Map<string, ReaderScrollEntry>();
    if (!root) return {
      root,
      entries,
      byElement,
      byExactRange,
      bySource: [],
      sourcePrefixMaximumUpper: []
    };
    const candidates = root.querySelectorAll<HTMLElement>(
      '[data-source-utf16-start][data-source-utf16-end]',
    );
    let styleReadCount = 0;
    let measureCount = 0;
    for (const element of candidates) {
      const lower = Number(element.dataset.sourceUtf16Start);
      const upper = Number(element.dataset.sourceUtf16End);
      if (!Number.isFinite(lower) || !Number.isFinite(upper) || upper < lower) continue;
      const style = getComputedStyle(element);
      styleReadCount++;
      if (style.display === 'inline' || style.display === 'contents'
          || style.display === 'none' || style.visibility === 'hidden') continue;
      const initialRect = element.getBoundingClientRect();
      measureCount++;
      if (initialRect.height <= 0) continue;
      const entry = {element, lower, upper, span: Math.max(0, upper - lower)};
      element.dataset.scholiumScrollAnchor = String(entries.length);
      entries.push(entry);
      byElement.set(element, entry);
      const key = lower + ':' + upper;
      const existing = byExactRange.get(key);
      if (!existing || entry.span < existing.span) byExactRange.set(key, entry);
    }
    const bySource = entries.slice().sort((left, right) =>
      left.lower - right.lower || left.span - right.span);
    let maximumUpper = Number.NEGATIVE_INFINITY;
    const sourcePrefixMaximumUpper = bySource.map(entry => {
      maximumUpper = Math.max(maximumUpper, entry.upper);
      return maximumUpper;
    });
    recordMetric?.("review-scroll-registry", startedAt, {review: 1,
      candidateCount: candidates.length, registeredBlockCount: entries.length, styleReadCount, measureCount});
    return {
      root,
      entries,
      byElement,
      byExactRange,
      bySource,
      sourcePrefixMaximumUpper
    };
  })();
  let lastScrollEntry: ReaderScrollEntry | null = null;

  function scrollEntryForNode(node: Node | null | undefined): ReaderScrollEntry | null {
    const root = scrollBlockRegistry.root;
    let element: HTMLElement | null = node instanceof HTMLElement
      ? node
      : node?.parentElement ?? null;
    while (element && element !== root) {
      const entry = scrollBlockRegistry.byElement.get(element);
      if (entry) return entry;
      element = element.parentElement;
    }
    return null;
  }

  function scrollEntryAtProbe(probe: number): ReaderScrollEntry | null {
    const registry = scrollBlockRegistry;
    if (!registry.root || !registry.entries.length) return null;
    if (lastScrollEntry) {
      const cachedRect = lastScrollEntry.element.getBoundingClientRect();
      if (cachedRect.height > 0 && probe >= cachedRect.top && probe < cachedRect.bottom) {
        return lastScrollEntry;
      }
    }
    const rootRect = registry.root.getBoundingClientRect();
    const probeX = Math.max(1, Math.min(window.innerWidth - 1,
      rootRect.left + Math.max(1, rootRect.width / 2)));
    let entry = scrollEntryForNode(document.elementFromPoint(probeX, probe));
    if (!entry && document.caretPositionFromPoint) {
      entry = scrollEntryForNode(document.caretPositionFromPoint(probeX, probe)?.offsetNode);
    }
    if (!entry && document.caretRangeFromPoint) {
      entry = scrollEntryForNode(document.caretRangeFromPoint(probeX, probe)?.startContainer);
    }
    if (entry) {
      lastScrollEntry = entry;
      return entry;
    }

    // Margins can leave the probe over the document background.
    // A logarithmic fallback reads only a bounded set of blocks.
    let low = 0;
    let high = registry.entries.length - 1;
    let nearestIndex = 0;
    let nearestDistance = Number.POSITIVE_INFINITY;
    while (low <= high) {
      const index = (low + high) >> 1;
      const candidate = registry.entries[index];
      const rect = candidate.element.getBoundingClientRect();
      const distance = rect.top <= probe && rect.bottom > probe
        ? 0
        : Math.min(Math.abs(rect.top - probe), Math.abs(rect.bottom - probe));
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
      if (rect.bottom <= probe) low = index + 1;
      else if (rect.top > probe) high = index - 1;
      else {
        lastScrollEntry = candidate;
        return candidate;
      }
    }
    const start = Math.max(0, nearestIndex - 2);
    const end = Math.min(registry.entries.length, nearestIndex + 3);
    let nearest = registry.entries[nearestIndex];
    for (let index = start; index < end; index += 1) {
      const candidate = registry.entries[index];
      const rect = candidate.element.getBoundingClientRect();
      const distance = rect.top <= probe && rect.bottom > probe
        ? 0
        : Math.min(Math.abs(rect.top - probe), Math.abs(rect.bottom - probe));
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = candidate;
      }
    }
    lastScrollEntry = nearest;
    return nearest;
  }

  function scrollEntryForAnchor(anchor: ReaderScrollAnchor): ReaderScrollEntry | null {
    const offset = Number(anchor.sourceUTF16Offset);
    const lower = Number(anchor.blockUTF16LowerBound);
    const upper = Number(anchor.blockUTF16UpperBound);
    const exact = scrollBlockRegistry.byExactRange.get(lower + ':' + upper);
    if (exact) return exact;
    const entries = scrollBlockRegistry.bySource;
    let low = 0;
    let high = entries.length;
    while (low < high) {
      const middle = (low + high) >> 1;
      if (entries[middle].lower <= offset) low = middle + 1;
      else high = middle;
    }
    const insertion = low;
    let containing: ReaderScrollEntry | null = null;
    for (let index = insertion - 1;
         index >= 0 && scrollBlockRegistry.sourcePrefixMaximumUpper[index] >= offset;
         index -= 1) {
      const candidate = entries[index];
      if (candidate.lower <= offset && candidate.upper >= offset
          && (!containing || candidate.span < containing.span)) containing = candidate;
    }
    if (containing) return containing;
    const before = entries[Math.max(0, insertion - 1)];
    const after = entries[Math.min(entries.length - 1, insertion)];
    if (!before) return after || null;
    if (!after) return before;
    return Math.abs(before.lower - offset) <= Math.abs(after.lower - offset) ? before : after;
  }

  function visibleScrollEntry(entry: ReaderScrollEntry | null): ReaderScrollEntry | null {
    let candidate = entry;
    while (candidate) {
      if (candidate.element.getBoundingClientRect().height > 0) return candidate;
      let parent = candidate.element.parentElement;
      candidate = null;
      while (parent && parent !== scrollBlockRegistry.root) {
        const registered = scrollBlockRegistry.byElement.get(parent);
        if (registered) {
          candidate = registered;
          break;
        }
        parent = parent.parentElement;
      }
    }
    return null;
  }

  function currentReadScrollAnchor(fraction: number): ReaderScrollAnchor | null {
    const probe = viewportTop() + 8;
    const selected = scrollEntryAtProbe(probe);
    if (!selected) return null;
    const rect = selected.element.getBoundingClientRect();
    const relativeBlockPosition = Math.max(0, Math.min(1,
      (probe - rect.top) / Math.max(1, rect.height)));
    const sourceUTF16Offset = Math.max(selected.lower, Math.min(selected.upper,
      Math.round(selected.lower + selected.span * relativeBlockPosition)));
    return {
      sourceUTF16Offset,
      blockUTF16LowerBound: selected.lower,
      blockUTF16UpperBound: selected.upper,
      relativeBlockPosition,
      fallbackFraction: fraction
    };
  }

  function restoreReadScrollAnchor(anchor: ReaderScrollAnchor) {
    if (!anchor || typeof anchor !== 'object') return false;
    const offset = Number(anchor.sourceUTF16Offset);
    const lower = Number(anchor.blockUTF16LowerBound);
    const upper = Number(anchor.blockUTF16UpperBound);
    const relative = Number(anchor.relativeBlockPosition);
    if (![offset, lower, upper, relative].every(Number.isFinite)) return false;
    // A restore is an explicit native handoff. Allow its next scroll event to
    // publish even when it lands on the same source anchor as the prior view.
    lastPostedScroll = null;
    const fallback = Number(anchor.fallbackFraction);
    if (Number.isFinite(fallback) && fallback <= 0) {
      scrollTo({top: 0, behavior: 'auto'});
      return true;
    }
    const target = visibleScrollEntry(scrollEntryForAnchor(anchor));
    if (!target) return false;
    lastScrollEntry = target;
    const rect = target.element.getBoundingClientRect();
    const height = Math.max(1, rect.height);
    const requestedOffset = Math.max(0, Math.min(1, relative)) * height;
    // WebKit can resolve a one-pixel boundary to the preceding
    // block after fractional layout or font substitution. Keep
    // the probe four CSS pixels inside the requested block so a
    // restore-generated scroll report resolves to that block.
    const interiorOffset = height > 8
      ? Math.max(4, Math.min(height - 4, requestedOffset))
      : requestedOffset;
    const requestedTop = scrollTop() + rect.top
      + interiorOffset - viewportTop() - 8;
    scrollTo({top: Math.max(0, requestedTop), behavior: 'auto'});
    return true;
  }

  readerWindow.scholiumReadScroll = {
    restoreCount: 0,
    fraction() { const extent = Math.max(0, scrollHeight() - viewportHeight()); return extent > 0 ? Math.max(0, Math.min(1, scrollTop() / extent)) : 0; },
    setFraction(fraction) { scrollTo({top: Math.max(0, Math.min(1, fraction)) * Math.max(0, scrollHeight() - viewportHeight()), behavior: 'auto'}); },
    recordRestoreAttempt() {
      this.restoreCount += 1;
    },
    testingSnapshot() {
      let previousTop = Number.NEGATIVE_INFINITY;
      let visualOrderIsMonotonic = true;
      for (const entry of scrollBlockRegistry.entries) {
        const top = entry.element.getBoundingClientRect().top;
        if (top + 1 < previousTop) visualOrderIsMonotonic = false;
        previousTop = Math.max(previousTop, top);
      }
      return {
        registryCount: scrollBlockRegistry.entries.length,
        visualOrderIsMonotonic,
      };
    },
    current(fraction) { return currentReadScrollAnchor(fraction); },
    restore(anchor) {
      return restoreReadScrollAnchor(anchor);
    }
  };

  const scrollReports = new AnimationFrameCoalescer(
    (callback) => window.requestAnimationFrame(callback),
    (identifier) => window.cancelAnimationFrame(identifier),
    (callback, delay) => window.setTimeout(callback, delay),
    (identifier) => window.clearTimeout(identifier),
  );
  cleanups.push(() => scrollReports.cancel());
  let lastPostedScroll: {
    fraction: number;
    anchor: ReaderScrollAnchor | null;
  } | null = null;
  const sameAnchor = (left: ReaderScrollAnchor | null, right: ReaderScrollAnchor | null) =>
    left === right || Boolean(left && right
      && left.sourceUTF16Offset === right.sourceUTF16Offset
      && left.blockUTF16LowerBound === right.blockUTF16LowerBound
      && left.blockUTF16UpperBound === right.blockUTF16UpperBound
      && left.relativeBlockPosition === right.relativeBlockPosition
      && left.fallbackFraction === right.fallbackFraction);
  const postCurrentScroll = () => {
    const extent = Math.max(0, scrollHeight() - viewportHeight());
    const fraction = extent > 0 ? Math.max(0, Math.min(1, scrollTop() / extent)) : 0;
    const anchor = currentReadScrollAnchor(fraction);
    if (lastPostedScroll
        && lastPostedScroll.fraction === fraction
        && sameAnchor(lastPostedScroll.anchor, anchor)) return;
    lastPostedScroll = {fraction, anchor};
    post('scrollChanged', {fraction, anchor});
  };
  listenWindow('scroll', () => {
    scrollReports.schedule(postCurrentScroll);
  }, {passive: true});
  // Install only after the rendered document and its event
  // handlers exist. The native side also probes this API from
  // didFinish, so a dropped early message cannot lose a query.
}
