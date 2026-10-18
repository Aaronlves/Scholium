import {ChangeDesc, ChangeSet, EditorSelection, EditorState, StateEffect, StateField, Transaction, type Extension} from "@codemirror/state";
import {historyField, invertedEffects, redo, redoSelection, undo, undoSelection} from "@codemirror/commands";
import {ExactSourceMirror, normalizedDocumentText, type NormalizedSourceChange} from "./state";
import {MAX_RECOVERY_HISTORY_BYTES} from "./protocol";
import {MAX_SOURCE_UTF8_BYTES, exactSourceFits, sourceCapacityMessage} from "./source-capacity";
export {exactSourceFits, sourceCapacityMessage} from "./source-capacity";
import {citationHistory, citationState, setCitationData, validCitationData, type ZoteroCitationData} from "./zotero-citation-state";
import {recordEditorMetric} from "./performance";

/** Exact bytes are part of the retained editor state, alongside its history. */
export const setExactSource = StateEffect.define<string>();
export const sourceCapacityExceeded = StateEffect.define<null>();
function admittedMirror(source: string) {
  if (!exactSourceFits(source)) throw new Error(sourceCapacityMessage);
  return new ExactSourceMirror(source);
}
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

/** Preserve the original separators of a source slice inserted by a move/copy.
 * Positions are in the resulting document, just like inverse-history effects.
 */
export function exactInsertionEffects(source: string, at: number) {
  const effects: StateEffect<LineEnding>[] = [];
  let position = at;
  for (let offset = 0; offset < source.length; offset++, position++) {
    const crlf = source[offset] === "\r" && source[offset + 1] === "\n";
    if (crlf || source[offset] === "\n") {
      effects.push(restoreLineEnding.of({at: position, ending: crlf ? "\r\n" : "\n"}));
      if (crlf) offset++;
    }
  }
  return effects;
}

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
  create: state => admittedMirror(state.doc.toString()),
  update(mirror, transaction) {
    const replacement = transaction.effects.find(effect => effect.is(setExactSource));
    if (replacement) {
      if (normalizedDocumentText(replacement.value) !== transaction.newDoc.toString()) {
        throw new Error("Exact source does not match the editor document");
      }
      return admittedMirror(replacement.value);
    }
    if (!transaction.docChanged) return mirror;
    const startedAt = performance.now();
    const changes = transactionChanges(transaction, mirror);
    const next = mirror.copy();
    if (!next.apply(changes)) throw new Error("Exact source change is invalid");
    if (next.utf8ByteCount > MAX_SOURCE_UTF8_BYTES) throw new Error(sourceCapacityMessage);
    if (detachedHistoryDepth === 0) recordEditorMetric("exact-source-update", startedAt, {
      changeCount: changes.length, documentLength: transaction.newDoc.length});
    return next;
  },
});

export const exactSourceHistory: Extension = [exactSourceState,
  EditorState.transactionFilter.of(transaction => {
    const startedAt = performance.now();
    const replacement = transaction.effects.find(effect => effect.is(setExactSource));
    const admitted = replacement ? exactSourceFits(replacement.value)
      : !transaction.docChanged || exactSourceFitsChanges(transaction.startState,
          transactionChanges(transaction, transaction.startState.field(exactSourceState)));
    if (detachedHistoryDepth === 0 && (transaction.docChanged || replacement)) {
      recordEditorMetric("exact-source-admission", startedAt, {
        documentLength: transaction.newDoc.length, admitted: admitted ? 1 : 0,
      });
    }
    // Refusal preserves text, selection and history as one atomic boundary.
    return admitted ? transaction : {effects: sourceCapacityExceeded.of(null)};
  }),
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
  const source = state.field(exactSourceState, false) ?? new ExactSourceMirror(state.doc.toString());
  if (changes.length <= 1) {
    const next = source.copy();
    return next.apply(changes) && next.utf8ByteCount <= MAX_SOURCE_UTF8_BYTES;
  }
  // Bound multi-range expansion before constructing ropes (for example Replace
  // All). Carry a high surrogate between pieces so UTF-8 is counted exactly.
  const encoder = new TextEncoder();
  let bytes = 0, previous = 0, pendingHigh = "";
  const append = (piece: string) => {
    const text = pendingHigh + piece;
    const last = text.charCodeAt(text.length - 1);
    pendingHigh = last >= 0xD800 && last <= 0xDBFF ? text.slice(-1) : "";
    bytes += encoder.encode(pendingHigh ? text.slice(0, -1) : text).byteLength;
    return bytes <= MAX_SOURCE_UTF8_BYTES;
  };
  for (const change of [...changes].sort((left, right) => left.from - right.from || left.to - right.to)) {
    if (!Number.isSafeInteger(change.from) || !Number.isSafeInteger(change.to)
        || change.from < previous || change.to < change.from || change.to > state.doc.length) return false;
    const normalized = normalizedDocumentText(change.insert);
    const insertion = change.exactInsert ?? (source.usesCRLF ? normalized.replaceAll("\n", "\r\n") : normalized);
    if (normalizedDocumentText(insertion) !== normalized) return false;
    if (!append(source.slice(previous, change.from)) || !append(insertion)) return false;
    previous = change.to;
  }
  return append(source.slice(previous, state.doc.length))
    && bytes + encoder.encode(pendingHigh).byteLength <= MAX_SOURCE_UTF8_BYTES;
}

/** The only private CodeMirror boundary in recovery. Verified against pinned
 * @codemirror/commands 6.10.4 and @codemirror/state 6.7.1. CodeMirror's JSON
 * preserves its complete history except inverse effects. Replaying commands to
 * restore those effects changes selection trails and lazy mappings, so retain
 * the original events and attach only our explicitly supported effects.
 * Every constructor, shape, codec and complete JSON roundtrip is checked before
 * a live state may be detached. Dependency upgrades must revalidate this adapter.
 */
interface HistoryEvent {
  changes?: ChangeSet;
  effects: readonly StateEffect<unknown>[];
  mapped?: ChangeDesc;
  startSelection?: EditorSelection;
  selectionsAfter: readonly EditorSelection[];
  toJSON(): unknown;
}
interface HistoryValue {
  done: readonly HistoryEvent[];
  undone: readonly HistoryEvent[];
  prevTime: number;
  prevUserEvent?: string;
}
interface HistoryGrouping {time: number; userEvent?: string}
type HistoryBranch = "done" | "undone";
type InverseEffects = ({lineEndings: [number[], string]} | {citation: number})[];
const historyError = () => new Error("Incompatible exact history metadata");
const ownKeys = (value: object, keys: readonly string[]) => {
  const actual = Object.keys(value).sort(), expected = [...keys].sort();
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
};
function checkedGrouping(value: unknown): HistoryGrouping {
  if (!value || typeof value !== "object"
      || !ownKeys(value, ["time"]) && !ownKeys(value, ["time", "userEvent"])) throw historyError();
  const grouping = value as HistoryGrouping;
  if (!Number.isFinite(grouping.time) || grouping.userEvent !== undefined && typeof grouping.userEvent !== "string") throw historyError();
  return grouping;
}
function jsonEqual(left: unknown, right: unknown): boolean {
  if (left === right) return true;
  if (!left || !right || typeof left !== "object" || typeof right !== "object") return false;
  if (Array.isArray(left) || Array.isArray(right)) return Array.isArray(left) && Array.isArray(right)
    && left.length === right.length && left.every((item, index) => jsonEqual(item, right[index]));
  const a = left as Record<string, unknown>, b = right as Record<string, unknown>;
  const keys = Object.keys(a).filter(key => a[key] !== undefined);
  return keys.length === Object.keys(b).filter(key => b[key] !== undefined).length
    && keys.every(key => Object.hasOwn(b, key) && jsonEqual(a[key], b[key]));
}
function validChangeJSON(value: unknown, mapping: boolean) {
  if (!Array.isArray(value)) return false;
  if (mapping) return value.length % 2 === 0 && value.every((part, index) => Number.isSafeInteger(part)
    && part >= (index % 2 ? -1 : 0));
  return value.every(part => Number.isSafeInteger(part) && part >= 0
    || Array.isArray(part) && part.length > 0 && Number.isSafeInteger(part[0]) && part[0] >= 0
      && part.slice(1).every(text => typeof text === "string"));
}
function checkedHistory(state: EditorState): HistoryValue {
  const value = state.field(historyField) as HistoryValue;
  if (!value || !ownKeys(value, ["done", "undone", "prevTime", "prevUserEvent"])
      || !Array.isArray(value.done) || !Array.isArray(value.undone)
      || !Number.isFinite(value.prevTime) || value.prevUserEvent !== undefined && typeof value.prevUserEvent !== "string") throw historyError();
  const prototype = Object.getPrototypeOf(value);
  if (!prototype || prototype.constructor === Object || prototype.constructor.length !== 2
      || !["isolate", "addChanges", "addSelection", "addMapping", "pop"].every(key => typeof prototype[key] === "function")) throw historyError();
  let eventPrototype: object | undefined;
  for (const branch of [value.done, value.undone]) for (const event of branch) {
    const eventProto = Object.getPrototypeOf(event);
    if (!eventProto || eventProto.constructor === Object || eventProto.constructor.length !== 5
        || typeof eventProto.toJSON !== "function" || typeof eventProto.setSelAfter !== "function"
        || typeof eventProto.constructor.fromJSON !== "function"
        || eventPrototype && eventProto !== eventPrototype
        || !ownKeys(event, ["changes", "effects", "mapped", "startSelection", "selectionsAfter"])
        || !Array.isArray(event.effects) || !Array.isArray(event.selectionsAfter)
        || !event.selectionsAfter.every((selection: unknown) => selection instanceof EditorSelection)
        || event.changes !== undefined && !(event.changes instanceof ChangeSet)
        || event.mapped !== undefined && !(event.mapped instanceof ChangeDesc)
        || event.startSelection !== undefined && !(event.startSelection instanceof EditorSelection)
        || !event.changes && (event.effects.length > 0 || event.mapped || event.startSelection)
        || event.changes && !event.startSelection) throw historyError();
    if (event.changes && (!validChangeJSON(event.changes.toJSON(), false)
        || !Number.isSafeInteger(event.changes.length) || !Number.isSafeInteger(event.changes.newLength)
        || event.changes.length < 0 || event.changes.newLength < 0)
        || event.mapped && (!validChangeJSON(event.mapped.toJSON(), true)
          || !Number.isSafeInteger(event.mapped.length) || !Number.isSafeInteger(event.mapped.newLength)
          || event.mapped.length < 0 || event.mapped.newLength < 0)) throw historyError();
    eventPrototype = eventProto;
    const decoded = eventProto.constructor.fromJSON(event.toJSON()) as HistoryEvent;
    if (!jsonEqual(decoded.toJSON(), event.toJSON())) throw historyError();
  }
  return value;
}
function historyJSON(value: HistoryValue) {
  return {done: value.done.map(event => event.toJSON()), undone: value.undone.map(event => event.toJSON())};
}
function attachInverseEffects(state: EditorState, effects: Record<HistoryBranch, InverseEffects[]>,
    citationTable: readonly (ZoteroCitationData | null)[], expectedHistory: unknown, grouping: HistoryGrouping) {
  const original = checkedHistory(state);
  const branches = {} as Record<HistoryBranch, HistoryEvent[]>;
  for (const branch of ["done", "undone"] as const) {
    if (!Array.isArray(effects[branch]) || effects[branch].length !== original[branch].length) throw historyError();
    branches[branch] = original[branch].map((event, index) => {
      const metadata = effects[branch][index];
      if (!Array.isArray(metadata)) throw historyError();
      const restored: StateEffect<unknown>[] = [];
      for (const record of metadata) {
        if (!record || typeof record !== "object") throw historyError();
        if (ownKeys(record, ["lineEndings"])) {
          const run = (record as {lineEndings: unknown}).lineEndings;
          if (!Array.isArray(run) || run.length !== 2 || !Array.isArray(run[0]) || run[0].length === 0
              || typeof run[1] !== "string" || !/^[cl]+$/.test(run[1]) || run[1].length !== run[0].length || !event.changes) throw historyError();
          let at = 0;
          run[0].forEach((delta, index) => {
            if (!Number.isSafeInteger(delta)) throw historyError();
            at += delta;
            if (!Number.isSafeInteger(at) || at < 0 || at > event.changes!.newLength) throw historyError();
            restored.push(restoreLineEnding.of({at, ending: run[1][index] === "c" ? "\r\n" : "\n"}));
          });
        } else if (ownKeys(record, ["citation"])) {
          const index = (record as {citation: number}).citation;
          if (!Number.isSafeInteger(index) || index < 0 || index >= citationTable.length
              || !state.field(citationState, false)) throw new Error("Invalid citation history");
          restored.push(setCitationData.of(citationTable[index] ?? undefined));
        } else throw historyError();
      }
      // Every newline inserted by this inverse must carry explicit fidelity
      // metadata. Lazy mappings may leave additional effects at collapsed ranges.
      const positions = new Set(restored.filter(effect => effect.is(restoreLineEnding)).map(effect => effect.value.at));
      event.changes?.iterChanges((_from, _to, fromB, _toB, inserted) => {
        let at = fromB;
        for (let line = 1; line < inserted.lines; line++) {
          at += inserted.line(line).length;
          if (!positions.has(at)) throw historyError();
          at++;
        }
      });
      for (const effect of restored) {
        if (effect.is(restoreLineEnding)) eventInverses.set(effect.value, event.changes!.desc);
      }
      const result = Reflect.construct(Object.getPrototypeOf(event).constructor,
        [event.changes, restored, event.mapped, event.startSelection, event.selectionsAfter]) as HistoryEvent;
      if (!jsonEqual(result.toJSON(), event.toJSON())) throw historyError();
      return result;
    });
  }
  const result = Reflect.construct(Object.getPrototypeOf(original).constructor,
    [branches.done, branches.undone, grouping.time, grouping.userEvent]) as HistoryValue;
  if (result.prevTime !== grouping.time || result.prevUserEvent !== grouping.userEvent
      || !jsonEqual(historyJSON(result), expectedHistory)) throw historyError();
  return result;
}

/** Shape validation cannot establish a historical selection's document size
 * or the dimensions of a lazy mapping chain. Execute both branches through
 * public commands on independent detached states, without writing the resulting
 * normalized events back into the original history. Only fidelity/history
 * extensions participate; view presentation and application callbacks do not.
 */
function validateHistoryBranches(state: EditorState, history: HistoryValue, source: string) {
  const companion = state.field(citationState, false);
  const detached = EditorState.create({doc: state.doc, selection: state.selection, extensions: [
    historyField.init(() => history), exactSourceHistory,
    ...(companion ? [citationHistory, citationState.init(() => companion)] : []),
    EditorState.allowMultipleSelections.of(true), EditorState.lineSeparator.of("\n"),
  ]}).update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
  const stepCount = (events: readonly HistoryEvent[]) => events.reduce((count, event) =>
    count + event.selectionsAfter.length + (event.changes ? 1 : 0), 0);
  for (const [side, command] of [["done", undoSelection], ["undone", redoSelection]] as const) {
    let branch = detached;
    const maximumSteps = stepCount(history[side]);
    if (!Number.isSafeInteger(maximumSteps)) throw historyError();
    for (let steps = 0; ; steps++) {
      const before = branch.field(historyField) as HistoryValue;
      const remaining = stepCount(before[side]);
      let dispatched = false;
      const handled = detachedHistory(() => command({state: branch, dispatch: transaction => {
        dispatched = true;
        if (transaction.effects.some(effect => effect.is(sourceCapacityExceeded))) throw historyError();
        const next = transaction.state;
        const after = next.field(historyField) as HistoryValue;
        if (next === branch || after === before || stepCount(after[side]) >= remaining) throw historyError();
        branch = next;
      }}));
      if (!handled) {
        if (dispatched || remaining !== 0) throw historyError();
        break;
      }
      // The limit follows the actual retained event/selection count. Refusal or
      // a command that stops consuming history cannot make validation hang.
      if (!dispatched || steps >= maximumSteps) throw historyError();
    }
  }
}

/** Retain CodeMirror's original JSON and only the effects it omits. Budget each
 * event before building the complete payload; selection trails count as bytes,
 * without an unrelated step limit. No live state is mutated during validation. */
export function captureExactHistory(state: EditorState, maximumBytes = MAX_RECOVERY_HISTORY_BYTES): string | undefined {
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 0 || maximumBytes > MAX_RECOVERY_HISTORY_BYTES) return undefined;
  const jsonBytes = (value: unknown) => new TextEncoder().encode(JSON.stringify(value)).byteLength;
  try {
    const history = checkedHistory(state);
    const citationFields = state.field(citationState, false) ? {citations: citationState} : undefined;
    const base = state.toJSON(citationFields);
    // These two scalars control typing/selection grouping but are omitted by
    // CodeMirror's JSON codec. Retain them alongside the inverse effects.
    const grouping = checkedGrouping({time: history.prevTime, userEvent: history.prevUserEvent});
    let remainingBytes = maximumBytes - jsonBytes(base) - jsonBytes(grouping);
    const citationTable: (ZoteroCitationData | null)[] = [];
    const citationIndices = new Map<string, number>();
    const citationIndex = (companion: ZoteroCitationData | null) => {
      if (companion !== null && !validCitationData(companion)) throw new Error("Invalid citation history");
      const serialized = JSON.stringify(companion);
      const existing = citationIndices.get(serialized);
      if (existing !== undefined) return existing;
      remainingBytes -= new TextEncoder().encode(serialized).byteLength;
      if (remainingBytes < 0) throw historyError();
      const index = citationTable.length;
      citationIndices.set(serialized, index);
      citationTable.push(companion);
      return index;
    };
    const effects = {} as Record<HistoryBranch, InverseEffects[]>;
    const encodedHistory = {done: [] as unknown[], undone: [] as unknown[]};
    for (const branch of ["done", "undone"] as const) {
      effects[branch] = [];
      for (const event of history[branch]) {
        const encoded = event.toJSON();
        remainingBytes -= jsonBytes(encoded);
        if (remainingBytes < 0) return undefined;
        encodedHistory[branch].push(encoded);
        const metadata: InverseEffects = [];
        let positions: number[] = [], endings = "", previous = 0;
        const finishRun = () => {
          if (positions.length) metadata.push({lineEndings: [positions, endings]});
          positions = []; endings = ""; previous = 0;
        };
        for (const effect of event.effects) {
          if (effect.is(restoreLineEnding)) {
            if (!Number.isSafeInteger(effect.value.at) || effect.value.at < 0
                || effect.value.ending !== "\n" && effect.value.ending !== "\r\n") throw historyError();
            positions.push(effect.value.at - previous);
            previous = effect.value.at;
            endings += effect.value.ending === "\r\n" ? "c" : "l";
          } else if (effect.is(setCitationData)) {
            finishRun();
            metadata.push({citation: citationIndex(effect.value ?? null)});
          } else throw historyError();
        }
        finishRun();
        remainingBytes -= jsonBytes(metadata);
        if (remainingBytes < 0) return undefined;
        effects[branch].push(metadata);
      }
    }
    // This proof also runs before ordinary suspension, while the actual editor
    // still owns its complete history. Runtime codec drift refuses departure.
    const serializedState = {...base, history: encodedHistory};
    const fields: Record<string, typeof historyField | typeof citationState> = {history: historyField};
    if (citationFields) fields.citations = citationState;
    const decoded = EditorState.fromJSON(serializedState, {extensions: [historyField, citationState,
      EditorState.allowMultipleSelections.of(true), EditorState.lineSeparator.of("\n")]}, fields);
    if (!jsonEqual(decoded.toJSON(fields), serializedState)) throw historyError();
    const roundtrip = attachInverseEffects(decoded, effects, citationTable, encodedHistory, grouping);
    for (const branch of ["done", "undone"] as const) for (let index = 0; index < history[branch].length; index++) {
      const original = history[branch][index].effects, restored = roundtrip[branch][index].effects;
      if (original.length !== restored.length || original.some((effect, index) => {
        const other = restored[index];
        return effect.is(restoreLineEnding) ? !other.is(restoreLineEnding) || !jsonEqual(effect.value, other.value)
          : !effect.is(setCitationData) || !other.is(setCitationData) || !jsonEqual(effect.value, other.value);
      })) throw historyError();
    }
    validateHistoryBranches(state, roundtrip, state.field(exactSourceState).text);
    const serialized = JSON.stringify({state: serializedState, effects, citationTable, grouping});
    return new TextEncoder().encode(serialized).byteLength <= maximumBytes ? serialized : undefined;
  } catch { return undefined; }
}

export function restoreExactHistory(serialized: string, source: string, extensions: Extension): EditorState {
  if (!exactSourceFits(source)) throw new Error(sourceCapacityMessage);
  if (new TextEncoder().encode(serialized).byteLength > MAX_RECOVERY_HISTORY_BYTES) throw new Error("History is too large");
  const payload = JSON.parse(serialized);
  if (!payload || !ownKeys(payload, ["state", "effects", "citationTable", "grouping"])
      || !payload.state || !payload.state.history || !ownKeys(payload.state.history, ["done", "undone"])
      || !payload.effects || !ownKeys(payload.effects, ["done", "undone"])) throw historyError();
  if (!Array.isArray(payload.citationTable)
      || !payload.citationTable.every((snapshot: unknown) => snapshot === null || validCitationData(snapshot))) throw new Error("Invalid citation history");
  const grouping = checkedGrouping(payload.grouping);
  const fields: Record<string, typeof historyField | typeof citationState> = {history: historyField};
  if (payload.state.citations) fields.citations = citationState;
  const original = EditorState.fromJSON(payload.state, {extensions}, fields);
  if (original.doc.toString() !== normalizedDocumentText(source)) throw new Error("History does not match the recovered source");
  if (!jsonEqual(original.toJSON(fields), payload.state)) throw historyError();
  const history = attachInverseEffects(original, payload.effects, payload.citationTable, payload.state.history, grouping);
  // Public field initialization installs the validated CodeMirror value. No
  // additional field becomes a second owner of text, selections or history.
  const state = EditorState.fromJSON(payload.state, {extensions: [historyField.init(() => history), extensions]},
    payload.state.citations ? {citations: citationState} : undefined)
    .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
  checkedHistory(state);
  if (state.field(exactSourceState).text !== source || !jsonEqual(state.toJSON(fields), payload.state)) throw historyError();
  validateHistoryBranches(state, history, source);
  return state;
}
