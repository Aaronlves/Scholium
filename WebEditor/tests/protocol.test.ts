import {describe, expect, it} from "vitest";
import {
  EDITOR_PROTOCOL_VERSION, MAX_INBOUND_BYTES, encodedByteLength, isEditorRequest, rejected,
} from "../protocol";

const request = {
  protocolVersion: EDITOR_PROTOCOL_VERSION,
  requestID: "request",
  sessionID: "session",
  documentID: "document",
  startingFingerprint: "fingerprint",
  expectedGeneration: 4,
  operation: {type: "queryText" as const},
};

describe("editor protocol", () => {
  it("accepts a complete versioned request", () => expect(isEditorRequest(request)).toBe(true));
  it("rejects stale versions, invalid generations, and unknown operations", () => {
    expect(isEditorRequest({...request, protocolVersion: 1})).toBe(false);
    expect(isEditorRequest({...request, expectedGeneration: -1})).toBe(false);
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
});
