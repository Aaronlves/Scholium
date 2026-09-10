---
name: scholium-hand-ink-illustration
description: "Create or edit bounded, textless Scholium product illustrations for welcome, empty, educational, or feature-introduction states. Preserve the canonical hand-ink visual language; exclude app-icon replacement, interface code, posters, and copied third-party art."
---

# Scholium Hand-Ink Illustration

Create finished, textless product illustrations that feel native to Scholium:
the existing icon supplies the hand-ink character; solid color fields and a
small number of flat shapes reinforce one intended action or relation at a
glance without becoming the task's sole meaning carrier.

Apply the shared [development contract](../scholium-toolkit-maintenance/references/researcher-codex-development-contract.md).
Before material artwork or a production-placement recommendation, apply the
[restrained-design protocol](../scholium-toolkit-maintenance/references/restrained-design-and-solution-research.md).

## Modes

- **Generate:** create a new visual proof from a bounded communication job.
- **Edit:** inspect the supplied product illustration, name the exact elements
  to preserve and change, and edit only that artwork. The application icon may
  remain style evidence but is never the edit target.

## Responsibility boundary

Use this skill for raster illustrations placed inside Scholium product
surfaces. Keep these neighboring responsibilities separate:

- Poster, cover, banner, typographic zine, and promotional composition are
  outside this product-illustration capability. Resolve an available general
  visual-artifact owner at task time instead of inventing a Scholium capability.
- Interface hierarchy, layout, controls, implementation, and accessibility
  behavior belong to native interface design and implementation.
- The application icon is immutable identity artwork. This skill may learn its
  drawing grammar but never recolor, crop, trace, edit, or reuse the exact icon
  composition as an illustration or glyph.
- Generated candidates are visual proofs until the researcher explicitly
  approves production integration. Do not modify app source or canonical
  product rules merely because an image was generated.

## Required authority and source inspection

Before material Scholium product art:

1. Read the affected workflow and all binding interface authority required by
   `AGENTS.md`.
2. Read [visual grammar](references/visual-grammar.md) completely.
3. Resolve the current canonical application icon from live specification and
   packaging construction. Inspect it as style evidence; when a preview is
   needed, derive it under `.build/` rather than creating a second canonical
   asset.
   Production placement remains subordinate to the current Design authority;
   candidate art palettes and compositions never expand a closed canonical
   product surface.
4. If the concept uses a named myth, text, historical object, or other source
   claim, verify the relevant character, object, and action before drawing.
   Separate source facts from the modern visual interpretation.

For maintenance provenance only, read
[research lineage](references/research-lineage.md).

## Delivery contract

Before raster work, bind the destination and communication job, exact frame or
aspect, safe regions and focal placement, background or alpha requirement,
final format and fit, and whether the request is one image or a genuine variant
set. If the live slot is unknown, return a clearly labelled visual proof rather
than inventing production dimensions. Preserve the supplied source or generated
master and derive exact-size delivery without distortion.

## Workflow

1. State one physical intent the image should reinforce. If no decisive action
   or relation can be named, stop rather than generate decoration.
2. Use the visual grammar to choose one intention-bearing direction, while
   keeping verified source facts separate from a modern interpretation.
3. Compile a concrete prompt and generate or edit through the available
   raster-image mechanism. Use the live icon only as a style reference, never
   an edit target. A prompt-only request stops before image work and reports
   that no raster was produced, changed, or measured.
4. Produce one image per materially different direction and apply the visual
   grammar's full-size and thumbnail inspection. Revise only against a bounded
   observable failure; recolors do not count as new directions.
5. Derive exact-size delivery without distortion, verify dimensions, format,
   alpha, and profile, and keep every unapproved candidate under
   `.build/visual-proofs/` outside research vaults and release assets.

## Evidence and invariants

- For each direction, return the rendered image, intent, prompt actually used,
  source basis and interpretation when applicable, absolute path, requested and
  measured raster facts, and explicit visual-proof or production-integrated
  status; a contact sheet is not the only deliverable.
- Product illustration does not define interface layout, semantic Variables,
  accessibility behavior, or production acceptance.
- The depicted action or relation remains intelligible without making adjacent
  copy or color the sole carrier of meaning; interface controls and text remain
  the complete task path.
- Measure delivery facts rather than inferring them from the request or master.
