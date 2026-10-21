import {parseHTML} from "linkedom";
import {afterEach, describe, expect, it, vi} from "vitest";
import {awaitVisibleDocumentImages, createDocumentImageReadiness, invalidateDocumentImageReadiness} from "../document-widget-readiness";
import {installReviewImageActivation} from "../review-image-activation";

function fixture() {
  const {document, window} = parseHTML("<html><body><main></main></body></html>");
  vi.stubGlobal("Element", window.Element);
  const root = document.querySelector("main")!;
  const viewport = {left: 0, right: 300, top: 0, bottom: 200};
  const label = vi.fn((name: string) => `Preview image ${name}`);
  const preview = vi.fn();
  const image = (index: number, options: {offscreen?: boolean; linked?: boolean; failed?: boolean} = {}) => {
    const element = document.createElement("img") as HTMLImageElement;
    element.className = "scholium-embedded-image";
    element.alt = `图 é ${index}`;
    element.dataset.scholiumImageTarget = `Attachments/${index}%2525.png`;
    element.dataset.scholiumImageLayout = "block";
    element.src = "data:image/png;base64,thumbnail";
    Object.defineProperties(element, {
      complete: {value: true},
      naturalWidth: {value: options.failed ? 0 : 400},
      naturalHeight: {value: options.failed ? 0 : 200},
    });
    const top = options.offscreen ? 500 : 20;
    element.getBoundingClientRect = () => ({left: 10, right: 210, top, bottom: top + 100,
      width: 200, height: 100} as DOMRect);
    element.decode = vi.fn(() => options.failed ? Promise.reject(new Error("invalid pixels")) : Promise.resolve());
    if (options.linked) {
      const link = document.createElement("a");
      link.href = "scholium-note:Other";
      link.append(element);
      root.append(link);
    } else root.append(element);
    return element;
  };
  const install = () => installReviewImageActivation(root, {label, preview, contextMenu: vi.fn()});
  return {document, window, root, viewport, label, preview, image, install};
}

describe("Review decoded image readiness", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("refreshes each decoded image once and does no work on a repeated settle", async () => {
    const {root, viewport, label, image, install} = fixture();
    const images = Array.from({length: 20}, (_, index) => image(index));
    const activation = install();
    const presentation = images.map(element => element.outerHTML);
    label.mockClear();
    const decoded = createDocumentImageReadiness();
    const settle = () => awaitVisibleDocumentImages(root, viewport, decoded, () => {},
      image => activation.refreshImage(image));
    expect(await settle()).toBe(true);
    console.info(`REVIEW_IMAGE_READINESS images=20 visible=20 activationVisits=${label.mock.calls.length}`);
    expect(label).toHaveBeenCalledTimes(20);
    expect(images.every(element => vi.mocked(element.decode).mock.calls.length === 1)).toBe(true);
    expect(images.map(element => element.outerHTML)).toEqual(presentation);
    label.mockClear();
    expect(await settle()).toBe(false);
    expect(label).not.toHaveBeenCalled();
    activation.destroy();
  });

  it("retains linked, failed and offscreen image presentation without touching unowned images", async () => {
    const {document, root, viewport, label, image, install} = fixture();
    const direct = image(0);
    const linked = image(1, {linked: true});
    const failed = image(2, {failed: true});
    const offscreen = image(3, {offscreen: true});
    const ordinary = image(4);
    ordinary.className = "authored-image";
    ordinary.setAttribute("role", "navigation");
    ordinary.setAttribute("tabindex", "7");
    ordinary.setAttribute("aria-label", "Authored é 图");
    const outside = image(5);
    document.body.append(outside);
    const activation = install();
    const ordinaryPresentation = ordinary.outerHTML;
    const outsidePresentation = outside.outerHTML;
    label.mockClear();
    expect(await awaitVisibleDocumentImages(root, viewport, createDocumentImageReadiness(), () => {},
      decoded => activation.refreshImage(decoded))).toBe(true);
    activation.refreshImage(outside);
    expect(label).toHaveBeenCalledExactlyOnceWith("图 é 0 (0%25.png)");
    expect(direct.getAttribute("role")).toBe("button");
    expect(direct.style.getPropertyValue("--scholium-image-aspect-ratio")).toBe("2");
    expect(linked.hasAttribute("role")).toBe(false);
    expect(linked.parentElement?.getAttribute("href")).toBe("scholium-note:Other");
    expect(failed.hasAttribute("role")).toBe(false);
    expect(failed.alt).toBe("图 é 2");
    expect(failed.src).toBe("data:image/png;base64,thumbnail");
    expect(offscreen.decode).not.toHaveBeenCalled();
    expect(outside.decode).not.toHaveBeenCalled();
    expect(ordinary.outerHTML).toBe(ordinaryPresentation);
    expect(outside.outerHTML).toBe(outsidePresentation);
    activation.destroy();
  });

  it.each(["detached", "stale"])("does not refresh an image after decode becomes %s", async reason => {
    const {root, viewport, label, image, install} = fixture();
    const element = image(0);
    let release!: () => void;
    element.decode = vi.fn(() => new Promise<void>(resolve => { release = resolve; }));
    const activation = install();
    label.mockClear();
    let current = true;
    const pending = awaitVisibleDocumentImages(root, viewport, createDocumentImageReadiness(), () => {
      if (!current) throw new Error("old reader");
    }, decoded => activation.refreshImage(decoded));
    if (reason === "detached") element.remove();
    else current = false;
    release();
    if (reason === "stale") await expect(pending).rejects.toThrow("old reader");
    else expect(await pending).toBe(true);
    expect(label).not.toHaveBeenCalled();
    activation.destroy();
  });

  it("decodes a replacement src on the same node and settles removal once", async () => {
    const {root, viewport, image} = fixture();
    const element = image(0);
    const decoded = createDocumentImageReadiness();
    const apply = vi.fn();
    const settle = () => awaitVisibleDocumentImages(root, viewport, decoded, () => {}, apply);
    expect(await settle()).toBe(true);
    expect(await settle()).toBe(false);
    element.src = "data:image/png;base64,replacement";
    expect(await settle()).toBe(true);
    expect(element.decode).toHaveBeenCalledTimes(2);
    expect(await settle()).toBe(false);
    element.removeAttribute("src");
    expect(await settle()).toBe(true);
    expect(await settle()).toBe(false);
    expect(element.decode).toHaveBeenCalledTimes(3);
  });

  it.each(["replacement", "removal"])("does not apply an obsolete decode or mark %s ready", async change => {
    const {root, viewport, image} = fixture();
    const element = image(0);
    let release!: () => void;
    element.decode = vi.fn().mockImplementationOnce(() => new Promise<void>(resolve => { release = resolve; }))
      .mockResolvedValue(undefined);
    const decoded = createDocumentImageReadiness();
    const apply = vi.fn();
    const settle = () => awaitVisibleDocumentImages(root, viewport, decoded, () => {}, apply);
    const original = settle();
    if (change === "replacement") element.src = "data:image/png;base64,replacement";
    else element.removeAttribute("src");
    release();
    expect(await original).toBe(true);
    expect(decoded.has(element)).toBe(false);
    expect(apply).not.toHaveBeenCalled();
    expect(await settle()).toBe(true);
    expect(element.decode).toHaveBeenCalledTimes(2);
    expect(apply).toHaveBeenCalledExactlyOnceWith(element);
    expect(await settle()).toBe(false);
  });

  it("does not let an old completion overwrite a newer resource's completed readiness", async () => {
    const {root, viewport, image} = fixture();
    const element = image(0);
    let release!: () => void;
    element.decode = vi.fn().mockImplementationOnce(() => new Promise<void>(resolve => { release = resolve; }))
      .mockResolvedValue(undefined);
    const decoded = createDocumentImageReadiness();
    const apply = vi.fn();
    const settle = () => awaitVisibleDocumentImages(root, viewport, decoded, () => {}, apply);
    const original = settle();
    element.src = "data:image/png;base64,replacement";
    expect(await settle()).toBe(true);
    release();
    expect(await original).toBe(true);
    expect(decoded.get(element)?.source).toBe("data:image/png;base64,replacement");
    expect(apply).toHaveBeenCalledExactlyOnceWith(element);
    expect(await settle()).toBe(false);
  });

  it("invalidates a removed and restored resource even when no settle observes the intermediate src", async () => {
    const {root, viewport, image} = fixture();
    const element = image(0);
    const original = element.getAttribute("src")!;
    const decoded = createDocumentImageReadiness();
    const settle = () => awaitVisibleDocumentImages(root, viewport, decoded, () => {}, () => {});
    expect(await settle()).toBe(true);
    element.removeAttribute("src");
    invalidateDocumentImageReadiness(element);
    element.setAttribute("src", original);
    invalidateDocumentImageReadiness(element);
    expect(await settle()).toBe(true);
    expect(element.decode).toHaveBeenCalledTimes(2);
    expect(await settle()).toBe(false);
  });
});
