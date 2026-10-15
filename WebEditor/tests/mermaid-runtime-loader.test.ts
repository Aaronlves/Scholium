import {afterEach, describe, expect, it, vi} from "vitest";
import {createMermaidRuntimeLoader} from "../mermaid-runtime-loader";
import type {ScholiumMermaidRuntime} from "../mermaid-runtime";

afterEach(() => vi.useRealTimers());

describe("Mermaid runtime attachment lifetime", () => {
  it("rejects an obsolete runtime that cannot provide independently admitted SVG copies", async () => {
    vi.useFakeTimers();
    const obsolete = {version: 2, render: vi.fn(), mount: vi.fn()};
    const host = {
      setTimeout: setTimeout as unknown as Window["setTimeout"],
      clearTimeout: clearTimeout as unknown as Window["clearTimeout"],
      scholiumMermaid: obsolete as unknown as ScholiumMermaidRuntime,
      scholiumMermaidRuntimeDidLoad: undefined as ((loaded: boolean) => void) | undefined,
    };
    const request = vi.fn();
    const loader = createMermaidRuntimeLoader(host, request);
    const pending = loader.ensure();
    expect(request).toHaveBeenCalledTimes(1);
    host.scholiumMermaidRuntimeDidLoad!(true);
    expect(await pending).toBeNull();
    expect(obsolete.render).not.toHaveBeenCalled();
    expect(obsolete.mount).not.toHaveBeenCalled();
    expect(vi.getTimerCount()).toBe(0);
    expect(host.scholiumMermaidRuntimeDidLoad).toBeUndefined();
  });

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
    const runtime = {version: 3} as ScholiumMermaidRuntime;
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
