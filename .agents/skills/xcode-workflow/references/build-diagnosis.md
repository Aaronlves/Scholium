# Build diagnosis

Use the existing repository build entrypoint and selected toolchain. Adding a
Makefile, formatter, project generator, or new build/run script is not a default
repair for verbose output or a slow build. Establish the missing capability first.

## Reliable output

Keep the raw build/test log and result bundle when available. A formatter is a
presentation aid: preserve the build tool's exit status through pipelines and
report the selected tests actually executed, failures, and skips. Zero discovered
tests or an empty formatter summary cannot establish a pass. Inspect the first
causal diagnostic before attributing a failure to production behavior.

Respect existing warning policy. Do not blanket-enable warnings-as-errors,
suppress warnings, or alter compiler/availability settings to repair an unrelated
failure. Match a deprecated API replacement to the selected SDK and deployment
target rather than copying a newer skill's defaults.

## A reported build-time problem

Separate clean builds, warm no-change builds, and representative edit/rebuilds;
they answer different questions. Hold toolchain, configuration, destination,
dependency resolution, cache state, and command constant for a comparison.
Measure only the reported scenario, repeat enough to expose noise, and compare
typical duration and spread rather than the fastest run. Record cache warm-up;
do not erase shared caches or conflate cold and warm results.

Use available build timing summaries or timelines to locate dependency planning,
compilation, linking, resource/script, or signing costs before changing settings.
Inspect declared script inputs/outputs and invalidated dependencies when unchanged
work reruns. Test one justified change against the same scenario and preserve
correctness checks; do not disable validation to manufacture a speedup.

## Sources and applicability

The controlled-comparison method is informed by Antoine van der Lee's
[build benchmark skill](https://github.com/AvdLee/Xcode-Build-Optimization-Agent-Skill/blob/6bd7b596cd688b1127ded00e812b1b6937ec35d6/skills/xcode-build-benchmark/SKILL.md)
(reviewed 2026-09-23). Its fixed run counts, storage paths, orchestration, and
project defaults are not local requirements. Apple's
[incremental-build guidance](https://developer.apple.com/documentation/xcode/improving-the-speed-of-incremental-builds)
and [build timeline explanation](https://developer.apple.com/videos/play/wwdc2022/110364/)
support dependency-based diagnosis; verify command and setting availability
against the selected toolchain. This method establishes build efficiency, not
application runtime performance or release acceptance.
