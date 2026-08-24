import {describe, expect, it} from "vitest";
import {createLiveInlineWidgets} from "../live-inline-widgets";

const widgets = createLiveInlineWidgets({
  requestMathRuntime() {},
  didToggleTask() {},
});

describe("live inline widget presentation", () => {
  it("keeps ordinary aliases visible", () => {
    expect(widgets.wikilinkPresentation(2, "Target", 12, "Readable")).toEqual({
      displayStart: 12,
      displayEnd: 20,
      isLegacyRelationship: false,
    });
  });

  it("hides a legacy relationship suffix without losing its authored alias", () => {
    expect(widgets.wikilinkPresentation(2, "Target", 12, "Readable: supports")).toEqual({
      displayStart: 12,
      displayEnd: 20,
      isLegacyRelationship: true,
    });
    expect(widgets.wikilinkPresentation(2, "Target", 12, ":supports")).toEqual({
      displayStart: 2,
      displayEnd: 8,
      isLegacyRelationship: true,
    });
  });

  it("derives nested list indentation from the shared semantic variable", () => {
    expect(widgets.listIndent(0)).toBe("");
    expect(widgets.listIndent(2)).toBe(
      "calc(var(--scholium-list-indent) + var(--scholium-list-indent))",
    );
  });
});
