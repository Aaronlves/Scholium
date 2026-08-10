import {describe, expect, it} from "vitest";
import {
  EDITOR_PROTOCOL_VERSION, MAX_INBOUND_BYTES, encodedByteLength, isEditorRequest,
  recoveryGenerationCanReplaceCurrent, rejected,
} from "../protocol";

const request = {
  protocolVersion: EDITOR_PROTOCOL_VERSION,
  requestID: "request",
  sessionID: "session",
  documentID: "document",
  startingFingerprint: "fingerprint",
  knownGeneration: 4,
  operation: {type: "queryText" as const},
};

const dialect = {
  version: 4,
  callouts: [{identifier: "state", aliases: ["definition"], label: "Statement", meaning: "Claim"}],
  vectorLinkOperators: [
    {marker: "", kind: "neutral", meaning: "Neutral"},
    {marker: "+", kind: "supports", meaning: "Supports"},
    {marker: "-", kind: "opposes", meaning: "Opposes"},
    {marker: "?", kind: "incompatible", meaning: "Incompatible"},
  ],
  footnotes: {
    namedReferenceOpening: "[^", namedReferenceClosing: "]", definitionSeparator: ":",
    inlineOpening: "^[", continuationIndentSpaces: 2, allowsTabContinuation: true,
    caseSensitiveIdentifiers: true, ordinalByFirstReference: true,
  },
  mathematics: {inlineDelimiter: "$", displayDelimiter: "$$", singleDollarInline: true},
};

describe("editor protocol", () => {
  it("uses the coalesced interaction bridge protocol", () => {
    expect(EDITOR_PROTOCOL_VERSION).toBe(10);
  });
  it("accepts a complete versioned request", () => expect(isEditorRequest(request)).toBe(true));
  it("accepts the bounded blur operation", () => {
    expect(isEditorRequest({...request, operation: {type: "blur"}})).toBe(true);
  });
  it("accepts the bounded performance query", () => {
    expect(isEditorRequest({...request, operation: {type: "queryPerformance"}})).toBe(true);
  });
  it("accepts only ordered UTF-16 source ranges", () => {
    expect(isEditorRequest({
      ...request,
      operation: {type: "revealSourceRange", fromUTF16: 12, toUTF16: 19},
    })).toBe(true);
    expect(isEditorRequest({
      ...request,
      operation: {type: "revealSourceRange", fromUTF16: 19, toUTF16: 12},
    })).toBe(false);
  });
  it("keeps presentation CSS separate from user CSS", () => {
    expect(isEditorRequest({
      ...request,
      operation: {type: "setPresentationCSS", value: ":root { --scale: 1.2; }"},
    })).toBe(true);
  });
  it("accepts only finite point-anchored preview coordinates", () => {
    expect(isEditorRequest({
      ...request,
      operation: {type: "showPreviewAt", x: 120.5, y: 80.25},
    })).toBe(true);
    expect(isEditorRequest({
      ...request,
      operation: {type: "showPreviewAt", x: Number.NaN, y: 80.25},
    })).toBe(false);
  });
  it("accepts the Markdown comment formatting command", () => {
    expect(isEditorRequest({
      ...request,
      operation: {type: "command", command: "markdownComment"},
    })).toBe(true);
  });
  it("accepts only the complete immutable editing dialect", () => {
    const initialize = {
      type: "initialize",
      text: "Body",
      mode: "livePreview",
      dialect,
      initialSelection: {anchor: 4, head: 4},
    };
    expect(isEditorRequest({...request, operation: initialize})).toBe(true);
    expect(isEditorRequest({
      ...request,
      operation: {...initialize, initialSelection: {anchor: 5, head: 5}},
    })).toBe(false);
    expect(isEditorRequest({
      ...request,
      operation: {
        ...initialize,
        dialect: {...dialect, footnotes: {...dialect.footnotes, continuationIndentSpaces: 4}},
      },
    })).toBe(false);
  });
  it("rejects stale versions, invalid generations, and unknown operations", () => {
    expect(isEditorRequest({...request, protocolVersion: 1})).toBe(false);
    expect(isEditorRequest({...request, knownGeneration: -1})).toBe(false);
    expect(isEditorRequest({...request, operation: {type: "executeAnything"}})).toBe(false);
    expect(isEditorRequest({...request, operation: {type: "setMode"}})).toBe(false);
    expect(isEditorRequest({...request, operation: {type: "command", command: "inventMeaning"}})).toBe(false);
  });
  it("measures UTF-8 bytes and rejects oversized envelopes", () => {
    expect(encodedByteLength("哲学")).toBeGreaterThan("哲学".length);
    expect(isEditorRequest({...request, operation: {type: "setUserCSS", value: "x".repeat(MAX_INBOUND_BYTES)}})).toBe(false);
  });
  it("returns a non-mutating typed rejection", () => {
    expect(rejected("r", 9, "stale generation")).toEqual({
      requestID: "r", resultingGeneration: 9, sourceChanged: false,
      selections: [], accepted: false, error: "stale generation",
    });
  });
  it("accepts only bounded semantic scroll anchors", () => {
    const anchor = {
      sourceUTF16Offset: 12,
      blockUTF16LowerBound: 10,
      blockUTF16UpperBound: 20,
      relativeBlockPosition: 0.25,
      fallbackFraction: 0.6,
    };
    expect(isEditorRequest({...request, operation: {type: "setScrollAnchor", anchor}})).toBe(true);
    expect(isEditorRequest({
      ...request,
      operation: {type: "setScrollAnchor", anchor: {...anchor, relativeBlockPosition: 1.1}},
    })).toBe(false);
    expect(isEditorRequest({...request, operation: {type: "queryScrollAnchor"}})).toBe(true);
  });

  it("rejects malformed and out-of-bounds recovery selections before dispatch", () => {
    const snapshot = {
      documentID: "document",
      fingerprint: "fingerprint",
      generation: 4,
      ranges: [{anchor: 0, head: 4}],
      source: "Body",
      undoHistoryPreserved: false,
      dirty: true,
    };
    expect(isEditorRequest({
      ...request,
      operation: {type: "restoreRecovery", snapshot},
    })).toBe(true);
    expect(isEditorRequest({
      ...request,
      operation: {
        type: "restoreRecovery",
        snapshot: {...snapshot, ranges: [{anchor: 0, head: 5}]},
      },
    })).toBe(false);
    expect(isEditorRequest({
      ...request,
      operation: {
        type: "restoreRecovery",
        snapshot: {...snapshot, ranges: [{anchor: -1, head: 0}]},
      },
    })).toBe(false);
  });

  it("does not let a recovery snapshot rewind the current generation", () => {
    expect(recoveryGenerationCanReplaceCurrent(3, 4)).toBe(false);
    expect(recoveryGenerationCanReplaceCurrent(4, 4)).toBe(true);
    expect(recoveryGenerationCanReplaceCurrent(5, 4)).toBe(true);
  });
});
