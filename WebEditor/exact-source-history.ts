import {ChangeSet, Compartment, EditorState, StateEffect, StateField, Transaction, type ChangeDesc, type Extension} from "@codemirror/state";
import {historyField, invertedEffects, redo, redoDepth, redoSelection, undo, undoDepth, undoSelection} from "@codemirror/commands";
import {ExactSourceMirror, normalizedDocumentText, type NormalizedSourceChange} from "./state";
import {MAX_INBOUND_BYTES, MAX_SOURCE_UTF8_BYTES} from "./protocol";
import {recordEditorMetric} from "./performance";

/** Exact bytes are part of the retained editor state, alongside its history. */
export const setExactSource = StateEffect.define<string>();
type LineEnding = {at: number; ending: string};
// Derived, nonowning context for CodeMirror's lazy nonhistory mappings. Values
// are the current complete event inverses, obtained through public Undo/Redo.
const eventInverses = new WeakMap<LineEnding, ChangeDesc>();
let detachedHistoryDepth = 0;
function detachedHistory<T>(operation: () => T): T {
  detachedHistoryDepth++;
  try { return operation(); } finally { detachedHistoryDepth--; }
}
const restoreLineEnding = StateEffect.define<LineEnding>({
  map(value, mapping) {
    // The pinned history implementation joins effects in restored/output
    // coordinates with a ChangeSet, but maps nonhistory changes in event/input
    // coordinates with a ChangeDesc. Deleted newlines live in the output.
    if (mapping instanceof ChangeSet) return {...value, at: mapping.mapPos(value.at, 1)};
    const inverse = eventInverses.get(value);
    if (!inverse) throw new Error("Exact history mapping is unavailable");
    const outputMapping = mapping.mapDesc(inverse, true);
    const result = {...value, at: outputMapping.mapPos(value.at, 1)};
    eventInverses.set(result, inverse.mapDesc(mapping));
    return result;
  },
});

function transactionChanges(transaction: Transaction, mirror: ExactSourceMirror): NormalizedSourceChange[] {
  const endings = new Map(transaction.effects.filter(effect => effect.is(restoreLineEnding))
    .map(effect => [effect.value.at, effect.value.ending]));
  const changes: NormalizedSourceChange[] = [];
  transaction.changes.iterChanges((from, to, fromB, _toB, inserted) => {
    const insert = inserted.toString();
    const exactInsert = insert.replace(/\n/g, (_newline, offset: number) =>
      endings.get(fromB + offset) ?? (mirror.usesCRLF ? "\r\n" : "\n"));
    changes.push({from, to, insert, exactInsert, removed: transaction.startState.doc.sliceString(from, to)});
  });
  return changes;
}

export const exactSourceState = StateField.define<ExactSourceMirror>({
  create: state => new ExactSourceMirror(state.doc.toString()),
  update(mirror, transaction) {
    const replacement = transaction.effects.find(effect => effect.is(setExactSource));
    if (replacement) {
      if (normalizedDocumentText(replacement.value) !== transaction.newDoc.toString()) {
        throw new Error("Exact source does not match the editor document");
      }
      return new ExactSourceMirror(replacement.value);
    }
    if (!transaction.docChanged) return mirror;
    const startedAt = performance.now();
    const changes = transactionChanges(transaction, mirror);
    const next = mirror.copy();
    if (!next.apply(changes)) throw new Error("Exact source change is invalid");
    if (detachedHistoryDepth === 0) recordEditorMetric("exact-source-update", startedAt, {
      changeCount: changes.length, documentLength: transaction.newDoc.length});
    return next;
  },
});

export const exactSourceHistory: Extension = [exactSourceState,
  EditorState.transactionExtender.of(transaction => {
    if (transaction.docChanged && transaction.annotation(Transaction.addToHistory) === false) {
      for (const command of [undo, redo]) {
        let detached = transaction.startState;
        while (detachedHistory(() => command({state: detached, dispatch: historical => {
          for (const effect of historical.effects) {
            if (effect.is(restoreLineEnding)) eventInverses.set(effect.value, historical.changes.desc);
          }
          detached = historical.state;
        }}))) { /* detached traversal only */ }
      }
    }
    return null;
  }), invertedEffects.of(transaction => {
  if (!transaction.docChanged) return [];
  const mirror = transaction.startState.field(exactSourceState);
  const effects: StateEffect<{at: number; ending: string}>[] = [];
  transaction.changes.iterChanges((from, to) => {
    const removed = mirror.slice(from, to);
    let normalizedOffset = from;
    for (let offset = 0; offset < removed.length; offset++, normalizedOffset++) {
      const crlf = removed[offset] === "\r" && removed[offset + 1] === "\n";
      if (crlf || removed[offset] === "\n") {
        effects.push(restoreLineEnding.of({at: normalizedOffset, ending: crlf ? "\r\n" : "\n"}));
        if (crlf) offset++;
      }
    }
  });
  return effects;
})];

export function exactSourceFitsChanges(state: EditorState, changes: readonly NormalizedSourceChange[]) {
  const source = state.field(exactSourceState);
  const encoder = new TextEncoder();
  let previous = 0, bytes = 0;
  // Count monotonic output pieces before allocating a potentially enormous
  // Replace All result. Untouched CRLF bytes count toward the same source cap.
  for (const change of [...changes].sort((left, right) => left.from - right.from || left.to - right.to)) {
    if (!Number.isSafeInteger(change.from) || !Number.isSafeInteger(change.to)
        || change.from < previous || change.to < change.from || change.to > state.doc.length) return false;
    const normalized = normalizedDocumentText(change.insert);
    const insertion = change.exactInsert ?? (source.usesCRLF ? normalized.replaceAll("\n", "\r\n") : normalized);
    if (normalizedDocumentText(insertion) !== normalized) return false;
    bytes += encoder.encode(source.slice(previous, change.from)).byteLength + encoder.encode(insertion).byteLength;
    if (bytes > MAX_SOURCE_UTF8_BYTES) return false;
    previous = change.to;
  }
  return bytes + encoder.encode(source.slice(previous, state.doc.length)).byteLength <= MAX_SOURCE_UTF8_BYTES;
}

function lineEndings(source: string) {
  return Array.from(source.matchAll(/\r?\n/g), match => match[0] === "\r\n" ? "c" : "l").join("");
}

function sourceWithEndings(source: string, endings: string) {
  let index = 0;
  const exact = source.replace(/\n/g, () => {
    const ending = endings[index++];
    if (ending !== "c" && ending !== "l") throw new Error("Invalid history line endings");
    return ending === "c" ? "\r\n" : "\n";
  });
  if (index !== endings.length) throw new Error("Invalid history line ending count");
  return exact;
}

const maximumRecoveryEvents = 512;

/** CodeMirror omits custom effects from its JSON. Capture only the missing
 * newline metadata through public Undo/Redo on detached immutable states. */
export function captureExactHistory(state: EditorState): string | undefined {
  let remainingBytes = MAX_INBOUND_BYTES - new TextEncoder().encode(state.doc.toString()).byteLength;
  const capture = (command: typeof undo) => {
    let detached = state;
    const endings: (string | null)[] = [];
    for (let index = 0; ; index++) {
      let changed = false;
      if (!detachedHistory(() => command({state: detached, dispatch: transaction => {
        changed = transaction.docChanged;
        // Inverse insertions are the source material serialized by history.
        // Bound it before constructing CodeMirror's full JSON object.
        transaction.changes.iterChanges((_from, _to, _fromB, _toB, inserted) => {
          remainingBytes -= new TextEncoder().encode(inserted.toString()).byteLength;
        });
        if (remainingBytes < 0) throw new Error("History is too large");
        detached = transaction.state;
      }}))) break;
      if (index >= maximumRecoveryEvents) throw new Error("History is too large");
      const value = changed ? lineEndings(detached.field(exactSourceState).text) : null;
      remainingBytes -= value?.length ?? 0;
      if (remainingBytes < 0) throw new Error("History is too large");
      endings.push(value);
    }
    return endings;
  };
  try {
    if (remainingBytes < 0) return undefined;
    const undoLineEndings = capture(undoSelection);
    const redoLineEndings = capture(redoSelection);
    const serialized = JSON.stringify({
      state: state.toJSON({history: historyField}),
      undoLineEndings,
      redoLineEndings,
    });
    return new TextEncoder().encode(serialized).byteLength <= MAX_INBOUND_BYTES ? serialized : undefined;
  } catch { return undefined; }
}

/** Rebuild both branches using public history transactions, keeping their
 * original grouping. The temporary extender exists only during restoration. */
export function restoreExactHistory(serialized: string, source: string, extensions: Extension): EditorState {
  if (new TextEncoder().encode(serialized).byteLength > MAX_INBOUND_BYTES) throw new Error("History is too large");
  const payload = JSON.parse(serialized);
  const validEndings = (value: unknown): value is (string | null)[] => Array.isArray(value)
    && value.length <= maximumRecoveryEvents && value.every(item => item === null || typeof item === "string" && /^[cl]*$/.test(item));
  if (!validEndings(payload.undoLineEndings) || !validEndings(payload.redoLineEndings)) {
    throw new Error("Invalid history line endings");
  }
  let state = EditorState.fromJSON(payload.state, {extensions}, {history: historyField});
  if (state.doc.toString() !== normalizedDocumentText(source)
      || undoDepth(state) !== payload.undoLineEndings.filter((value: string | null) => value !== null).length
      || redoDepth(state) !== payload.redoLineEndings.filter((value: string | null) => value !== null).length) {
    throw new Error("History does not match the recovered source");
  }
  const recovery = new Compartment();
  let targetEndings: string | undefined;
  state = state.update({effects: [setExactSource.of(source), StateEffect.appendConfig.of(recovery.of(
    EditorState.transactionExtender.of(transaction => targetEndings === undefined ? null : {
      effects: setExactSource.of(sourceWithEndings(transaction.newDoc.toString(), targetEndings)),
    }),
  ))], annotations: Transaction.addToHistory.of(false)}).state;
  function replay(command: typeof undo, endings?: string | null) {
    targetEndings = endings ?? undefined;
    try {
      if (!detachedHistory(() => command({state, dispatch: transaction => { state = transaction.state; }}))) throw new Error("History could not be restored");
    } finally { targetEndings = undefined; }
  }
  // Redo creates exact inverses for the existing undone branch; undo it back
  // before rebuilding the done branch in the same way.
  for (const endings of payload.redoLineEndings) replay(redoSelection, endings);
  for (const _ of payload.redoLineEndings) replay(undoSelection);
  for (const endings of payload.undoLineEndings) replay(undoSelection, endings);
  for (const _ of payload.undoLineEndings) replay(redoSelection);
  state = state.update({effects: recovery.reconfigure([]), annotations: Transaction.addToHistory.of(false)}).state;
  if (state.field(exactSourceState).text !== source) throw new Error("History source did not restore exactly");
  return state;
}
