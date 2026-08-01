import mermaid from "mermaid";

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
  readonly version: 2;
  render(request: ScholiumMermaidRenderRequest): Promise<ScholiumMermaidRenderResult>;
  mount(host: HTMLElement, svg: SVGSVGElement): boolean;
}

const maximumSourceLength = 32_768;
const maximumLineCount = 512;
let renderSequence = 0;
let renderQueue: Promise<void> = Promise.resolve();

const deniedStatement = /(?:^|[;\r\n])\s*(?:click|href|class|classDef|style|linkStyle)\b/i;
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
  inline-size: auto !important;
  min-inline-size: 0 !important;
  max-inline-size: 100% !important;
  block-size: auto !important;
  max-block-size: min(70vh, 42rem) !important;
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

interface ScholiumMermaidTheme {
  readonly darkMode: boolean;
  readonly variables: Readonly<Record<string, string>>;
}

type MermaidThemeStyle = Pick<CSSStyleDeclaration, "getPropertyValue">;

function semanticColor(style: MermaidThemeStyle, name: string) {
  const value = style.getPropertyValue(name).trim();
  return /^#[0-9a-f]{6}$/i.test(value) ? value : null;
}

function relativeLuminance(hex: string) {
  const channels = [1, 3, 5].map((offset) => Number.parseInt(hex.slice(offset, offset + 2), 16) / 255)
    .map((channel) => channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4);
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

export function mermaidThemeFromStyle(style: MermaidThemeStyle): ScholiumMermaidTheme | null {
  const background = semanticColor(style, "--scholium-color-document-background");
  const surface = semanticColor(style, "--scholium-color-surface-background");
  const text = semanticColor(style, "--scholium-color-primary-text");
  const accent = semanticColor(style, "--scholium-color-accent");
  const separator = semanticColor(style, "--scholium-color-separator");
  if (!background || !surface || !text || !accent || !separator) return null;
  const diagramScale = Object.fromEntries(Array.from({length: 12}, (_, index) => [
    [`cScale${index}`, index % 2 === 0 ? surface : background],
    [`cScaleLabel${index}`, text],
    [`cScaleInv${index}`, separator],
    [`lineColor${index}`, accent],
  ]).flat());
  return {
    darkMode: relativeLuminance(background) < 0.5,
    variables: {
      background,
      primaryColor: surface,
      primaryTextColor: text,
      primaryBorderColor: accent,
      secondaryColor: background,
      secondaryTextColor: text,
      secondaryBorderColor: separator,
      tertiaryColor: surface,
      tertiaryTextColor: text,
      tertiaryBorderColor: separator,
      lineColor: separator,
      textColor: text,
      mainBkg: surface,
      nodeBkg: surface,
      nodeBorder: accent,
      clusterBkg: background,
      clusterBorder: separator,
      edgeLabelBackground: background,
      noteBkgColor: surface,
      noteTextColor: text,
      noteBorderColor: separator,
      ...diagramScale,
    },
  };
}

function protectedMermaidThemeCSS(theme: ScholiumMermaidTheme) {
  const surface = theme.variables.primaryColor;
  const text = theme.variables.primaryTextColor;
  const accent = theme.variables.primaryBorderColor;
  const separator = theme.variables.lineColor;
  return `
.mindmap-node rect,
.mindmap-node path,
.mindmap-node circle,
.mindmap-node polygon {
  fill: ${surface} !important;
  stroke: ${accent} !important;
}
.mindmap-node text,
.mindmap-node .nodeLabel,
.mindmap-node-label {
  fill: ${text} !important;
  color: ${text} !important;
}
.mindmapDiagram .edge,
.mindmapDiagram .flowchart-link {
  stroke: ${separator} !important;
}
`;
}

async function renderValidatedMermaid(
  request: ScholiumMermaidRenderRequest,
  validation: Extract<ReturnType<typeof validateMermaidSource>, {ok: true}>,
  theme: ScholiumMermaidTheme,
): Promise<ScholiumMermaidRenderResult> {
  if (request.signal?.aborted) return {ok: false, reason: "cancelled"};
  try {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      secure: ["secure", "securityLevel", "startOnLoad", "maxTextSize", "suppressErrorRendering", "maxEdges"],
      htmlLabels: false,
      suppressErrorRendering: true,
      maxTextSize: maximumSourceLength,
      maxEdges: 512,
      deterministicIds: true,
      deterministicIDSeed: "scholium",
      theme: "base",
      themeCSS: protectedMermaidThemeCSS(theme),
      themeVariables: {
        darkMode: theme.darkMode,
        ...theme.variables,
        fontFamily: "Alegreya, Georgia, serif",
      },
      flowchart: {useMaxWidth: false},
    });
    const parsed = await mermaid.parse(request.source, {suppressErrors: true});
    if (!parsed) return {ok: false, reason: "unsupported-diagram"};
    if (request.signal?.aborted) return {ok: false, reason: "cancelled"};
    const identifier = `scholium-mermaid-${++renderSequence}`;
    const rendered = await mermaid.render(identifier, request.source);
    if (request.signal?.aborted) return {ok: false, reason: "cancelled"};
    const sanitized = sanitizeMermaidSVG(rendered.svg);
    if (!sanitized) return {ok: false, reason: "unsafe-output"};
    return {
      ok: true,
      svg: sanitized,
      kind: parsed.diagramType,
      accessibilityWarning: validation.accessibilityWarning,
    };
  } catch {
    return {ok: false, reason: "render-failed"};
  }
}

export function renderMermaid(request: ScholiumMermaidRenderRequest): Promise<ScholiumMermaidRenderResult> {
  if (request?.signal?.aborted) return Promise.resolve({ok: false, reason: "cancelled"});
  const validation = validateMermaidSource(request?.source);
  if (!validation.ok) return Promise.resolve(validation);
  if (!request) return Promise.resolve({ok: false, reason: "invalid-source"});
  const themeRoot = request.themeRoot
    ?? (typeof document === "undefined" ? null : document.documentElement);
  const theme = themeRoot ? mermaidThemeFromStyle(getComputedStyle(themeRoot)) : null;
  if (!theme) return Promise.resolve({ok: false, reason: "invalid-theme"});
  const result = renderQueue
    .catch(() => {})
    .then(() => renderValidatedMermaid(request, validation, theme));
  renderQueue = result.then(() => {}, () => {});
  return result;
}

export const scholiumMermaidRuntime: ScholiumMermaidRuntime = Object.freeze({
  version: 2,
  render: renderMermaid,
  mount: mountMermaidSVG,
});

declare global {
  interface Window {
    scholiumMermaid?: ScholiumMermaidRuntime;
    scholiumMermaidRuntimeDidLoad?: (loaded: boolean) => void;
  }
}

if (typeof window !== "undefined") window.scholiumMermaid = scholiumMermaidRuntime;
