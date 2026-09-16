import type {ScholiumMermaidRuntime} from "./mermaid-runtime";

type RuntimeHost = Pick<Window, "scholiumMermaid" | "scholiumMermaidRuntimeDidLoad"
  | "setTimeout" | "clearTimeout">;

/** A runtime survives reuse, but an unfinished request belongs to its attachment. */
export function createMermaidRuntimeLoader(host: RuntimeHost, requestRuntime: () => void) {
  let pending: {promise: Promise<ScholiumMermaidRuntime | null>; cancel(): void} | null = null;
  return {
    ensure(): Promise<ScholiumMermaidRuntime | null> {
      if (host.scholiumMermaid?.version === 2) return Promise.resolve(host.scholiumMermaid);
      if (pending) return pending.promise;
      let resolve!: (runtime: ScholiumMermaidRuntime | null) => void;
      const promise = new Promise<ScholiumMermaidRuntime | null>(complete => { resolve = complete; });
      let settled = false;
      const complete = (runtime: ScholiumMermaidRuntime | null) => {
        if (settled) return;
        settled = true;
        host.clearTimeout(timeout);
        if (host.scholiumMermaidRuntimeDidLoad === finish) host.scholiumMermaidRuntimeDidLoad = undefined;
        if (pending === load) pending = null;
        resolve(runtime);
      };
      const finish = () => complete(host.scholiumMermaid?.version === 2 ? host.scholiumMermaid : null);
      const timeout = host.setTimeout(finish, 8_000);
      const load = {promise, cancel: () => complete(null)};
      pending = load;
      host.scholiumMermaidRuntimeDidLoad = finish;
      requestRuntime();
      return promise;
    },
    resetDocument() { pending?.cancel(); },
  };
}
