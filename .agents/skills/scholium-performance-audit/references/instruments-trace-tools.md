# Scholium Instruments trace tools

Use these tools only after defining the exact Scholium interaction, build,
fixture, and measurement question. Record only disposable nonprivate fixtures.
Keep trace bundles, stop files, QA copies, and generated summaries in one
repository-local ignored `.build/` task directory outside research vaults.

## Bind the selected Xcode

Resolve the repository's selected developer directory and preserve it for every
recording and analysis command:

```bash
developer_dir="$(./Tools/Scripts/resolve-xcode-developer-dir.sh)"
export DEVELOPER_DIR="$developer_dir"
skill_dir=".agents/skills/scholium-performance-audit"
task_id="task-run"
trace_dir=".build/performance-traces/$task_id"
qa_app_path=".build/qa/$task_id/Scholium-QA.app"
mkdir -p "$trace_dir"
```

Replace `task-run` with one unique task-owned identifier and create that exact
directory before recording. Keep retained trace evidence there; remove the
test-owned QA copy when its journey finishes.

Confirm `xcrun --find xctrace`, the Instruments templates, the target process,
and the build configuration. A Debug trace is diagnostic evidence, not a
release-performance result.

## Record

Discover available targets and templates:

```bash
python3 "$skill_dir/scripts/record_trace.py" --list-devices
python3 "$skill_dir/scripts/record_trace.py" --list-templates
```

Attach to the one running QA process or launch a specific test-owned app:

```bash
python3 "$skill_dir/scripts/record_trace.py" \
  --attach Scholium \
  --stop-file "$trace_dir/stop" \
  --output "$trace_dir/session.trace"

python3 "$skill_dir/scripts/record_trace.py" \
  --launch "$qa_app_path" \
  --time-limit 30s \
  --output "$trace_dir/launch.trace"
```

The script refuses to overwrite an existing output. Use a new test-owned path;
do not delete an artifact unless the current run owns it. For the host Mac, the
SwiftUI template is normally appropriate. Verify the actual template and lanes
rather than applying an iOS simulator rule to macOS.

## Analyze

Inspect one trace without modifying application source:

```bash
python3 "$skill_dir/scripts/analyze_trace.py" \
  --trace "$trace_dir/session.trace" \
  --json-only --top 10
```

Use `--list-runs` before selecting `--run N` for a multi-run trace. Use logs or
signposts to derive a bounded window, then analyze that same window:

```bash
python3 "$skill_dir/scripts/analyze_trace.py" \
  --trace "$trace_dir/session.trace" \
  --list-signposts --signpost-name-contains "NoteLoad"

python3 "$skill_dir/scripts/analyze_trace.py" \
  --trace "$trace_dir/session.trace" \
  --window START_MS:END_MS --json-only
```

When a SwiftUI destination repeatedly updates, `--fanin-for "ViewName"` can
surface likely attribute-graph sources. Treat a partial symbol or view-name
match as a search lead until live source and call sites confirm it.

## Interpret and verify

- Separate blocked-main-thread, CPU, layout, invalidation, and bridge hypotheses.
- Treat coverage percentages, edge counts, event severity, and frame-duration
  cutoffs as heuristics tied to the recorded toolchain—not universal proof.
- Route SwiftUI invalidation and identity hypotheses to
  `swiftui-performance-checks.md`; route state ownership, focus, scene, and
  adapter changes to the native-interface capability.
- Preserve note bytes, fingerprints, source ranges, selection, undo, focus,
  privacy, and window isolation while investigating.
- Capture the identical interaction before and after a change and report the
  exact build, fixture, trace window, metrics, and remaining uncertainty.

The scripts require only Python 3 and the selected Xcode's `xctrace`. They come
from the MIT-licensed
[AvdLee SwiftUI Expert Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) at
revision `f06d1437a3fbec7df6cdce93f77004e5409b31ee`; see
`../LICENSE-AVDLEE-SWIFTUI-EXPERT`.
