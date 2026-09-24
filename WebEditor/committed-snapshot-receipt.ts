import type {EditorOperation, EditorRequest} from "./protocol";

type Commit = Extract<EditorOperation, {type: "acknowledgeCommittedSnapshot"}>;
type Identity = Pick<EditorRequest, "sessionID" | "documentID" | "startingFingerprint">;

/** One completed acknowledgement, retained only until the next commit or page
 * attachment. It authorizes a response replay, never a second source mutation. */
export class CommittedSnapshotReceipt {
  private receipt: (Identity & Commit) | null = null;

  clear() { this.receipt = null; }

  remember(identity: Identity, operation: Commit) {
    this.receipt = {
      sessionID: identity.sessionID,
      documentID: identity.documentID,
      startingFingerprint: identity.startingFingerprint,
      ...operation,
    };
  }

  replay(request: Pick<EditorRequest, "sessionID" | "documentID" | "startingFingerprint" | "operation">,
    current: Identity, source: string, dirty: boolean) {
    if (!this.canReplay(request, current) || request.operation.type !== "acknowledgeCommittedSnapshot") return null;
    return {text: source, commitSuperseded: dirty || source !== request.operation.committedText};
  }

  canReplay(request: Pick<EditorRequest, "sessionID" | "documentID" | "startingFingerprint" | "operation">,
    current: Identity) {
    const receipt = this.receipt;
    const operation = request.operation;
    return receipt !== null && operation.type === "acknowledgeCommittedSnapshot"
      // Equal-base requests still use ordinary reconciliation, which may mark
      // a newly saved, byte-identical buffer clean. Only the old-base retry
      // needs this narrowly scoped identity exception.
      && request.startingFingerprint !== current.startingFingerprint
      && receipt.sessionID === current.sessionID && request.sessionID === receipt.sessionID
      && receipt.documentID === current.documentID && request.documentID === receipt.documentID
      && request.startingFingerprint === receipt.startingFingerprint
      && current.startingFingerprint === receipt.committedFingerprint
      && operation.committedFingerprint === receipt.committedFingerprint
      && operation.expectedText === receipt.expectedText
      && operation.committedText === receipt.committedText;
  }
}
