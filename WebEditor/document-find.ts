import {EditorSelection, EditorState, Transaction} from "@codemirror/state";
import {isolateHistory} from "@codemirror/commands";
import {
  closeSearchPanel,
  openSearchPanel,
  search,
  searchPanelOpen,
  SearchCursor,
  SearchQuery,
  setSearchQuery,
} from "@codemirror/search";
import {EditorView} from "@codemirror/view";
import {exactSourceFitsChanges} from "./exact-source-history";
import {normalizedDocumentText} from "./state";
import {localized} from "./localization";
import {documentFindWordBoundary, type DocumentFindMatch} from "./document-find-matching";

export type DocumentFindAction =
  | "present" | "update" | "next" | "previous" | "replaceCurrent" | "replaceAll";

export interface DocumentFindRequest {
  query: string;
  replacement: string;
  caseSensitive: boolean;
  wholeWord: boolean;
  action: DocumentFindAction;
}

export interface DocumentFindResult {
  current: number;
  total: number;
  replaceable: number;
  canReplaceCurrent: boolean;
  replacement?: {replaced: number; skipped: number};
  sourceChanged: boolean;
  undoLabel?: string;
}

interface LocatedFindMatch extends DocumentFindMatch {precise: boolean}

/**
 * CodeMirror owns matching and visible highlights, while Scholium's native
 * Document panel owns fields and focus. The required panel remains an inert,
 * hidden state carrier and never becomes a second interface surface.
 */
export const documentFindExtension = search({
  literal: true,
  createPanel: () => {
    const dom = document.createElement("div");
    dom.hidden = true;
    dom.setAttribute("aria-hidden", "true");
    return {dom};
  },
});

function searchQuery(request: DocumentFindRequest) {
  return new SearchQuery({
    search: request.query,
    replace: request.replacement,
    caseSensitive: request.caseSensitive,
    literal: true,
    regexp: false,
    wholeWord: request.wholeWord,
    test: request.wholeWord ? (_match, state, from, to) =>
      documentFindWordBoundary(state.doc, from, to)
      : undefined,
  });
}

// Navigation and counts need no retained match catalog, even for a dense query.
// Replace All alone collects the changes required by its atomic transaction.
function* matchingRanges(state: EditorState, query: SearchQuery): IterableIterator<LocatedFindMatch> {
  if (!query.valid) return;
  const cursor = query.getCursor(state);
  for (let next = cursor.next(); !next.done; next = cursor.next()) {
    yield {from: next.value.from, to: next.value.to,
      precise: cursor instanceof SearchCursor && cursor.value.precise};
  }
}

function selectMatch(view: EditorView, match: DocumentFindMatch | null) {
  if (!match) return;
  const selection = EditorSelection.single(match.from, match.to);
  view.dispatch({
    selection,
    effects: EditorView.scrollIntoView(selection.main, {y: "center"}),
    annotations: Transaction.userEvent.of("select.search"),
  });
}

function forwardMatch(view: EditorView, query: SearchQuery, boundary: number) {
  let first: LocatedFindMatch | null = null;
  for (const match of matchingRanges(view.state, query)) {
    first ??= match;
    if (match.from >= boundary) return match;
  }
  return first;
}

function previousMatch(view: EditorView, query: SearchQuery, boundary: number) {
  let previous: LocatedFindMatch | null = null;
  let last: LocatedFindMatch | null = null;
  for (const match of matchingRanges(view.state, query)) {
    last = match;
    if (match.to <= boundary) previous = match;
  }
  return previous ?? last;
}

function currentMatch(view: EditorView, query: SearchQuery) {
  const selection = view.state.selection.main;
  for (const match of matchingRanges(view.state, query)) {
    if (match.from === selection.from && match.to === selection.to) return match;
  }
  return null;
}

function summary(view: EditorView, query: SearchQuery) {
  const selection = view.state.selection.main;
  let first: LocatedFindMatch | null = null;
  let forward: LocatedFindMatch | null = null;
  let selected: LocatedFindMatch | null = null;
  let current = 0, total = 0, replaceable = 0;
  for (const match of matchingRanges(view.state, query)) {
    first ??= match;
    total += 1;
    if (match.precise) replaceable += 1;
    if (forward === null && match.from >= selection.from) forward = match;
    if (match.from === selection.from && match.to === selection.to) {
      selected = match;
      current = total;
    }
  }
  const replacementTarget = selected ?? forward ?? first;
  const writable = !view.state.readOnly && view.state.facet(EditorView.editable);
  return {current, total,
    replaceable: writable ? replaceable : 0,
    canReplaceCurrent: writable && replacementTarget?.precise === true};
}

function installQuery(view: EditorView, query: SearchQuery) {
  view.dispatch({effects: setSearchQuery.of(query)});
  if (!searchPanelOpen(view.state)) openSearchPanel(view);
}

export function performDocumentFind(
  view: EditorView,
  request: DocumentFindRequest,
): DocumentFindResult {
  const query = searchQuery(request);
  installQuery(view, query);

  let sourceChanged = false;
  let undoLabel: string | undefined;
  let replacement: DocumentFindResult["replacement"];
  switch (request.action) {
  case "present":
    break;
  case "update":
    selectMatch(view, forwardMatch(view, query, view.state.selection.main.from));
    break;
  case "next":
    selectMatch(view, forwardMatch(view, query, view.state.selection.main.to));
    break;
  case "previous":
    selectMatch(view, previousMatch(view, query, view.state.selection.main.from));
    break;
  case "replaceCurrent": {
    if (view.state.readOnly || !view.state.facet(EditorView.editable)) break;
    const match = currentMatch(view, query)
      ?? forwardMatch(view, query, view.state.selection.main.from);
    replacement = {replaced: 0, skipped: match && !match.precise ? 1 : 0};
    if (match?.precise) {
      const changes = [{from: match.from, to: match.to, insert: normalizedDocumentText(request.replacement)}];
      if (!exactSourceFitsChanges(view.state, changes)) throw new Error(localized("The replacement would make the document too large."));
      view.dispatch({
        changes,
        annotations: [Transaction.userEvent.of("input.replace"), isolateHistory.of("full")],
      });
      sourceChanged = true;
      replacement.replaced = 1;
      undoLabel = "Replace";
      selectMatch(view, forwardMatch(view, query, match.from + changes[0].insert.length));
    } else if (match) {
      // As in CodeMirror's replacement command, a normalization-only match
      // cannot authorize replacing the larger source character it covers.
      selectMatch(view, forwardMatch(view, query, match.to));
    }
    break;
  }
  case "replaceAll": {
    if (view.state.readOnly || !view.state.facet(EditorView.editable)) break;
    const changes: {from: number; to: number; insert: string}[] = [];
    const insert = normalizedDocumentText(request.replacement);
    let matched = 0;
    for (const match of matchingRanges(view.state, query)) {
      matched += 1;
      if (match.precise) changes.push({from: match.from, to: match.to, insert});
    }
    replacement = {replaced: changes.length, skipped: matched - changes.length};
    if (changes.length > 0) {
      if (!exactSourceFitsChanges(view.state, changes)) throw new Error(localized("The replacement would make the document too large."));
      view.dispatch({
        changes,
        annotations: [Transaction.userEvent.of("input.replace.all"), isolateHistory.of("full")],
      });
      sourceChanged = true;
      undoLabel = "Replace All";
      selectMatch(view, forwardMatch(view, query, view.state.selection.main.from));
    }
    break;
  }
  }

  return {...summary(view, query), replacement, sourceChanged, undoLabel};
}

export function clearDocumentFind(view: EditorView) {
  closeSearchPanel(view);
}
