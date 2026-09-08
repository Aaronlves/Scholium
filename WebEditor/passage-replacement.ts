import {normalizedDocumentText} from "./state";

/** Exact captured revision and source offsets only; never relocate a passage by wording. */
export function passageReplacement(source: string, expected: string, from: number, to: number, replacement: string) {
  if (source !== expected || !Number.isSafeInteger(from) || !Number.isSafeInteger(to)
      || from < 0 || to <= from || to > source.length || replacement.length === 0) return null;
  function boundary(offset: number) {
    if (offset <= 0 || offset >= source.length) return true;
    const before = source.charCodeAt(offset - 1), after = source.charCodeAt(offset);
    return !(before === 13 && after === 10)
      && !(before >= 0xD800 && before <= 0xDBFF && after >= 0xDC00 && after <= 0xDFFF);
  }
  if (!boundary(from) || !boundary(to)) return null;
  return {from: normalizedDocumentText(source.slice(0, from)).length,
    to: normalizedDocumentText(source.slice(0, to)).length, insert: normalizedDocumentText(replacement)};
}
