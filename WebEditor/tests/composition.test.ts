import {describe, expect, it} from "vitest";
import {CompositionRequestGate, compositionRequestPolicy} from "../composition";

type Request = {id: string; generation: number; identity: string};
type Result = {accepted: boolean; id: string};

describe("CompositionRequestGate synthetic bridge policy", () => {
  it("gates every source, selection, mode, and projection mutation", () => {
    expect(compositionRequestPolicy("initialize")).toBe("reject");
    for (const operation of [
      "setMode", "goToLine", "restoreRecovery", "synchronizeCommittedText", "command",
      "setPresentationCSS", "setUserCSS", "setLinkPreviews",
    ]) {
      expect(compositionRequestPolicy(operation)).toBe("defer");
    }
    expect(compositionRequestPolicy("queryContext")).toBe("allow");
    expect(compositionRequestPolicy("markClean")).toBe("allow");
  });
  it("releases queued requests once and in order after composition", async () => {
    const gate = new CompositionRequestGate<Request, Result>();
    gate.begin();
    const first = gate.enqueue({id: "format", generation: 4, identity: "A"});
    const second = gate.enqueue({id: "mode", generation: 4, identity: "A"});

    const pending = gate.finish();
    expect(gate.active).toBe(false);
    expect(pending.map((item) => item.request.id)).toEqual(["format", "mode"]);
    for (const item of pending) item.resolve({accepted: true, id: item.request.id});

    await expect(first).resolves.toEqual({accepted: true, id: "format"});
    await expect(second).resolves.toEqual({accepted: true, id: "mode"});
    expect(gate.finish()).toEqual([]);
  });

  it("lets the dispatcher reject a request after composition changes generation", async () => {
    const gate = new CompositionRequestGate<Request, Result>();
    gate.begin();
    const result = gate.enqueue({id: "format", generation: 8, identity: "A"});
    const currentGeneration = 9;
    for (const item of gate.finish()) {
      item.resolve({accepted: item.request.generation === currentGeneration, id: item.request.id});
    }
    await expect(result).resolves.toEqual({accepted: false, id: "format"});
  });

  it("rejects every queued request when the editor identity changes", async () => {
    const gate = new CompositionRequestGate<Request, Result>();
    gate.begin();
    const result = gate.enqueue({id: "mode", generation: 2, identity: "A"});
    gate.rejectAll((request) => ({accepted: false, id: request.id}));
    await expect(result).resolves.toEqual({accepted: false, id: "mode"});
    expect(gate.active).toBe(false);
  });

  it("releases a request after a cancelled composition when identity and generation stay unchanged", async () => {
    const gate = new CompositionRequestGate<Request, Result>();
    gate.begin();
    const request = {id: "source-mode", generation: 3, identity: "A"};
    const result = gate.enqueue(request);
    for (const item of gate.finish()) {
      item.resolve({
        accepted: item.request.generation === 3 && item.request.identity === "A",
        id: item.request.id,
      });
    }
    await expect(result).resolves.toEqual({accepted: true, id: "source-mode"});
  });
});
