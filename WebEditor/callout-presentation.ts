import type {MarkdownEditingDialect} from "./protocol";
import {localized, localizedCallout} from "./localization";

export type ResolvedCallout = MarkdownEditingDialect["callouts"][number];

/** A role's inter-block gap uses the surrounding prose em, not its scaled content. */
export function calloutSourceGapCSS(identifier: string): string {
  const role = /^[a-z][a-z0-9-]{0,31}$/.test(identifier) ? identifier : "neutral";
  return `calc(var(--scholium-callout-${role}-gap-ems, var(--scholium-callout-gap-ems)) * var(--scholium-callout-source-em))`;
}

export function calloutDefinition(
  dialect: MarkdownEditingDialect | null,
  rawKind: string,
): ResolvedCallout {
  const kind = rawKind.toLowerCase().replace(/:+$/, "").trim();
  const definition = dialect?.callouts.find((callout) => callout.identifier === kind) ?? {
    identifier: "neutral",
    label: localized("Note"),
    meaning: localized("Preserves an unsupported callout without assigning a research role."),
  };
  return {...definition, ...localizedCallout(definition.identifier, definition)};
}

export function calloutHeader(text: string): RegExpExecArray | null {
  return /^(\s*(?:>\s*)+)\[!([^\]]+)\]([+-])?\s*(.*)$/.exec(text);
}
