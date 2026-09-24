import {describe, expect, it} from "vitest";
import {CommittedSnapshotReceipt} from "../committed-snapshot-receipt";
import type {EditorOperation} from "../protocol";

const identity = {sessionID: "session", documentID: "document", startingFingerprint: "old"};
const commit = {type: "acknowledgeCommittedSnapshot" as const,
  expectedText: "\uFEFFa\r\nb\n", committedText: "\uFEFFa\r\nb\n", committedFingerprint: "new"};
const request = {...identity, operation: commit};
const current = {...identity, startingFingerprint: "new"};

describe("completed commit acknowledgement receipt", () => {
  it("allows an exact old-base retry after new input without reading or changing the live buffer", () => {
    const receipt = new CommittedSnapshotReceipt();
    receipt.remember(identity, commit);
    const live = {source: commit.committedText + "new input", dirty: true, generation: 7};
    expect(receipt.replay(request, current, live.source, live.dirty)).toEqual({
      text: live.source, commitSuperseded: true,
    });
    // Undo can return to byte-identical content while the current session still
    // owns unsaved editing history; a replay must not clear that dirty state.
    expect(receipt.replay(request, current, commit.committedText, true)).toEqual({
      text: commit.committedText, commitSuperseded: true,
    });
    expect(receipt.replay(request, current, commit.committedText, false)).toEqual({
      text: commit.committedText, commitSuperseded: false,
    });
  });

  it("rejects every wrong identity, exact source, target commit, or operation", () => {
    const receipt = new CommittedSnapshotReceipt();
    receipt.remember(identity, commit);
    for (const attempted of [
      {...request, sessionID: "other"}, {...request, documentID: "other"},
      {...request, startingFingerprint: "other"},
      {...request, operation: {...commit, expectedText: "\uFEFFa\nb\n"}},
      {...request, operation: {...commit, committedText: "different"}},
      {...request, operation: {...commit, committedFingerprint: "later"}},
      {...request, operation: {type: "queryText"} as EditorOperation},
    ]) expect(receipt.canReplay(attempted, current)).toBe(false);
    expect(receipt.canReplay(request, {...current, sessionID: "reattached"})).toBe(false);
    expect(receipt.canReplay(request, {...current, documentID: "other"})).toBe(false);
    expect(receipt.canReplay(request, {...current, startingFingerprint: "later"})).toBe(false);
  });

  it("retains only the most recent commit and clears at document attachment", () => {
    const receipt = new CommittedSnapshotReceipt();
    expect(receipt.canReplay(request, current)).toBe(false);
    receipt.remember(identity, commit);
    const next = {...commit, expectedText: "next", committedText: "next", committedFingerprint: "later"};
    receipt.remember(current, next);
    expect(receipt.canReplay(request, current)).toBe(false);
    expect(receipt.canReplay({...current, operation: next}, {...current, startingFingerprint: "later"})).toBe(true);
    receipt.clear();
    expect(receipt.canReplay({...current, operation: next}, {...current, startingFingerprint: "later"})).toBe(false);
  });

  it("leaves equal-base byte-identical saves on the ordinary reconciliation path", () => {
    const receipt = new CommittedSnapshotReceipt();
    const unchanged = {...commit, committedFingerprint: identity.startingFingerprint};
    receipt.remember(identity, unchanged);
    expect(receipt.canReplay({...identity, operation: unchanged}, identity)).toBe(false);
  });
});
