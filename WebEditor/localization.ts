export const webInterfaceLocalizationKeys = [
  "File and image paste is not supported in Editor 1.0.",
  "Markdown editor, Edit mode",
  "Markdown source editor",
  "Heading level {level}",
  "Link",
  "Callout",
  "Quotation",
  "Table",
  "Bulleted list",
  "Numbered list",
  "Bold text",
  "Emphasized text",
  "Inline code",
  "Exact Markdown and YAML source",
  "Task item",
  "Show Link Annotation",
  "Hide Link Annotation",
  "linked note",
  "Markdown table",
  "Embedded note {title}",
  "Open embedded note {title}",
  "Embedded note content for {title}",
  "Embedded note",
  "Mathematics could not be rendered. Source is shown.",
  "Diagram rendering is unavailable. Mermaid source is shown.",
  "This Mermaid diagram is unsupported or could not be rendered. Source is shown.",
  "This Mermaid diagram could not be isolated safely. Source is shown.",
  "Mermaid source: {source}",
  "Add accTitle and accDescr to provide a concise nonvisual account of this diagram.",
  "This Mermaid diagram could not be rendered. Source is shown.",
  "Footnote {ordinal}",
  "Referenced footnote",
  "Edit mode is unavailable because YAML frontmatter is not closed. Use Source mode to finish the frontmatter.",
  "Edit mode unavailable",
  "Close the YAML frontmatter in Source mode to restore the visual projection.",
  "The editor could not preserve the exact source line endings.",
  "The Markdown editor could not start.",
  "The Review renderer stopped unexpectedly.",
  "No preview is available at the insertion point.",
  "Preview content",
  "Formatting actions",
  "Text Style",
  "Paragraph",
  "Heading {level}",
  "Bold",
  "Bold (⌘B)",
  "Italic",
  "Italic (⌘I)",
  "Strikethrough",
  "Highlight",
  "Link (⌘K)",
  "Wiki links",
  "Wiki",
  "Annotated Wikilink",
  "More Formatting",
  "Import Image…",
  "Index Image…",
  "Inline Code",
  "Code Block",
  "Lists",
  "Bullet List",
  "Numbered List",
  "Checkbox List",
  "Blockquote",
  "Comment",
  "Date",
  "Inline Math",
  "Display Math",
  "Mermaid",
  "Footnote",
  "Divider",
  "Orientation",
  "Introduces the note's purpose, scope, and route.",
  "Source",
  "Records sources that anchor the note without implying that they support every claim.",
  "Connections",
  "Routes the reader to a curated set of neighboring knowledge objects.",
  "Statement",
  "Isolates a claim, definition, principle, formula, distinction, or compact argument without endorsing it.",
  "Illustration",
  "Presents a scenario, example, thought experiment, or test case used in reasoning.",
  "Preserves source-specific wording with attribution.",
  "Caution",
  "Marks a limitation, unresolved dependency, source restriction, or interpretive warning.",
  "Note",
  "Preserves an unsupported callout without assigning a research role.",
  "Selection actions",
  "Return saves · Shift-Return adds a line · Escape cancels",
  "Submit Comment for QA",
  "Comment for line {start}",
  "Comment for lines {start} through {end}",
  "Open comment at line {start}",
  "Open comment at lines {start} through {end}",
  "Open {count} comments at line {start}",
  "Open {count} comments at lines {start} through {end}",
  "Could not save. Your Comment is still here.",
  "This Comment is too long to save here.",
  "Saving…",
] as const;

export type WebInterfaceLocalizationKey = typeof webInterfaceLocalizationKeys[number];

interface WebInterfaceLocalizationPayload {
  languageTag: string;
  strings: Partial<Record<WebInterfaceLocalizationKey, string>>;
}

const fallbackPayload: WebInterfaceLocalizationPayload = {
  languageTag: "en",
  strings: {},
};

function payloadFromDocument(): WebInterfaceLocalizationPayload {
  if (typeof document === "undefined") return fallbackPayload;
  const encoded = document.querySelector<HTMLMetaElement>(
    'meta[name="scholium-interface-localization"]',
  )?.content;
  if (!encoded) return fallbackPayload;
  try {
    const bytes = Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0));
    const candidate = JSON.parse(new TextDecoder().decode(bytes)) as Partial<WebInterfaceLocalizationPayload>;
    if (typeof candidate.languageTag !== "string"
        || !candidate.strings || typeof candidate.strings !== "object") return fallbackPayload;
    const strings: Partial<Record<WebInterfaceLocalizationKey, string>> = {};
    for (const key of webInterfaceLocalizationKeys) {
      const value = candidate.strings[key];
      if (typeof value === "string" && value.length <= 4_096) strings[key] = value;
    }
    return {languageTag: candidate.languageTag.slice(0, 32), strings};
  } catch {
    return fallbackPayload;
  }
}

let activePayload = payloadFromDocument();

export function localized(key: WebInterfaceLocalizationKey): string {
  return localizedFrom(activePayload, key);
}

export function localizedTemplate(
  key: WebInterfaceLocalizationKey,
  replacements: Readonly<Record<string, string | number>>,
): string {
  return localizedTemplateFrom(activePayload, key, replacements);
}

function localizedFrom(
  payload: WebInterfaceLocalizationPayload,
  key: WebInterfaceLocalizationKey,
) {
  return payload.strings[key] ?? key;
}

function localizedTemplateFrom(
  payload: WebInterfaceLocalizationPayload,
  key: WebInterfaceLocalizationKey,
  replacements: Readonly<Record<string, string | number>>,
) {
  return localizedFrom(payload, key).replace(/\{([A-Za-z]+)\}/g, (placeholder, name: string) =>
    Object.hasOwn(replacements, name) ? String(replacements[name]) : placeholder,
  );
}

const calloutLocalizationKeys = {
  orient: ["Orientation", "Introduces the note's purpose, scope, and route."],
  cite: ["Source", "Records sources that anchor the note without implying that they support every claim."],
  connect: ["Connections", "Routes the reader to a curated set of neighboring knowledge objects."],
  state: ["Statement", "Isolates a claim, definition, principle, formula, distinction, or compact argument without endorsing it."],
  illustrate: ["Illustration", "Presents a scenario, example, thought experiment, or test case used in reasoning."],
  quote: ["Quotation", "Preserves source-specific wording with attribution."],
  flag: ["Caution", "Marks a limitation, unresolved dependency, source restriction, or interpretive warning."],
  neutral: ["Note", "Preserves an unsupported callout without assigning a research role."],
} as const satisfies Record<string, readonly [WebInterfaceLocalizationKey, WebInterfaceLocalizationKey]>;

export function localizedCallout(
  identifier: string,
  fallback: {label: string; meaning: string},
) {
  if (activePayload.languageTag !== "zh-Hans") return fallback;
  const keys = calloutLocalizationKeys[identifier as keyof typeof calloutLocalizationKeys];
  return keys
    ? {label: localized(keys[0]), meaning: localized(keys[1])}
    : fallback;
}

export const localizationTesting = {
  install(payload: WebInterfaceLocalizationPayload) {
    activePayload = payload;
  },
  reset() {
    activePayload = payloadFromDocument();
  },
  resolve(
    payload: WebInterfaceLocalizationPayload,
    key: WebInterfaceLocalizationKey,
    replacements: Readonly<Record<string, string | number>> = {},
  ) {
    return localizedTemplateFrom(payload, key, replacements);
  },
};
