import {markdown, markdownLanguage} from "@codemirror/lang-markdown";
import {yamlFrontmatter} from "@codemirror/lang-yaml";
import {scholiumMarkdownDialect} from "./scholium-markdown";

/**
 * One CodeMirror language owner for complete Scholium note source.
 *
 * The YAML wrapper keeps frontmatter and Markdown in one incremental Lezer
 * tree. Scholium-specific syntax extensions can be added to the Markdown
 * content language here without creating a second parser configuration in a
 * mode adapter.
 */
export const scholiumNoteLanguage = yamlFrontmatter({
  content: markdown({base: markdownLanguage, extensions: scholiumMarkdownDialect}),
});
