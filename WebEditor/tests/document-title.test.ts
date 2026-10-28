import {Compartment, EditorState} from "@codemirror/state";
import {history, undoDepth} from "@codemirror/commands";
import {showPanel, type EditorView, type Panel, type PanelConstructor, type ViewUpdate} from "@codemirror/view";
import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {createDocumentTitle} from "../document-title";
import {createMarkdownDocumentState} from "../bootstrap";
import {exactSourceHistory, exactSourceState} from "../exact-source-history";

function harness() {
  const {document, window} = parseHTML("<html><body></body></html>");
  vi.stubGlobal("document", document);
  vi.stubGlobal("Element", window.Element);
  let attachment = 1;
  let suspended = false;
  let requestSequence = 0;
  const requestRename = vi.fn();
  const beginComposition = vi.fn();
  const endComposition = vi.fn();
  let state: EditorState;
  const title = createDocumentTitle({
    attachment: () => attachment,
    isSuspended: () => suspended,
    requestID: () => `rename-${++requestSequence}`,
    dispatch: effect => { state = state.update({effects: effect}).state; },
    requestRename,
    focusChanged: vi.fn(),
    beginComposition,
    endComposition,
  });
  const source = "\uFEFF---\r\nkind: note\r\n---\r\n😀 Body\r\n";
  const editMode = new Compartment();
  const extensions = [history(), exactSourceHistory, editMode.of(title.extension)];
  state = createMarkdownDocumentState(source, extensions);
  const scrollDOM = document.createElement("div");
  const contentDOM = document.createElement("div");
  scrollDOM.append(contentDOM);
  document.body.append(scrollDOM);
  const view = {scrollDOM, contentDOM, requestMeasure: vi.fn()} as unknown as EditorView;
  let panel: Panel | undefined;
  let constructor: PanelConstructor | undefined;
  // Exercise the public panel lifecycle without substituting a layout or AX
  // engine. WK integration checks the real CodeMirror mount and geometry.
  const synchronizePanel = () => {
    const next = state.facet(showPanel).find((value): value is PanelConstructor => value !== null);
    if (next !== constructor) {
      const previousGroup = panel?.dom.parentElement;
      panel?.destroy?.();
      previousGroup?.remove();
      constructor = next;
      panel = next?.(view);
      if (panel) {
        const group = document.createElement("div");
        group.className = "cm-panels cm-panels-top";
        group.append(panel.dom);
        panel.mount?.();
        scrollDOM.querySelector(".scholium-note-title-container")!.append(group);
      }
    } else {
      panel?.update?.({state} as ViewUpdate);
    }
  };
  const render = () => {
    synchronizePanel();
    const input = panel!.dom.querySelector("textarea") as HTMLTextAreaElement;
    input.setSelectionRange = vi.fn();
    return input;
  };
  const event = (input: HTMLTextAreaElement, type: string, key?: string) => {
    const value = new window.Event(type, {bubbles: true});
    if (key) Object.defineProperty(value, "key", {value: key});
    input.dispatchEvent(value);
    return value;
  };
  const draft = (input: HTMLTextAreaElement, value: string) => {
    input.value = value;
    event(input, "input");
  };
  title.setTitle("Title");
  return {
    title, render, event, draft, requestRename, beginComposition, endComposition, scrollDOM, contentDOM,
    leaveEdit() {
      state = state.update({effects: editMode.reconfigure([])}).state;
      synchronizePanel();
    },
    enterEdit() {
      state = state.update({effects: editMode.reconfigure(title.extension)}).state;
      synchronizePanel();
    },
    bodyTransaction() { state = state.update({changes: {from: state.doc.length, insert: "Body input"}}).state; },
    suspend: () => { suspended = true; },
    replaceDocument() {
      attachment += 1;
      title.resetDocument();
      state = createMarkdownDocumentState(source, extensions);
      title.setTitle("Next");
    },
    expectSourceUnchanged() {
      expect(state.field(exactSourceState).text).toBe(source);
      expect(undoDepth(state)).toBe(0);
    },
  };
}

afterEach(() => vi.unstubAllGlobals());

describe("filename title ownership", () => {
  it("mounts one separate filename control before Markdown in the same scrolling flow", () => {
    const h = harness();
    const input = h.render();
    const container = h.scrollDOM.querySelector(".scholium-note-title-container")!;
    expect(h.contentDOM.contains(input)).toBe(false);
    expect(container.contains(input)).toBe(true);
    expect(container.nextSibling).toBe(h.contentDOM);
    expect(h.scrollDOM.classList.contains("scholium-note-title-scroll")).toBe(true);
    expect(h.scrollDOM.querySelectorAll(".scholium-note-title-input")).toHaveLength(1);
    h.expectSourceUnchanged();
  });

  it("retains a title draft and its control across an independent body transaction", () => {
    const h = harness();
    const input = h.render();
    h.draft(input, "Draft 中文 🦉");
    h.bodyTransaction();
    expect(h.render()).toBe(input);
    expect(input.value).toBe("Draft 中文 🦉");
    expect(h.requestRename).not.toHaveBeenCalled();
    expect(h.title.allowsDetachment()).toBe(false);
  });

  it("removes its panel framing when Edit leaves and remounts one saved title", () => {
    const h = harness();
    h.render();
    h.leaveEdit();
    expect(h.scrollDOM.querySelector(".scholium-note-title-container")).toBeNull();
    expect(h.scrollDOM.classList.contains("scholium-note-title-scroll")).toBe(false);
    expect(h.contentDOM.querySelector("textarea")).toBeNull();
    h.expectSourceUnchanged();
    h.enterEdit();
    expect(h.render().value).toBe("Title");
    expect(h.scrollDOM.querySelectorAll(".scholium-note-title-input")).toHaveLength(1);
  });

  it("restores the saved accessible heading with the input when Escape cancels a title draft", () => {
    const h = harness();
    const input = h.render();
    const heading = input.parentElement!;
    input.blur = () => { h.event(input, "blur"); };
    expect(heading.getAttribute("role")).toBe("heading");
    for (const draft of ["Cancelled title 中文", "Another draft 🦉"]) {
      h.draft(input, draft);
      expect(heading.getAttribute("aria-label")).toBe(draft);
      h.event(input, "keydown", "Escape");
      expect(input.value).toBe("Title");
      expect(heading.getAttribute("aria-label")).toBe("Title");
      expect(h.title.allowsDetachment()).toBe(true);
      expect(h.requestRename).not.toHaveBeenCalled();
      h.expectSourceUnchanged();
    }
  });

  it("clears a rejected rename's error projection when Escape restores the saved title", async () => {
    const h = harness();
    let input = h.render();
    for (const [index, draft] of ["Rejected 中文", "Rejected again 🦉"].entries()) {
      h.draft(input, draft); h.event(input, "blur");
      h.title.resolveRename(`rename-${index + 1}`, false, "Title", "Name already exists");
      input = h.render(); await Promise.resolve();
      const heading = input.parentElement!;
      input.blur = () => { h.event(input, "blur"); };
      expect(input.getAttribute("aria-invalid")).toBe("true");
      expect(input.getAttribute("aria-describedby")).toBe("scholium-note-title-error");
      expect(heading.querySelector("[role=alert]")?.textContent).toBe("Name already exists");
      h.event(input, "keydown", "Escape");
      expect(input.value).toBe("Title");
      expect(heading.getAttribute("aria-label")).toBe("Title");
      expect(input.getAttribute("aria-invalid")).toBeNull();
      expect(input.getAttribute("aria-describedby")).toBeNull();
      expect(heading.querySelector("[role=alert]")).toBeNull();
      expect(h.requestRename).toHaveBeenCalledTimes(index + 1);
      expect(h.title.allowsDetachment()).toBe(true);
      h.expectSourceUnchanged();
    }
  });

  it("keeps drafts and rename failures outside source and blocks detachment until settled", async () => {
    const h = harness();
    let input = h.render();
    expect(h.title.allowsDetachment()).toBe(true);
    h.draft(input, "");
    expect(h.title.allowsDetachment()).toBe(false);
    h.draft(input, "Draft");
    h.event(input, "blur");
    expect(h.requestRename).toHaveBeenCalledWith({requestID: "rename-1", expectedTitle: "Title", requestedTitle: "Draft"});
    expect(input.disabled).toBe(true);
    expect(h.title.allowsDetachment()).toBe(false);
    h.title.resolveRename("wrong", true, "Ignored", "");
    expect(h.title.allowsDetachment()).toBe(false);
    h.title.resolveRename("rename-1", false, "Title", "Name already exists");
    input = h.render();
    await Promise.resolve();
    expect(input.value).toBe("Draft");
    expect(input.getAttribute("aria-invalid")).toBe("true");
    expect(h.title.allowsDetachment()).toBe(false);
    h.draft(input, "Available");
    h.event(input, "blur");
    h.title.resolveRename("rename-2", true, "Available", "");
    expect(h.render().value).toBe("Available");
    expect(h.title.allowsDetachment()).toBe(true);
    h.expectSourceUnchanged();
  });

  it("delegates IME lifetime to the shared gate and waits to rename until composition ends", () => {
    const h = harness();
    const input = h.render();
    let ownsComposition = false;
    input.addEventListener("compositionstart", event => {
      ownsComposition = h.title.ownsCompositionEvent(event);
    });
    h.event(input, "compositionstart");
    expect(ownsComposition).toBe(true);
    expect(h.beginComposition).toHaveBeenCalledOnce();
    h.draft(input, "中文\n标题");
    h.event(input, "blur");
    expect(h.requestRename).not.toHaveBeenCalled();
    h.event(input, "compositionend");
    expect(h.endComposition).toHaveBeenCalledOnce();
    expect(h.requestRename).toHaveBeenCalledWith({requestID: "rename-1", expectedTitle: "Title", requestedTitle: "中文 标题"});
    h.expectSourceUnchanged();
  });

  it("rejects old control events and rename replies after attachment changes", () => {
    const h = harness();
    const oldInput = h.render();
    h.draft(oldInput, "Old draft");
    h.event(oldInput, "blur");
    h.replaceDocument();
    h.title.resolveRename("rename-1", true, "Old draft", "");
    h.draft(oldInput, "Stale input");
    h.event(oldInput, "blur");
    h.event(oldInput, "compositionstart");
    expect(h.requestRename).toHaveBeenCalledOnce();
    expect(h.beginComposition).not.toHaveBeenCalled();
    expect(h.render().value).toBe("Next");
    expect(h.title.allowsDetachment()).toBe(true);
    h.expectSourceUnchanged();
  });

  it("does not send a rename from a suspended editor", () => {
    const h = harness();
    const input = h.render();
    h.draft(input, "Draft");
    h.suspend();
    h.event(input, "blur");
    expect(h.requestRename).not.toHaveBeenCalled();
    expect(h.title.allowsDetachment()).toBe(false);
    h.expectSourceUnchanged();
  });
});
