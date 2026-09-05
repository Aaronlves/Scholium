# Scholium accessibility verification

Use this only for a user-facing change whose accessibility consequences need
explicit task coverage. Apple HIG and selected-SDK documentation own platform
rules; the Scholium specification owns workflow meaning.

This reference derives design obligations and findings. Deterministic
application journeys and genuine assistive-technology or input acceptance
belong to the UI-verification owner; structure inspection alone proves neither.

## Procedure

1. Name the researcher task, research object, current state, expected outcome,
   and every framework boundary crossed.
2. Identify the applicable keyboard, menu, pointer, focus, assistive-technology,
   scaling, appearance, motion, language, and recovery routes from live authority.
3. Inspect semantics and accessibility structure. When the claim requires an
   actual input or assistive technology, hand that exact task to the
   UI-verification owner rather than treating structure as proof.
4. Exercise only adjacent states that can change the task's meaning or
   operability, including failure or recovery when relevant.
5. Report automated evidence, exploratory observation, and genuine human
   acceptance separately.

## Invariants

- Source, researcher writing, agent content, review state, and derived state
  remain distinguishable by more than color or position.
- Every core action has a non-hover, non-drag, non-motion route with meaningful
  name, order, state, and focus behavior.
- Selection, semantic location, unsaved work, conflict, and recovery remain
  understandable across mode, window, and presentation changes.
- Researcher-authored and source text remains verbatim; interface strings remain
  localizable. Mixed scripts, directionality, and enlarged text must not alter
  document identity.
- Spatial views provide a source-anchored nonspatial equivalent and never make
  layout itself evidential meaning.

Prioritize inability or risk to complete the task, then authority or recovery
ambiguity, then bounded consistency or adaptation weaknesses. Each finding
states task, consequence, authority, evidence, and the smallest credible fix.
