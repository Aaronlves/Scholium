import {describe, expect, it} from "vitest";
import {validatedReaderConfiguration} from "../reader-configuration";

const currentConfiguration = {
  version: 6,
  documentID: "work-001",
  fingerprint: "a".repeat(64),
  loadGeneration: 3,
  selectionEnabled: true,
  testingEnabled: true,
  presentationCSS: "",
  userCSS: "",
  localization: {strings: {}},
  linkPreviews: [],
};

describe("reader configuration", () => {
  it("accepts the current bounded native configuration", () => {
    expect(validatedReaderConfiguration(currentConfiguration)).toEqual(currentConfiguration);
  });

  it("rejects unknown versions and unbounded identities", () => {
    expect(validatedReaderConfiguration({...currentConfiguration, version: 5})).toBeNull();
    expect(validatedReaderConfiguration({...currentConfiguration, chatReplyPreviousHTML: '<p>old</p>'})).toBeNull();
    expect(validatedReaderConfiguration({...currentConfiguration, chatReply: true, chatReplyPreviousHTML: 'x'.repeat(262_145)})).toBeNull();
    expect(validatedReaderConfiguration({...currentConfiguration, chatReply: true, chatReplyPreviousHTML: '<p>old</p>'})).not.toBeNull();
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
});
