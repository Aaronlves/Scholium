import {describe, expect, it} from "vitest";
import {validatedReaderConfiguration} from "../reader-configuration";

const currentConfiguration = {
  version: 7,
  documentID: "work-001",
  fingerprint: "a".repeat(64),
  loadGeneration: 3,
  selectionEnabled: true,
  imagePreviewsEnabled: false,
  testingEnabled: true,
  presentationCSS: "",
  userCSS: "",
  localization: {languageTag: "en", strings: {}},
  linkPreviews: [],
};

describe("reader configuration", () => {
  it("accepts the current bounded native configuration", () => {
    expect(validatedReaderConfiguration(currentConfiguration)).toEqual(currentConfiguration);
    expect(validatedReaderConfiguration({...currentConfiguration, imagePreviewsEnabled: true})?.imagePreviewsEnabled).toBe(true);
    expect(validatedReaderConfiguration({...currentConfiguration, imagePreviewsEnabled: undefined})).toBeNull();
    expect(validatedReaderConfiguration({...currentConfiguration, imagePreviewsEnabled: "true"})).toBeNull();
  });

  it("rejects unknown versions and unbounded identities", () => {
    expect(validatedReaderConfiguration({...currentConfiguration, version: 5})).toBeNull();
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

  it("requires the same bounded interface-language payload used by Edit", () => {
    for (const localization of [{strings: {}}, {languageTag: "zh-Hans", strings: []},
      {languageTag: "<script>", strings: {}}]) {
      expect(validatedReaderConfiguration({...currentConfiguration, localization})).toBeNull();
    }
    const result = validatedReaderConfiguration({...currentConfiguration, localization: {
      languageTag: "zh_CN", strings: {
        "Note title": "笔记标题",
        "Embedded note {title}": "错误模板 {other}",
        "private research text": "must not become an interface key",
      },
    }});
    expect(result?.localization).toEqual({languageTag: "zh-Hans", strings: {"Note title": "笔记标题"}});
  });
});
