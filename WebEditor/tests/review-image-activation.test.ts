import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {installReviewImageActivation} from "../review-image-activation";

function fixture(options: {linked?: boolean; loaded?: boolean; enabled?: boolean; block?: boolean} = {}) {
  const markup = `<img class="scholium-embedded-image" alt="图 é" data-scholium-image-target="Attachments/100%2525.png" data-scholium-image-layout="${options.block === false ? "inline" : "block"}" src="data:image/png;base64,thumbnail">`;
  const {document, window} = parseHTML(`<html><body><main>${options.linked ? `<a href="scholium-note:Other">${markup}</a>` : markup}</main></body></html>`);
  vi.stubGlobal("Element", window.Element);
  const root = document.querySelector("main")!;
  const image = root.querySelector("img")!;
  const state = {complete: options.loaded !== false, width: options.loaded === false ? 0 : 400, height: options.loaded === false ? 0 : 200};
  Object.defineProperties(image, {
    complete: {get: () => state.complete}, naturalWidth: {get: () => state.width}, naturalHeight: {get: () => state.height},
  });
  image.getBoundingClientRect = () => ({left: 20, top: 30, width: 400, height: 200}) as DOMRect;
  const preview = vi.fn();
  const contextMenu = vi.fn();
  const focus = vi.spyOn(image, "focus");
  const activation = installReviewImageActivation(root, options.enabled === false ? null : {
    label: name => `Preview image ${name}`, preview, contextMenu,
  });
  function dispatch(type: string, fields: Record<string, unknown> = {}, target: Element = image) {
    const event = new window.Event(type, {bubbles: true, cancelable: true});
    Object.assign(event, {button: 0, detail: 1, clientX: 70, clientY: 90, key: "", keyCode: 0,
      metaKey: false, altKey: false, ctrlKey: false, shiftKey: false, repeat: false, isComposing: false}, fields);
    target.dispatchEvent(event);
    return event;
  }
  return {root, image, state, preview, contextMenu, focus, activation, dispatch};
}

describe("Review original image activation", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("uses the admitted parser target without interpreting the thumbnail and preserves pointer focus", () => {
    const {image, preview, focus, dispatch} = fixture();
    expect(image.getAttribute("role")).toBe("button");
    expect(image.getAttribute("tabindex")).toBe("0");
    expect(image.getAttribute("aria-label")).toBe("Preview image 图 é (100%25.png)");
    expect(image.classList.contains("scholium-embedded-image-block")).toBe(true);
    expect(image.style.getPropertyValue("--scholium-image-aspect-ratio")).toBe("2");
    expect(dispatch("mousedown").defaultPrevented).toBe(true);
    dispatch("mouseup");
    expect(dispatch("click").defaultPrevented).toBe(true);
    expect(preview).toHaveBeenCalledExactlyOnceWith("Attachments/100%2525.png");
    expect(focus).not.toHaveBeenCalled();
    expect(image.src).toBe("data:image/png;base64,thumbnail");
  });

  it("adds actionable semantics only after successful decoding and removes them on failure", () => {
    const {image, state, preview, dispatch} = fixture({loaded: false});
    expect(image.hasAttribute("role")).toBe(false);
    dispatch("click");
    expect(preview).not.toHaveBeenCalled();
    state.complete = true; state.width = 200; state.height = 400;
    dispatch("load");
    expect(image.getAttribute("role")).toBe("button");
    expect(image.style.getPropertyValue("--scholium-image-aspect-ratio")).toBe("0.5");
    state.width = 0; state.height = 0;
    dispatch("error");
    expect(image.hasAttribute("role")).toBe(false);
    expect(image.hasAttribute("tabindex")).toBe(false);
    expect(image.hasAttribute("aria-label")).toBe(false);
    dispatch("click");
    expect(preview).not.toHaveBeenCalled();
  });

  it("uses Enter and Space without taking composition, repeated keys, or page scroll", () => {
    const {preview, dispatch} = fixture();
    expect(dispatch("keydown", {key: "Enter"}).defaultPrevented).toBe(true);
    dispatch("keydown", {key: "Enter", repeat: true});
    expect(preview).toHaveBeenCalledTimes(1);
    expect(dispatch("keydown", {key: " "}).defaultPrevented).toBe(true);
    expect(preview).toHaveBeenCalledTimes(1);
    dispatch("keyup", {key: " "});
    expect(preview).toHaveBeenCalledTimes(2);
    dispatch("keydown", {key: "Enter", isComposing: true});
    dispatch("keydown", {key: "Enter", keyCode: 229});
    dispatch("keydown", {key: "Enter", metaKey: true});
    expect(preview).toHaveBeenCalledTimes(2);
    dispatch("keydown", {key: " "}); dispatch("focusout"); dispatch("keyup", {key: " "});
    expect(preview).toHaveBeenCalledTimes(2);
  });

  it("retains authored linked-image activation and offers original-image menus from pointer or focused link", () => {
    const {root, image, preview, contextMenu, dispatch} = fixture({linked: true});
    const link = root.querySelector("a")!;
    expect(image.hasAttribute("role")).toBe(false);
    expect(image.hasAttribute("tabindex")).toBe(false);
    expect(dispatch("click").defaultPrevented).toBe(false);
    expect(dispatch("mousedown", {ctrlKey: true}).defaultPrevented).toBe(true);
    expect(dispatch("keydown", {key: "Enter"}, link).defaultPrevented).toBe(false);
    expect(preview).not.toHaveBeenCalled();
    expect(dispatch("contextmenu").defaultPrevented).toBe(true);
    expect(contextMenu).toHaveBeenLastCalledWith("Attachments/100%2525.png", 70, 90);
    expect(dispatch("contextmenu", {clientX: 0, clientY: 0}, link).defaultPrevented).toBe(true);
    expect(contextMenu).toHaveBeenLastCalledWith("Attachments/100%2525.png", 220, 130);
    expect(dispatch("keydown", {key: "F10", shiftKey: true}, link).defaultPrevented).toBe(true);
    expect(contextMenu).toHaveBeenCalledTimes(3);
    expect(contextMenu).toHaveBeenLastCalledWith("Attachments/100%2525.png", 220, 130);
    dispatch("keydown", {key: "ContextMenu", isComposing: true}, link);
    expect(contextMenu).toHaveBeenCalledTimes(3);
    expect(link.getAttribute("href")).toBe("scholium-note:Other");
  });

  it("keeps inline geometry and omits action semantics without the native capability", () => {
    const {image, preview, contextMenu, dispatch} = fixture({enabled: false, block: false});
    expect(image.classList.contains("scholium-embedded-image-block")).toBe(false);
    expect(image.hasAttribute("role")).toBe(false);
    expect(dispatch("click").defaultPrevented).toBe(false);
    expect(dispatch("contextmenu").defaultPrevented).toBe(false);
    expect(preview).not.toHaveBeenCalled();
    expect(contextMenu).not.toHaveBeenCalled();
  });

  it("does not activate detached, unbounded, or removed targets and cleans event listeners", () => {
    const {image, preview, dispatch, activation} = fixture();
    image.dataset.scholiumImageTarget = "🦉".repeat(2_049);
    dispatch("click");
    delete image.dataset.scholiumImageTarget;
    dispatch("click");
    expect(preview).not.toHaveBeenCalled();
    image.dataset.scholiumImageTarget = "Attachments/100%2525.png";
    activation.destroy();
    dispatch("click");
    expect(preview).not.toHaveBeenCalled();
  });

  it.each(["move", "mouseout", "dragstart", "pointercancel", "unreleased", "changedTarget", "detached"])(
    "cancels pointer activation after %s", reason => {
      const {image, preview, dispatch} = fixture();
      dispatch("mousedown");
      if (reason === "move") dispatch("mousemove", {clientX: 75});
      else if (["mouseout", "dragstart", "pointercancel"].includes(reason)) dispatch(reason);
      else if (reason === "changedTarget") image.dataset.scholiumImageTarget = "Attachments/other.png";
      else if (reason === "detached") image.remove();
      if (reason !== "unreleased") dispatch("mouseup");
      dispatch("click");
      expect(preview).not.toHaveBeenCalled();
    });

  it("permits accessibility clicks without pointer events and rejects a changed Space target", () => {
    const {image, preview, dispatch} = fixture();
    dispatch("click", {detail: 0});
    expect(preview).toHaveBeenCalledExactlyOnceWith("Attachments/100%2525.png");
    dispatch("keydown", {key: " "});
    image.dataset.scholiumImageTarget = "Attachments/other.png";
    dispatch("keyup", {key: " "});
    expect(preview).toHaveBeenCalledTimes(1);
  });
});
