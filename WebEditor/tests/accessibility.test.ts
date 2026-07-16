import {parseHTML} from "linkedom";
import {describe, expect, it, vi} from "vitest";
import {
  activeConstructAccessibilityDescription,
  announceEditorMessage,
  editorAccessibilityAttributes,
  updateEditorAccessibility,
} from "../accessibility";
import type {EditorContext} from "../protocol";

const context = (blocks: string[] = [], inline: string[] = []): EditorContext => ({
  selections: [{anchor: 0, head: 0}],
  activeInlineConstructs: inline,
  activeBlockConstructs: blocks,
  composing: false,
  availableCommands: [],
});

describe("editor accessibility contract", () => {
  it("keeps one labeled multiline textbox without a duplicate value representation", () => {
    const attributes = editorAccessibilityAttributes("livePreview");
    expect(attributes).toMatchObject({
      role: "textbox",
      "aria-label": "Markdown live preview editor",
      "aria-multiline": "true",
      spellcheck: "true",
    });
    expect("aria-valuetext" in attributes).toBe(false);
  });

  it("describes the active semantic construct without replacing the editable source", () => {
    expect(activeConstructAccessibilityDescription(context(["ATXHeading2"]))).toBe("Heading level 2");
    expect(activeConstructAccessibilityDescription(context([], ["Link"]))).toBe("Link");
    expect(activeConstructAccessibilityDescription(context(["Callout"]))).toBe("Callout");
  });

  it("restores the stable construct description after a consequential announcement", () => {
    vi.useFakeTimers();
    const {document, window} = parseHTML("<div id='editor'></div>");
    Object.assign(globalThis, {window});
    const content = document.getElementById("editor") as unknown as HTMLElement;
    updateEditorAccessibility(content, "livePreview", context(["ATXHeading3"]));
    announceEditorMessage(content, "The exact source was recovered.");
    expect(content.getAttribute("aria-description")).toBe("The exact source was recovered.");
    vi.advanceTimersByTime(4_000);
    expect(content.getAttribute("aria-description")).toBe("Heading level 3");
    vi.useRealTimers();
  });
});
