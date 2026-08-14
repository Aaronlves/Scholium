export interface DeferredCompositionRequest<Request, Result> {
  request: Request;
  resolve: (result: Result) => void;
}

export type CompositionRequestPolicy = "allow" | "defer" | "reject";

export function compositionRequestPolicy(operationType: string): CompositionRequestPolicy {
  if (operationType === "initialize") return "reject";
  if ([
    "setMode",
    "setPresentationCSS",
    "setUserCSS",
    "setLinkPreviews",
    "goToLine",
    "restoreRecovery",
    "acknowledgeCommittedSnapshot",
    "command",
    "documentFind",
    "clearDocumentFind",
  ].includes(operationType)) return "defer";
  return "allow";
}

/**
 * Holds native requests while WebKit owns a marked-text composition.
 *
 * The caller remains responsible for validating document identity and
 * generation after composition ends. Keeping that validation outside this
 * gate makes the policy explicit: this type controls timing, never authority.
 */
export class CompositionRequestGate<Request, Result> {
  private requests: Array<DeferredCompositionRequest<Request, Result>> = [];
  private composing = false;

  get active() { return this.composing; }

  begin() {
    this.composing = true;
  }

  enqueue(request: Request): Promise<Result> {
    return new Promise((resolve) => this.requests.push({request, resolve}));
  }

  finish(): Array<DeferredCompositionRequest<Request, Result>> {
    this.composing = false;
    return this.requests.splice(0);
  }

  rejectAll(result: (request: Request) => Result) {
    this.composing = false;
    for (const pending of this.requests.splice(0)) pending.resolve(result(pending.request));
  }
}
