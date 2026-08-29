import {describe, expect, it} from "vitest";
import {
  validatedReadCommentAnchors,
  validatedReaderConfiguration,
} from "../reader-configuration";

const currentConfiguration = {
  version: 1,
  documentID: "work-001",
  fingerprint: "a".repeat(64),
  loadGeneration: 3,
  commentEnabled: true,
  selectionEnabled: true,
  testingEnabled: true,
  presentationCSS: "",
  userCSS: "",
  localization: {strings: {Comment: "Comment"}},
  linkPreviews: [],
  commentAnchors: [],
  vectorSymbols: {neutral: "data:image/svg+xml;base64,AA=="},
};

describe("reader configuration", () => {
  it("accepts the current bounded native configuration", () => {
    expect(validatedReaderConfiguration(currentConfiguration)).toEqual(currentConfiguration);
  });

  it("rejects unknown versions and unbounded identities", () => {
    expect(validatedReaderConfiguration({...currentConfiguration, version: 2})).toBeNull();
    expect(validatedReaderConfiguration({
      ...currentConfiguration,
      documentID: "x".repeat(4_097),
    })).toBeNull();
    expect(validatedReaderConfiguration({
      ...currentConfiguration,
      linkPreviews: Array.from({length: 129}, () => ({})),
    })).toBeNull();
  });

  it("accepts bounded comment anchors and rejects ambiguous identities or ranges", () => {
    const anchor = {
      id: "discussion-12-14",
      discussionID: "11111111-1111-1111-1111-111111111111",
      statementID: "22222222-2222-2222-2222-222222222222",
      startLine: 12,
      endLine: 14,
      commentCount: 2,
    };
    expect(validatedReadCommentAnchors([anchor])).toEqual([anchor]);
    expect(validatedReadCommentAnchors([anchor, anchor])).toBeNull();
    expect(validatedReadCommentAnchors([{...anchor, startLine: 0}])).toBeNull();
    expect(validatedReadCommentAnchors([{...anchor, endLine: 11}])).toBeNull();
    expect(validatedReadCommentAnchors([{...anchor, commentCount: 0}])).toBeNull();
    expect(validatedReadCommentAnchors([{...anchor, id: "ambiguous token"}])).toBeNull();
    expect(validatedReadCommentAnchors([{...anchor, statementID: "not-a-uuid"}])).toBeNull();
  });
});
