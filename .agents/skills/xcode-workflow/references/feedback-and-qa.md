# Rapid Xcode Feedback and QA

Use this workflow when a user wants to operate a development build and report
bugs without waiting for a release package.

## Start one feedback session

1. Read the repository's QA and fixture rules.
2. Record the source revision and existing worktree changes.
3. Select the intended Xcode toolchain explicitly.
4. Build one test-identified Debug/QA app into a test-owned location.
5. Use a disposable fixture copy and isolated app-support directory.
6. Launch one process and leave it available for the user to inspect.
7. Tell the user which behaviors differ from a release build, especially App
   Sandbox, signing, entitlements, embedded-resource layout, and Gatekeeper.

Prefer the repository's existing QA script. Do not create a second launcher or
fixture convention when one already exists.

## Accept low-friction reports

A screenshot and one sentence can be sufficient. Do not require a form before
starting diagnosis. When more structure is useful, ask for only the missing
field:

```text
Bug: What went wrong
Steps: What I clicked
Expected: What should happen
Actual: What happened
Frequency: Always / Sometimes / Once
```

Also capture when relevant:

- first launch versus restored state;
- window width, appearance, accessibility settings, and input method;
- selected document mode or workspace;
- whether the app was relaunched;
- screenshot or short screen recording; and
- exact alert or diagnostic text without private research content.

## Triage before rerunning

Classify the report into one primary boundary:

- SwiftUI/AppKit layout, focus, command, or presentation;
- editor/WebKit bridge or embedded resources;
- persistence, restoration, concurrency, or filesystem coordination;
- search/index/derived state;
- App Sandbox, security-scoped bookmark, entitlement, or signing;
- test harness, automation permission, destination, or stale build; or
- release packaging and installation.

Reproduce once on the smallest disposable state. If it fails, retain and inspect
the screenshot, hierarchy, logs, or result bundle before another run. If it does
not fail, compare build identity and state instead of assuming the report is
wrong.

## Fix and return quickly

1. Reuse existing proof; add or update a regression test when it can detect the
   reported failure. A small visual adjustment does not by itself require a new test.
2. Implement the smallest complete fix under repository authority.
3. Run the focused test.
4. Rebuild the same QA app and return it to the user.
5. Complete the verification required by `AGENTS.md` for the change. User
   retesting does not create an additional prerequisite for automated checks.

Package only when the user requests a distributable artifact or release-specific
validation is in scope. An accepted Debug fix alone does not authorize packaging.

## End the session

Quit the QA process and remove only test-owned bundles, fixtures, derived data,
result bundles, and isolated state. Preserve user files, real vaults, unrelated
worktree changes, and retained evidence still needed for diagnosis.
