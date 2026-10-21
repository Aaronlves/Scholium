import {parseHTML} from "linkedom";
import {describe, expect, it, vi} from "vitest";
import {awaitVisibleDocumentImages, awaitVisibleDocumentWidgets, beginDocumentWidgetPreparation, createDocumentImageReadiness, pendingVisibleDocumentWidgetCounts} from "../document-widget-readiness";

function harness() {
  const {document} = parseHTML("<html><body><div id='viewport'><div id='root'></div></div><div id='popover'></div></body></html>");
  const root = document.getElementById("root")!;
  const viewport = document.getElementById("viewport")!;
  viewport.getBoundingClientRect = () => ({left: 0, right: 300, top: 0, bottom: 200} as DOMRect);
  const node = (parent = root, top = 40) => {
    const element = document.createElement("div");
    element.getBoundingClientRect = () => ({left: 10, right: 200, top, bottom: top + 30} as DOMRect);
    parent.append(element);
    return element;
  };
  return {document, root, viewport, node};
}

describe("document viewport widget readiness", () => {
  it("reports actual pending visible Math and Mermaid until their preparation ends", () => {
    const {root, viewport, node} = harness();
    const mathNode = node();
    mathNode.className = "scholium-math";
    const math = beginDocumentWidgetPreparation(mathNode);
    const mermaidNode = node();
    mermaidNode.className = "cm-live-mermaid-widget";
    const mermaid = beginDocumentWidgetPreparation(mermaidNode);
    const offscreen = beginDocumentWidgetPreparation(node(root, 500));
    expect(pendingVisibleDocumentWidgetCounts(root, viewport)).toEqual({math: 1, mermaid: 1, other: 0});
    math.finish();
    mermaidNode.remove();
    expect(pendingVisibleDocumentWidgetCounts(root, viewport)).toEqual({math: 0, mermaid: 0, other: 0});
    mermaid.finish();
    offscreen.finish();
  });

  it("waits for visible real widgets while excluding offscreen widgets and popovers", async () => {
    const {document, root, viewport, node} = harness();
    const visible = beginDocumentWidgetPreparation(node());
    const offscreen = beginDocumentWidgetPreparation(node(root, 500));
    const popover = beginDocumentWidgetPreparation(node(document.getElementById("popover")!));
    let completed = false;
    const pending = awaitVisibleDocumentWidgets(root, viewport, () => {}).then(waited => {
      completed = true;
      return waited;
    });
    await Promise.resolve();
    expect(completed).toBe(false);
    visible.finish();
    expect(await pending).toBe(true);
    expect(await awaitVisibleDocumentWidgets(root, viewport, () => {})).toBe(false);
    offscreen.finish();
    popover.finish();
  });

  it("collects newly visible work after the caller restores and measures its viewport", async () => {
    const {root, viewport, node} = harness();
    const element = node(root, 500);
    const preparation = beginDocumentWidgetPreparation(element);
    expect(await awaitVisibleDocumentWidgets(root, viewport, () => {})).toBe(false);
    element.getBoundingClientRect = () => ({left: 10, right: 200, top: 0, bottom: 30} as DOMRect);
    const pending = awaitVisibleDocumentWidgets(root, viewport, () => {});
    preparation.finish();
    expect(await pending).toBe(true);
  });

  it.each(["widget", "root"])("does not wait for unfinished rendering after its %s is removed", async kind => {
    const {root, viewport, node} = harness();
    const element = node();
    const preparation = beginDocumentWidgetPreparation(element);
    const pending = awaitVisibleDocumentWidgets(root, viewport, () => {});
    (kind === "widget" ? element : root).remove();
    expect(await pending).toBe(true);
    preparation.finish();
  });

  it("rejects stale admission after pending work settles", async () => {
    const {root, viewport, node} = harness();
    const preparation = beginDocumentWidgetPreparation(node());
    let current = true;
    const pending = awaitVisibleDocumentWidgets(root, viewport, () => {
      if (!current) throw new Error("old attachment");
    });
    current = false;
    preparation.finish();
    await expect(pending).rejects.toThrow("old attachment");
  });
});

describe("shared visible image readiness", () => {
  it("settles cached and zero-size embedded images, excludes offscreen and popover content, and rechecks the restored viewport", async () => {
    const {document, root, viewport, node} = harness();
    const image = (parent: HTMLElement, top: number, empty = false) => {
      const element = document.createElement("img") as HTMLImageElement;
      element.getBoundingClientRect = () => ({left: 10, right: 200, top, bottom: top + 30,
        width: empty ? 0 : 190, height: empty ? 0 : 30} as DOMRect);
      element.decode = vi.fn(() => Promise.resolve());
      Object.defineProperty(element, "complete", {value: true});
      parent.append(element);
      return element;
    };
    const cached = image(root, 20);
    const zeroSize = image(node(), 0, true);
    const later = image(root, 500);
    const popover = image(document.getElementById("popover")!, 20);
    const decoded = createDocumentImageReadiness();
    const apply = vi.fn();
    expect(await awaitVisibleDocumentImages(root, viewport.getBoundingClientRect(), decoded, () => {}, apply)).toBe(true);
    expect(cached.decode).toHaveBeenCalledOnce();
    expect(zeroSize.decode).toHaveBeenCalledOnce();
    expect(later.decode).not.toHaveBeenCalled();
    expect(popover.decode).not.toHaveBeenCalled();
    expect(apply.mock.calls.map(([value]) => value)).toEqual([cached, zeroSize]);
    later.getBoundingClientRect = () => ({left: 10, right: 200, top: 40, bottom: 70, width: 190, height: 30} as DOMRect);
    expect(await awaitVisibleDocumentImages(root, viewport.getBoundingClientRect(), decoded, () => {}, apply)).toBe(true);
    expect(later.decode).toHaveBeenCalledOnce();
    expect(await awaitVisibleDocumentImages(root, viewport.getBoundingClientRect(), decoded, () => {}, apply)).toBe(false);
  });

  it("keeps failed media terminal and never applies a detached image's presentation", async () => {
    const {document, root, viewport, node} = harness();
    const failed = document.createElement("img") as HTMLImageElement;
    failed.alt = "Authored alt";
    failed.decode = vi.fn(() => Promise.reject(new Error("invalid pixels")));
    failed.getBoundingClientRect = () => ({width: 0, height: 0} as DOMRect);
    node().append(failed);
    const decoded = createDocumentImageReadiness();
    const apply = vi.fn();
    expect(await awaitVisibleDocumentImages(root, viewport.getBoundingClientRect(), decoded, () => {}, apply)).toBe(true);
    expect(failed.alt).toBe("Authored alt");
    expect(await awaitVisibleDocumentImages(root, viewport.getBoundingClientRect(), decoded, () => {}, apply)).toBe(false);
    let complete!: () => void;
    const removed = document.createElement("img") as HTMLImageElement;
    removed.decode = () => new Promise(resolve => { complete = resolve; });
    removed.getBoundingClientRect = failed.getBoundingClientRect;
    node().append(removed);
    const pending = awaitVisibleDocumentImages(root, viewport.getBoundingClientRect(), decoded, () => {}, apply);
    removed.remove();
    complete();
    await pending;
    expect(apply).toHaveBeenCalledOnce();
  });
});
