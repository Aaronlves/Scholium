import {
  calloutLocalizationKeys,
  localizedTemplate,
  type createInterfaceLocalizer,
} from "./localization";

/** Translate only the renderer's generated chrome, leaving authored prose and titles intact. */
export function localizeRenderedInterface(
  root: ParentNode,
  localize: ReturnType<typeof createInterfaceLocalizer> = (key, replacements = {}) =>
    localizedTemplate(key, replacements),
) {
  root.querySelectorAll<HTMLElement>(".scholium-callout").forEach(callout => {
    const identifier = Object.keys(calloutLocalizationKeys).find(role =>
      callout.classList.contains(`scholium-callout-${role}`));
    if (!identifier) return;
    const [labelKey, meaningKey] = calloutLocalizationKeys[identifier as keyof typeof calloutLocalizationKeys];
    const label = localize(labelKey);
    const meaning = localize(meaningKey);
    const role = callout.querySelector<HTMLElement>(".scholium-callout-role");
    if (role?.closest(".scholium-callout") === callout) {
      if (role.textContent !== label) role.textContent = label;
      if (role.title !== meaning) role.title = meaning;
      role.setAttribute("aria-label", localize("{label}. {meaning}", {label, meaning}));
    }
    const generatedTitle = callout.querySelector<HTMLElement>(".scholium-callout-default-title");
    if (generatedTitle?.closest(".scholium-callout") === callout && generatedTitle.textContent !== label) {
      generatedTitle.textContent = label;
    }
  });
  root.querySelectorAll<HTMLElement>(".footnote-reference[data-footnote]").forEach(reference => {
    const ordinal = reference.dataset.footnote;
    if (ordinal) reference.setAttribute("aria-label", localize("Footnote {ordinal}", {ordinal}));
  });
  root.querySelectorAll<HTMLElement>(".footnote-return[data-footnote]").forEach(reference => {
    const ordinal = reference.dataset.footnote;
    if (ordinal) reference.setAttribute("aria-label", localize("Return to footnote reference {ordinal}", {ordinal}));
  });
  root.querySelectorAll<HTMLElement>(".footnotes").forEach(section => {
    section.setAttribute("aria-label", localize("Footnotes"));
  });
  root.querySelectorAll<HTMLInputElement>(".scholium-task-checkbox").forEach(checkbox => {
    checkbox.setAttribute("aria-label", localize(checkbox.checked ? "Completed task" : "Incomplete task"));
  });
  root.querySelectorAll<HTMLElement>(".scholium-table").forEach(table => {
    table.setAttribute("aria-label", localize("Markdown table"));
  });
  root.querySelectorAll<HTMLButtonElement>("button[data-link-annotation]").forEach(button => {
    const title = button.dataset.linkAnnotationTarget?.trim()
      || button.closest(".scholium-annotated-link")?.querySelector(".wiki-link")?.textContent?.trim()
      || localize("linked note");
    button.dataset.linkAnnotationTarget = title;
    const expanded = button.getAttribute("aria-expanded") === "true";
    button.setAttribute("aria-label", localize(
      expanded ? "Hide Link Annotation for {title}" : "Show Link Annotation for {title}", {title}));
  });
}
