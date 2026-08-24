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

interface ReaderMessageHandler {
  postMessage(message: Record<string, unknown>): void;
}

interface ReaderScrollAnchor {
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

type ReaderWindow = Window & {
  webkit?: {messageHandlers?: {scholiumRead?: ReaderMessageHandler}};
  scholiumReadReady?: Promise<void>;
  scholiumRead?: {initialize(value: unknown): Promise<void>};
  scholiumReviewFind?: {perform(request: ReviewFindRequest): ReviewFindResult};
  scholiumReviewSelection?: ReturnType<typeof createReviewSelectionPresentation>;
  scholiumMermaidReady?: Promise<void>;
  scholiumSetLinkPreviews?: (previews: ReadLinkPreview[]) => void;
  scholiumShowCommentComposer?: () => boolean;
  scholiumSetReviewSelectionSurfaceActive?: (active: boolean) => boolean;
  scholiumResolveCommentSubmission?: (requestID: string, succeeded: boolean) => boolean;
  scholiumReadScroll?: {
    restoreCount: number;
    recordRestoreAttempt(): void;
    current(fraction: number): ReaderScrollAnchor | null;
    restore(anchor: ReaderScrollAnchor): boolean;
    testingSnapshot(): Record<string, unknown>;
  };
};

const readerWindow = window as ReaderWindow;

function requiredElement<ElementType extends HTMLElement>(id: string): ElementType {
  const element = document.getElementById(id);
  if (!(element instanceof HTMLElement)) throw new Error(`Missing reader element: ${id}`);
  return element as ElementType;
}

async function initializeReader(value: unknown): Promise<void> {
  const config = validatedReaderConfiguration(value);
  if (!config) throw new Error("Invalid reader configuration.");
  const {
    version, documentID, fingerprint, loadGeneration, commentEnabled,
    selectionEnabled, presentationCSS, userCSS, localization, linkPreviews,
    vectorSymbols, testingEnabled,
  } = config;
  const presentationStyle = requiredElement<HTMLStyleElement>('scholium-presentation-css');
  const userStyle = requiredElement<HTMLStyleElement>('scholium-user-css');
  presentationStyle.textContent = presentationCSS;
  userStyle.textContent = userCSS;
  const strings = localization.strings || {};
  const localized = (key: string, replacements: Record<string, unknown> = {}) =>
    String(strings[key] || key).replace(
      /\{([A-Za-z]+)\}/g,
      (placeholder, name: string) => Object.prototype.hasOwnProperty.call(replacements, name)
        ? String(replacements[name])
        : placeholder,
    );
  const handler = readerWindow.webkit?.messageHandlers?.scholiumRead;
  const post = (type: string, extra: Record<string, unknown> = {}) => handler?.postMessage({
    version, documentID, fingerprint, loadGeneration, type, ...extra,
  });
  const popover = requiredElement('scholium-preview-popover');
  const previewTitle = popover.querySelector<HTMLElement>('.scholium-preview-title')!;
  const previewMetadata = popover.querySelector<HTMLElement>('.scholium-preview-metadata')!;
  const previewBody = popover.querySelector<HTMLElement>('.scholium-preview-body')!;
  const selectionActions = requiredElement('selection-actions');
  const selectionToolbar = requiredElement('selection-toolbar');
  const commentButton = requiredElement<HTMLButtonElement>('comment-selection');
  const commentComposer = requiredElement('comment-composer');
  const commentText = requiredElement<HTMLTextAreaElement>('comment-text');
  const commentHelp = requiredElement('comment-help');
  const qaCommentSubmit = document.getElementById('qa-submit-comment');
  const defaultCommentHelpText = localized('Return saves · Shift-Return adds a line · Escape cancels');
  selectionToolbar.setAttribute('aria-label', localized('Selection actions'));
  const selectionLabel = commentButton.querySelector<HTMLElement>('.scholium-selection-label');
  if (!selectionLabel) throw new Error("Missing reader selection label.");
  selectionLabel.textContent = localized('Comment');
  commentText.placeholder = localized('Comment');
  commentText.setAttribute('aria-label', localized('Comment'));
  commentHelp.textContent = defaultCommentHelpText;
  if (qaCommentSubmit) qaCommentSubmit.textContent = localized('Submit Comment for QA');
  const viewportRoot = document.documentElement;
  const viewportResizeScrollBarClass = 'scholium-viewport-resize-suppresses-overlay-scrollbar';
  const viewportResizeSettleDelay = 80;
  // A fixed viewport-unit probe distinguishes a real WKWebView
  // resize from the resize that WebKit reports when scrollbar
  // presentation changes. Animation frames are not a reliable
  // settling signal while an offscreen WebView is suspended.
  const viewportGeometryProbe = document.createElement('span');
  viewportGeometryProbe.setAttribute('aria-hidden', 'true');
  viewportGeometryProbe.style.cssText = 'position:fixed;inline-size:100vw;block-size:100vh;visibility:hidden;pointer-events:none';
  document.body.append(viewportGeometryProbe);
  const viewportGeometry = () => viewportGeometryProbe.getBoundingClientRect();
  let viewportResizeGeneration = 0;
  let viewportResizeTimer: ReturnType<typeof setTimeout> | undefined;
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
        setTimeout(() => {
          viewportBounds = viewportGeometry();
          window.addEventListener('resize', viewportDidResize);
        }, 0);
      }
    }, viewportResizeSettleDelay);
  };
  window.addEventListener('resize', viewportDidResize);
  const synchronizeSelectionKeyboardFocus = (target: EventTarget | null) => {
    commentButton.classList.toggle(
      'scholium-selection-keyboard-focus',
      target === commentButton
    );
  };
  selectionActions.addEventListener('focusin', event => {
    synchronizeSelectionKeyboardFocus(event.target);
  });
  selectionActions.addEventListener('focusout', () => {
    queueMicrotask(() => synchronizeSelectionKeyboardFocus(document.activeElement));
  });
  const resizeCommentText = () => {
    commentText.style.height = 'auto';
    commentText.style.height = Math.min(
      Math.max(commentText.scrollHeight, 64),
      132
    ) + 'px';
    if (!commentComposer.hidden && commentSelectionRange) {
      positionSelectionActions(commentSelectionRange.getBoundingClientRect());
    }
  };
  readerWindow.scholiumReviewFind = installReviewFind();
  const reviewSelectionPresentation = createReviewSelectionPresentation(
    selectionEnabled,
    testingEnabled,
  );
  readerWindow.scholiumReviewSelection = reviewSelectionPresentation;
  let pendingCommentRequestID: string | null = null;
  let commentAnchorElement: HTMLElement | null = null;
  let commentSelectionRange: Range | null = null;
  let reviewPointerSelectionActive = false;
  let reviewSelectionSurfaceActive = true;
  let suspendedCommentComposer = false;
  const positionSelectionActions = (anchorBounds: DOMRect) => {
    selectionActions.hidden = false;
    const bounds = selectionActions.getBoundingClientRect();
    const viewportInset = 12;
    const verticalInset = 8;
    const gap = 6;
    const centeredLeft = anchorBounds.left
      + (anchorBounds.width - bounds.width) / 2;
    const aboveTop = anchorBounds.top - bounds.height - gap;
    const belowTop = anchorBounds.bottom + gap;
    const preferredTop = aboveTop >= verticalInset ? aboveTop : belowTop;
    selectionActions.style.left = window.scrollX + Math.max(
      viewportInset,
      Math.min(centeredLeft, window.innerWidth - bounds.width - viewportInset)
    ) + 'px';
    selectionActions.style.top = window.scrollY + Math.max(
      verticalInset,
      Math.min(preferredTop, window.innerHeight - bounds.height - verticalInset)
    ) + 'px';
  };
  let previewByRange = new Map(linkPreviews.map(preview => [
    preview.utf16LowerBound + ':' + preview.utf16UpperBound,
    preview
  ]));
  const origins = new Map();
  const vectorSemantics = {
    neutral: {label: localized('Related note'), symbolName: 'link', symbol: vectorSymbols.neutral ?? ''},
    supports: {label: localized('Supports'), symbolName: 'plus', symbol: vectorSymbols.supports ?? ''},
    opposes: {label: localized('Opposes'), symbolName: 'minus', symbol: vectorSymbols.opposes ?? ''},
    incompatible: {label: localized('Incompatible'), symbolName: 'xmark', symbol: vectorSymbols.incompatible ?? ''}
  };

  function renderMathNodes() {
    const runtime = readerWindow.scholiumMath;
    if (!runtime || runtime.version !== 1) return;
    document.querySelectorAll<HTMLElement>('.scholium-math[data-math-source][data-math-kind]').forEach(element => {
      try {
        const encodedSource = element.dataset.mathSource;
        const kind = element.dataset.mathKind;
        if (!encodedSource || (kind !== 'inline' && kind !== 'display')) return;
        const source = new TextDecoder().decode(
          Uint8Array.from(atob(encodedSource), character => character.charCodeAt(0))
        );
        const result = runtime.render({source, kind});
        if (!result.ok) {
          element.classList.add('scholium-math-error');
          element.setAttribute(
            'aria-label',
            localized('Mathematics could not be rendered. Source is shown.')
          );
          return;
        }
        const fallback = element.querySelector('.scholium-math-source');
        const rendered = document.createElement('span');
        rendered.className = 'scholium-math-output';
        rendered.innerHTML = result.html;
        fallback && fallback.before(rendered);
        element.classList.add('scholium-math-rendered');
      } catch (_) {
        element.classList.add('scholium-math-error');
      }
    });
  }
  renderMathNodes();

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
    if (current?.version === 2) return Promise.resolve(current);
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
        if (loaded?.version !== 2) mermaidRuntimePromise = null;
        resolve(loaded?.version === 2 ? loaded : null);
      };
      const timeout = setTimeout(finish, 8000);
      readerWindow.scholiumMermaidRuntimeDidLoad = finish;
      post('requestMermaidRuntime');
    });
    return mermaidRuntimePromise;
  }

  async function renderMermaidWrapper(wrapper: HTMLElement, source: string) {
    for (const child of [...wrapper.children]) {
      if (child.classList.contains('scholium-mermaid-output')
          || child.classList.contains('scholium-mermaid-diagnostic')
          || child.classList.contains('scholium-mermaid-accessible-source')) {
        child.remove();
      }
    }
    wrapper.classList.remove('scholium-mermaid-rendered', 'scholium-mermaid-error');
    const runtime = await ensureMermaidRuntime();
    if (!runtime) {
      wrapper.classList.add('scholium-mermaid-error');
      mermaidDiagnostic(
        wrapper,
        localized('Diagram rendering is unavailable. Mermaid source is shown.')
      );
      return;
    }
    try {
      const result = await runtime.render({source, themeRoot: document.documentElement});
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
    const nodes = [...document.querySelectorAll('pre > code')]
      .filter(code => isMermaidCode(code) && !code.closest('.scholium-mermaid'));
    for (const code of nodes) {
      const original = code.parentElement;
      if (!original) continue;
      const source = code.textContent || '';
      const wrapper = document.createElement('figure');
      wrapper.className = 'scholium-mermaid';
      wrapper.dataset.scholiumProtected = 'mermaid';
      for (const name of ['data-source-utf16-start', 'data-source-utf16-end', 'data-source-start-line', 'data-source-end-line']) {
        const value = original.getAttribute(name);
        if (value !== null) wrapper.setAttribute(name, value);
      }
      const fallback = original.cloneNode(true) as HTMLElement;
      fallback.classList.add('scholium-mermaid-source');
      wrapper.append(fallback);
      original.replaceWith(wrapper);
      await renderMermaidWrapper(wrapper, source);
    }
  }

  async function refreshMermaidNodes() {
    for (const wrapper of document.querySelectorAll<HTMLElement>('.scholium-mermaid')) {
      const source = wrapper.querySelector('.scholium-mermaid-source > code')?.textContent || '';
      await renderMermaidWrapper(wrapper, source);
    }
  }

  function scheduleMermaidRefresh() {
    const current = readerWindow.scholiumMermaidReady || Promise.resolve();
    readerWindow.scholiumMermaidReady = current.catch(() => {}).then(refreshMermaidNodes);
  }
  readerWindow.scholiumMermaidReady = renderMermaidNodes();
  await readerWindow.scholiumMermaidReady;
  for (const mediaQuery of [
    matchMedia('(prefers-color-scheme: dark)'),
    matchMedia('(prefers-contrast: more)')
  ]) {
    mediaQuery.addEventListener('change', scheduleMermaidRefresh);
  }

  document.querySelectorAll<HTMLAnchorElement>('a.wiki-link[data-vector-kind]').forEach(link => {
    const kind = link.dataset.vectorKind;
    const semantics = kind
      ? vectorSemantics[kind as keyof typeof vectorSemantics]
      : undefined;
    if (!kind || !semantics) return;
    const noteName = (link.textContent || '').trim();
    link.classList.add('scholium-vector-link', 'scholium-vector-' + kind.replaceAll('_', '-'));
    link.dataset.scholiumProtected = 'vector-link';
    link.setAttribute('aria-label', semantics.label + ' ' + noteName);
    link.title = semantics.label + ' ' + noteName;
    const icon = document.createElement('span');
    icon.className = 'scholium-vector-icon';
    icon.setAttribute('aria-hidden', 'true');
    icon.dataset.scholiumSystemSymbol = semantics.symbolName;
    icon.style.webkitMaskImage = `url("${semantics.symbol}")`;
    icon.style.maskImage = `url("${semantics.symbol}")`;
    link.append(icon);
  });

  let popoverHideTimer: ReturnType<typeof setTimeout> | undefined;
  function hidePopover() {
    clearTimeout(popoverHideTimer);
    popoverHideTimer = undefined;
    popover.hidden = true;
    previewTitle.textContent = '';
    previewMetadata.textContent = '';
    previewMetadata.hidden = true;
    previewBody.replaceChildren();
  }

  function cancelPopoverHide() {
    clearTimeout(popoverHideTimer);
    popoverHideTimer = undefined;
  }

  function schedulePopoverHide() {
    clearTimeout(popoverHideTimer);
    popoverHideTimer = setTimeout(hidePopover, 180);
  }

  function normalizedPreviewTitle(value: string | null | undefined) {
    return String(value || '').trim().replace(/\s+/g, ' ').toLocaleLowerCase();
  }

  function sanitizeInertContent(container: HTMLElement) {
    container.querySelectorAll('script, style, iframe, object, embed, form, input, button').forEach(node => node.remove());
    container.querySelectorAll<HTMLElement>('*').forEach(node => {
      Array.from(node.attributes).forEach(attribute => {
        if (attribute.name.toLowerCase().startsWith('on')) node.removeAttribute(attribute.name);
        if (attribute.name.toLowerCase().startsWith('data-source-')) {
          node.removeAttribute(attribute.name);
        }
      });
      node.removeAttribute('href');
      node.removeAttribute('contenteditable');
      node.removeAttribute('id');
      node.removeAttribute('for');
      node.removeAttribute('aria-describedby');
      node.removeAttribute('aria-labelledby');
      node.removeAttribute('aria-owns');
      node.tabIndex = -1;
    });
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
    open.className = 'wiki-link scholium-vector-link scholium-vector-neutral scholium-embedded-note-open';
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
    const documentRoot = document.getElementById('scholium-document');
    if (!documentRoot) return;
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

  function positionPopover(anchor: Element) {
    popover.hidden = false;
    const rect = anchor.getBoundingClientRect();
    const measured = popover.getBoundingClientRect();
    const left = Math.max(12, Math.min(rect.left, window.innerWidth - measured.width - 12));
    const below = rect.bottom + 8;
    const top = below + measured.height <= window.innerHeight - 12
      ? below
      : Math.max(12, rect.top - measured.height - 8);
    popover.style.left = left + 'px';
    popover.style.top = top + 'px';
  }

  function showFootnotePopover(button: HTMLElement) {
    const ordinal = button.dataset.footnote;
    const definition = document.getElementById('fn-' + ordinal);
    const content = definition && definition.querySelector('.footnote-content');
    if (!content) return;
    previewTitle.textContent = localized('Footnote {ordinal}', {ordinal});
    previewMetadata.textContent = localized('Referenced footnote');
    previewMetadata.hidden = false;
    previewBody.replaceChildren(content.cloneNode(true));
    sanitizeInertContent(previewBody);
    positionPopover(button);
  }

  function showLinkPopover(link: HTMLAnchorElement) {
    const key = link.dataset.sourceUtf16Start + ':' + link.dataset.sourceUtf16End;
    const preview = previewByRange.get(key);
    if (!preview) return;
    previewTitle.textContent = preview.title;
    previewMetadata.textContent = preview.fragment || '';
    previewMetadata.hidden = !preview.fragment;
    installInertDocumentContent(previewBody, preview);
    positionPopover(link);
  }

  function previewAnchorFor(target: EventTarget | null): HTMLElement | null {
    if (!(target instanceof Element)) return null;
    if (target.closest('.scholium-embedded-note')) return null;
    return target.closest<HTMLElement>('.footnote-reference, a.wiki-link');
  }

  function showPreviewFor(anchor: HTMLElement) {
    if (anchor.matches('.footnote-reference')) {
      showFootnotePopover(anchor);
    } else if (anchor.matches('a.wiki-link')) {
      showLinkPopover(anchor as HTMLAnchorElement);
    }
  }

  function remainsInsidePreviewAnchor(anchor: Element, relatedTarget: EventTarget | null) {
    return relatedTarget instanceof Node && anchor.contains(relatedTarget);
  }

  document.addEventListener('pointerover', event => {
    const anchor = previewAnchorFor(event.target);
    if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
    cancelPopoverHide();
    showPreviewFor(anchor);
  });
  document.addEventListener('focusin', event => {
    const anchor = previewAnchorFor(event.target);
    if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
    cancelPopoverHide();
    showPreviewFor(anchor);
  });
  document.addEventListener('pointerout', event => {
    const anchor = previewAnchorFor(event.target);
    if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
    if (event.relatedTarget instanceof Node && popover.contains(event.relatedTarget)) {
      cancelPopoverHide();
    } else {
      schedulePopoverHide();
    }
  });
  document.addEventListener('focusout', event => {
    const anchor = previewAnchorFor(event.target);
    if (anchor && !remainsInsidePreviewAnchor(anchor, event.relatedTarget)) schedulePopoverHide();
  });
  popover.addEventListener('pointerenter', cancelPopoverHide);
  popover.addEventListener('pointerleave', schedulePopoverHide);
  window.addEventListener('scroll', hidePopover, {passive: true});
  window.addEventListener('resize', hidePopover);
  window.addEventListener('blur', hidePopover);
  renderEmbeddedNotes();

  document.addEventListener('click', event => {
    const eventElement = event.target instanceof Element ? event.target : null;
    const reference = eventElement?.closest<HTMLButtonElement>('.footnote-reference');
    if (reference && !reference.disabled) {
      const ordinal = reference.dataset.footnote;
      const targetID = reference.dataset.target;
      const target = targetID ? document.getElementById(targetID) : null;
      if (target) {
        const origin = reference.closest('.footnote-reference-wrap') || reference;
        origins.set(ordinal, origin.id);
        target.tabIndex = -1;
        target.scrollIntoView({block: 'center', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'});
        target.focus({preventScroll: true});
      }
      event.preventDefault();
      return;
    }
    const back = eventElement?.closest<HTMLElement>('.footnote-return');
    if (back) {
      const ordinal = back.dataset.footnote;
      const originID = origins.get(ordinal) || 'fnref-' + ordinal + '-1';
      const origin = document.getElementById(originID);
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

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      hidePopover();
      if (!commentComposer.hidden) return;
      commentComposer.hidden = true;
      selectionToolbar.hidden = false;
      commentText.value = '';
      selectionActions.hidden = true;
    }
  });

  function showCommentComposer() {
    if (!reviewSelectionSurfaceActive
        || !commentEnabled
        || selectionActions.hidden
        || !commentButton.dataset.startLine) return false;
    const startLine = Number(commentButton.dataset.startLine);
    const endLine = Number(commentButton.dataset.endLine || commentButton.dataset.startLine);
    commentText.setAttribute(
      'aria-label',
      startLine === endLine
        ? localized('Comment for line {start}', {start: startLine})
        : localized('Comment for lines {start} through {end}', {start: startLine, end: endLine})
    );
    selectionToolbar.hidden = true;
    commentComposer.hidden = false;
    suspendedCommentComposer = false;
    selectionActions.classList.add('scholium-comment-composing');
    commentComposer.removeAttribute('data-state');
    commentComposer.setAttribute('aria-busy', 'false');
    commentHelp.textContent = defaultCommentHelpText;
    resizeCommentText();
    const anchorBounds = commentSelectionRange?.getBoundingClientRect();
    if (anchorBounds) positionSelectionActions(anchorBounds);
    commentText.focus();
    return true;
  }
  readerWindow.scholiumShowCommentComposer = showCommentComposer;

  function restoreCommentFocus() {
    const anchor = commentAnchorElement;
    const range = commentSelectionRange?.cloneRange();
    if (anchor instanceof HTMLElement) {
      const previousTabIndex = anchor.getAttribute('tabindex');
      anchor.tabIndex = -1;
      anchor.focus({preventScroll: true});
      if (previousTabIndex === null) anchor.removeAttribute('tabindex');
      else anchor.setAttribute('tabindex', previousTabIndex);
    }
    if (range) {
      const selection = window.getSelection();
      if (!selection) return;
      selection.removeAllRanges();
      selection.addRange(range);
    }
  }

  function cancelComment(restoreSelection: boolean, onlyWhenEmpty: boolean) {
    if (pendingCommentRequestID
        || (onlyWhenEmpty && commentText.value.trim())) return false;
    commentText.value = '';
    commentText.style.height = '';
    commentText.readOnly = false;
    commentComposer.removeAttribute('data-state');
    commentComposer.setAttribute('aria-busy', 'false');
    commentHelp.textContent = defaultCommentHelpText;
    commentComposer.hidden = true;
    suspendedCommentComposer = false;
    selectionToolbar.hidden = false;
    selectionActions.hidden = true;
    selectionActions.classList.remove('scholium-comment-composing');
    if (restoreSelection) {
      restoreCommentFocus();
    } else {
      commentText.blur();
      commentSelectionRange = null;
      commentAnchorElement = null;
    }
    return true;
  }

  readerWindow.scholiumSetReviewSelectionSurfaceActive = active => {
    const nextActive = Boolean(active);
    if (nextActive === reviewSelectionSurfaceActive) return true;
    reviewSelectionSurfaceActive = nextActive;
    reviewPointerSelectionActive = false;
    if (!nextActive) {
      const retainsDraft = !commentComposer.hidden
        && (Boolean(pendingCommentRequestID) || Boolean(commentText.value.trim()));
      suspendedCommentComposer = retainsDraft;
      selectionActions.hidden = true;
      reviewSelectionPresentation.clear();
      commentText.blur();
      if (!retainsDraft) cancelComment(false, false);
      return true;
    }
    if (suspendedCommentComposer && commentSelectionRange) {
      suspendedCommentComposer = false;
      selectionToolbar.hidden = true;
      commentComposer.hidden = false;
      selectionActions.hidden = false;
      selectionActions.classList.add('scholium-comment-composing');
      positionSelectionActions(commentSelectionRange.getBoundingClientRect());
      if (!pendingCommentRequestID) commentText.focus();
    } else {
      suspendedCommentComposer = false;
    }
    return true;
  };

  readerWindow.scholiumResolveCommentSubmission = (requestID, succeeded) => {
    if (!pendingCommentRequestID || requestID !== pendingCommentRequestID) return false;
    pendingCommentRequestID = null;
    commentText.readOnly = false;
    commentComposer.setAttribute('aria-busy', 'false');
    if (!succeeded) {
      commentHelp.textContent = localized('Could not save. Your Comment is still here.');
      commentComposer.dataset.state = 'error';
      if (reviewSelectionSurfaceActive) commentText.focus();
      return true;
    }
    commentText.value = '';
    commentText.style.height = '';
    commentComposer.removeAttribute('data-state');
    commentHelp.textContent = defaultCommentHelpText;
    commentComposer.hidden = true;
    selectionToolbar.hidden = false;
    selectionActions.hidden = true;
    selectionActions.classList.remove('scholium-comment-composing');
    suspendedCommentComposer = false;
    if (reviewSelectionSurfaceActive) {
      restoreCommentFocus();
    } else {
      commentText.blur();
      commentSelectionRange = null;
      commentAnchorElement = null;
    }
    return true;
  };

  if (selectionEnabled) {
    const reviewDocument = document.getElementById('scholium-document');
    const reviewMermaidElements = reviewDocument
      ? [...reviewDocument.querySelectorAll('[data-scholium-protected="mermaid"]')]
      : [];
    const repositionReviewSelectionActions = () => {
      if (!reviewSelectionSurfaceActive
          || reviewPointerSelectionActive
          || !commentSelectionRange
          || selectionActions.hidden) return;
      positionSelectionActions(commentSelectionRange.getBoundingClientRect());
    };
    const clearReviewSelection = () => {
      commentSelectionRange = null;
      commentAnchorElement = null;
      selectionActions.hidden = true;
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
    const updateSelectionActions = () => {
      // Focusing the Comment textarea collapses the document
      // selection. Keep the anchored composer stable until the
      // researcher saves or cancels it; that focus transition is
      // not a request to discard the marginal note.
      if (!reviewSelectionSurfaceActive) {
        selectionActions.hidden = true;
        return;
      }
      if (!commentComposer.hidden) return;
      const selection = window.getSelection();
      const main = reviewDocument;
      reviewSelectionPresentation.update(selection, main);
      if (reviewPointerSelectionActive) {
        selectionActions.hidden = true;
        return;
      }
      if (!selection || selection.rangeCount !== 1 || selection.isCollapsed || !main) {
        clearReviewSelection();
        return;
      }
      const range = selection.getRangeAt(0);
      if (!main.contains(range.startContainer) || !main.contains(range.endContainer)) {
        clearReviewSelection();
        return;
      }
      if (rangeIntersectsMermaid(range)) {
        clearReviewSelection();
        return;
      }
      const text = boundedReviewRangeText(range, main, 2000);
      if (!text) {
        clearReviewSelection();
        return;
      }
      const rect = range.getBoundingClientRect();
      commentSelectionRange = range.cloneRange();
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
      const payload = {
        text,
        contextBefore: reviewContextBefore(range, main, 80),
        contextAfter: reviewContextAfter(range, main, 80),
        startLine: Math.min(startLine, endLine),
        endLine: Math.max(startLine, endLine)
      };
      post('selectionChanged', payload);
      if (!commentEnabled) {
        selectionActions.hidden = true;
        return;
      }
      commentButton.dataset.startLine = String(payload.startLine);
      commentButton.dataset.endLine = String(payload.endLine);
      commentButton.dataset.selection = payload.text;
      commentButton.dataset.contextBefore = payload.contextBefore;
      commentButton.dataset.contextAfter = payload.contextAfter;
      commentAnchorElement = sourceElement;
      commentButton.hidden = !commentEnabled;
      positionSelectionActions(rect);
    };
    document.addEventListener('selectionchange', updateSelectionActions);
    reviewDocument?.addEventListener('pointerdown', event => {
      if (!reviewSelectionSurfaceActive || event.button !== 0) return;
      if (!commentComposer.hidden && !cancelComment(false, true)) {
        event.preventDefault();
        commentText.focus();
        return;
      }
      if (commentAnchorElement instanceof HTMLElement
          && document.activeElement === commentAnchorElement) {
        commentAnchorElement.blur();
      }
      commentSelectionRange = null;
      commentAnchorElement = null;
      reviewPointerSelectionActive = true;
      selectionActions.hidden = true;
    }, true);
    window.addEventListener('pointerup', event => {
      if (!reviewPointerSelectionActive || event.button !== 0) return;
      reviewPointerSelectionActive = false;
      queueMicrotask(updateSelectionActions);
    }, true);
    window.addEventListener('pointercancel', () => {
      reviewPointerSelectionActive = false;
      selectionActions.hidden = true;
    }, true);
    window.addEventListener('resize', repositionReviewSelectionActions);
    window.addEventListener('blur', () => {
      reviewPointerSelectionActive = false;
      if (commentComposer.hidden) selectionActions.hidden = true;
    });
  }
  if (commentEnabled) {
    // Keep the document selection alive through the button's
    // pointer-down. The subsequent click owns the deliberate
    // transition from the compact bar to the anchored field.
    commentButton.addEventListener('mousedown', event => event.preventDefault());
    commentButton.addEventListener('click', showCommentComposer);
    let preservesNextInsertedLineBreak = false;
    const makeRequestID = () => {
      if (globalThis.crypto && typeof globalThis.crypto.randomUUID === 'function') {
        return globalThis.crypto.randomUUID();
      }
      const bytes = new Uint8Array(16);
      if (globalThis.crypto && typeof globalThis.crypto.getRandomValues === 'function') {
        globalThis.crypto.getRandomValues(bytes);
      } else {
        for (let index = 0; index < bytes.length; index += 1) {
          bytes[index] = Math.floor(Math.random() * 256);
        }
      }
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, '0'));
      return hex.slice(0, 4).join('') + '-' + hex.slice(4, 6).join('') + '-'
        + hex.slice(6, 8).join('') + '-' + hex.slice(8, 10).join('') + '-'
        + hex.slice(10, 16).join('');
    };
    const submitComment = () => {
      const comment = commentText.value.trim();
      if (!comment || pendingCommentRequestID) return;
      if (new TextEncoder().encode(comment).byteLength > 16384) {
        commentHelp.textContent = localized('This Comment is too long to save here.');
        commentComposer.dataset.state = 'error';
        return;
      }
      pendingCommentRequestID = makeRequestID();
      commentText.readOnly = true;
      commentComposer.setAttribute('aria-busy', 'true');
      commentHelp.textContent = localized('Saving…');
      commentComposer.dataset.state = 'saving';
      post('commentSubmitted', {
        requestID: pendingCommentRequestID,
        comment,
        text: commentButton.dataset.selection || '',
        contextBefore: commentButton.dataset.contextBefore || '',
        contextAfter: commentButton.dataset.contextAfter || '',
        startLine: Number(commentButton.dataset.startLine || '1'),
        endLine: Number(commentButton.dataset.endLine || commentButton.dataset.startLine || '1')
      });
    };
    qaCommentSubmit && qaCommentSubmit.addEventListener('click', submitComment);
    commentText.addEventListener('input', () => {
      resizeCommentText();
      if (commentComposer.dataset.state === 'error') {
        commentComposer.removeAttribute('data-state');
        commentHelp.textContent = defaultCommentHelpText;
      }
    });
    commentText.addEventListener('keydown', event => {
      if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        cancelComment(true, false);
        return;
      }
      const isReturn = event.key === 'Enter'
        || event.key === 'Return'
        || event.code === 'Enter'
        || event.code === 'NumpadEnter';
      if (!isReturn || event.isComposing) return;
      if (event.shiftKey) {
        preservesNextInsertedLineBreak = true;
        setTimeout(() => { preservesNextInsertedLineBreak = false; }, 0);
        return;
      }
      event.preventDefault();
      submitComment();
    });
    // Accessibility text insertion can bypass DOM keydown while
    // still producing an InputEvent whose type is insertText.
    // Treat only an actually inserted line break as Return-to-save;
    // a real Shift-Return marks exactly its following input as prose.
    commentText.addEventListener('input', event => {
      const input = event as InputEvent;
      const insertedLineBreak = input.inputType === 'insertLineBreak'
        || input.inputType === 'insertParagraph'
        || (input.inputType === 'insertText'
          && ((typeof input.data === 'string' && /[\r\n]/.test(input.data))
            || /[\r\n]$/.test(commentText.value)));
      if (!insertedLineBreak) return;
      if (preservesNextInsertedLineBreak) {
        preservesNextInsertedLineBreak = false;
        return;
      }
      submitComment();
    });
  }

  const scrollBlockRegistry = (() => {
    const root = document.getElementById('scholium-document');
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
    for (const element of candidates) {
      const lower = Number(element.dataset.sourceUtf16Start);
      const upper = Number(element.dataset.sourceUtf16End);
      if (!Number.isFinite(lower) || !Number.isFinite(upper) || upper < lower) continue;
      const style = getComputedStyle(element);
      if (style.display === 'inline' || style.display === 'contents'
          || style.display === 'none' || style.visibility === 'hidden') continue;
      const initialRect = element.getBoundingClientRect();
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
    return {
      root,
      entries,
      byElement,
      byExactRange,
      bySource,
      sourcePrefixMaximumUpper
    };
  })();

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
    if (entry) return entry;

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
      else return candidate;
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
    const probe = 8;
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
    const target = visibleScrollEntry(scrollEntryForAnchor(anchor));
    if (!target) return false;
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
    const requestedTop = window.scrollY + rect.top
      + interiorOffset - 8;
    window.scrollTo({top: Math.max(0, requestedTop), behavior: 'auto'});
    return true;
  }

  readerWindow.scholiumReadScroll = {
    restoreCount: 0,
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

  let scrollTimer: ReturnType<typeof setTimeout> | undefined;
  window.addEventListener('scroll', () => {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(() => {
      const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
      const fraction = extent > 0 ? Math.max(0, Math.min(1, window.scrollY / extent)) : 0;
      post('scrollChanged', {fraction, anchor: currentReadScrollAnchor(fraction)});
    }, 120);
  }, {passive: true});
  // Install only after the rendered document and its event
  // handlers exist. The native side also probes this API from
  // didFinish, so a dropped early message cannot lose a query.
}

readerWindow.scholiumRead = {
  initialize(value: unknown) {
    const ready = initializeReader(value);
    readerWindow.scholiumReadReady = ready;
    return ready;
  },
};
