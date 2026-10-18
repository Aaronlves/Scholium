import {detectType, parse as parsePele, PeleError, render as renderPele} from "pele";

export type ScholiumMermaidDiagramKind = string;

export interface ScholiumMermaidRenderRequest {
  readonly source: string;
  readonly themeRoot?: Element;
  readonly signal?: AbortSignal;
}

export type ScholiumMermaidFailureReason =
  | "invalid-source"
  | "invalid-theme"
  | "unsupported-diagram"
  | "unsafe-syntax"
  | "cancelled"
  | "render-failed"
  | "unsafe-output";

export type ScholiumMermaidRenderResult =
  | {
      readonly ok: true;
      readonly svg: SVGSVGElement;
      readonly kind: ScholiumMermaidDiagramKind;
      readonly accessibilityWarning: boolean;
    }
  | {readonly ok: false; readonly reason: ScholiumMermaidFailureReason};

export interface ScholiumMermaidRuntime {
  readonly version: 3;
  render(request: ScholiumMermaidRenderRequest): Promise<ScholiumMermaidRenderResult>;
  copy(svg: SVGSVGElement): SVGSVGElement | null;
  mount(host: HTMLElement, svg: SVGSVGElement): boolean;
}

const maximumSourceLength = 32_768;
const maximumLineCount = 512;
let renderSequence = 0;

const deniedStatement = /(?:^|[;\r\n])\s*(?:click|href|class|classDef|style|linkStyle|UpdateElementStyle|UpdateRelStyle)\b/i;
const deniedTodayMarkerStyle = /(?:^|[;\r\n])\s*todayMarker\b(?![ \t]+off[ \t]*(?:[;\r\n]|$))/i;
const deniedResourceSyntax = /(?:icon\s*::|img\s*:|image\s*:)/i;
const deniedEmbeddedResourceElement = /<\s*\/?\s*(?:a|audio|embed|iframe|image|img|link|object|picture|source|video)\b/i;
const deniedClassSyntax = /:::[A-Za-z_]/;
const externalValue = /(?:javascript\s*:|data\s*:|https?\s*:|file\s*:|blob\s*:|@import)/i;
const urlFunction = /url\(\s*([^)]+)\s*\)/gi;
const deniedCSSControl = /(?::host(?:-context)?\b|::slotted\b)/i;
const deniedElements = new Set([
  "a", "animate", "animatemotion", "animatetransform", "embed", "foreignobject",
  "iframe", "image", "object", "script", "set", "use",
]);
const sanitizedSVGNodes = new WeakSet<Element>();
const isolatedSVGStyle = `
:host {
  display: block;
  max-inline-size: 100%;
  contain: paint;
  isolation: isolate;
}
svg {
  display: block !important;
  inline-size: var(--scholium-diagram-inline-size, auto) !important;
  min-inline-size: 0 !important;
  max-inline-size: 100% !important;
  block-size: var(--scholium-diagram-block-size, auto) !important;
  max-block-size: var(--scholium-diagram-max-block-size, min(70vh, 42rem)) !important;
  margin-inline: auto !important;
}
*, *::before, *::after {
  animation: none !important;
  transition: none !important;
}
`;

function hasAccessibilityMetadata(source: string) {
  const hasTitle = /^\s*accTitle\s*:\s*\S.*$/im.test(source);
  const hasDescription = /^\s*accDescr\s*:\s*\S.*$/im.test(source)
    || /^\s*accDescr\s*\{[\s\S]*?\S[\s\S]*?^\s*\}\s*$/im.test(source);
  return hasTitle && hasDescription;
}

export function validateMermaidSource(source: unknown):
  | {readonly ok: true; readonly accessibilityWarning: boolean}
  | {readonly ok: false; readonly reason: Exclude<ScholiumMermaidFailureReason, "cancelled" | "render-failed" | "unsafe-output">} {
  if (typeof source !== "string"
      || source.trim().length === 0
      || source.length > maximumSourceLength
      || source.split(/\r\n|\r|\n/).length > maximumLineCount) {
    return {ok: false, reason: "invalid-source"};
  }
  if (/^\s*---(?:\r?\n|\r)/.test(source)
      || /%%\s*\{/.test(source)
      || deniedStatement.test(source)
      || deniedTodayMarkerStyle.test(source)
      || (detectType(source) === "sequence" && /(?:^|[;\r\n])\s*rect\b/i.test(source))
      || deniedClassSyntax.test(source)
      || deniedResourceSyntax.test(source)
      || deniedEmbeddedResourceElement.test(source)) {
    return {ok: false, reason: "unsafe-syntax"};
  }
  return {ok: true, accessibilityWarning: !hasAccessibilityMetadata(source)};
}

function valueHasUnsafeURL(value: string) {
  if (externalValue.test(value)) return true;
  urlFunction.lastIndex = 0;
  for (let match = urlFunction.exec(value); match; match = urlFunction.exec(value)) {
    const destination = match[1].trim().replace(/^['"]|['"]$/g, "");
    if (!/^#[A-Za-z_][A-Za-z0-9_.:-]*$/.test(destination)) return true;
  }
  return false;
}

export function sanitizeMermaidSVG(svg: string, parser: DOMParser = new DOMParser()): SVGSVGElement | null {
  if (typeof svg !== "string" || svg.length === 0 || svg.length > 2_000_000) return null;
  const parsed = parser.parseFromString(svg, "image/svg+xml");
  const root = parsed.documentElement;
  if (!root
      || root.localName.toLowerCase() !== "svg"
      || parsed.querySelector("parsererror")) return null;

  for (const element of [root, ...root.querySelectorAll("*")]) {
    const name = element.localName.toLowerCase();
    if (deniedElements.has(name)) return null;
    if (name === "style"
        && (valueHasUnsafeURL(element.textContent ?? "")
          || deniedCSSControl.test(element.textContent ?? ""))) return null;
    for (const attribute of [...element.attributes]) {
      const attributeName = attribute.name.toLowerCase();
      if (attributeName === "xmlns" || attributeName === "xmlns:xlink") continue;
      if (attributeName.startsWith("on") || attributeName === "href" || attributeName === "xlink:href") {
        return null;
      }
      if (valueHasUnsafeURL(attribute.value)
          || (attributeName === "style" && deniedCSSControl.test(attribute.value))) return null;
    }
  }
  root.setAttribute("role", "img");
  root.setAttribute("focusable", "false");
  sanitizedSVGNodes.add(root);
  return root as unknown as SVGSVGElement;
}

export function mountMermaidSVG(host: HTMLElement, svg: SVGSVGElement): boolean {
  if (!host || host.shadowRoot || !sanitizedSVGNodes.has(svg)) return false;
  sanitizedSVGNodes.delete(svg);
  const shadow = host.attachShadow({mode: "open"});
  const style = host.ownerDocument.createElement("style");
  style.textContent = isolatedSVGStyle;
  shadow.append(svg, style);
  return true;
}

/** Only an unconsumed admitted node can yield another independently admitted node. */
export function copyMermaidSVG(svg: SVGSVGElement, parser: DOMParser = new DOMParser()): SVGSVGElement | null {
  if (!sanitizedSVGNodes.has(svg)) return null;
  return sanitizeMermaidSVG(svg.outerHTML, parser);
}

interface ScholiumMermaidTheme {
  readonly fontFamily: string;
  readonly variables: Readonly<Record<string, string>>;
}

type MermaidThemeStyle = Pick<CSSStyleDeclaration, "getPropertyValue">;

function semanticColor(style: MermaidThemeStyle, name: string, systemAccent?: string) {
  const value = style.getPropertyValue(name).trim();
  if (/^#[0-9a-f]{6}$/i.test(value)) return value;
  // The document keeps Accent live. Resolve it for the admitted SVG so all
  // diagram colors still come from the protected native semantic palette.
  if (name === "--scholium-color-accent" && value === "-apple-system-control-accent") {
    return systemAccent ?? value;
  }
  return null;
}

function cssRGBToHex(value: string) {
  const match = /^rgba?\(([^)]+)\)$/i.exec(value.trim());
  if (!match) return null;
  const channels = match[1].split(/[,\s/]+/).filter(Boolean).slice(0, 3);
  if (channels.length !== 3) return null;
  const values = channels.map((channel) => {
    if (channel.endsWith("%")) return Number.parseFloat(channel) * 2.55;
    return Number.parseFloat(channel);
  });
  if (values.some((channel) => !Number.isFinite(channel) || channel < 0 || channel > 255)) return null;
  return `#${values.map((channel) => Math.round(channel).toString(16).padStart(2, "0")).join("")}`;
}

function resolvedSystemAccent(themeRoot: Element) {
  const style = getComputedStyle(themeRoot);
  if (style.getPropertyValue("--scholium-color-accent").trim() !== "-apple-system-control-accent") {
    return null;
  }
  const document = themeRoot.ownerDocument;
  const parent = document.body ?? themeRoot;
  const probe = document.createElement("span");
  probe.setAttribute("aria-hidden", "true");
  probe.style.cssText = "position:fixed;inline-size:0;block-size:0;visibility:hidden;pointer-events:none;color:-apple-system-control-accent";
  parent.append(probe);
  const resolved = cssRGBToHex(getComputedStyle(probe).color);
  probe.remove();
  return resolved;
}

export function mermaidThemeFromStyle(
  style: MermaidThemeStyle,
  systemAccent?: string,
): ScholiumMermaidTheme | null {
  const background = semanticColor(style, "--scholium-color-document-background");
  const surface = semanticColor(style, "--scholium-color-surface-background");
  const text = semanticColor(style, "--scholium-color-primary-text");
  const accent = semanticColor(style, "--scholium-color-accent", systemAccent);
  const separator = semanticColor(style, "--scholium-color-separator");
  const fontFamily = style.getPropertyValue("--scholium-document-body-font-family").trim();
  if (!background || !surface || !text || !accent || !separator || !fontFamily) return null;
  // Series may carry inverse text in Pele. Document ink against the document
  // background preserves contrast without importing a second diagram palette.
  const series = Object.fromEntries(Array.from({length: 8}, (_, index) => [
    `--pele-series-${index + 1}`, text,
  ]));
  const variables = {
    "--pele-bg": background,
    "--pele-fg": text,
    "--pele-muted": semanticColor(style, "--scholium-color-secondary-text") ?? text,
    "--pele-line": separator,
    "--pele-surface": surface,
    "--pele-surface-alt": background,
    "--pele-border": accent,
    "--pele-accent": accent,
    "--pele-critical": accent,
    "--pele-font": fontFamily,
    "--pele-font-mono": style.getPropertyValue("--scholium-document-source-font-family").trim() || "monospace",
    ...series,
  };
  if (Object.values(variables).some(value => valueHasUnsafeURL(value) || deniedCSSControl.test(value))) return null;
  return {fontFamily, variables};
}

function renderValidatedMermaid(
  request: ScholiumMermaidRenderRequest,
  validation: Extract<ReturnType<typeof validateMermaidSource>, {ok: true}>,
  theme: ScholiumMermaidTheme,
): ScholiumMermaidRenderResult {
  if (request.signal?.aborted) return {ok: false, reason: "cancelled"};
  try {
    const model = parsePele(request.source, {limit: maximumSourceLength, maxEdges: 512});
    // Preserve uncolored sequence groups while refusing authored box colors.
    if (model.type === "sequence" && model.boxes.some(box => box.fill && box.fill !== "transparent")) {
      return {ok: false, reason: "unsafe-syntax"};
    }
    const rendered = renderPele(model, {
      idPrefix: `scholium-mermaid-${++renderSequence}`,
      fontFamily: theme.fontFamily,
      fontFamilyMono: theme.variables["--pele-font-mono"],
      // Source direction stays authoritative; the host owns bounded scaling.
      autoDirection: false,
      links: false,
      images: false,
      limit: maximumSourceLength,
      outputLimit: 2_000_000,
      maxEdges: 512,
    });
    if (request.signal?.aborted) return {ok: false, reason: "cancelled"};
    const sanitized = sanitizeMermaidSVG(rendered.svg);
    if (!sanitized) return {ok: false, reason: "unsafe-output"};
    for (const [name, value] of Object.entries(theme.variables)) {
      sanitized.style.setProperty(name, value);
    }
    return {
      ok: true,
      svg: sanitized,
      kind: rendered.type,
      accessibilityWarning: validation.accessibilityWarning,
    };
  } catch (error) {
    return {ok: false, reason: error instanceof PeleError && error.code === "unsupported-diagram"
      ? "unsupported-diagram" : "render-failed"};
  }
}

export function renderMermaid(request: ScholiumMermaidRenderRequest): Promise<ScholiumMermaidRenderResult> {
  if (request?.signal?.aborted) return Promise.resolve({ok: false, reason: "cancelled"});
  const validation = validateMermaidSource(request?.source);
  if (!validation.ok) return Promise.resolve(validation);
  if (!request) return Promise.resolve({ok: false, reason: "invalid-source"});
  const themeRoot = request.themeRoot
    ?? (typeof document === "undefined" ? null : document.documentElement);
  const theme = themeRoot
    ? mermaidThemeFromStyle(getComputedStyle(themeRoot), resolvedSystemAccent(themeRoot) ?? undefined)
    : null;
  if (!theme) return Promise.resolve({ok: false, reason: "invalid-theme"});
  // Keep the shared asynchronous contract and a cancellation boundary, without
  // Mermaid.js's runtime-global initialization or serialized render queue.
  return Promise.resolve().then(() => renderValidatedMermaid(request, validation, theme));
}

export const scholiumMermaidRuntime: ScholiumMermaidRuntime = Object.freeze({
  version: 3,
  render: renderMermaid,
  copy: copyMermaidSVG,
  mount: mountMermaidSVG,
});

declare global {
  interface Window {
    scholiumMermaid?: ScholiumMermaidRuntime;
    scholiumMermaidRuntimeDidLoad?: (loaded: boolean) => void;
  }
}

if (typeof window !== "undefined") window.scholiumMermaid = scholiumMermaidRuntime;
