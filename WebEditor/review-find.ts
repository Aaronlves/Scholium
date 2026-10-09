import {documentFindMatches} from "./document-find-matching";

export interface ReviewFindRequest {
  operation?: "clear";
  action?: "present" | "update" | "next" | "previous";
  query: string;
  caseSensitive: boolean;
  wholeWord: boolean;
}

export interface ReviewFindResult {
  current: number;
  total: number;
}

type HighlightRegistry = Map<string, Highlight> & {
  delete(name: string): boolean;
  set(name: string, highlight: Highlight): unknown;
};

function highlightRegistry(): HighlightRegistry | null {
  return (CSS as typeof CSS & {highlights?: HighlightRegistry}).highlights ?? null;
}

function textNodesIn(element: Element): Text[] {
  const nodes: Text[] = [];
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      const parent = node.parentElement;
      if (!parent || !node.textContent) return NodeFilter.FILTER_REJECT;
      if (parent.closest(
        'script, style, [hidden], [aria-hidden="true"], #scholium-preview-popover',
      )) return NodeFilter.FILTER_REJECT;
      if (parent.closest('[data-scholium-protected="mermaid"]')) {
        return NodeFilter.FILTER_REJECT;
      }
      return NodeFilter.FILTER_ACCEPT;
    },
  });
  while (walker.nextNode()) {
    if (walker.currentNode instanceof Text) nodes.push(walker.currentNode);
  }
  return nodes;
}

function rangeFor(nodes: Text[], start: number, end: number): Range | null {
  let offset = 0;
  let startNode: Text | null = null;
  let startOffset = 0;
  let endNode: Text | null = null;
  let endOffset = 0;
  for (const node of nodes) {
    const next = offset + node.data.length;
    if (!startNode && start >= offset && start <= next) {
      startNode = node;
      startOffset = start - offset;
    }
    if (!endNode && end >= offset && end <= next) {
      endNode = node;
      endOffset = end - offset;
      break;
    }
    offset = next;
  }
  if (!startNode || !endNode) return null;
  const range = new Range();
  range.setStart(startNode, startOffset);
  range.setEnd(endNode, endOffset);
  return range;
}

function searchableLines(): Element[] {
  const root = document.querySelector("main");
  if (!root) return [];
  const lines = Array.from(root.querySelectorAll("[data-source-line]"))
    .filter((element) => !element.querySelector("[data-source-line]"));
  return lines.length > 0 ? lines : [root];
}

function rangesFor(request: ReviewFindRequest): Range[] {
  if (!request.query) return [];
  const result: Range[] = [];
  for (const line of searchableLines()) {
    const nodes = textNodesIn(line);
    const text = nodes.map((node) => node.data).join("");
    for (const match of documentFindMatches(text, {
      query: request.query, caseSensitive: request.caseSensitive, wholeWord: request.wholeWord,
    })) {
      const range = rangeFor(nodes, match.from, match.to);
      if (range) result.push(range);
    }
  }
  return result;
}

export function installReviewFind(): {
  perform(request: ReviewFindRequest): ReviewFindResult;
} {
  const allName = "scholium-review-find";
  const currentName = "scholium-review-find-current";
  const registry = highlightRegistry();
  let signature = "";
  let matches: Range[] = [];
  let current = -1;

  const style = document.createElement("style");
  style.textContent = `
    ::highlight(scholium-review-find) {
      background: color-mix(in srgb, var(--scholium-color-accent) 22%, transparent);
    }
    ::highlight(scholium-review-find-current) {
      background: color-mix(in srgb, var(--scholium-color-accent) 42%, transparent);
      text-decoration: underline;
      text-decoration-color: var(--scholium-color-accent);
    }
  `;
  document.head.appendChild(style);

  const clear = () => {
    registry?.delete(allName);
    registry?.delete(currentName);
  };
  const present = (scrollToMatch: boolean) => {
    clear();
    if (matches.length === 0 || current < 0) return;
    if (registry) {
      const ordinary = matches.filter((_, index) => index !== current);
      if (ordinary.length > 0) registry.set(allName, new Highlight(...ordinary));
      registry.set(currentName, new Highlight(matches[current]));
    }
    if (scrollToMatch) {
      const target = matches[current].startContainer.parentElement;
      for (let ancestor = target; ancestor; ancestor = ancestor.parentElement) {
        if (ancestor.tagName.toLowerCase() === "details") ancestor.setAttribute("open", "");
      }
      target?.scrollIntoView({block: "center", behavior: "auto"});
    }
  };

  return {
    perform(request) {
      if (!request || request.operation === "clear") {
        signature = "";
        matches = [];
        current = -1;
        clear();
        return {current: 0, total: 0};
      }
      const nextSignature = JSON.stringify([
        request.query, request.caseSensitive, request.wholeWord,
      ]);
      if (nextSignature !== signature || request.action === "update") {
        signature = nextSignature;
        matches = rangesFor(request);
        current = matches.length > 0 ? 0 : -1;
      } else if (request.action === "next" && matches.length > 0) {
        current = (current + 1) % matches.length;
      } else if (request.action === "previous" && matches.length > 0) {
        current = (current - 1 + matches.length) % matches.length;
      }
      present(request.action !== "present");
      return {current: current < 0 ? 0 : current + 1, total: matches.length};
    },
  };
}
