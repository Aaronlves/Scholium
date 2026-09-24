import {type Extension, type Range} from "@codemirror/state";
import {Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate} from "@codemirror/view";

export type ScholiumTextLanguage = "zh-Hans" | "en";

export interface ScholiumTextRange {
  from: number;
  to: number;
}

function isHan(codePoint: number) {
  return codePoint >= 0x3400 && codePoint <= 0x4dbf
    || codePoint >= 0x4e00 && codePoint <= 0x9fff
    || codePoint >= 0xf900 && codePoint <= 0xfaff
    || codePoint >= 0x20000 && codePoint <= 0x2ffff;
}

function isKanaOrHangul(codePoint: number) {
  return codePoint >= 0x3040 && codePoint <= 0x30ff
    || codePoint >= 0xac00 && codePoint <= 0xd7af;
}

function isCJKPunctuation(codePoint: number) {
  return codePoint >= 0x3000 && codePoint <= 0x303f
    || codePoint >= 0xff01 && codePoint <= 0xff65;
}

function isCJKPresentationCharacter(codePoint: number) {
  return isHan(codePoint) || isCJKPunctuation(codePoint);
}

/** Returns source ranges that should receive the Chinese presentation face. */
export function cjkPresentationRanges(text: string): ScholiumTextRange[] {
  const ranges: ScholiumTextRange[] = [];
  let runStart: number | undefined;
  for (let offset = 0; offset < text.length;) {
    const codePoint = text.codePointAt(offset) ?? 0;
    const width = codePoint > 0xffff ? 2 : 1;
    if (isCJKPresentationCharacter(codePoint)) {
      if (runStart === undefined) runStart = offset;
    } else if (runStart !== undefined) {
      ranges.push({from: runStart, to: offset});
      runStart = undefined;
    }
    offset += width;
  }
  if (runStart !== undefined) ranges.push({from: runStart, to: text.length});
  return ranges;
}

/**
 * Provides a presentation-only language hint for a physical editor line.
 * Mixed Han/Latin prose uses the CJK rule set; kana, Hangul, and lines with
 * no confidently supported script remain unlabelled instead of being guessed.
 */
export function languageForText(text: string): ScholiumTextLanguage | undefined {
  let han = false;
  let kanaOrHangul = false;
  let latin = false;
  for (const character of text) {
    const codePoint = character.codePointAt(0) ?? 0;
    if (isHan(codePoint)) han = true;
    else if (isKanaOrHangul(codePoint)) kanaOrHangul = true;
    else if (codePoint >= 0x41 && codePoint <= 0x5a
      || codePoint >= 0x61 && codePoint <= 0x7a) latin = true;
  }
  if (kanaOrHangul) return undefined;
  if (han) return "zh-Hans";
  if (latin) return "en";
  return undefined;
}

function languageDecorations(view: EditorView): DecorationSet {
  const ranges: Array<Range<Decoration>> = [];
  const seen = new Set<number>();
  const seenCJK = new Set<string>();
  for (const visible of view.visibleRanges) {
    let line = view.state.doc.lineAt(visible.from);
    while (line.from <= visible.to) {
      if (!seen.has(line.from)) {
        seen.add(line.from);
        const language = languageForText(line.text);
        if (language) ranges.push(Decoration.line({attributes: {lang: language}}).range(line.from));
      }
      for (const cjk of cjkPresentationRanges(line.text)) {
        const from = Math.max(line.from + cjk.from, visible.from);
        const to = Math.min(line.from + cjk.to, visible.to);
        const key = `${from}:${to}`;
        if (to > from && !seenCJK.has(key)) {
          seenCJK.add(key);
          ranges.push(Decoration.mark({
            class: "cm-live-cjk",
            attributes: {lang: "zh-Hans"},
          }).range(from, to));
        }
      }
      if (line.number >= view.state.doc.lines || line.to >= visible.to) break;
      line = view.state.doc.line(line.number + 1);
    }
  }
  return Decoration.set(ranges, true);
}

/** Presentation-only, viewport-bounded language context for mixed-script text. */
export const documentTextLanguage: Extension = ViewPlugin.fromClass(class {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = languageDecorations(view);
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = languageDecorations(update.view);
    }
  }
}, {
  decorations: value => value.decorations,
});
