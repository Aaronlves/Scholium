import {describe, expect, it} from "vitest";
import {
  EDITOR_PROTOCOL_VERSION, MAX_INBOUND_BYTES, MAX_SOURCE_ENVELOPE_BYTES, MAX_RECOVERY_ENVELOPE_BYTES,
  MAX_RECOVERY_HISTORY_BYTES, MAX_RECOVERY_ACTION_LABEL_BYTES, MAX_PRESENTATION_ENVELOPE_BYTES, encodedByteLength, isEditorRequest,
  admitPresentationSources, generationCanExecuteEditorRequest, rejected,
} from "../protocol";

const request = {
  protocolVersion: EDITOR_PROTOCOL_VERSION,
  requestID: "request",
  expiresAt: Date.now() + 8_000,
  sessionID: "session",
  documentID: "document",
  startingFingerprint: "fingerprint",
  knownGeneration: 4,
  operation: {type: "queryText" as const},
};

const presentation = {
  documentTitle: "", presentationCSS: "", userCSS: "", linkPreviews: [], linkPreviewGeneration: 0,
  imageResources: {}, imageResourceGeneration: 0, writingContinuationEnabled: false,
  writingContinuationContextKey: "", writingIndexContextKey: "",
};

const dialect = {
  version: 6,
  callouts: [{identifier: "state", label: "Statement", meaning: "Claim"}],
  linkAnnotation: {
    openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\",
    allowsMultiline: true, allowsNesting: false,
  },
  footnotes: {
    namedReferenceOpening: "[^", namedReferenceClosing: "]", definitionSeparator: ":",
    inlineOpening: "^[", continuationIndentSpaces: 2, allowsTabContinuation: true,
    caseSensitiveIdentifiers: true, ordinalByFirstReference: true,
  },
  mathematics: {inlineDelimiter: "$", displayDelimiter: "$$", singleDollarInline: true},
};

const initializeRecovery = (recovery: Record<string, unknown>) => ({...request, knownGeneration: 0,
  operation: {type: "initialize", text: recovery.source, mode: "source", dialect, presentation, recovery},
});

describe("editor protocol", () => {
  it("transports escaped recovery history independently of ordinary message limits", () => {
    const stateJSON = JSON.stringify({doc: "\u0000\"\\".repeat(300_000)});
    expect(new TextEncoder().encode(stateJSON).byteLength).toBeGreaterThan(MAX_INBOUND_BYTES);
    const envelope = initializeRecovery({
      documentID: "document", fingerprint: "fingerprint", generation: 4,
      ranges: [{anchor: 0, head: 0}], source: "", stateJSON, undoHistoryPreserved: true, dirty: true,
    });
    expect(encodedByteLength(envelope)).toBeLessThan(MAX_SOURCE_ENVELOPE_BYTES + MAX_PRESENTATION_ENVELOPE_BYTES + MAX_RECOVERY_ENVELOPE_BYTES);
    expect(MAX_RECOVERY_ENVELOPE_BYTES).toBeGreaterThan(MAX_SOURCE_ENVELOPE_BYTES + MAX_RECOVERY_HISTORY_BYTES * 2);
    expect(isEditorRequest(envelope)).toBe(true);
  });

  it("admits only bounded UTF-8 recovery action labels", () => {
    const snapshot = {
      documentID: "document", fingerprint: "fingerprint", generation: 4,
      ranges: [{anchor: 0, head: 0}], source: "", undoHistoryPreserved: true, dirty: true,
    };
    const admitted = (labels: Record<string, unknown>) => isEditorRequest(initializeRecovery({...snapshot, ...labels}));
    expect(admitted({})).toBe(true);
    expect(admitted({undoLabel: "Paste", redoLabel: "Citation Operation"})).toBe(true);
    const bounded = "😀".repeat(MAX_RECOVERY_ACTION_LABEL_BYTES / 4);
    expect(admitted({undoLabel: bounded, redoLabel: bounded})).toBe(true);
    for (const field of ["undoLabel", "redoLabel"]) {
      for (const invalid of [null, 1, {}, "a".repeat(MAX_RECOVERY_ACTION_LABEL_BYTES + 1), bounded + "x"]) {
        expect(admitted({[field]: invalid})).toBe(false);
      }
    }
  });

  it("admits the complete existing image budget alongside independently bounded initial presentation", () => {
    const data = "A".repeat(4 * Math.ceil(10 * 1_024 * 1_024 / 3) - 2) + "==";
    const imageResources = Object.fromEntries(Array.from({length: 8}, (_, index) => [`${index}.png`, `data:image/png;base64,${data}`]));
    const value = {...presentation, imageResources, presentationCSS: "a".repeat(1_000_000), userCSS: "b".repeat(1_000_000)};
    const operation = {type: "initialize", text: "Body", mode: "livePreview", dialect, presentation: value};
    const envelope = {...request, operation};
    expect(encodedByteLength(envelope)).toBeGreaterThan(MAX_SOURCE_ENVELOPE_BYTES);
    expect(encodedByteLength(envelope)).toBeLessThan(MAX_SOURCE_ENVELOPE_BYTES + MAX_PRESENTATION_ENVELOPE_BYTES);
    expect(isEditorRequest(envelope)).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "setPresentation", value}})).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "setPresentation", value: {...value, userCSS: "b".repeat(1_000_001)}}})).toBe(false);
  });

  it("admits latest appearance while retaining only already applied source-bound catalogs", () => {
    const previous = {...presentation, documentTitle: "Previous title", linkPreviews: [{from: 12, to: 22}],
      linkPreviewGeneration: 5, imageResources: {"current.png": "current"}, imageResourceGeneration: 5};
    const oldRequest = {...presentation, documentTitle: "Latest title", presentationCSS: "latest CSS",
      linkPreviews: [{from: 0, to: 10}], linkPreviewGeneration: 4,
      imageResources: {"old.png": "old"}, imageResourceGeneration: 4};
    const admitted = admitPresentationSources(oldRequest, 5, previous);
    expect(admitted.documentTitle).toBe("Latest title");
    expect(admitted.presentationCSS).toBe("latest CSS");
    expect(admitted.linkPreviews).toBe(previous.linkPreviews);
    expect(admitted.imageResources).toBe(previous.imageResources);
    expect(admitPresentationSources(oldRequest, 4, previous).linkPreviews).toBe(oldRequest.linkPreviews);
    expect(admitPresentationSources(oldRequest, 5, null).linkPreviews).toEqual([]);
  });

  it("keeps measurement generation-bound and releases presentation with a bounded focus target", () => {
    expect(isEditorRequest({...request, operation: {type: "completePreparation"}})).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "completePreparation", fraction: 0}})).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "completePreparation", fraction: 1.1}})).toBe(false);
    expect(generationCanExecuteEditorRequest("completePreparation", 3, 4)).toBe(false);
    expect(isEditorRequest({...request, operation: {type: "releasePreparation", focusTarget: "editor"}})).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "releasePreparation", focusTarget: "elsewhere"}})).toBe(false);
    expect(generationCanExecuteEditorRequest("releasePreparation", 3, 4)).toBe(false);
  });

  it("uses the atomic initialization recovery protocol and rejects its predecessor", () => {
    expect(EDITOR_PROTOCOL_VERSION).toBe(53);
    expect(isEditorRequest({...request, protocolVersion: 52})).toBe(false);
  });
  it("admits bounded managed citation snapshots without weakening standalone initialization", () => {
    const citationSnapshot = {noteID: "11111111-1111-1111-1111-111111111111", vaultID: "22222222-2222-2222-2222-222222222222", status: "absent"};
    const operation = {type: "initialize", text: "Argument", mode: "source", dialect, citationSnapshot, presentation};
    expect(isEditorRequest({...request, operation})).toBe(true);
    expect(isEditorRequest({...request, operation: {...operation, citationSnapshot: {...citationSnapshot, status: "available"}}})).toBe(false);
    expect(isEditorRequest({...request, operation: {...operation, citationSnapshot: {...citationSnapshot, data: {schemaVersion: 2, fields: []}}}})).toBe(false);
    const data = {schemaVersion: 1, fields: [], documentData: "opaque"};
    const committedCitationSnapshot = {...citationSnapshot, status: "available", data,
      sourceFingerprint: {sha256: "a".repeat(64), byteCount: 8}};
    // Recovered draft bytes may differ from the saved disk baseline.
    expect(isEditorRequest({...request, operation: {...operation, text: "A longer recovered draft", citationSnapshot: committedCitationSnapshot}})).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "acknowledgeCommittedSnapshot", expectedText: "Argument", committedText: "Argument",
      committedFingerprint: "a".repeat(64), expectedCitationData: data, committedCitationSnapshot}})).toBe(true);
  });
  it("accepts a complete versioned request", () => expect(isEditorRequest(request)).toBe(true));
  it("admits only closed citation operations with bounded completion coordinates", () => {
    const reference = {actionID: "insertCitation", requestID: "8E1AD940-840E-49D1-A675-2C6D1079EAA0",
      query: "Author e\u0301", fromUTF16: 10, toUTF16: 20, caretUTF16Offset: 20,
      editorCaretUTF16Offset: 19, interactionRevision: 7};
    const begin = {type: "beginCitation", transactionID: "citation_fixture", command: "addEditCitation", reference};
    expect(isEditorRequest({...request, operation: begin})).toBe(true);
    for (const invalid of [
      {...begin, command: "unlinkAll"}, {...begin, transactionID: ""},
      {...begin, transactionID: "bad\nidentifier"}, {...begin, unexpected: true},
      {...begin, reference: {...reference, toUTF16: 19}},
      {...begin, reference: {...reference, interactionRevision: true}},
      {...begin, reference: {...reference, editorCaretUTF16Offset: -1}},
      {...begin, reference: {...reference, unexpected: true}},
    ]) expect(isEditorRequest({...request, operation: invalid})).toBe(false);
    const callback = {type: "citationCallback", transactionID: "citation_fixture", value: {type: "getFields"}};
    expect(isEditorRequest({...request, operation: callback})).toBe(true);
    expect(isEditorRequest({...request, operation: {...callback, value: {type: "getFields", privateData: true}}})).toBe(false);
    for (const type of ["finishCitation", "cancelCitation"]) {
      expect(isEditorRequest({...request, operation: {type, transactionID: "citation_fixture"}})).toBe(true);
      expect(isEditorRequest({...request, operation: {type, transactionID: "citation_fixture", text: "replacement"}})).toBe(false);
    }
  });
  it("binds Select All to the current editor generation", () => {
    expect(isEditorRequest({...request, operation: {type: "selectAll"}})).toBe(true);
    expect(generationCanExecuteEditorRequest("selectAll", 4, 4)).toBe(true);
    expect(generationCanExecuteEditorRequest("selectAll", 3, 4)).toBe(false);
  });
  it("bounds native clipboard text and the captured selection without relaxing generation", () => {
    const operation = {type: "pasteClipboard", plainText: "\uFEFF中文😀e\u0301\r\n", selections: [{anchor: 2, head: 7}]};
    expect(isEditorRequest({...request, operation})).toBe(true);
    expect(isEditorRequest({...request, operation: {...operation, plainText: "x".repeat(8_000_000)}})).toBe(true);
    expect(isEditorRequest({...request, operation: {...operation, plainText: "x".repeat(8_000_001)}})).toBe(false);
    for (const selections of [[], [{anchor: -1, head: 2}], [{anchor: 2.5, head: 3}], [{anchor: 0, head: 8_000_001}], Array(129).fill({anchor: 0, head: 0})]) {
      expect(isEditorRequest({...request, operation: {...operation, selections}})).toBe(false);
    }
    expect(isEditorRequest({...request, operation: {...operation, plainText: 4}})).toBe(false);
    expect(generationCanExecuteEditorRequest("pasteClipboard", 4, 4)).toBe(true);
    expect(generationCanExecuteEditorRequest("pasteClipboard", 3, 4)).toBe(false);
    expect(generationCanExecuteEditorRequest("pasteClipboard", 5, 4)).toBe(false);
  });
  it("rejects retired title positioning while retaining blur", () => {
    expect(isEditorRequest({...request, operation: {type: "positionDocumentTitle"}})).toBe(false);
    expect(isEditorRequest({...request, operation: {type: "blur"}})).toBe(true);
  });
  it("accepts the bounded title-focus operation", () => {
    expect(isEditorRequest({...request, operation: {type: "focusTitle"}})).toBe(true);
  });
  it("bounds the independent writing index context", () => {
    expect(isEditorRequest({...request, operation: {type: "setPresentation", value: {...presentation, writingIndexContextKey: "catalog-2"}}})).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "setPresentation", value: {...presentation, writingIndexContextKey: "x".repeat(257)}}})).toBe(false);
  });
  it("accepts the bounded performance query", () => {
    expect(isEditorRequest({...request, operation: {type: "queryPerformance"}})).toBe(true);
  });
  it("accepts only a bounded document title projection", () => {
    expect(isEditorRequest({
      ...request,
      operation: {type: "setPresentation", value: {...presentation, documentTitle: "Reasons and Emotion"}},
    })).toBe(true);
    expect(isEditorRequest({
      ...request,
      operation: {type: "setPresentation", value: {...presentation, documentTitle: "x".repeat(1_025)}},
    })).toBe(false);
    expect(generationCanExecuteEditorRequest("setPresentation", 3, 4)).toBe(true);
  });
  it("accepts only bounded literal document-find requests", () => {
    const value = {
      query: "value",
      replacement: "replacement",
      caseSensitive: false,
      wholeWord: true,
      action: "replaceAll",
    };
    expect(isEditorRequest({
      ...request,
      operation: {type: "documentFind", value},
    })).toBe(true);
    expect(isEditorRequest({
      ...request,
      operation: {type: "documentFind", value: {...value, action: "regex"}},
    })).toBe(false);
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
      operation: {type: "setPresentation", value: {...presentation, presentationCSS: ":root { --scale: 1.2; }"}},
    })).toBe(true);
  });
  it("selection presentation carries no writable source or external range and binds the current generation", () => {
    expect(isEditorRequest({...request, operation: {type: "showSelectionActions"}})).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "showSelectionActions", source: "replace this"}})).toBe(false);
    expect(generationCanExecuteEditorRequest("showSelectionActions", 4, 4)).toBe(true);
    expect(generationCanExecuteEditorRequest("showSelectionActions", 3, 4)).toBe(false);
  });
  it("accepts the Markdown comment formatting command", () => {
    expect(isEditorRequest({
      ...request,
      operation: {type: "command", command: "markdownComment"},
    })).toBe(true);
  });
  it("accepts both source-distinct footnote insertion commands", () => {
    expect(isEditorRequest({
      ...request,
      operation: {type: "command", command: "insertFootnote"},
    })).toBe(true);
    expect(isEditorRequest({
      ...request,
      operation: {type: "command", command: "insertInlineFootnote"},
    })).toBe(true);
  });
  it("accepts only the complete immutable editing dialect", () => {
    const initialize = {
      type: "initialize",
      text: "Body",
      mode: "livePreview",
      dialect,
      presentation,
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
    expect(isEditorRequest({
      ...request,
      operation: {
        ...initialize,
        dialect: {
          ...dialect,
          callouts: [{identifier: "state", aliases: ["theorem"], label: "Statement", meaning: "Claim"}],
        },
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
    expect(isEditorRequest({...request, operation: {type: "setPresentation", value: {...presentation, userCSS: "x".repeat(MAX_INBOUND_BYTES)}}})).toBe(false);
  });
  it("returns a non-mutating typed rejection", () => {
    expect(rejected("r", 9, "stale generation", 17)).toEqual({
      requestID: "r", resultingGeneration: 9, interactionRevision: 17, sourceChanged: false,
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
      focusTarget: "title",
    };
    expect(isEditorRequest(initializeRecovery(snapshot))).toBe(true);
    expect(isEditorRequest(initializeRecovery({...snapshot, ranges: [{anchor: 0, head: 5}]}))).toBe(false);
    expect(isEditorRequest(initializeRecovery({...snapshot, ranges: [{anchor: -1, head: 0}]}))).toBe(false);
    expect(isEditorRequest(initializeRecovery({...snapshot, focusTarget: "sidebar"}))).toBe(false);
    for (const generation of [-1, Number.NaN, Number.MAX_SAFE_INTEGER + 1]) {
      expect(isEditorRequest(initializeRecovery({...snapshot, generation}))).toBe(false);
    }
  });

  it("binds initialization recovery to exact bytes, outer identity and citation ownership", () => {
    const citationSnapshot = {noteID: "11111111-1111-1111-1111-111111111111", vaultID: "22222222-2222-2222-2222-222222222222",
      status: "available", sourceFingerprint: {sha256: "a".repeat(64), byteCount: 4}, data: {schemaVersion: 1, fields: []}};
    const recovery = {documentID: "document", fingerprint: "a".repeat(64), generation: 7,
      source: "\uFEFFDraft Cafe\u0301\r\n尾", ranges: [{anchor: 1, head: 4}, {anchor: 9, head: 11}],
      undoHistoryPreserved: false, dirty: true, citationSnapshot, citationData: {schemaVersion: 1, fields: [], documentData: "draft"}};
    const envelope = {...initializeRecovery(recovery), startingFingerprint: recovery.fingerprint};
    const operation = {...envelope.operation, citationSnapshot};
    // The saved fingerprint/byte count names the disk baseline, not draft bytes.
    expect(isEditorRequest({...envelope, operation})).toBe(true);
    for (const changed of [
      {...recovery, documentID: "another"}, {...recovery, fingerprint: "b".repeat(64)},
      {...recovery, source: recovery.source.replace("e\u0301", "é")},
      {...recovery, citationSnapshot: {...citationSnapshot, noteID: "33333333-3333-3333-3333-333333333333"}},
      {...recovery, citationSnapshot: {...citationSnapshot, vaultID: "33333333-3333-3333-3333-333333333333"}},
      {...recovery, citationSnapshot: undefined, citationData: undefined},
    ]) {
      expect(isEditorRequest({...envelope, operation: {...operation, recovery: changed}})).toBe(false);
    }
    expect(isEditorRequest({...envelope, operation: {...operation, citationSnapshot: undefined}})).toBe(false);
  });

  it("authorizes mutations only at their exact document generation", () => {
    expect(generationCanExecuteEditorRequest("command", 4, 4)).toBe(true);
    expect(generationCanExecuteEditorRequest("command", 4, 5)).toBe(false);
    expect(generationCanExecuteEditorRequest("setMode", 4, 5)).toBe(false);
    expect(generationCanExecuteEditorRequest("documentFind", 4, 5)).toBe(false);
  });

  it("allows bounded snapshot reads to observe a newer generation", () => {
    expect(generationCanExecuteEditorRequest("queryText", 4, 5)).toBe(true);
    expect(generationCanExecuteEditorRequest("captureRecovery", 4, 5)).toBe(true);
    expect(generationCanExecuteEditorRequest("acknowledgeCommittedSnapshot", 4, 5)).toBe(true);
    expect(generationCanExecuteEditorRequest("queryText", 6, 5)).toBe(false);
  });
});

 it("admits only bounded exact-passage replacements with the current generation", () => {
   const operation = {type: "replacePassage", expectedText: "Original", fromUTF16: 0, toUTF16: 8, replacement: "Proposal", preserveSelection: false};
   expect(isEditorRequest({...request, operation})).toBe(true);
   expect(isEditorRequest({...request, operation: {...operation, fromUTF16: 8, toUTF16: 8, preserveSelection: true}})).toBe(true);
   expect(isEditorRequest({...request, operation: {...operation, preserveSelection: undefined}})).toBe(false);
   expect(isEditorRequest({...request, operation: {...operation, preserveSelection: "true"}})).toBe(false);
   expect(isEditorRequest({...request, operation: {...operation, replacement: ""}})).toBe(false);
   expect(isEditorRequest({...request, operation: {...operation, fromUTF16: -1}})).toBe(false);
   expect(generationCanExecuteEditorRequest("replacePassage", 3, 4)).toBe(false);
 });


describe("guarded reference insertion", () => {
  it("requires a bounded literal target, collapsed selection and receipt generation", () => {
    const operation = {type: "insertReference", target: "Concept", generation: 4, selection: {anchor: 5, head: 5}};
    expect(isEditorRequest({...request, operation})).toBe(true);
    for (const patch of [{generation: -1}, {generation: 1.2}, {target: "bad]]text"}, {target: ""}, {selection: {anchor: 5, head: 6}}]) {
      expect(isEditorRequest({...request, operation: {...operation, ...patch}})).toBe(false);
    }
    expect(generationCanExecuteEditorRequest("insertReference", 3, 4)).toBe(false);
  });
  it("requires a finite deadline and bounded suspension token", () => {
    for (const expiresAt of [undefined, 0, -1, Infinity, 1.5]) {
      expect(isEditorRequest({...request, expiresAt})).toBe(false);
    }
    for (const type of ["suspendForDetachment", "resumeAfterDetachment"]) {
      expect(isEditorRequest({...request, operation: {type, suspensionID: "lease"}})).toBe(true);
      expect(isEditorRequest({...request, operation: {type, suspensionID: ""}})).toBe(false);
    }
  });
  it("freezes and resumes current input without admitting future generations or stale content commands", () => {
    for (const type of ["suspendForDetachment", "resumeAfterDetachment"]) {
      expect(generationCanExecuteEditorRequest(type, 3, 4)).toBe(true);
      expect(generationCanExecuteEditorRequest(type, 5, 4)).toBe(false);
    }
    expect(generationCanExecuteEditorRequest("command", 3, 4)).toBe(false);
  });
  it("admits escaped double-source acknowledgements while bounding each exact source", () => {
    const source = "\u0001".repeat(700_000);
    expect(isEditorRequest({...request, operation: {type: "acknowledgeCommittedSnapshot",
      expectedText: source, committedText: source, committedFingerprint: "next"}})).toBe(true);
    expect(isEditorRequest({...request, operation: {type: "acknowledgeCommittedSnapshot",
      expectedText: "a".repeat(8_000_001), committedText: "", committedFingerprint: "next"}})).toBe(false);
  });

});
