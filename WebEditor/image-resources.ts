export const MAX_IMAGE_BYTES = 10 * 1_024 * 1_024;
export const MAX_IMAGE_CATALOG_BYTES = 80 * 1_024 * 1_024;
export const MAX_IMAGE_ENVELOPE_BYTES = 4 * Math.ceil(MAX_IMAGE_CATALOG_BYTES / 3) + 512 * 1_024;
const dataImage = /^data:image\/(?:png|jpeg|gif|webp);base64,([A-Za-z0-9+/]+={0,2})$/;

/** Only native-admitted raster bytes cross the bridge. Never fetch a URL here. */
export function validImageResources(value: unknown): value is Record<string, string> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  let totalBytes = 0;
  let metadataBytes = 0;
  for (const [destination, resource] of Object.entries(value)) {
    if (!destination || destination.length > 16_384 || typeof resource !== "string") return false;
    metadataBytes += new TextEncoder().encode(destination).length + 64;
    if (metadataBytes > 512 * 1_024) return false;
    const match = dataImage.exec(resource);
    if (!match || match[1].length % 4 !== 0) return false;
    const bytes = match[1].length / 4 * 3 - (match[1].endsWith("==") ? 2 : match[1].endsWith("=") ? 1 : 0);
    if (bytes <= 0 || bytes > MAX_IMAGE_BYTES) return false;
    totalBytes += bytes;
    if (totalBytes > MAX_IMAGE_CATALOG_BYTES) return false;
  }
  return true;
}

