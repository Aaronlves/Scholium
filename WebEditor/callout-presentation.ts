import type {MarkdownEditingDialect} from "./protocol";
import {localized, localizedCallout} from "./localization";

export type ResolvedCallout = MarkdownEditingDialect["callouts"][number];

const neutralCallout: ResolvedCallout = {
  identifier: "neutral",
  aliases: [],
  label: localized("Note"),
  meaning: localized("Preserves an unsupported callout without assigning a research role."),
};

export function calloutDefinition(
  dialect: MarkdownEditingDialect | null,
  rawKind: string,
): ResolvedCallout {
  const kind = rawKind.toLowerCase().replace(/:+$/, "").trim();
  const definition = dialect?.callouts.find((callout) =>
    callout.identifier === kind || callout.aliases.includes(kind),
  ) ?? neutralCallout;
  return {...definition, ...localizedCallout(definition.identifier, definition)};
}

export function calloutHeader(text: string): RegExpExecArray | null {
  return /^(\s*(?:>\s*)+)\[!([^\]]+)\]([+-])?\s*(.*)$/.exec(text);
}
