import {describe, expect, it} from "vitest";
import {validatedReaderConfiguration} from "../reader-configuration";

const currentConfiguration = {
  version: 2,
  documentID: "work-001",
  fingerprint: "a".repeat(64),
  loadGeneration: 3,
  selectionEnabled: true,
  testingEnabled: true,
  presentationCSS: "",
  userCSS: "",
  localization: {strings: {}},
  linkPreviews: [],
  documentAttachments: [],
};

describe("reader configuration", () => {
  it("accepts the current bounded native configuration", () => {
    expect(validatedReaderConfiguration(currentConfiguration)).toEqual(currentConfiguration);
  });

  it("rejects unknown versions and unbounded identities", () => {
    expect(validatedReaderConfiguration({...currentConfiguration, version: 3})).toBeNull();
    expect(validatedReaderConfiguration({
      ...currentConfiguration,
      documentID: "x".repeat(4_097),
    })).toBeNull();
    expect(validatedReaderConfiguration({
      ...currentConfiguration,
      linkPreviews: Array.from({length: 129}, () => ({})),
    })).toBeNull();
    expect(validatedReaderConfiguration({
      ...currentConfiguration,
      documentAttachments: Array.from({length: 101}, () => ({})),
    })).toBeNull();
  });
});
