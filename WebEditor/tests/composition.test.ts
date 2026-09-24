import {afterEach, describe, expect, it, vi} from "vitest";
import {CompositionRequestGate, compositionRequestPolicy} from "../composition";

type Request = {id: string; expiresAt: number; generation: number; identity: string};
type Result = {accepted: boolean; id: string};

describe("CompositionRequestGate synthetic bridge policy", () => {
  afterEach(() => vi.useRealTimers());
  it("gates every source, selection, mode, and projection mutation", () => {
    expect(compositionRequestPolicy("initialize")).toBe("reject");
    for (const operation of [
      "queryText", "querySelection", "captureRecovery", "markClean",
      "setMode", "goToLine", "restoreRecovery", "acknowledgeCommittedSnapshot", "command",
      "setPresentationCSS", "setUserCSS", "setLinkPreviews",
      "setDocumentTitle", "revealSourceRange", "suspendForDetachment",
    ] as const) {
      expect(compositionRequestPolicy(operation)).toBe("defer");
    }
    expect(compositionRequestPolicy("queryContext")).toBe("allow");
  });
  it("releases queued requests once and in order after composition", async () => {
    const gate = new CompositionRequestGate<Request, Result>(request => ({accepted: false, id: request.id}));
    gate.begin();
    const first = gate.enqueue({id: "format", generation: 4, identity: "A", expiresAt: Date.now() + 8_000});
    const second = gate.enqueue({id: "mode", generation: 4, identity: "A", expiresAt: Date.now() + 8_000});

    const pending = gate.finish();
    expect(gate.active).toBe(false);
    expect(pending.map((item) => item.request.id)).toEqual(["format", "mode"]);
    for (const item of pending) item.resolve({accepted: true, id: item.request.id});

    await expect(first).resolves.toEqual({accepted: true, id: "format"});
    await expect(second).resolves.toEqual({accepted: true, id: "mode"});
    expect(gate.finish()).toEqual([]);
  });

  it("lets the dispatcher reject a request after composition changes generation", async () => {
    const gate = new CompositionRequestGate<Request, Result>(request => ({accepted: false, id: request.id}));
    gate.begin();
    const result = gate.enqueue({id: "format", generation: 8, identity: "A", expiresAt: Date.now() + 8_000});
    const currentGeneration = 9;
    for (const item of gate.finish()) {
      item.resolve({accepted: item.request.generation === currentGeneration, id: item.request.id});
    }
    await expect(result).resolves.toEqual({accepted: false, id: "format"});
  });

  it("rejects every queued request when the editor identity changes", async () => {
    const gate = new CompositionRequestGate<Request, Result>(request => ({accepted: false, id: request.id}));
    gate.begin();
    const result = gate.enqueue({id: "mode", generation: 2, identity: "A", expiresAt: Date.now() + 8_000});
    gate.rejectAll((request) => ({accepted: false, id: request.id}));
    await expect(result).resolves.toEqual({accepted: false, id: "mode"});
    expect(gate.active).toBe(false);
  });

  it("releases a request after a cancelled composition when identity and generation stay unchanged", async () => {
    const gate = new CompositionRequestGate<Request, Result>(request => ({accepted: false, id: request.id}));
    gate.begin();
    const request = {id: "source-mode", generation: 3, identity: "A", expiresAt: Date.now() + 8_000};
    const result = gate.enqueue(request);
    for (const item of gate.finish()) {
      item.resolve({
        accepted: item.request.generation === 3 && item.request.identity === "A",
        id: item.request.id,
      });
    }
    await expect(result).resolves.toEqual({accepted: true, id: "source-mode"});
  });
  it("waits for both body and title and ignores an old compositionend task", async () => {
    const gate = new CompositionRequestGate<Request, Result>(request => ({accepted: false, id: request.id}));
    gate.begin("editor");
    gate.begin("title");
    const oldTitle = gate.revision("title");
    const result = gate.enqueue({id: "mode", generation: 1, identity: "A", expiresAt: Date.now() + 8_000});
    gate.begin("title");
    expect(gate.finish("title", oldTitle)).toEqual([]);
    expect(gate.finish("editor")).toEqual([]);
    expect(gate.active).toBe(true);
    for (const pending of gate.finish("title")) pending.resolve({accepted: true, id: pending.request.id});
    await expect(result).resolves.toEqual({accepted: true, id: "mode"});
  });

  it("expires a queued command even when cancelled composition leaves generation unchanged", async () => {
    vi.useFakeTimers();
    const gate = new CompositionRequestGate<Request, Result>(request => ({accepted: false, id: request.id}));
    gate.begin();
    const result = gate.enqueue({id: "command", generation: 1, identity: "A", expiresAt: Date.now() + 8_000});
    vi.advanceTimersByTime(8_000);
    await expect(result).resolves.toEqual({accepted: false, id: "command"});
    expect(gate.finish()).toEqual([]);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("rechecks expiration when a timer has not run before composition release", async () => {
    vi.useFakeTimers();
    const gate = new CompositionRequestGate<Request, Result>(request => ({accepted: false, id: request.id}));
    gate.begin("title");
    const result = gate.enqueue({id: "command", generation: 1, identity: "A", expiresAt: Date.now() + 10});
    vi.setSystemTime(Date.now() + 11);
    expect(gate.finish("title")).toEqual([]);
    await expect(result).resolves.toEqual({accepted: false, id: "command"});
    expect(vi.getTimerCount()).toBe(0);
  });

});
