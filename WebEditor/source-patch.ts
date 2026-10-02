import {normalizedDocumentText} from "./state";

/** Exact-source patch captured by a native source-property editor. */
export function sourcePatch(source: string, expected: string, from: number, to: number, replacement: string) {
  if (source !== expected || !Number.isSafeInteger(from) || !Number.isSafeInteger(to)
      || from < 0 || to < from || to > source.length) return null;
  const boundary = (offset: number) => offset === 0 || offset === source.length
    || !(source.charCodeAt(offset - 1) === 13 && source.charCodeAt(offset) === 10)
      && !(source.charCodeAt(offset - 1) >= 0xD800 && source.charCodeAt(offset - 1) <= 0xDBFF
        && source.charCodeAt(offset) >= 0xDC00 && source.charCodeAt(offset) <= 0xDFFF);
  if (!boundary(from) || !boundary(to)
      || from === 0 && source.charCodeAt(0) === 0xFEFF && replacement.charCodeAt(0) !== 0xFEFF) return null;
  return {
    from: normalizedDocumentText(source.slice(0, from)).length,
    to: normalizedDocumentText(source.slice(0, to)).length,
    insert: normalizedDocumentText(replacement), exactInsert: replacement,
  };
}
