import type {EditorOperation} from "./protocol";

export interface DeferredCompositionRequest<Request, Result> {
  request: Request;
  resolve: (result: Result) => void;
}

export type CompositionRequestPolicy = "allow" | "defer" | "reject";

// Every protocol addition must choose its marked-text behavior explicitly.
const policies: Record<EditorOperation["type"], CompositionRequestPolicy> = {
  initialize: "reject", replacePassage: "reject", insertReference: "reject",
  queryText: "defer", querySelection: "defer", captureRecovery: "defer",
  markClean: "defer", setMode: "defer", setDocumentTitle: "defer",
  setPresentationCSS: "defer", setUserCSS: "defer", setLinkPreviews: "defer",
  goToLine: "defer", revealSourceRange: "defer", restoreRecovery: "defer",
  acknowledgeCommittedSnapshot: "defer", command: "defer", documentFind: "defer",
  clearDocumentFind: "defer", showPreview: "defer", showPreviewAt: "defer",
  measureVisibleProjection: "defer", setScrollFraction: "defer", setScrollAnchor: "defer",
  focus: "defer", focusTitle: "defer", blur: "defer",
  queryContext: "allow", queryScrollAnchor: "allow", queryPerformance: "allow", announceStatus: "allow",
  suspendForDetachment: "defer", resumeAfterDetachment: "allow",
};
export function compositionRequestPolicy(operationType: EditorOperation["type"]): CompositionRequestPolicy {
  return policies[operationType];
}

/** Body and title marked text share one timing owner; identity and generation
 * are still revalidated by the dispatcher after the last composition ends. */
export class CompositionRequestGate<Request extends {expiresAt: number}, Result> {
  private requests = new Map<DeferredCompositionRequest<Request, Result>, ReturnType<typeof setTimeout>>();
  private owners = new Map<"editor" | "title", number>();
  private sequence = 0;

  constructor(private readonly expired: (request: Request) => Result) {}
  get active() { return this.owners.size > 0; }
  begin(owner: "editor" | "title" = "editor") { this.owners.set(owner, ++this.sequence); }

  revision(owner: "editor" | "title") { return this.owners.get(owner); }

  enqueue(request: Request): Promise<Result> {
    if (request.expiresAt <= Date.now()) return Promise.resolve(this.expired(request));
    return new Promise(resolve => {
      const pending = {request, resolve};
      const expire = () => {
        if (request.expiresAt > Date.now()) {
          this.requests.set(pending, setTimeout(expire, Math.min(2_147_483_647, request.expiresAt - Date.now())));
          return;
        }
        this.requests.delete(pending);
        resolve(this.expired(request));
      };
      this.requests.set(pending, setTimeout(expire, Math.min(2_147_483_647, request.expiresAt - Date.now())));
    });
  }

  finish(owner: "editor" | "title" = "editor", revision = this.owners.get(owner)): Array<DeferredCompositionRequest<Request, Result>> {
    if (revision !== this.owners.get(owner)) return [];
    this.owners.delete(owner);
    if (this.active) return [];
    const pending = [...this.requests.keys()];
    for (const timer of this.requests.values()) clearTimeout(timer);
    this.requests.clear();
    return pending.filter(item => {
      if (item.request.expiresAt > Date.now()) return true;
      item.resolve(this.expired(item.request));
      return false;
    });
  }

  rejectAll(result: (request: Request) => Result) {
    this.owners.clear();
    for (const [pending, timer] of this.requests) {
      clearTimeout(timer);
      pending.resolve(result(pending.request));
    }
    this.requests.clear();
  }
}
