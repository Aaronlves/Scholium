import type {ScholiumMermaidRenderResult, ScholiumMermaidRuntime} from "./mermaid-runtime";

type RenderedDiagram = Extract<ScholiumMermaidRenderResult, {ok: true}>;
export type ReaderMermaidPass = (
  runtime: ScholiumMermaidRuntime,
  source: string,
) => Promise<ScholiumMermaidRenderResult>;

/** A complete pass owns its duplicate work; nothing survives into another pass. */
export function createReaderMermaidPass(
  sources: readonly string[],
  themeRoot: Element,
  presentationRevision: () => number,
): ReaderMermaidPass {
  const remaining = new Map<string, number>();
  for (const source of sources) {
    remaining.set(source, (remaining.get(source) ?? 0) + 1);
  }
  const templates = new Map<string, {revision: number; result: RenderedDiagram}>();
  return async (runtime, source) => {
    const following = (remaining.get(source) ?? 1) - 1;
    if (following > 0) remaining.set(source, following);
    else remaining.delete(source);
    const revision = presentationRevision();
    const previous = templates.get(source);
    if (previous?.revision === revision) {
      const svg = runtime.copy(previous.result.svg);
      if (following === 0) templates.delete(source);
      if (svg) return {...previous.result, svg};
    }
    const result = await runtime.render({source, themeRoot});
    if (result.ok && following > 0 && presentationRevision() === revision) {
      // Preserve an unmounted template. Every displayed copy is revalidated
      // and independently consumes the runtime's one-mount authorization.
      const svg = runtime.copy(result.svg);
      if (svg) templates.set(source, {revision, result: {...result, svg}});
    } else {
      templates.delete(source);
    }
    return result;
  };
}
