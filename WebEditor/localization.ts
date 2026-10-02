export const webInterfaceLocalizationKeys = [
  "Tab",
  "AI",
  "Index",
  "Accept AI continuation: {text} (Tab)",
  "Accept index suggestion: {text} (Tab)",
  "AI continuation timed out.",
  "AI continuation is preparing.",
  "AI continuation is retrieving related context.",
  "AI continuation is composing.",
  "AI continuation is not enabled.",
  "AI continuation is not connected. Connect Codex in Agents & Chat.",
  "AI continuation is not ready. Check Writing Assistance settings.",
  "The selected AI continuation model is unavailable. Choose an available model in Writing Assistance.",
  "AI continuation is still stopping. Try again in a moment.",
  "AI continuation could not connect. Check Agents & Chat.",
  "AI continuation timed out. Library completion remains available.",
  "AI returned no usable continuation. Library completion remains available.",
  "AI continuation could not be used for this writing context.",
  "AI continuation was cancelled.",
  "AI continuation could not be generated. Library completion remains available.",

  "The edited Markdown document exceeds the supported editor size.",
  "Finish editing the note title before switching documents.",
  "The insertion position changed. Confirm the cursor again.",
  "The reference is too large.",
  "Finish composition before adopting a suggestion.",
  "Finish composition before changing note information.",
  "The note changed. Reload Note Info before applying changes.",
  "The passage changed. Request a new suggestion.",
  "The suggestion is too large.",
  "Copy",
  "Expand",
  "YAML frontmatter",
  "File and image paste is not supported in Editor 1.0.",
  "Markdown editor, Edit mode",
  "Markdown source editor",
  "Note title",
  "Empty Note",
  "This note has no body content.",
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
  "Completed task",
  "Incomplete task",
  "Show Link Annotation for {title}",
  "Hide Link Annotation for {title}",
  "Link Annotation",
  "Callout: {title}",
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
  "Footnotes",
  "Return to footnote reference {ordinal}",
  "Edit mode unavailable",
  "Close the YAML frontmatter in Source mode to restore the visual projection.",
  "The editor could not preserve the exact source line endings.",
  "The replacement would make the document too large.",
  "The Markdown editor could not start.",
  "The Review renderer stopped unexpectedly.",
  "No preview is available at the insertion point.",
  "Preview content",
  "Paragraph",
  "Bold",
  "Italic",
  "Strikethrough",
  "Highlight",
  "Annotated Wikilink",
  "Inline Code",
  "Code Block",
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
  "{label}. {meaning}",
] as const;

export type WebInterfaceLocalizationKey = typeof webInterfaceLocalizationKeys[number];

export interface WebInterfaceLocalizationPayload {
  languageTag: string;
  strings: Partial<Record<WebInterfaceLocalizationKey, string>>;
}

const fallbackPayload: WebInterfaceLocalizationPayload = {
  languageTag: "en",
  strings: {},
};

const templatePlaceholder = /\{([A-Za-z][A-Za-z0-9_]*)\}/g;
const interfaceLanguageIdentifier = /^[A-Za-z]{2,8}(?:[-_][A-Za-z0-9]{1,8})*$/;

function placeholders(value: string) {
  return [...value.matchAll(templatePlaceholder)].map(match => match[1]).sort().join("\0");
}

/** Native and page-side language identifiers resolve to the same two shipped languages. */
export function supportedInterfaceLanguage(identifier: string): "en" | "zh-Hans" {
  if (identifier.length > 64 || !interfaceLanguageIdentifier.test(identifier)) return "en";
  const normalized = identifier.replaceAll("_", "-").toLowerCase();
  const parts = normalized.split("-");
  return parts[0] === "zh" && (parts.length === 1 || parts[1] === "hans"
    || parts[1] === "cn" || parts[1] === "sg") ? "zh-Hans" : "en";
}

/** Only registered, bounded interface copy crosses this boundary; source never does. */
export function validatedInterfaceLocalization(value: unknown): WebInterfaceLocalizationPayload | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const candidate = value as {languageTag?: unknown; strings?: unknown};
  if (typeof candidate.languageTag !== "string" || candidate.languageTag.length > 64
      || !interfaceLanguageIdentifier.test(candidate.languageTag)
      || !candidate.strings || typeof candidate.strings !== "object"
      || Array.isArray(candidate.strings)) return null;
  const strings: Partial<Record<WebInterfaceLocalizationKey, string>> = {};
  const languageTag = supportedInterfaceLanguage(candidate.languageTag);
  if (languageTag === "en" && !/^en(?:[-_]|$)/i.test(candidate.languageTag)) {
    return {...fallbackPayload};
  }
  const entries = candidate.strings as Record<string, unknown>;
  for (const key of webInterfaceLocalizationKeys) {
    if (!Object.hasOwn(entries, key)) continue;
    const translation = entries[key];
    if (typeof translation === "string" && translation.trim().length > 0
        && translation.length <= 4_096 && placeholders(translation) === placeholders(key)) {
      strings[key] = translation;
    }
  }
  return {languageTag, strings};
}

export function interfaceLocalizationFromBase64(encoded: string): WebInterfaceLocalizationPayload {
  // The registered table is small; never allocate an unbounded metadata payload.
  if (!encoded || encoded.length > 2_796_204) return fallbackPayload;
  try {
    const bytes = Uint8Array.from(atob(encoded), character => character.charCodeAt(0));
    if (bytes.byteLength > 2_097_152) return fallbackPayload;
    return validatedInterfaceLocalization(JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(bytes)))
      ?? fallbackPayload;
  } catch {
    return fallbackPayload;
  }
}

function payloadFromDocument(): WebInterfaceLocalizationPayload {
  if (typeof document === "undefined") return fallbackPayload;
  const encoded = document.querySelector<HTMLMetaElement>(
    'meta[name="scholium-interface-localization"]',
  )?.content;
  return interfaceLocalizationFromBase64(encoded ?? "");
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
  return localizedFrom(payload, key).replace(templatePlaceholder, (placeholder, name: string) =>
    Object.hasOwn(replacements, name) ? String(replacements[name]) : placeholder,
  );
}

/** Review retains its own payload so an instance never changes another surface's copy. */
export function createInterfaceLocalizer(payload: WebInterfaceLocalizationPayload) {
  const localization = validatedInterfaceLocalization(payload) ?? fallbackPayload;
  return (key: WebInterfaceLocalizationKey, replacements: Readonly<Record<string, string | number>> = {}) =>
    localizedTemplateFrom(localization, key, replacements);
}

export const calloutLocalizationKeys = {
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
    activePayload = validatedInterfaceLocalization(payload) ?? fallbackPayload;
  },
  reset() {
    activePayload = payloadFromDocument();
  },
  resolve(
    payload: WebInterfaceLocalizationPayload,
    key: WebInterfaceLocalizationKey,
    replacements: Readonly<Record<string, string | number>> = {},
  ) {
    return createInterfaceLocalizer(payload)(key, replacements);
  },
};
