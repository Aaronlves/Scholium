"use strict";
(() => {
  // review-find.ts
  function highlightRegistry() {
    return CSS.highlights ?? null;
  }
  function textNodesIn(element) {
    const nodes = [];
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || !node.textContent) return NodeFilter.FILTER_REJECT;
        if (parent.closest(
          'script, style, [hidden], [aria-hidden="true"], #selection-actions, #scholium-preview-popover'
        )) return NodeFilter.FILTER_REJECT;
        if (parent.closest('[data-scholium-protected="mermaid"]')) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    while (walker.nextNode()) {
      if (walker.currentNode instanceof Text) nodes.push(walker.currentNode);
    }
    return nodes;
  }
  function rangeFor(nodes, start, end) {
    let offset = 0;
    let startNode = null;
    let startOffset = 0;
    let endNode = null;
    let endOffset = 0;
    for (const node of nodes) {
      const next = offset + node.data.length;
      if (!startNode && start >= offset && start <= next) {
        startNode = node;
        startOffset = start - offset;
      }
      if (!endNode && end >= offset && end <= next) {
        endNode = node;
        endOffset = end - offset;
        break;
      }
      offset = next;
    }
    if (!startNode || !endNode) return null;
    const range = new Range();
    range.setStart(startNode, startOffset);
    range.setEnd(endNode, endOffset);
    return range;
  }
  function isWord(character) {
    return Boolean(character) && /[\p{L}\p{N}_]/u.test(character ?? "");
  }
  function searchableLines() {
    const root = document.querySelector("main");
    if (!root) return [];
    const lines = Array.from(root.querySelectorAll("[data-source-line]")).filter((element) => !element.querySelector("[data-source-line]"));
    return lines.length > 0 ? lines : [root];
  }
  function rangesFor(request) {
    if (!request.query) return [];
    const collator = request.caseSensitive ? null : new Intl.Collator(void 0, { usage: "search", sensitivity: "accent" });
    const result = [];
    for (const line of searchableLines()) {
      const nodes = textNodesIn(line);
      const text = nodes.map((node) => node.data).join("");
      for (let index = 0; index <= text.length - request.query.length; ) {
        const candidate = text.slice(index, index + request.query.length);
        const equal = request.caseSensitive ? candidate === request.query : collator?.compare(candidate, request.query) === 0;
        const whole = !request.wholeWord || !isWord(text[index - 1]) && !isWord(text[index + request.query.length]);
        if (equal && whole) {
          const range = rangeFor(nodes, index, index + request.query.length);
          if (range) result.push(range);
          index += Math.max(1, request.query.length);
        } else {
          index += 1;
        }
      }
    }
    return result;
  }
  function installReviewFind() {
    const allName = "scholium-review-find";
    const currentName = "scholium-review-find-current";
    const registry = highlightRegistry();
    let signature = "";
    let matches = [];
    let current = -1;
    const style = document.createElement("style");
    style.textContent = `
    ::highlight(scholium-review-find) {
      background: color-mix(in srgb, var(--scholium-color-accent) 22%, transparent);
    }
    ::highlight(scholium-review-find-current) {
      background: color-mix(in srgb, var(--scholium-color-accent) 42%, transparent);
      text-decoration: underline;
      text-decoration-color: var(--scholium-color-accent);
    }
  `;
    document.head.appendChild(style);
    const clear = () => {
      registry?.delete(allName);
      registry?.delete(currentName);
    };
    const present = () => {
      clear();
      if (matches.length === 0 || !registry || current < 0) return;
      const ordinary = matches.filter((_, index) => index !== current);
      if (ordinary.length > 0) registry.set(allName, new Highlight(...ordinary));
      registry.set(currentName, new Highlight(matches[current]));
      matches[current].startContainer.parentElement?.scrollIntoView({ block: "center", behavior: "auto" });
    };
    return {
      perform(request) {
        if (!request || request.operation === "clear") {
          signature = "";
          matches = [];
          current = -1;
          clear();
          return { current: 0, total: 0 };
        }
        const nextSignature = JSON.stringify([
          request.query,
          request.caseSensitive,
          request.wholeWord
        ]);
        if (nextSignature !== signature || request.action === "update") {
          signature = nextSignature;
          matches = rangesFor(request);
          current = matches.length > 0 ? 0 : -1;
        } else if (request.action === "next" && matches.length > 0) {
          current = (current + 1) % matches.length;
        } else if (request.action === "previous" && matches.length > 0) {
          current = (current - 1 + matches.length) % matches.length;
        }
        present();
        return { current: current < 0 ? 0 : current + 1, total: matches.length };
      }
    };
  }

  // review-selection-text.ts
  function nodeAfterSubtree(node, root) {
    let current = node;
    while (current && current !== root) {
      if (current.nextSibling) return current.nextSibling;
      current = current.parentNode;
    }
    return null;
  }
  function nextNode(node, root) {
    return node.firstChild || nodeAfterSubtree(node, root);
  }
  function previousNode(node, root) {
    if (!node || node === root) return null;
    if (node.previousSibling) {
      let previous = node.previousSibling;
      while (previous.lastChild) previous = previous.lastChild;
      return previous;
    }
    return node.parentNode === root ? root : node.parentNode;
  }
  function boundaryNode(container, offset, root) {
    if (container instanceof Text) return container;
    return container.childNodes[offset] || nodeAfterSubtree(container, root);
  }
  function* reviewRangeTextNodes(range, root) {
    let node = boundaryNode(range.startContainer, range.startOffset, root);
    const stop = range.endContainer instanceof Text ? nextNode(range.endContainer, root) : boundaryNode(range.endContainer, range.endOffset, root);
    while (node && node !== stop) {
      if (node instanceof Text) {
        try {
          if (range.intersectsNode(node)) yield node;
        } catch {
        }
      }
      node = nextNode(node, root);
    }
  }
  function boundedReviewRangeText(range, root, limit) {
    let result = "";
    let started = false;
    let nonWhitespaceAfterLimit = false;
    for (const node of reviewRangeTextNodes(range, root)) {
      const from = range.startContainer === node ? range.startOffset : 0;
      const to = range.endContainer === node ? range.endOffset : node.length;
      let chunk = node.data.slice(from, to);
      if (!started) {
        const firstContent = chunk.search(/\S/u);
        if (firstContent < 0) continue;
        chunk = chunk.slice(firstContent);
        started = true;
      }
      const remaining = Math.max(0, limit - result.length);
      if (remaining > 0) result += chunk.slice(0, remaining);
      if (/\S/u.test(chunk.slice(remaining))) {
        nonWhitespaceAfterLimit = true;
        if (result.length >= limit) break;
      }
    }
    return nonWhitespaceAfterLimit ? result : result.trimEnd();
  }
  function reviewContextBefore(range, root, limit) {
    const chunks = [];
    let remaining = limit;
    let node = range.startContainer;
    if (node instanceof Text) {
      const chunk = node.data.slice(0, range.startOffset).slice(-remaining);
      if (chunk) {
        chunks.push(chunk);
        remaining -= chunk.length;
      }
      node = previousNode(node, root);
    } else if (range.startOffset > 0) {
      node = node.childNodes[range.startOffset - 1] || previousNode(node, root);
      while (node?.lastChild) node = node.lastChild;
    } else {
      node = previousNode(node, root);
    }
    while (node && node !== root && remaining > 0) {
      if (node instanceof Text) {
        const chunk = node.data.slice(-remaining);
        if (chunk) {
          chunks.push(chunk);
          remaining -= chunk.length;
        }
      }
      node = previousNode(node, root);
    }
    return chunks.reverse().join("");
  }
  function reviewContextAfter(range, root, limit) {
    const chunks = [];
    let remaining = limit;
    let node;
    if (range.endContainer instanceof Text) {
      const chunk = range.endContainer.data.slice(range.endOffset, range.endOffset + remaining);
      if (chunk) {
        chunks.push(chunk);
        remaining -= chunk.length;
      }
      node = nextNode(range.endContainer, root);
    } else {
      node = boundaryNode(range.endContainer, range.endOffset, root);
    }
    while (node && remaining > 0) {
      if (node instanceof Text) {
        const chunk = node.data.slice(0, remaining);
        if (chunk) {
          chunks.push(chunk);
          remaining -= chunk.length;
        }
      }
      node = nextNode(node, root);
    }
    return chunks.join("");
  }

  // review-selection-presentation.ts
  function highlightRegistry2() {
    const value = CSS.highlights;
    return value ?? null;
  }
  function createReviewSelectionPresentation(selectionEnabled, testingEnabled) {
    const registry = highlightRegistry2();
    const supported = selectionEnabled && typeof Highlight === "function" && registry !== null;
    let textRanges = [];
    const presentation = {
      supported,
      clear() {
        const hadRanges = textRanges.length > 0;
        textRanges = [];
        if (supported && hadRanges) registry?.delete("scholium-review-selection");
      },
      update(selection, main) {
        this.clear();
        if (!supported || !main || !selection || selection.rangeCount !== 1 || selection.isCollapsed) return;
        const sourceRange = selection.getRangeAt(0);
        if (!main.contains(sourceRange.startContainer) || !main.contains(sourceRange.endContainer)) return;
        for (const node of reviewRangeTextNodes(sourceRange, main)) {
          if (!node.textContent?.trim() || node.parentElement?.closest('[aria-hidden="true"], script, style')) continue;
          const from = sourceRange.startContainer === node ? sourceRange.startOffset : 0;
          const to = sourceRange.endContainer === node ? sourceRange.endOffset : node.length;
          if (from >= to) continue;
          const range = document.createRange();
          range.setStart(node, from);
          range.setEnd(node, to);
          textRanges.push(range);
        }
        if (textRanges.length && registry) {
          registry.set("scholium-review-selection", new Highlight(...textRanges));
        }
      }
    };
    if (testingEnabled) {
      presentation.testingSnapshot = () => {
        const selection = window.getSelection();
        const nativeRange = selection?.rangeCount ? selection.getRangeAt(0) : null;
        const rectangles = (range) => range ? Array.from(range.getClientRects()).map((rect) => ({
          left: rect.left,
          right: rect.right,
          top: rect.top,
          bottom: rect.bottom,
          width: rect.width,
          height: rect.height
        })) : [];
        const paragraph = document.querySelector("#scholium-document p");
        return {
          supported,
          selectedText: selection?.toString() ?? "",
          presentedText: textRanges.map((range) => range.toString()).join(""),
          nativeSelectionBackground: paragraph ? getComputedStyle(paragraph, "::selection").backgroundColor : "",
          nativeRectangles: rectangles(nativeRange),
          textRectangles: textRanges.flatMap((range) => rectangles(range)),
          textRangeCount: textRanges.length,
          customHighlightInstalled: supported && (registry?.has("scholium-review-selection") ?? false)
        };
      };
    }
    if (supported) document.documentElement.classList.add("scholium-review-custom-selection");
    return presentation;
  }

  // reader-configuration.ts
  function validatedReaderConfiguration(value) {
    if (!value || typeof value !== "object") return null;
    const config = value;
    if (config.version !== 2 || typeof config.documentID !== "string" || !config.documentID || config.documentID.length > 4096 || typeof config.fingerprint !== "string" || !config.fingerprint || config.fingerprint.length > 256 || !Number.isSafeInteger(config.loadGeneration) || Number(config.loadGeneration) < 0 || typeof config.selectionEnabled !== "boolean" || typeof config.testingEnabled !== "boolean" || typeof config.presentationCSS !== "string" || typeof config.userCSS !== "string" || !config.localization || typeof config.localization !== "object" || !config.localization.strings || typeof config.localization.strings !== "object" || !Array.isArray(config.linkPreviews) || config.linkPreviews.length > 128) return null;
    return config;
  }

  // reader.ts
  var readerWindow = window;
  function requiredElement(id) {
    const element = document.getElementById(id);
    if (!(element instanceof HTMLElement)) throw new Error(`Missing reader element: ${id}`);
    return element;
  }
  async function initializeReader(value) {
    const config = validatedReaderConfiguration(value);
    if (!config) throw new Error("Invalid reader configuration.");
    const {
      version,
      documentID,
      fingerprint,
      loadGeneration,
      selectionEnabled,
      presentationCSS,
      userCSS,
      localization,
      linkPreviews,
      testingEnabled
    } = config;
    const presentationStyle = requiredElement("scholium-presentation-css");
    const userStyle = requiredElement("scholium-user-css");
    presentationStyle.textContent = presentationCSS;
    userStyle.textContent = userCSS;
    const strings = localization.strings || {};
    const localized = (key, replacements = {}) => String(strings[key] || key).replace(
      /\{([A-Za-z]+)\}/g,
      (placeholder, name) => Object.prototype.hasOwnProperty.call(replacements, name) ? String(replacements[name]) : placeholder
    );
    const handler = readerWindow.webkit?.messageHandlers?.scholiumRead;
    const post = (type, extra = {}) => handler?.postMessage({
      version,
      documentID,
      fingerprint,
      loadGeneration,
      type,
      ...extra
    });
    const popover = requiredElement("scholium-preview-popover");
    const previewTitle = popover.querySelector(".scholium-preview-title");
    const previewMetadata = popover.querySelector(".scholium-preview-metadata");
    const previewBody = popover.querySelector(".scholium-preview-body");
    const viewportRoot = document.documentElement;
    const viewportResizeScrollBarClass = "scholium-viewport-resize-suppresses-overlay-scrollbar";
    const viewportResizeSettleDelay = 80;
    const viewportGeometryProbe = document.createElement("span");
    viewportGeometryProbe.setAttribute("aria-hidden", "true");
    viewportGeometryProbe.style.cssText = "position:fixed;inline-size:100vw;block-size:100vh;visibility:hidden;pointer-events:none";
    document.body.append(viewportGeometryProbe);
    const viewportGeometry = () => viewportGeometryProbe.getBoundingClientRect();
    let viewportResizeGeneration = 0;
    let viewportResizeTimer;
    let viewportBounds = viewportGeometry();
    const viewportDidResize = () => {
      const nextBounds = viewportGeometry();
      if (Math.abs(nextBounds.width - viewportBounds.width) < 0.5 && Math.abs(nextBounds.height - viewportBounds.height) < 0.5) return;
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
          window.removeEventListener("resize", viewportDidResize);
          viewportRoot.classList.remove(viewportResizeScrollBarClass);
          setTimeout(() => {
            viewportBounds = viewportGeometry();
            window.addEventListener("resize", viewportDidResize);
          }, 0);
        }
      }, viewportResizeSettleDelay);
    };
    window.addEventListener("resize", viewportDidResize);
    readerWindow.scholiumReviewFind = installReviewFind();
    const reviewSelectionPresentation = createReviewSelectionPresentation(
      selectionEnabled,
      testingEnabled
    );
    readerWindow.scholiumReviewSelection = reviewSelectionPresentation;
    let reviewPointerSelectionActive = false;
    let reviewSelectionSurfaceActive = true;
    let previewByRange = new Map(linkPreviews.map((preview) => [
      preview.utf16LowerBound + ":" + preview.utf16UpperBound,
      preview
    ]));
    const origins = /* @__PURE__ */ new Map();
    function renderMathNodes() {
      const runtime = readerWindow.scholiumMath;
      if (!runtime || runtime.version !== 1) return;
      document.querySelectorAll(".scholium-math[data-math-source][data-math-kind]").forEach((element) => {
        try {
          const encodedSource = element.dataset.mathSource;
          const kind = element.dataset.mathKind;
          if (!encodedSource || kind !== "inline" && kind !== "display") return;
          const source = new TextDecoder().decode(
            Uint8Array.from(atob(encodedSource), (character) => character.charCodeAt(0))
          );
          const result = runtime.render({ source, kind });
          if (!result.ok) {
            element.classList.add("scholium-math-error");
            element.setAttribute(
              "aria-label",
              localized("Mathematics could not be rendered. Source is shown.")
            );
            return;
          }
          const fallback = element.querySelector(".scholium-math-source");
          const rendered = document.createElement("span");
          rendered.className = "scholium-math-output";
          rendered.innerHTML = result.html;
          fallback && fallback.before(rendered);
          element.classList.add("scholium-math-rendered");
        } catch (_) {
          element.classList.add("scholium-math-error");
        }
      });
    }
    renderMathNodes();
    function mermaidDiagnostic(wrapper, message) {
      const diagnostic = document.createElement("p");
      diagnostic.className = "scholium-mermaid-diagnostic";
      diagnostic.textContent = message;
      wrapper.append(diagnostic);
    }
    function isMermaidCode(code) {
      return [...code.classList].some((name) => name.toLowerCase() === "language-mermaid");
    }
    let mermaidRuntimePromise = null;
    function ensureMermaidRuntime() {
      const current = readerWindow.scholiumMermaid;
      if (current?.version === 2) return Promise.resolve(current);
      if (!handler) return Promise.resolve(null);
      if (mermaidRuntimePromise) return mermaidRuntimePromise;
      mermaidRuntimePromise = new Promise((resolve) => {
        let settled = false;
        const finish = () => {
          if (settled) return;
          settled = true;
          clearTimeout(timeout);
          readerWindow.scholiumMermaidRuntimeDidLoad = void 0;
          const loaded = readerWindow.scholiumMermaid;
          if (loaded?.version !== 2) mermaidRuntimePromise = null;
          resolve(loaded?.version === 2 ? loaded : null);
        };
        const timeout = setTimeout(finish, 8e3);
        readerWindow.scholiumMermaidRuntimeDidLoad = finish;
        post("requestMermaidRuntime");
      });
      return mermaidRuntimePromise;
    }
    async function renderMermaidWrapper(wrapper, source) {
      for (const child of [...wrapper.children]) {
        if (child.classList.contains("scholium-mermaid-output") || child.classList.contains("scholium-mermaid-diagnostic") || child.classList.contains("scholium-mermaid-accessible-source")) {
          child.remove();
        }
      }
      wrapper.classList.remove("scholium-mermaid-rendered", "scholium-mermaid-error");
      const runtime = await ensureMermaidRuntime();
      if (!runtime) {
        wrapper.classList.add("scholium-mermaid-error");
        mermaidDiagnostic(
          wrapper,
          localized("Diagram rendering is unavailable. Mermaid source is shown.")
        );
        return;
      }
      try {
        const result = await runtime.render({ source, themeRoot: document.documentElement });
        if (!result.ok) {
          wrapper.classList.add("scholium-mermaid-error");
          mermaidDiagnostic(
            wrapper,
            localized("This Mermaid diagram is unsupported or could not be rendered. Source is shown.")
          );
          return;
        }
        const output = document.createElement("div");
        output.className = "scholium-mermaid-output";
        if (!runtime.mount(output, result.svg)) {
          wrapper.classList.add("scholium-mermaid-error");
          mermaidDiagnostic(
            wrapper,
            localized("This Mermaid diagram could not be isolated safely. Source is shown.")
          );
          return;
        }
        wrapper.prepend(output);
        wrapper.classList.add("scholium-mermaid-rendered");
        if (result.accessibilityWarning) {
          const accessibleSource = document.createElement("span");
          accessibleSource.className = "scholium-mermaid-accessible-source";
          accessibleSource.textContent = localized("Mermaid source: {source}", { source });
          wrapper.append(accessibleSource);
          mermaidDiagnostic(
            wrapper,
            localized("Add accTitle and accDescr to provide a concise nonvisual account of this diagram.")
          );
        }
      } catch (_) {
        wrapper.classList.add("scholium-mermaid-error");
        mermaidDiagnostic(
          wrapper,
          localized("This Mermaid diagram could not be rendered. Source is shown.")
        );
      }
    }
    async function renderMermaidNodes() {
      const nodes = [...document.querySelectorAll("pre > code")].filter((code) => isMermaidCode(code) && !code.closest(".scholium-mermaid"));
      for (const code of nodes) {
        const original = code.parentElement;
        if (!original) continue;
        const source = code.textContent || "";
        const wrapper = document.createElement("figure");
        wrapper.className = "scholium-mermaid";
        wrapper.dataset.scholiumProtected = "mermaid";
        for (const name of ["data-source-utf16-start", "data-source-utf16-end", "data-source-start-line", "data-source-end-line"]) {
          const value2 = original.getAttribute(name);
          if (value2 !== null) wrapper.setAttribute(name, value2);
        }
        const fallback = original.cloneNode(true);
        fallback.classList.add("scholium-mermaid-source");
        wrapper.append(fallback);
        original.replaceWith(wrapper);
        await renderMermaidWrapper(wrapper, source);
      }
    }
    async function refreshMermaidNodes() {
      for (const wrapper of document.querySelectorAll(".scholium-mermaid")) {
        const source = wrapper.querySelector(".scholium-mermaid-source > code")?.textContent || "";
        await renderMermaidWrapper(wrapper, source);
      }
    }
    function scheduleMermaidRefresh() {
      const current = readerWindow.scholiumMermaidReady || Promise.resolve();
      readerWindow.scholiumMermaidReady = current.catch(() => {
      }).then(refreshMermaidNodes);
    }
    readerWindow.scholiumMermaidReady = renderMermaidNodes();
    await readerWindow.scholiumMermaidReady;
    for (const mediaQuery of [
      matchMedia("(prefers-color-scheme: dark)"),
      matchMedia("(prefers-contrast: more)")
    ]) {
      mediaQuery.addEventListener("change", scheduleMermaidRefresh);
    }
    document.querySelectorAll("button[data-link-annotation]").forEach((button) => {
      const identifier = button.dataset.linkAnnotation;
      if (!identifier) return;
      const wrapper = button.closest(".scholium-annotated-link");
      const template = document.getElementById(`${identifier}-template`);
      const linkName = wrapper?.querySelector(".wiki-link")?.textContent?.trim() || localized("linked note");
      if (!wrapper || !template) return;
      const setLabel = (expanded) => {
        button.setAttribute(
          "aria-label",
          `${localized(expanded ? "Hide Link Annotation" : "Show Link Annotation")} ${linkName}`
        );
      };
      setLabel(false);
      button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        const existing = wrapper.querySelector(":scope > .scholium-link-annotation-panel");
        if (existing) {
          existing.remove();
          button.setAttribute("aria-expanded", "false");
          setLabel(false);
          return;
        }
        const panel = document.createElement("span");
        panel.id = identifier;
        panel.className = "scholium-link-annotation-panel";
        panel.setAttribute("role", "note");
        panel.append(template.content.cloneNode(true));
        wrapper.append(panel);
        button.setAttribute("aria-expanded", "true");
        setLabel(true);
      });
    });
    let popoverHideTimer;
    function hidePopover() {
      clearTimeout(popoverHideTimer);
      popoverHideTimer = void 0;
      popover.hidden = true;
      previewTitle.textContent = "";
      previewMetadata.textContent = "";
      previewMetadata.hidden = true;
      previewBody.replaceChildren();
    }
    function cancelPopoverHide() {
      clearTimeout(popoverHideTimer);
      popoverHideTimer = void 0;
    }
    function schedulePopoverHide() {
      clearTimeout(popoverHideTimer);
      popoverHideTimer = setTimeout(hidePopover, 180);
    }
    function normalizedPreviewTitle(value2) {
      return String(value2 || "").trim().replace(/\s+/g, " ").toLocaleLowerCase();
    }
    function sanitizeInertContent(container) {
      container.querySelectorAll("script, style, iframe, object, embed, form, input, button").forEach((node) => node.remove());
      container.querySelectorAll("*").forEach((node) => {
        Array.from(node.attributes).forEach((attribute) => {
          if (attribute.name.toLowerCase().startsWith("on")) node.removeAttribute(attribute.name);
          if (attribute.name.toLowerCase().startsWith("data-source-")) {
            node.removeAttribute(attribute.name);
          }
        });
        node.removeAttribute("href");
        node.removeAttribute("contenteditable");
        node.removeAttribute("id");
        node.removeAttribute("for");
        node.removeAttribute("aria-describedby");
        node.removeAttribute("aria-labelledby");
        node.removeAttribute("aria-owns");
        node.tabIndex = -1;
      });
    }
    function installInertDocumentContent(container, preview) {
      container.innerHTML = preview.htmlBody;
      sanitizeInertContent(container);
      const firstHeading = container.querySelector(":scope > h1:first-child");
      if (firstHeading && normalizedPreviewTitle(firstHeading.textContent) === normalizedPreviewTitle(preview.title)) {
        firstHeading.remove();
      }
    }
    function embeddedNoteFor(anchor, preview, key) {
      const shell = document.createElement("section");
      shell.className = "scholium-embedded-note";
      shell.dataset.scholiumProtected = "embedded-note";
      shell.dataset.previewRange = key;
      shell.dataset.embedHref = anchor.getAttribute("href") || "";
      shell.dataset.embedLabel = (anchor.textContent || preview.title).trim();
      shell.setAttribute("role", "group");
      shell.setAttribute(
        "aria-label",
        localized("Embedded note {title}", { title: preview.title })
      );
      for (const name of [
        "data-source-utf16-start",
        "data-source-utf16-end",
        "data-source-start-line",
        "data-source-end-line",
        "data-source-line"
      ]) {
        const value2 = anchor.getAttribute(name);
        if (value2 !== null) shell.setAttribute(name, value2);
      }
      const header = document.createElement("header");
      header.className = "scholium-embedded-note-header";
      const open = document.createElement("a");
      open.className = "wiki-link scholium-embedded-note-open";
      open.dir = "auto";
      open.href = shell.dataset.embedHref ?? "";
      open.append(document.createTextNode(preview.title));
      open.setAttribute(
        "aria-label",
        localized("Open embedded note {title}", { title: preview.title })
      );
      open.title = localized("Open embedded note {title}", { title: preview.title });
      header.append(open);
      const viewport = document.createElement("div");
      viewport.className = "scholium-embedded-note-viewport";
      viewport.tabIndex = 0;
      viewport.setAttribute("role", "region");
      viewport.setAttribute(
        "aria-label",
        localized("Embedded note content for {title}", { title: preview.title })
      );
      const body = document.createElement("div");
      body.className = "scholium-embedded-note-body scholium-document";
      installInertDocumentContent(body, preview);
      viewport.append(body);
      shell.append(header, viewport);
      return shell;
    }
    function restoreEmbeddedNoteFallback(shell) {
      const fallback = document.createElement("a");
      fallback.className = "wiki-link scholium-embed";
      fallback.dir = "auto";
      fallback.href = shell.dataset.embedHref || "";
      fallback.textContent = shell.dataset.embedLabel || localized("Embedded note");
      fallback.dataset.scholiumProtected = "embed";
      for (const name of [
        "data-source-utf16-start",
        "data-source-utf16-end",
        "data-source-start-line",
        "data-source-end-line",
        "data-source-line"
      ]) {
        const value2 = shell.getAttribute(name);
        if (value2 !== null) fallback.setAttribute(name, value2);
      }
      shell.replaceWith(fallback);
    }
    function renderEmbeddedNotes() {
      const documentRoot = document.getElementById("scholium-document");
      if (!documentRoot) return;
      for (const shell of documentRoot.querySelectorAll(
        ".scholium-embedded-note[data-preview-range]"
      )) {
        if (shell.parentElement?.closest(".scholium-embedded-note")) continue;
        const previewRange = shell.dataset.previewRange;
        const preview = previewRange ? previewByRange.get(previewRange) : void 0;
        if (!preview || !preview.isEmbedded) {
          restoreEmbeddedNoteFallback(shell);
          continue;
        }
        const body = shell.querySelector(".scholium-embedded-note-body");
        const open = shell.querySelector(".scholium-embedded-note-open");
        if (body) installInertDocumentContent(body, preview);
        if (open) {
          const label = open.firstChild;
          if (label) label.textContent = preview.title;
          open.setAttribute(
            "aria-label",
            localized("Open embedded note {title}", { title: preview.title })
          );
          open.title = localized("Open embedded note {title}", { title: preview.title });
        }
        shell.setAttribute(
          "aria-label",
          localized("Embedded note {title}", { title: preview.title })
        );
      }
      const anchors = [...documentRoot.querySelectorAll("a.scholium-embed")].filter((anchor) => !anchor.parentElement?.closest(".scholium-embedded-note"));
      for (const anchor of anchors) {
        const key = anchor.dataset.sourceUtf16Start + ":" + anchor.dataset.sourceUtf16End;
        const preview = previewByRange.get(key);
        if (!preview || !preview.isEmbedded) continue;
        anchor.replaceWith(embeddedNoteFor(anchor, preview, key));
      }
    }
    readerWindow.scholiumSetLinkPreviews = (previews) => {
      previewByRange = new Map(previews.map((preview) => [
        preview.utf16LowerBound + ":" + preview.utf16UpperBound,
        preview
      ]));
      hidePopover();
      renderEmbeddedNotes();
      return true;
    };
    function positionPopover(anchor) {
      popover.hidden = false;
      const rect = anchor.getBoundingClientRect();
      const measured = popover.getBoundingClientRect();
      const left = Math.max(12, Math.min(rect.left, window.innerWidth - measured.width - 12));
      const below = rect.bottom + 8;
      const top = below + measured.height <= window.innerHeight - 12 ? below : Math.max(12, rect.top - measured.height - 8);
      popover.style.left = left + "px";
      popover.style.top = top + "px";
    }
    function showFootnotePopover(button) {
      const ordinal = button.dataset.footnote;
      const definition = document.getElementById("fn-" + ordinal);
      const content = definition && definition.querySelector(".footnote-content");
      if (!content) return;
      previewTitle.textContent = localized("Footnote {ordinal}", { ordinal });
      previewMetadata.textContent = localized("Referenced footnote");
      previewMetadata.hidden = false;
      previewBody.replaceChildren(content.cloneNode(true));
      sanitizeInertContent(previewBody);
      positionPopover(button);
    }
    function showLinkPopover(link) {
      const key = link.dataset.sourceUtf16Start + ":" + link.dataset.sourceUtf16End;
      const preview = previewByRange.get(key);
      if (!preview) return;
      previewTitle.textContent = preview.title;
      previewMetadata.textContent = preview.fragment || "";
      previewMetadata.hidden = !preview.fragment;
      installInertDocumentContent(previewBody, preview);
      positionPopover(link);
    }
    function previewAnchorFor(target) {
      if (!(target instanceof Element)) return null;
      if (target.closest(".scholium-embedded-note")) return null;
      return target.closest(".footnote-reference, a.wiki-link");
    }
    function showPreviewFor(anchor) {
      if (anchor.matches(".footnote-reference")) {
        showFootnotePopover(anchor);
      } else if (anchor.matches("a.wiki-link")) {
        showLinkPopover(anchor);
      }
    }
    function remainsInsidePreviewAnchor(anchor, relatedTarget) {
      return relatedTarget instanceof Node && anchor.contains(relatedTarget);
    }
    document.addEventListener("pointerover", (event) => {
      const anchor = previewAnchorFor(event.target);
      if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
      cancelPopoverHide();
      showPreviewFor(anchor);
    });
    document.addEventListener("focusin", (event) => {
      const anchor = previewAnchorFor(event.target);
      if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
      cancelPopoverHide();
      showPreviewFor(anchor);
    });
    document.addEventListener("pointerout", (event) => {
      const anchor = previewAnchorFor(event.target);
      if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
      if (event.relatedTarget instanceof Node && popover.contains(event.relatedTarget)) {
        cancelPopoverHide();
      } else {
        schedulePopoverHide();
      }
    });
    document.addEventListener("focusout", (event) => {
      const anchor = previewAnchorFor(event.target);
      if (anchor && !remainsInsidePreviewAnchor(anchor, event.relatedTarget)) schedulePopoverHide();
    });
    popover.addEventListener("pointerenter", cancelPopoverHide);
    popover.addEventListener("pointerleave", schedulePopoverHide);
    window.addEventListener("scroll", hidePopover, { passive: true });
    window.addEventListener("resize", hidePopover);
    window.addEventListener("blur", hidePopover);
    renderEmbeddedNotes();
    document.addEventListener("click", (event) => {
      const eventElement = event.target instanceof Element ? event.target : null;
      const reference = eventElement?.closest(".footnote-reference");
      if (reference && !reference.disabled) {
        const ordinal = reference.dataset.footnote;
        const targetID = reference.dataset.target;
        const target = targetID ? document.getElementById(targetID) : null;
        if (target) {
          const origin = reference.closest(".footnote-reference-wrap") || reference;
          origins.set(ordinal, origin.id);
          target.tabIndex = -1;
          target.scrollIntoView({ block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
          target.focus({ preventScroll: true });
        }
        event.preventDefault();
        return;
      }
      const back = eventElement?.closest(".footnote-return");
      if (back) {
        const ordinal = back.dataset.footnote;
        const originID = origins.get(ordinal) || "fnref-" + ordinal + "-1";
        const origin = document.getElementById(originID);
        if (origin) {
          const focusTarget = origin.matches(".footnote-reference") ? origin : origin.querySelector(".footnote-reference");
          origin.scrollIntoView({ block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
          (focusTarget || origin).focus({ preventScroll: true });
        }
        event.preventDefault();
        return;
      }
      const link = eventElement?.closest('a[href^="scholium-note:"]');
      if (link) {
        const encoded = link.getAttribute("href")?.slice("scholium-note:".length) ?? "";
        post("internalLink", { target: decodeURIComponent(encoded) });
        event.preventDefault();
      }
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        hidePopover();
      }
    });
    readerWindow.scholiumSetReviewSelectionSurfaceActive = (active) => {
      const nextActive = Boolean(active);
      if (nextActive === reviewSelectionSurfaceActive) return true;
      reviewSelectionSurfaceActive = nextActive;
      reviewPointerSelectionActive = false;
      if (!nextActive) {
        reviewSelectionPresentation.clear();
        post("selectionChanged");
      }
      return true;
    };
    if (selectionEnabled) {
      const reviewDocument = document.getElementById("scholium-document");
      const reviewMermaidElements = reviewDocument ? [...reviewDocument.querySelectorAll('[data-scholium-protected="mermaid"]')] : [];
      const clearReviewSelection = () => {
        post("selectionChanged");
      };
      const nodeBelongsToMermaid = (node) => {
        const element = node instanceof Element ? node : node.parentElement;
        if (element?.closest?.('[data-scholium-protected="mermaid"]')) return true;
        const root = node.getRootNode();
        const shadowHost = root instanceof ShadowRoot ? root.host : null;
        return Boolean(shadowHost?.closest?.('[data-scholium-protected="mermaid"]'));
      };
      const rangeIntersectsMermaid = (range) => {
        if (nodeBelongsToMermaid(range.startContainer) || nodeBelongsToMermaid(range.endContainer)) return true;
        return reviewMermaidElements.some((element) => {
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
        if (rangeIntersectsMermaid(range)) {
          clearReviewSelection();
          return;
        }
        const text = boundedReviewRangeText(range, main, 2e3);
        if (!text) {
          clearReviewSelection();
          return;
        }
        const sourceElement = (range.startContainer instanceof Element ? range.startContainer : range.startContainer.parentElement)?.closest("[data-source-line]") ?? null;
        const endSourceElement = (range.endContainer instanceof Element ? range.endContainer : range.endContainer.parentElement)?.closest("[data-source-line]") ?? null;
        const startLine = Number(sourceElement ? sourceElement.dataset.sourceLine : "1");
        const endLine = Number(endSourceElement ? endSourceElement.dataset.sourceEndLine || endSourceElement.dataset.sourceLine : String(startLine));
        const payload = {
          text,
          contextBefore: reviewContextBefore(range, main, 80),
          contextAfter: reviewContextAfter(range, main, 80),
          startLine: Math.min(startLine, endLine),
          endLine: Math.max(startLine, endLine)
        };
        post("selectionChanged", payload);
      };
      document.addEventListener("selectionchange", updateReviewSelection);
      reviewDocument?.addEventListener("pointerdown", (event) => {
        if (!reviewSelectionSurfaceActive || event.button !== 0) return;
        reviewPointerSelectionActive = true;
      }, true);
      window.addEventListener("pointerup", (event) => {
        if (!reviewPointerSelectionActive || event.button !== 0) return;
        reviewPointerSelectionActive = false;
        queueMicrotask(updateReviewSelection);
      }, true);
      window.addEventListener("pointercancel", () => {
        reviewPointerSelectionActive = false;
      }, true);
      window.addEventListener("blur", () => {
        reviewPointerSelectionActive = false;
      });
    }
    const scrollBlockRegistry = (() => {
      const root = document.getElementById("scholium-document");
      const entries = [];
      const byElement = /* @__PURE__ */ new WeakMap();
      const byExactRange = /* @__PURE__ */ new Map();
      if (!root) return {
        root,
        entries,
        byElement,
        byExactRange,
        bySource: [],
        sourcePrefixMaximumUpper: []
      };
      const candidates = root.querySelectorAll(
        "[data-source-utf16-start][data-source-utf16-end]"
      );
      for (const element of candidates) {
        const lower = Number(element.dataset.sourceUtf16Start);
        const upper = Number(element.dataset.sourceUtf16End);
        if (!Number.isFinite(lower) || !Number.isFinite(upper) || upper < lower) continue;
        const style = getComputedStyle(element);
        if (style.display === "inline" || style.display === "contents" || style.display === "none" || style.visibility === "hidden") continue;
        const initialRect = element.getBoundingClientRect();
        if (initialRect.height <= 0) continue;
        const entry = { element, lower, upper, span: Math.max(0, upper - lower) };
        element.dataset.scholiumScrollAnchor = String(entries.length);
        entries.push(entry);
        byElement.set(element, entry);
        const key = lower + ":" + upper;
        const existing = byExactRange.get(key);
        if (!existing || entry.span < existing.span) byExactRange.set(key, entry);
      }
      const bySource = entries.slice().sort((left, right) => left.lower - right.lower || left.span - right.span);
      let maximumUpper = Number.NEGATIVE_INFINITY;
      const sourcePrefixMaximumUpper = bySource.map((entry) => {
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
    function scrollEntryForNode(node) {
      const root = scrollBlockRegistry.root;
      let element = node instanceof HTMLElement ? node : node?.parentElement ?? null;
      while (element && element !== root) {
        const entry = scrollBlockRegistry.byElement.get(element);
        if (entry) return entry;
        element = element.parentElement;
      }
      return null;
    }
    function scrollEntryAtProbe(probe) {
      const registry = scrollBlockRegistry;
      if (!registry.root || !registry.entries.length) return null;
      const rootRect = registry.root.getBoundingClientRect();
      const probeX = Math.max(1, Math.min(
        window.innerWidth - 1,
        rootRect.left + Math.max(1, rootRect.width / 2)
      ));
      let entry = scrollEntryForNode(document.elementFromPoint(probeX, probe));
      if (!entry && document.caretPositionFromPoint) {
        entry = scrollEntryForNode(document.caretPositionFromPoint(probeX, probe)?.offsetNode);
      }
      if (!entry && document.caretRangeFromPoint) {
        entry = scrollEntryForNode(document.caretRangeFromPoint(probeX, probe)?.startContainer);
      }
      if (entry) return entry;
      let low = 0;
      let high = registry.entries.length - 1;
      let nearestIndex = 0;
      let nearestDistance = Number.POSITIVE_INFINITY;
      while (low <= high) {
        const index = low + high >> 1;
        const candidate = registry.entries[index];
        const rect = candidate.element.getBoundingClientRect();
        const distance = rect.top <= probe && rect.bottom > probe ? 0 : Math.min(Math.abs(rect.top - probe), Math.abs(rect.bottom - probe));
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
        const distance = rect.top <= probe && rect.bottom > probe ? 0 : Math.min(Math.abs(rect.top - probe), Math.abs(rect.bottom - probe));
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = candidate;
        }
      }
      return nearest;
    }
    function scrollEntryForAnchor(anchor) {
      const offset = Number(anchor.sourceUTF16Offset);
      const lower = Number(anchor.blockUTF16LowerBound);
      const upper = Number(anchor.blockUTF16UpperBound);
      const exact = scrollBlockRegistry.byExactRange.get(lower + ":" + upper);
      if (exact) return exact;
      const entries = scrollBlockRegistry.bySource;
      let low = 0;
      let high = entries.length;
      while (low < high) {
        const middle = low + high >> 1;
        if (entries[middle].lower <= offset) low = middle + 1;
        else high = middle;
      }
      const insertion = low;
      let containing = null;
      for (let index = insertion - 1; index >= 0 && scrollBlockRegistry.sourcePrefixMaximumUpper[index] >= offset; index -= 1) {
        const candidate = entries[index];
        if (candidate.lower <= offset && candidate.upper >= offset && (!containing || candidate.span < containing.span)) containing = candidate;
      }
      if (containing) return containing;
      const before = entries[Math.max(0, insertion - 1)];
      const after = entries[Math.min(entries.length - 1, insertion)];
      if (!before) return after || null;
      if (!after) return before;
      return Math.abs(before.lower - offset) <= Math.abs(after.lower - offset) ? before : after;
    }
    function visibleScrollEntry(entry) {
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
    function currentReadScrollAnchor(fraction) {
      const probe = 8;
      const selected = scrollEntryAtProbe(probe);
      if (!selected) return null;
      const rect = selected.element.getBoundingClientRect();
      const relativeBlockPosition = Math.max(0, Math.min(
        1,
        (probe - rect.top) / Math.max(1, rect.height)
      ));
      const sourceUTF16Offset = Math.max(selected.lower, Math.min(
        selected.upper,
        Math.round(selected.lower + selected.span * relativeBlockPosition)
      ));
      return {
        sourceUTF16Offset,
        blockUTF16LowerBound: selected.lower,
        blockUTF16UpperBound: selected.upper,
        relativeBlockPosition,
        fallbackFraction: fraction
      };
    }
    function restoreReadScrollAnchor(anchor) {
      if (!anchor || typeof anchor !== "object") return false;
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
      const interiorOffset = height > 8 ? Math.max(4, Math.min(height - 4, requestedOffset)) : requestedOffset;
      const requestedTop = window.scrollY + rect.top + interiorOffset - 8;
      window.scrollTo({ top: Math.max(0, requestedTop), behavior: "auto" });
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
          visualOrderIsMonotonic
        };
      },
      current(fraction) {
        return currentReadScrollAnchor(fraction);
      },
      restore(anchor) {
        return restoreReadScrollAnchor(anchor);
      }
    };
    let scrollTimer;
    window.addEventListener("scroll", () => {
      clearTimeout(scrollTimer);
      scrollTimer = setTimeout(() => {
        const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
        const fraction = extent > 0 ? Math.max(0, Math.min(1, window.scrollY / extent)) : 0;
        post("scrollChanged", { fraction, anchor: currentReadScrollAnchor(fraction) });
      }, 120);
    }, { passive: true });
  }
  readerWindow.scholiumRead = {
    initialize(value) {
      const ready = initializeReader(value);
      readerWindow.scholiumReadReady = ready;
      return ready;
    }
  };
})();
