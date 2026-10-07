import {DOMParser} from "linkedom";
import {appendMarkdownBlocks} from "../markdown-fragment";

type Emphasis = "plain" | "italic" | "bold" | "bold-italic";
type FormattingRun = [text: string, emphasis: Emphasis];
interface FormattingFixture {
  name: string;
  html: string;
  kind: "citation" | "bibliography";
  paragraphs: FormattingRun[][];
}

// The expected runs express HTML intent independently of the production normalizer.
export const vendorFormattingFixtures: FormattingFixture[] = [
  {name: "adjacent italics", kind: "citation", html: "<i>one</i><i>two</i>", paragraphs: [[["onetwo", "italic"]]]},
  {name: "adjacent bold", kind: "citation", html: "<b>one</b><b>two</b>", paragraphs: [[["onetwo", "bold"]]]},
  {name: "adjacent italic then bold", kind: "citation", html: "<i>one</i><b>two</b>", paragraphs: [[["one", "italic"], ["two", "bold"]]]},
  {name: "adjacent bold then italic", kind: "citation", html: "<b>one</b><i>two</i>", paragraphs: [[["one", "bold"], ["two", "italic"]]]},
  {name: "nested italics", kind: "citation", html: "<i>one<i>two</i>three</i>", paragraphs: [[["onetwothree", "italic"]]]},
  {name: "nested bold", kind: "citation", html: "<b>one<b>two</b>three</b>", paragraphs: [[["onetwothree", "bold"]]]},
  {name: "bold within italic", kind: "citation", html: "<i>one <b>two</b> three</i>",
    paragraphs: [[["one ", "italic"], ["two", "bold-italic"], [" three", "italic"]]]},
  {name: "italic within bold", kind: "citation", html: "<b>one <i>two</i> three</b>",
    paragraphs: [[["one ", "bold"], ["two", "bold-italic"], [" three", "bold"]]]},
  {name: "adjacent nested mixed emphasis", kind: "citation", html: "<i><b>one</b></i><i><b>two</b></i>",
    paragraphs: [[["onetwo", "bold-italic"]]]},
  {name: "mixed punctuation and escapes", kind: "citation", html: "(<i>Book [A] &amp; é 😀!</i>), <b>Title: \\*_?&lt;literal&gt;</b>.",
    paragraphs: [[["(", "plain"], ["Book [A] & é 😀!", "italic"], ["), ", "plain"], ["Title: \\*_?<literal>", "bold"], [".", "plain"]]]},
  {name: "bibliography paragraph boundaries", kind: "bibliography", html: '<div class="csl-bib-body"><div class="csl-entry"><i>one</i><i>two</i>.</div><div class="csl-entry"><b>three <i>four</i></b>.</div></div>',
    paragraphs: [[["onetwo", "italic"], [".", "plain"]], [["three ", "bold"], ["four", "bold-italic"], [".", "plain"]]]},
  {name: "ordinary paragraph sequence", kind: "bibliography", html: "<p><i>one</i></p><p><b>two</b></p>",
    paragraphs: [[["one", "italic"]], [["two", "bold"]]]},
  {name: "wrapped ordinary paragraph sequence", kind: "bibliography", html: '<div class="csl-bib-body">\n<p><i>one</i></p>\n<p><b>two</b></p>\n</div>',
    paragraphs: [[["one", "italic"]], [["two", "bold"]]]},
  {name: "unwrapped bibliography entries", kind: "bibliography", html: '<div class="csl-entry"><i>one</i></div><div class="csl-entry"><b>two</b></div>',
    paragraphs: [[["one", "italic"]], [["two", "bold"]]]},
];

export const unrepresentableVendorFormatting = [
  "a<i>!</i>b",
  "a<b>?</b>b",
  "a<i><b>!</b></i>b",
];

export const unrepresentableVendorBlocks = [
  '<div class="csl-entry">one<div class="csl-entry">two</div>three</div>',
  'one<div class="csl-bib-body"><div class="csl-entry">two</div></div>',
  "<p>one</p>two",
  '<div class="csl-bib-body"><div class="csl-bib-body"><div class="csl-entry">one</div></div></div>',
  '<i>one<div class="csl-entry">two</div>three</i>',
  "<p>one</p><p></p><p>two</p>",
  '<div class="csl-bib-body"><div class="csl-entry">one</div><div class="csl-entry"> </div></div>',
  '<p>one<div class="csl-entry">two</div>three</p>',
];

/** Only the actual production fragment renderer determines Markdown semantics. */
export function renderedFormatting(markdown: string): FormattingRun[][] {
  const document = new DOMParser().parseFromString("<html><body></body></html>", "text/html");
  appendMarkdownBlocks(markdown, document.body);
  return Array.from(document.body.querySelectorAll("p")).map(paragraph => {
    const runs: FormattingRun[] = [];
    const walker = document.createTreeWalker(paragraph, 4); // DOM SHOW_TEXT
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const text = node.textContent ?? "", parent = node.parentElement;
      if (!text) continue;
      const italic = !!parent?.closest("em"), bold = !!parent?.closest("strong");
      const emphasis: Emphasis = bold ? italic ? "bold-italic" : "bold" : italic ? "italic" : "plain";
      const previous = runs.at(-1);
      if (previous?.[1] === emphasis) previous[0] += text;
      else runs.push([text, emphasis]);
    }
    return runs;
  });
}
