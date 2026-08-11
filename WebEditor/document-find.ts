import {EditorSelection, EditorState, Transaction} from "@codemirror/state";
import {
  closeSearchPanel,
  openSearchPanel,
  search,
  searchPanelOpen,
  SearchQuery,
  setSearchQuery,
} from "@codemirror/search";
import {EditorView} from "@codemirror/view";

export type DocumentFindAction =
  | "update" | "next" | "previous" | "replaceCurrent" | "replaceAll";

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
  sourceChanged: boolean;
  undoLabel?: string;
}

export interface DocumentFindMatch {from: number; to: number}

/**
 * CodeMirror owns matching and visible highlights, while Scholium's native
 * Document bar owns fields and focus. The required panel remains an inert,
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
  });
}

function matchingRanges(state: EditorState, query: SearchQuery): DocumentFindMatch[] {
  if (!query.valid) return [];
  const matches: DocumentFindMatch[] = [];
  const cursor = query.getCursor(state);
  for (let next = cursor.next(); !next.done; next = cursor.next()) {
    matches.push({from: next.value.from, to: next.value.to});
  }
  return matches;
}

export function documentFindMatches(
  source: string,
  request: DocumentFindRequest,
): DocumentFindMatch[] {
  return matchingRanges(EditorState.create({doc: source}), searchQuery(request));
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
  const matches = matchingRanges(view.state, query);
  return matches.find((match) => match.from >= boundary) ?? matches[0] ?? null;
}

function previousMatch(view: EditorView, query: SearchQuery, boundary: number) {
  const matches = matchingRanges(view.state, query);
  return matches.findLast((match) => match.to <= boundary)
    ?? matches.at(-1)
    ?? null;
}

function currentMatch(view: EditorView, query: SearchQuery) {
  const selection = view.state.selection.main;
  return matchingRanges(view.state, query).find(
    (match) => match.from === selection.from && match.to === selection.to,
  ) ?? null;
}

function summary(view: EditorView, query: SearchQuery) {
  const selection = view.state.selection.main;
  const matches = matchingRanges(view.state, query);
  const current = matches.findIndex(
    (match) => match.from === selection.from && match.to === selection.to,
  );
  return {current: current < 0 ? 0 : current + 1, total: matches.length};
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
  switch (request.action) {
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
    const match = currentMatch(view, query)
      ?? forwardMatch(view, query, view.state.selection.main.from);
    if (match) {
      view.dispatch({
        changes: {from: match.from, to: match.to, insert: request.replacement},
        annotations: Transaction.userEvent.of("input.replace"),
      });
      sourceChanged = true;
      undoLabel = "Replace";
      selectMatch(view, forwardMatch(view, query, match.from + request.replacement.length));
    }
    break;
  }
  case "replaceAll": {
    const changes = matchingRanges(view.state, query).map((match) => ({
      ...match,
      insert: request.replacement,
    }));
    if (changes.length > 0) {
      view.dispatch({
        changes,
        annotations: Transaction.userEvent.of("input.replace.all"),
      });
      sourceChanged = true;
      undoLabel = "Replace All";
      selectMatch(view, forwardMatch(view, query, view.state.selection.main.from));
    }
    break;
  }
  }

  return {...summary(view, query), sourceChanged, undoLabel};
}

export function clearDocumentFind(view: EditorView) {
  closeSearchPanel(view);
}
