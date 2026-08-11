import type {EditorSelection, Extension, Text} from "@codemirror/state";
import {EditorView, ViewPlugin, type ViewUpdate} from "@codemirror/view";
import {floatingSurfacePosition} from "./floating-surface-geometry";
import type {MarkdownEditorCommand} from "./protocol";
import {systemSymbolElement, type WebSystemSymbolKey} from "./system-symbols";
import {localized, localizedTemplate} from "./localization";

export const selectionActionCommands = [
  "paragraph", "heading1", "heading2", "heading3", "heading4", "heading5", "heading6",
  "bold", "emphasis", "strikethrough", "highlight", "standardLink", "wikilink",
  "vectorSupports", "vectorOpposes", "vectorIncompatible", "inlineCode", "fencedCode",
  "bulletList", "numberedList", "taskList", "blockQuotation", "markdownComment",
] as const satisfies readonly MarkdownEditorCommand[];

export type SelectionActionCommand = typeof selectionActionCommands[number];

export interface SelectionActionsController {
  readonly extension: Extension;
  hide(): void;
  reposition(view: EditorView): void;
  update(view: EditorView): void;
}

interface MenuController {
  readonly element: HTMLDivElement;
  readonly trigger: HTMLButtonElement;
  readonly parent?: MenuController;
}

function selectionSymbol(key: WebSystemSymbolKey, className = "") {
  return systemSymbolElement(
    key,
    `scholium-selection-symbol ${className}`.trim(),
  );
}

function chevronIcon(className = "") {
  return selectionSymbol("chevron-down", className);
}

function directMenuButtons(menu: HTMLDivElement) {
  return Array.from(menu.children).filter(
    (child): child is HTMLButtonElement => child instanceof HTMLButtonElement,
  );
}

/**
 * Owns the transient formatting toolbar, its menus, and their DOM lifetime.
 * Markdown mutation remains with the editor composition root through
 * `applyCommand`; the toolbar never mirrors source, selection, or Undo state.
 */
export function createSelectionActionsController(options: {
  applyCommand(view: EditorView, command: SelectionActionCommand): void;
  selectionForPresentation?(view: EditorView): EditorSelection;
  presentationInteractionChanged?(update: ViewUpdate): boolean;
  pointerSelectionIsComplete?(view: EditorView): boolean;
  selectionIsAvailable?(view: EditorView): boolean;
}): SelectionActionsController {
  let root: HTMLDivElement | null = null;
  let activeView: EditorView | null = null;
  let focusExitTimer: number | null = null;
  let presentedDocument: Text | null = null;
  let presentedSelection: EditorSelection | null = null;
  let activeTextStyle: SelectionActionCommand | null = null;
  const positionMeasureKey = {};
  let positionGeneration = 0;
  let positionWatchdog: number | null = null;
  const menus: MenuController[] = [];
  const styleChecks = new Map<SelectionActionCommand, HTMLSpanElement>();
  const menuByTrigger = new Map<HTMLButtonElement, MenuController>();

  function clearFocusExitTimer() {
    if (focusExitTimer === null) return;
    window.clearTimeout(focusExitTimer);
    focusExitTimer = null;
  }

  function supersedePositionRequest() {
    positionGeneration += 1;
    if (positionWatchdog !== null) {
      window.clearTimeout(positionWatchdog);
      positionWatchdog = null;
    }
    return positionGeneration;
  }

  function hideMenu(menu: MenuController) {
    if (!menu.element.hidden) menu.element.hidden = true;
    if (menu.trigger.getAttribute("aria-expanded") !== "false") {
      menu.trigger.setAttribute("aria-expanded", "false");
    }
    for (const child of menus) {
      if (child.parent === menu) hideMenu(child);
    }
  }

  function closeMenus() {
    for (const menu of menus) {
      if (!menu.parent) hideMenu(menu);
    }
  }

  function synchronizeKeyboardFocusFeedback(target: EventTarget | null) {
    if (!root) return;
    for (const element of root.querySelectorAll(".scholium-selection-keyboard-focus")) {
      element.classList.remove("scholium-selection-keyboard-focus");
    }
    if (target instanceof HTMLButtonElement && root.contains(target)) {
      target.classList.add("scholium-selection-keyboard-focus");
    }
  }

  function visibleToolbarControls() {
    if (!root) return [];
    return Array.from(root.querySelectorAll<HTMLButtonElement>(
      ".scholium-selection-toolbar .scholium-selection-control",
    )).filter((button) => button.getClientRects().length > 0);
  }

  function visibleMenuButtons(menu: HTMLDivElement) {
    return directMenuButtons(menu).filter((button) => button.getClientRects().length > 0);
  }

  function topMenu(menu: MenuController) {
    let current = menu;
    while (current.parent) current = current.parent;
    return current;
  }

  function positionMenu(menu: MenuController) {
    if (menu.element.hidden) return;
    menu.element.style.visibility = "hidden";
    const triggerBounds = menu.trigger.getBoundingClientRect();
    const menuBounds = menu.element.getBoundingClientRect();
    const viewportInset = 8;
    let left = menu.parent ? triggerBounds.right + 4 : triggerBounds.left;
    let top = menu.parent ? triggerBounds.top - 4 : triggerBounds.bottom + 5;

    if (left + menuBounds.width > window.innerWidth - viewportInset) {
      left = menu.parent
        ? triggerBounds.left - menuBounds.width - 4
        : window.innerWidth - menuBounds.width - viewportInset;
    }
    if (top + menuBounds.height > window.innerHeight - viewportInset) {
      top = menu.parent
        ? window.innerHeight - menuBounds.height - viewportInset
        : triggerBounds.top - menuBounds.height - 5;
    }
    menu.element.style.left = `${Math.max(viewportInset, left)}px`;
    menu.element.style.top = `${Math.max(viewportInset, top)}px`;
    menu.element.style.visibility = "";
  }

  function positionOpenMenus() {
    for (const menu of menus) positionMenu(menu);
  }

  function openMenu(menu: MenuController, focusFirstItem: boolean) {
    if (!menu.parent) {
      closeMenus();
    } else {
      for (const sibling of menus) {
        if (sibling.parent === menu.parent && sibling !== menu) hideMenu(sibling);
      }
    }
    menu.element.hidden = false;
    menu.trigger.setAttribute("aria-expanded", "true");
    positionMenu(menu);
    if (focusFirstItem) {
      window.queueMicrotask(() => visibleMenuButtons(menu.element)[0]?.focus());
    }
  }

  function apply(command: SelectionActionCommand) {
    closeMenus();
    const view = activeView;
    if (view) options.applyCommand(view, command);
  }

  function createToolbarButton(
    label: string,
    title: string | null,
    className = "",
  ) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `scholium-selection-control ${className}`.trim();
    button.setAttribute("aria-label", label);
    if (title) button.title = title;
    return button;
  }

  function bindCommand(button: HTMLButtonElement, command: SelectionActionCommand) {
    button.dataset.scholiumCommand = command;
    button.addEventListener("click", () => apply(command));
  }

  function createMenu(trigger: HTMLButtonElement, className: string, parent?: MenuController) {
    const element = document.createElement("div");
    element.className = `scholium-selection-menu ${className}`;
    element.setAttribute("role", "menu");
    element.hidden = true;
    const menu: MenuController = {element, trigger, parent};
    menus.push(menu);
    menuByTrigger.set(trigger, menu);
    trigger.setAttribute("aria-haspopup", "menu");
    trigger.setAttribute("aria-expanded", "false");
    trigger.addEventListener("click", (event) => {
      if (element.hidden) openMenu(menu, event.detail === 0);
      else hideMenu(menu);
    });
    trigger.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
      event.preventDefault();
      openMenu(menu, false);
      const items = visibleMenuButtons(element);
      (event.key === "ArrowUp" ? items.at(-1) : items[0])?.focus();
    });
    element.addEventListener("keydown", (event) => handleMenuKeydown(menu, event));
    root?.append(element);
    return menu;
  }

  function addMenuItem(
    menu: MenuController,
    label: string,
    command: SelectionActionCommand,
    className = "",
    radio = false,
    symbol?: WebSystemSymbolKey,
  ) {
    const item = document.createElement("button");
    item.type = "button";
    item.className = `scholium-selection-menu-item ${className}`.trim();
    item.dataset.scholiumCommand = command;
    item.tabIndex = -1;
    item.setAttribute("role", radio ? "menuitemradio" : "menuitem");
    if (radio) {
      item.setAttribute("aria-checked", "false");
      const check = selectionSymbol("checkmark", "scholium-selection-menu-check");
      styleChecks.set(command, check);
      item.append(check);
    }
    if (symbol) {
      item.append(selectionSymbol(symbol, "scholium-selection-menu-symbol"));
    }
    const text = document.createElement("span");
    text.className = "scholium-selection-menu-label";
    text.textContent = label;
    item.append(text);
    item.addEventListener("click", () => apply(command));
    menu.element.append(item);
    return item;
  }

  function addSubmenuItem(
    menu: MenuController,
    label: string,
    symbol?: WebSystemSymbolKey,
  ) {
    const item = document.createElement("button");
    item.type = "button";
    item.className = "scholium-selection-menu-item scholium-selection-submenu-trigger";
    item.tabIndex = -1;
    item.setAttribute("role", "menuitem");
    const text = document.createElement("span");
    text.className = "scholium-selection-menu-label";
    text.textContent = label;
    const leading = document.createElement("span");
    leading.className = "scholium-selection-menu-leading";
    if (symbol) {
      leading.append(selectionSymbol(symbol, "scholium-selection-menu-symbol"));
    }
    leading.append(text);
    item.append(leading, chevronIcon("scholium-selection-submenu-chevron"));
    menu.element.append(item);
    return item;
  }

  function handleMenuKeydown(menu: MenuController, event: KeyboardEvent) {
    const items = visibleMenuButtons(menu.element);
    const current = event.target instanceof HTMLButtonElement ? items.indexOf(event.target) : -1;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const delta = event.key === "ArrowDown" ? 1 : -1;
      items[(current + delta + items.length) % items.length]?.focus();
      return;
    }
    if (event.key === "Home" || event.key === "End") {
      event.preventDefault();
      (event.key === "Home" ? items[0] : items.at(-1))?.focus();
      return;
    }
    if (event.key === "ArrowRight" && event.target instanceof HTMLButtonElement) {
      const submenu = menuByTrigger.get(event.target);
      if (submenu) {
        event.preventDefault();
        openMenu(submenu, true);
      }
      return;
    }
    if (event.key === "ArrowLeft" && menu.parent) {
      event.preventDefault();
      hideMenu(menu);
      menu.trigger.focus();
      return;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      const top = topMenu(menu);
      closeMenus();
      top.trigger.focus();
      return;
    }
    if (event.key === "Tab") {
      const controls = visibleToolbarControls();
      const trigger = topMenu(menu).trigger;
      const index = controls.indexOf(trigger);
      const destination = controls[index + (event.shiftKey ? -1 : 1)];
      closeMenus();
      if (destination) {
        event.preventDefault();
        destination.focus();
      }
    }
  }

  function refreshTextStyle(view: EditorView) {
    const line = view.state.doc.lineAt(view.state.selection.main.head);
    const heading = /^ {0,3}(#{1,6})[ \t]+/.exec(line.text);
    const active = heading
      ? `heading${heading[1].length}` as SelectionActionCommand
      : "paragraph";
    if (active === activeTextStyle) return;
    activeTextStyle = active;
    for (const [command, check] of styleChecks) {
      const selected = command === active;
      check.parentElement?.setAttribute("aria-checked", String(selected));
      check.classList.toggle("scholium-selection-menu-check-active", selected);
    }
  }

  function requestPosition(view: EditorView) {
    if (!root || root.hidden) return;
    const generation = supersedePositionRequest();
    let settled = false;
    const read = () => {
      if (settled || generation !== positionGeneration || !root || root.hidden) return null;
      const selection = options.selectionForPresentation?.(view) ?? view.state.selection;
      const main = selection.main;
      const from = Math.min(main.anchor, main.head);
      const to = Math.max(main.anchor, main.head);
      let anchor: {left: number; right: number; top: number; bottom: number} | null = null;
      for (const element of view.contentDOM.querySelectorAll<HTMLElement>(
        ".cm-scholium-selected-text",
      )) {
        for (const rectangle of element.getClientRects()) {
          if (rectangle.width <= 0 || rectangle.height <= 0) continue;
          anchor = anchor
            ? {
                left: Math.min(anchor.left, rectangle.left),
                right: Math.max(anchor.right, rectangle.right),
                top: Math.min(anchor.top, rectangle.top),
                bottom: Math.max(anchor.bottom, rectangle.bottom),
              }
            : {
                left: rectangle.left,
                right: rectangle.right,
                top: rectangle.top,
                bottom: rectangle.bottom,
              };
        }
      }
      if (!anchor) {
        const start = view.coordsAtPos(from, 1)
          ?? view.coordsAtPos(Math.min(to, from + 1), -1);
        const end = view.coordsAtPos(to, -1)
          ?? view.coordsAtPos(Math.max(from, to - 1), 1)
          ?? start;
        if (!start || !end) return null;
        anchor = {
          left: Math.min(start.left, end.left),
          right: Math.max(start.right, end.right),
          top: Math.min(start.top, end.top),
          bottom: Math.max(start.bottom, end.bottom),
        };
      }
      const bounds = root.getBoundingClientRect();
      return floatingSurfacePosition({
        anchor,
        surface: bounds,
        viewport: {width: window.innerWidth, height: window.innerHeight},
        horizontal: "center",
        preferredPlacement: "above",
        inset: 8,
        gap: 6,
      });
    };
    const write = (measured: ReturnType<typeof read>) => {
      if (settled || generation !== positionGeneration || !root || root.hidden) return;
      settled = true;
      if (positionWatchdog !== null) {
        window.clearTimeout(positionWatchdog);
        positionWatchdog = null;
      }
      if (!measured) {
        hide();
        return;
      }
      const left = `${measured.left}px`;
      const top = `${measured.top}px`;
      if (root.style.left !== left) root.style.left = left;
      if (root.style.top !== top) root.style.top = top;
      root.style.visibility = "visible";
      if (menus.some((menu) => !menu.element.hidden)) {
        window.queueMicrotask(positionOpenMenus);
      }
    };
    view.requestMeasure({
      read,
      write,
      key: positionMeasureKey,
    });
    // WebKit may throttle animation frames for an attached but occluded
    // document surface. Keep the bar unavailable until it is positioned, then
    // use one bounded fallback instead of exposing the offscreen static box.
    positionWatchdog = window.setTimeout(() => write(read()), 50);
  }

  function scheduleFocusExit(view: EditorView) {
    clearFocusExitTimer();
    focusExitTimer = window.setTimeout(() => {
      focusExitTimer = null;
      if (root?.contains(document.activeElement)
          || view.hasFocus
          || view.contentDOM.contains(document.activeElement)) return;
      hide();
    }, 0);
  }

  function handleToolbarKeydown(event: KeyboardEvent) {
    const controls = visibleToolbarControls();
    const current = event.target instanceof HTMLButtonElement ? controls.indexOf(event.target) : -1;
    if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
      event.preventDefault();
      const delta = event.key === "ArrowRight" ? 1 : -1;
      controls[(current + delta + controls.length) % controls.length]?.focus();
    } else if (event.key === "Home" || event.key === "End") {
      event.preventDefault();
      (event.key === "Home" ? controls[0] : controls.at(-1))?.focus();
    } else if (event.key === "Escape") {
      event.preventDefault();
      closeMenus();
      activeView?.focus();
    }
  }

  function mount(view: EditorView) {
    if (root) return;
    root = document.createElement("div");
    root.id = "scholium-selection-actions";
    root.className = "scholium-selection-actions";
    root.hidden = true;
    root.dataset.scholiumProtected = "selection-actions";
    root.addEventListener("mousedown", (event) => event.preventDefault());
    root.addEventListener("focusin", (event) => {
      clearFocusExitTimer();
      synchronizeKeyboardFocusFeedback(event.target);
    });
    root.addEventListener("focusout", () => {
      window.queueMicrotask(() => synchronizeKeyboardFocusFeedback(document.activeElement));
      if (activeView) scheduleFocusExit(activeView);
    });

    const commandBar = document.createElement("div");
    commandBar.className = "scholium-selection-toolbar";
    commandBar.setAttribute("role", "toolbar");
    commandBar.setAttribute("aria-label", localized("Formatting actions"));
    commandBar.addEventListener("keydown", handleToolbarKeydown);
    root.append(commandBar);

    const styleButton = createToolbarButton(
      localized("Text Style"),
      localized("Text Style"),
      "scholium-selection-style-trigger",
    );
    styleButton.append(
      selectionSymbol("textformat", "scholium-selection-icon-style"),
      chevronIcon("scholium-selection-chevron"),
    );
    commandBar.append(styleButton);
    const styleMenu = createMenu(styleButton, "scholium-selection-style-menu");
    addMenuItem(styleMenu, localized("Paragraph"), "paragraph", "", true);
    for (let level = 1; level <= 6; level += 1) {
      addMenuItem(
        styleMenu,
        localizedTemplate("Heading {level}", {level}),
        `heading${level}` as SelectionActionCommand,
        "",
        true,
      );
    }

    const bold = createToolbarButton(localized("Bold"), localized("Bold (⌘B)"));
    bold.append(selectionSymbol("bold", "scholium-selection-icon-bold"));
    bindCommand(bold, "bold");
    commandBar.append(bold);

    const italic = createToolbarButton(localized("Italic"), localized("Italic (⌘I)"));
    italic.append(selectionSymbol("italic", "scholium-selection-icon-italic"));
    bindCommand(italic, "emphasis");
    commandBar.append(italic);

    const strike = createToolbarButton(
      localized("Strikethrough"),
      localized("Strikethrough"),
      "scholium-selection-wide-only",
    );
    strike.append(selectionSymbol("strikethrough", "scholium-selection-icon-strike"));
    bindCommand(strike, "strikethrough");
    commandBar.append(strike);

    const highlight = createToolbarButton(
      localized("Highlight"),
      localized("Highlight"),
      "scholium-selection-wide-only",
    );
    highlight.append(selectionSymbol("highlighter", "scholium-selection-highlight-icon"));
    bindCommand(highlight, "highlight");
    commandBar.append(highlight);

    const firstSeparator = document.createElement("span");
    firstSeparator.className = "scholium-selection-separator";
    firstSeparator.setAttribute("role", "separator");
    commandBar.append(firstSeparator);

    const link = createToolbarButton(localized("Link"), localized("Link (⌘K)"));
    link.append(selectionSymbol("link", "scholium-selection-link-icon"));
    bindCommand(link, "standardLink");
    commandBar.append(link);

    const wikiGroup = document.createElement("div");
    wikiGroup.className = "scholium-selection-wiki-group";
    wikiGroup.setAttribute("role", "group");
    wikiGroup.setAttribute("aria-label", localized("Wiki links"));
    const wiki = createToolbarButton(localized("Wiki"), null, "scholium-selection-wiki-primary");
    const wikiLabel = document.createElement("span");
    wikiLabel.className = "scholium-selection-label";
    wikiLabel.textContent = localized("Wiki");
    wiki.append(wikiLabel);
    bindCommand(wiki, "wikilink");
    const vector = createToolbarButton(
      localized("Vector Link Options"),
      localized("Vector Link"),
      "scholium-selection-wiki-menu-trigger",
    );
    vector.append(chevronIcon("scholium-selection-chevron"));
    wikiGroup.append(wiki, vector);
    commandBar.append(wikiGroup);
    const vectorMenu = createMenu(vector, "scholium-selection-vector-menu");
    addMenuItem(vectorMenu, localized("Supports"), "vectorSupports", "", false, "plus-circle");
    addMenuItem(vectorMenu, localized("Opposes"), "vectorOpposes", "", false, "minus-circle");
    addMenuItem(vectorMenu, localized("Incompatible"), "vectorIncompatible", "", false, "xmark-circle");

    const secondSeparator = document.createElement("span");
    secondSeparator.className = "scholium-selection-separator";
    secondSeparator.setAttribute("role", "separator");
    commandBar.append(secondSeparator);

    const more = createToolbarButton(localized("More Formatting"), localized("More Formatting"));
    more.append(selectionSymbol("ellipsis", "scholium-selection-more-icon"));
    commandBar.append(more);
    const moreMenu = createMenu(more, "scholium-selection-more-menu");
    addMenuItem(
      moreMenu,
      localized("Strikethrough"),
      "strikethrough",
      "scholium-selection-compact-only",
      false,
      "strikethrough",
    );
    addMenuItem(
      moreMenu,
      localized("Highlight"),
      "highlight",
      "scholium-selection-compact-only",
      false,
      "highlighter",
    );
    addMenuItem(moreMenu, localized("Inline Code"), "inlineCode", "", false, "curlybraces");
    addMenuItem(moreMenu, localized("Code Block"), "fencedCode", "", false, "curlybraces-square");
    const lists = addSubmenuItem(moreMenu, localized("Lists"), "list-bullet");
    const listsMenu = createMenu(lists, "scholium-selection-lists-menu", moreMenu);
    addMenuItem(listsMenu, localized("Bullet List"), "bulletList", "", false, "list-bullet");
    addMenuItem(listsMenu, localized("Numbered List"), "numberedList", "", false, "list-number");
    addMenuItem(listsMenu, localized("Checkbox List"), "taskList", "", false, "checklist");
    addMenuItem(moreMenu, localized("Blockquote"), "blockQuotation", "", false, "text-quote");
    addMenuItem(moreMenu, localized("Comment"), "markdownComment", "", false, "eye-slash");

    const handleDocumentMouseDown = (event: MouseEvent) => {
      if (root && event.target instanceof Node && !root.contains(event.target)) closeMenus();
    };
    const handleContentKeydown = (event: KeyboardEvent) => {
      if (!event.ctrlKey || event.altKey || event.metaKey || event.shiftKey || event.key !== "F5") return;
      if (!root || root.hidden) return;
      event.preventDefault();
      visibleToolbarControls()[0]?.focus();
    };
    const handleResize = () => {
      if (activeView) reposition(activeView);
    };
    const handleContentFocusOut = () => scheduleFocusExit(view);
    const handleWindowFocus = () => {
      if (!root || root.hidden || activeView !== view) update(view);
    };
    const handleWindowBlur = () => hide();
    document.addEventListener("mousedown", handleDocumentMouseDown, true);
    view.contentDOM.addEventListener("keydown", handleContentKeydown);
    view.contentDOM.addEventListener("focusout", handleContentFocusOut);
    window.addEventListener("resize", handleResize);
    window.addEventListener("focus", handleWindowFocus);
    window.addEventListener("blur", handleWindowBlur);
    cleanup = () => {
      document.removeEventListener("mousedown", handleDocumentMouseDown, true);
      view.contentDOM.removeEventListener("keydown", handleContentKeydown);
      view.contentDOM.removeEventListener("focusout", handleContentFocusOut);
      window.removeEventListener("resize", handleResize);
      window.removeEventListener("focus", handleWindowFocus);
      window.removeEventListener("blur", handleWindowBlur);
    };
    document.body.append(root);
    update(view);
  }

  let cleanup: (() => void) | null = null;

  function unmount(view: EditorView) {
    clearFocusExitTimer();
    supersedePositionRequest();
    cleanup?.();
    cleanup = null;
    if (activeView === view) activeView = null;
    root?.remove();
    root = null;
    menus.length = 0;
    styleChecks.clear();
    menuByTrigger.clear();
    presentedDocument = null;
    presentedSelection = null;
    activeTextStyle = null;
  }

  function hide() {
    clearFocusExitTimer();
    supersedePositionRequest();
    if (!root || (root.hidden && activeView === null)) return;
    closeMenus();
    synchronizeKeyboardFocusFeedback(null);
    root.hidden = true;
    activeView = null;
    presentedDocument = null;
    presentedSelection = null;
  }

  function reposition(view: EditorView) {
    if (activeView !== view || !root || root.hidden) return;
    requestPosition(view);
  }

  function update(view: EditorView) {
    if (!root) return;
    const selection = options.selectionForPresentation?.(view) ?? view.state.selection;
    const main = selection.main;
    if (view.composing
        || selection.ranges.length !== 1
        || main.empty
        || options.pointerSelectionIsComplete?.(view) === false
        || options.selectionIsAvailable?.(view) === false) {
      hide();
      return;
    }
    if (!view.hasFocus
        && !view.contentDOM.contains(document.activeElement)
        && !root.contains(document.activeElement)) {
      scheduleFocusExit(view);
      return;
    }
    if (!root.hidden
        && activeView === view
        && presentedDocument === view.state.doc
        && presentedSelection?.eq(selection)) {
      reposition(view);
      return;
    }
    clearFocusExitTimer();
    activeView = view;
    presentedDocument = view.state.doc;
    presentedSelection = selection;
    if (root.hidden) {
      root.style.visibility = "hidden";
      root.hidden = false;
    }
    refreshTextStyle(view);
    requestPosition(view);
  }

  const extension = ViewPlugin.define((view) => {
    mount(view);
    return {
      update(updateEvent: ViewUpdate) {
        if (updateEvent.docChanged
            || updateEvent.focusChanged
            || (options.presentationInteractionChanged?.(updateEvent) ?? updateEvent.selectionSet)) {
          update(updateEvent.view);
        } else if (updateEvent.geometryChanged || updateEvent.viewportChanged) {
          reposition(updateEvent.view);
        }
      },
      destroy() {
        unmount(view);
      },
    };
  });

  return {
    extension,
    hide,
    reposition,
    update,
  };
}
