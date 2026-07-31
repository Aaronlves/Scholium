import {markdown, markdownLanguage} from "@codemirror/lang-markdown";
import {yamlFrontmatter} from "@codemirror/lang-yaml";
import {NodeProp} from "@lezer/common";
import {scholiumMarkdownDialect} from "./scholium-markdown";

// CodeMirror's bidiIsolates extension consumes language-owned NodeProp.isolate
// metadata. Markdown does not provide it by default, so the one Scholium note
// language declares which complete constructs must remain coherent when their
// neutral delimiters appear inside an opposite-direction line.
const markdownBidiIsolation = {
  props: [NodeProp.isolate.add({
    Emphasis: "auto",
    StrongEmphasis: "auto",
    Strikethrough: "auto",
    Highlight: "auto",
    InlineFootnote: "auto",
    InlineCode: "ltr",
    InlineMath: "ltr",
    Link: "ltr",
    Autolink: "ltr",
    WikiLink: "ltr",
    VectorLink: "ltr",
    FootnoteReference: "ltr",
  })],
};

/**
 * One CodeMirror language owner for complete Scholium note source.
 *
 * The YAML wrapper keeps frontmatter and Markdown in one incremental Lezer
 * tree. Scholium-specific syntax extensions can be added to the Markdown
 * content language here without creating a second parser configuration in a
 * mode adapter.
 */
export const scholiumNoteLanguage = yamlFrontmatter({
  content: markdown({
    base: markdownLanguage,
    extensions: [scholiumMarkdownDialect, markdownBidiIsolation],
  }),
});
