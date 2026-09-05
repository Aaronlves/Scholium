# Human interaction acceptance

Use this mode when synthetic automation cannot establish the claimed input, assistive-technology, perception, or system-adaptation behavior. It complements deterministic UI tests; it does not weaken or replace them.

## Separate evidence layers

- **Automated safeguard:** deterministic state, source preservation, identifiers, focus targets, menu routes, and recoverable failure behavior.
- **Exploratory observation:** current visual or accessibility-tree behavior in a named build and environment.
- **Human acceptance:** a person genuinely performs the input or judges the output under the stated system configuration.

Never promote one layer into another. In particular, synthetic keystrokes do not certify Voice Control, Dictation, or genuine IME candidate selection.

## Stage the session

1. Name the exact claim, build, fixture, account, language/input source, assistive technology, and system adaptations.
2. Use one isolated QA process and disposable nonprivate fixture state.
3. Record the pre-session system settings that may change and the restoration procedure.
4. Automate launch, navigation, deterministic setup, source fingerprints, and post-action assertions wherever safe.
5. Reduce the human handoff to the irreducible action and observable question.

Do not install input sources, change unrelated applications, or broaden system permissions without the researcher's explicit direction.

## Human-only examples

- Speak an actual Voice Control command and confirm discoverability, targeting, and visible feedback.
- Dictate real text and verify composition, punctuation, undo, save, and exact-source behavior.
- Use an actual CJK input method to compose, navigate candidates, commit a non-default candidate, undo, save, reopen, and compare source.
- Navigate with VoiceOver or Full Keyboard Access and judge reading order, naming, grouping, focus continuity, and recovery.
- Judge legibility and state distinction under Increase Contrast, Reduce Transparency, Reduce Motion, text scaling, light/dark appearance, and inactive-window state.

## Evidence record

Record:

- claim and acceptance criterion;
- exact artifact and fixture identity;
- macOS, account type, language, input source, and relevant settings;
- automated preconditions and postconditions;
- concise human action and observed result;
- pass, fail, blocked, or not run;
- screenshot or hierarchy only when nonprivate and materially useful;
- settings restored; and
- residual uncertainty.

A checked box without artifact, environment, action, and observation is not retained acceptance evidence.

## Failure and handoff

When the human step fails, preserve the synthetic fixture and the smallest nonprivate evidence, restore the environment, and classify whether the failure is product behavior, environment, permissions, or an unexercised prerequisite. Do not silently retry with a different build or input path.

When the researcher is unavailable, complete the automated staging, provide the minimal handoff, and mark the human gate pending. Never claim the broader acceptance gate passed.
