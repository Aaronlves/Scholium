import {vi} from "vitest";

/** Linkedom exposes a parsed stylesheet but not the constructable-sheet API. */
export function installConstructableStylesheet(document: Document) {
  vi.stubGlobal("CSSStyleSheet", class {
    cssRules: CSSRuleList = [] as unknown as CSSRuleList;
    replaceSync(css: string) {
      const style = document.createElement("style");
      style.textContent = css;
      this.cssRules = style.sheet!.cssRules;
    }
  });
}
