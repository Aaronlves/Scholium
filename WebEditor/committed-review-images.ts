import {invalidateDocumentImageReadiness} from "./document-widget-readiness";

/** Bind native-admitted raster resources without copying their bytes into HTML.
 * The renderer has already decoded each catalog key; decoding it again would
 * change filenames containing literal percent escapes or character references.
 * Resource admission belongs to the versioned presentation protocol. */
export function bindCommittedReviewImageResources(root: HTMLElement,
  resources: Readonly<Record<string, string>>): HTMLImageElement[] {
  const changed: HTMLImageElement[] = [];
  const scopes: ParentNode[] = [root];
  for (let index = 0; index < scopes.length; index++) {
    for (const element of scopes[index].querySelectorAll<HTMLElement>(
      "img.scholium-embedded-image[data-scholium-image-resource], template")) {
      // Embedded Note HTML belongs to another source and carries its own
      // admitted raster bytes. Its raw keys cannot resolve in this catalog.
      if (element.closest(".scholium-embedded-note")) continue;
      if (element.localName === "template") {
        // Annotation popovers clone these inert fragments. querySelectorAll
        // deliberately does not enter their contents in a browser.
        scopes.push((element as HTMLTemplateElement).content);
        continue;
      }
      const image = element as HTMLImageElement;
      const key = image.getAttribute("data-scholium-image-resource")!;
      const resource = Object.hasOwn(resources, key) ? resources[key] : undefined;
      const previous = image.getAttribute("src");
      if (resource === undefined ? previous === null : previous === resource) continue;
      invalidateDocumentImageReadiness(image);
      image.style.removeProperty("--scholium-image-aspect-ratio");
      if (resource === undefined) image.removeAttribute("src");
      else image.setAttribute("src", resource);
      changed.push(image);
    }
  }
  return changed;
}
