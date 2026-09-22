import {EditorState} from "@codemirror/state";
import {history, undoDepth} from "@codemirror/commands";
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
  const extensions = [history(), exactSourceHistory, title.extension];
  state = createMarkdownDocumentState(source, extensions);
  const render = () => {
    const widget = state.field(title.extension).iter().value!.spec.widget;
    const wrapper = widget.toDOM();
    document.body.replaceChildren(wrapper);
    const input = wrapper.querySelector("textarea") as HTMLTextAreaElement;
    input.setSelectionRange = vi.fn();
    return input;
  };
  const event = (input: HTMLTextAreaElement, type: string) => {
    const value = new window.Event(type, {bubbles: true});
    input.dispatchEvent(value);
    return value;
  };
  const draft = (input: HTMLTextAreaElement, value: string) => {
    input.value = value;
    event(input, "input");
  };
  title.setTitle("Title");
  return {
    title, render, event, draft, requestRename, beginComposition, endComposition,
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
