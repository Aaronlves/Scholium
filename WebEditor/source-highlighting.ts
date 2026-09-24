import {HighlightStyle, syntaxHighlighting} from "@codemirror/language";
import {tags} from "@lezer/highlight";

// The retained Lezer tree supplies token ranges. Source adds only color;
// typographic emphasis changes WebKit's accessible plain-text serialization.
// Highlighting never substitutes text, changes offsets, or adds widgets.
const sourceHighlightStyle = HighlightStyle.define([
  {tag: tags.heading, class: "cm-source-heading"},
  {tag: tags.link, class: "cm-source-link"},
  {tag: tags.definition(tags.propertyName), class: "cm-source-yaml-key"},
  {tag: tags.processingInstruction, class: "cm-source-marker"},
  {tag: tags.meta, class: "cm-source-meta"},
  {tag: tags.url, class: "cm-source-url"},
  {tag: tags.comment, class: "cm-source-comment"},
]);

export const sourceHighlighting = syntaxHighlighting(sourceHighlightStyle);
