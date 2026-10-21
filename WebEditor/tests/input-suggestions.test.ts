import {
  CompletionContext,
  acceptCompletion,
  completionStatus,
  currentCompletions,
  startCompletion,
  type CompletionResult,
  type CompletionSource,
} from "@codemirror/autocomplete";
import {EditorSelection, EditorState, StateEffect, Transaction, type Extension, type TransactionSpec} from "@codemirror/state";
import {EditorView, keymap, type DecorationSet, type WidgetType, type ViewUpdate} from "@codemirror/view";
import {history, undo, redo, undoDepth} from "@codemirror/commands";
import {CompositionRequestGate} from "../composition";
import {scholiumNoteLanguage} from "../language";
import {createLiveProjectionIndexController} from "../live-projection-index";
import {parseHTML} from "linkedom";
import {describe, expect, it, vi} from "vitest";
import {
  createEditorInputSuggestions,
  inputSuggestionTesting,
  safeContinuationSuffix,
  type EditorCitationSuggestionIntent,
  type EditorInputSuggestionActionCompletion,
} from "../input-suggestions";
import {documentFindExtension, performDocumentFind, type DocumentFindRequest} from "../document-find";
import {writingCaretIsReadable} from "../writing-readable-context";
import {localizationTesting} from "../localization";
import type {EditorMode, MarkdownEditingDialect} from "../protocol";
import {exactSourceHistory, exactSourceState, setExactSource} from "../exact-source-history";
import {ExactSourceMirror, normalizedDocumentText} from "../state";

function inlineContinuationHarness(source = "A claim about res", options: {
  composing?: boolean; isComposing?: () => boolean; protectedRanges?: readonly {from: number; to: number}[]; multipleSelections?: boolean;
  find?: boolean; mode?: EditorMode; readOnly?: boolean; editable?: boolean; aiEnabled?: boolean;
  projection?: ReturnType<typeof createLiveProjectionIndexController>; caret?: number; contextReady?: () => boolean; canContinue?: () => boolean;
} = {}) {
  const requests: string[] = [], cancelled: string[] = [], terms: string[] = [], labels: string[] = [], announcements: string[] = [];
  const termQueries: {id: string; kind: string; query: string}[] = [];
  const cancelledTerms: string[] = [];
  const cancellationEvents: {id: string; reason: string}[] = [];
  let state = EditorState.create({doc: normalizedDocumentText(source),
    selection: options.multipleSelections ? EditorSelection.create([EditorSelection.cursor(0), EditorSelection.cursor(normalizedDocumentText(source).length)])
      : {anchor: options.caret ?? normalizedDocumentText(source).length},
    extensions: [history(), exactSourceHistory, EditorState.allowMultipleSelections.of(true),
      ...(options.find ? [documentFindExtension] : []),
      ...(options.readOnly ? [EditorState.readOnly.of(true)] : []),
      ...(options.editable === false ? [EditorView.editable.of(false)] : []),
      ...(options.projection ? [scholiumNoteLanguage, options.projection.extension] : [])]})
    .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
  const suggestions = createEditorInputSuggestions({
    nativeFloating: {show: () => 0, hide: () => {}}, mode: () => options.mode ?? "livePreview",
    dialect: () => dialect, isComposing: () => options.isComposing?.() ?? options.composing ?? false, protectedRanges: () => options.protectedRanges ?? [],
    writingContextReady: options.contextReady,
    canContinueWriting: options.canContinue ?? (options.projection ? (state, position) => writingCaretIsReadable(state, options.projection!.index(state), position) : undefined),
    requestLinkCompletions: (id, kind, query) => { terms.push(id); termQueries.push({id, kind, query}); },
    cancelWritingTermQuery: id => cancelledTerms.push(id),
    requestWritingContinuation: id => { requests.push(id); },
    cancelWritingContinuation: (id, reason) => { cancelled.push(id); cancellationEvents.push({id, reason}); }, didApply: label => labels.push(label),
  });
  state = state.update({effects: StateEffect.appendConfig.of(suggestions.extension),
    annotations: Transaction.addToHistory.of(false)}).state;
  const fixtureDOM = parseHTML("<html><body><div id='editor'><div class='cm-content'></div></div></body></html>");
  const view = {get state() {return state;}, composing: false, hasFocus: true,
    dom: fixtureDOM.document.getElementById("editor"), requestMeasure: () => {},
    dispatch(spec: TransactionSpec) {
      const transaction = state.update(spec);
      for (const effect of transaction.effects) if (effect.is(EditorView.announce)) announcements.push(effect.value);
      state = transaction.state;
    }} as unknown as EditorView;
  // A detached plugin exercises scheduling without pretending to establish WebKit input acceptance.
  const definition = (suggestions.extension as Extension[])[1] as unknown as {create(view: EditorView): {
    decorations: DecorationSet; schedule(): void; clear(): void; accept(): boolean; retry(): boolean; update(update: ViewUpdate): void; destroy(): void;
  }};
  const plugin = definition.create(view);
  suggestions.configureWritingContinuation(options.aiEnabled ?? true, "model-a");
  plugin.schedule();
  return {suggestions, plugin, requests, cancelled, cancellationEvents, cancelledTerms, terms, termQueries, labels, announcements, state: () => state, view};
}

function renderedInlineWidget(decorations: DecorationSet) {
  let widget: WidgetType | undefined;
  let side: number | undefined;
  decorations.between(0, Number.MAX_SAFE_INTEGER, (_from, _to, decoration) => {
    widget = decoration.spec.widget;
    side = decoration.spec.side;
  });
  expect(widget).toBeDefined();
  const {document} = parseHTML("<html><body></body></html>");
  vi.stubGlobal("document", document);
  try { return {node: widget!.toDOM({} as EditorView) as HTMLElement, side}; }
  finally { vi.unstubAllGlobals(); }
}

describe("Coordinated local and AI writing previews", () => {
  function typeSuffix(h: ReturnType<typeof inlineContinuationHarness>, text: string) {
    const transaction = h.state().update({changes: {from: h.state().selection.main.head, insert: text},
      selection: {anchor: h.state().selection.main.head + text.length}, annotations: Transaction.userEvent.of("input.type")});
    h.view.dispatch(transaction);
    h.plugin.update({view: h.view, state: h.state(), startState: transaction.startState,
      changes: transaction.changes, docChanged: true, selectionSet: true, focusChanged: false,
      transactions: [transaction]} as unknown as ViewUpdate);
  }

  it.each([16_384, 1_048_576])("checks writing updates without full source snapshots (%i UTF-16 units)", size => {
    vi.useFakeTimers({toFake: ["setTimeout", "clearTimeout"]});
    const line = "Research 中文 😀 e\u0301.\r\n";
    const source = "\uFEFF" + line.repeat(Math.ceil(size / line.length)) + "A claim about res";
    const h = inlineContinuationHarness(source, {aiEnabled: false});
    const snapshots = vi.spyOn(ExactSourceMirror.prototype, "text", "get");
    try {
      for (const action of ["idle", "caret", "typing"] as const) {
        snapshots.mockClear();
        const samples: number[] = [];
        for (let index = 0; index < 80; index++) {
          const previous = h.state();
          const head = previous.selection.main.head;
          const startedAt = performance.now();
          const transaction = previous.update(action === "typing"
            ? {changes: {from: head, insert: "x"}, selection: {anchor: head + 1}, annotations: Transaction.userEvent.of("input.type")}
            : action === "caret" ? {selection: {anchor: head + (index % 2 === 0 ? -1 : 1)}} : {});
          h.view.dispatch(transaction);
          h.plugin.update({view: h.view, state: h.state(), startState: previous,
            docChanged: transaction.docChanged, selectionSet: transaction.selection !== undefined,
            focusChanged: false, geometryChanged: action === "idle", viewportChanged: action === "idle",
            changes: transaction.changes, transactions: [transaction]} as unknown as ViewUpdate);
          samples.push(performance.now() - startedAt);
        }
        const count = snapshots.mock.calls.length;
        samples.sort((left, right) => left - right);
        if (process.env.SCHOLIUM_WRITING_DIAGNOSTIC === "1") console.log(JSON.stringify({
          metric: "writing-update-proxy", units: "milliseconds", sourceUTF16: source.length, action,
          iterations: samples.length, fullSnapshots: count,
          median: samples[Math.floor(samples.length / 2)], p95: samples[Math.floor(samples.length * 0.95)],
        }));
        expect.soft(count).toBe(0);
      }
      snapshots.mockRestore();
      expect(h.state().field(exactSourceState).text).toBe(source + "x".repeat(80));
      expect(h.state().selection.main.head).toBe(normalizedDocumentText(source).length + 80);
    } finally { snapshots.mockRestore(); h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each([true, false].flatMap(ai => ["pending", "preview"].map(stage => ({ai, stage}))))(
    "retains $stage writing candidates across an equal exact-source reinstall (AI $ai)", async ({ai, stage}) => {
      vi.useFakeTimers();
      const source = "\uFEFFEarlier 😀 e\u0301.\r\nA claim about res";
      const h = inlineContinuationHarness(source, {aiEnabled: ai});
      const snapshots = vi.spyOn(ExactSourceMirror.prototype, "text", "get");
      const publish = async () => {
        if (ai) h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility"});
        else h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{
          label: "responsibility", insertion: "", detail: "", availability: "available",
          writingAction: "term", replacementUTF16Count: 3,
        }]});
        await vi.advanceTimersByTimeAsync(0);
      };
      try {
        await vi.advanceTimersByTimeAsync(800);
        if (stage === "preview") await publish();
        const previous = h.state();
        const transaction = previous.update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)});
        h.view.dispatch(transaction);
        expect(h.state().field(exactSourceState)).not.toBe(previous.field(exactSourceState));
        h.plugin.update({view: h.view, state: h.state(), startState: previous,
          docChanged: false, selectionSet: false, focusChanged: false,
          changes: transaction.changes, transactions: [transaction]} as unknown as ViewUpdate);
        if (stage === "pending") await publish();
        expect(h.cancelled).toEqual([]);
        expect(h.plugin.accept()).toBe(true);
        expect(snapshots).not.toHaveBeenCalled();
        snapshots.mockRestore();
        expect(h.state().field(exactSourceState).text).toBe(source + "ponsibility");
        expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
        expect(h.state().field(exactSourceState).text).toBe(source);
        expect(redo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
        expect(h.state().field(exactSourceState).text).toBe(source + "ponsibility");
      } finally { snapshots.mockRestore(); h.plugin.destroy(); vi.useRealTimers(); }
    });

  it.each((["present", "update", "next"] as const).flatMap(action => [true, false].map(aiEnabled => ({action, aiEnabled}))))(
    "Find $action and save preserve current candidates or reject departed ones (AI $aiEnabled)", async ({action, aiEnabled}) => {
    vi.useFakeTimers();
    const source = "\uFEFFEarlier 😀 e\u0301.\r\nA claim about res";
    const h = inlineContinuationHarness(source, {find: true, aiEnabled});
    const dispatch = h.view.dispatch.bind(h.view);
    h.view.dispatch = (...input: (Transaction | readonly Transaction[] | TransactionSpec)[]) => {
      const first = input[0];
      const transactions: readonly Transaction[] = first instanceof Transaction ? [first]
        : Array.isArray(first) ? first : [h.state().update(...input as TransactionSpec[])];
      for (const transaction of transactions) {
        dispatch(transaction);
        h.plugin.update({view:h.view, state:h.state(), startState:transaction.startState,
          changes:transaction.changes, docChanged:transaction.docChanged,
          selectionSet:transaction.selection !== undefined, focusChanged:false,
          transactions:[transaction]} as unknown as ViewUpdate);
      }
    };
    try {
      await vi.advanceTimersByTimeAsync(800);
      const original = h.state().selection, id = h.requests[0];
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state:"current", candidates:[localResponsibility]});
      await vi.advanceTimersByTimeAsync(0);
      const request: DocumentFindRequest = {query:"claim", replacement:"", caseSensitive:false, wholeWord:false, action};
      performDocumentFind(h.view, request);
      const selected = h.state().selection;
      h.suggestions.configureWritingIndexContext("autosave-find");
      performDocumentFind(h.view, {...request, action:"present"});
      if (aiEnabled) h.suggestions.resolveWritingContinuation(id, {text:"ponsibility is shared."});
      await vi.advanceTimersByTimeAsync(0);
      // Resolve after save validation or after Find has discarded the local round.
      h.suggestions.resolveLinkCompletionQuery(h.terms.at(-1)!, {state:"current", candidates:[localResponsibility]});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.state().field(exactSourceState).text).toBe(source);
      expect(h.state().selection.eq(selected)).toBe(true);
      expect(undoDepth(h.state())).toBe(0);
      expect(h.view.hasFocus).toBe(true);
      if (action === "present") {
        expect(selected.eq(original)).toBe(true);
        expect(h.cancelled).toEqual([]);
        expect(h.requests).toHaveLength(aiEnabled ? 1 : 0);
        expect(h.plugin.accept()).toBe(true);
        expect(h.state().field(exactSourceState).text).toBe(source + (aiEnabled ? "ponsibility is shared." : "ponsibility"));
        expect(undo({state:h.state(), dispatch:transaction => h.view.dispatch(transaction)})).toBe(true);
        expect(h.state().field(exactSourceState).text).toBe(source);
      } else {
        expect(selected.eq(original)).toBe(false);
        if (aiEnabled) expect(h.cancelled).toContain(id);
        expect(h.plugin.decorations.size).toBe(0);
        expect(h.plugin.accept()).toBe(false);
        expect(h.state().field(exactSourceState).text).toBe(source);
        expect(h.state().selection.eq(selected)).toBe(true);
        expect(h.labels).toEqual([]);
      }
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each([
    ["\uFEFFFirst 😀.\r\nA claim about res", "ponsibility is shared.", "pon"],
    ["这个论证仍需", "进一步验证。", "进一步"],
    ["An example ", "🙂 remains useful.", "🙂"],
  ])("consumes matching AI input immediately and Tab/one Undo changes only the remaining suffix: %s", async (original, suffix, typed) => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness(original);
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: suffix});
      await vi.advanceTimersByTimeAsync(0);
      typeSuffix(h, typed);
      expect(renderedInlineWidget(h.plugin.decorations).node.querySelector(".scholium-writing-ghost-text")?.textContent).toBe(suffix.slice(typed.length));
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toHaveLength(1); expect(h.terms).toHaveLength(original.endsWith(" ") ? 0 : 1);
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe(original + suffix);
      expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe(original + typed);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("consumes a confirmed local suffix without another query and dismisses it on mismatching input", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("res", {aiEnabled: false});
    try {
      await vi.advanceTimersByTimeAsync(100);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
        availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
      await vi.advanceTimersByTimeAsync(0);
      typeSuffix(h, "pon");
      expect(renderedInlineWidget(h.plugin.decorations).node.querySelector(".scholium-writing-ghost-text")?.textContent).toBe("sibility");
      expect(h.terms).toHaveLength(1);
      typeSuffix(h, "x");
      expect(h.plugin.decorations.size).toBe(0);
      await vi.advanceTimersByTimeAsync(100);
      expect(h.terms).toHaveLength(2);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });


  it.each([true, false])("retains matching suffix during parser preparation and confirms queued Tab before insertion (readable %s)", async readable => {
    vi.useFakeTimers();
    let ready = true;
    let allowed = true;
    const options = {contextReady: () => ready, canContinue: () => ready && allowed};
    const h = inlineContinuationHarness("A claim about res", options);
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility."});
      await vi.advanceTimersByTimeAsync(0);
      ready = false;
      typeSuffix(h, "pon");
      expect(renderedInlineWidget(h.plugin.decorations).node.querySelector(".scholium-writing-ghost-text")?.textContent).toBe("sibility.");
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().doc.toString()).toBe("A claim about respon");
      ready = true;
      // The production parser may newly identify a protected context.
      if (!readable) {
        allowed = false;
      }
      h.plugin.update({view: h.view, state: h.state(), startState: h.state(), docChanged: false,
        selectionSet: false, focusChanged: false, transactions: []} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(0);
      expect(h.state().doc.toString()).toBe(readable ? "A claim about responsibility." : "A claim about respon");
      expect(h.requests).toHaveLength(1);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each([false, true])("revokes pending and published AI continuation on an Edit/Source transition (published %s)", async published => {
    vi.useFakeTimers();
    const options: {mode: EditorMode} = {mode: "livePreview"};
    const h = inlineContinuationHarness("A claim about res", options);
    try {
      await vi.advanceTimersByTimeAsync(800);
      if (published) {
        h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility."});
        await vi.advanceTimersByTimeAsync(0);
      }
      options.mode = "source";
      h.plugin.update({view: h.view, state: h.state(), startState: h.state(), docChanged: false,
        selectionSet: false, focusChanged: false, transactions: []} as unknown as ViewUpdate);
      expect(h.plugin.decorations.size).toBe(0); expect(h.plugin.accept()).toBe(false);
      if (!published) expect(h.cancelled).toEqual(h.requests);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: " stale."});
      await vi.advanceTimersByTimeAsync(16_000);
      expect(h.terms).toHaveLength(1); expect(h.plugin.decorations.size).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("accepts a provider result after 20 seconds and keeps retry separate from fallback acceptance", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    try {
      await vi.advanceTimersByTimeAsync(20_800);
      expect(h.cancelled).toEqual([]); expect(h.terms).toHaveLength(1);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: null, reason: "Connection failed. Check Agents & Chat."});
      await vi.advanceTimersByTimeAsync(0);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: []});
      await vi.advanceTimersByTimeAsync(0);
      const failure = h.view.dom.querySelector(".scholium-writing-feedback button")!;
      expect(h.plugin.decorations.size).toBe(0);
      expect(failure.textContent).toBe("Retry AI");
      expect(failure.getAttribute("aria-label")).toContain("Option-Return");
      expect(h.plugin.retry()).toBe(true);
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toHaveLength(2);
      h.suggestions.resolveWritingContinuation(h.requests[1], {text: "ponsibility."});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().doc.toString()).toBe("A claim about responsibility.");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each([true, false])("schedules local100ms and AI400ms independently and restarts both on input (AI %s)", async aiEnabled => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("res", {aiEnabled});
    try {
      await vi.advanceTimersByTimeAsync(99); expect(h.terms).toEqual([]); expect(h.requests).toEqual([]);
      await vi.advanceTimersByTimeAsync(1); expect(h.terms).toHaveLength(1); expect(h.requests).toEqual([]);
      typeSuffix(h, "p");
      await vi.advanceTimersByTimeAsync(399);
      expect(h.cancelledTerms).toContain(h.terms[0]); expect(h.terms).toHaveLength(2); expect(h.requests).toEqual([]);
      await vi.advanceTimersByTimeAsync(1); expect(h.requests).toHaveLength(aiEnabled ? 1 : 0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["dismiss", "input", "blur", "composition", "timeout", "departure"])("propagates local query cancellation on %s and rejects late results", async reason => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("A claim about res", {aiEnabled: false});
    try {
      await vi.advanceTimersByTimeAsync(100);
      expect(h.terms).toHaveLength(1);
      const requestID = h.terms[0];
      if (reason === "timeout") await vi.advanceTimersByTimeAsync(5_000);
      else if (reason === "departure") h.suggestions.resetDocument();
      else if (reason === "input") {
        const previous = h.state();
        h.view.dispatch({changes: {from: previous.doc.length, insert: "p"}});
        h.plugin.update({state: h.state(), startState: previous, docChanged: true,
          selectionSet: true, focusChanged: false, transactions: []} as unknown as ViewUpdate);
      } else if (reason === "blur" || reason === "composition") {
        const definition = (h.suggestions.extension as Extension[])[1] as unknown as {
          domEventHandlers: {blur(this: unknown): void; compositionstart(this: unknown): void};
        };
        if (reason === "blur") definition.domEventHandlers.blur.call(h.plugin);
        else definition.domEventHandlers.compositionstart.call(h.plugin);
      } else h.plugin.clear();
      await vi.advanceTimersByTimeAsync(0);
      expect(h.cancelledTerms).toEqual([requestID]);
      const source = h.state().field(exactSourceState).text;
      const historyDepth = undoDepth(h.state());
      h.suggestions.resolveLinkCompletionQuery(requestID, {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
        availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.accept()).toBe(false);
      expect(h.state().field(exactSourceState).text).toBe(source);
      expect(undoDepth(h.state())).toBe(historyDepth);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["livePreview", "source"] as const)("requests local immediately in headings while AI runs independently in %s", async mode => {
    vi.useFakeTimers();
    try {
      for (const source of ["# Unfinished res", "Unfinished res\n==="]) {
        const projection = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
        const caret = source.indexOf("res") + 3;
        const h = inlineContinuationHarness(source, {mode, projection, caret});
        try {
          await vi.advanceTimersByTimeAsync(800);
          expect(h.requests).toHaveLength(1);
          expect(h.terms).toHaveLength(1);
          h.suggestions.resolveWritingContinuation(h.requests[0], {text: null});
          await vi.advanceTimersByTimeAsync(0);
          expect(h.terms).toHaveLength(1);
          h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
            availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
          await vi.advanceTimersByTimeAsync(0);
          expect(h.plugin.accept()).toBe(true);
          expect(h.state().field(exactSourceState).text).toBe(source.replace("res", "responsibility"));
          expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
          expect(h.state().field(exactSourceState).text).toBe(source);
        } finally { h.plugin.destroy(); }
      }
    } finally { vi.useRealTimers(); }
  });
  it.each(["livePreview", "source"] as const)("accepts a multiword local suffix from heading and AI-off prose in %s", async mode => {
    vi.useFakeTimers();
    const typed = "Manual Heading Completion T";
    const label = "Manual Heading Completion Target";
    try {
      for (const prefix of ["# ", "A claim about "]) {
        const source = "\uFEFFEarlier 😀.\r\n" + prefix + typed;
        const projection = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
        const h = inlineContinuationHarness(source, {mode, projection, aiEnabled: false});
        try {
          await vi.advanceTimersByTimeAsync(100);
          expect(h.requests).toEqual([]);
          expect(h.termQueries).toHaveLength(1);
          expect(h.termQueries[0].kind).toBe("term");
          expect(h.termQueries[0].query).toBe(prefix === "# " ? " " + typed : prefix + typed);
          h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label, insertion: label, detail: "",
            availability: "available", writingAction: "term", replacementUTF16Count: typed.length}]});
          await vi.advanceTimersByTimeAsync(0);
          const ghost = renderedInlineWidget(h.plugin.decorations);
          expect(ghost.node.querySelector(".scholium-writing-ghost-text")?.textContent).toBe("arget");
          expect(ghost.node.querySelector(".scholium-writing-ghost-key")?.textContent).toBe("Index ⇥");
          expect(h.state().field(exactSourceState).text).toBe(source);
          expect(undoDepth(h.state())).toBe(0);
          expect(h.plugin.accept()).toBe(true);
          expect(h.state().field(exactSourceState).text).toBe(source + "arget");
          expect(undoDepth(h.state())).toBe(1);
          expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
          expect(h.state().field(exactSourceState).text).toBe(source);
          expect(redo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
          expect(h.state().field(exactSourceState).text).toBe(source + "arget");
        } finally { h.plugin.destroy(); }
      }
    } finally { vi.useRealTimers(); }
  });

  it.each([true, false])("resumes writing only after the shared IME gate commits final source (AI %s)", async aiEnabled => {
    vi.useFakeTimers();
    const gate = new CompositionRequestGate<{expiresAt: number}, boolean>(() => false);
    gate.begin();
    const revision = gate.revision("editor");
    const original = "\uFEFFEarlier 😀.\r\n论证尚需";
    const h = inlineContinuationHarness(original, {aiEnabled, isComposing: () => gate.active});
    try {
      // compositionend precedes the shared gate's final-input task.
      h.plugin.schedule();
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
      const from = h.state().doc.length;
      const transaction = h.state().update({changes: {from, insert: "解释"}, selection: {anchor: from + 2},
        annotations: Transaction.userEvent.of("input.type.compose")});
      h.view.dispatch(transaction);
      h.plugin.update({view: h.view, state: h.state(), startState: transaction.startState,
        changes: transaction.changes, docChanged: true, selectionSet: true, focusChanged: false,
        viewportChanged: false, viewportMoved: false, heightChanged: false, geometryChanged: true,
        transactions: [transaction]});
      expect(h.state().field(exactSourceState).text).toBe(original + "解释");
      expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
      const depth = undoDepth(h.state());
      gate.finish("editor", revision);
      h.suggestions.resumeWritingAfterComposition();
      const delay = aiEnabled ? 400 : 100;
      await vi.advanceTimersByTimeAsync(delay - 1);
      expect(h.requests).toEqual([]); expect(h.terms).toHaveLength(aiEnabled ? 1 : 0);
      await vi.advanceTimersByTimeAsync(1);
      expect(h.requests).toHaveLength(aiEnabled ? 1 : 0);
      expect(h.terms).toHaveLength(1);
      expect(h.state().field(exactSourceState).text).toBe(original + "解释");
      expect(undoDepth(h.state())).toBe(depth);
      if (aiEnabled) h.suggestions.resolveWritingContinuation(h.requests[0], {text: "其适用范围。"});
      else h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "解释性", insertion: "", detail: "",
        availability: "available", writingAction: "term", replacementUTF16Count: 2}]});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.accept()).toBe(true);
      const accepted = original + "解释" + (aiEnabled ? "其适用范围。" : "性");
      expect(h.state().field(exactSourceState).text).toBe(accepted);
      expect(undoDepth(h.state())).toBe(depth + 1);
      expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe(original + "解释");
      expect(redo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe(accepted);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("rejects composition resumption while another composition, blur or teardown owns the editor", async () => {
    vi.useFakeTimers();
    const gate = new CompositionRequestGate<{expiresAt: number}, boolean>(() => false);
    gate.begin();
    const revision = gate.revision("editor");
    const h = inlineContinuationHarness("未完成的论证", {isComposing: () => gate.active});
    try {
      gate.begin(); // A stale compositionend must not release this newer input.
      gate.finish("editor", revision);
      h.suggestions.resumeWritingAfterComposition();
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toEqual([]);
      gate.finish();
      Object.defineProperty(h.view, "hasFocus", {value: false, configurable: true});
      h.suggestions.resumeWritingAfterComposition();
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toEqual([]);
      Object.defineProperty(h.view, "hasFocus", {value: true});
      h.plugin.destroy();
      h.suggestions.resumeWritingAfterComposition();
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
      expect(h.state().field(exactSourceState).text).toBe("未完成的论证");
      expect(undoDepth(h.state())).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });
  it("rejects a visible ghost as soon as composition starts before its first text change", async () => {
    vi.useFakeTimers();
    const options = {composing: false, aiEnabled: false};
    const h = inlineContinuationHarness("res", options);
    await vi.advanceTimersByTimeAsync(100);
    expect(h.terms).toHaveLength(1);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "",
      detail: "", availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(1);
    options.composing = true;
    expect(h.view.composing).toBe(false);
    expect(h.plugin.accept()).toBe(false);
    expect(h.state().doc.toString()).toBe("res");
    h.plugin.clear();
    vi.useRealTimers();
  });
  it("permits short AI continuation after completed readable sentences", async () => {
    vi.useFakeTimers();
    try {
      for (const source of ["A completed claim. ", "A completed claim。", "A completed claim.”"]) {
        const h = inlineContinuationHarness(source);
        await vi.advanceTimersByTimeAsync(800);
        expect(h.requests).toHaveLength(1);
        expect(h.terms).toEqual([]);
        h.plugin.destroy();
      }
    } finally { vi.useRealTimers(); }
  });

  it("keeps local requests independent and accepts a validated AI suffix in one Undo, and accepts one exact Undo event", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("\uFEFFFirst 😀.\r\nA claim about res");
    await vi.advanceTimersByTimeAsync(399);
    expect(h.requests).toEqual([]); expect(h.terms).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(h.requests).toHaveLength(1); expect(h.terms).toHaveLength(1);
    h.suggestions.configureWritingIndexContext("catalog-1");
    expect(h.cancelled).toEqual([]);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility needs qualification."});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(1);
    const ai = renderedInlineWidget(h.plugin.decorations);
    expect(ai.node.querySelector(".scholium-writing-ghost-key")?.textContent).toBe("AI ⇥");
    expect(ai.node.getAttribute("aria-label")).toContain("Accept AI continuation:");
    h.suggestions.configureWritingIndexContext("catalog-2");
    expect(h.plugin.decorations.size).toBe(1);
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().field(exactSourceState).text).toBe("\uFEFFFirst 😀.\r\nA claim about responsibility needs qualification.");
    expect(h.labels).toEqual(["Accept AI Continuation"]);
    expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
    expect(h.state().field(exactSourceState).text).toBe("\uFEFFFirst 😀.\r\nA claim about res");
    vi.useRealTimers();
  });

  it.each(["en", "zh-Hans"] as const)("announces %s progress outside content and exposes failure recovery outside caret decorations without changing source", async languageTag => {
    vi.useFakeTimers();
    const chinese = languageTag === "zh-Hans";
    const phases = [
      {phase: "preparing", label: "Preparing", full: "AI continuation is preparing.", zhLabel: "准备中", zhFull: "AI 续写准备中。"},
      {phase: "retrieving", label: "Retrieving", full: "AI continuation is retrieving related context.", zhLabel: "检索中", zhFull: "AI 续写正在检索相关上下文。"},
      {phase: "generating", label: "Composing", full: "AI continuation is composing.", zhLabel: "续写中", zhFull: "AI 续写正在组织句子。"},
    ] as const;
    localizationTesting.install({languageTag, strings: Object.fromEntries(phases.flatMap(value => [
      [value.label, chinese ? value.zhLabel : value.label], [value.full, chinese ? value.zhFull : value.full],
    ]))});
    const original = "\uFEFFFirst 😀.\r\nA claim about res";
    const h = inlineContinuationHarness(original);
    try {
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toHaveLength(1);
      for (const [index, value] of phases.entries()) {
        if (index > 0) h.suggestions.setWritingContinuationStatus(h.requests[0], {phase: value.phase});
        expect(h.plugin.decorations.size).toBe(0);
        expect(h.announcements.at(-1)).toBe(chinese ? value.zhFull : value.full);
        expect(h.view.dom.querySelector(".cm-content .scholium-writing-status")).toBeNull();
        expect(h.state().field(exactSourceState).text).toBe(original);
        expect(undoDepth(h.state())).toBe(0);
      }
      const reason = chinese ? "AI 续写无法连接。请检查“智能体与聊天”。" : "AI continuation could not connect. Check Agents & Chat.";
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: null, reason});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.terms).toHaveLength(1);
      expect(h.plugin.decorations.size).toBe(0);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: []});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.accept()).toBe(false);
      const error = h.view.dom.querySelector(".scholium-writing-feedback")!;
      expect(error.querySelector(".scholium-writing-feedback-message")?.textContent).toBe(reason);
      expect(error.getAttribute("role")).toBe("status");
      expect(error.getAttribute("aria-live")).toBe("polite");
      expect(error.querySelector("button")?.getAttribute("aria-label")).toContain(reason);
      expect(h.plugin.decorations.size).toBe(0);
      expect(h.state().field(exactSourceState).text).toBe(original);
      expect(undoDepth(h.state())).toBe(0);
    } finally { h.plugin.destroy(); localizationTesting.reset(); vi.useRealTimers(); }
  });


  it("restores the original three dots after the caret only during generation, outside text layout", async () => {
    vi.useFakeTimers();
    const original = "\uFEFFFirst 😀.\r\n# Argument res";
    const h = inlineContinuationHarness(original);
    try {
      await vi.advanceTimersByTimeAsync(400);
      const id = h.requests[0];
      expect(h.view.dom.querySelector(".scholium-writing-activity")).toBeNull();
      h.suggestions.setWritingContinuationStatus(id, {phase: "retrieving"});
      expect(h.view.dom.querySelector(".scholium-writing-activity")).toBeNull();
      h.suggestions.setWritingContinuationStatus(id, {phase: "generating"});
      const activity = h.view.dom.querySelector(".scholium-writing-activity")!;
      expect(activity).not.toBeNull();
      expect(activity.parentElement).toBe(h.view.dom);
      expect(h.view.dom.querySelector(".cm-content")!.contains(activity)).toBe(false);
      expect(activity.querySelectorAll(".scholium-writing-orb-dot")).toHaveLength(3);
      expect(activity.getAttribute("aria-hidden")).toBe("true");
      expect(activity.querySelector("button, [tabindex]")).toBeNull();
      expect(h.plugin.decorations.size).toBe(0);
      h.suggestions.setWritingContinuationStatus(id, {phase: "preparing"});
      expect(h.view.dom.querySelector(".scholium-writing-activity")).toBe(activity);
      expect(h.announcements.at(-1)).toBe("AI continuation is composing.");
      expect(h.state().field(exactSourceState).text).toBe(original);
      expect(undoDepth(h.state())).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["suggestion", "empty", "error", "parserPending"])("removes the generation dots on %s before publishing a suffix or fallback", async outcome => {
    vi.useFakeTimers();
    let ready = true;
    const h = inlineContinuationHarness(undefined, {contextReady: () => ready});
    try {
      await vi.advanceTimersByTimeAsync(400);
      h.suggestions.setWritingContinuationStatus(h.requests[0], {phase: "generating"});
      expect(h.view.dom.querySelector(".scholium-writing-activity")).not.toBeNull();
      ready = outcome !== "parserPending";
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: outcome === "suggestion" || outcome === "parserPending" ? "ponsibility." : null,
        reason: outcome === "error" ? "AI continuation timed out." : null});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.view.dom.querySelector(".scholium-writing-activity")).toBeNull();
      if (outcome === "suggestion") expect(renderedInlineWidget(h.plugin.decorations).node.dataset.source).toBe("ai");
      expect(h.state().field(exactSourceState).text).toBe("A claim about res");
      expect(undoDepth(h.state())).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["reset", "configuration", "focus", "composition", "clear", "destroy", "watchdog"])("removes the generation dots immediately on %s and ignores late status", async ending => {
    vi.useFakeTimers();
    let composing = false;
    const h = inlineContinuationHarness(undefined, {isComposing: () => composing});
    try {
      await vi.advanceTimersByTimeAsync(400);
      const id = h.requests[0];
      h.suggestions.setWritingContinuationStatus(id, {phase: "generating"});
      expect(h.view.dom.querySelector(".scholium-writing-activity")).not.toBeNull();
      if (ending === "reset") h.suggestions.resetDocument();
      else if (ending === "configuration") h.suggestions.configureWritingContinuation(false, "disabled");
      else if (ending === "destroy") h.plugin.destroy();
      else if (ending === "watchdog") await vi.advanceTimersByTimeAsync(35_000);
      else if (ending === "focus" || ending === "composition") {
        if (ending === "focus") Object.assign(h.view, {hasFocus: false});
        else composing = true;
        h.plugin.update({state:h.state(), startState:h.state(), docChanged:false, selectionSet:false,
          focusChanged:ending === "focus", transactions:[]} as unknown as ViewUpdate);
      } else h.plugin.clear();
      expect(h.view.dom.querySelector(".scholium-writing-activity")).toBeNull();
      h.suggestions.setWritingContinuationStatus(id, {phase: "generating"});
      expect(h.view.dom.querySelector(".scholium-writing-activity")).toBeNull();
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("measures the dots with the same wrap affinity and scale as the caret, and discards stale measures", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    const measures: NonNullable<Parameters<EditorView["requestMeasure"]>[0]>[] = [];
    const point = {left:180, right:180, top:120, bottom:160};
    const bounds = {left:100, right:700, top:80, bottom:600};
    const coords = vi.fn(() => point);
    Object.assign(h.view, {coordsAtPos:coords, scrollDOM:h.view.dom, scaleX:2, scaleY:2});
    Object.defineProperty(h.view.dom, "getBoundingClientRect", {value:() => bounds});
    vi.spyOn(h.view, "requestMeasure").mockImplementation(request => {if (request) measures.push(request);});
    try {
      await vi.advanceTimersByTimeAsync(400);
      const first = h.requests[0];
      h.suggestions.setWritingContinuationStatus(first, {phase:"generating"});
      const activity = h.view.dom.querySelector<HTMLElement>(".scholium-writing-activity")!;
      const measure = measures.at(-1)!;
      expect(measure).toBeDefined();
      measure.write?.(measure.read(h.view), h.view);
      expect(coords).toHaveBeenCalledWith(h.state().selection.main.head, h.state().selection.main.assoc || 1);
      expect(parseFloat(activity.style.left)).toBeGreaterThan((point.left - bounds.left) / 2);
      expect(parseFloat(activity.style.top)).toBeGreaterThanOrEqual((point.top - bounds.top) / 2);
      expect(parseFloat(activity.style.top)).toBeLessThan((point.bottom - bounds.top) / 2);
      expect(activity.style.visibility).toBe("visible");
      point.left = 670; point.right = 670;
      measure.write?.(measure.read(h.view), h.view);
      expect(activity.style.visibility).toBe("visible");
      expect(bounds.left + parseFloat(activity.style.left) * 2 + parseFloat(activity.style.fontSize) * 1.2 * 2).toBeLessThanOrEqual(bounds.right);
      point.left = 698; point.right = 698;
      measure.write?.(measure.read(h.view), h.view);
      expect(activity.style.visibility).toBe("hidden");
      point.left = 180; point.right = 180;
      point.top = 650; point.bottom = 690;
      measure.write?.(measure.read(h.view), h.view);
      expect(activity.style.visibility).toBe("hidden");
      const delayed = measure.read(h.view);
      h.plugin.schedule();
      await vi.advanceTimersByTimeAsync(400);
      h.suggestions.setWritingContinuationStatus(h.requests[1], {phase:"generating"});
      const successor = h.view.dom.querySelector(".scholium-writing-activity");
      measure.write?.(delayed, h.view);
      h.suggestions.setWritingContinuationStatus(first, {phase:"generating"});
      expect(successor).not.toBe(activity);
      expect(h.view.dom.querySelector(".scholium-writing-activity")).toBe(successor);
      expect(h.view.dom.querySelectorAll(".scholium-writing-activity")).toHaveLength(1);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("keeps preparation time separate from the generation watchdog", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.setWritingContinuationStatus(h.requests[0], {phase: "retrieving"});
      await vi.advanceTimersByTimeAsync(29_000);
      h.suggestions.setWritingContinuationStatus(h.requests[0], {phase: "generating"});
      await vi.advanceTimersByTimeAsync(20_000);
      expect(h.cancelled).toEqual([]); expect(h.terms).toHaveLength(1);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility."});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().doc.toString()).toBe("A claim about responsibility.");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("repeated generation status cannot extend a stalled request indefinitely", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.setWritingContinuationStatus(h.requests[0], {phase: "generating"});
      await vi.advanceTimersByTimeAsync(34_000);
      h.suggestions.setWritingContinuationStatus(h.requests[0], {phase: "generating"});
      await vi.advanceTimersByTimeAsync(1_000);
      expect(h.cancelled).toEqual(h.requests); expect(h.terms).toHaveLength(1);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: " stale."});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.accept()).toBe(false);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("falls back after timeout and ignores the late AI response", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    await vi.advanceTimersByTimeAsync(100);
    expect(h.requests).toEqual([]); expect(h.terms).toHaveLength(1);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
      availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
    await vi.advanceTimersByTimeAsync(0);
    await vi.advanceTimersByTimeAsync(35_700);
    expect(h.cancelled).toEqual(h.requests);
    expect(h.view.dom.querySelector(".scholium-writing-feedback")).not.toBeNull();
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: "different sentence."});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().doc.toString()).toBe("A claim about responsibility");
    vi.useRealTimers();
  });

  it("retains local Source prediction with off-content failure recovery", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("A claim about res", {mode: "source"});
    await vi.advanceTimersByTimeAsync(800);
    expect(h.requests).toHaveLength(1); expect(h.terms).toHaveLength(1);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: null, reason: "Offline"});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.terms).toHaveLength(1);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
      availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
    await vi.advanceTimersByTimeAsync(0);
    const fallback = renderedInlineWidget(h.plugin.decorations);
    expect(fallback.node.querySelectorAll(".scholium-writing-status")).toHaveLength(0);
    expect(fallback.node.querySelectorAll(".scholium-writing-retry")).toHaveLength(0);
    expect(h.view.dom.querySelectorAll(".scholium-writing-retry")).toHaveLength(1);
    expect(fallback.node.querySelector(".scholium-writing-ghost-key")?.textContent).toBe("Index ⇥");
    expect(fallback.node.getAttribute("aria-label")).toContain("Accept index suggestion:");
    expect(h.view.dom.querySelector(".scholium-writing-feedback-message")?.textContent).toBe("Offline");
    expect(h.plugin.decorations.size).toBe(1);
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().doc.toString()).toBe("A claim about responsibility");
    vi.useRealTimers();
  });

  it("uses the index when AI is off, with no AI request or failure badge", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("A claim about res", {aiEnabled: false});
    await vi.advanceTimersByTimeAsync(99);
    expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
    await vi.advanceTimersByTimeAsync(1);
    expect(h.terms).toHaveLength(1);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
      availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
    await vi.advanceTimersByTimeAsync(0);
    const ghost = renderedInlineWidget(h.plugin.decorations);
    expect(ghost.node.querySelector(".scholium-writing-ghost-key")?.textContent).toBe("Index ⇥");
    expect(ghost.node.querySelector(".scholium-writing-retry")).toBeNull();
    expect(h.plugin.accept()).toBe(true);
    expect(h.state().doc.toString()).toBe("A claim about responsibility");
    vi.useRealTimers();
  });

  it("keeps a quiet AI absence quiet through empty index fallback", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    await vi.advanceTimersByTimeAsync(800);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: null, reason: ""});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.terms).toHaveLength(1);
    expect(h.plugin.decorations.size).toBe(0);
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: []});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(0);
    expect(h.plugin.accept()).toBe(false);
    vi.useRealTimers();
  });

  it("discards an old index result on catalog change", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    await vi.advanceTimersByTimeAsync(800);
    h.suggestions.resolveWritingContinuation(h.requests[0], {text: null, reason: ""});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.terms).toHaveLength(1);
    h.suggestions.configureWritingIndexContext("catalog-2");
    h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
      availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
    await vi.advanceTimersByTimeAsync(0);
    expect(h.plugin.decorations.size).toBe(0);
    expect(h.plugin.accept()).toBe(false);
    vi.useRealTimers();
  });

  it.each([false, true])("resumes only the retained input when parser context becomes ready (dismissed %s)", async dismissed => {
    vi.useFakeTimers();
    let ready = false;
    const h = inlineContinuationHarness("# Unfinished res", {contextReady: () => ready});
    try {
      await vi.advanceTimersByTimeAsync(2_000);
      expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
      if (dismissed) h.plugin.clear();
      ready = true;
      const previous = h.state();
      const transaction = previous.update({effects: StateEffect.define<boolean>().of(true)});
      h.view.dispatch(transaction);
      const update = {state: h.state(), startState: previous, changes: transaction.changes, docChanged: false, selectionSet: false,
        focusChanged: false, transactions: [transaction]} as unknown as ViewUpdate;
      h.plugin.update(update);
      h.plugin.update(update);
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toHaveLength(dismissed ? 0 : 1);
      expect(h.terms).toHaveLength(dismissed ? 0 : 1);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each([false, true])("retains and validates the same preview after repeated catalog publication (heading %s)", async heading => {
    vi.useFakeTimers();
    const original = "\uFEFFEarlier 😀.\r\n" + (heading ? "# " : "A claim about ") + "Manual Heading Completion T";
    const projection = createLiveProjectionIndexController({editingDialect: () => dialect, recordMetric: () => {}});
    const h = inlineContinuationHarness(original, {projection, aiEnabled: false});
    const candidate = {label: "Manual Heading Completion Target", insertion: "", detail: "",
      availability: "available", writingAction: "term", replacementUTF16Count: 27};
    try {
      await vi.advanceTimersByTimeAsync(100);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [candidate]});
      await vi.advanceTimersByTimeAsync(0);
      const originalDecoration = h.plugin.decorations;
      for (const catalog of ["autosave", "source-commit", "publication"]) {
        h.suggestions.configureWritingIndexContext(catalog);
        expect(h.plugin.decorations).toBe(originalDecoration);
        await vi.advanceTimersByTimeAsync(0);
        h.suggestions.resolveLinkCompletionQuery(h.terms.at(-1)!, {state: "current", candidates: [candidate]});
        await vi.advanceTimersByTimeAsync(0);
        expect(h.plugin.decorations).toBe(originalDecoration);
      }
      expect(h.requests).toEqual([]);
      expect(h.state().field(exactSourceState).text).toBe(original);
      expect(undoDepth(h.state())).toBe(0);
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe(original + "arget");
      expect(undoDepth(h.state())).toBe(1);
      expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe(original);
      expect(redo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe(original + "arget");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("keeps the mounted CodeMirror ghost node through autosave publications and unavailable validation", async () => {
    vi.useFakeTimers();
    const {document, window} = parseHTML("<html><head></head><body><div id='editor'></div></body></html>");
    vi.stubGlobal("document", document);
    vi.stubGlobal("window", window);
    vi.stubGlobal("MutationObserver", window.MutationObserver);
    // This DOM test deliberately performs no geometry or native event simulation.
    vi.stubGlobal("requestAnimationFrame", () => 1);
    vi.stubGlobal("cancelAnimationFrame", () => {});
    Object.defineProperty(document, "getSelection", {value: () => null});
    Object.defineProperty(document, "hasFocus", {value: () => false});
    const ids: string[] = [], failures: unknown[] = [];
    const suggestions = createEditorInputSuggestions({
      nativeFloating: {show: () => 0, hide: () => {}}, mode: () => "source", dialect: () => dialect,
      isComposing: () => false, protectedRanges: () => [], requestLinkCompletions: id => ids.push(id), didApply: () => {},
    });
    let view: EditorView | undefined;
    try {
      view = new EditorView({parent: document.getElementById("editor")!, state: EditorState.create({
        doc: "A claim about re", selection: {anchor: 16},
        extensions: [history(), exactSourceHistory, suggestions.extension, EditorView.exceptionSink.of(error => failures.push(error))],
      })});
      Object.defineProperty(view, "hasFocus", {get: () => true});
      // Geometry belongs to native QA; the native popup idle read is disjoint from ghost DOM identity.
      view.coordsAtPos = () => null;
      view.dispatch({changes: {from: 16, insert: "s"}, selection: {anchor: 17}, annotations: Transaction.userEvent.of("input.type")});
      await vi.advanceTimersByTimeAsync(100);
      const candidate = {label: "responsibility", insertion: "", detail: "", availability: "available", writingAction: "term", replacementUTF16Count: 3};
      suggestions.resolveLinkCompletionQuery(ids[0], {state: "current", candidates: [candidate]});
      await vi.advanceTimersByTimeAsync(0);
      const node = view.contentDOM.querySelector(".scholium-writing-ghost");
      expect(node).not.toBeNull();
      for (const [key, current] of [["autosave", true], ["index-loading", false], ["index-current", true]] as const) {
        suggestions.configureWritingIndexContext(key);
        expect(view.contentDOM.querySelector(".scholium-writing-ghost")).toBe(node);
        await vi.advanceTimersByTimeAsync(0);
        suggestions.resolveLinkCompletionQuery(ids.at(-1)!, {state: current ? "current" : "unavailable", candidates: current ? [candidate] : []});
        await vi.advanceTimersByTimeAsync(0);
        expect(view.contentDOM.querySelector(".scholium-writing-ghost")).toBe(node);
        expect(node?.textContent).toContain("ponsibility");
      }
      expect(view.state.doc.toString()).toBe("A claim about res");
      expect(failures).toEqual([]);
      suggestions.configureWritingIndexContext("confirmed-deleted");
      await vi.advanceTimersByTimeAsync(0);
      suggestions.resolveLinkCompletionQuery(ids.at(-1)!, {state: "current", candidates: []});
      await vi.advanceTimersByTimeAsync(0);
      expect(view.contentDOM.querySelector(".scholium-writing-ghost")).toBeNull();
      expect(failures).toEqual([]);
    } finally { view?.destroy(); vi.unstubAllGlobals(); vi.useRealTimers(); }
  });

  it.each(["same", "different", "deleted", "unavailable", "timeout"])("queues one acceptance while refreshing and handles %s without stale insertion", async outcome => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("A claim about res", {aiEnabled: false});
    const candidate = {label: "responsibility", insertion: "", detail: "",
      availability: "available", writingAction: "term", replacementUTF16Count: 3};
    try {
      await vi.advanceTimersByTimeAsync(100);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [candidate]});
      await vi.advanceTimersByTimeAsync(0);
      const visible = h.plugin.decorations;
      h.suggestions.configureWritingIndexContext("refresh");
      expect(h.plugin.accept()).toBe(true);
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().doc.toString()).toBe("A claim about res");
      expect(h.plugin.decorations).toBe(visible);
      await vi.advanceTimersByTimeAsync(0);
      if (outcome === "timeout") await vi.advanceTimersByTimeAsync(5_000);
      else h.suggestions.resolveLinkCompletionQuery(h.terms[1], outcome === "unavailable" ? {state: "unavailable", candidates: []}
        : {state: "current", candidates: outcome === "deleted" ? []
          : [{...candidate, label: outcome === "different" ? "research" : candidate.label}]});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.state().doc.toString()).toBe(outcome === "same" ? "A claim about responsibility" : "A claim about res");
      expect(h.labels).toEqual(outcome === "same" ? ["Complete Term"] : []);
      expect(undoDepth(h.state())).toBe(outcome === "same" ? 1 : 0);
      if (outcome === "unavailable" || outcome === "timeout") {
        expect(h.plugin.decorations).toBe(visible);
        expect(h.plugin.accept()).toBe(true); // explicit retry, no stale insertion
        await vi.advanceTimersByTimeAsync(0);
        expect(h.terms).toHaveLength(3);
        expect(h.state().doc.toString()).toBe("A claim about res");
      }
      expect(h.requests).toEqual([]);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["dismiss", "blur", "composition", "selection", "input", "exact-source", "AI-enabled", "departure"])(
    "cancels a queued refreshed acceptance on %s", async reason => {
      vi.useFakeTimers();
      const h = inlineContinuationHarness("Earlier.\nA claim about res", {aiEnabled: false});
      const candidate = {label: "responsibility", insertion: "", detail: "", availability: "available", writingAction: "term", replacementUTF16Count: 3};
      try {
        await vi.advanceTimersByTimeAsync(100);
        h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [candidate]});
        await vi.advanceTimersByTimeAsync(0);
        h.suggestions.configureWritingIndexContext("refreshing");
        expect(h.plugin.accept()).toBe(true);
        await vi.advanceTimersByTimeAsync(0);
        const id = h.terms[1];
        if (reason === "departure") h.suggestions.resetDocument();
        else if (reason === "AI-enabled") h.suggestions.configureWritingContinuation(true, "model-a");
        else if (reason === "selection" || reason === "input" || reason === "exact-source") {
          const previous = h.state();
          const transaction = previous.update(reason === "selection" ? {selection: {anchor: 0}}
            : reason === "input" ? {changes: {from: previous.doc.length, insert: "x"}, selection: {anchor: previous.doc.length + 1},
              annotations: Transaction.userEvent.of("input.type")}
            : {effects: setExactSource.of("Earlier.\r\nA claim about res"), annotations: Transaction.addToHistory.of(false)});
          h.view.dispatch(transaction);
          h.plugin.update({state: h.state(), startState: previous, changes: transaction.changes, docChanged: transaction.docChanged,
            selectionSet: transaction.selection !== undefined, focusChanged: false, transactions: [transaction]} as unknown as ViewUpdate);
        } else if (reason === "blur" || reason === "composition") {
          const definition = (h.suggestions.extension as Extension[])[1] as unknown as {
            domEventHandlers: {blur(this: unknown): void; compositionstart(this: unknown): void};
          };
          (reason === "blur" ? definition.domEventHandlers.blur : definition.domEventHandlers.compositionstart).call(h.plugin);
        } else h.plugin.clear();
        const source = h.state().field(exactSourceState).text;
        h.suggestions.resolveLinkCompletionQuery(id, {state: "current", candidates: [candidate]});
        await vi.advanceTimersByTimeAsync(800);
        expect(h.state().field(exactSourceState).text).toBe(source);
        expect(h.labels).toEqual([]);
        expect(h.cancelledTerms).toContain(id);
      } finally { h.plugin.destroy(); vi.useRealTimers(); }
    });

  it.each([false, true])("keeps the preview through an unchanged selection transaction (AI %s)", async aiEnabled => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("A claim about res", {aiEnabled});
    try {
      await vi.advanceTimersByTimeAsync(aiEnabled ? 800 : 100);
      if (aiEnabled) h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility"});
      else h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
        availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.decorations.size).toBe(1);
      const previous = h.state();
      const transaction = previous.update({selection: previous.selection});
      expect(transaction.selection).toBeDefined();
      h.view.dispatch(transaction);
      h.plugin.update({state: h.state(), startState: previous, changes: transaction.changes, docChanged: false,
        selectionSet: true, focusChanged: false, transactions: [transaction]} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(2_000);
      expect(h.plugin.decorations.size).toBe(1);
      expect(h.terms).toHaveLength(1);
      expect(h.requests).toHaveLength(aiEnabled ? 1 : 0);
      expect(undoDepth(h.state())).toBe(0);
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe("A claim about responsibility");
      expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe("A claim about res");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("removes a local suffix whose candidate disappeared from the new catalog", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness("A claim about res", {aiEnabled: false});
    try {
      await vi.advanceTimersByTimeAsync(100);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
        availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.decorations.size).toBe(1);
      h.suggestions.configureWritingIndexContext("candidate-deleted");
      expect(h.plugin.accept()).toBe(true);
      await vi.advanceTimersByTimeAsync(0);
      expect(h.terms).toHaveLength(2);
      h.suggestions.resolveLinkCompletionQuery(h.terms[1], {state: "current", candidates: []});
      await vi.advanceTimersByTimeAsync(2_000);
      expect(h.requests).toEqual([]);
      expect(h.plugin.decorations.size).toBe(0);
      expect(h.plugin.accept()).toBe(false);
      expect(h.state().field(exactSourceState).text).toBe("A claim about res");
      expect(undoDepth(h.state())).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("refreshes an AI fallback locally while retaining the failure reason", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    const reason = "The provider is unavailable.";
    try {
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toHaveLength(1);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: null, reason});
      await vi.advanceTimersByTimeAsync(0);
      const first = h.terms[0];
      h.suggestions.configureWritingIndexContext("new-catalog");
      await vi.advanceTimersByTimeAsync(0);
      expect(h.terms).toHaveLength(2);
      expect(h.cancelledTerms).toEqual([first]);
      h.suggestions.resolveLinkCompletionQuery(h.terms[1], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
        availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
      await vi.advanceTimersByTimeAsync(2_000);
      expect(h.requests).toHaveLength(1);
      const ghost = renderedInlineWidget(h.plugin.decorations);
      expect(ghost.node.querySelector(".scholium-writing-ghost-key")?.textContent).toBe("Index ⇥");
      expect(h.view.dom.querySelector(".scholium-writing-feedback-message")?.textContent).toBe(reason);
      expect(ghost.node.querySelector(".scholium-writing-retry")).toBeNull();
      expect(h.view.dom.querySelector(".scholium-writing-retry")).not.toBeNull();
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["dismiss", "blur", "composition", "selection", "departure", "destroy"])(
    "does not revive refreshed local completion after %s", async reason => {
      vi.useFakeTimers();
      const h = inlineContinuationHarness("A claim about res", {aiEnabled: false});
      try {
        await vi.advanceTimersByTimeAsync(100);
        h.suggestions.configureWritingIndexContext("refreshing");
        await vi.advanceTimersByTimeAsync(0);
        expect(h.terms).toHaveLength(2);
        const fresh = h.terms[1];
        if (reason === "departure") h.suggestions.resetDocument();
        else if (reason === "destroy") h.plugin.destroy();
        else if (reason === "selection") {
          const previous = h.state();
          const transaction = previous.update({selection: {anchor: 0}});
          h.view.dispatch(transaction);
          h.plugin.update({state: h.state(), startState: previous, changes: transaction.changes, docChanged: false,
            selectionSet: true, focusChanged: false, transactions: [transaction]} as unknown as ViewUpdate);
        } else if (reason === "blur" || reason === "composition") {
          const definition = (h.suggestions.extension as Extension[])[1] as unknown as {
            domEventHandlers: {blur(this: unknown): void; compositionstart(this: unknown): void};
          };
          if (reason === "blur") definition.domEventHandlers.blur.call(h.plugin);
          else definition.domEventHandlers.compositionstart.call(h.plugin);
        } else h.plugin.clear();
        h.suggestions.configureWritingIndexContext("later-catalog");
        h.suggestions.resolveLinkCompletionQuery(fresh, {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
          availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
        await vi.advanceTimersByTimeAsync(2_000);
        expect(h.terms).toHaveLength(2);
        expect(h.requests).toEqual([]);
        expect(h.cancelledTerms).toEqual([h.terms[0], fresh]);
        expect(h.plugin.decorations.size).toBe(0);
        expect(h.plugin.accept()).toBe(false);
        expect(h.state().field(exactSourceState).text).toBe("A claim about res");
        expect(undoDepth(h.state())).toBe(0);
      } finally { h.plugin.destroy(); vi.useRealTimers(); }
    });

  it("does not query or accept inline writing in read-only or noneditable states", async () => {
    vi.useFakeTimers();
    for (const options of [{readOnly: true}, {editable: false}]) {
      const h = inlineContinuationHarness("A claim about res", options);
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
      expect(h.termQueries).toEqual([]);
      expect(h.plugin.accept()).toBe(false);
    }
    for (const extension of [EditorState.readOnly.of(true), EditorView.editable.of(false)]) {
      const h = inlineContinuationHarness();
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponse."});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.decorations.size).toBe(1);
      h.view.dispatch({effects: StateEffect.appendConfig.of(extension)});
      expect(h.plugin.accept()).toBe(false);
      expect(h.state().doc.toString()).toBe("A claim about res");
      h.plugin.clear();
    }
    vi.useRealTimers();
  });

  it.each([false, true])("retains an AI round when parsing becomes unavailable before dispatch (cancelled %s)", async cancelled => {
    vi.useFakeTimers(); let ready = true;
    const h = inlineContinuationHarness("res", {contextReady: () => ready});
    try {
      await vi.advanceTimersByTimeAsync(100);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
        availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
      await vi.advanceTimersByTimeAsync(0);
      ready = false;
      await vi.advanceTimersByTimeAsync(300);
      expect(h.requests).toHaveLength(0); expect(h.plugin.decorations.size).toBe(0);
      if (cancelled) h.plugin.clear();
      ready = true;
      h.plugin.update({view: h.view, state: h.state(), startState: h.state(),
        docChanged: false, selectionSet: false, focusChanged: false, transactions: []} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(400);
      expect(h.requests).toHaveLength(cancelled ? 0 : 1);
      if (!cancelled) {
        expect(h.suggestions.resolveWritingContinuation(h.requests[0], {text: "earch"})).toBe(true);
        expect(h.suggestions.resolveWritingContinuation(h.requests[0], {text: "obsolete"})).toBe(false);
        await vi.advanceTimersByTimeAsync(0);
        expect(renderedInlineWidget(h.plugin.decorations).node.dataset.source).toBe("ai");
      }
      expect(h.state().field(exactSourceState).text).toBe("res");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["pending", "failed"])("parser recovery after a late local reply preserves the existing AI round (%s)", async phase => {
    vi.useFakeTimers(); let ready = true;
    const h = inlineContinuationHarness("A claim about res", {contextReady: () => ready});
    try {
      await vi.advanceTimersByTimeAsync(400);
      const remote = h.requests[0];
      ready = false;
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state:"current", candidates:[]});
      await vi.advanceTimersByTimeAsync(0);
      if (phase === "failed") {
        h.suggestions.resolveWritingContinuation(remote, {text:null, reason:"Provider unavailable."});
        await vi.advanceTimersByTimeAsync(0);
      }
      ready = true;
      h.plugin.update({view:h.view, state:h.state(), startState:h.state(), docChanged:false,
        selectionSet:false, focusChanged:false, transactions:[]} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toEqual([remote]);
      expect(h.cancelled).toEqual([]);
      if (phase === "pending") {
        h.suggestions.resolveWritingContinuation(remote, {text:"ponsibility."});
        await vi.advanceTimersByTimeAsync(0);
        expect(renderedInlineWidget(h.plugin.decorations).node.dataset.source).toBe("ai");
      } else {
        h.suggestions.resolveLinkCompletionQuery(h.terms.at(-1)!, {state:"current", candidates:[{label:"responsibility", insertion:"", detail:"",
          availability:"available", writingAction:"term", replacementUTF16Count:3}]});
        await vi.advanceTimersByTimeAsync(0);
        expect(renderedInlineWidget(h.plugin.decorations).node.dataset.source).toBe("index");
        expect(h.view.dom.querySelector(".scholium-writing-feedback-message")?.textContent).toBe("Provider unavailable.");
      }
      expect(h.state().field(exactSourceState).text).toBe("A claim about res");
      expect(undoDepth(h.state())).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["delete.backward", "delete.forward", "undo", "input.paste"])("starts a new paused writing round only for direct deletion (%s)", async event => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("resX");
    try {
      const transaction = h.state().update({changes: {from: 3, to: 4}, selection: {anchor: 3},
        annotations: Transaction.userEvent.of(event)});
      h.view.dispatch(transaction);
      h.plugin.update({view: h.view, state: h.state(), startState: transaction.startState,
        changes: transaction.changes, docChanged: true, selectionSet: true, focusChanged: false,
        transactions: [transaction]} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(400);
      expect(h.requests).toHaveLength(event.startsWith("delete.") ? 1 : 0);
      expect(h.state().field(exactSourceState).text).toBe("res");
      if (h.requests.length) {
        h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility"});
        await vi.advanceTimersByTimeAsync(0);
        expect(h.plugin.accept()).toBe(true);
        expect(undo({state: h.state(), dispatch: transaction => h.view.dispatch(transaction)})).toBe(true);
        expect(h.state().field(exactSourceState).text).toBe("res");
      }
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["typing", "deletion", "caret", "focus", "composition", "configuration", "lifecycle"])("reports source-free page cancellation cause (%s)", async reason => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("resX");
    try {
      await vi.advanceTimersByTimeAsync(400);
      const id = h.requests[0];
      if (reason === "typing") typeSuffix(h, "x");
      else if (reason === "deletion" || reason === "caret") {
        const transaction = h.state().update({...(reason === "deletion" ? {changes: {from: 3, to: 4}} : {}),
          selection: {anchor: 3}, annotations: Transaction.userEvent.of(reason === "deletion" ? "delete.backward" : "select.pointer")});
        h.view.dispatch(transaction);
        h.plugin.update({view: h.view, state: h.state(), startState: transaction.startState,
          changes: transaction.changes, docChanged: reason === "deletion", selectionSet: true,
          focusChanged: false, transactions: [transaction]} as unknown as ViewUpdate);
      } else if (reason === "focus" || reason === "composition") {
        const definition = (h.suggestions.extension as Extension[])[1] as unknown as {
          domEventHandlers: {blur(this: unknown): void; compositionstart(this: unknown): void};
        };
        if (reason === "focus") {
          Object.defineProperty(h.view, "hasFocus", {value: false});
          definition.domEventHandlers.blur.call(h.plugin);
        } else definition.domEventHandlers.compositionstart.call(h.plugin);
      } else if (reason === "configuration") h.suggestions.configureWritingContinuation(true, "model-b");
      else h.suggestions.resetDocument();
      expect(h.cancellationEvents).toEqual([{id, reason}]);
      expect(h.suggestions.resolveWritingContinuation(id, {text: "obsolete"})).toBe(false);
      expect(h.plugin.decorations.size).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("dismissal stays quiet; AI configuration changes reroute active writing and ignore predecessors", async () => {
    vi.useFakeTimers();
    const h = inlineContinuationHarness();
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.plugin.clear();
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility matters."});
      await vi.advanceTimersByTimeAsync(10_000);
      expect(h.terms).toHaveLength(1); expect(h.plugin.decorations.size).toBe(0);
      h.plugin.schedule(); await vi.advanceTimersByTimeAsync(800);
      h.suggestions.configureWritingContinuation(true, "model-b");
      h.suggestions.resolveWritingContinuation(h.requests[1], {text: "obsolete."});
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toHaveLength(3);
      expect(h.cancelled).toEqual(h.requests.slice(0, 2));
      h.suggestions.configureWritingContinuation(false, "model-b");
      await vi.advanceTimersByTimeAsync(100);
      expect(h.terms).toHaveLength(4);
      h.suggestions.resolveWritingContinuation(h.requests[2], {text: "obsolete."});
      h.suggestions.resolveLinkCompletionQuery(h.terms[3], {state: "current", candidates: [{label: "responsibility", insertion: "", detail: "",
        availability: "available", writingAction: "term", replacementUTF16Count: 3}]});
      await vi.advanceTimersByTimeAsync(0);
      const preview = h.plugin.decorations;
      h.suggestions.configureWritingContinuation(false, "model-c");
      expect(h.plugin.decorations).toBe(preview);
      h.suggestions.configureWritingContinuation(true, "model-c");
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toHaveLength(4);
      expect(h.terms).toHaveLength(5);
      h.suggestions.resolveWritingContinuation(h.requests[3], {text: "ponsibility matters."});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.accept()).toBe(true);
      expect(h.labels).toEqual(["Accept AI Continuation"]);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });


  const localResponsibility = {label: "responsibility", insertion: "", detail: "",
    availability: "available", writingAction: "term", replacementUTF16Count: 3};
  const visibleSuffix = (h: ReturnType<typeof inlineContinuationHarness>) =>
    renderedInlineWidget(h.plugin.decorations).node.querySelector(".scholium-writing-ghost-text")?.textContent;

  it.each(["success", "absence", "failure", "timeout"])("AI priority hides prefetched Index until a settled fallback (%s)", async outcome => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("res");
    try {
      await vi.advanceTimersByTimeAsync(100);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.decorations.size).toBe(0);
      expect(h.plugin.accept()).toBe(false);
      await vi.advanceTimersByTimeAsync(700);
      if (outcome === "timeout") await vi.advanceTimersByTimeAsync(35_000);
      else h.suggestions.resolveWritingContinuation(h.requests[0], {
        text: outcome === "success" ? "earch needs care." : null,
        reason: outcome === "failure" ? "Synthetic service failure" : null,
      });
      await vi.advanceTimersByTimeAsync(0);
      expect(visibleSuffix(h)).toBe(outcome === "success" ? "earch needs care." : "ponsibility");
      const node = renderedInlineWidget(h.plugin.decorations).node;
      expect(node.dataset.source).toBe(outcome === "success" ? "ai" : "index");
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe(outcome === "success" ? "research needs care." : "responsibility");
      expect(undo({state: h.state(), dispatch: t => h.view.dispatch(t)})).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe("res");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each([true, false])("disabling AI publishes only a confirmed current hidden local cache (fresh %s)", async fresh => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("res");
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
      await vi.advanceTimersByTimeAsync(0); expect(h.plugin.decorations.size).toBe(0);
      if (!fresh) h.suggestions.configureWritingIndexContext("changed");
      h.suggestions.configureWritingContinuation(false, "model-a");
      expect(h.cancelled).toEqual([h.requests[0]]);
      if (fresh) expect(visibleSuffix(h)).toBe("ponsibility");
      else { expect(h.plugin.decorations.size).toBe(0); expect(h.plugin.accept()).toBe(false); }
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "OLD."});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.state().field(exactSourceState).text).toBe("res");
      if (fresh) expect(renderedInlineWidget(h.plugin.decorations).node.dataset.source).toBe("index");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each([true, false])("AI absence waits for current cache validation after catalog change (available %s)", async available => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("res");
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
      await vi.advanceTimersByTimeAsync(0);
      h.suggestions.configureWritingIndexContext("changed");
      await vi.advanceTimersByTimeAsync(0);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: null});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.decorations.size).toBe(0); expect(h.plugin.accept()).toBe(false);
      h.suggestions.resolveLinkCompletionQuery(h.terms[1], {state: "current", candidates: available ? [localResponsibility] : []});
      await vi.advanceTimersByTimeAsync(0);
      if (available) expect(visibleSuffix(h)).toBe("ponsibility");
      else expect(h.plugin.decorations.size).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["same", "source", "caret", "mode", "composition", "dismiss", "departure", "disabled"])("ordinary blur resumes only its unchanged writing round (%s)", async change => {
    vi.useFakeTimers(); const options = {mode: "livePreview" as EditorMode}; const h = inlineContinuationHarness("res", options);
    try {
      await vi.advanceTimersByTimeAsync(800); expect(h.requests).toHaveLength(1);
      Object.assign(h.view, {hasFocus: false});
      const definition = (h.suggestions.extension as Extension[])[1] as unknown as {
        domEventHandlers: {blur(this: unknown): void; compositionstart(this: unknown): void};
      };
      definition.domEventHandlers.blur.call(h.plugin);
      h.plugin.update({state: h.state(), startState: h.state(), docChanged: false,
        selectionSet: false, focusChanged: true, transactions: []} as unknown as ViewUpdate);
      expect(h.cancelled).toEqual([h.requests[0]]);
      if (change === "composition") definition.domEventHandlers.compositionstart.call(h.plugin);
      else if (change === "dismiss") h.plugin.clear();
      else if (change === "departure") h.suggestions.resetDocument();
      else if (change === "disabled") h.suggestions.configureWritingContinuation(false, "model-a");
      else if (change === "mode") options.mode = "source";
      const previous = h.state();
      const transaction = previous.update(change === "source" ? {changes: {from: 0, insert: "x"}}
        : change === "caret" ? {selection: {anchor: 0}} : {});
      h.view.dispatch(transaction); Object.assign(h.view, {hasFocus: true});
      h.plugin.update({state: h.state(), startState: previous, changes: transaction.changes,
        docChanged: transaction.docChanged, selectionSet: transaction.selection !== undefined,
        focusChanged: true, transactions: [transaction]} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toHaveLength(change === "same" ? 2 : 1);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "OLD."});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.decorations.size).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["same", "matching-input", "source", "caret", "mode", "composition", "dismiss", "departure", "disabled", "configuration", "index"])("reuses only a validated unchanged AI suffix after blur (%s)", async change => {
    vi.useFakeTimers(); const options = {mode: "livePreview" as EditorMode}; const h = inlineContinuationHarness("res", options);
    try {
      await vi.advanceTimersByTimeAsync(400);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility"});
      await vi.advanceTimersByTimeAsync(0);
      if (change === "matching-input") typeSuffix(h, "pon");
      const original = h.state().field(exactSourceState).text;
      Object.assign(h.view, {hasFocus: false});
      const definition = (h.suggestions.extension as Extension[])[1] as unknown as {
        domEventHandlers: {blur(this: unknown): void; compositionstart(this: unknown): void};
      };
      definition.domEventHandlers.blur.call(h.plugin);
      // CodeMirror delivers focus loss after DOM blur: retention must be idempotent.
      h.plugin.update({state: h.state(), startState: h.state(), docChanged: false,
        selectionSet: false, focusChanged: true, transactions: []} as unknown as ViewUpdate);
      expect(h.plugin.decorations.size).toBe(0);
      if (change === "composition") definition.domEventHandlers.compositionstart.call(h.plugin);
      else if (change === "dismiss") h.plugin.clear();
      else if (change === "departure") h.suggestions.resetDocument();
      else if (change === "disabled") h.suggestions.configureWritingContinuation(false, "model-a");
      else if (change === "configuration") h.suggestions.configureWritingContinuation(true, "model-b");
      else if (change === "index") h.suggestions.configureWritingIndexContext("new-index");
      else if (change === "mode") options.mode = "source";
      const previous = h.state();
      const transaction = previous.update(change === "source" ? {changes: {from: 0, insert: "x"}}
        : change === "caret" ? {selection: {anchor: 0}} : {});
      h.view.dispatch(transaction); Object.assign(h.view, {hasFocus: true});
      h.plugin.update({state: h.state(), startState: previous, changes: transaction.changes,
        docChanged: transaction.docChanged, selectionSet: transaction.selection !== undefined,
        focusChanged: true, transactions: [transaction]} as unknown as ViewUpdate);
      const reused = change === "same" || change === "matching-input";
      expect(h.plugin.decorations.size).toBe(reused ? 1 : 0);
      if (reused) {
        expect(visibleSuffix(h)).toBe(change === "matching-input" ? "sibility" : "ponsibility");
        expect(h.state().field(exactSourceState).text).toBe(original);
        await vi.advanceTimersByTimeAsync(800);
        expect(h.requests).toHaveLength(1);
        expect(h.plugin.accept()).toBe(true);
        expect(h.state().field(exactSourceState).text).toBe("responsibility");
        expect(undo(h.view)).toBe(true);
        expect(h.state().field(exactSourceState).text).toBe(original);
      } else {
        await vi.advanceTimersByTimeAsync(400);
        expect(h.requests).toHaveLength(change === "configuration" || change === "index" ? 2 : 1);
        expect(h.plugin.decorations.size).toBe(0);
      }
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each([true, false])("publishes AI while local remains hidden without concurrent ghosts (compatible %s)", async compatible => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("res");
    try {
      await vi.advanceTimersByTimeAsync(100);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.decorations.size).toBe(0); const before = h.plugin.decorations;
      await vi.advanceTimersByTimeAsync(700);
      h.suggestions.setWritingContinuationStatus(h.requests[0], {phase: "generating"});
      expect(h.plugin.decorations).toBe(before);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: compatible ? "ponsibility is shared." : "earch needs care."});
      await vi.advanceTimersByTimeAsync(0);
      expect(visibleSuffix(h)).toBe(compatible ? "ponsibility is shared." : "earch needs care.");
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe(compatible ? "responsibility is shared." : "research needs care.");
      expect(undo({state: h.state(), dispatch: t => h.view.dispatch(t)})).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe("res");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("starts a fresh AI-priority round after matching input consumes a local fallback", async () => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("res");
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: null});
      await vi.advanceTimersByTimeAsync(0); expect(visibleSuffix(h)).toBe("ponsibility");
      typeSuffix(h, "pon"); expect(h.plugin.decorations.size).toBe(0);
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveWritingContinuation(h.requests[1], {text: "dents need care."});
      await vi.advanceTimersByTimeAsync(0); expect(visibleSuffix(h)).toBe("dents need care.");
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe("respondents need care.");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each(["same", "model", "effort", "source", "caret", "departure", "disabled"])("enabling in Settings resumes only the unchanged focused caret (%s)", async change => {
    vi.useFakeTimers(); const h=inlineContinuationHarness("res",{aiEnabled:false});
    try {
      h.plugin.clear(); Object.assign(h.view,{hasFocus:false});
      h.suggestions.configureWritingContinuation(true,"model-a");
      await vi.advanceTimersByTimeAsync(800); expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
      if (change==="model" || change==="effort") h.suggestions.configureWritingContinuation(true,change);
      if (change==="departure") h.suggestions.resetDocument();
      else if (change==="disabled") h.suggestions.configureWritingContinuation(false,"model-a");
      const previous=h.state();
      const transaction=previous.update(change==="source" ? {changes:{from:0,insert:"x"}} : change==="caret" ? {selection:{anchor:0}} : {});
      h.view.dispatch(transaction); Object.assign(h.view,{hasFocus:true});
      h.plugin.update({state:h.state(),startState:previous,changes:transaction.changes,docChanged:transaction.docChanged,
        selectionSet:transaction.selection!==undefined,focusChanged:true,transactions:[transaction]} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toHaveLength(["same","model","effort"].includes(change) ? 1 : 0);
      expect(h.terms).toHaveLength(["same","model","effort"].includes(change) ? 1 : 0);
    } finally {h.plugin.destroy();vi.useRealTimers();}
  });

  it("ignores local replies after AI publication and cancels pending AI when local is accepted", async () => {
    vi.useFakeTimers();
    for (const aiFirst of [true, false]) {
      const h = inlineContinuationHarness("res");
      try {
        await vi.advanceTimersByTimeAsync(800);
        if (aiFirst) {
          h.suggestions.resolveWritingContinuation(h.requests[0], {text: "earch is needed."});
          await vi.advanceTimersByTimeAsync(0);
        } else {
          h.suggestions.resolveWritingContinuation(h.requests[0], {text: null});
          await vi.advanceTimersByTimeAsync(0);
        }
        h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
        await vi.advanceTimersByTimeAsync(0);
        expect(visibleSuffix(h)).toBe(aiFirst ? "earch is needed." : "ponsibility");
        expect(h.plugin.accept()).toBe(true);
        h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility is shared."});
        await vi.advanceTimersByTimeAsync(0);
        expect(h.state().field(exactSourceState).text).toBe(aiFirst ? "research is needed." : "responsibility");
        expect(h.plugin.decorations.size).toBe(0);
        expect(h.cancelled).toEqual([]);
      } finally { h.plugin.destroy(); }
    }
    vi.useRealTimers();
  });

  it("freezes queued AI Tab through parser readiness and late local publication", async () => {
    vi.useFakeTimers(); let ready = true; const h = inlineContinuationHarness("res", {contextReady: () => ready});
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "earch needs care."});
      await vi.advanceTimersByTimeAsync(0);
      ready = false; expect(h.plugin.accept()).toBe(true);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
      ready = true;
      h.plugin.update({state: h.state(), startState: h.state(), docChanged: false,
        selectionSet: false, focusChanged: false, transactions: []} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(0);
      expect(h.state().field(exactSourceState).text).toBe("research needs care.");
      expect(h.labels).toEqual(["Accept AI Continuation"]);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("restarts AI priority after matching fallback input waits for parsing", async () => {
    vi.useFakeTimers(); let ready = true; const h = inlineContinuationHarness("res", {contextReady: () => ready});
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: null});
      await vi.advanceTimersByTimeAsync(0);
      ready = false; typeSuffix(h, "pon");
      expect(h.plugin.decorations.size).toBe(0);
      await vi.advanceTimersByTimeAsync(1_000); expect(h.requests).toHaveLength(1);
      ready = true;
      h.plugin.update({state: h.state(), startState: h.state(), docChanged: false,
        selectionSet: false, focusChanged: false, transactions: []} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(399); expect(h.requests).toHaveLength(1);
      await vi.advanceTimersByTimeAsync(1); expect(h.requests).toHaveLength(2);
      h.suggestions.resolveWritingContinuation(h.requests[1], {text: "dents need care."});
      await vi.advanceTimersByTimeAsync(0); expect(visibleSuffix(h)).toBe("dents need care.");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it.each([false, true])("restores AI after configuration waits for parsing with retained local (already enabled %s)", async enabled => {
    vi.useFakeTimers(); let ready = true;
    const h = inlineContinuationHarness("res", {aiEnabled: enabled, contextReady: () => ready});
    try {
      await vi.advanceTimersByTimeAsync(100);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
      await vi.advanceTimersByTimeAsync(700);
      ready = false; h.suggestions.configureWritingContinuation(true, "model-b");
      expect(h.plugin.decorations.size).toBe(0);
      await vi.advanceTimersByTimeAsync(1_000); expect(h.requests).toHaveLength(enabled ? 1 : 0);
      ready = true;
      h.plugin.update({state: h.state(), startState: h.state(), docChanged: false,
        selectionSet: false, focusChanged: false, transactions: []} as unknown as ViewUpdate);
      await vi.advanceTimersByTimeAsync(399); expect(h.requests).toHaveLength(enabled ? 1 : 0);
      await vi.advanceTimersByTimeAsync(1); expect(h.requests).toHaveLength(enabled ? 2 : 1);
      expect(h.plugin.decorations.size).toBe(0);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("retains hidden local prefetch and pending AI through an index refresh", async () => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("res");
    try {
      await vi.advanceTimersByTimeAsync(100);
      h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state: "current", candidates: [localResponsibility]});
      await vi.advanceTimersByTimeAsync(700); const before = h.plugin.decorations;
      h.suggestions.configureWritingIndexContext("autosave");
      await vi.advanceTimersByTimeAsync(0);
      expect(h.plugin.decorations).toBe(before); expect(h.cancelled).toEqual([]);
      h.suggestions.resolveLinkCompletionQuery(h.terms[1], {state: "current", candidates: [localResponsibility]});
      await vi.advanceTimersByTimeAsync(0);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility is shared."});
      await vi.advanceTimersByTimeAsync(0); expect(visibleSuffix(h)).toBe("ponsibility is shared.");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("rejects a captured pointer target after matching AI input changes its visible suffix", async () => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("res");
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility is shared."});
      await vi.advanceTimersByTimeAsync(0);
      vi.stubGlobal("document", h.view.dom.ownerDocument);
      let node!: HTMLElement;
      h.plugin.decorations.between(0, 100, (_from, _to, d) => { node = d.spec.widget.toDOM(h.view); });
      vi.unstubAllGlobals(); h.view.dom.append(node);
      const Event = node.ownerDocument.defaultView!.Event;
      node.dispatchEvent(new Event("mousedown"));
      typeSuffix(h, "pon");
      h.plugin.decorations.between(0, 100, (_from, _to, d) => d.spec.widget.updateDOM(node));
      node.dispatchEvent(new Event("click"));
      expect(h.state().field(exactSourceState).text).toBe("respon");
      expect(h.labels).toEqual([]); expect(visibleSuffix(h)).toBe("sibility is shared.");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("accepts the consumed AI suffix and provenance through a reused widget DOM", async () => {
    vi.useFakeTimers(); const h = inlineContinuationHarness("res");
    try {
      await vi.advanceTimersByTimeAsync(800);
      h.suggestions.resolveWritingContinuation(h.requests[0], {text: "ponsibility is shared."});
      await vi.advanceTimersByTimeAsync(0);
      vi.stubGlobal("document", h.view.dom.ownerDocument); let node!: HTMLElement;
      h.plugin.decorations.between(0, 100, (_from, _to, d) => { node = d.spec.widget.toDOM(h.view); });
      vi.unstubAllGlobals(); h.view.dom.append(node);
      typeSuffix(h, "pon");
      h.plugin.decorations.between(0, 100, (_from, _to, d) => d.spec.widget.updateDOM(node));
      const Event = node.ownerDocument.defaultView!.Event;
      node.dispatchEvent(new Event("mousedown")); node.dispatchEvent(new Event("click"));
      expect(h.state().field(exactSourceState).text).toBe("responsibility is shared.");
      expect(h.labels).toEqual(["Accept AI Continuation"]);
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("rejects every C1 and direction-control suffix without rejecting visible multilingual or ZWJ text", () => {
    const forbidden = [...Array.from({length:32}, (_, i) => String.fromCodePoint(0x80 + i)), "\u061c", "\u200e", "\u200f"];
    for (const control of forbidden) expect(safeContinuationSuffix("a" + control + "b")).toBeNull();
    for (const suffix of [" follows.", "进一步验证。", " فرضية", " e\u0301.", " 👩‍👩‍👧‍👦 remains."]) expect(safeContinuationSuffix(suffix)).toBe(suffix);
  });

  it("rejects multiline, hidden controls, Markdown structures and malformed UTF16", () => {
    for (const text of ["", " ", "a\nb", "a\u0085b", "a\u2028b", "a\u2029b", "a\u202eb", "[[note]]", "*claim*", "\ud800", "x".repeat(513), " first. second", "第一句。第二句"]) {
      expect(safeContinuationSuffix(text)).toBeNull();
    }
    expect(safeContinuationSuffix(" qualifies the claim 😀。" )).toBe(" qualifies the claim 😀。");
    expect(safeContinuationSuffix(" 👩‍🔬 می‌نویسد।")).toBe(" 👩‍🔬 می‌نویسد।");
  });

  it("does not request AI in composition, protected constructs, trigger menus or multiple selections", async () => {
    vi.useFakeTimers();
    for (const [source, options] of [
      ["A claim about res", {composing: true}],
      ["A claim about res", {protectedRanges: [{from: 0, to: 20}]}],
      ["A claim about res", {multipleSelections: true}],
      ["[[respons", {}], ["Claim @author", {}], ["Claim /table", {}],
    ] as const) {
      const h = inlineContinuationHarness(source, options);
      await vi.advanceTimersByTimeAsync(800);
      expect(h.requests).toEqual([]); expect(h.terms).toEqual([]);
      h.plugin.clear();
    }
    vi.useRealTimers();
  });
});

const dialect: MarkdownEditingDialect = {
  version: 6,
  callouts: [
    {identifier: "orient", label: "Orient", meaning: "Purpose and route."},
    {identifier: "state", label: "State", meaning: "A compact claim."},
  ],
  linkAnnotation: {
    openingDelimiter: "{{", closingDelimiter: "}}", escapeCharacter: "\\",
    allowsMultiline: true, allowsNesting: false,
  },
  footnotes: {
    namedReferenceOpening: "[^",
    namedReferenceClosing: "]",
    definitionSeparator: ":",
    inlineOpening: "^[",
    continuationIndentSpaces: 2,
    allowsTabContinuation: true,
    caseSensitiveIdentifiers: true,
    ordinalByFirstReference: true,
  },
  mathematics: {
    inlineDelimiter: "$",
    displayDelimiter: "$$",
    singleDollarInline: true,
  },
};

function controller(
  mode: EditorMode = "livePreview",
  protectedRanges: readonly {from: number; to: number}[] = [],
  composing = false,
  editingDialect: MarkdownEditingDialect = dialect,
) {
  let request: {id: string; kind: string; query: string} | null = null;
  const undoLabels: string[] = [];
  const suggestions = createEditorInputSuggestions({
    nativeFloating: {show: () => 0, hide: () => {}},
    mode: () => mode,
    dialect: () => editingDialect,
    isComposing: () => composing,
    protectedRanges: () => protectedRanges,
    requestLinkCompletions: (id, kind, query) => { request = {id, kind, query}; },
    didApply: (label) => { undoLabels.push(label); },
  });
  return {suggestions, request: () => request, undoLabels};
}

function synchronousResult(
  source: CompletionSource,
  text: string,
): CompletionResult | null {
  const state = EditorState.create({
    doc: text,
    selection: {anchor: text.length},
  });
  const result = source(new CompletionContext(state, text.length, false));
  expect(result).not.toBeInstanceOf(Promise);
  return result as CompletionResult | null;
}

function mutableView(initialState: EditorState) {
  let state = initialState;
  const view = {
    get state() { return state; },
    dispatch(...specs: (Transaction | TransactionSpec)[]) {
      if (specs.length === 1 && specs[0] instanceof Transaction) {
        state = specs[0].state;
      } else {
        state = state.update(...specs as TransactionSpec[]).state;
      }
    },
  } as unknown as EditorView;
  return {view, state: () => state};
}

function applyOption(source: CompletionSource, text: string, label: string) {
  const initialState = EditorState.create({doc: text, selection: {anchor: text.length}});
  const result = source(new CompletionContext(initialState, text.length, false)) as CompletionResult;
  const completion = result.options.find((option) => option.label === label)!;
  const mutable = mutableView(initialState);
  expect(typeof completion.apply).toBe("function");
  if (typeof completion.apply === "function") {
    completion.apply(mutable.view, completion, result.from, text.length);
  }
  return mutable.state();
}

describe("Edit input suggestions", () => {
  it.each([EditorState.readOnly.of(true), EditorView.editable.of(false)])("suppresses all caret lists in a nonwritable state", extension => {
    const {suggestions, request} = controller();
    for (const [completionSource, text] of [
      [suggestions.slashCompletionSource, "/"], [suggestions.calloutCompletionSource, "> [!"],
      [suggestions.wikilinkCompletionSource, "[["], [suggestions.analysisReferenceCompletionSource, "@"],
    ] as const) {
      const state = EditorState.create({doc: text, selection: {anchor: text.length}, extensions: [extension]});
      expect(completionSource(new CompletionContext(state, text.length, false))).toBeNull();
    }
    expect(request()).toBeNull();
  });
  it.each(["analysis", "wikilink"])("keeps an %s query from replacing a protected construct later in its span", kind => {
    const source = kind === "analysis" ? "@work `literal`" : "[[work `literal`";
    const from = source.indexOf("`");
    const {suggestions, request} = controller("livePreview", [{from, to: source.length}]);
    const completionSource = kind === "analysis" ? suggestions.analysisReferenceCompletionSource
      : suggestions.wikilinkCompletionSource;
    expect(synchronousResult(completionSource, source)).toBeNull();
    expect(request()).toBeNull();
  });
  it("suppresses every caret suggestion while the composition lifetime gate is active", () => {
    const {suggestions, request} = controller("livePreview", [], true);
    for (const [source, text] of [
      [suggestions.slashCompletionSource, "/"],
      [suggestions.calloutCompletionSource, "> [!"],
      [suggestions.wikilinkCompletionSource, "[["],
      [suggestions.analysisReferenceCompletionSource, "@"],
      [suggestions.citationCompletionSource, "@"],
    ] as const) {
      expect(synchronousResult(source, text)).toBeNull();
    }
    expect(request()).toBeNull();
  });
  function expectCompletionUndo(mutable: ReturnType<typeof mutableView>, original: string) {
    const completed = mutable.state().doc.toString();
    const range = mutable.state().selection.main;
    mutable.view.dispatch({changes: {from: range.from, to: range.to, insert: "x"},
      selection: {anchor: range.from + 1}, userEvent: "input.type"});
    expect(undo({state: mutable.state(), dispatch: mutable.view.dispatch})).toBe(true);
    expect(mutable.state().doc.toString()).toBe(completed);
    expect(undo({state: mutable.state(), dispatch: mutable.view.dispatch})).toBe(true);
    expect(mutable.state().doc.toString()).toBe(original);
  }

  it.each(["Date", "Code Block", "Footnote"])("isolates %s slash acceptance from subsequent typing", label => {
    const {suggestions} = controller();
    const mutable = mutableView(EditorState.create({doc: "/", selection: {anchor: 1},
      extensions: [history(), suggestions.extension]}));
    const result = suggestions.slashCompletionSource(
      new CompletionContext(mutable.state(), 1, false),
    ) as CompletionResult;
    const completion = result.options.find(option => option.label === label)!;
    expect(typeof completion.apply).toBe("function");
    if (typeof completion.apply === "function") {
      completion.apply(mutable.view, completion, result.from, 1);
    }
    expectCompletionUndo(mutable, "/");
  });

  it.each(["wikilink", "analysisReference"] as const)("isolates %s acceptance from subsequent typing", async kind => {
    const {suggestions, request} = controller();
    const source = kind === "wikilink" ? "[[Val" : "@Val";
    const mutable = mutableView(EditorState.create({doc: source, selection: {anchor: source.length},
      extensions: [history(), suggestions.extension]}));
    const completionSource = kind === "wikilink"
      ? suggestions.wikilinkCompletionSource : suggestions.analysisReferenceCompletionSource;
    const pending = completionSource(new CompletionContext(mutable.state(), source.length, false));
    suggestions.resolveLinkCompletionQuery(request()!.id, [{label: "Value", insertion: "Value",
      displayText: "Value", detail: "", availability: "available"}]);
    const result = (await pending)!;
    const completion = result.options[0];
    expect(typeof completion.apply).toBe("function");
    if (typeof completion.apply === "function") {
      completion.apply(mutable.view, completion, result.from, source.length);
    }
    expectCompletionUndo(mutable, source);
  });
  it("offers every context-available slash command and filters while editing", () => {
    const {suggestions} = controller();
    const block = synchronousResult(suggestions.slashCompletionSource, "/")!;
    expect(block.options.map((option) => option.label)).toEqual([
      "Callout",
      "Date",
      "Inline Math",
      "Display Math",
      "Mermaid",
      "Table",
      "Footnote",
      "Code Block",
      "Divider",
    ]);

    const inline = synchronousResult(suggestions.slashCompletionSource, "Claim /")!;
    expect(inline.options.map((option) => option.label)).toEqual([
      "Date",
      "Inline Math",
      "Footnote",
    ]);

    expect(synchronousResult(suggestions.slashCompletionSource, "/tab")?.options.map(option => option.label)).toEqual(["Table"]);
    expect(synchronousResult(suggestions.slashCompletionSource, "/math")?.options.map(option => option.label)).toEqual(["Inline Math", "Display Math"]);
    for (const text of ["https://", "word/", "/table/"]) {
      expect(synchronousResult(suggestions.slashCompletionSource, text)).toBeNull();
    }

  });

  it("keeps input suggestions out of Source and protected syntax", () => {
    const source = controller("source").suggestions;
    expect(synchronousResult(source.slashCompletionSource, "/")).toBeNull();

    const protectedSuggestions = controller("livePreview", [{from: 0, to: 4}]).suggestions;
    expect(synchronousResult(protectedSuggestions.slashCompletionSource, "/")).toBeNull();
  });

  it("uses compact callout role labels without syntax or explanatory prose", () => {
    const {suggestions} = controller();
    const result = synchronousResult(suggestions.calloutCompletionSource, "> [!")!;
    expect(result.options.map((option) => option.label)).toEqual(["Orient", "State"]);
    expect(result.options.every((option) => option.detail === undefined)).toBe(true);
  });

  it("updates local Callout results synchronously through filtering and context exit", () => {
    const {suggestions} = controller();
    const initial = synchronousResult(suggestions.calloutCompletionSource, "> [!")!;
    const update = (text: string) => {
      const state = EditorState.create({doc: text, selection: {anchor: text.length}});
      return initial.update!(initial, initial.from, text.length, new CompletionContext(state, text.length, false));
    };
    expect(update("> [!sta")!.options.map(option => option.label)).toEqual(["State"]);
    expect(update("> [!")!.options.map(option => option.label)).toEqual(["Orient", "State"]);
    expect(update("> [!state] text")).toBeNull();
  });

  it("filters Callouts by their visible English and Chinese names while inserting canonical syntax", () => {
    const researchDialect = {...dialect, callouts: [
      {identifier: "flag", label: "Caution", meaning: "Limits"},
      {identifier: "cite", label: "Source", meaning: "Sources"},
    ]};
    const suggestions = controller("livePreview", [], false, researchDialect).suggestions;
    expect(synchronousResult(suggestions.calloutCompletionSource, "> [!caut")?.options.map(option => option.label)).toEqual(["Caution"]);
    expect(synchronousResult(suggestions.calloutCompletionSource, "> [!source")?.options.map(option => option.label)).toEqual(["Source"]);
    localizationTesting.install({languageTag: "zh-Hans", strings: {Caution: "限制", Source: "来源"}});
    try {
      expect(synchronousResult(suggestions.calloutCompletionSource, "> [!来源")?.options.map(option => option.label)).toEqual(["来源"]);
      expect(applyOption(suggestions.calloutCompletionSource, "> [!限制", "限制").doc.toString()).toBe("> [!flag] ");
    } finally { localizationTesting.reset(); }
  });

  it("reuses a closing Callout bracket and preserves authored folding and title text", () => {
    for (const [text, expected] of [
      ["> [!sta]", "> [!state] "],
      ["> [!sta] Title", "> [!state] Title"],
      ["> [!sta]+ Title", "> [!state]+ Title"],
      ["> [!sta]-\tTitle", "> [!state]-\tTitle"],
      ["> [!sta]  Title", "> [!state]  Title"],
    ]) {
      const {suggestions} = controller();
      const position = text.indexOf("]");
      const state = EditorState.create({doc: text, selection: {anchor: position}});
      const result = suggestions.calloutCompletionSource(
        new CompletionContext(state, position, false),
      ) as CompletionResult;
      const completion = result.options[0];
      const mutable = mutableView(state);
      expect(typeof completion.apply).toBe("function");
      if (typeof completion.apply === "function") {
        completion.apply(mutable.view, completion, result.from, position);
      }
      expect(mutable.state().doc.toString()).toBe(expected);
      expect(mutable.state().sliceDoc(0, mutable.state().selection.main.head))
        .toMatch(/^> \[!state\][+-]?[ \t]$/);
    }
  });

  it("keeps Callout completion separate from subsequent typing in Undo", () => {
    const {suggestions} = controller();
    const query = "> [!sta]";
    const position = query.indexOf("]");
    const mutable = mutableView(EditorState.create({doc: query,
      selection: {anchor: position}, extensions: [history(), suggestions.extension]}));
    const result = suggestions.calloutCompletionSource(
      new CompletionContext(mutable.state(), position, false),
    ) as CompletionResult;
    const completion = result.options[0];
    expect(typeof completion.apply).toBe("function");
    if (typeof completion.apply === "function") {
      completion.apply(mutable.view, completion, result.from, position);
    }
    const completed = mutable.state().doc.toString();
    const head = mutable.state().selection.main.head;
    mutable.view.dispatch({changes: {from: head, insert: "Title"},
      selection: {anchor: head + 5}, userEvent: "input.type"});
    expect(undo({state: mutable.state(), dispatch: mutable.view.dispatch})).toBe(true);
    expect(mutable.state().doc.toString()).toBe(completed);
    expect(undo({state: mutable.state(), dispatch: mutable.view.dispatch})).toBe(true);
    expect(mutable.state().doc.toString()).toBe(query);
  });

  it("inserts bounded structural templates and chains Callout role choice", () => {
    const {suggestions} = controller();
    expect(applyOption(suggestions.slashCompletionSource, "/", "Date").doc.toString())
      .toBe(inputSuggestionTesting.localISODate());
    expect(applyOption(suggestions.slashCompletionSource, "/", "Inline Math").doc.toString())
      .toBe("$$");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Display Math").doc.toString())
      .toBe("$$\n\n$$");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Mermaid").doc.toString())
      .toBe("```mermaid\n\n```");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Table").doc.toString())
      .toBe("| Column 1 | Column 2 |\n| --- | --- |\n|  |  |");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Footnote").doc.toString())
      .toBe("[^1]\n\n[^1]: \n");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Code Block").doc.toString())
      .toBe("```language\n\n```");
    expect(applyOption(suggestions.slashCompletionSource, "/", "Divider").doc.toString())
      .toBe("---");

    const calloutStart = applyOption(
      suggestions.slashCompletionSource,
      "/",
      "Callout",
    );
    expect(calloutStart.doc.toString()).toBe("> [!");
    expect(applyOption(
      suggestions.calloutCompletionSource,
      calloutStart.doc.toString(),
      "Orient",
    ).doc.toString()).toBe("> [!orient] ");
  });

  it("queries note titles incrementally and reuses auto-inserted closing brackets", async () => {
    const {suggestions, request, undoLabels} = controller();
    const state = EditorState.create({doc: "[[价值]]", selection: {anchor: 4}});
    const pending = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 4, false),
    ) as Promise<CompletionResult>;
    const query = request();
    expect(query?.kind).toBe("wikilink");
    expect(query?.query).toBe("价值");
    suggestions.resolveLinkCompletionQuery(query!.id, [{
      label: "价值理论",
      insertion: "价值理论",
      detail: "Topics — 价值理论.md",
      availability: "available",
    }]);
    const result = await pending;
    expect(result.options.map((option) => option.label)).toEqual(["价值理论"]);
    expect(result.options[0].detail).toBe("Topics — 价值理论.md");

    const mutable = mutableView(state);
    const apply = result.options[0].apply;
    expect(typeof apply).toBe("function");
    if (typeof apply === "function") {
      apply(mutable.view, result.options[0], result.from, 4);
    }
    expect(mutable.state().doc.toString()).toBe("[[价值理论]]");
    expect(undoLabels).toEqual(["Insert Wikilink"]);
  });

  it("inserts a stored alias as canonical target plus display text", async () => {
    const {suggestions, request} = controller();
    const text = "[[Value Theory]]";
    const state = EditorState.create({doc: text, selection: {anchor: 14}});
    const pending = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 14, false),
    ) as Promise<CompletionResult>;
    const query = request()!;
    suggestions.resolveLinkCompletionQuery(query.id, [{
      label: "Value Theory",
      insertion: "Axiology",
      detail: "Axiology — Topics/Value.md",
      displayText: "Value Theory",
      availability: "available",
    }]);
    const result = await pending;
    const mutable = mutableView(state);
    const apply = result.options[0].apply;
    if (typeof apply === "function") {
      apply(mutable.view, result.options[0], result.from, 14);
    }
    expect(mutable.state().doc.toString()).toBe("[[Axiology|Value Theory]]");
  });

  it("turns an Analysis-only at completion into a Wikilink reference", async () => {
    const {suggestions, request, undoLabels} = controller();
    const text = "According to @Scanlon";
    const state = EditorState.create({doc: text, selection: {anchor: text.length}});
    const pending = suggestions.analysisReferenceCompletionSource(
      new CompletionContext(state, text.length, false),
    ) as Promise<CompletionResult>;
    const query = request()!;
    expect(query.kind).toBe("analysisReference");
    expect(query.query).toBe("Scanlon");
    suggestions.resolveLinkCompletionQuery(query.id, [{
      label: "T. M. Scanlon 1998",
      insertion: "What We Owe",
      detail: "What We Owe to Each Other — T. M. Scanlon — 1998",
      displayText: "T. M. Scanlon 1998",
      availability: "available",
    }]);
    const result = await pending;
    const mutable = mutableView(state);
    const apply = result.options[0].apply;
    if (typeof apply === "function") {
      apply(mutable.view, result.options[0], result.from, text.length);
    }
    expect(mutable.state().doc.toString())
      .toBe("According to [[What We Owe|T. M. Scanlon 1998]]");
    expect(undoLabels).toEqual(["Insert Analysis Reference"]);
    expect(synchronousResult(suggestions.analysisReferenceCompletionSource, "mail@example"))
      .toBeNull();
  });

  it("keeps completion active inside an empty auto-closed Wikilink", async () => {
    const {suggestions, request} = controller();
    const state = EditorState.create({doc: "[[]]", selection: {anchor: 2}});
    const pending = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 2, false),
    ) as Promise<CompletionResult>;
    const query = request();
    expect(query?.query).toBe("");
    suggestions.resolveLinkCompletionQuery(query!.id, []);
    const result = await pending;
    expect(result.from).toBe(2);
    expect(result.options).toEqual([]);
  });

  it.each(["wikilink", "analysis"])("retains an unavailable %s candidate and its literal query even through CodeMirror acceptance", async kind => {
    vi.useFakeTimers();
    const {suggestions, request, undoLabels} = controller();
    const text = kind === "wikilink" ? "[[Foo]]" : "@Foo";
    const caret = kind === "wikilink" ? text.length - 2 : text.length;
    const state = EditorState.create({doc: text, selection: {anchor: caret},
      extensions: [history(), exactSourceHistory, suggestions.extension]})
      .update({effects: setExactSource.of(text), annotations: Transaction.addToHistory.of(false)}).state;
    const mutable = mutableView(state);
    // Drive the installed CodeMirror completion owner without claiming native UI proof.
    startCompletion(mutable.view);
    const extension = (suggestions.extension as Extension[])[0] as Extension[];
    const definition = extension[3] as unknown as {create(view: EditorView): unknown};
    definition.create(mutable.view);
    const reason = "This Note has no unique Wikilink target from the current Note. Add a unique alias.";
    suggestions.resolveLinkCompletionQuery(request()!.id, [{label: "Foo", insertion: "", detail: "Analyses/Foo.md",
      displayText: "Foo", availability: "ambiguous", unavailableReason: reason}]);
    try {
      await vi.advanceTimersByTimeAsync(100);
      expect(currentCompletions(mutable.state())).toHaveLength(1);
      expect(currentCompletions(mutable.state())[0].detail).toContain(reason);
      const enter = mutable.state().facet(keymap).flat().find(binding => binding.key === "Enter")!;
      expect(enter.run!(mutable.view)).toBe(true);
      expect(acceptCompletion(mutable.view)).toBe(true);
      expect(completionStatus(mutable.state())).toBe("active");
      expect(mutable.state().doc.toString()).toBe(text);
      expect(mutable.state().field(exactSourceState).text).toBe(text);
      expect(mutable.state().selection.eq(state.selection)).toBe(true);
      expect(undoDepth(mutable.state())).toBe(0);
      expect(undoLabels).toEqual([]);
    } finally { suggestions.resetDocument(); vi.useRealTimers(); }
  });

  it.each(["wikilink", "analysis"])("rejects stale %s acceptance after catalog, selection, source or composition changes", async kind => {
    for (const changed of ["catalog", "selection", "source", "composition"] as const) {
      const {suggestions, request, undoLabels} = controller();
      const text = kind === "wikilink" ? "[[Foo]]" : "@Foo";
      const caret = kind === "wikilink" ? text.length - 2 : text.length;
      const state = EditorState.create({doc: text, selection: {anchor: caret}});
      const completionSource = kind === "wikilink" ? suggestions.wikilinkCompletionSource : suggestions.analysisReferenceCompletionSource;
      const pending = completionSource(new CompletionContext(state, caret, false));
      suggestions.resolveLinkCompletionQuery(request()!.id, [{label: "Foo", insertion: "Foo", detail: "Topics/Foo.md",
        displayText: "Foo", availability: "available"}]);
      const result = (await pending)!;
      const mutable = mutableView(state);
      if (changed === "catalog") suggestions.configureWritingIndexContext("new-catalog");
      else if (changed === "composition") Object.defineProperty(mutable.view, "composing", {value: true});
      else mutable.view.dispatch(changed === "selection" ? {selection: {anchor: 0}} : {changes: {from: 0, insert: "x"}});
      const before = mutable.state();
      const option = result.options[0];
      if (typeof option.apply === "function") option.apply(mutable.view, option, result.from, caret);
      expect(mutable.state()).toBe(before);
      expect(undoLabels).toEqual([]);
    }
  });

  it.each(["wikilink", "analysis"])("requeries a pending %s after catalog change and ignores its old reply", async kind => {
    vi.useFakeTimers();
    vi.stubGlobal("window", {setTimeout, clearTimeout});
    const requests: Array<{id: string; kind: string}> = [];
    const suggestions = createEditorInputSuggestions({nativeFloating: {show: () => 1, hide() {}},
      mode: () => "livePreview", dialect: () => dialect, isComposing: () => false, protectedRanges: () => [],
      requestLinkCompletions: (id, kind) => requests.push({id, kind}), didApply() {}});
    const text = kind === "wikilink" ? "[[Fo]]" : "@Fo";
    const caret = kind === "wikilink" ? text.length - 2 : text.length;
    let state = EditorState.create({doc: text, selection: {anchor: caret},
      extensions: [history(), exactSourceHistory, suggestions.extension]})
      .update({effects: setExactSource.of(text), annotations: Transaction.addToHistory.of(false)}).state;
    let completionPlugin: {update(update: ViewUpdate): void} | undefined;
    const contentDOM = {};
    const view = {get state() {return state;}, composing: false, hasFocus: true, contentDOM,
      root: {activeElement: contentDOM}, requestMeasure() {}, coordsAtPos: () => ({left: 0, top: 0, bottom: 20}),
      dispatch(spec: TransactionSpec) {
        const startState = state, transaction = state.update(spec);
        state = transaction.state;
        completionPlugin?.update({state, startState, transactions: [transaction],
          docChanged: transaction.docChanged, selectionSet: !!transaction.selection} as unknown as ViewUpdate);
      },
    } as unknown as EditorView;
    startCompletion(view);
    const extensions = suggestions.extension as Extension[];
    const completionDefinition = (extensions[0] as Extension[])[3] as unknown as {
      create(view: EditorView): {update(update: ViewUpdate): void};
    };
    completionPlugin = completionDefinition.create(view);
    const nativeDefinition = extensions[3] as unknown as {create(view: EditorView): {destroy(): void}};
    const nativePlugin = nativeDefinition.create(view);
    try {
      expect(completionStatus(state)).toBe("pending");
      expect(currentCompletions(state)).toEqual([]);
      const oldID = requests[0].id;
      suggestions.configureWritingIndexContext("new-catalog");
      await vi.advanceTimersByTimeAsync(60);
      expect(requests).toHaveLength(2);
      const freshID = requests[1].id;
      expect(freshID).not.toBe(oldID);
      suggestions.resolveLinkCompletionQuery(oldID, [{label: "Old", insertion: "Old", detail: "Old.md",
        displayText: "Old", availability: "available"}]);
      await vi.advanceTimersByTimeAsync(0);
      expect(currentCompletions(state)).toEqual([]);
      expect(state.doc.toString()).toBe(text);
      expect(state.field(exactSourceState).text).toBe(text);
      expect(state.selection.main.anchor).toBe(caret);
      expect(state.selection.main.head).toBe(caret);
      expect(undoDepth(state)).toBe(0);
      suggestions.resolveLinkCompletionQuery(freshID, [{label: "Fresh", insertion: "Fresh", detail: "Fresh.md",
        displayText: "Fresh", availability: "available"}]);
      await vi.advanceTimersByTimeAsync(100);
      expect(currentCompletions(state).map(item => item.label)).toEqual(["Fresh"]);
      expect(acceptCompletion(view)).toBe(true);
      expect(state.doc.toString()).toBe("[[Fresh|Fresh]]");
    } finally {
      nativePlugin.destroy(); suggestions.resetDocument(); vi.unstubAllGlobals(); vi.useRealTimers();
    }
  });

  it("cancels pending candidates when the retained editor changes document", async () => {
    const {suggestions, request} = controller();
    const state = EditorState.create({doc: "[[old", selection: {anchor: 5}});
    const pending = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 5, false),
    ) as Promise<CompletionResult>;
    const oldID = request()!.id;
    suggestions.resetDocument();
    suggestions.resolveLinkCompletionQuery(oldID, [{
      label: "Old note", insertion: "Old note", detail: "", availability: "available",
    }]);
    expect(await pending).toBeNull();

    const next = suggestions.wikilinkCompletionSource(
      new CompletionContext(state, 5, false),
    ) as Promise<CompletionResult>;
    suggestions.resolveLinkCompletionQuery(request()!.id, [{
      label: "New note", insertion: "New note", detail: "", availability: "available",
    }]);
    expect((await next).options.map(option => option.label)).toEqual(["New note"]);
  });

  it("formats the inserted date as a local ISO calendar date", () => {
    expect(inputSuggestionTesting.localISODate(new Date(2026, 7, 3, 12, 30)))
      .toBe("2026-08-03");
  });
});

describe("Indexed writing suggestions", () => {
  const candidate = {label: "responsibility", insertion: "responsibility", detail: "Origin",
    availability: "available", writingAction: "term", replacementUTF16Count: 3};

  async function localPreview(text: string, options: Parameters<typeof inlineContinuationHarness>[1] = {}) {
    const h = inlineContinuationHarness(text, {...options, aiEnabled: false});
    await vi.advanceTimersByTimeAsync(100);
    if (h.terms[0]) h.suggestions.resolveLinkCompletionQuery(h.terms[0], {state:"current", candidates:[candidate]});
    await vi.advanceTimersByTimeAsync(0);
    return h;
  }

  it.each(["Compare [[Value]] with res", "Email author@example.org and res", "Compare A/B with res"])(
    "completes after finished syntax and ordinary punctuation: %s", async text => {
      vi.useFakeTimers(); const h = await localPreview(text);
      try {
        expect(h.termQueries[0]?.kind).toBe("term");
        expect(h.plugin.accept()).toBe(true);
        expect(h.state().field(exactSourceState).text).toBe(text + "ponsibility");
      } finally { h.plugin.destroy(); vi.useRealTimers(); }
    });

  it.each(["Read [[Val", "According to @Scanlon res", "Try /date"])("suppresses Index while a caret-owned trigger remains open: %s", async text => {
    vi.useFakeTimers(); const h = await localPreview(text);
    try { expect(h.termQueries).toEqual([]); expect(h.plugin.accept()).toBe(false); }
    finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("inserts a term as ordinary text and rejects the previous candidate after an edit", async () => {
    vi.useFakeTimers(); const h = await localPreview("res"), changed = await localPreview("res");
    try {
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe("responsibility");
      const transaction = changed.state().update({changes:{from:3,insert:"x"}, selection:{anchor:4}, userEvent:"input.type"});
      changed.view.dispatch(transaction);
      changed.plugin.update({view:changed.view,state:changed.state(),startState:transaction.startState,
        changes:transaction.changes,docChanged:true,selectionSet:true,focusChanged:false,transactions:[transaction]} as unknown as ViewUpdate);
      expect(changed.plugin.accept()).toBe(false);
      expect(changed.state().field(exactSourceState).text).toBe("resx");
    } finally { h.plugin.destroy(); changed.plugin.destroy(); vi.useRealTimers(); }
  });

  it("preserves capitalization and source bytes before the ghost suffix", async () => {
    vi.useFakeTimers(); const h = await localPreview("\uFEFFEarlier 😀 e\u0301.\r\nRes");
    try {
      expect(h.plugin.accept()).toBe(true);
      expect(h.state().field(exactSourceState).text).toBe("\uFEFFEarlier 😀 e\u0301.\r\nResponsibility");
    } finally { h.plugin.destroy(); vi.useRealTimers(); }
  });

  it("leaves IME composition and existing word tails untouched", async () => {
    vi.useFakeTimers(); const composing = await localPreview("res", {composing:true}), tail = await localPreview("result", {caret:3});
    try {
      for (const h of [composing, tail]) { expect(h.termQueries).toEqual([]); expect(h.plugin.accept()).toBe(false); }
    } finally { composing.plugin.destroy(); tail.plugin.destroy(); vi.useRealTimers(); }
  });

  it("does not suggest after spaces or at the end of a protected region", async () => {
    vi.useFakeTimers(); const blank = await localPreview("   "), protectedText = await localPreview("res", {mode:"source", protectedRanges:[{from:0,to:3}]});
    try {
      for (const h of [blank, protectedText]) { expect(h.termQueries).toEqual([]); expect(h.plugin.accept()).toBe(false); }
    } finally { blank.plugin.destroy(); protectedText.plugin.destroy(); vi.useRealTimers(); }
  });
});


function citationSuggestionHarness(source = "According to @", setup: {
  composing?: boolean; mode?: EditorMode; protectedRanges?: readonly {from: number; to: number}[];
  readOnly?: boolean; editable?: boolean; multipleSelections?: boolean;
  canInsertCitation?: (state: EditorState) => boolean;
} = {}) {
  const normalized = normalizedDocumentText(source);
  let composing = setup.composing ?? false, revision = 1;
  let state = EditorState.create({doc: normalized,
    selection: setup.multipleSelections ? EditorSelection.create([EditorSelection.cursor(0), EditorSelection.cursor(normalized.length)])
      : {anchor: normalized.length},
    extensions: [history(), exactSourceHistory, EditorState.allowMultipleSelections.of(true),
      ...(setup.readOnly ? [EditorState.readOnly.of(true)] : []),
      ...(setup.editable === false ? [EditorView.editable.of(false)] : [])]})
    .update({effects: setExactSource.of(source), annotations: Transaction.addToHistory.of(false)}).state;
  const intents: EditorCitationSuggestionIntent[] = [], queries: {id: string; kind: string; query: string}[] = [];
  const suggestions = createEditorInputSuggestions({
    nativeFloating: {show: () => 0, hide: () => {}}, mode: () => setup.mode ?? "livePreview",
    dialect: () => dialect, isComposing: () => composing,
    protectedRanges: () => setup.protectedRanges ?? [],
    requestLinkCompletions: (id, kind, query) => {queries.push({id, kind, query});},
    requestCitationInsertion: intent => intents.push(intent), citationContextRevision: () => revision,
    canInsertCitation: setup.canInsertCitation,
    didApply: () => {throw new Error("A citation intent must not label an editor mutation.");},
  });
  const view = {get state() {return state;}, get composing() {return composing;}, hasFocus: true,
    dispatch(spec: Transaction | TransactionSpec) {
      state = spec instanceof Transaction ? spec.state : state.update(spec).state;
    }} as unknown as EditorView;
  function result() {
    return suggestions.citationCompletionSource(new CompletionContext(state, state.selection.main.head, false)) as CompletionResult | null;
  }
  function accept(completionResult: CompletionResult) {
    const action = completionResult.options[0];
    expect(typeof action.apply).toBe("function");
    if (typeof action.apply === "function") action.apply(view, action, completionResult.from, state.selection.main.head);
  }
  return {suggestions, intents, queries, view, result, accept, state: () => state,
    setComposing: (value: boolean) => {composing = value;}, changeRevision: () => {revision++;}};
}

describe("local citation completion", () => {
  it("checks citation availability when offering and accepting without restricting Analysis references", async () => {
    let available = false;
    const checkedStates: EditorState[] = [];
    const h = citationSuggestionHarness("According to @Scanlon", {canInsertCitation: state => {
      checkedStates.push(state);
      return available;
    }});
    expect(h.result()).toBeNull();
    expect(checkedStates).toEqual([h.state()]);
    const pending = h.suggestions.analysisReferenceCompletionSource(
      new CompletionContext(h.state(), h.state().selection.main.head, false),
    ) as Promise<CompletionResult>;
    expect(h.queries[0]).toMatchObject({kind: "analysisReference", query: "Scanlon"});
    h.suggestions.resolveLinkCompletionQuery(h.queries[0].id, [{
      label: "T. M. Scanlon 1998", insertion: "What We Owe", detail: "Analysis",
      displayText: "T. M. Scanlon 1998", availability: "available",
    }]);
    expect((await pending).options.map(option => option.label)).toEqual(["T. M. Scanlon 1998"]);
    expect(checkedStates).toHaveLength(1);
    available = true;
    const offered = h.result()!;
    expect(offered.options).toHaveLength(1);
    available = false;
    h.accept(offered);
    expect(checkedStates).toHaveLength(3);
    expect(checkedStates[2]).toBe(h.state());
    expect(h.intents).toEqual([]);
    expect(h.state().field(exactSourceState).text).toBe("According to @Scanlon");
    expect(undoDepth(h.state())).toBe(0);
  });

  it("shares the 512 UTF-16 unit query limit with Analysis references and keeps the preceding boundary", async () => {
    const query = "🧭".repeat(255) + "ab";
    expect(query.length).toBe(512);
    const h = citationSuggestionHarness(`According to @${query}`);
    const offered = h.result()!;
    expect(offered.from).toBe("According to ".length);
    const pending = h.suggestions.analysisReferenceCompletionSource(
      new CompletionContext(h.state(), h.state().selection.main.head, false),
    ) as Promise<CompletionResult>;
    expect(h.queries[0]).toMatchObject({kind: "analysisReference", query});
    h.suggestions.resolveLinkCompletionQuery(h.queries[0].id, []);
    expect((await pending).from).toBe(offered.from);
    h.accept(offered);
    expect(h.intents[0].query).toBe(query);
    expect(h.intents[0].toUTF16 - h.intents[0].fromUTF16).toBe(513);
    for (const source of [`@${query}c`, `mail@${query}`]) {
      const invalid = citationSuggestionHarness(source);
      expect(invalid.result()).toBeNull();
      expect(invalid.suggestions.analysisReferenceCompletionSource(
        new CompletionContext(invalid.state(), invalid.state().selection.main.head, false),
      )).toBeNull();
      expect(invalid.queries).toEqual([]);
    }
  });

  it("offers an immediate typed action while Analysis references are still pending", async () => {
    const h = citationSuggestionHarness("According to @Scanlon");
    const context = new CompletionContext(h.state(), h.state().selection.main.head, false);
    const pending = h.suggestions.analysisReferenceCompletionSource(context) as Promise<CompletionResult>;
    expect(pending).toBeInstanceOf(Promise);
    expect(h.queries[0].kind).toBe("analysisReference");
    const local = h.result()!;
    expect(local).not.toBeInstanceOf(Promise);
    const action = local.options[0] as EditorInputSuggestionActionCompletion;
    expect(action.label).toBe("Insert Citation…");
    expect(action.actionID).toBe("insertCitation");
    expect(action.detail).toBe("Zotero");
    h.suggestions.resolveLinkCompletionQuery(h.queries[0].id, [{
      label: "T. M. Scanlon 1998", insertion: "What We Owe", detail: "Analysis",
      displayText: "T. M. Scanlon 1998", availability: "available",
    }]);
    expect((await pending).options.map(option => option.label)).toEqual(["T. M. Scanlon 1998"]);
    expect(h.state().field(exactSourceState).text).toBe("According to @Scanlon");
  });

  it("emits checked exact offsets without deleting the query or adding an Undo event", () => {
    const source = "\uFEFF🧭 First.\r\nAccording to @作者 e\u0301";
    const h = citationSuggestionHarness(source);
    const result = h.result()!;
    h.accept(result);
    expect(h.intents).toHaveLength(1);
    expect(h.intents[0]).toMatchObject({actionID: "insertCitation", query: "作者 e\u0301",
      fromUTF16: source.indexOf("@"), toUTF16: source.length, caretUTF16Offset: source.length,
      editorCaretUTF16Offset: normalizedDocumentText(source).length, interactionRevision: 1});
    expect(h.intents[0].requestID.length).toBeGreaterThan(0);
    expect(h.state().field(exactSourceState).text).toBe(source);
    expect(undoDepth(h.state())).toBe(0);
    h.accept(result);
    expect(h.intents).toHaveLength(1);
  });

  it.each([true, false])("rechecks exact source across a reinstall without a full snapshot (equal %s)", equal => {
    const source = "\uFEFFEarlier 😀 e\u0301.\r\nAccording to @作者";
    const h = citationSuggestionHarness(source);
    const snapshots = vi.spyOn(ExactSourceMirror.prototype, "text", "get");
    try {
      const result = h.result()!;
      const previous = h.state();
      h.view.dispatch({effects: setExactSource.of(equal ? source : source.replaceAll("\r\n", "\n")),
        annotations: Transaction.addToHistory.of(false)});
      expect(h.state().doc).toBe(previous.doc);
      expect(h.state().field(exactSourceState)).not.toBe(previous.field(exactSourceState));
      h.accept(result);
      expect(h.intents).toHaveLength(equal ? 1 : 0);
      expect(undoDepth(h.state())).toBe(0);
      expect(snapshots).not.toHaveBeenCalled();
    } finally { snapshots.mockRestore(); }
  });

  it("rejects source, interaction, lifecycle and composition changes before acceptance", () => {
    for (const invalidate of [
      (h: ReturnType<typeof citationSuggestionHarness>) => h.view.dispatch({changes: {from: 0, insert: "changed "}}),
      (h: ReturnType<typeof citationSuggestionHarness>) => h.changeRevision(),
      (h: ReturnType<typeof citationSuggestionHarness>) => h.suggestions.resetDocument(),
      (h: ReturnType<typeof citationSuggestionHarness>) => h.setComposing(true),
      (h: ReturnType<typeof citationSuggestionHarness>) => h.view.dispatch({selection: {anchor: 0}}),
    ]) {
      const h = citationSuggestionHarness();
      const result = h.result()!;
      invalidate(h);
      const before = h.state().field(exactSourceState).text;
      h.accept(result);
      expect(h.intents).toEqual([]);
      expect(h.state().field(exactSourceState).text).toBe(before);
    }
    const restored = citationSuggestionHarness();
    const result = restored.result()!;
    restored.view.dispatch({selection: {anchor: 0}}); restored.changeRevision();
    restored.view.dispatch({selection: {anchor: restored.state().doc.length}}); restored.changeRevision();
    restored.accept(result);
    expect(restored.intents).toEqual([]);
  });

  it("yields to composition, protected spans, read-only state and unsupported completion contexts", () => {
    for (const h of [
      citationSuggestionHarness("@", {composing: true}),
      citationSuggestionHarness("@", {mode: "source"}),
      citationSuggestionHarness("@", {readOnly: true}),
      citationSuggestionHarness("@", {editable: false}),
      citationSuggestionHarness("@", {multipleSelections: true}),
      citationSuggestionHarness("@key", {protectedRanges: [{from: 0, to: 4}]}),
      citationSuggestionHarness("@name", {protectedRanges: [{from: 1, to: 5}]}),
      citationSuggestionHarness("mail@example"),
    ]) expect(h.result()).toBeNull();
    const {suggestions} = controller();
    const h = citationSuggestionHarness();
    expect(suggestions.citationCompletionSource(new CompletionContext(h.state(), h.state().doc.length, false))).toBeNull();
  });
});
