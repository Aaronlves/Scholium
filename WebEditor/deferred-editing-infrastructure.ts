import {Compartment, Facet, type EditorState, type Extension} from "@codemirror/state";
import type {EditorMode} from "./protocol";

/** Cold Review needs committed DOM only. Once created, editing infrastructure survives mode changes. */
export function createDeferredEditingInfrastructure(extensions: Extension) {
  const compartment = new Compartment();
  const initialized = Facet.define<boolean, boolean>({combine: values => values.includes(true)});
  const editing = [extensions, initialized.of(true)];
  return {
    forDocument(mode: EditorMode) { return compartment.of(mode === "review" ? [] : editing); },
    activationEffects(state: EditorState, mode: EditorMode) {
      return mode !== "review" && !state.facet(initialized) ? [compartment.reconfigure(editing)] : [];
    },
  };
}
