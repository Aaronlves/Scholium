"use strict";
(() => {
  // chat-reply-projection.ts
  function createReplyProjection(root) {
    let sourceNodes = [...root.childNodes].map((node) => node.cloneNode(true));
    let renderedNodes = [...root.childNodes];
    const commit = () => {
      renderedNodes = [...root.childNodes];
    };
    function patch(current, previous, next) {
      if (previous.isEqualNode(next)) return current;
      if (current.nodeType === 3 && next.nodeType === 3) {
        const text = current;
        const value = next.textContent || "";
        let prefix = 0;
        while (prefix < text.length && prefix < value.length && text.data[prefix] === value[prefix]) prefix++;
        text.replaceData(prefix, text.length - prefix, value.slice(prefix));
        return current;
      }
      if (current.nodeType === 1 && next.nodeType === 1 && current.isEqualNode(previous) && current.tagName === next.tagName) {
        const element = current;
        for (const attribute of [...element.attributes]) element.removeAttribute(attribute.name);
        for (const attribute of [...next.attributes]) element.setAttribute(attribute.name, attribute.value);
        const oldChildren = [...previous.childNodes];
        const children = [...current.childNodes];
        [...next.childNodes].forEach((child, index) => {
          const updated = children[index] ? patch(children[index], oldChildren[index], child) : child.cloneNode(true);
          if (!children[index]) current.appendChild(updated);
          else if (updated !== children[index]) current.replaceChild(updated, children[index]);
        });
        children.slice(next.childNodes.length).forEach((child) => child.parentNode?.removeChild(child));
        return current;
      }
      return next.cloneNode(true);
    }
    function apply(html) {
      const selection = root.ownerDocument.defaultView?.getSelection();
      const range = selection?.rangeCount && !selection.isCollapsed ? selection.getRangeAt(0) : null;
      const selected = range && root.contains(range.commonAncestorContainer) ? range.toString() : "";
      let offset = 0;
      let backward = false;
      if (selected && range && selection) {
        const before = range.cloneRange();
        before.selectNodeContents(root);
        before.setEnd(range.startContainer, range.startOffset);
        offset = before.toString().length;
        backward = selection.anchorNode === range.endContainer && selection.anchorOffset === range.endOffset;
      }
      const template = root.ownerDocument.createElement("template");
      template.innerHTML = html;
      const nextNodes = [...template.content.childNodes];
      nextNodes.forEach((next, index) => {
        const current = renderedNodes[index];
        const updated = current ? patch(current, sourceNodes[index], next) : next.cloneNode(true);
        if (!current) root.appendChild(updated);
        else if (updated !== current) root.replaceChild(updated, current);
      });
      renderedNodes.slice(nextNodes.length).forEach((node) => node.parentNode?.removeChild(node));
      sourceNodes = nextNodes.map((node) => node.cloneNode(true));
      commit();
      return () => {
        if (!selected || !selection || selection.toString() === selected) return;
        const text = root.textContent || "";
        if (text.slice(offset, offset + selected.length) !== selected) {
          const candidate = text.indexOf(selected);
          if (candidate < 0 || text.indexOf(selected, candidate + 1) >= 0) return;
          offset = candidate;
        }
        const walker = root.ownerDocument.createTreeWalker(root, 4);
        let position = 0;
        let start;
        let end;
        while (walker.nextNode()) {
          const node = walker.currentNode;
          if (!start && position + node.length >= offset) start = [node, offset - position];
          if (position + node.length >= offset + selected.length) {
            end = [node, offset + selected.length - position];
            break;
          }
          position += node.length;
        }
        if (start && end) selection.setBaseAndExtent(...backward ? end : start, ...backward ? start : end);
      };
    }
    return { apply, commit };
  }

  // attachment-presentation.ts
  var attachmentSymbols = {
    pdf: "doc-richtext",
    doc: "doc-text",
    docx: "doc-text",
    odt: "doc-text",
    rtf: "doc-text",
    txt: "doc-text",
    xls: "tablecells",
    xlsx: "tablecells",
    ods: "tablecells",
    numbers: "tablecells",
    csv: "tablecells",
    tsv: "tablecells",
    ppt: "rectangle-on-rectangle",
    pptx: "rectangle-on-rectangle",
    odp: "rectangle-on-rectangle",
    key: "rectangle-on-rectangle",
    png: "photo",
    jpg: "photo",
    jpeg: "photo",
    gif: "photo",
    webp: "photo",
    heic: "photo",
    heif: "photo",
    avif: "photo",
    tiff: "photo",
    tif: "photo",
    bmp: "photo",
    svg: "photo",
    ico: "photo",
    zip: "doc-zipper",
    gz: "doc-zipper",
    gzip: "doc-zipper",
    tar: "doc-zipper",
    tgz: "doc-zipper",
    bz2: "doc-zipper",
    xz: "doc-zipper",
    "7z": "doc-zipper",
    rar: "doc-zipper"
  };
  function attachmentSymbol(destination) {
    if (/[\u0000-\u001f\u007f]/.test(destination)) return null;
    let path = destination.trim();
    if (path.startsWith("<") && path.endsWith(">")) path = path.slice(1, -1);
    else if (path.startsWith("<") || path.endsWith(">")) return null;
    if (!path || path.startsWith("#")) return null;
    if (/^scholium-note:/i.test(path)) {
      path = path.slice("scholium-note:".length);
    }
    const scheme = /^([a-z][a-z\d+.-]*):/i.exec(path)?.[1].toLowerCase();
    if (scheme === "file") {
      try {
        const url = new URL(path);
        if (url.hostname && url.hostname !== "localhost") return null;
        path = url.pathname;
      } catch {
        return null;
      }
    } else if (scheme) {
      return null;
    }
    path = path.split(/[?#]/, 1)[0];
    try {
      path = decodeURIComponent(path);
    } catch {
      return null;
    }
    if (path.startsWith("#") || /\.(?:md|markdown)[?#]/i.test(path)) return null;
    if (!path || /[\u0000-\u001f\u007f]/.test(path) || path.startsWith("//") || path.endsWith("/") || /^[a-z][a-z\d+.-]*:/i.test(path)) return null;
    const filename = path.slice(path.lastIndexOf("/") + 1);
    const dot = filename.lastIndexOf(".");
    if (dot <= 0 || dot === filename.length - 1) return null;
    const extension = filename.slice(dot + 1).toLowerCase();
    if (extension === "md" || extension === "markdown") return null;
    return Object.hasOwn(attachmentSymbols, extension) ? attachmentSymbols[extension] : "paperclip";
  }
  function decorateAttachmentLinks(root) {
    root.querySelectorAll("a").forEach((anchor) => {
      const excluded = anchor.matches(".wiki-link, .scholium-embed") || anchor.closest(".scholium-embedded-note") !== null;
      const symbol = excluded ? null : attachmentSymbol(anchor.getAttribute("href") ?? "");
      if (symbol) {
        anchor.classList.add("scholium-attachment-link");
        anchor.dataset.scholiumAttachmentSymbol = symbol;
      } else {
        if (anchor.classList.contains("scholium-attachment-link")) {
          anchor.classList.remove("scholium-attachment-link");
        }
        delete anchor.dataset.scholiumAttachmentSymbol;
      }
    });
  }

  // chat-link-presentation.ts
  var noteID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  function chatWebsiteIconKey(href) {
    let url;
    try {
      url = new URL(href);
    } catch {
      return null;
    }
    if (url.protocol !== "https:" && url.protocol !== "http:") return null;
    const host = url.hostname.toLowerCase();
    return host === "openai.com" || host.endsWith(".openai.com") || host === "chatgpt.com" || host.endsWith(".chatgpt.com") ? "openai" : null;
  }
  function chatLinkSymbol(href) {
    let destination = href;
    if (href.toLowerCase().startsWith("scholium-note:") && !href.toLowerCase().startsWith("scholium-note://")) {
      try {
        destination = decodeURIComponent(href.slice("scholium-note:".length));
      } catch {
        return null;
      }
    }
    let url;
    try {
      url = new URL(destination);
    } catch {
      return null;
    }
    const scheme = url.protocol.toLowerCase();
    if (scheme === "scholium-note:") {
      return noteID.test(url.hostname) && (url.pathname === "" || url.pathname === "/") && !url.username && !url.password && !url.hash ? "doc-text" : null;
    }
    if (scheme === "zotero:") return "books-vertical";
    if (scheme !== "https:" && scheme !== "http:") return null;
    if (!url.hostname) return null;
    if (/\.(?:md|markdown)$/i.test(url.pathname)) return "doc-text";
    const fileSymbol = attachmentSymbol(url.pathname);
    return fileSymbol && fileSymbol !== "paperclip" ? fileSymbol : "globe";
  }
  function decorateChatReplyLinks(root) {
    root.querySelectorAll("a").forEach((anchor) => {
      const embedded = anchor.matches(".scholium-embed") || anchor.closest(".scholium-embedded-note") !== null;
      const symbol = embedded ? null : chatLinkSymbol(anchor.getAttribute("href") ?? "");
      if (symbol) {
        anchor.dataset.scholiumChatLinkSymbol = symbol;
        anchor.classList.add("scholium-chat-link");
        const websiteIcon = symbol === "globe" ? chatWebsiteIconKey(anchor.getAttribute("href") ?? "") : null;
        if (websiteIcon) anchor.dataset.scholiumChatWebsiteIcon = websiteIcon;
        else delete anchor.dataset.scholiumChatWebsiteIcon;
      } else {
        delete anchor.dataset.scholiumChatLinkSymbol;
        delete anchor.dataset.scholiumChatWebsiteIcon;
        anchor.classList.remove("scholium-chat-link");
      }
      anchor.classList.remove("scholium-attachment-link");
      delete anchor.dataset.scholiumAttachmentSymbol;
    });
  }

  // chat-reply.ts
  function installChatReply(root, post) {
    const quote = () => {
      const selection = window.getSelection();
      if (!selection?.rangeCount || selection.isCollapsed || !root.contains(selection.anchorNode) || !root.contains(selection.focusNode)) return;
      const text = selection.toString();
      if (text.trim() && new TextEncoder().encode(text).length <= 65536) post("replyQuote", { text });
    };
    const keydown = (event) => {
      if (event.metaKey && event.shiftKey && !event.altKey && !event.ctrlKey && event.key.toLowerCase() === "r") {
        event.preventDefault();
        quote();
      }
    };
    const noteContextMenu = (event) => {
      const selection = window.getSelection();
      if (selection?.rangeCount && !selection.isCollapsed && root.contains(selection.anchorNode) && root.contains(selection.focusNode) && [...selection.getRangeAt(0).getClientRects()].some((rect) => event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom)) {
        const text = selection.toString();
        if (text.trim() && new TextEncoder().encode(text).length <= 65536) {
          event.preventDefault();
          event.stopPropagation();
          post("replySelectionContext", { text, left: event.clientX, top: event.clientY });
          return;
        }
      }
      const anchor = event.target instanceof Element ? event.target.closest("a[href]") : null;
      if (!anchor || !root.contains(anchor) || anchor.protocol !== "scholium-note:") return;
      let url;
      try {
        url = decodeURIComponent((anchor.getAttribute("href") || "").slice("scholium-note:".length));
      } catch {
        return;
      }
      if (!url.startsWith("scholium-note://")) return;
      event.preventDefault();
      event.stopPropagation();
      post("replyNoteContext", { url, left: event.clientX, top: event.clientY });
    };
    const interact = () => post("replyInteraction", {});
    const dragstart = (event) => {
      const selection = window.getSelection();
      if (!event.dataTransfer || !selection || selection.isCollapsed || selection.rangeCount !== 1 || !root.contains(selection.anchorNode) || !root.contains(selection.focusNode)) return;
      if (![...selection.getRangeAt(0).getClientRects()].some((rect) => event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom)) return;
      const text = selection.toString();
      if (!text) return;
      event.dataTransfer.clearData();
      event.dataTransfer.setData("text/plain", text);
      event.dataTransfer.effectAllowed = "copy";
      interact();
    };
    const selected = () => {
      const selection = window.getSelection();
      if (selection && !selection.isCollapsed && root.contains(selection.anchorNode)) interact();
    };
    root.addEventListener("pointerdown", interact);
    root.addEventListener("keydown", interact);
    root.ownerDocument.addEventListener("selectionchange", selected);
    root.addEventListener("contextmenu", noteContextMenu);
    root.addEventListener("keydown", keydown);
    root.addEventListener("dragstart", dragstart);
    root.tabIndex = 0;
    const decorateObjects = () => {
      root.querySelectorAll("[data-scholium-object]").forEach((element) => {
        if (element.parentElement?.closest("[data-scholium-object]")) return;
        if (element.closest(".scholium-reply-object")) return;
        const wrapper = document.createElement("div");
        wrapper.className = "scholium-reply-object";
        wrapper.dataset.replyIdentity = element.dataset.scholiumObject;
        const controls = document.createElement("div");
        controls.className = "scholium-reply-controls";
        controls.setAttribute("aria-hidden", "true");
        const tableScroller = element.parentElement?.classList.contains("scholium-table-scroll") ? element.parentElement : null;
        if (tableScroller) {
          tableScroller.before(wrapper);
          wrapper.append(controls, tableScroller);
        } else {
          const scroller = document.createElement("div");
          scroller.className = "scholium-reply-object-scroll";
          element.before(wrapper);
          wrapper.append(controls, scroller);
          scroller.append(element);
        }
      });
    };
    decorateObjects();
    const reportSize = () => {
      let intrinsicWidth = null;
      const paragraph = root.firstElementChild;
      if (root.children.length === 1 && paragraph instanceof HTMLElement && paragraph.tagName === "P" && !paragraph.querySelector("img, svg, .katex, br")) {
        const width = paragraph.style.width;
        const maximum = paragraph.style.maxWidth;
        paragraph.style.width = "max-content";
        paragraph.style.maxWidth = "none";
        intrinsicWidth = Math.ceil(paragraph.getBoundingClientRect().width);
        paragraph.style.width = width;
        paragraph.style.maxWidth = maximum;
      }
      const objects = [...root.querySelectorAll(".scholium-reply-object")].map((wrapper) => {
        const element = wrapper.querySelector("[data-scholium-object]");
        const rect = wrapper.getBoundingClientRect();
        const svg = element.querySelector(".scholium-mermaid-output")?.shadowRoot?.querySelector("svg");
        const box = svg?.viewBox.baseVal;
        return {
          identity: wrapper.dataset.replyIdentity,
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          naturalWidth: box?.width || Math.max(1, element.scrollWidth),
          naturalHeight: box?.height || Math.max(1, element.getBoundingClientRect().height)
        };
      });
      post("replyLayout", { height: Math.ceil(root.getBoundingClientRect().height), intrinsicWidth, objects });
    };
    const observer = new ResizeObserver(reportSize);
    observer.observe(root);
    reportSize();
    const dispose = () => {
      observer.disconnect();
      root.removeEventListener("keydown", keydown);
      root.removeEventListener("contextmenu", noteContextMenu);
      root.removeEventListener("dragstart", dragstart);
      root.removeEventListener("pointerdown", interact);
      root.removeEventListener("keydown", interact);
      root.ownerDocument.removeEventListener("selectionchange", selected);
    };
    return Object.assign(dispose, { refresh: () => {
      decorateObjects();
      reportSize();
    } });
  }

  // selection-actions.ts
  function createSelectionActions(floating, current) {
    let id = null;
    let key = null;
    let dismissed = null;
    function hide() {
      if (id !== null) floating.hide(id);
      id = null;
      key = null;
    }
    function dismiss() {
      const visible = id !== null;
      if (key !== null) dismissed = key;
      hide();
      return visible;
    }
    return {
      dismiss,
      update(target = current()) {
        if (!target) {
          hide();
          dismissed = null;
          return;
        }
        if (target.key === key || target.key === dismissed) return;
        hide();
        key = target.key;
        id = floating.show({ ...target.anchor }, {
          dismiss,
          choose: () => {
            const valid = current()?.key === target.key;
            return valid;
          }
        });
      }
    };
  }

  // arrival-highlight.ts
  var arrivalDuration = 1400;
  var arrivalClass = "scholium-arrival-target";
  function sourceRangeElement(root, lower, upper) {
    if (!Number.isSafeInteger(lower) || !Number.isSafeInteger(upper) || lower < 0 || upper <= lower || upper - lower > 32e3) return;
    return [...root.querySelectorAll("[data-source-utf16-start][data-source-utf16-end]")].filter((element) => Number(element.dataset.sourceUtf16Start) <= lower && Number(element.dataset.sourceUtf16End) >= upper && (element.textContent?.length ?? 0) <= 64e3).sort((a, b) => Number(a.dataset.sourceUtf16End) - Number(a.dataset.sourceUtf16Start) - (Number(b.dataset.sourceUtf16End) - Number(b.dataset.sourceUtf16Start)))[0];
  }
  function readerSourceRangeCandidate(root, lower, upper) {
    const element = sourceRangeElement(root, lower, upper);
    return element ? {
      blockLower: Number(element.dataset.sourceUtf16Start),
      blockUpper: Number(element.dataset.sourceUtf16End),
      blockText: element.textContent ?? ""
    } : null;
  }
  function createReaderArrival(root) {
    let marker = null;
    let generation = 0;
    let timer;
    const owner = root.ownerDocument.defaultView;
    function clear() {
      generation += 1;
      clearTimeout(timer);
      timer = void 0;
      marker?.remove();
      marker = null;
    }
    const span = (element) => Number(element.dataset.sourceUtf16End ?? 0) - Number(element.dataset.sourceUtf16Start ?? 0);
    async function reveal(line) {
      clear();
      const requestGeneration = generation;
      if (!Number.isSafeInteger(line) || line < 1 || !owner) return false;
      const candidates = [...root.querySelectorAll("[data-source-line]")].filter((element) => Number(element.dataset.sourceLine) <= line && Number(element.dataset.sourceEndLine ?? element.dataset.sourceLine) >= line).sort((a, b) => Number(Number(b.dataset.sourceLine) === line) - Number(Number(a.dataset.sourceLine) === line) || span(a) - span(b));
      const target = candidates[0];
      if (!target) return false;
      const reduceMotion = typeof owner.matchMedia === "function" && owner.matchMedia("(prefers-reduced-motion: reduce)").matches;
      const extent = Math.max(0, root.ownerDocument.documentElement.scrollHeight - owner.innerHeight);
      const destination = Math.max(0, Math.min(extent, owner.scrollY + target.getBoundingClientRect().top));
      if (!reduceMotion && Math.abs(destination - owner.scrollY) > owner.innerHeight) {
        const travel = Math.sign(destination - owner.scrollY) * owner.innerHeight;
        owner.scrollTo({ top: destination - travel, behavior: "auto" });
      }
      target.scrollIntoView({
        block: "start",
        behavior: reduceMotion ? "auto" : "smooth"
      });
      const deadline = Date.now() + 2e3;
      while (Math.abs(owner.scrollY - destination) > 1) {
        if (generation !== requestGeneration || Date.now() >= deadline) return false;
        await new Promise((resolve) => setTimeout(resolve, 16));
      }
      if (generation !== requestGeneration || !target.isConnected) return false;
      const range = root.ownerDocument.createRange();
      range.selectNodeContents(target);
      const rect = [...range.getClientRects()].find((rect2) => rect2.width > 0 && rect2.height > 0);
      if (!rect) return false;
      const block = target.closest("p, li, pre, td, th, h1, h2, h3, h4, h5, h6") ?? target;
      const bounds = block.getBoundingClientRect();
      const height = Math.max(rect.height, parseFloat(owner.getComputedStyle(block).lineHeight) || 0);
      marker = root.ownerDocument.createElement("div");
      marker.className = arrivalClass + " scholium-reader-arrival";
      marker.setAttribute("aria-hidden", "true");
      marker.dataset.arrivalLine = String(line);
      Object.assign(marker.style, {
        position: "absolute",
        pointerEvents: "none",
        left: `${bounds.left + owner.scrollX}px`,
        top: `${rect.top + owner.scrollY - (height - rect.height) / 2}px`,
        width: `${bounds.width}px`,
        height: `${height}px`
      });
      root.ownerDocument.body.appendChild(marker);
      timer = setTimeout(clear, arrivalDuration);
      return true;
    }
    owner?.addEventListener("resize", clear);
    function destroy() {
      clear();
      owner?.removeEventListener("resize", clear);
    }
    function revealRange(lower, upper, expected) {
      const target = sourceRangeElement(root, lower, upper);
      const candidate = readerSourceRangeCandidate(root, lower, upper);
      if (!owner || !target || !candidate || candidate.blockLower !== expected.blockLower || candidate.blockUpper !== expected.blockUpper || candidate.blockText !== expected.blockText) return false;
      const from = lower - candidate.blockLower, to = upper - candidate.blockLower;
      if (from < 0 || to > candidate.blockText.length) return false;
      const walker = root.ownerDocument.createTreeWalker(
        target,
        4
        /* SHOW_TEXT */
      );
      let offset = 0, start, end;
      while (walker.nextNode()) {
        const node = walker.currentNode, length = node.textContent?.length ?? 0;
        if (!start && from >= offset && from <= offset + length) start = [node, from - offset];
        if (!end && to >= offset && to <= offset + length) end = [node, to - offset];
        offset += length;
      }
      if (!start || !end) return false;
      const range = root.ownerDocument.createRange();
      range.setStart(...start);
      range.setEnd(...end);
      if (range.toString() !== candidate.blockText.slice(from, to)) return false;
      const selection = owner.getSelection();
      if (!selection) return false;
      clear();
      selection.removeAllRanges();
      selection.addRange(range);
      const rect = range.getBoundingClientRect();
      owner.scrollBy({ top: rect.top - owner.innerHeight / 3, behavior: "auto" });
      return true;
    }
    return { reveal, rangeCandidate: (lower, upper) => readerSourceRangeCandidate(root, lower, upper), revealRange, clear, destroy };
  }

  // native-floating.ts
  function createNativeFloatingPorts(post) {
    let serial = 0;
    let active = null;
    function activate(kind, callbacks, event2) {
      if (active && active.kind !== kind) active.dismiss();
      const id = ++serial;
      active = { kind, id, dismiss: callbacks.dismiss, event: event2 };
      return id;
    }
    function hide(kind, id) {
      if (active?.kind !== kind || active.id !== id) return;
      post({ type: "dismissSurface", kind, id });
      active = null;
    }
    const preview = {
      show(surface, callbacks) {
        const id = activate("preview", callbacks, (currentID, action, _index) => {
          if (currentID !== id) return false;
          if (action === "enter") callbacks.enter?.();
          else if (action === "leave") callbacks.leave?.();
          else if (action === "dismiss") callbacks.dismiss();
          else return false;
          return true;
        });
        post({ type: "previewSurface", surface: { ...surface, id } });
        return id;
      },
      hide(id) {
        hide("preview", id);
      }
    };
    const suggestions = {
      show(surface, callbacks) {
        const id = activate("suggestions", callbacks, (currentID, action, index) => {
          if (currentID !== id || !Number.isInteger(index)) return false;
          if (action === "dismiss") callbacks.dismiss();
          else if (action === "select" && index >= 0 && index < surface.items.length) callbacks.select?.(index);
          else if (action === "choose" && index >= 0 && index < surface.items.length) {
            return callbacks.choose?.(index) !== false;
          } else return false;
          return true;
        });
        post({ type: "suggestionSurface", surface: { ...surface, id } });
        return id;
      },
      hide(id) {
        hide("suggestions", id);
      }
    };
    const selection = {
      show(surface, callbacks) {
        const id = activate("selection", callbacks, (currentID, action, index) => {
          if (currentID !== id) return false;
          if (action === "dismiss") callbacks.dismiss();
          else if (action === "choose" && index === 0) return callbacks.choose?.(index) !== false;
          else return false;
          return true;
        });
        post({ type: "selectionSurface", surface: { ...surface, id } });
        return id;
      },
      hide(id) {
        hide("selection", id);
      }
    };
    const event = (id, action, index) => active?.id === id ? active.event(id, action, index) : false;
    window.scholiumNativeFloatingEvent = event;
    return { preview, suggestions, selection };
  }
  function previewSurface(anchor, root) {
    const css = Array.from(document.querySelectorAll("style"), (node) => node.textContent ?? "").join("\n");
    return {
      left: anchor.left,
      top: anchor.top,
      bottom: anchor.bottom,
      html: root.innerHTML,
      css
    };
  }

  // node_modules/@marijn/find-cluster-break/src/index.js
  var rangeFrom = [];
  var rangeTo = [];
  (() => {
    let numbers = "lc,34,7n,7,7b,19,,,,2,,2,,,20,b,1c,l,g,,2t,7,2,6,2,2,,4,z,,u,r,2j,b,1m,9,9,,o,4,,9,,3,,5,17,3,3b,f,,w,1j,,,,4,8,4,,3,7,a,2,t,,1m,,,,2,4,8,,9,,a,2,q,,2,2,1l,,4,2,4,2,2,3,3,,u,2,3,,b,2,1l,,4,5,,2,4,,k,2,m,6,,,1m,,,2,,4,8,,7,3,a,2,u,,1n,,,,c,,9,,14,,3,,1l,3,5,3,,4,7,2,b,2,t,,1m,,2,,2,,3,,5,2,7,2,b,2,s,2,1l,2,,,2,4,8,,9,,a,2,t,,20,,4,,2,3,,,8,,29,,2,7,c,8,2q,,2,9,b,6,22,2,r,,,,,,1j,e,,5,,2,5,b,,10,9,,2u,4,,6,,2,2,2,p,2,4,3,g,4,d,,2,2,6,,f,,jj,3,qa,3,t,3,t,2,u,2,1s,2,,7,8,,2,b,9,,19,3,3b,2,y,,3a,3,4,2,9,,6,3,63,2,2,,1m,,,7,,,,,2,8,6,a,2,,1c,h,1r,4,1c,7,,,5,,14,9,c,2,w,4,2,2,,3,1k,,,2,3,,,3,1m,8,2,2,48,3,,d,,7,4,,6,,3,2,5i,1m,,5,ek,,5f,x,2da,3,3x,,2o,w,fe,6,2x,2,n9w,4,,a,w,2,28,2,7k,,3,,4,,p,2,5,,47,2,q,i,d,,12,8,p,b,1a,3,1c,,2,4,2,2,13,,1v,6,2,2,2,2,c,,8,,1b,,1f,,,3,2,2,5,2,,,16,2,8,,6m,,2,,4,,fn4,,kh,g,g,g,a6,2,gt,,6a,,45,5,1ae,3,,2,5,4,14,3,4,,4l,2,fx,4,ar,2,49,b,4w,,1i,f,1k,3,1d,4,2,2,1x,3,10,5,,8,1q,,c,2,1g,9,a,4,2,,2n,3,2,,,2,6,,4g,,3,8,l,2,1l,2,,,,,m,,e,7,3,5,5f,8,2,3,,,n,,29,,2,6,,,2,,,2,,2,6j,,2,4,6,2,,2,r,2,2d,8,2,,,2,2y,,,,2,6,,,2t,3,2,4,,5,77,9,,2,6t,,a,2,,,4,,40,4,2,2,4,,w,a,14,6,2,4,8,,9,6,2,3,1a,d,,2,ba,7,,6,,,2a,m,2,7,,2,,2,3e,6,3,,,2,,7,,,20,2,3,,,,9n,2,f0b,5,1n,7,t4,,1r,4,29,,f5k,2,43q,,,3,4,5,8,8,2,7,u,4,44,3,1iz,1j,4,1e,8,,e,,m,5,,f,11s,7,,h,2,7,,2,,5,79,7,c5,4,15s,7,31,7,240,5,gx7k,2o,3k,6o".split(",").map((s) => s ? parseInt(s, 36) : 1);
    for (let i = 0, n = 0; i < numbers.length; i++)
      (i % 2 ? rangeTo : rangeFrom).push(n = n + numbers[i]);
  })();
  function isExtendingChar(code) {
    if (code < 768) return false;
    for (let from = 0, to = rangeFrom.length; ; ) {
      let mid = from + to >> 1;
      if (code < rangeFrom[mid]) to = mid;
      else if (code >= rangeTo[mid]) from = mid + 1;
      else return true;
      if (from == to) return false;
    }
  }
  function isRegionalIndicator(code) {
    return code >= 127462 && code <= 127487;
  }
  var ZWJ = 8205;
  function findClusterBreak(str, pos, forward = true, includeExtending = true) {
    return (forward ? nextClusterBreak : prevClusterBreak)(str, pos, includeExtending);
  }
  function nextClusterBreak(str, pos, includeExtending) {
    if (pos == str.length) return pos;
    if (pos && surrogateLow(str.charCodeAt(pos)) && surrogateHigh(str.charCodeAt(pos - 1))) pos--;
    let prev = codePointAt(str, pos);
    pos += codePointSize(prev);
    while (pos < str.length) {
      let next = codePointAt(str, pos);
      if (prev == ZWJ || next == ZWJ || includeExtending && isExtendingChar(next)) {
        pos += codePointSize(next);
        prev = next;
      } else if (isRegionalIndicator(next)) {
        let countBefore = 0, i = pos - 2;
        while (i >= 0 && isRegionalIndicator(codePointAt(str, i))) {
          countBefore++;
          i -= 2;
        }
        if (countBefore % 2 == 0) break;
        else pos += 2;
      } else {
        break;
      }
    }
    return pos;
  }
  function prevClusterBreak(str, pos, includeExtending) {
    while (pos > 1) {
      let found = nextClusterBreak(str, pos - 2, includeExtending);
      if (found < pos) return found;
      pos--;
    }
    return 0;
  }
  function codePointAt(str, pos) {
    let code0 = str.charCodeAt(pos);
    if (!surrogateHigh(code0) || pos + 1 == str.length) return code0;
    let code1 = str.charCodeAt(pos + 1);
    if (!surrogateLow(code1)) return code0;
    return (code0 - 55296 << 10) + (code1 - 56320) + 65536;
  }
  function surrogateLow(ch) {
    return ch >= 56320 && ch < 57344;
  }
  function surrogateHigh(ch) {
    return ch >= 55296 && ch < 56320;
  }
  function codePointSize(code) {
    return code < 65536 ? 1 : 2;
  }

  // node_modules/@codemirror/state/dist/index.js
  var Text2 = class _Text {
    /**
    Get the line description around the given position.
    */
    lineAt(pos) {
      if (pos < 0 || pos > this.length)
        throw new RangeError(`Invalid position ${pos} in document of length ${this.length}`);
      return this.lineInner(pos, false, 1, 0);
    }
    /**
    Get the description for the given (1-based) line number.
    */
    line(n) {
      if (n < 1 || n > this.lines)
        throw new RangeError(`Invalid line number ${n} in ${this.lines}-line document`);
      return this.lineInner(n, true, 1, 0);
    }
    /**
    Replace a range of the text with the given content.
    */
    replace(from, to, text) {
      [from, to] = clip(this, from, to);
      let parts = [];
      this.decompose(
        0,
        from,
        parts,
        2
        /* Open.To */
      );
      if (text.length)
        text.decompose(
          0,
          text.length,
          parts,
          1 | 2
          /* Open.To */
        );
      this.decompose(
        to,
        this.length,
        parts,
        1
        /* Open.From */
      );
      return TextNode.from(parts, this.length - (to - from) + text.length);
    }
    /**
    Append another document to this one.
    */
    append(other) {
      return this.replace(this.length, this.length, other);
    }
    /**
    Retrieve the text between the given points.
    */
    slice(from, to = this.length) {
      [from, to] = clip(this, from, to);
      let parts = [];
      this.decompose(from, to, parts, 0);
      return TextNode.from(parts, to - from);
    }
    /**
    Test whether this text is equal to another instance.
    */
    eq(other) {
      if (other == this)
        return true;
      if (other.length != this.length || other.lines != this.lines)
        return false;
      let start = this.scanIdentical(other, 1), end = this.length - this.scanIdentical(other, -1);
      let a = new RawTextCursor(this), b = new RawTextCursor(other);
      for (let skip = start, pos = start; ; ) {
        a.next(skip);
        b.next(skip);
        skip = 0;
        if (a.lineBreak != b.lineBreak || a.done != b.done || a.value != b.value)
          return false;
        pos += a.value.length;
        if (a.done || pos >= end)
          return true;
      }
    }
    /**
    Iterate over the text. When `dir` is `-1`, iteration happens
    from end to start. This will return lines and the breaks between
    them as separate strings.
    */
    iter(dir = 1) {
      return new RawTextCursor(this, dir);
    }
    /**
    Iterate over a range of the text. When `from` > `to`, the
    iterator will run in reverse.
    */
    iterRange(from, to = this.length) {
      return new PartialTextCursor(this, from, to);
    }
    /**
    Return a cursor that iterates over the given range of lines,
    _without_ returning the line breaks between, and yielding empty
    strings for empty lines.
    
    When `from` and `to` are given, they should be 1-based line numbers.
    */
    iterLines(from, to) {
      let inner;
      if (from == null) {
        inner = this.iter();
      } else {
        if (to == null)
          to = this.lines + 1;
        let start = this.line(from).from;
        inner = this.iterRange(start, Math.max(start, to == this.lines + 1 ? this.length : to <= 1 ? 0 : this.line(to - 1).to));
      }
      return new LineCursor(inner);
    }
    /**
    Return the document as a string, using newline characters to
    separate lines.
    */
    toString() {
      return this.sliceString(0);
    }
    /**
    Convert the document to an array of lines (which can be
    deserialized again via [`Text.of`](https://codemirror.net/6/docs/ref/#state.Text^of)).
    */
    toJSON() {
      let lines = [];
      this.flatten(lines);
      return lines;
    }
    /**
    @internal
    */
    constructor() {
    }
    /**
    Create a `Text` instance for the given array of lines.
    */
    static of(text) {
      if (text.length == 0)
        throw new RangeError("A document must have at least one line");
      if (text.length == 1 && !text[0])
        return _Text.empty;
      return text.length <= 32 ? new TextLeaf(text) : TextNode.from(TextLeaf.split(text, []));
    }
  };
  var TextLeaf = class _TextLeaf extends Text2 {
    constructor(text, length = textLength(text)) {
      super();
      this.text = text;
      this.length = length;
    }
    get lines() {
      return this.text.length;
    }
    get children() {
      return null;
    }
    lineInner(target, isLine, line, offset) {
      for (let i = 0; ; i++) {
        let string = this.text[i], end = offset + string.length;
        if ((isLine ? line : end) >= target)
          return new Line(offset, end, line, string);
        offset = end + 1;
        line++;
      }
    }
    decompose(from, to, target, open) {
      let text = from <= 0 && to >= this.length ? this : new _TextLeaf(sliceText(this.text, from, to), Math.min(to, this.length) - Math.max(0, from));
      if (open & 1) {
        let prev = target.pop();
        let joined = appendText(text.text, prev.text.slice(), 0, text.length);
        if (joined.length <= 32) {
          target.push(new _TextLeaf(joined, prev.length + text.length));
        } else {
          let mid = joined.length >> 1;
          target.push(new _TextLeaf(joined.slice(0, mid)), new _TextLeaf(joined.slice(mid)));
        }
      } else {
        target.push(text);
      }
    }
    replace(from, to, text) {
      if (!(text instanceof _TextLeaf))
        return super.replace(from, to, text);
      [from, to] = clip(this, from, to);
      let lines = appendText(this.text, appendText(text.text, sliceText(this.text, 0, from)), to);
      let newLen = this.length + text.length - (to - from);
      if (lines.length <= 32)
        return new _TextLeaf(lines, newLen);
      return TextNode.from(_TextLeaf.split(lines, []), newLen);
    }
    sliceString(from, to = this.length, lineSep = "\n") {
      [from, to] = clip(this, from, to);
      let result = "";
      for (let pos = 0, i = 0; pos <= to && i < this.text.length; i++) {
        let line = this.text[i], end = pos + line.length;
        if (pos > from && i)
          result += lineSep;
        if (from < end && to > pos)
          result += line.slice(Math.max(0, from - pos), to - pos);
        pos = end + 1;
      }
      return result;
    }
    flatten(target) {
      for (let line of this.text)
        target.push(line);
    }
    scanIdentical() {
      return 0;
    }
    static split(text, target) {
      let part = [], len = -1;
      for (let line of text) {
        part.push(line);
        len += line.length + 1;
        if (part.length == 32) {
          target.push(new _TextLeaf(part, len));
          part = [];
          len = -1;
        }
      }
      if (len > -1)
        target.push(new _TextLeaf(part, len));
      return target;
    }
  };
  var TextNode = class _TextNode extends Text2 {
    constructor(children, length) {
      super();
      this.children = children;
      this.length = length;
      this.lines = 0;
      for (let child of children)
        this.lines += child.lines;
    }
    lineInner(target, isLine, line, offset) {
      for (let i = 0; ; i++) {
        let child = this.children[i], end = offset + child.length, endLine = line + child.lines - 1;
        if ((isLine ? endLine : end) >= target)
          return child.lineInner(target, isLine, line, offset);
        offset = end + 1;
        line = endLine + 1;
      }
    }
    decompose(from, to, target, open) {
      for (let i = 0, pos = 0; pos <= to && i < this.children.length; i++) {
        let child = this.children[i], end = pos + child.length;
        if (from <= end && to >= pos) {
          let childOpen = open & ((pos <= from ? 1 : 0) | (end >= to ? 2 : 0));
          if (pos >= from && end <= to && !childOpen)
            target.push(child);
          else
            child.decompose(from - pos, to - pos, target, childOpen);
        }
        pos = end + 1;
      }
    }
    replace(from, to, text) {
      [from, to] = clip(this, from, to);
      if (text.lines < this.lines)
        for (let i = 0, pos = 0; i < this.children.length; i++) {
          let child = this.children[i], end = pos + child.length;
          if (from >= pos && to <= end) {
            let updated = child.replace(from - pos, to - pos, text);
            let totalLines = this.lines - child.lines + updated.lines;
            if (updated.lines < totalLines >> 5 - 1 && updated.lines > totalLines >> 5 + 1) {
              let copy = this.children.slice();
              copy[i] = updated;
              return new _TextNode(copy, this.length - (to - from) + text.length);
            }
            return super.replace(pos, end, updated);
          }
          pos = end + 1;
        }
      return super.replace(from, to, text);
    }
    sliceString(from, to = this.length, lineSep = "\n") {
      [from, to] = clip(this, from, to);
      let result = "";
      for (let i = 0, pos = 0; i < this.children.length && pos <= to; i++) {
        let child = this.children[i], end = pos + child.length;
        if (pos > from && i)
          result += lineSep;
        if (from < end && to > pos)
          result += child.sliceString(from - pos, to - pos, lineSep);
        pos = end + 1;
      }
      return result;
    }
    flatten(target) {
      for (let child of this.children)
        child.flatten(target);
    }
    scanIdentical(other, dir) {
      if (!(other instanceof _TextNode))
        return 0;
      let length = 0;
      let [iA, iB, eA, eB] = dir > 0 ? [0, 0, this.children.length, other.children.length] : [this.children.length - 1, other.children.length - 1, -1, -1];
      for (; ; iA += dir, iB += dir) {
        if (iA == eA || iB == eB)
          return length;
        let chA = this.children[iA], chB = other.children[iB];
        if (chA != chB)
          return length + chA.scanIdentical(chB, dir);
        length += chA.length + 1;
      }
    }
    static from(children, length = children.reduce((l, ch) => l + ch.length + 1, -1)) {
      let lines = 0;
      for (let ch of children)
        lines += ch.lines;
      if (lines < 32) {
        let flat = [];
        for (let ch of children)
          ch.flatten(flat);
        return new TextLeaf(flat, length);
      }
      let chunk = Math.max(
        32,
        lines >> 5
        /* Tree.BranchShift */
      ), maxChunk = chunk << 1, minChunk = chunk >> 1;
      let chunked = [], currentLines = 0, currentLen = -1, currentChunk = [];
      function add(child) {
        let last;
        if (child.lines > maxChunk && child instanceof _TextNode) {
          for (let node of child.children)
            add(node);
        } else if (child.lines > minChunk && (currentLines > minChunk || !currentLines)) {
          flush();
          chunked.push(child);
        } else if (child instanceof TextLeaf && currentLines && (last = currentChunk[currentChunk.length - 1]) instanceof TextLeaf && child.lines + last.lines <= 32) {
          currentLines += child.lines;
          currentLen += child.length + 1;
          currentChunk[currentChunk.length - 1] = new TextLeaf(last.text.concat(child.text), last.length + 1 + child.length);
        } else {
          if (currentLines + child.lines > chunk)
            flush();
          currentLines += child.lines;
          currentLen += child.length + 1;
          currentChunk.push(child);
        }
      }
      function flush() {
        if (currentLines == 0)
          return;
        chunked.push(currentChunk.length == 1 ? currentChunk[0] : _TextNode.from(currentChunk, currentLen));
        currentLen = -1;
        currentLines = currentChunk.length = 0;
      }
      for (let child of children)
        add(child);
      flush();
      return chunked.length == 1 ? chunked[0] : new _TextNode(chunked, length);
    }
  };
  Text2.empty = /* @__PURE__ */ new TextLeaf([""], 0);
  function textLength(text) {
    let length = -1;
    for (let line of text)
      length += line.length + 1;
    return length;
  }
  function appendText(text, target, from = 0, to = 1e9) {
    for (let pos = 0, i = 0, first = true; i < text.length && pos <= to; i++) {
      let line = text[i], end = pos + line.length;
      if (end >= from) {
        if (end > to)
          line = line.slice(0, to - pos);
        if (pos < from)
          line = line.slice(from - pos);
        if (first) {
          target[target.length - 1] += line;
          first = false;
        } else
          target.push(line);
      }
      pos = end + 1;
    }
    return target;
  }
  function sliceText(text, from, to) {
    return appendText(text, [""], from, to);
  }
  var RawTextCursor = class {
    constructor(text, dir = 1) {
      this.dir = dir;
      this.done = false;
      this.lineBreak = false;
      this.value = "";
      this.nodes = [text];
      this.offsets = [dir > 0 ? 1 : (text instanceof TextLeaf ? text.text.length : text.children.length) << 1];
    }
    nextInner(skip, dir) {
      this.done = this.lineBreak = false;
      for (; ; ) {
        let last = this.nodes.length - 1;
        let top = this.nodes[last], offsetValue = this.offsets[last], offset = offsetValue >> 1;
        let size = top instanceof TextLeaf ? top.text.length : top.children.length;
        if (offset == (dir > 0 ? size : 0)) {
          if (last == 0) {
            this.done = true;
            this.value = "";
            return this;
          }
          if (dir > 0)
            this.offsets[last - 1]++;
          this.nodes.pop();
          this.offsets.pop();
        } else if ((offsetValue & 1) == (dir > 0 ? 0 : 1)) {
          this.offsets[last] += dir;
          if (skip == 0) {
            this.lineBreak = true;
            this.value = "\n";
            return this;
          }
          skip--;
        } else if (top instanceof TextLeaf) {
          let next = top.text[offset + (dir < 0 ? -1 : 0)];
          this.offsets[last] += dir;
          if (next.length > Math.max(0, skip)) {
            this.value = skip == 0 ? next : dir > 0 ? next.slice(skip) : next.slice(0, next.length - skip);
            return this;
          }
          skip -= next.length;
        } else {
          let next = top.children[offset + (dir < 0 ? -1 : 0)];
          if (skip > next.length) {
            skip -= next.length;
            this.offsets[last] += dir;
          } else {
            if (dir < 0)
              this.offsets[last]--;
            this.nodes.push(next);
            this.offsets.push(dir > 0 ? 1 : (next instanceof TextLeaf ? next.text.length : next.children.length) << 1);
          }
        }
      }
    }
    next(skip = 0) {
      if (skip < 0) {
        this.nextInner(-skip, -this.dir);
        skip = this.value.length;
      }
      return this.nextInner(skip, this.dir);
    }
  };
  var PartialTextCursor = class {
    constructor(text, start, end) {
      this.value = "";
      this.done = false;
      this.cursor = new RawTextCursor(text, start > end ? -1 : 1);
      this.pos = start > end ? text.length : 0;
      this.from = Math.min(start, end);
      this.to = Math.max(start, end);
    }
    nextInner(skip, dir) {
      if (dir < 0 ? this.pos <= this.from : this.pos >= this.to) {
        this.value = "";
        this.done = true;
        return this;
      }
      skip += Math.max(0, dir < 0 ? this.pos - this.to : this.from - this.pos);
      let limit = dir < 0 ? this.pos - this.from : this.to - this.pos;
      if (skip > limit)
        skip = limit;
      limit -= skip;
      let { value } = this.cursor.next(skip);
      this.pos += (value.length + skip) * dir;
      this.value = value.length <= limit ? value : dir < 0 ? value.slice(value.length - limit) : value.slice(0, limit);
      this.done = !this.value;
      return this;
    }
    next(skip = 0) {
      if (skip < 0)
        skip = Math.max(skip, this.from - this.pos);
      else if (skip > 0)
        skip = Math.min(skip, this.to - this.pos);
      return this.nextInner(skip, this.cursor.dir);
    }
    get lineBreak() {
      return this.cursor.lineBreak && this.value != "";
    }
  };
  var LineCursor = class {
    constructor(inner) {
      this.inner = inner;
      this.afterBreak = true;
      this.value = "";
      this.done = false;
    }
    next(skip = 0) {
      let { done, lineBreak, value } = this.inner.next(skip);
      if (done && this.afterBreak) {
        this.value = "";
        this.afterBreak = false;
      } else if (done) {
        this.done = true;
        this.value = "";
      } else if (lineBreak) {
        if (this.afterBreak) {
          this.value = "";
        } else {
          this.afterBreak = true;
          this.next();
        }
      } else {
        this.value = value;
        this.afterBreak = false;
      }
      return this;
    }
    get lineBreak() {
      return false;
    }
  };
  if (typeof Symbol != "undefined") {
    Text2.prototype[Symbol.iterator] = function() {
      return this.iter();
    };
    RawTextCursor.prototype[Symbol.iterator] = PartialTextCursor.prototype[Symbol.iterator] = LineCursor.prototype[Symbol.iterator] = function() {
      return this;
    };
  }
  var Line = class {
    /**
    @internal
    */
    constructor(from, to, number, text) {
      this.from = from;
      this.to = to;
      this.number = number;
      this.text = text;
    }
    /**
    The length of the line (not including any line break after it).
    */
    get length() {
      return this.to - this.from;
    }
  };
  function clip(text, from, to) {
    from = Math.max(0, Math.min(text.length, from));
    return [from, Math.max(from, Math.min(text.length, to))];
  }
  function findClusterBreak2(str, pos, forward = true, includeExtending = true) {
    return findClusterBreak(str, pos, forward, includeExtending);
  }
  function surrogateLow2(ch) {
    return ch >= 56320 && ch < 57344;
  }
  function surrogateHigh2(ch) {
    return ch >= 55296 && ch < 56320;
  }
  function codePointAt2(str, pos) {
    let code0 = str.charCodeAt(pos);
    if (!surrogateHigh2(code0) || pos + 1 == str.length)
      return code0;
    let code1 = str.charCodeAt(pos + 1);
    if (!surrogateLow2(code1))
      return code0;
    return (code0 - 55296 << 10) + (code1 - 56320) + 65536;
  }
  function fromCodePoint(code) {
    if (code <= 65535)
      return String.fromCharCode(code);
    code -= 65536;
    return String.fromCharCode((code >> 10) + 55296, (code & 1023) + 56320);
  }
  function codePointSize2(code) {
    return code < 65536 ? 1 : 2;
  }
  var DefaultSplit = /\r\n?|\n/;
  var MapMode = /* @__PURE__ */ (function(MapMode2) {
    MapMode2[MapMode2["Simple"] = 0] = "Simple";
    MapMode2[MapMode2["TrackDel"] = 1] = "TrackDel";
    MapMode2[MapMode2["TrackBefore"] = 2] = "TrackBefore";
    MapMode2[MapMode2["TrackAfter"] = 3] = "TrackAfter";
    return MapMode2;
  })(MapMode || (MapMode = {}));
  var ChangeDesc = class _ChangeDesc {
    // Sections are encoded as pairs of integers. The first is the
    // length in the current document, and the second is -1 for
    // unaffected sections, and the length of the replacement content
    // otherwise. So an insertion would be (0, n>0), a deletion (n>0,
    // 0), and a replacement two positive numbers.
    /**
    @internal
    */
    constructor(sections) {
      this.sections = sections;
    }
    /**
    The length of the document before the change.
    */
    get length() {
      let result = 0;
      for (let i = 0; i < this.sections.length; i += 2)
        result += this.sections[i];
      return result;
    }
    /**
    The length of the document after the change.
    */
    get newLength() {
      let result = 0;
      for (let i = 0; i < this.sections.length; i += 2) {
        let ins = this.sections[i + 1];
        result += ins < 0 ? this.sections[i] : ins;
      }
      return result;
    }
    /**
    False when there are actual changes in this set.
    */
    get empty() {
      return this.sections.length == 0 || this.sections.length == 2 && this.sections[1] < 0;
    }
    /**
    Iterate over the unchanged parts left by these changes. `posA`
    provides the position of the range in the old document, `posB`
    the new position in the changed document.
    */
    iterGaps(f) {
      for (let i = 0, posA = 0, posB = 0; i < this.sections.length; ) {
        let len = this.sections[i++], ins = this.sections[i++];
        if (ins < 0) {
          f(posA, posB, len);
          posB += len;
        } else {
          posB += ins;
        }
        posA += len;
      }
    }
    /**
    Iterate over the ranges changed by these changes. (See
    [`ChangeSet.iterChanges`](https://codemirror.net/6/docs/ref/#state.ChangeSet.iterChanges) for a
    variant that also provides you with the inserted text.)
    `fromA`/`toA` provides the extent of the change in the starting
    document, `fromB`/`toB` the extent of the replacement in the
    changed document.
    
    When `individual` is true, adjacent changes (which are kept
    separate for [position mapping](https://codemirror.net/6/docs/ref/#state.ChangeDesc.mapPos)) are
    reported separately.
    */
    iterChangedRanges(f, individual = false) {
      iterChanges(this, f, individual);
    }
    /**
    Get a description of the inverted form of these changes.
    */
    get invertedDesc() {
      let sections = [];
      for (let i = 0; i < this.sections.length; ) {
        let len = this.sections[i++], ins = this.sections[i++];
        if (ins < 0)
          sections.push(len, ins);
        else
          sections.push(ins, len);
      }
      return new _ChangeDesc(sections);
    }
    /**
    Compute the combined effect of applying another set of changes
    after this one. The length of the document after this set should
    match the length before `other`.
    */
    composeDesc(other) {
      return this.empty ? other : other.empty ? this : composeSets(this, other);
    }
    /**
    Map this description, which should start with the same document
    as `other`, over another set of changes, so that it can be
    applied after it. When `before` is true, map as if the changes
    in `this` happened before the ones in `other`.
    */
    mapDesc(other, before = false) {
      return other.empty ? this : mapSet(this, other, before);
    }
    mapPos(pos, assoc = -1, mode = MapMode.Simple) {
      let posA = 0, posB = 0;
      for (let i = 0; i < this.sections.length; ) {
        let len = this.sections[i++], ins = this.sections[i++], endA = posA + len;
        if (ins < 0) {
          if (endA > pos)
            return posB + (pos - posA);
          posB += len;
        } else {
          if (mode != MapMode.Simple && endA >= pos && (mode == MapMode.TrackDel && posA < pos && endA > pos || mode == MapMode.TrackBefore && posA < pos || mode == MapMode.TrackAfter && endA > pos))
            return null;
          if (endA > pos || endA == pos && assoc < 0 && !len)
            return pos == posA || assoc < 0 ? posB : posB + ins;
          posB += ins;
        }
        posA = endA;
      }
      if (pos > posA)
        throw new RangeError(`Position ${pos} is out of range for changeset of length ${posA}`);
      return posB;
    }
    /**
    Check whether these changes touch a given range. When one of the
    changes entirely covers the range, the string `"cover"` is
    returned.
    */
    touchesRange(from, to = from) {
      for (let i = 0, pos = 0; i < this.sections.length && pos <= to; ) {
        let len = this.sections[i++], ins = this.sections[i++], end = pos + len;
        if (ins >= 0 && pos <= to && end >= from)
          return pos < from && end > to ? "cover" : true;
        pos = end;
      }
      return false;
    }
    /**
    @internal
    */
    toString() {
      let result = "";
      for (let i = 0; i < this.sections.length; ) {
        let len = this.sections[i++], ins = this.sections[i++];
        result += (result ? " " : "") + len + (ins >= 0 ? ":" + ins : "");
      }
      return result;
    }
    /**
    Serialize this change desc to a JSON-representable value.
    */
    toJSON() {
      return this.sections;
    }
    /**
    Create a change desc from its JSON representation (as produced
    by [`toJSON`](https://codemirror.net/6/docs/ref/#state.ChangeDesc.toJSON).
    */
    static fromJSON(json) {
      if (!Array.isArray(json) || json.length % 2 || json.some((a) => typeof a != "number"))
        throw new RangeError("Invalid JSON representation of ChangeDesc");
      return new _ChangeDesc(json);
    }
    /**
    @internal
    */
    static create(sections) {
      return new _ChangeDesc(sections);
    }
  };
  var ChangeSet = class _ChangeSet extends ChangeDesc {
    constructor(sections, inserted) {
      super(sections);
      this.inserted = inserted;
    }
    /**
    Apply the changes to a document, returning the modified
    document.
    */
    apply(doc) {
      if (this.length != doc.length)
        throw new RangeError("Applying change set to a document with the wrong length");
      iterChanges(this, (fromA, toA, fromB, _toB, text) => doc = doc.replace(fromB, fromB + (toA - fromA), text), false);
      return doc;
    }
    mapDesc(other, before = false) {
      return mapSet(this, other, before, true);
    }
    /**
    Given the document as it existed _before_ the changes, return a
    change set that represents the inverse of this set, which could
    be used to go from the document created by the changes back to
    the document as it existed before the changes.
    */
    invert(doc) {
      let sections = this.sections.slice(), inserted = [];
      for (let i = 0, pos = 0; i < sections.length; i += 2) {
        let len = sections[i], ins = sections[i + 1];
        if (ins >= 0) {
          sections[i] = ins;
          sections[i + 1] = len;
          let index = i >> 1;
          while (inserted.length < index)
            inserted.push(Text2.empty);
          inserted.push(len ? doc.slice(pos, pos + len) : Text2.empty);
        }
        pos += len;
      }
      return new _ChangeSet(sections, inserted);
    }
    /**
    Combine two subsequent change sets into a single set. `other`
    must start in the document produced by `this`. If `this` goes
    `docA` → `docB` and `other` represents `docB` → `docC`, the
    returned value will represent the change `docA` → `docC`.
    */
    compose(other) {
      return this.empty ? other : other.empty ? this : composeSets(this, other, true);
    }
    /**
    Given another change set starting in the same document, maps this
    change set over the other, producing a new change set that can be
    applied to the document produced by applying `other`. When
    `before` is `true`, order changes as if `this` comes before
    `other`, otherwise (the default) treat `other` as coming first.
    
    Given two changes `A` and `B`, `A.compose(B.map(A))` and
    `B.compose(A.map(B, true))` will produce the same document. This
    provides a basic form of [operational
    transformation](https://en.wikipedia.org/wiki/Operational_transformation),
    and can be used for collaborative editing.
    */
    map(other, before = false) {
      return other.empty ? this : mapSet(this, other, before, true);
    }
    /**
    Iterate over the changed ranges in the document, calling `f` for
    each, with the range in the original document (`fromA`-`toA`)
    and the range that replaces it in the new document
    (`fromB`-`toB`).
    
    When `individual` is true, adjacent changes are reported
    separately.
    */
    iterChanges(f, individual = false) {
      iterChanges(this, f, individual);
    }
    /**
    Get a [change description](https://codemirror.net/6/docs/ref/#state.ChangeDesc) for this change
    set.
    */
    get desc() {
      return ChangeDesc.create(this.sections);
    }
    /**
    @internal
    */
    filter(ranges) {
      let resultSections = [], resultInserted = [], filteredSections = [];
      let iter = new SectionIter(this);
      done: for (let i = 0, pos = 0; ; ) {
        let next = i == ranges.length ? 1e9 : ranges[i++];
        while (pos < next || pos == next && iter.len == 0) {
          if (iter.done)
            break done;
          let len = Math.min(iter.len, next - pos);
          addSection(filteredSections, len, -1);
          let ins = iter.ins == -1 ? -1 : iter.off == 0 ? iter.ins : 0;
          addSection(resultSections, len, ins);
          if (ins > 0)
            addInsert(resultInserted, resultSections, iter.text);
          iter.forward(len);
          pos += len;
        }
        let end = ranges[i++];
        while (pos < end) {
          if (iter.done)
            break done;
          let len = Math.min(iter.len, end - pos);
          addSection(resultSections, len, -1);
          addSection(filteredSections, len, iter.ins == -1 ? -1 : iter.off == 0 ? iter.ins : 0);
          iter.forward(len);
          pos += len;
        }
      }
      return {
        changes: new _ChangeSet(resultSections, resultInserted),
        filtered: ChangeDesc.create(filteredSections)
      };
    }
    /**
    Serialize this change set to a JSON-representable value.
    */
    toJSON() {
      let parts = [];
      for (let i = 0; i < this.sections.length; i += 2) {
        let len = this.sections[i], ins = this.sections[i + 1];
        if (ins < 0)
          parts.push(len);
        else if (ins == 0)
          parts.push([len]);
        else
          parts.push([len].concat(this.inserted[i >> 1].toJSON()));
      }
      return parts;
    }
    /**
    Create a change set for the given changes, for a document of the
    given length, using `lineSep` as line separator.
    */
    static of(changes, length, lineSep) {
      let sections = [], inserted = [], pos = 0;
      let total = null;
      function flush(force = false) {
        if (!force && !sections.length)
          return;
        if (pos < length)
          addSection(sections, length - pos, -1);
        let set = new _ChangeSet(sections, inserted);
        total = total ? total.compose(set.map(total)) : set;
        sections = [];
        inserted = [];
        pos = 0;
      }
      function process(spec) {
        if (Array.isArray(spec)) {
          for (let sub of spec)
            process(sub);
        } else if (spec instanceof _ChangeSet) {
          if (spec.length != length)
            throw new RangeError(`Mismatched change set length (got ${spec.length}, expected ${length})`);
          flush();
          total = total ? total.compose(spec.map(total)) : spec;
        } else {
          let { from, to = from, insert: insert2 } = spec;
          if (from > to || from < 0 || to > length)
            throw new RangeError(`Invalid change range ${from} to ${to} (in doc of length ${length})`);
          let insText = !insert2 ? Text2.empty : typeof insert2 == "string" ? Text2.of(insert2.split(lineSep || DefaultSplit)) : insert2;
          let insLen = insText.length;
          if (from == to && insLen == 0)
            return;
          if (from < pos)
            flush();
          if (from > pos)
            addSection(sections, from - pos, -1);
          addSection(sections, to - from, insLen);
          addInsert(inserted, sections, insText);
          pos = to;
        }
      }
      process(changes);
      flush(!total);
      return total;
    }
    /**
    Create an empty changeset of the given length.
    */
    static empty(length) {
      return new _ChangeSet(length ? [length, -1] : [], []);
    }
    /**
    Create a changeset from its JSON representation (as produced by
    [`toJSON`](https://codemirror.net/6/docs/ref/#state.ChangeSet.toJSON).
    */
    static fromJSON(json) {
      if (!Array.isArray(json))
        throw new RangeError("Invalid JSON representation of ChangeSet");
      let sections = [], inserted = [];
      for (let i = 0; i < json.length; i++) {
        let part = json[i];
        if (typeof part == "number") {
          sections.push(part, -1);
        } else if (!Array.isArray(part) || typeof part[0] != "number" || part.some((e, i2) => i2 && typeof e != "string")) {
          throw new RangeError("Invalid JSON representation of ChangeSet");
        } else if (part.length == 1) {
          sections.push(part[0], 0);
        } else {
          while (inserted.length < i)
            inserted.push(Text2.empty);
          inserted[i] = Text2.of(part.slice(1));
          sections.push(part[0], inserted[i].length);
        }
      }
      return new _ChangeSet(sections, inserted);
    }
    /**
    @internal
    */
    static createSet(sections, inserted) {
      return new _ChangeSet(sections, inserted);
    }
  };
  function addSection(sections, len, ins, forceJoin = false) {
    if (len == 0 && ins <= 0)
      return;
    let last = sections.length - 2;
    if (last >= 0 && ins <= 0 && ins == sections[last + 1])
      sections[last] += len;
    else if (last >= 0 && len == 0 && sections[last] == 0)
      sections[last + 1] += ins;
    else if (forceJoin) {
      sections[last] += len;
      sections[last + 1] += ins;
    } else
      sections.push(len, ins);
  }
  function addInsert(values, sections, value) {
    if (value.length == 0)
      return;
    let index = sections.length - 2 >> 1;
    if (index < values.length) {
      values[values.length - 1] = values[values.length - 1].append(value);
    } else {
      while (values.length < index)
        values.push(Text2.empty);
      values.push(value);
    }
  }
  function iterChanges(desc, f, individual) {
    let inserted = desc.inserted;
    for (let posA = 0, posB = 0, i = 0; i < desc.sections.length; ) {
      let len = desc.sections[i++], ins = desc.sections[i++];
      if (ins < 0) {
        posA += len;
        posB += len;
      } else {
        let endA = posA, endB = posB, text = Text2.empty;
        for (; ; ) {
          endA += len;
          endB += ins;
          if (ins && inserted)
            text = text.append(inserted[i - 2 >> 1]);
          if (individual || i == desc.sections.length || desc.sections[i + 1] < 0)
            break;
          len = desc.sections[i++];
          ins = desc.sections[i++];
        }
        f(posA, endA, posB, endB, text);
        posA = endA;
        posB = endB;
      }
    }
  }
  function mapSet(setA, setB, before, mkSet = false) {
    let sections = [], insert2 = mkSet ? [] : null;
    let a = new SectionIter(setA), b = new SectionIter(setB);
    for (let inserted = -1; ; ) {
      if (a.done && b.len || b.done && a.len) {
        throw new Error("Mismatched change set lengths");
      } else if (a.ins == -1 && b.ins == -1) {
        let len = Math.min(a.len, b.len);
        addSection(sections, len, -1);
        a.forward(len);
        b.forward(len);
      } else if (b.ins >= 0 && (a.ins < 0 || inserted == a.i || a.off == 0 && (b.len < a.len || b.len == a.len && !before))) {
        let len = b.len;
        addSection(sections, b.ins, -1);
        while (len) {
          let piece = Math.min(a.len, len);
          if (a.ins >= 0 && inserted < a.i && a.len <= piece) {
            addSection(sections, 0, a.ins);
            if (insert2)
              addInsert(insert2, sections, a.text);
            inserted = a.i;
          }
          a.forward(piece);
          len -= piece;
        }
        b.next();
      } else if (a.ins >= 0) {
        let len = 0, left = a.len;
        while (left) {
          if (b.ins == -1) {
            let piece = Math.min(left, b.len);
            len += piece;
            left -= piece;
            b.forward(piece);
          } else if (b.ins == 0 && b.len < left) {
            left -= b.len;
            b.next();
          } else {
            break;
          }
        }
        addSection(sections, len, inserted < a.i ? a.ins : 0);
        if (insert2 && inserted < a.i)
          addInsert(insert2, sections, a.text);
        inserted = a.i;
        a.forward(a.len - left);
      } else if (a.done && b.done) {
        return insert2 ? ChangeSet.createSet(sections, insert2) : ChangeDesc.create(sections);
      } else {
        throw new Error("Mismatched change set lengths");
      }
    }
  }
  function composeSets(setA, setB, mkSet = false) {
    let sections = [];
    let insert2 = mkSet ? [] : null;
    let a = new SectionIter(setA), b = new SectionIter(setB);
    for (let open = false; ; ) {
      if (a.done && b.done) {
        return insert2 ? ChangeSet.createSet(sections, insert2) : ChangeDesc.create(sections);
      } else if (a.ins == 0) {
        addSection(sections, a.len, 0, open);
        a.next();
      } else if (b.len == 0 && !b.done) {
        addSection(sections, 0, b.ins, open);
        if (insert2)
          addInsert(insert2, sections, b.text);
        b.next();
      } else if (a.done || b.done) {
        throw new Error("Mismatched change set lengths");
      } else {
        let len = Math.min(a.len2, b.len), sectionLen = sections.length;
        if (a.ins == -1) {
          let insB = b.ins == -1 ? -1 : b.off ? 0 : b.ins;
          addSection(sections, len, insB, open);
          if (insert2 && insB)
            addInsert(insert2, sections, b.text);
        } else if (b.ins == -1) {
          addSection(sections, a.off ? 0 : a.len, len, open);
          if (insert2)
            addInsert(insert2, sections, a.textBit(len));
        } else {
          addSection(sections, a.off ? 0 : a.len, b.off ? 0 : b.ins, open);
          if (insert2 && !b.off)
            addInsert(insert2, sections, b.text);
        }
        open = (a.ins > len || b.ins >= 0 && b.len > len) && (open || sections.length > sectionLen);
        a.forward2(len);
        b.forward(len);
      }
    }
  }
  var SectionIter = class {
    constructor(set) {
      this.set = set;
      this.i = 0;
      this.next();
    }
    next() {
      let { sections } = this.set;
      if (this.i < sections.length) {
        this.len = sections[this.i++];
        this.ins = sections[this.i++];
      } else {
        this.len = 0;
        this.ins = -2;
      }
      this.off = 0;
    }
    get done() {
      return this.ins == -2;
    }
    get len2() {
      return this.ins < 0 ? this.len : this.ins;
    }
    get text() {
      let { inserted } = this.set, index = this.i - 2 >> 1;
      return index >= inserted.length ? Text2.empty : inserted[index];
    }
    textBit(len) {
      let { inserted } = this.set, index = this.i - 2 >> 1;
      return index >= inserted.length && !len ? Text2.empty : inserted[index].slice(this.off, len == null ? void 0 : this.off + len);
    }
    forward(len) {
      if (len == this.len)
        this.next();
      else {
        this.len -= len;
        this.off += len;
      }
    }
    forward2(len) {
      if (this.ins == -1)
        this.forward(len);
      else if (len == this.ins)
        this.next();
      else {
        this.ins -= len;
        this.off += len;
      }
    }
  };
  var SelectionRange = class _SelectionRange {
    constructor(from, to, flags, goalColumn) {
      this.from = from;
      this.to = to;
      this.flags = flags;
      this.goalColumn = goalColumn;
    }
    /**
    The anchor of the range—the side that doesn't move when you
    extend it.
    */
    get anchor() {
      return this.flags & 32 ? this.to : this.from;
    }
    /**
    The head of the range, which is moved when the range is
    [extended](https://codemirror.net/6/docs/ref/#state.SelectionRange.extend).
    */
    get head() {
      return this.flags & 32 ? this.from : this.to;
    }
    /**
    True when `anchor` and `head` are at the same position.
    */
    get empty() {
      return this.from == this.to;
    }
    /**
    If this is a cursor that is explicitly associated with the
    character on one of its sides, this returns the side. -1 means
    the character before its position, 1 the character after, and 0
    means no association.
    */
    get assoc() {
      return this.flags & 8 ? -1 : this.flags & 16 ? 1 : 0;
    }
    /**
    A flag that, when set, makes some selection-extending commands
    treat the range's head and anchor as exchangeable, so that for
    example Shift-ArrowUp will make the lower side of the selection
    the anchor, even if that was the head before. Used to implement
    MacOS-style undirectional selections.
    */
    get undirectional() {
      return (this.flags & 64) > 0;
    }
    /**
    The bidirectional text level associated with this cursor, if
    any.
    */
    get bidiLevel() {
      let level = this.flags & 7;
      return level == 7 ? null : level;
    }
    /**
    Map this range through a change, producing a valid range in the
    updated document.
    */
    map(change, assoc = -1) {
      let from, to;
      if (this.empty) {
        from = to = change.mapPos(this.from, assoc);
      } else {
        from = change.mapPos(this.from, 1);
        to = change.mapPos(this.to, -1);
      }
      return from == this.from && to == this.to ? this : new _SelectionRange(from, to, this.flags, this.goalColumn);
    }
    /**
    Extend this range to cover at least `from` to `to`.
    */
    extend(from, to = from, assoc = 0) {
      if (from <= this.anchor && to >= this.anchor)
        return EditorSelection.range(from, to, void 0, void 0, assoc);
      let head = Math.abs(from - this.anchor) > Math.abs(to - this.anchor) ? from : to;
      return EditorSelection.range(this.anchor, head, void 0, void 0, assoc);
    }
    /**
    Compare this range to another range.
    */
    eq(other, includeAssoc = false) {
      return this.anchor == other.anchor && this.head == other.head && this.goalColumn == other.goalColumn && (!includeAssoc || !this.empty || this.assoc == other.assoc);
    }
    /**
    Return a JSON-serializable object representing the range.
    */
    toJSON() {
      return { anchor: this.anchor, head: this.head };
    }
    /**
    Convert a JSON representation of a range to a `SelectionRange`
    instance.
    */
    static fromJSON(json) {
      if (!json || typeof json.anchor != "number" || typeof json.head != "number")
        throw new RangeError("Invalid JSON representation for SelectionRange");
      return EditorSelection.range(json.anchor, json.head);
    }
    /**
    @internal
    */
    static create(from, to, flags, goalColumn) {
      return new _SelectionRange(from, to, flags, goalColumn);
    }
  };
  var EditorSelection = class _EditorSelection {
    constructor(ranges, mainIndex) {
      this.ranges = ranges;
      this.mainIndex = mainIndex;
    }
    /**
    Map a selection through a change. Used to adjust the selection
    position for changes.
    */
    map(change, assoc = -1) {
      if (change.empty)
        return this;
      return _EditorSelection.create(this.ranges.map((r) => r.map(change, assoc)), this.mainIndex);
    }
    /**
    Compare this selection to another selection. By default, ranges
    are compared only by position. When `includeAssoc` is true,
    cursor ranges must also have the same
    [`assoc`](https://codemirror.net/6/docs/ref/#state.SelectionRange.assoc) value.
    */
    eq(other, includeAssoc = false) {
      if (this.ranges.length != other.ranges.length || this.mainIndex != other.mainIndex)
        return false;
      for (let i = 0; i < this.ranges.length; i++)
        if (!this.ranges[i].eq(other.ranges[i], includeAssoc))
          return false;
      return true;
    }
    /**
    Get the primary selection range. Usually, you should make sure
    your code applies to _all_ ranges, by using methods like
    [`changeByRange`](https://codemirror.net/6/docs/ref/#state.EditorState.changeByRange).
    */
    get main() {
      return this.ranges[this.mainIndex];
    }
    /**
    Make sure the selection only has one range. Returns a selection
    holding only the main range from this selection.
    */
    asSingle() {
      return this.ranges.length == 1 ? this : new _EditorSelection([this.main], 0);
    }
    /**
    Extend this selection with an extra range.
    */
    addRange(range, main = true) {
      return _EditorSelection.create([range].concat(this.ranges), main ? 0 : this.mainIndex + 1);
    }
    /**
    Replace a given range with another range, and then normalize the
    selection to merge and sort ranges if necessary.
    */
    replaceRange(range, which = this.mainIndex) {
      let ranges = this.ranges.slice();
      ranges[which] = range;
      return _EditorSelection.create(ranges, this.mainIndex);
    }
    /**
    Convert this selection to an object that can be serialized to
    JSON.
    */
    toJSON() {
      return { ranges: this.ranges.map((r) => r.toJSON()), main: this.mainIndex };
    }
    /**
    Create a selection from a JSON representation.
    */
    static fromJSON(json) {
      if (!json || !Array.isArray(json.ranges) || typeof json.main != "number" || json.main >= json.ranges.length)
        throw new RangeError("Invalid JSON representation for EditorSelection");
      return new _EditorSelection(json.ranges.map((r) => SelectionRange.fromJSON(r)), json.main);
    }
    /**
    Create a selection holding a single range.
    */
    static single(anchor, head = anchor) {
      return new _EditorSelection([_EditorSelection.range(anchor, head)], 0);
    }
    /**
    Sort and merge the given set of ranges, creating a valid
    selection.
    */
    static create(ranges, mainIndex = 0) {
      if (ranges.length == 0)
        throw new RangeError("A selection needs at least one range");
      for (let pos = 0, i = 0; i < ranges.length; i++) {
        let range = ranges[i];
        if (range.empty ? range.from <= pos : range.from < pos)
          return _EditorSelection.normalized(ranges.slice(), mainIndex);
        pos = range.to;
      }
      return new _EditorSelection(ranges, mainIndex);
    }
    /**
    Create a cursor selection range at the given position. You can
    safely ignore the optional arguments in most situations.
    */
    static cursor(pos, assoc = 0, bidiLevel, goalColumn) {
      return SelectionRange.create(pos, pos, (assoc == 0 ? 0 : assoc < 0 ? 8 : 16) | (bidiLevel == null ? 7 : Math.min(6, bidiLevel)), goalColumn);
    }
    /**
    Create a selection range.
    */
    static range(anchor, head, goalColumn, bidiLevel, assoc) {
      let flags = bidiLevel == null ? 7 : Math.min(6, bidiLevel);
      if (!assoc && anchor != head)
        assoc = head < anchor ? 1 : -1;
      if (assoc)
        flags |= assoc < 0 ? 8 : 16;
      return head < anchor ? SelectionRange.create(head, anchor, flags | 32, goalColumn) : SelectionRange.create(anchor, head, flags, goalColumn);
    }
    /**
    Create an [undirectional](https://codemirror.net/6/docs/ref/#state.SelectionRange.undirectional)
    selection range.
    */
    static undirectionalRange(from, to) {
      return SelectionRange.create(from, to, 64, void 0);
    }
    /**
    @internal
    */
    static normalized(ranges, mainIndex = 0) {
      let main = ranges[mainIndex];
      ranges.sort((a, b) => a.from - b.from);
      mainIndex = ranges.indexOf(main);
      for (let i = 1; i < ranges.length; i++) {
        let range = ranges[i], prev = ranges[i - 1];
        if (range.empty ? range.from <= prev.to : range.from < prev.to) {
          let from = prev.from, to = Math.max(range.to, prev.to);
          if (i <= mainIndex)
            mainIndex--;
          ranges.splice(--i, 2, range.anchor > range.head ? _EditorSelection.range(to, from) : _EditorSelection.range(from, to));
        }
      }
      return new _EditorSelection(ranges, mainIndex);
    }
  };
  function checkSelection(selection, docLength) {
    for (let range of selection.ranges)
      if (range.to > docLength)
        throw new RangeError("Selection points outside of document");
  }
  var nextID = 0;
  var Facet = class _Facet {
    constructor(combine, compareInput, compare2, isStatic, enables) {
      this.combine = combine;
      this.compareInput = compareInput;
      this.compare = compare2;
      this.isStatic = isStatic;
      this.id = nextID++;
      this.default = combine([]);
      this.extensions = typeof enables == "function" ? enables(this) : enables;
    }
    /**
    Returns a facet reader for this facet, which can be used to
    [read](https://codemirror.net/6/docs/ref/#state.EditorState.facet) it but not to define values for it.
    */
    get reader() {
      return this;
    }
    /**
    Define a new facet.
    */
    static define(config = {}) {
      return new _Facet(config.combine || ((a) => a), config.compareInput || ((a, b) => a === b), config.compare || (!config.combine ? sameArray : (a, b) => a === b), !!config.static, config.enables);
    }
    /**
    Returns an extension that adds the given value to this facet.
    */
    of(value) {
      return new FacetProvider([], this, 0, value);
    }
    /**
    Create an extension that computes a value for the facet from a
    state. You must take care to declare the parts of the state that
    this value depends on, since your function is only called again
    for a new state when one of those parts changed.
    
    In cases where your value depends only on a single field, you'll
    want to use the [`from`](https://codemirror.net/6/docs/ref/#state.Facet.from) method instead.
    */
    compute(deps, get) {
      if (this.isStatic)
        throw new Error("Can't compute a static facet");
      return new FacetProvider(deps, this, 1, get);
    }
    /**
    Create an extension that computes zero or more values for this
    facet from a state.
    */
    computeN(deps, get) {
      if (this.isStatic)
        throw new Error("Can't compute a static facet");
      return new FacetProvider(deps, this, 2, get);
    }
    from(field, get) {
      if (!get)
        get = (x) => x;
      return this.compute([field], (state) => get(state.field(field)));
    }
  };
  function sameArray(a, b) {
    return a == b || a.length == b.length && a.every((e, i) => e === b[i]);
  }
  var FacetProvider = class {
    constructor(dependencies, facet, type, value) {
      this.dependencies = dependencies;
      this.facet = facet;
      this.type = type;
      this.value = value;
      this.id = nextID++;
    }
    dynamicSlot(addresses) {
      var _a;
      let getter = this.value;
      let compare2 = this.facet.compareInput;
      let id = this.id, idx = addresses[id] >> 1, multi = this.type == 2;
      let depDoc = false, depSel = false, depAddrs = [];
      for (let dep of this.dependencies) {
        if (dep == "doc")
          depDoc = true;
        else if (dep == "selection")
          depSel = true;
        else if ((((_a = addresses[dep.id]) !== null && _a !== void 0 ? _a : 1) & 1) == 0)
          depAddrs.push(addresses[dep.id]);
      }
      return {
        create(state) {
          state.values[idx] = getter(state);
          return 1;
        },
        update(state, tr) {
          if (depDoc && tr.docChanged || depSel && (tr.docChanged || tr.selection) || ensureAll(state, depAddrs)) {
            let newVal = getter(state);
            if (multi ? !compareArray(newVal, state.values[idx], compare2) : !compare2(newVal, state.values[idx])) {
              state.values[idx] = newVal;
              return 1;
            }
          }
          return 0;
        },
        reconfigure: (state, oldState) => {
          let newVal, oldAddr = oldState.config.address[id];
          if (oldAddr != null) {
            let oldVal = getAddr(oldState, oldAddr);
            if (this.dependencies.every((dep) => {
              return dep instanceof Facet ? oldState.facet(dep) === state.facet(dep) : dep instanceof StateField ? oldState.field(dep, false) == state.field(dep, false) : true;
            }) || (multi ? compareArray(newVal = getter(state), oldVal, compare2) : compare2(newVal = getter(state), oldVal))) {
              state.values[idx] = oldVal;
              return 0;
            }
          } else {
            newVal = getter(state);
          }
          state.values[idx] = newVal;
          return 1;
        }
      };
    }
    get extension() {
      return this;
    }
  };
  function compareArray(a, b, compare2) {
    if (a.length != b.length)
      return false;
    for (let i = 0; i < a.length; i++)
      if (!compare2(a[i], b[i]))
        return false;
    return true;
  }
  function ensureAll(state, addrs) {
    let changed = false;
    for (let addr of addrs)
      if (ensureAddr(state, addr) & 1)
        changed = true;
    return changed;
  }
  function dynamicFacetSlot(addresses, facet, providers) {
    let providerAddrs = providers.map((p) => addresses[p.id]);
    let providerTypes = providers.map((p) => p.type);
    let dynamic = providerAddrs.filter((p) => !(p & 1));
    let idx = addresses[facet.id] >> 1;
    function get(state) {
      let values = [];
      for (let i = 0; i < providerAddrs.length; i++) {
        let value = getAddr(state, providerAddrs[i]);
        if (providerTypes[i] == 2)
          for (let val of value)
            values.push(val);
        else
          values.push(value);
      }
      return facet.combine(values);
    }
    return {
      create(state) {
        for (let addr of providerAddrs)
          ensureAddr(state, addr);
        state.values[idx] = get(state);
        return 1;
      },
      update(state, tr) {
        if (!ensureAll(state, dynamic))
          return 0;
        let value = get(state);
        if (facet.compare(value, state.values[idx]))
          return 0;
        state.values[idx] = value;
        return 1;
      },
      reconfigure(state, oldState) {
        let depChanged = ensureAll(state, providerAddrs);
        let oldProviders = oldState.config.facets[facet.id], oldValue = oldState.facet(facet);
        if (oldProviders && !depChanged && sameArray(providers, oldProviders)) {
          state.values[idx] = oldValue;
          return 0;
        }
        let value = get(state);
        if (facet.compare(value, oldValue)) {
          state.values[idx] = oldValue;
          return 0;
        }
        state.values[idx] = value;
        return 1;
      }
    };
  }
  var initField = /* @__PURE__ */ Facet.define({ static: true });
  var StateField = class _StateField {
    constructor(id, createF, updateF, compareF, spec) {
      this.id = id;
      this.createF = createF;
      this.updateF = updateF;
      this.compareF = compareF;
      this.spec = spec;
      this.provides = void 0;
    }
    /**
    Define a state field.
    */
    static define(config) {
      let field = new _StateField(nextID++, config.create, config.update, config.compare || ((a, b) => a === b), config);
      if (config.provide)
        field.provides = config.provide(field);
      return field;
    }
    create(state) {
      let init = state.facet(initField).find((i) => i.field == this);
      return ((init === null || init === void 0 ? void 0 : init.create) || this.createF)(state);
    }
    /**
    @internal
    */
    slot(addresses) {
      let idx = addresses[this.id] >> 1;
      return {
        create: (state) => {
          state.values[idx] = this.create(state);
          return 1;
        },
        update: (state, tr) => {
          let oldVal = state.values[idx];
          let value = this.updateF(oldVal, tr);
          if (this.compareF(oldVal, value))
            return 0;
          state.values[idx] = value;
          return 1;
        },
        reconfigure: (state, oldState) => {
          let init = state.facet(initField), oldInit = oldState.facet(initField), reInit;
          if ((reInit = init.find((i) => i.field == this)) && reInit != oldInit.find((i) => i.field == this)) {
            state.values[idx] = reInit.create(state);
            return 1;
          }
          if (oldState.config.address[this.id] != null) {
            state.values[idx] = oldState.field(this);
            return 0;
          }
          state.values[idx] = this.create(state);
          return 1;
        }
      };
    }
    /**
    Returns an extension that enables this field and overrides the
    way it is initialized. Can be useful when you need to provide a
    non-default starting value for the field.
    */
    init(create) {
      return [this, initField.of({ field: this, create })];
    }
    /**
    State field instances can be used as
    [`Extension`](https://codemirror.net/6/docs/ref/#state.Extension) values to enable the field in a
    given state.
    */
    get extension() {
      return this;
    }
  };
  var Prec_ = { lowest: 4, low: 3, default: 2, high: 1, highest: 0 };
  function prec(value) {
    return (ext) => new PrecExtension(ext, value);
  }
  var Prec = {
    /**
    The highest precedence level, for extensions that should end up
    near the start of the precedence ordering.
    */
    highest: /* @__PURE__ */ prec(Prec_.highest),
    /**
    A higher-than-default precedence, for extensions that should
    come before those with default precedence.
    */
    high: /* @__PURE__ */ prec(Prec_.high),
    /**
    The default precedence, which is also used for extensions
    without an explicit precedence.
    */
    default: /* @__PURE__ */ prec(Prec_.default),
    /**
    A lower-than-default precedence.
    */
    low: /* @__PURE__ */ prec(Prec_.low),
    /**
    The lowest precedence level. Meant for things that should end up
    near the end of the extension order.
    */
    lowest: /* @__PURE__ */ prec(Prec_.lowest)
  };
  var PrecExtension = class {
    constructor(inner, prec2) {
      this.inner = inner;
      this.prec = prec2;
    }
    get extension() {
      return this;
    }
  };
  var Compartment = class _Compartment {
    /**
    Create an instance of this compartment to add to your [state
    configuration](https://codemirror.net/6/docs/ref/#state.EditorStateConfig.extensions).
    */
    of(ext) {
      return new CompartmentInstance(this, ext);
    }
    /**
    Create an [effect](https://codemirror.net/6/docs/ref/#state.TransactionSpec.effects) that
    reconfigures this compartment.
    */
    reconfigure(content) {
      return _Compartment.reconfigure.of({ compartment: this, extension: content });
    }
    /**
    Get the current content of the compartment in the state, or
    `undefined` if it isn't present.
    */
    get(state) {
      return state.config.compartments.get(this);
    }
  };
  var CompartmentInstance = class {
    constructor(compartment, inner) {
      this.compartment = compartment;
      this.inner = inner;
    }
    get extension() {
      return this;
    }
  };
  var Configuration = class _Configuration {
    constructor(base, compartments, dynamicSlots, address, staticValues, facets) {
      this.base = base;
      this.compartments = compartments;
      this.dynamicSlots = dynamicSlots;
      this.address = address;
      this.staticValues = staticValues;
      this.facets = facets;
      this.statusTemplate = [];
      while (this.statusTemplate.length < dynamicSlots.length)
        this.statusTemplate.push(
          0
          /* SlotStatus.Unresolved */
        );
    }
    staticFacet(facet) {
      let addr = this.address[facet.id];
      return addr == null ? facet.default : this.staticValues[addr >> 1];
    }
    static resolve(base, compartments, oldState) {
      let fields = [];
      let facets = /* @__PURE__ */ Object.create(null);
      let newCompartments = /* @__PURE__ */ new Map();
      for (let ext of flatten(base, compartments, newCompartments)) {
        if (ext instanceof StateField)
          fields.push(ext);
        else
          (facets[ext.facet.id] || (facets[ext.facet.id] = [])).push(ext);
      }
      let address = /* @__PURE__ */ Object.create(null);
      let staticValues = [];
      let dynamicSlots = [];
      for (let field of fields) {
        address[field.id] = dynamicSlots.length << 1;
        dynamicSlots.push((a) => field.slot(a));
      }
      let oldFacets = oldState === null || oldState === void 0 ? void 0 : oldState.config.facets;
      for (let id in facets) {
        let providers = facets[id], facet = providers[0].facet;
        let oldProviders = oldFacets && oldFacets[id] || [];
        if (providers.every(
          (p) => p.type == 0
          /* Provider.Static */
        )) {
          address[facet.id] = staticValues.length << 1 | 1;
          if (sameArray(oldProviders, providers)) {
            staticValues.push(oldState.facet(facet));
          } else {
            let value = facet.combine(providers.map((p) => p.value));
            staticValues.push(oldState && facet.compare(value, oldState.facet(facet)) ? oldState.facet(facet) : value);
          }
        } else {
          for (let p of providers) {
            if (p.type == 0) {
              address[p.id] = staticValues.length << 1 | 1;
              staticValues.push(p.value);
            } else {
              address[p.id] = dynamicSlots.length << 1;
              dynamicSlots.push((a) => p.dynamicSlot(a));
            }
          }
          address[facet.id] = dynamicSlots.length << 1;
          dynamicSlots.push((a) => dynamicFacetSlot(a, facet, providers));
        }
      }
      let dynamic = dynamicSlots.map((f) => f(address));
      return new _Configuration(base, newCompartments, dynamic, address, staticValues, facets);
    }
  };
  function flatten(extension, compartments, newCompartments) {
    let result = [[], [], [], [], []];
    let seen = /* @__PURE__ */ new Map();
    function inner(ext, prec2) {
      let known = seen.get(ext);
      if (known != null) {
        if (known <= prec2)
          return;
        let found = result[known].indexOf(ext);
        if (found > -1)
          result[known].splice(found, 1);
        if (ext instanceof CompartmentInstance)
          newCompartments.delete(ext.compartment);
      }
      seen.set(ext, prec2);
      if (Array.isArray(ext)) {
        for (let e of ext)
          inner(e, prec2);
      } else if (ext instanceof CompartmentInstance) {
        if (newCompartments.has(ext.compartment))
          throw new RangeError(`Duplicate use of compartment in extensions`);
        let content = compartments.get(ext.compartment) || ext.inner;
        newCompartments.set(ext.compartment, content);
        inner(content, prec2);
      } else if (ext instanceof PrecExtension) {
        inner(ext.inner, ext.prec);
      } else if (ext instanceof StateField) {
        result[prec2].push(ext);
        if (ext.provides)
          inner(ext.provides, prec2);
      } else if (ext instanceof FacetProvider) {
        result[prec2].push(ext);
        if (ext.facet.extensions)
          inner(ext.facet.extensions, Prec_.default);
      } else {
        let content = ext.extension;
        if (!content)
          throw new Error(`Unrecognized extension value in extension set (${ext}).`);
        if (content == ext)
          throw new Error(`Unrecognized extension value in extension set (${ext}). This sometimes happens because multiple instances of @codemirror/state are loaded, breaking instanceof checks.`);
        inner(content, prec2);
      }
    }
    inner(extension, Prec_.default);
    return result.reduce((a, b) => a.concat(b));
  }
  function ensureAddr(state, addr) {
    if (addr & 1)
      return 2;
    let idx = addr >> 1;
    let status = state.status[idx];
    if (status == 4)
      throw new Error("Cyclic dependency between fields and/or facets");
    if (status & 2)
      return status;
    state.status[idx] = 4;
    let changed = state.computeSlot(state, state.config.dynamicSlots[idx]);
    return state.status[idx] = 2 | changed;
  }
  function getAddr(state, addr) {
    return addr & 1 ? state.config.staticValues[addr >> 1] : state.values[addr >> 1];
  }
  var languageData = /* @__PURE__ */ Facet.define();
  var allowMultipleSelections = /* @__PURE__ */ Facet.define({
    combine: (values) => values.some((v) => v),
    static: true
  });
  var lineSeparator = /* @__PURE__ */ Facet.define({
    combine: (values) => values.length ? values[0] : void 0,
    static: true
  });
  var changeFilter = /* @__PURE__ */ Facet.define();
  var transactionFilter = /* @__PURE__ */ Facet.define();
  var transactionExtender = /* @__PURE__ */ Facet.define();
  var readOnly = /* @__PURE__ */ Facet.define({
    combine: (values) => values.length ? values[0] : false
  });
  var Annotation = class {
    /**
    @internal
    */
    constructor(type, value) {
      this.type = type;
      this.value = value;
    }
    /**
    Define a new type of annotation.
    */
    static define() {
      return new AnnotationType();
    }
  };
  var AnnotationType = class {
    /**
    Create an instance of this annotation.
    */
    of(value) {
      return new Annotation(this, value);
    }
  };
  var StateEffectType = class {
    /**
    @internal
    */
    constructor(map) {
      this.map = map;
    }
    /**
    Create a [state effect](https://codemirror.net/6/docs/ref/#state.StateEffect) instance of this
    type.
    */
    of(value) {
      return new StateEffect(this, value);
    }
  };
  var StateEffect = class _StateEffect {
    /**
    @internal
    */
    constructor(type, value) {
      this.type = type;
      this.value = value;
    }
    /**
    Map this effect through a position mapping. Will return
    `undefined` when that ends up deleting the effect.
    */
    map(mapping) {
      let mapped = this.type.map(this.value, mapping);
      return mapped === void 0 ? void 0 : mapped == this.value ? this : new _StateEffect(this.type, mapped);
    }
    /**
    Tells you whether this effect object is of a given
    [type](https://codemirror.net/6/docs/ref/#state.StateEffectType).
    */
    is(type) {
      return this.type == type;
    }
    /**
    Define a new effect type. The type parameter indicates the type
    of values that his effect holds. It should be a type that
    doesn't include `undefined`, since that is used in
    [mapping](https://codemirror.net/6/docs/ref/#state.StateEffect.map) to indicate that an effect is
    removed.
    */
    static define(spec = {}) {
      return new StateEffectType(spec.map || ((v) => v));
    }
    /**
    Map an array of effects through a change set.
    */
    static mapEffects(effects, mapping) {
      if (!effects.length)
        return effects;
      let result = [];
      for (let effect of effects) {
        let mapped = effect.map(mapping);
        if (mapped)
          result.push(mapped);
      }
      return result;
    }
  };
  StateEffect.reconfigure = /* @__PURE__ */ StateEffect.define();
  StateEffect.appendConfig = /* @__PURE__ */ StateEffect.define();
  var Transaction = class _Transaction {
    constructor(startState, changes, selection, effects, annotations, scrollIntoView) {
      this.startState = startState;
      this.changes = changes;
      this.selection = selection;
      this.effects = effects;
      this.annotations = annotations;
      this.scrollIntoView = scrollIntoView;
      this._doc = null;
      this._state = null;
      if (selection)
        checkSelection(selection, changes.newLength);
      if (!annotations.some((a) => a.type == _Transaction.time))
        this.annotations = annotations.concat(_Transaction.time.of(Date.now()));
    }
    /**
    @internal
    */
    static create(startState, changes, selection, effects, annotations, scrollIntoView) {
      return new _Transaction(startState, changes, selection, effects, annotations, scrollIntoView);
    }
    /**
    The new document produced by the transaction. Contrary to
    [`.state`](https://codemirror.net/6/docs/ref/#state.Transaction.state)`.doc`, accessing this won't
    force the entire new state to be computed right away, so it is
    recommended that [transaction
    filters](https://codemirror.net/6/docs/ref/#state.EditorState^transactionFilter) use this getter
    when they need to look at the new document.
    */
    get newDoc() {
      return this._doc || (this._doc = this.changes.apply(this.startState.doc));
    }
    /**
    The new selection produced by the transaction. If
    [`this.selection`](https://codemirror.net/6/docs/ref/#state.Transaction.selection) is undefined,
    this will [map](https://codemirror.net/6/docs/ref/#state.EditorSelection.map) the start state's
    current selection through the changes made by the transaction.
    */
    get newSelection() {
      return this.selection || this.startState.selection.map(this.changes);
    }
    /**
    The new state created by the transaction. Computed on demand
    (but retained for subsequent access), so it is recommended not to
    access it in [transaction
    filters](https://codemirror.net/6/docs/ref/#state.EditorState^transactionFilter) when possible.
    */
    get state() {
      if (!this._state)
        this.startState.applyTransaction(this);
      return this._state;
    }
    /**
    Get the value of the given annotation type, if any.
    */
    annotation(type) {
      for (let ann of this.annotations)
        if (ann.type == type)
          return ann.value;
      return void 0;
    }
    /**
    Indicates whether the transaction changed the document.
    */
    get docChanged() {
      return !this.changes.empty;
    }
    /**
    Indicates whether this transaction reconfigures the state
    (through a [configuration compartment](https://codemirror.net/6/docs/ref/#state.Compartment) or
    with a top-level configuration
    [effect](https://codemirror.net/6/docs/ref/#state.StateEffect^reconfigure).
    */
    get reconfigured() {
      return this.startState.config != this.state.config;
    }
    /**
    Returns true if the transaction has a [user
    event](https://codemirror.net/6/docs/ref/#state.Transaction^userEvent) annotation that is equal to
    or more specific than `event`. For example, if the transaction
    has `"select.pointer"` as user event, `"select"` and
    `"select.pointer"` will match it.
    */
    isUserEvent(event) {
      let e = this.annotation(_Transaction.userEvent);
      return !!(e && (e == event || e.length > event.length && e.slice(0, event.length) == event && e[event.length] == "."));
    }
  };
  Transaction.time = /* @__PURE__ */ Annotation.define();
  Transaction.userEvent = /* @__PURE__ */ Annotation.define();
  Transaction.addToHistory = /* @__PURE__ */ Annotation.define();
  Transaction.remote = /* @__PURE__ */ Annotation.define();
  function joinRanges(a, b) {
    let result = [];
    for (let iA = 0, iB = 0; ; ) {
      let from, to;
      if (iA < a.length && (iB == b.length || b[iB] >= a[iA])) {
        from = a[iA++];
        to = a[iA++];
      } else if (iB < b.length) {
        from = b[iB++];
        to = b[iB++];
      } else
        return result;
      if (!result.length || result[result.length - 1] < from)
        result.push(from, to);
      else if (result[result.length - 1] < to)
        result[result.length - 1] = to;
    }
  }
  function mergeTransaction(a, b, sequential) {
    var _a;
    let mapForA, mapForB, changes;
    if (sequential) {
      mapForA = b.changes;
      mapForB = ChangeSet.empty(b.changes.length);
      changes = a.changes.compose(b.changes);
    } else {
      mapForA = b.changes.map(a.changes);
      mapForB = a.changes.mapDesc(b.changes, true);
      changes = a.changes.compose(mapForA);
    }
    return {
      changes,
      selection: b.selection ? b.selection.map(mapForB) : (_a = a.selection) === null || _a === void 0 ? void 0 : _a.map(mapForA),
      effects: StateEffect.mapEffects(a.effects, mapForA).concat(StateEffect.mapEffects(b.effects, mapForB)),
      annotations: a.annotations.length ? a.annotations.concat(b.annotations) : b.annotations,
      scrollIntoView: a.scrollIntoView || b.scrollIntoView
    };
  }
  function resolveTransactionInner(state, spec, docSize) {
    let sel = spec.selection, annotations = asArray(spec.annotations);
    if (spec.userEvent)
      annotations = annotations.concat(Transaction.userEvent.of(spec.userEvent));
    return {
      changes: spec.changes instanceof ChangeSet ? spec.changes : ChangeSet.of(spec.changes || [], docSize, state.facet(lineSeparator)),
      selection: sel && (sel instanceof EditorSelection ? sel : EditorSelection.single(sel.anchor, sel.head)),
      effects: asArray(spec.effects),
      annotations,
      scrollIntoView: !!spec.scrollIntoView
    };
  }
  function resolveTransaction(state, specs, filter) {
    let s = resolveTransactionInner(state, specs.length ? specs[0] : {}, state.doc.length);
    if (specs.length && specs[0].filter === false)
      filter = false;
    for (let i = 1; i < specs.length; i++) {
      if (specs[i].filter === false)
        filter = false;
      let seq = !!specs[i].sequential;
      s = mergeTransaction(s, resolveTransactionInner(state, specs[i], seq ? s.changes.newLength : state.doc.length), seq);
    }
    let tr = Transaction.create(state, s.changes, s.selection, s.effects, s.annotations, s.scrollIntoView);
    return extendTransaction(filter ? filterTransaction(tr) : tr);
  }
  function filterTransaction(tr) {
    let state = tr.startState;
    let result = true;
    for (let filter of state.facet(changeFilter)) {
      let value = filter(tr);
      if (value === false) {
        result = false;
        break;
      }
      if (Array.isArray(value))
        result = result === true ? value : joinRanges(result, value);
    }
    if (result !== true) {
      let changes, back;
      if (result === false) {
        back = tr.changes.invertedDesc;
        changes = ChangeSet.empty(state.doc.length);
      } else {
        let filtered = tr.changes.filter(result);
        changes = filtered.changes;
        back = filtered.filtered.mapDesc(filtered.changes).invertedDesc;
      }
      tr = Transaction.create(state, changes, tr.selection && tr.selection.map(back), StateEffect.mapEffects(tr.effects, back), tr.annotations, tr.scrollIntoView);
    }
    let filters = state.facet(transactionFilter);
    for (let i = filters.length - 1; i >= 0; i--) {
      let filtered = filters[i](tr);
      if (filtered instanceof Transaction)
        tr = filtered;
      else if (Array.isArray(filtered) && filtered.length == 1 && filtered[0] instanceof Transaction)
        tr = filtered[0];
      else
        tr = resolveTransaction(state, asArray(filtered), false);
    }
    return tr;
  }
  function extendTransaction(tr) {
    let state = tr.startState, extenders = state.facet(transactionExtender), spec = tr;
    for (let i = extenders.length - 1; i >= 0; i--) {
      let extension = extenders[i](tr);
      if (extension && Object.keys(extension).length)
        spec = mergeTransaction(spec, resolveTransactionInner(state, extension, tr.changes.newLength), true);
    }
    return spec == tr ? tr : Transaction.create(state, tr.changes, tr.selection, spec.effects, spec.annotations, spec.scrollIntoView);
  }
  var none = [];
  function asArray(value) {
    return value == null ? none : Array.isArray(value) ? value : [value];
  }
  var CharCategory = /* @__PURE__ */ (function(CharCategory2) {
    CharCategory2[CharCategory2["Word"] = 0] = "Word";
    CharCategory2[CharCategory2["Space"] = 1] = "Space";
    CharCategory2[CharCategory2["Other"] = 2] = "Other";
    return CharCategory2;
  })(CharCategory || (CharCategory = {}));
  var nonASCIISingleCaseWordChar = /[\u00df\u0587\u0590-\u05f4\u0600-\u06ff\u3040-\u309f\u30a0-\u30ff\u3400-\u4db5\u4e00-\u9fcc\uac00-\ud7af]/;
  var wordChar;
  try {
    wordChar = /* @__PURE__ */ new RegExp("[\\p{Alphabetic}\\p{Number}_]", "u");
  } catch (_) {
  }
  function hasWordChar(str) {
    if (wordChar)
      return wordChar.test(str);
    for (let i = 0; i < str.length; i++) {
      let ch = str[i];
      if (/\w/.test(ch) || ch > "\x80" && (ch.toUpperCase() != ch.toLowerCase() || nonASCIISingleCaseWordChar.test(ch)))
        return true;
    }
    return false;
  }
  function makeCategorizer(wordChars) {
    return (char) => {
      if (!/\S/.test(char))
        return CharCategory.Space;
      if (hasWordChar(char))
        return CharCategory.Word;
      for (let i = 0; i < wordChars.length; i++)
        if (char.indexOf(wordChars[i]) > -1)
          return CharCategory.Word;
      return CharCategory.Other;
    };
  }
  var EditorState = class _EditorState {
    constructor(config, doc, selection, values, computeSlot, tr) {
      this.config = config;
      this.doc = doc;
      this.selection = selection;
      this.values = values;
      this.status = config.statusTemplate.slice();
      this.computeSlot = computeSlot;
      if (tr)
        tr._state = this;
      for (let i = 0; i < this.config.dynamicSlots.length; i++)
        ensureAddr(this, i << 1);
      this.computeSlot = null;
    }
    field(field, require2 = true) {
      let addr = this.config.address[field.id];
      if (addr == null) {
        if (require2)
          throw new RangeError("Field is not present in this state");
        return void 0;
      }
      ensureAddr(this, addr);
      return getAddr(this, addr);
    }
    /**
    Create a [transaction](https://codemirror.net/6/docs/ref/#state.Transaction) that updates this
    state. Any number of [transaction specs](https://codemirror.net/6/docs/ref/#state.TransactionSpec)
    can be passed. Unless
    [`sequential`](https://codemirror.net/6/docs/ref/#state.TransactionSpec.sequential) is set, the
    [changes](https://codemirror.net/6/docs/ref/#state.TransactionSpec.changes) (if any) of each spec
    are assumed to start in the _current_ document (not the document
    produced by previous specs), and its
    [selection](https://codemirror.net/6/docs/ref/#state.TransactionSpec.selection) and
    [effects](https://codemirror.net/6/docs/ref/#state.TransactionSpec.effects) are assumed to refer
    to the document created by its _own_ changes. The resulting
    transaction contains the combined effect of all the different
    specs. For [selection](https://codemirror.net/6/docs/ref/#state.TransactionSpec.selection), later
    specs take precedence over earlier ones.
    */
    update(...specs) {
      return resolveTransaction(this, specs, true);
    }
    /**
    @internal
    */
    applyTransaction(tr) {
      let conf = this.config, { base, compartments } = conf;
      for (let effect of tr.effects) {
        if (effect.is(Compartment.reconfigure)) {
          if (conf) {
            compartments = /* @__PURE__ */ new Map();
            conf.compartments.forEach((val, key) => compartments.set(key, val));
            conf = null;
          }
          compartments.set(effect.value.compartment, effect.value.extension);
        } else if (effect.is(StateEffect.reconfigure)) {
          conf = null;
          base = effect.value;
        } else if (effect.is(StateEffect.appendConfig)) {
          conf = null;
          base = asArray(base).concat(effect.value);
        }
      }
      let startValues;
      if (!conf) {
        conf = Configuration.resolve(base, compartments, this);
        let intermediateState = new _EditorState(conf, this.doc, this.selection, conf.dynamicSlots.map(() => null), (state, slot) => slot.reconfigure(state, this), null);
        startValues = intermediateState.values;
      } else {
        startValues = tr.startState.values.slice();
      }
      let selection = tr.startState.facet(allowMultipleSelections) ? tr.newSelection : tr.newSelection.asSingle();
      new _EditorState(conf, tr.newDoc, selection, startValues, (state, slot) => slot.update(state, tr), tr);
    }
    /**
    Create a [transaction spec](https://codemirror.net/6/docs/ref/#state.TransactionSpec) that
    replaces every selection range with the given content.
    */
    replaceSelection(text) {
      if (typeof text == "string")
        text = this.toText(text);
      return this.changeByRange((range) => ({
        changes: { from: range.from, to: range.to, insert: text },
        range: EditorSelection.cursor(range.from + text.length)
      }));
    }
    /**
    Create a set of changes and a new selection by running the given
    function for each range in the active selection. The function
    can return an optional set of changes (in the coordinate space
    of the start document), plus an updated range (in the coordinate
    space of the document produced by the call's own changes). This
    method will merge all the changes and ranges into a single
    changeset and selection, and return it as a [transaction
    spec](https://codemirror.net/6/docs/ref/#state.TransactionSpec), which can be passed to
    [`update`](https://codemirror.net/6/docs/ref/#state.EditorState.update).
    */
    changeByRange(f) {
      let sel = this.selection;
      let result1 = f(sel.ranges[0]);
      let changes = this.changes(result1.changes), ranges = [result1.range];
      let effects = asArray(result1.effects);
      for (let i = 1; i < sel.ranges.length; i++) {
        let result = f(sel.ranges[i]);
        let newChanges = this.changes(result.changes), newMapped = newChanges.map(changes);
        for (let j = 0; j < i; j++)
          ranges[j] = ranges[j].map(newMapped);
        let mapBy = changes.mapDesc(newChanges, true);
        ranges.push(result.range.map(mapBy));
        changes = changes.compose(newMapped);
        effects = StateEffect.mapEffects(effects, newMapped).concat(StateEffect.mapEffects(asArray(result.effects), mapBy));
      }
      return {
        changes,
        selection: EditorSelection.create(ranges, sel.mainIndex),
        effects
      };
    }
    /**
    Create a [change set](https://codemirror.net/6/docs/ref/#state.ChangeSet) from the given change
    description, taking the state's document length and line
    separator into account.
    */
    changes(spec = []) {
      if (spec instanceof ChangeSet)
        return spec;
      return ChangeSet.of(spec, this.doc.length, this.facet(_EditorState.lineSeparator));
    }
    /**
    Using the state's [line
    separator](https://codemirror.net/6/docs/ref/#state.EditorState^lineSeparator), create a
    [`Text`](https://codemirror.net/6/docs/ref/#state.Text) instance from the given string.
    */
    toText(string) {
      return Text2.of(string.split(this.facet(_EditorState.lineSeparator) || DefaultSplit));
    }
    /**
    Return the given range of the document as a string.
    */
    sliceDoc(from = 0, to = this.doc.length) {
      return this.doc.sliceString(from, to, this.lineBreak);
    }
    /**
    Get the value of a state [facet](https://codemirror.net/6/docs/ref/#state.Facet).
    */
    facet(facet) {
      let addr = this.config.address[facet.id];
      if (addr == null)
        return facet.default;
      ensureAddr(this, addr);
      return getAddr(this, addr);
    }
    /**
    Convert this state to a JSON-serializable object. When custom
    fields should be serialized, you can pass them in as an object
    mapping property names (in the resulting object, which should
    not use `doc` or `selection`) to fields.
    */
    toJSON(fields) {
      let result = {
        doc: this.sliceDoc(),
        selection: this.selection.toJSON()
      };
      if (fields)
        for (let prop in fields) {
          let value = fields[prop];
          if (value instanceof StateField && this.config.address[value.id] != null)
            result[prop] = value.spec.toJSON(this.field(fields[prop]), this);
        }
      return result;
    }
    /**
    Deserialize a state from its JSON representation. When custom
    fields should be deserialized, pass the same object you passed
    to [`toJSON`](https://codemirror.net/6/docs/ref/#state.EditorState.toJSON) when serializing as
    third argument.
    */
    static fromJSON(json, config = {}, fields) {
      if (!json || typeof json.doc != "string")
        throw new RangeError("Invalid JSON representation for EditorState");
      let fieldInit = [];
      if (fields)
        for (let prop in fields) {
          if (Object.prototype.hasOwnProperty.call(json, prop)) {
            let field = fields[prop], value = json[prop];
            fieldInit.push(field.init((state) => field.spec.fromJSON(value, state)));
          }
        }
      return _EditorState.create({
        doc: json.doc,
        selection: EditorSelection.fromJSON(json.selection),
        extensions: config.extensions ? fieldInit.concat([config.extensions]) : fieldInit
      });
    }
    /**
    Create a new state. You'll usually only need this when
    initializing an editor—updated states are created by applying
    transactions.
    */
    static create(config = {}) {
      let configuration = Configuration.resolve(config.extensions || [], /* @__PURE__ */ new Map());
      let doc = config.doc instanceof Text2 ? config.doc : Text2.of((config.doc || "").split(configuration.staticFacet(_EditorState.lineSeparator) || DefaultSplit));
      let selection = !config.selection ? EditorSelection.single(0) : config.selection instanceof EditorSelection ? config.selection : EditorSelection.single(config.selection.anchor, config.selection.head);
      checkSelection(selection, doc.length);
      if (!configuration.staticFacet(allowMultipleSelections))
        selection = selection.asSingle();
      return new _EditorState(configuration, doc, selection, configuration.dynamicSlots.map(() => null), (state, slot) => slot.create(state), null);
    }
    /**
    The size (in columns) of a tab in the document, determined by
    the [`tabSize`](https://codemirror.net/6/docs/ref/#state.EditorState^tabSize) facet.
    */
    get tabSize() {
      return this.facet(_EditorState.tabSize);
    }
    /**
    Get the proper [line-break](https://codemirror.net/6/docs/ref/#state.EditorState^lineSeparator)
    string for this state.
    */
    get lineBreak() {
      return this.facet(_EditorState.lineSeparator) || "\n";
    }
    /**
    Returns true when the editor is
    [configured](https://codemirror.net/6/docs/ref/#state.EditorState^readOnly) to be read-only.
    */
    get readOnly() {
      return this.facet(readOnly);
    }
    /**
    Look up a translation for the given phrase (via the
    [`phrases`](https://codemirror.net/6/docs/ref/#state.EditorState^phrases) facet), or return the
    original string if no translation is found.
    
    If additional arguments are passed, they will be inserted in
    place of markers like `$1` (for the first value) and `$2`, etc.
    A single `$` is equivalent to `$1`, and `$$` will produce a
    literal dollar sign.
    */
    phrase(phrase, ...insert2) {
      for (let map of this.facet(_EditorState.phrases))
        if (Object.prototype.hasOwnProperty.call(map, phrase)) {
          phrase = map[phrase];
          break;
        }
      if (insert2.length)
        phrase = phrase.replace(/\$(\$|\d*)/g, (m, i) => {
          if (i == "$")
            return "$";
          let n = +(i || 1);
          return !n || n > insert2.length ? m : insert2[n - 1];
        });
      return phrase;
    }
    /**
    Find the values for a given language data field, provided by the
    the [`languageData`](https://codemirror.net/6/docs/ref/#state.EditorState^languageData) facet.
    
    Examples of language data fields are...
    
    - [`"commentTokens"`](https://codemirror.net/6/docs/ref/#commands.CommentTokens) for specifying
      comment syntax.
    - [`"autocomplete"`](https://codemirror.net/6/docs/ref/#autocomplete.autocompletion^config.override)
      for providing language-specific completion sources.
    - [`"wordChars"`](https://codemirror.net/6/docs/ref/#state.EditorState.charCategorizer) for adding
      characters that should be considered part of words in this
      language.
    - [`"closeBrackets"`](https://codemirror.net/6/docs/ref/#autocomplete.CloseBracketConfig) controls
      bracket closing behavior.
    */
    languageDataAt(name, pos, side = -1) {
      let values = [];
      for (let provider of this.facet(languageData)) {
        for (let result of provider(this, pos, side)) {
          if (Object.prototype.hasOwnProperty.call(result, name))
            values.push(result[name]);
        }
      }
      return values;
    }
    /**
    Return a function that can categorize strings (expected to
    represent a single [grapheme cluster](https://codemirror.net/6/docs/ref/#state.findClusterBreak))
    into one of:
    
     - Word (contains an alphanumeric character or a character
       explicitly listed in the local language's `"wordChars"`
       language data, which should be a string)
     - Space (contains only whitespace)
     - Other (anything else)
    */
    charCategorizer(at) {
      let chars = this.languageDataAt("wordChars", at);
      return makeCategorizer(chars.length ? chars[0] : "");
    }
    /**
    Find the word at the given position, meaning the range
    containing all [word](https://codemirror.net/6/docs/ref/#state.CharCategory.Word) characters
    around it. If no word characters are adjacent to the position,
    this returns null.
    */
    wordAt(pos) {
      let { text, from, length } = this.doc.lineAt(pos);
      let cat = this.charCategorizer(pos);
      let start = pos - from, end = pos - from;
      while (start > 0) {
        let prev = findClusterBreak2(text, start, false);
        if (cat(text.slice(prev, start)) != CharCategory.Word)
          break;
        start = prev;
      }
      while (end < length) {
        let next = findClusterBreak2(text, end);
        if (cat(text.slice(end, next)) != CharCategory.Word)
          break;
        end = next;
      }
      return start == end ? null : EditorSelection.range(start + from, end + from);
    }
  };
  EditorState.allowMultipleSelections = allowMultipleSelections;
  EditorState.tabSize = /* @__PURE__ */ Facet.define({
    combine: (values) => values.length ? values[0] : 4
  });
  EditorState.lineSeparator = lineSeparator;
  EditorState.readOnly = readOnly;
  EditorState.phrases = /* @__PURE__ */ Facet.define({
    compare(a, b) {
      let kA = Object.keys(a), kB = Object.keys(b);
      return kA.length == kB.length && kA.every((k) => a[k] == b[k]);
    }
  });
  EditorState.languageData = languageData;
  EditorState.changeFilter = changeFilter;
  EditorState.transactionFilter = transactionFilter;
  EditorState.transactionExtender = transactionExtender;
  Compartment.reconfigure = /* @__PURE__ */ StateEffect.define();
  var RangeValue = class {
    /**
    Compare this value with another value. Used when comparing
    rangesets. The default implementation compares by identity.
    Unless you are only creating a fixed number of unique instances
    of your value type, it is a good idea to implement this
    properly.
    */
    eq(other) {
      return this == other;
    }
    /**
    Create a [range](https://codemirror.net/6/docs/ref/#state.Range) with this value.
    */
    range(from, to = from) {
      return Range2.create(from, to, this);
    }
  };
  RangeValue.prototype.startSide = RangeValue.prototype.endSide = 0;
  RangeValue.prototype.point = false;
  RangeValue.prototype.mapMode = MapMode.TrackDel;
  function cmpVal(a, b) {
    return a == b || a.constructor == b.constructor && a.eq(b);
  }
  var Range2 = class _Range {
    constructor(from, to, value) {
      this.from = from;
      this.to = to;
      this.value = value;
    }
    /**
    @internal
    */
    static create(from, to, value) {
      return new _Range(from, to, value);
    }
  };
  function cmpRange(a, b) {
    return a.from - b.from || a.value.startSide - b.value.startSide;
  }
  var Chunk = class _Chunk {
    constructor(from, to, value, maxPoint) {
      this.from = from;
      this.to = to;
      this.value = value;
      this.maxPoint = maxPoint;
    }
    get length() {
      return this.to[this.to.length - 1];
    }
    // Find the index of the given position and side. Use the ranges'
    // `from` pos when `end == false`, `to` when `end == true`.
    findIndex(pos, side, end, startAt = 0) {
      let arr = end ? this.to : this.from;
      for (let lo = startAt, hi = arr.length; ; ) {
        if (lo == hi)
          return lo;
        let mid = lo + hi >> 1;
        let diff = arr[mid] - pos || (end ? this.value[mid].endSide : this.value[mid].startSide) - side;
        if (mid == lo)
          return diff >= 0 ? lo : hi;
        if (diff >= 0)
          hi = mid;
        else
          lo = mid + 1;
      }
    }
    between(offset, from, to, f) {
      for (let i = this.findIndex(from, -1e9, true), e = this.findIndex(to, 1e9, false, i); i < e; i++)
        if (f(this.from[i] + offset, this.to[i] + offset, this.value[i]) === false)
          return false;
    }
    map(offset, changes) {
      let value = [], from = [], to = [], newPos = -1, maxPoint = -1;
      for (let i = 0; i < this.value.length; i++) {
        let val = this.value[i], curFrom = this.from[i] + offset, curTo = this.to[i] + offset, newFrom, newTo;
        if (curFrom == curTo) {
          let mapped = changes.mapPos(curFrom, val.startSide, val.mapMode);
          if (mapped == null)
            continue;
          newFrom = newTo = mapped;
          if (val.startSide != val.endSide) {
            newTo = changes.mapPos(curFrom, val.endSide);
            if (newTo < newFrom)
              continue;
          }
        } else {
          newFrom = changes.mapPos(curFrom, val.startSide);
          newTo = changes.mapPos(curTo, val.endSide);
          if (newFrom > newTo || newFrom == newTo && val.startSide > 0 && val.endSide <= 0)
            continue;
        }
        if ((newTo - newFrom || val.endSide - val.startSide) < 0)
          continue;
        if (newPos < 0)
          newPos = newFrom;
        if (val.point)
          maxPoint = Math.max(maxPoint, newTo - newFrom);
        value.push(val);
        from.push(newFrom - newPos);
        to.push(newTo - newPos);
      }
      return { mapped: value.length ? new _Chunk(from, to, value, maxPoint) : null, pos: newPos };
    }
  };
  var RangeSet = class _RangeSet {
    constructor(chunkPos, chunk, nextLayer, maxPoint) {
      this.chunkPos = chunkPos;
      this.chunk = chunk;
      this.nextLayer = nextLayer;
      this.maxPoint = maxPoint;
    }
    /**
    @internal
    */
    static create(chunkPos, chunk, nextLayer, maxPoint) {
      return new _RangeSet(chunkPos, chunk, nextLayer, maxPoint);
    }
    /**
    @internal
    */
    get length() {
      let last = this.chunk.length - 1;
      return last < 0 ? 0 : Math.max(this.chunkEnd(last), this.nextLayer.length);
    }
    /**
    The number of ranges in the set.
    */
    get size() {
      if (this.isEmpty)
        return 0;
      let size = this.nextLayer.size;
      for (let chunk of this.chunk)
        size += chunk.value.length;
      return size;
    }
    /**
    @internal
    */
    chunkEnd(index) {
      return this.chunkPos[index] + this.chunk[index].length;
    }
    /**
    Update the range set, optionally adding new ranges or filtering
    out existing ones.
    
    (Note: The type parameter is just there as a kludge to work
    around TypeScript variance issues that prevented `RangeSet<X>`
    from being a subtype of `RangeSet<Y>` when `X` is a subtype of
    `Y`.)
    */
    update(updateSpec) {
      let { add = [], sort = false, filterFrom = 0, filterTo = this.length } = updateSpec;
      let filter = updateSpec.filter;
      if (add.length == 0 && !filter)
        return this;
      if (sort)
        add = add.slice().sort(cmpRange);
      if (this.isEmpty)
        return add.length ? _RangeSet.of(add) : this;
      let cur = new LayerCursor(this, null, -1).goto(0), i = 0, spill = [];
      let builder = new RangeSetBuilder();
      while (cur.value || i < add.length) {
        if (i < add.length && (cur.from - add[i].from || cur.startSide - add[i].value.startSide) >= 0) {
          let range = add[i++];
          if (!builder.addInner(range.from, range.to, range.value))
            spill.push(range);
        } else if (cur.rangeIndex == 1 && cur.chunkIndex < this.chunk.length && (i == add.length || this.chunkEnd(cur.chunkIndex) < add[i].from) && (!filter || filterFrom > this.chunkEnd(cur.chunkIndex) || filterTo < this.chunkPos[cur.chunkIndex]) && builder.addChunk(this.chunkPos[cur.chunkIndex], this.chunk[cur.chunkIndex])) {
          cur.nextChunk();
        } else {
          if (!filter || filterFrom > cur.to || filterTo < cur.from || filter(cur.from, cur.to, cur.value)) {
            if (!builder.addInner(cur.from, cur.to, cur.value))
              spill.push(Range2.create(cur.from, cur.to, cur.value));
          }
          cur.next();
        }
      }
      return builder.finishInner(this.nextLayer.isEmpty && !spill.length ? _RangeSet.empty : this.nextLayer.update({ add: spill, filter, filterFrom, filterTo }));
    }
    /**
    Map this range set through a set of changes, return the new set.
    */
    map(changes) {
      if (changes.empty || this.isEmpty)
        return this;
      let chunks = [], chunkPos = [], maxPoint = -1;
      for (let i = 0; i < this.chunk.length; i++) {
        let start = this.chunkPos[i], chunk = this.chunk[i];
        let touch = changes.touchesRange(start, start + chunk.length);
        if (touch === false) {
          maxPoint = Math.max(maxPoint, chunk.maxPoint);
          chunks.push(chunk);
          chunkPos.push(changes.mapPos(start));
        } else if (touch === true) {
          let { mapped, pos } = chunk.map(start, changes);
          if (mapped) {
            maxPoint = Math.max(maxPoint, mapped.maxPoint);
            chunks.push(mapped);
            chunkPos.push(pos);
          }
        }
      }
      let next = this.nextLayer.map(changes);
      return chunks.length == 0 ? next : new _RangeSet(chunkPos, chunks, next || _RangeSet.empty, maxPoint);
    }
    /**
    Iterate over the ranges that touch the region `from` to `to`,
    calling `f` for each. There is no guarantee that the ranges will
    be reported in any specific order. When the callback returns
    `false`, iteration stops.
    */
    between(from, to, f) {
      if (this.isEmpty)
        return;
      for (let i = 0; i < this.chunk.length; i++) {
        let start = this.chunkPos[i], chunk = this.chunk[i];
        if (to >= start && from <= start + chunk.length && chunk.between(start, from - start, to - start, f) === false)
          return;
      }
      this.nextLayer.between(from, to, f);
    }
    /**
    Iterate over the ranges in this set, in order, including all
    ranges that end at or after `from`.
    */
    iter(from = 0) {
      return HeapCursor.from([this]).goto(from);
    }
    /**
    @internal
    */
    get isEmpty() {
      return this.nextLayer == this;
    }
    /**
    Iterate over the ranges in a collection of sets, in order,
    starting from `from`.
    */
    static iter(sets, from = 0) {
      return HeapCursor.from(sets).goto(from);
    }
    /**
    Iterate over two groups of sets, calling methods on `comparator`
    to notify it of possible differences.
    */
    static compare(oldSets, newSets, textDiff, comparator, minPointSize = -1) {
      let a = oldSets.filter((set) => set.maxPoint > 0 || !set.isEmpty && set.maxPoint >= minPointSize);
      let b = newSets.filter((set) => set.maxPoint > 0 || !set.isEmpty && set.maxPoint >= minPointSize);
      let sharedChunks = findSharedChunks(a, b, textDiff);
      let sideA = new SpanCursor(a, sharedChunks, minPointSize);
      let sideB = new SpanCursor(b, sharedChunks, minPointSize);
      textDiff.iterGaps((fromA, fromB, length) => compare(sideA, fromA, sideB, fromB, length, comparator));
      if (textDiff.empty && textDiff.length == 0)
        compare(sideA, 0, sideB, 0, 0, comparator);
    }
    /**
    Compare the contents of two groups of range sets, returning true
    if they are equivalent in the given range.
    */
    static eq(oldSets, newSets, from = 0, to) {
      if (to == null)
        to = 1e9 - 1;
      let a = oldSets.filter((set) => !set.isEmpty && newSets.indexOf(set) < 0);
      let b = newSets.filter((set) => !set.isEmpty && oldSets.indexOf(set) < 0);
      if (a.length != b.length)
        return false;
      if (!a.length)
        return true;
      let sharedChunks = findSharedChunks(a, b);
      let sideA = new SpanCursor(a, sharedChunks, 0).goto(from), sideB = new SpanCursor(b, sharedChunks, 0).goto(from);
      for (; ; ) {
        if (sideA.to != sideB.to || !sameValues(sideA.active, sideB.active) || sideA.point && (!sideB.point || !cmpVal(sideA.point, sideB.point)))
          return false;
        if (sideA.to > to)
          return true;
        sideA.next();
        sideB.next();
      }
    }
    /**
    Iterate over a group of range sets at the same time, notifying
    the iterator about the ranges covering every given piece of
    content. Returns the open count (see
    [`SpanIterator.span`](https://codemirror.net/6/docs/ref/#state.SpanIterator.span)) at the end
    of the iteration.
    */
    static spans(sets, from, to, iterator, minPointSize = -1) {
      let cursor = new SpanCursor(sets, null, minPointSize).goto(from), pos = from;
      let openRanges = cursor.openStart;
      for (; ; ) {
        let curTo = Math.min(cursor.to, to);
        if (cursor.point) {
          let active = cursor.activeForPoint(cursor.to);
          let openCount = cursor.pointFrom < from ? active.length + 1 : cursor.point.startSide < 0 ? active.length : Math.min(active.length, openRanges);
          iterator.point(pos, curTo, cursor.point, active, openCount, cursor.pointRank);
          openRanges = Math.min(cursor.openEnd(curTo), active.length);
        } else if (curTo > pos) {
          iterator.span(pos, curTo, cursor.active, openRanges);
          openRanges = cursor.openEnd(curTo);
        }
        if (cursor.to > to)
          return openRanges + (cursor.point && cursor.to > to ? 1 : 0);
        pos = cursor.to;
        cursor.next();
      }
    }
    /**
    Create a range set for the given range or array of ranges. By
    default, this expects the ranges to be _sorted_ (by start
    position and, if two start at the same position,
    `value.startSide`). You can pass `true` as second argument to
    cause the method to sort them.
    */
    static of(ranges, sort = false) {
      let build = new RangeSetBuilder();
      for (let range of ranges instanceof Range2 ? [ranges] : sort ? lazySort(ranges) : ranges)
        build.add(range.from, range.to, range.value);
      return build.finish();
    }
    /**
    Join an array of range sets into a single set.
    */
    static join(sets) {
      if (!sets.length)
        return _RangeSet.empty;
      let result = sets[sets.length - 1];
      for (let i = sets.length - 2; i >= 0; i--) {
        for (let layer = sets[i]; layer != _RangeSet.empty; layer = layer.nextLayer)
          result = new _RangeSet(layer.chunkPos, layer.chunk, result, Math.max(layer.maxPoint, result.maxPoint));
      }
      return result;
    }
  };
  RangeSet.empty = /* @__PURE__ */ new RangeSet([], [], null, -1);
  function lazySort(ranges) {
    if (ranges.length > 1)
      for (let prev = ranges[0], i = 1; i < ranges.length; i++) {
        let cur = ranges[i];
        if (cmpRange(prev, cur) > 0)
          return ranges.slice().sort(cmpRange);
        prev = cur;
      }
    return ranges;
  }
  RangeSet.empty.nextLayer = RangeSet.empty;
  var RangeSetBuilder = class _RangeSetBuilder {
    finishChunk(newArrays) {
      this.chunks.push(new Chunk(this.from, this.to, this.value, this.maxPoint));
      this.chunkPos.push(this.chunkStart);
      this.chunkStart = -1;
      this.setMaxPoint = Math.max(this.setMaxPoint, this.maxPoint);
      this.maxPoint = -1;
      if (newArrays) {
        this.from = [];
        this.to = [];
        this.value = [];
      }
    }
    /**
    Create an empty builder.
    */
    constructor() {
      this.chunks = [];
      this.chunkPos = [];
      this.chunkStart = -1;
      this.last = null;
      this.lastFrom = -1e9;
      this.lastTo = -1e9;
      this.from = [];
      this.to = [];
      this.value = [];
      this.maxPoint = -1;
      this.setMaxPoint = -1;
      this.nextLayer = null;
    }
    /**
    Add a range. Ranges should be added in sorted (by `from` and
    `value.startSide`) order.
    */
    add(from, to, value) {
      if (!this.addInner(from, to, value))
        (this.nextLayer || (this.nextLayer = new _RangeSetBuilder())).add(from, to, value);
    }
    /**
    @internal
    */
    addInner(from, to, value) {
      let diff = from - this.lastTo || value.startSide - this.last.endSide;
      if (diff <= 0 && (from - this.lastFrom || value.startSide - this.last.startSide) < 0)
        throw new Error("Ranges must be added sorted by `from` position and `startSide`");
      if (diff < 0)
        return false;
      if (this.from.length == 250)
        this.finishChunk(true);
      if (this.chunkStart < 0)
        this.chunkStart = from;
      this.from.push(from - this.chunkStart);
      this.to.push(to - this.chunkStart);
      this.last = value;
      this.lastFrom = from;
      this.lastTo = to;
      this.value.push(value);
      if (value.point)
        this.maxPoint = Math.max(this.maxPoint, to - from);
      return true;
    }
    /**
    @internal
    */
    addChunk(from, chunk) {
      if ((from - this.lastTo || chunk.value[0].startSide - this.last.endSide) < 0)
        return false;
      if (this.from.length)
        this.finishChunk(true);
      this.setMaxPoint = Math.max(this.setMaxPoint, chunk.maxPoint);
      this.chunks.push(chunk);
      this.chunkPos.push(from);
      let last = chunk.value.length - 1;
      this.last = chunk.value[last];
      this.lastFrom = chunk.from[last] + from;
      this.lastTo = chunk.to[last] + from;
      return true;
    }
    /**
    Finish the range set. Returns the new set. The builder can't be
    used anymore after this has been called.
    */
    finish() {
      return this.finishInner(RangeSet.empty);
    }
    /**
    @internal
    */
    finishInner(next) {
      if (this.from.length)
        this.finishChunk(false);
      if (this.chunks.length == 0)
        return next;
      let result = RangeSet.create(this.chunkPos, this.chunks, this.nextLayer ? this.nextLayer.finishInner(next) : next, this.setMaxPoint);
      this.from = null;
      return result;
    }
  };
  function findSharedChunks(a, b, textDiff) {
    let inA = /* @__PURE__ */ new Map();
    for (let set of a)
      for (let i = 0; i < set.chunk.length; i++)
        if (set.chunk[i].maxPoint <= 0)
          inA.set(set.chunk[i], set.chunkPos[i]);
    let shared = /* @__PURE__ */ new Set();
    for (let set of b)
      for (let i = 0; i < set.chunk.length; i++) {
        let known = inA.get(set.chunk[i]);
        if (known != null && (textDiff ? textDiff.mapPos(known) : known) == set.chunkPos[i] && !(textDiff === null || textDiff === void 0 ? void 0 : textDiff.touchesRange(known, known + set.chunk[i].length)))
          shared.add(set.chunk[i]);
      }
    return shared;
  }
  var LayerCursor = class {
    constructor(layer, skip, minPoint, rank = 0) {
      this.layer = layer;
      this.skip = skip;
      this.minPoint = minPoint;
      this.rank = rank;
    }
    get startSide() {
      return this.value ? this.value.startSide : 0;
    }
    get endSide() {
      return this.value ? this.value.endSide : 0;
    }
    goto(pos, side = -1e9) {
      this.chunkIndex = this.rangeIndex = 0;
      this.gotoInner(pos, side, false);
      return this;
    }
    gotoInner(pos, side, forward) {
      while (this.chunkIndex < this.layer.chunk.length) {
        let next = this.layer.chunk[this.chunkIndex];
        if (!(this.skip && this.skip.has(next) || this.layer.chunkEnd(this.chunkIndex) < pos || next.maxPoint < this.minPoint))
          break;
        this.chunkIndex++;
        forward = false;
      }
      if (this.chunkIndex < this.layer.chunk.length) {
        let rangeIndex = this.layer.chunk[this.chunkIndex].findIndex(pos - this.layer.chunkPos[this.chunkIndex], side, true);
        if (!forward || this.rangeIndex < rangeIndex)
          this.setRangeIndex(rangeIndex);
      }
      this.next();
    }
    forward(pos, side) {
      if ((this.to - pos || this.endSide - side) < 0)
        this.gotoInner(pos, side, true);
    }
    next() {
      for (; ; ) {
        if (this.chunkIndex == this.layer.chunk.length) {
          this.from = this.to = 1e9;
          this.value = null;
          break;
        } else {
          let chunkPos = this.layer.chunkPos[this.chunkIndex], chunk = this.layer.chunk[this.chunkIndex];
          let from = chunkPos + chunk.from[this.rangeIndex];
          this.from = from;
          this.to = chunkPos + chunk.to[this.rangeIndex];
          this.value = chunk.value[this.rangeIndex];
          this.setRangeIndex(this.rangeIndex + 1);
          if (this.minPoint < 0 || this.value.point && this.to - this.from >= this.minPoint)
            break;
        }
      }
    }
    setRangeIndex(index) {
      if (index == this.layer.chunk[this.chunkIndex].value.length) {
        this.chunkIndex++;
        if (this.skip) {
          while (this.chunkIndex < this.layer.chunk.length && this.skip.has(this.layer.chunk[this.chunkIndex]))
            this.chunkIndex++;
        }
        this.rangeIndex = 0;
      } else {
        this.rangeIndex = index;
      }
    }
    nextChunk() {
      this.chunkIndex++;
      this.rangeIndex = 0;
      this.next();
    }
    compare(other) {
      return this.from - other.from || this.startSide - other.startSide || this.rank - other.rank || this.to - other.to || this.endSide - other.endSide;
    }
  };
  var HeapCursor = class _HeapCursor {
    constructor(heap) {
      this.heap = heap;
    }
    static from(sets, skip = null, minPoint = -1) {
      let heap = [];
      for (let i = 0; i < sets.length; i++) {
        for (let cur = sets[i]; !cur.isEmpty; cur = cur.nextLayer) {
          if (cur.maxPoint >= minPoint)
            heap.push(new LayerCursor(cur, skip, minPoint, i));
        }
      }
      return heap.length == 1 ? heap[0] : new _HeapCursor(heap);
    }
    get startSide() {
      return this.value ? this.value.startSide : 0;
    }
    goto(pos, side = -1e9) {
      for (let cur of this.heap)
        cur.goto(pos, side);
      for (let i = this.heap.length >> 1; i >= 0; i--)
        heapBubble(this.heap, i);
      this.next();
      return this;
    }
    forward(pos, side) {
      for (let cur of this.heap)
        cur.forward(pos, side);
      for (let i = this.heap.length >> 1; i >= 0; i--)
        heapBubble(this.heap, i);
      if ((this.to - pos || this.value.endSide - side) < 0)
        this.next();
    }
    next() {
      if (this.heap.length == 0) {
        this.from = this.to = 1e9;
        this.value = null;
        this.rank = -1;
      } else {
        let top = this.heap[0];
        this.from = top.from;
        this.to = top.to;
        this.value = top.value;
        this.rank = top.rank;
        if (top.value)
          top.next();
        heapBubble(this.heap, 0);
      }
    }
  };
  function heapBubble(heap, index) {
    for (let cur = heap[index]; ; ) {
      let childIndex = (index << 1) + 1;
      if (childIndex >= heap.length)
        break;
      let child = heap[childIndex];
      if (childIndex + 1 < heap.length && child.compare(heap[childIndex + 1]) >= 0) {
        child = heap[childIndex + 1];
        childIndex++;
      }
      if (cur.compare(child) < 0)
        break;
      heap[childIndex] = cur;
      heap[index] = child;
      index = childIndex;
    }
  }
  var SpanCursor = class {
    constructor(sets, skip, minPoint) {
      this.minPoint = minPoint;
      this.active = [];
      this.activeTo = [];
      this.activeRank = [];
      this.minActive = -1;
      this.point = null;
      this.pointFrom = 0;
      this.pointRank = 0;
      this.to = -1e9;
      this.endSide = 0;
      this.openStart = -1;
      this.cursor = HeapCursor.from(sets, skip, minPoint);
    }
    goto(pos, side = -1e9) {
      this.cursor.goto(pos, side);
      this.active.length = this.activeTo.length = this.activeRank.length = 0;
      this.minActive = -1;
      this.to = pos;
      this.endSide = side;
      this.openStart = -1;
      this.next();
      return this;
    }
    forward(pos, side) {
      while (this.minActive > -1 && (this.activeTo[this.minActive] - pos || this.active[this.minActive].endSide - side) < 0)
        this.removeActive(this.minActive);
      this.cursor.forward(pos, side);
    }
    removeActive(index) {
      remove(this.active, index);
      remove(this.activeTo, index);
      remove(this.activeRank, index);
      this.minActive = findMinIndex(this.active, this.activeTo);
    }
    addActive(trackOpen) {
      let i = 0, { value, to, rank } = this.cursor;
      while (i < this.activeRank.length && (rank - this.activeRank[i] || to - this.activeTo[i]) > 0)
        i++;
      insert(this.active, i, value);
      insert(this.activeTo, i, to);
      insert(this.activeRank, i, rank);
      if (trackOpen)
        insert(trackOpen, i, this.cursor.from);
      this.minActive = findMinIndex(this.active, this.activeTo);
    }
    // After calling this, if `this.point` != null, the next range is a
    // point. Otherwise, it's a regular range, covered by `this.active`.
    next() {
      let from = this.to, wasPoint = this.point;
      this.point = null;
      let trackOpen = this.openStart < 0 ? [] : null;
      for (; ; ) {
        let a = this.minActive;
        if (a > -1 && (this.activeTo[a] - this.cursor.from || this.active[a].endSide - this.cursor.startSide) < 0) {
          if (this.activeTo[a] > from) {
            this.to = this.activeTo[a];
            this.endSide = this.active[a].endSide;
            break;
          }
          this.removeActive(a);
          if (trackOpen)
            remove(trackOpen, a);
        } else if (!this.cursor.value) {
          this.to = this.endSide = 1e9;
          break;
        } else if (this.cursor.from > from) {
          this.to = this.cursor.from;
          this.endSide = this.cursor.startSide;
          break;
        } else {
          let nextVal = this.cursor.value;
          if (!nextVal.point) {
            this.addActive(trackOpen);
            this.cursor.next();
          } else if (wasPoint && this.cursor.to == this.to && this.cursor.from < this.cursor.to) {
            this.cursor.next();
          } else {
            this.point = nextVal;
            this.pointFrom = this.cursor.from;
            this.pointRank = this.cursor.rank;
            this.to = this.cursor.to;
            this.endSide = nextVal.endSide;
            this.cursor.next();
            this.forward(this.to, this.endSide);
            break;
          }
        }
      }
      if (trackOpen) {
        this.openStart = 0;
        for (let i = trackOpen.length - 1; i >= 0 && trackOpen[i] < from; i--)
          this.openStart++;
      }
    }
    activeForPoint(to) {
      if (!this.active.length)
        return this.active;
      let active = [];
      for (let i = this.active.length - 1; i >= 0; i--) {
        if (this.activeRank[i] < this.pointRank)
          break;
        if (this.activeTo[i] > to || this.activeTo[i] == to && this.active[i].endSide >= this.point.endSide)
          active.push(this.active[i]);
      }
      return active.reverse();
    }
    openEnd(to) {
      let open = 0;
      for (let i = this.activeTo.length - 1; i >= 0 && this.activeTo[i] > to; i--)
        open++;
      return open;
    }
  };
  function compare(a, startA, b, startB, length, comparator) {
    a.goto(startA);
    b.goto(startB);
    let endB = startB + length;
    let pos = startB, dPos = startB - startA;
    let bounds = !!comparator.boundChange;
    for (let boundChange = false; ; ) {
      let dEnd = a.to + dPos - b.to, diff = dEnd || a.endSide - b.endSide;
      let end = diff < 0 ? a.to + dPos : b.to, clipEnd = Math.min(end, endB);
      let point = a.point || b.point;
      if (point) {
        if (!(a.point && b.point && cmpVal(a.point, b.point) && sameValues(a.activeForPoint(a.to), b.activeForPoint(b.to))))
          comparator.comparePoint(pos, clipEnd, a.point, b.point);
        boundChange = false;
      } else {
        if (boundChange)
          comparator.boundChange(pos);
        if (clipEnd > pos && !sameValues(a.active, b.active))
          comparator.compareRange(pos, clipEnd, a.active, b.active);
        if (bounds && clipEnd < endB && (dEnd || a.openEnd(end) != b.openEnd(end)))
          boundChange = true;
      }
      if (end > endB)
        break;
      pos = end;
      if (diff <= 0)
        a.next();
      if (diff >= 0)
        b.next();
    }
  }
  function sameValues(a, b) {
    if (a.length != b.length)
      return false;
    for (let i = 0; i < a.length; i++)
      if (a[i] != b[i] && !cmpVal(a[i], b[i]))
        return false;
    return true;
  }
  function remove(array, index) {
    for (let i = index, e = array.length - 1; i < e; i++)
      array[i] = array[i + 1];
    array.pop();
  }
  function insert(array, index, value) {
    for (let i = array.length - 1; i >= index; i--)
      array[i + 1] = array[i];
    array[index] = value;
  }
  function findMinIndex(value, array) {
    let found = -1, foundPos = 1e9;
    for (let i = 0; i < array.length; i++)
      if ((array[i] - foundPos || value[i].endSide - value[found].endSide) < 0) {
        found = i;
        foundPos = array[i];
      }
    return found;
  }

  // node_modules/@codemirror/search/dist/index.js
  var basicNormalize = typeof String.prototype.normalize == "function" ? (x) => x.normalize("NFKD") : (x) => x;
  var SearchCursor = class {
    /**
    Create a text cursor. The query is the search string, `from` to
    `to` provides the region to search.
    
    When `normalize` is given, it will be called, on both the query
    string and the content it is matched against, before comparing.
    You can, for example, create a case-insensitive search by
    passing `s => s.toLowerCase()`.
    
    Text is always normalized with
    [`.normalize("NFKD")`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/normalize)
    (when supported).
    */
    constructor(text, query, from = 0, to = text.length, normalize, test) {
      this.test = test;
      this.value = { from: 0, to: 0, precise: false };
      this.done = false;
      this.matches = [];
      this.buffer = "";
      this.bufferPos = 0;
      this.iter = text.iterRange(from, to);
      this.bufferStart = from;
      this.normalize = normalize ? (x) => normalize(basicNormalize(x)) : basicNormalize;
      this.query = this.normalize(query);
    }
    peek() {
      if (this.bufferPos == this.buffer.length) {
        this.bufferStart += this.buffer.length;
        this.iter.next();
        if (this.iter.done)
          return -1;
        this.bufferPos = 0;
        this.buffer = this.iter.value;
      }
      return codePointAt2(this.buffer, this.bufferPos);
    }
    /**
    Look for the next match. Updates the iterator's
    [`value`](https://codemirror.net/6/docs/ref/#search.SearchCursor.value) and
    [`done`](https://codemirror.net/6/docs/ref/#search.SearchCursor.done) properties. Should be called
    at least once before using the cursor.
    */
    next() {
      while (this.matches.length)
        this.matches.pop();
      return this.nextOverlapping();
    }
    /**
    The `next` method will ignore matches that partially overlap a
    previous match. This method behaves like `next`, but includes
    such matches.
    */
    nextOverlapping() {
      for (; ; ) {
        let next = this.peek();
        if (next < 0) {
          this.done = true;
          return this;
        }
        let str = fromCodePoint(next), start = this.bufferStart + this.bufferPos;
        this.bufferPos += codePointSize2(next);
        let norm = this.normalize(str);
        if (norm.length)
          for (let i = 0, pos = start, posPrecise = true; ; i++) {
            let code = norm.charCodeAt(i);
            let match = this.match(code, pos, posPrecise, this.bufferPos + this.bufferStart, i == norm.length - 1);
            if (match) {
              this.value = match;
              return this;
            }
            if (i == norm.length - 1)
              break;
            if (posPrecise && i < str.length && str.charCodeAt(i) == code)
              pos++;
            else
              posPrecise = false;
          }
      }
    }
    match(code, pos, posPrecise, end, endPrecise) {
      let match = null;
      for (let i = 0; i < this.matches.length; ) {
        let partial = this.matches[i], keep = false;
        if (this.query.charCodeAt(partial.index) == code) {
          if (partial.index == this.query.length - 1) {
            match = { from: partial.from, to: end, precise: endPrecise && partial.precise };
          } else {
            partial.index++;
            keep = true;
          }
        }
        if (keep)
          i++;
        else
          this.matches.splice(i, 1);
      }
      if (this.query.charCodeAt(0) == code) {
        if (this.query.length == 1)
          match = { from: pos, to: end, precise: posPrecise && endPrecise };
        else
          this.matches.push({ from: pos, index: 1, precise: posPrecise });
      }
      if (match && this.test && !this.test(match.from, match.to, this.buffer, this.bufferStart))
        match = null;
      return match;
    }
  };
  if (typeof Symbol != "undefined")
    SearchCursor.prototype[Symbol.iterator] = function() {
      return this;
    };
  var empty = { from: -1, to: -1, match: /* @__PURE__ */ /.*/.exec(""), precise: true };
  var baseFlags = "gm" + (/x/.unicode == null ? "" : "u");
  var RegExpCursor = class {
    /**
    Create a cursor that will search the given range in the given
    document. `query` should be the raw pattern (as you'd pass it to
    `new RegExp`).
    */
    constructor(text, query, options, from = 0, to = text.length) {
      this.text = text;
      this.to = to;
      this.curLine = "";
      this.done = false;
      this.value = empty;
      if (/\\[sWDnr]|\n|\r|\[\^/.test(query))
        return new MultilineRegExpCursor(text, query, options, from, to);
      this.re = new RegExp(query, baseFlags + ((options === null || options === void 0 ? void 0 : options.ignoreCase) ? "i" : ""));
      this.test = options === null || options === void 0 ? void 0 : options.test;
      this.iter = text.iter();
      let startLine = text.lineAt(from);
      this.curLineStart = startLine.from;
      this.matchPos = toCharEnd(text, from);
      this.getLine(this.curLineStart);
    }
    getLine(skip) {
      this.iter.next(skip);
      if (this.iter.lineBreak) {
        this.curLine = "";
      } else {
        this.curLine = this.iter.value;
        if (this.curLineStart + this.curLine.length > this.to)
          this.curLine = this.curLine.slice(0, this.to - this.curLineStart);
        this.iter.next();
      }
    }
    nextLine() {
      this.curLineStart = this.curLineStart + this.curLine.length + 1;
      if (this.curLineStart > this.to)
        this.curLine = "";
      else
        this.getLine(0);
    }
    /**
    Move to the next match, if there is one.
    */
    next() {
      for (let off = this.matchPos - this.curLineStart; ; ) {
        this.re.lastIndex = off;
        let match = this.matchPos <= this.to && this.re.exec(this.curLine);
        if (match) {
          let from = this.curLineStart + match.index, to = from + match[0].length;
          this.matchPos = toCharEnd(this.text, to + (from == to ? 1 : 0));
          if (from == this.curLineStart + this.curLine.length)
            this.nextLine();
          if ((from < to || from > this.value.to) && (!this.test || this.test(from, to, match))) {
            this.value = { from, to, precise: true, match };
            return this;
          }
          off = this.matchPos - this.curLineStart;
        } else if (this.curLineStart + this.curLine.length < this.to) {
          this.nextLine();
          off = 0;
        } else {
          this.done = true;
          return this;
        }
      }
    }
  };
  var flattened = /* @__PURE__ */ new WeakMap();
  var FlattenedDoc = class _FlattenedDoc {
    constructor(from, text) {
      this.from = from;
      this.text = text;
    }
    get to() {
      return this.from + this.text.length;
    }
    static get(doc, from, to) {
      let cached = flattened.get(doc);
      if (!cached || cached.from >= to || cached.to <= from) {
        let flat = new _FlattenedDoc(from, doc.sliceString(from, to));
        flattened.set(doc, flat);
        return flat;
      }
      if (cached.from == from && cached.to == to)
        return cached;
      let { text, from: cachedFrom } = cached;
      if (cachedFrom > from) {
        text = doc.sliceString(from, cachedFrom) + text;
        cachedFrom = from;
      }
      if (cached.to < to)
        text += doc.sliceString(cached.to, to);
      flattened.set(doc, new _FlattenedDoc(cachedFrom, text));
      return new _FlattenedDoc(from, text.slice(from - cachedFrom, to - cachedFrom));
    }
  };
  var MultilineRegExpCursor = class {
    constructor(text, query, options, from, to) {
      this.text = text;
      this.to = to;
      this.done = false;
      this.value = empty;
      this.matchPos = toCharEnd(text, from);
      this.re = new RegExp(query, baseFlags + ((options === null || options === void 0 ? void 0 : options.ignoreCase) ? "i" : ""));
      this.test = options === null || options === void 0 ? void 0 : options.test;
      this.flat = FlattenedDoc.get(text, from, this.chunkEnd(
        from + 5e3
        /* Chunk.Base */
      ));
    }
    chunkEnd(pos) {
      return pos >= this.to ? this.to : this.text.lineAt(pos).to;
    }
    next() {
      for (; ; ) {
        let off = this.re.lastIndex = this.matchPos - this.flat.from;
        let match = this.re.exec(this.flat.text);
        if (match && !match[0] && match.index == off) {
          this.re.lastIndex = off + 1;
          match = this.re.exec(this.flat.text);
        }
        if (match) {
          let from = this.flat.from + match.index, to = from + match[0].length;
          if ((this.flat.to >= this.to || match.index + match[0].length <= this.flat.text.length - 10) && (!this.test || this.test(from, to, match))) {
            this.value = { from, to, precise: true, match };
            this.matchPos = toCharEnd(this.text, to + (from == to ? 1 : 0));
            return this;
          }
        }
        if (this.flat.to == this.to) {
          this.done = true;
          return this;
        }
        this.flat = FlattenedDoc.get(this.text, this.flat.from, this.chunkEnd(this.flat.from + this.flat.text.length * 2));
      }
    }
  };
  if (typeof Symbol != "undefined") {
    RegExpCursor.prototype[Symbol.iterator] = MultilineRegExpCursor.prototype[Symbol.iterator] = function() {
      return this;
    };
  }
  function toCharEnd(text, pos) {
    if (pos >= text.length)
      return pos;
    let line = text.lineAt(pos), next;
    while (pos < line.to && (next = line.text.charCodeAt(pos - line.from)) >= 56320 && next < 57344)
      pos++;
    return pos;
  }

  // document-find-matching.ts
  function documentFindWordBoundary(doc, from, to) {
    const before = (position) => /[\p{L}\p{N}\p{M}_]$/u.test(
      doc.sliceString(Math.max(0, position - 2), position)
    );
    const after = (position) => /^[\p{L}\p{N}\p{M}_]/u.test(
      doc.sliceString(position, Math.min(doc.length, position + 2))
    );
    return (!before(from) || !after(from)) && (!after(to) || !before(to));
  }
  function documentFindMatches(source, request) {
    if (!request.query) return [];
    const doc = Text2.of(source.split("\n"));
    const cursor = new SearchCursor(
      doc,
      request.query,
      0,
      doc.length,
      request.caseSensitive ? void 0 : (value) => value.toLowerCase(),
      request.wholeWord ? (from, to) => documentFindWordBoundary(doc, from, to) : void 0
    );
    const matches = [];
    for (let next = cursor.next(); !next.done; next = cursor.next()) {
      matches.push({ from: next.value.from, to: next.value.to });
    }
    return matches;
  }

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
          'script, style, [hidden], [aria-hidden="true"], #scholium-preview-popover'
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
  function searchableLines() {
    const root = document.querySelector("main");
    if (!root) return [];
    const lines = Array.from(root.querySelectorAll("[data-source-line]")).filter((element) => !element.querySelector("[data-source-line]"));
    return lines.length > 0 ? lines : [root];
  }
  function rangesFor(request) {
    if (!request.query) return [];
    const result = [];
    for (const line of searchableLines()) {
      const nodes = textNodesIn(line);
      const text = nodes.map((node) => node.data).join("");
      for (const match of documentFindMatches(text, {
        query: request.query,
        caseSensitive: request.caseSensitive,
        wholeWord: request.wholeWord
      })) {
        const range = rangeFor(nodes, match.from, match.to);
        if (range) result.push(range);
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
    const present = (scrollToMatch) => {
      clear();
      if (matches.length === 0 || current < 0) return;
      if (registry) {
        const ordinary = matches.filter((_, index) => index !== current);
        if (ordinary.length > 0) registry.set(allName, new Highlight(...ordinary));
        registry.set(currentName, new Highlight(matches[current]));
      }
      if (scrollToMatch) {
        const target = matches[current].startContainer.parentElement;
        for (let ancestor = target; ancestor; ancestor = ancestor.parentElement) {
          if (ancestor.tagName.toLowerCase() === "details") ancestor.setAttribute("open", "");
        }
        target?.scrollIntoView({ block: "center", behavior: "auto" });
      }
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
        present(request.action !== "present");
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

  // localization.ts
  var webInterfaceLocalizationKeys = [
    "Preview image {name}",
    "Tab",
    "AI",
    "Index",
    "Accept AI continuation: {text} (Tab)",
    "Accept index suggestion: {text} (Tab)",
    "AI continuation timed out.",
    "AI continuation is preparing.",
    "AI continuation is retrieving related context.",
    "AI continuation is composing.",
    "AI continuation is not enabled.",
    "AI continuation is not connected. Connect Codex in Agents & Chat.",
    "AI continuation is not ready. Check Writing Assistance settings.",
    "The selected AI continuation model is unavailable. Choose an available model in Writing Assistance.",
    "AI continuation is still stopping. Try again in a moment.",
    "AI continuation could not connect. Check Agents & Chat.",
    "AI continuation timed out. Library completion remains available.",
    "AI returned no usable continuation. Library completion remains available.",
    "AI continuation could not be used for this writing context.",
    "AI continuation was cancelled.",
    "AI continuation could not be generated. Library completion remains available.",
    "The edited Markdown document exceeds the supported editor size.",
    "Finish editing the note title before switching documents.",
    "The insertion position changed. Confirm the cursor again.",
    "The reference is too large.",
    "Insert Citation\u2026",
    "Citation Operation",
    "The citation operation could not finish. Your text was preserved.",
    "Footnote and endnote citation styles are unavailable. Your text was preserved.",
    "A citation operation is already active or this editor is unavailable.",
    "Citation completion is stale.",
    "Citation transaction is unavailable.",
    "Citation source changed before acceptance.",
    "Finish composition before adopting a suggestion.",
    "The passage changed. Request a new suggestion.",
    "The suggestion is too large.",
    "Copy",
    "Expand",
    "YAML frontmatter",
    "File and image paste is not supported in Editor 1.0.",
    "Markdown editor, Edit mode",
    "Markdown source editor",
    "Note title",
    "Empty Note",
    "This note has no body content.",
    "Heading level {level}",
    "Link",
    "Callout",
    "Quotation",
    "Table",
    "Bulleted list",
    "Numbered list",
    "Bold text",
    "Emphasized text",
    "Inline code",
    "Exact Markdown and YAML source",
    "Task item",
    "Completed task",
    "Incomplete task",
    "Show Link Annotation for {title}",
    "Hide Link Annotation for {title}",
    "Link Annotation",
    "Callout: {title}",
    "linked note",
    "Markdown table",
    "Embedded note {title}",
    "Open embedded note {title}",
    "Embedded note content for {title}",
    "Embedded note",
    "Mathematics could not be rendered. Source is shown.",
    "Diagram rendering is unavailable. Mermaid source is shown.",
    "This Mermaid diagram is unsupported or could not be rendered. Source is shown.",
    "This Mermaid diagram could not be isolated safely. Source is shown.",
    "Mermaid source: {source}",
    "Add accTitle and accDescr to provide a concise nonvisual account of this diagram.",
    "This Mermaid diagram could not be rendered. Source is shown.",
    "Footnote {ordinal}",
    "Footnotes",
    "Return to footnote reference {ordinal}",
    "Edit mode unavailable",
    "Close the YAML frontmatter in Source mode to restore the visual projection.",
    "The editor could not preserve the exact source line endings.",
    "The replacement would make the document too large.",
    "The Markdown editor could not start.",
    "The Review renderer stopped unexpectedly.",
    "No preview is available at the insertion point.",
    "Preview content",
    "Paragraph",
    "Bold",
    "Italic",
    "Strikethrough",
    "Highlight",
    "Annotated Wikilink",
    "Inline Code",
    "Code Block",
    "Blockquote",
    "Comment",
    "Date",
    "Inline Math",
    "Display Math",
    "Mermaid",
    "Footnote",
    "Divider",
    "Orientation",
    "Introduces the note's purpose, scope, and route.",
    "Source",
    "Records sources that anchor the note without implying that they support every claim.",
    "Connections",
    "Routes the reader to a curated set of neighboring knowledge objects.",
    "Statement",
    "Isolates a claim, definition, principle, formula, distinction, or compact argument without endorsing it.",
    "Illustration",
    "Presents a scenario, example, thought experiment, or test case used in reasoning.",
    "Preserves source-specific wording with attribution.",
    "Caution",
    "Marks a limitation, unresolved dependency, source restriction, or interpretive warning.",
    "Note",
    "Preserves an unsupported callout without assigning a research role.",
    "Selection actions",
    "Return saves \xB7 Shift-Return adds a line \xB7 Escape cancels",
    "Submit Comment for QA",
    "Comment for line {start}",
    "Comment for lines {start} through {end}",
    "Open comment at line {start}",
    "Open comment at lines {start} through {end}",
    "Open {count} comments at line {start}",
    "Open {count} comments at lines {start} through {end}",
    "Could not save. Your Comment is still here.",
    "This Comment is too long to save here.",
    "Saving\u2026",
    "{label}. {meaning}"
  ];
  var fallbackPayload = {
    languageTag: "en",
    strings: {}
  };
  var templatePlaceholder = /\{([A-Za-z][A-Za-z0-9_]*)\}/g;
  var interfaceLanguageIdentifier = /^[A-Za-z]{2,8}(?:[-_][A-Za-z0-9]{1,8})*$/;
  function placeholders(value) {
    return [...value.matchAll(templatePlaceholder)].map((match) => match[1]).sort().join("\0");
  }
  function supportedInterfaceLanguage(identifier) {
    if (identifier.length > 64 || !interfaceLanguageIdentifier.test(identifier)) return "en";
    const normalized = identifier.replaceAll("_", "-").toLowerCase();
    const parts = normalized.split("-");
    return parts[0] === "zh" && (parts.length === 1 || parts[1] === "hans" || parts[1] === "cn" || parts[1] === "sg") ? "zh-Hans" : "en";
  }
  function validatedInterfaceLocalization(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const candidate = value;
    if (typeof candidate.languageTag !== "string" || candidate.languageTag.length > 64 || !interfaceLanguageIdentifier.test(candidate.languageTag) || !candidate.strings || typeof candidate.strings !== "object" || Array.isArray(candidate.strings)) return null;
    const strings = {};
    const languageTag = supportedInterfaceLanguage(candidate.languageTag);
    if (languageTag === "en" && !/^en(?:[-_]|$)/i.test(candidate.languageTag)) {
      return { ...fallbackPayload };
    }
    const entries = candidate.strings;
    for (const key of webInterfaceLocalizationKeys) {
      if (!Object.hasOwn(entries, key)) continue;
      const translation = entries[key];
      if (typeof translation === "string" && translation.trim().length > 0 && translation.length <= 4096 && placeholders(translation) === placeholders(key)) {
        strings[key] = translation;
      }
    }
    return { languageTag, strings };
  }
  function interfaceLocalizationFromBase64(encoded) {
    if (!encoded || encoded.length > 2796204) return fallbackPayload;
    try {
      const bytes = Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0));
      if (bytes.byteLength > 2097152) return fallbackPayload;
      return validatedInterfaceLocalization(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes))) ?? fallbackPayload;
    } catch {
      return fallbackPayload;
    }
  }
  function payloadFromDocument() {
    if (typeof document === "undefined") return fallbackPayload;
    const encoded = document.querySelector(
      'meta[name="scholium-interface-localization"]'
    )?.content;
    return interfaceLocalizationFromBase64(encoded ?? "");
  }
  var activePayload = payloadFromDocument();
  function localizedTemplate(key, replacements) {
    return localizedTemplateFrom(activePayload, key, replacements);
  }
  function localizedFrom(payload, key) {
    return payload.strings[key] ?? key;
  }
  function localizedTemplateFrom(payload, key, replacements) {
    return localizedFrom(payload, key).replace(
      templatePlaceholder,
      (placeholder, name) => Object.hasOwn(replacements, name) ? String(replacements[name]) : placeholder
    );
  }
  function createInterfaceLocalizer(payload) {
    const localization = validatedInterfaceLocalization(payload) ?? fallbackPayload;
    return (key, replacements = {}) => localizedTemplateFrom(localization, key, replacements);
  }
  var calloutLocalizationKeys = {
    orient: ["Orientation", "Introduces the note's purpose, scope, and route."],
    cite: ["Source", "Records sources that anchor the note without implying that they support every claim."],
    connect: ["Connections", "Routes the reader to a curated set of neighboring knowledge objects."],
    state: ["Statement", "Isolates a claim, definition, principle, formula, distinction, or compact argument without endorsing it."],
    illustrate: ["Illustration", "Presents a scenario, example, thought experiment, or test case used in reasoning."],
    quote: ["Quotation", "Preserves source-specific wording with attribution."],
    flag: ["Caution", "Marks a limitation, unresolved dependency, source restriction, or interpretive warning."],
    neutral: ["Note", "Preserves an unsupported callout without assigning a research role."]
  };

  // reader-configuration.ts
  function validatedReaderConfiguration(value) {
    if (!value || typeof value !== "object") return null;
    const config = value;
    if (config.version !== 7 || typeof config.documentID !== "string" || !config.documentID || config.documentID.length > 4096 || typeof config.fingerprint !== "string" || !config.fingerprint || config.fingerprint.length > 256 || !Number.isSafeInteger(config.loadGeneration) || Number(config.loadGeneration) < 0 || typeof config.selectionEnabled !== "boolean" || typeof config.imagePreviewsEnabled !== "boolean" || config.replyProjection !== void 0 && typeof config.replyProjection !== "boolean" || typeof config.testingEnabled !== "boolean" || typeof config.presentationCSS !== "string" || typeof config.userCSS !== "string" || !config.localization || typeof config.localization !== "object" || !config.localization.strings || typeof config.localization.strings !== "object" || !Array.isArray(config.linkPreviews) || config.linkPreviews.length > 128) return null;
    const localization = validatedInterfaceLocalization(config.localization);
    if (!localization) return null;
    return { ...config, localization };
  }

  // heading-accessibility.ts
  function bodyHeadingAccessibilityLevel(markdownLevel) {
    return Math.min(6, Math.max(1, markdownLevel)) + 1;
  }

  // interaction-reporting.ts
  var AnimationFrameCoalescer = class {
    constructor(requestFrame, cancelFrame, requestWatchdog, cancelWatchdog, watchdogMilliseconds = 50) {
      this.requestFrame = requestFrame;
      this.cancelFrame = cancelFrame;
      this.requestWatchdog = requestWatchdog;
      this.cancelWatchdog = cancelWatchdog;
      this.watchdogMilliseconds = watchdogMilliseconds;
    }
    requestFrame;
    cancelFrame;
    requestWatchdog;
    cancelWatchdog;
    watchdogMilliseconds;
    frame = null;
    watchdog = null;
    latest = null;
    generation = 0;
    schedule(callback) {
      this.latest = callback;
      if (this.frame !== null) return;
      const generation = ++this.generation;
      this.frame = this.requestFrame(() => this.flush("frame", generation));
      this.watchdog = this.requestWatchdog(
        () => this.flush("watchdog", generation),
        this.watchdogMilliseconds
      );
    }
    cancel() {
      if (this.frame !== null) this.cancelFrame(this.frame);
      if (this.watchdog !== null) this.cancelWatchdog(this.watchdog);
      this.frame = null;
      this.watchdog = null;
      this.latest = null;
      this.generation += 1;
    }
    /** Native modal tracking must start with the finalized selection already
     * delivered; its nested event loop can defer later bridge messages. */
    flushNow() {
      const latest = this.latest;
      this.cancel();
      latest?.();
    }
    flush(source, generation) {
      if (generation !== this.generation) return;
      if (source === "watchdog" && this.frame !== null) this.cancelFrame(this.frame);
      if (source === "frame" && this.watchdog !== null) this.cancelWatchdog(this.watchdog);
      this.frame = null;
      this.watchdog = null;
      const latest = this.latest;
      this.latest = null;
      latest?.();
    }
  };

  // rendered-interface-localization.ts
  function localizeRenderedInterface(root, localize = (key, replacements = {}) => localizedTemplate(key, replacements)) {
    root.querySelectorAll(".scholium-callout").forEach((callout) => {
      const identifier = Object.keys(calloutLocalizationKeys).find((role2) => callout.classList.contains(`scholium-callout-${role2}`));
      if (!identifier) return;
      const [labelKey, meaningKey] = calloutLocalizationKeys[identifier];
      const label = localize(labelKey);
      const meaning = localize(meaningKey);
      const role = callout.querySelector(".scholium-callout-role");
      if (role?.closest(".scholium-callout") === callout) {
        if (role.textContent !== label) role.textContent = label;
        if (role.title !== meaning) role.title = meaning;
        role.setAttribute("aria-label", localize("{label}. {meaning}", { label, meaning }));
      }
      const generatedTitle = callout.querySelector(".scholium-callout-default-title");
      if (generatedTitle?.closest(".scholium-callout") === callout && generatedTitle.textContent !== label) {
        generatedTitle.textContent = label;
      }
    });
    root.querySelectorAll(".footnote-reference[data-footnote]").forEach((reference) => {
      const ordinal = reference.dataset.footnote;
      if (ordinal) reference.setAttribute("aria-label", localize("Footnote {ordinal}", { ordinal }));
    });
    root.querySelectorAll(".footnote-return[data-footnote]").forEach((reference) => {
      const ordinal = reference.dataset.footnote;
      if (ordinal) reference.setAttribute("aria-label", localize("Return to footnote reference {ordinal}", { ordinal }));
    });
    root.querySelectorAll(".footnotes").forEach((section) => {
      section.setAttribute("aria-label", localize("Footnotes"));
    });
    root.querySelectorAll(".scholium-task-checkbox").forEach((checkbox) => {
      checkbox.setAttribute("aria-label", localize(checkbox.checked ? "Completed task" : "Incomplete task"));
    });
    root.querySelectorAll(".scholium-table").forEach((table) => {
      table.setAttribute("aria-label", localize("Markdown table"));
    });
    root.querySelectorAll("button[data-link-annotation]").forEach((button) => {
      const title = button.dataset.linkAnnotationTarget?.trim() || button.closest(".scholium-annotated-link")?.querySelector(".wiki-link")?.textContent?.trim() || localize("linked note");
      button.dataset.linkAnnotationTarget = title;
      const expanded = button.getAttribute("aria-expanded") === "true";
      button.setAttribute("aria-label", localize(
        expanded ? "Hide Link Annotation for {title}" : "Show Link Annotation for {title}",
        { title }
      ));
    });
  }

  // review-image-activation.ts
  var imageSelector = "img.scholium-embedded-image[data-scholium-image-target]";
  function installReviewImageActivation(root, actions) {
    let spaceTarget = null;
    let pointer = null;
    const targetFor = (image) => {
      if (!root.contains(image) || !image.matches(imageSelector) || !image.complete || image.naturalWidth <= 0 || image.naturalHeight <= 0) return null;
      const target = image.dataset.scholiumImageTarget;
      return target && new TextEncoder().encode(target).length <= 8192 ? target : null;
    };
    const imageFor = (target) => {
      if (!(target instanceof Element)) return null;
      if (target.matches(imageSelector)) return target;
      const link = target.closest("a");
      const images = link?.querySelectorAll(imageSelector);
      return images?.length === 1 ? images[0] : null;
    };
    const refreshImage = (image) => {
      const target = targetFor(image);
      const block = image.dataset.scholiumImageLayout === "block";
      image.classList.toggle("scholium-embedded-image-block", block);
      if (target) image.style.setProperty("--scholium-image-aspect-ratio", String(image.naturalWidth / image.naturalHeight));
      else image.style.removeProperty("--scholium-image-aspect-ratio");
      const directPreview = Boolean(actions && target && !image.closest("a"));
      image.classList.toggle("scholium-image-preview", directPreview);
      if (directPreview) {
        let filename = target.slice(target.lastIndexOf("/") + 1);
        try {
          filename = decodeURIComponent(filename);
        } catch {
        }
        const alt = image.alt.trim();
        const name = alt && alt !== filename ? `${alt} (${filename})` : filename;
        image.setAttribute("role", "button");
        image.setAttribute("tabindex", "0");
        image.setAttribute("aria-label", actions.label(name));
      } else {
        image.removeAttribute("role");
        image.removeAttribute("tabindex");
        image.removeAttribute("aria-label");
        if (spaceTarget?.image === image) spaceTarget = null;
        if (pointer?.image === image) pointer = null;
      }
    };
    const refresh = () => root.querySelectorAll(imageSelector).forEach(refreshImage);
    const loadChanged = (event) => {
      const image = imageFor(event.target);
      if (image) refreshImage(image);
    };
    const unmodified = (event) => !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey;
    const mouseDown = (event) => {
      pointer = null;
      const image = imageFor(event.target);
      const target = image && targetFor(image);
      const contextClick = event.button === 2 || event.button === 0 && event.ctrlKey && !event.metaKey && !event.altKey && !event.shiftKey;
      if (actions && image && target && (contextClick || event.button === 0 && unmodified(event) && !image.closest("a"))) {
        event.preventDefault();
        if (!contextClick) pointer = { image, target, x: event.clientX, y: event.clientY, released: false };
      }
    };
    const pointerMatches = (event) => pointer && event.target === pointer.image && targetFor(pointer.image) === pointer.target && Math.hypot(event.clientX - pointer.x, event.clientY - pointer.y) <= 4;
    const mouseMove = (event) => {
      if (pointer && !pointerMatches(event)) pointer = null;
    };
    const mouseUp = (event) => {
      if (event.button === 0 && pointerMatches(event)) pointer.released = true;
      else pointer = null;
    };
    const cancelPointer = () => {
      pointer = null;
    };
    const mouseOut = (event) => {
      if (pointer && event.target === pointer.image) pointer = null;
    };
    const click = (event) => {
      const started = pointer;
      const completed = pointerMatches(event);
      pointer = null;
      const image = imageFor(event.target);
      const target = image && targetFor(image);
      if (!actions || !image || !target || image.closest("a") || event.button !== 0 || !unmodified(event)) return;
      if (event.detail !== 0 && (!completed || !started?.released)) return;
      event.preventDefault();
      event.stopPropagation();
      actions.preview(target);
    };
    const openContextMenu = (image, target, clientX = 0, clientY = 0) => {
      if (clientX === 0 && clientY === 0) {
        const bounds = image.getBoundingClientRect();
        clientX = bounds.left + bounds.width / 2;
        clientY = bounds.top + bounds.height / 2;
      }
      actions?.contextMenu(target, clientX, clientY);
    };
    const keyDown = (event) => {
      pointer = null;
      const image = imageFor(event.target);
      const target = image && targetFor(image);
      if (!actions || !image || !target || event.isComposing || event.keyCode === 229) return;
      if (!event.metaKey && !event.ctrlKey && !event.altKey && (event.key === "ContextMenu" || event.key === "F10" && event.shiftKey)) {
        event.preventDefault();
        event.stopPropagation();
        if (!event.repeat) openContextMenu(image, target);
        return;
      }
      if (image.closest("a") || !unmodified(event)) return;
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      event.stopPropagation();
      if (event.repeat) return;
      if (event.key === "Enter") actions.preview(target);
      else spaceTarget = { image, target };
    };
    const keyUp = (event) => {
      if (event.key !== " ") return;
      const started = spaceTarget;
      spaceTarget = null;
      if (!actions || !started || event.target !== started.image || event.isComposing || !unmodified(event)) return;
      event.preventDefault();
      event.stopPropagation();
      const target = targetFor(started.image);
      if (target === started.target) actions.preview(target);
    };
    const focusOut = () => {
      spaceTarget = null;
      pointer = null;
    };
    const contextMenu = (event) => {
      const image = imageFor(event.target);
      const target = image && targetFor(image);
      if (!actions || !image || !target) return;
      event.preventDefault();
      event.stopPropagation();
      openContextMenu(image, target, event.clientX, event.clientY);
    };
    refresh();
    root.addEventListener("load", loadChanged, true);
    root.addEventListener("error", loadChanged, true);
    root.addEventListener("mousedown", mouseDown);
    root.addEventListener("mousemove", mouseMove);
    root.addEventListener("mouseup", mouseUp);
    root.addEventListener("mouseout", mouseOut);
    root.addEventListener("dragstart", cancelPointer);
    root.addEventListener("pointercancel", cancelPointer);
    root.addEventListener("click", click);
    root.addEventListener("keydown", keyDown);
    root.addEventListener("keyup", keyUp);
    root.addEventListener("focusout", focusOut);
    root.addEventListener("contextmenu", contextMenu);
    return {
      refresh,
      destroy() {
        spaceTarget = null;
        pointer = null;
        root.removeEventListener("load", loadChanged, true);
        root.removeEventListener("error", loadChanged, true);
        root.removeEventListener("mousedown", mouseDown);
        root.removeEventListener("mousemove", mouseMove);
        root.removeEventListener("mouseup", mouseUp);
        root.removeEventListener("mouseout", mouseOut);
        root.removeEventListener("dragstart", cancelPointer);
        root.removeEventListener("pointercancel", cancelPointer);
        root.removeEventListener("click", click);
        root.removeEventListener("keydown", keyDown);
        root.removeEventListener("keyup", keyUp);
        root.removeEventListener("focusout", focusOut);
        root.removeEventListener("contextmenu", contextMenu);
      }
    };
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
      loadGeneration,
      selectionEnabled,
      presentationCSS,
      userCSS,
      localization,
      linkPreviews,
      testingEnabled
    } = config;
    let fingerprint = config.fingerprint;
    const presentationStyle = requiredElement("scholium-presentation-css");
    const userStyle = requiredElement("scholium-user-css");
    presentationStyle.textContent = presentationCSS;
    userStyle.textContent = userCSS;
    const documentRoot = requiredElement("scholium-document");
    let presentationUpdateSequence = 0;
    const replyProjection = config.replyProjection ? createReplyProjection(documentRoot) : null;
    decorateAttachmentLinks(documentRoot);
    if (config.replyProjection) decorateChatReplyLinks(documentRoot);
    readerWindow.scholiumReadNavigation?.destroy();
    readerWindow.scholiumReadNavigation = createReaderArrival(documentRoot);
    window.addEventListener("pagehide", () => readerWindow.scholiumReadNavigation?.destroy(), { once: true });
    documentRoot.querySelectorAll("h1, h2, h3, h4, h5, h6").forEach((heading) => {
      const level = Number(heading.tagName.slice(1));
      heading.setAttribute("role", "heading");
      heading.setAttribute("aria-level", String(bodyHeadingAccessibilityLevel(level)));
    });
    const localized = createInterfaceLocalizer(localization);
    localizeRenderedInterface(documentRoot, localized);
    const handler = readerWindow.webkit?.messageHandlers?.scholiumRead;
    const post = (type, extra = {}) => handler?.postMessage({
      version,
      documentID,
      fingerprint,
      loadGeneration,
      type,
      ...extra
    });
    readerWindow.scholiumReviewImages?.destroy();
    readerWindow.scholiumReviewImages = installReviewImageActivation(documentRoot, config.imagePreviewsEnabled ? {
      label: (name) => localized("Preview image {name}", { name }),
      preview: (target) => post("imagePreview", { target }),
      contextMenu: (target, clientX, clientY) => post("imageContextMenu", {
        target,
        clientX,
        clientY,
        payloadFingerprint: fingerprint
      })
    } : null);
    window.addEventListener("pagehide", () => readerWindow.scholiumReviewImages?.destroy(), { once: true });
    const popover = requiredElement("scholium-preview-popover");
    popover.remove();
    const nativeFloating = createNativeFloatingPorts((event) => post("floatingSurface", { event }));
    let nativePreviewID = 0;
    let nativePreviewHovered = false;
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
      document.querySelectorAll(".scholium-math[data-math-source][data-math-kind]:not(.scholium-math-rendered):not(.scholium-math-error)").forEach((element) => {
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
        for (const name of ["data-source-utf16-start", "data-source-utf16-end", "data-source-start-line", "data-source-end-line", "data-scholium-object"]) {
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
    readerWindow.scholiumSetPresentationCSS = async (nextPresentationCSS, nextUserCSS) => {
      if (typeof nextPresentationCSS !== "string" || typeof nextUserCSS !== "string" || nextPresentationCSS.length > 8e6 || nextUserCSS.length > 8e6) {
        return false;
      }
      const sequence = ++presentationUpdateSequence;
      const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
      const fallbackTop = window.scrollY;
      const fraction = extent > 0 ? Math.max(0, Math.min(1, fallbackTop / extent)) : 0;
      const anchor = currentReadScrollAnchor(fraction);
      if (presentationStyle.textContent !== nextPresentationCSS) {
        presentationStyle.textContent = nextPresentationCSS;
      }
      if (userStyle.textContent !== nextUserCSS) {
        userStyle.textContent = nextUserCSS;
      }
      scheduleMermaidRefresh();
      await new Promise((resolve) => window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => resolve());
      }));
      if (sequence !== presentationUpdateSequence) return false;
      if (anchor) {
        restoreReadScrollAnchor(anchor);
      } else {
        window.scrollTo({ top: Math.max(0, fallbackTop), behavior: "auto" });
      }
      return true;
    };
    readerWindow.scholiumMermaidReady = renderMermaidNodes();
    await readerWindow.scholiumMermaidReady;
    if (config.replyProjection === true) {
      const disposeReply = installChatReply(documentRoot, post);
      replyProjection.commit();
      readerWindow.scholiumUpdateReply = async (value2) => {
        if (!value2 || typeof value2 !== "object") return false;
        const update = value2;
        if (update.version !== version || update.documentID !== documentID || update.loadGeneration !== loadGeneration || update.previousFingerprint !== fingerprint || typeof update.fingerprint !== "string" || !update.fingerprint || update.fingerprint.length > 256 || typeof update.html !== "string" || update.html.length > 16777216 || typeof update.presentationCSS !== "string" || typeof update.userCSS !== "string") return false;
        const restoreSelection = replyProjection.apply(update.html);
        localizeRenderedInterface(documentRoot, localized);
        decorateAttachmentLinks(documentRoot);
        decorateChatReplyLinks(documentRoot);
        readerWindow.scholiumReviewImages?.refresh();
        fingerprint = update.fingerprint;
        presentationStyle.textContent = update.presentationCSS;
        userStyle.textContent = update.userCSS;
        renderMathNodes();
        readerWindow.scholiumMermaidReady = renderMermaidNodes();
        await readerWindow.scholiumMermaidReady;
        documentRoot.querySelectorAll("h1, h2, h3, h4, h5, h6").forEach((heading) => {
          heading.setAttribute("role", "heading");
          heading.setAttribute("aria-level", String(bodyHeadingAccessibilityLevel(Number(heading.tagName.slice(1)))));
        });
        disposeReply.refresh();
        replyProjection.commit();
        restoreSelection();
        return true;
      };
      window.addEventListener("pagehide", disposeReply, { once: true });
    }
    for (const mediaQuery of [
      matchMedia("(prefers-color-scheme: dark)"),
      matchMedia("(prefers-contrast: more)")
    ]) {
      mediaQuery.addEventListener("change", scheduleMermaidRefresh);
    }
    document.querySelectorAll("button[data-link-annotation]").forEach((button) => {
      const linkName = button.dataset.linkAnnotationTarget?.trim() || button.closest(".scholium-annotated-link")?.querySelector(".wiki-link")?.textContent?.trim() || localized("linked note");
      button.dataset.linkAnnotationTarget = linkName;
      button.setAttribute(
        "aria-label",
        localized("Show Link Annotation for {title}", { title: linkName })
      );
    });
    let popoverHideTimer;
    let activeAnnotationButton = null;
    let activeFootnoteButton = null;
    let pinnedAnnotationButton = null;
    function annotationTarget(button) {
      return button.dataset.linkAnnotationTarget?.trim() || localized("linked note");
    }
    function setAnnotationExpanded(button, expanded) {
      button.setAttribute("aria-expanded", expanded ? "true" : "false");
      button.setAttribute(
        "aria-label",
        localized(
          expanded ? "Hide Link Annotation for {title}" : "Show Link Annotation for {title}",
          { title: annotationTarget(button) }
        )
      );
    }
    function setFootnoteExpanded(button, expanded) {
      button.setAttribute("aria-expanded", expanded ? "true" : "false");
    }
    function hidePopover() {
      nativePreviewHovered = false;
      nativeFloating.preview.hide(nativePreviewID);
      clearTimeout(popoverHideTimer);
      popoverHideTimer = void 0;
      if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
      if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
      activeAnnotationButton = null;
      activeFootnoteButton = null;
      pinnedAnnotationButton = null;
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
      if (nativePreviewHovered) return;
      if (pinnedAnnotationButton) return;
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
      localizeRenderedInterface(container, localized);
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
      const documentRoot2 = document.getElementById("scholium-document");
      if (!documentRoot2) return;
      for (const shell of documentRoot2.querySelectorAll(
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
      const anchors = [...documentRoot2.querySelectorAll("a.scholium-embed")].filter((anchor) => !anchor.parentElement?.closest(".scholium-embedded-note"));
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
      nativePreviewID = nativeFloating.preview.show(previewSurface(anchor.getBoundingClientRect(), popover), {
        dismiss: hidePopover,
        enter: () => {
          nativePreviewHovered = true;
          cancelPopoverHide();
        },
        leave: () => {
          nativePreviewHovered = false;
          schedulePopoverHide();
        }
      });
    }
    function showFootnotePopover(button) {
      const ordinal = button.dataset.footnote;
      if (!ordinal) return;
      const definition = document.getElementById("fn-" + ordinal);
      const content = definition && definition.querySelector(".footnote-content");
      if (!content) return;
      if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
      if (activeFootnoteButton && activeFootnoteButton !== button) {
        setFootnoteExpanded(activeFootnoteButton, false);
      }
      activeAnnotationButton = null;
      activeFootnoteButton = button;
      setFootnoteExpanded(activeFootnoteButton, true);
      previewTitle.textContent = localized("Footnote {ordinal}", { ordinal });
      previewMetadata.textContent = "";
      previewMetadata.hidden = true;
      previewBody.replaceChildren(content.cloneNode(true));
      sanitizeInertContent(previewBody);
      positionPopover(button);
    }
    function showLinkPopover(link) {
      const key = link.dataset.sourceUtf16Start + ":" + link.dataset.sourceUtf16End;
      const preview = previewByRange.get(key);
      if (!preview) return;
      if (activeAnnotationButton) setAnnotationExpanded(activeAnnotationButton, false);
      if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
      activeAnnotationButton = null;
      activeFootnoteButton = null;
      previewTitle.textContent = preview.title;
      previewMetadata.textContent = preview.fragment || "";
      previewMetadata.hidden = !preview.fragment;
      installInertDocumentContent(previewBody, preview);
      positionPopover(link);
    }
    function showLinkAnnotationPopover(button) {
      const identifier = button.dataset.linkAnnotation;
      const marker = button.closest(".scholium-link-annotation-marker");
      const template = identifier ? document.getElementById(`${identifier}-template`) : marker?.querySelector(":scope > template") ?? null;
      if (!template) return;
      if (activeAnnotationButton && activeAnnotationButton !== button) {
        setAnnotationExpanded(activeAnnotationButton, false);
      }
      if (activeFootnoteButton) setFootnoteExpanded(activeFootnoteButton, false);
      activeAnnotationButton = button;
      activeFootnoteButton = null;
      setAnnotationExpanded(button, true);
      previewTitle.textContent = annotationTarget(button);
      previewMetadata.textContent = localized("Link Annotation");
      previewMetadata.hidden = false;
      previewBody.replaceChildren(template.content.cloneNode(true));
      sanitizeInertContent(previewBody);
      positionPopover(button);
    }
    function previewAnchorFor(target) {
      if (!(target instanceof Element)) return null;
      if (target.closest(".scholium-embedded-note")) return null;
      return target.closest(
        ".scholium-link-annotation-button, .footnote-reference, a.wiki-link"
      );
    }
    function showPreviewFor(anchor) {
      if (anchor.matches(".scholium-link-annotation-button")) {
        showLinkAnnotationPopover(anchor);
      } else if (anchor.matches(".footnote-reference")) {
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
      if (pinnedAnnotationButton && anchor !== pinnedAnnotationButton) return;
      cancelPopoverHide();
      showPreviewFor(anchor);
    });
    document.addEventListener("focusin", (event) => {
      const anchor = previewAnchorFor(event.target);
      if (!anchor || remainsInsidePreviewAnchor(anchor, event.relatedTarget)) return;
      if (pinnedAnnotationButton && anchor !== pinnedAnnotationButton) return;
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
    renderEmbeddedNotes();
    document.addEventListener("click", (event) => {
      const eventElement = event.target instanceof Element ? event.target : null;
      const annotationButton = eventElement?.closest(
        ".scholium-link-annotation-button"
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
      if (pinnedAnnotationButton && !(event.target instanceof Node && popover.contains(event.target))) hidePopover();
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
        hidePopover();
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
      const selectionActions = createSelectionActions(nativeFloating.selection, () => {
        const selection = window.getSelection();
        if (!reviewSelectionSurfaceActive || reviewPointerSelectionActive || !selection || selection.rangeCount !== 1 || selection.isCollapsed || !reviewDocument) return null;
        const range = selection.getRangeAt(0);
        if (!reviewDocument.contains(range.startContainer) || !reviewDocument.contains(range.endContainer) || rangeIntersectsMermaid(range)) return null;
        const text = boundedReviewRangeText(range, reviewDocument, 2e3);
        if (!text) return null;
        const before = reviewContextBefore(range, reviewDocument, 80);
        const rect = range.getBoundingClientRect();
        if (rect.bottom < 0 || rect.top > window.innerHeight) return null;
        return {
          key: `${fingerprint}:${text}:${before}:${rect.top}:${rect.bottom}`,
          anchor: { left: rect.left + rect.width / 2, top: rect.top, bottom: rect.bottom }
        };
      });
      window.addEventListener("scroll", () => selectionActions.dismiss(), { passive: true });
      document.addEventListener("keydown", (event) => {
        const dismissed = selectionActions.dismiss();
        if (event.key === "Escape" && !event.isComposing && dismissed) {
          event.preventDefault();
          event.stopPropagation();
        }
      }, true);
      let passageSelection = null;
      const clearReviewSelection = () => {
        passageSelection = null;
        selectionActions.update();
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
        const common = range.commonAncestorContainer;
        const block = (common instanceof Element ? common : common.parentElement)?.closest("[data-source-utf16-start][data-source-utf16-end]");
        const beforeRange = document.createRange();
        let sourceMapping = {};
        if (block && block.textContent && block.textContent.length <= 64e3) {
          beforeRange.selectNodeContents(block);
          beforeRange.setEnd(range.startContainer, range.startOffset);
          const selectionLower = beforeRange.toString().length;
          sourceMapping = {
            blockLower: Number(block.dataset.sourceUtf16Start),
            blockUpper: Number(block.dataset.sourceUtf16End),
            blockText: block.textContent,
            selectionLower,
            selectionUpper: selectionLower + range.toString().length
          };
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
        post("selectionChanged", payload);
        selectionActions.update();
      };
      reviewDocument?.addEventListener("contextmenu", (event) => {
        if (!reviewSelectionSurfaceActive) return;
        const target = event.target instanceof Element ? event.target : null;
        if (!target || target.closest("a, img, table, pre, .scholium-embedded-note, [data-scholium-protected]")) return;
        const paragraph = target.closest("p[data-source-utf16-start][data-source-utf16-end]");
        if (!paragraph) return;
        const selection = window.getSelection();
        const range = selection?.rangeCount === 1 && !selection.isCollapsed ? selection.getRangeAt(0) : null;
        const inSelection = range && (event.button === 0 && event.detail === 0 || [...range.getClientRects()].some((rect) => event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom));
        if (!inSelection) {
          const selectedParagraph = document.createRange();
          selectedParagraph.selectNodeContents(paragraph);
          selection?.removeAllRanges();
          selection?.addRange(selectedParagraph);
        }
        updateReviewSelection();
        event.preventDefault();
        selectionActions.dismiss();
        post("passageContextMenu", {
          clientX: event.clientX,
          clientY: event.clientY,
          selection: inSelection ? passageSelection : null,
          paragraphLower: Number(paragraph.dataset.sourceUtf16Start),
          paragraphUpper: Number(paragraph.dataset.sourceUtf16End)
        });
      });
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
    let lastScrollEntry = null;
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
      if (lastScrollEntry) {
        const cachedRect = lastScrollEntry.element.getBoundingClientRect();
        if (cachedRect.height > 0 && probe >= cachedRect.top && probe < cachedRect.bottom) {
          return lastScrollEntry;
        }
      }
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
      if (entry) {
        lastScrollEntry = entry;
        return entry;
      }
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
        const distance = rect.top <= probe && rect.bottom > probe ? 0 : Math.min(Math.abs(rect.top - probe), Math.abs(rect.bottom - probe));
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = candidate;
        }
      }
      lastScrollEntry = nearest;
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
      lastPostedScroll = null;
      const fallback = Number(anchor.fallbackFraction);
      if (Number.isFinite(fallback) && fallback <= 0) {
        window.scrollTo({ top: 0, behavior: "auto" });
        return true;
      }
      const target = visibleScrollEntry(scrollEntryForAnchor(anchor));
      if (!target) return false;
      lastScrollEntry = target;
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
    const scrollReports = new AnimationFrameCoalescer(
      (callback) => window.requestAnimationFrame(callback),
      (identifier) => window.cancelAnimationFrame(identifier),
      (callback, delay) => window.setTimeout(callback, delay),
      (identifier) => window.clearTimeout(identifier)
    );
    let lastPostedScroll = null;
    const sameAnchor = (left, right) => left === right || Boolean(left && right && left.sourceUTF16Offset === right.sourceUTF16Offset && left.blockUTF16LowerBound === right.blockUTF16LowerBound && left.blockUTF16UpperBound === right.blockUTF16UpperBound && left.relativeBlockPosition === right.relativeBlockPosition && left.fallbackFraction === right.fallbackFraction);
    const postCurrentScroll = () => {
      const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
      const fraction = extent > 0 ? Math.max(0, Math.min(1, window.scrollY / extent)) : 0;
      const anchor = currentReadScrollAnchor(fraction);
      if (lastPostedScroll && lastPostedScroll.fraction === fraction && sameAnchor(lastPostedScroll.anchor, anchor)) return;
      lastPostedScroll = { fraction, anchor };
      post("scrollChanged", { fraction, anchor });
    };
    window.addEventListener("scroll", () => {
      scrollReports.schedule(postCurrentScroll);
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
