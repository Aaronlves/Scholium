import {afterEach, describe, expect, it, vi} from "vitest";
import {createMermaidRuntimeLoader} from "../mermaid-runtime-loader";
import type {ScholiumMermaidRuntime} from "../mermaid-runtime";

afterEach(() => vi.useRealTimers());

describe("Mermaid runtime attachment lifetime", () => {
  it("cancels the detached request and requests the next coordinator immediately", async () => {
    vi.useFakeTimers();
    const host = {
      setTimeout: setTimeout as unknown as Window["setTimeout"],
      clearTimeout: clearTimeout as unknown as Window["clearTimeout"],
      scholiumMermaid: undefined as ScholiumMermaidRuntime | undefined,
      scholiumMermaidRuntimeDidLoad: undefined as ((loaded: boolean) => void) | undefined,
    };
    const request = vi.fn();
    const loader = createMermaidRuntimeLoader(host, request);
    const first = loader.ensure();
    expect(loader.ensure()).toBe(first);
    const oldFinish = host.scholiumMermaidRuntimeDidLoad!;
    loader.resetDocument();
    expect(await first).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
    expect(host.scholiumMermaidRuntimeDidLoad).toBeUndefined();

    const second = loader.ensure();
    const newFinish = host.scholiumMermaidRuntimeDidLoad!;
    expect(request).toHaveBeenCalledTimes(2);
    oldFinish(false);
    expect(host.scholiumMermaidRuntimeDidLoad).toBe(newFinish);
    expect(vi.getTimerCount()).toBe(1);
    const runtime = {version: 2} as ScholiumMermaidRuntime;
    host.scholiumMermaid = runtime;
    newFinish(true);
    expect(await second).toBe(runtime);
    expect(vi.getTimerCount()).toBe(0);
    loader.resetDocument();
    expect(await loader.ensure()).toBe(runtime);
    expect(request).toHaveBeenCalledTimes(2);
  });

  it("retries after the load timeout without retaining its callback", async () => {
    vi.useFakeTimers();
    const host = {
      setTimeout: setTimeout as unknown as Window["setTimeout"],
      clearTimeout: clearTimeout as unknown as Window["clearTimeout"],
      scholiumMermaidRuntimeDidLoad: undefined as ((loaded: boolean) => void) | undefined,
    };
    const request = vi.fn();
    const loader = createMermaidRuntimeLoader(host, request);
    const first = loader.ensure();
    vi.advanceTimersByTime(8_000);
    expect(await first).toBeNull();
    expect(host.scholiumMermaidRuntimeDidLoad).toBeUndefined();
    const retry = loader.ensure();
    expect(request).toHaveBeenCalledTimes(2);
    loader.resetDocument();
    expect(await retry).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });
});
