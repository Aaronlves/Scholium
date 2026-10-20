import type {ExactSourceMirror} from "./state";
import type {EditorScrollAnchor} from "./protocol";
import {validatedReaderConfiguration, type ReadLinkPreview, type ReaderConfiguration} from "./reader-configuration";

/** Native sanitized committed rendering. It never participates in writable source/history. */
export interface CommittedReviewProjection {
  documentID: string;
  sourceFingerprint: string;
  htmlBody: string;
  css: string;
  configuration: ReaderConfiguration;
}

export function validCommittedReviewProjection(value: unknown): value is CommittedReviewProjection {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const projection = value as Partial<CommittedReviewProjection>;
  const config = validatedReaderConfiguration(projection.configuration);
  return typeof projection.documentID === "string" && projection.documentID.length > 0 && projection.documentID.length <= 4096
    && typeof projection.sourceFingerprint === "string" && projection.sourceFingerprint.length <= 256
    && typeof projection.htmlBody === "string" && projection.htmlBody.length <= 16_777_216
    && typeof projection.css === "string" && projection.css.length <= 2_000_000
    && Boolean(config && config.fingerprint === projection.sourceFingerprint && !config.replyProjection);
}

/** A scope wrapper preserves sanitized user selectors, strings and declarations verbatim. */
export function wrapReviewCSS(css: string): string {
  return `@scope (.scholium-review-projection) { ${css} }`;
}

/** Scope native page selectors without rewriting declaration values or comments. */
export function scopedReviewCSS(css: string, rootVariables: "inherit" | "local" = "inherit"): string {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(css);
  const visit = (rules: CSSRuleList) => {
    for (const rule of rules) {
      if ("selectorText" in rule) {
        const style = rule as CSSStyleRule;
        style.selectorText = style.selectorText.replace(/(^|[\s,(>+~])(:root|html|body)(?=$|[\s,.#:\[>+~)])/g,
          (_match, prefix: string, token: string) => prefix + (token === ":root" && rootVariables === "inherit" ? token : ":scope"));
      }
      if ("cssRules" in rule) visit((rule as CSSGroupingRule).cssRules);
    }
  };
  visit(sheet.cssRules);
  // The editor page already installs the same native root defaults. In base
  // CSS, :root remains outside this scope and its variables are inherited,
  // including native Accent/appearance projections. The later configuration
  // stylesheet maps :root locally so its chosen typography and compact insets
  // have the same scoping proximity as these base rules.
  return wrapReviewCSS(Array.from(sheet.cssRules, rule => rule.cssText).join("\n"));
}

export function reviewProjectionMatches(projection: CommittedReviewProjection | null | undefined,
  documentID: string, fingerprint: string, dirty: boolean): projection is CommittedReviewProjection {
  return !dirty && Boolean(projection && validCommittedReviewProjection(projection)
    && projection.sourceFingerprint === fingerprint && projection.documentID === documentID);
}


/** The embedded reader uses exact-source UTF-16; the editor bridge uses CodeMirror UTF-16. */
export function mapReviewAnchor(anchor: EditorScrollAnchor, mirror: ExactSourceMirror,
  target: "exact" | "normalized"): EditorScrollAnchor | null {
  const convert = (value: number) => target === "exact" ? mirror.exactOffset(value) : mirror.normalizedOffset(value);
  const sourceUTF16Offset = convert(anchor.sourceUTF16Offset);
  const blockUTF16LowerBound = convert(anchor.blockUTF16LowerBound);
  const blockUTF16UpperBound = convert(anchor.blockUTF16UpperBound);
  if (sourceUTF16Offset === null || blockUTF16LowerBound === null || blockUTF16UpperBound === null) return null;
  return {...anchor, sourceUTF16Offset, blockUTF16LowerBound, blockUTF16UpperBound};
}

/** JSON transports dictionary order, which is never reader identity or semantic change. */
export function reviewConfigurationSharesDOM(left: ReaderConfiguration, right: ReaderConfiguration): boolean {
  const leftStrings = left.localization.strings, rightStrings = right.localization.strings;
  return left.version === right.version && left.documentID === right.documentID
    && left.fingerprint === right.fingerprint && left.loadGeneration === right.loadGeneration
    && left.selectionEnabled === right.selectionEnabled && left.imagePreviewsEnabled === right.imagePreviewsEnabled
    && (left.replyProjection ?? false) === (right.replyProjection ?? false)
    && left.testingEnabled === right.testingEnabled && left.localization.languageTag === right.localization.languageTag
    && Object.keys(leftStrings).length === Object.keys(rightStrings).length
    && Object.entries(leftStrings).every(([key, value]) => rightStrings[key as keyof typeof rightStrings] === value);
}

export function readLinkPreviewsEqual(left: readonly ReadLinkPreview[], right: readonly ReadLinkPreview[]): boolean {
  return left.length === right.length && left.every((preview, index) => {
    const other = right[index];
    return preview.utf16LowerBound === other.utf16LowerBound && preview.utf16UpperBound === other.utf16UpperBound
      && preview.title === other.title && preview.isEmbedded === other.isEmbedded
      && preview.fragment === other.fragment && preview.htmlBody === other.htmlBody;
  });
}
