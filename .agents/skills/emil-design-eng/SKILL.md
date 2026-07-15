---
name: emil-design-eng
description: Apply an optional design-craft lens derived from Emil Kowalski's published interface and motion work. Use only when the user explicitly asks for an Emil Kowalski or animations.dev perspective, or when evaluating web-interface polish through that named lens. Do not use as Apple HIG authority, Scholium product authority, native API guidance, or a substitute for platform-specific design and implementation skills.
---

# Emil Design Craft Lens

Use this skill as an attributed secondary perspective, not as a universal rulebook.

## Establish authority first

- For Scholium, read the affected Product Guide workflow and the complete Design Handbook.
- Route every Apple-platform claim through `apple-hig`.
- Use `scholium-apple-design` for Scholium-specific interpretation and `scholium-swiftui-implementation` for native mechanics.
- Treat the selected SDK, compiler, and framework documentation as authority for implementation-facing claims.

Do not translate CSS, React, browser, or Motion-library mechanisms directly into SwiftUI or AppKit. Do not describe third-party curves, timing values, spring parameters, or examples as Apple rules.

## Apply the lens

Evaluate whether an interaction:

- communicates purpose, state, spatial relationship, or feedback;
- responds promptly and remains interruptible when the user can change direction;
- matches its frequency of use and the product's visual character;
- preserves accessibility and a non-motion path to meaning and action;
- avoids unnecessary work on the relevant rendering stack; and
- benefits from motion at all.

For a web implementation, read [references/web-motion-craft.md](references/web-motion-craft.md). Its values are attributed heuristics that require validation against the product's existing tokens, runtime evidence, and accessibility behavior.

For Scholium native work, do not load the web reference as a standards catalog. Use `scholium-apple-design` and its routed fluid-interaction reference instead.

## Report

Name the authority used for each conclusion. Separate product or platform requirements from this optional craft evaluation, and mark judgments that require visual or runtime testing.
