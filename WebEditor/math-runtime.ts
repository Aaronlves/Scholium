import katex from "katex";

export type ScholiumMathKind = "inline" | "display";

export interface ScholiumMathRenderRequest {
  source: string;
  kind: ScholiumMathKind;
}

export type ScholiumMathRenderResult =
  | {ok: true; html: string}
  | {ok: false; reason: "invalid-source" | "unsupported-mathematics"};

export interface ScholiumMathRuntime {
  readonly version: 1;
  render(request: ScholiumMathRenderRequest): ScholiumMathRenderResult;
}

const maximumSourceLength = 16_384;

export function renderMath(request: ScholiumMathRenderRequest): ScholiumMathRenderResult {
  if (
    (request.kind !== "inline" && request.kind !== "display")
    || typeof request.source !== "string"
    || request.source.length === 0
    || request.source.length > maximumSourceLength
  ) {
    return {ok: false, reason: "invalid-source"};
  }

  try {
    return {
      ok: true,
      html: katex.renderToString(request.source, {
        displayMode: request.kind === "display",
        output: "htmlAndMathml",
        throwOnError: true,
        trust: false,
        strict: "error",
        maxExpand: 100,
        maxSize: 20,
      }),
    };
  } catch {
    return {ok: false, reason: "unsupported-mathematics"};
  }
}

export const scholiumMathRuntime: ScholiumMathRuntime = Object.freeze({
  version: 1,
  render: renderMath,
});

declare global {
  interface Window {
    scholiumMath?: ScholiumMathRuntime;
  }
}

if (typeof window !== "undefined") {
  window.scholiumMath = scholiumMathRuntime;
}
