import remend, {isWithinMathBlock, type RemendOptions} from "remend";

const completionOptions = {
  // Scholium's math and literal-HTML dialect remains owned by its safe
  // renderer. Streaming must not reinterpret currency, operators or ranges.
  inlineKatex: false,
  katex: false,
  comparisonOperators: false,
  singleTilde: false,
  htmlTags: false,
} satisfies RemendOptions;

// CommonMark's Unicode whitespace class, rather than trimEnd()'s additional
// characters such as the authored BOM: https://spec.commonmark.org/0.31.2/#unicode-whitespace-character
const trailingWhitespace = /[\p{Zs}\t\n\f\r]+$/u;
const onlyWhitespace = /^[\p{Zs}\t\n\f\r]*$/u;

/** Display-only completion. The caller retains the exact source and performs
 * final parsing and safe HTML generation; this module never supplies HTML. */
export function completeStreamingMarkdown(source: string): string {
  // Native projection protects already parsed mathematical expressions. Leave
  // an unfinished mathematical tail literal as well, using the library's own
  // code-aware context and its valid-character-index contract.
  if (source.length > 0 && isWithinMathBlock(source, source.length - 1)) return source;
  const whitespace = source.match(trailingWhitespace)?.[0];
  if (!whitespace) return remend(source, completionOptions);
  const content = source.slice(0, -whitespace.length);
  if (!content) return source;

  // An emphasis delimiter after whitespace cannot close in CommonMark, while
  // Remend appends at EOF and may delete a final space. Complete the content
  // boundary and retain every received whitespace character outside it.
  const completed = remend(content, completionOptions);
  const suffix = completed.startsWith(content) ? completed.slice(content.length) : "";
  if (/^`+$/.test(suffix)) {
    // Code-span whitespace belongs inside the span. Let Remend's original
    // snapshot scan decide whether a closer is allowed in this paragraph,
    // then retain whitespace that its general-purpose trimming would remove.
    const original = remend(source, completionOptions);
    if (original.endsWith(suffix)) {
      const prefix = original.slice(0, -suffix.length);
      if (source.startsWith(prefix) && onlyWhitespace.test(source.slice(prefix.length))) {
        return source + suffix;
      }
    }
    return source;
  }
  return completed + whitespace;
}

// A standalone JavaScriptCore context has no DOM, module loader or host bridge.
// Expose only the deterministic string-to-string entry point used by Swift.
Object.defineProperty(globalThis, "scholiumCompleteStreamingMarkdown", {
  value: completeStreamingMarkdown,
  writable: false,
  configurable: false,
});
