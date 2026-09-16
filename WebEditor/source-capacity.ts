/** Exact Markdown bytes and transport bytes are separate bounded contracts. */
export const MAX_SOURCE_UTF8_BYTES = 8_000_000;
export const sourceCapacityMessage = "The edited Markdown document exceeds the supported editor size.";
export function exactSourceFits(source: string) {
  return new TextEncoder().encode(source).byteLength <= MAX_SOURCE_UTF8_BYTES;
}
