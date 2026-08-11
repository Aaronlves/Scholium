import {describe, expect, it} from "vitest";
import {documentFindMatches, type DocumentFindRequest} from "../document-find";

const request = (
  query: string,
  overrides: Partial<DocumentFindRequest> = {},
): DocumentFindRequest => ({
  query,
  replacement: "",
  caseSensitive: false,
  wholeWord: false,
  action: "update",
  ...overrides,
});

describe("document find", () => {
  it("uses literal, case-insensitive matching by default", () => {
    expect(documentFindMatches("Value value a.b axb", request("value"))).toEqual([
      {from: 0, to: 5},
      {from: 6, to: 11},
    ]);
    expect(documentFindMatches("a.b axb", request("a.b"))).toEqual([
      {from: 0, to: 3},
    ]);
  });

  it("respects case-sensitive and whole-word options", () => {
    expect(documentFindMatches(
      "Value value valuable",
      request("value", {caseSensitive: true}),
    )).toEqual([{from: 6, to: 11}]);
    expect(documentFindMatches(
      "value valuable value",
      request("value", {wholeWord: true}),
    )).toEqual([{from: 0, to: 5}, {from: 15, to: 20}]);
  });
});
