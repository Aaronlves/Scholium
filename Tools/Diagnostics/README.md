# Foreground note-opening diagnostics

Run the opt-in XCTest journey through the QA wrapper:

```sh
Tools/Scripts/run-ui-tests.sh foreground-opening
SCHOLIUM_FOREGROUND_OPEN_INITIAL_ALTERNATE=1 Tools/Scripts/run-ui-tests.sh foreground-opening
SCHOLIUM_FOREGROUND_OPEN_RETAIN_TARGET=1 Tools/Scripts/run-ui-tests.sh foreground-opening
```

The default uses ordinary Library replacement; the retained option keeps the target
in an existing tab. These are different lifecycle paths. Both retain Live Preview.
The initial-alternate option starts with B loaded before the first measured A click.
Without it, the app is already open with no selected document; process launch is
outside the measurement. Neither option proves a cold OS/WebKit process cache.

For a fresh Open in New Tab action, set `SCHOLIUM_FOREGROUND_OPEN_NEW_TAB=1`,
`SCHOLIUM_FOREGROUND_OPEN_INITIAL_ALTERNATE=1` and
`SCHOLIUM_FOREGROUND_OPEN_RETAIN_TARGET=1`. Each process records one new A Tab
while B remains open; repeat fresh processes for independent samples. The context
menu opens before capture; timing starts inside the native new-Tab action handler.
For waits exceeding two seconds, `SCHOLIUM_QA_FRAME_RATE=15` keeps capture within
the existing 128-frame memory bound. Match frame rate before/after and report the
actual interval; other diagnostics default to 60 fps.

`Tools/Scripts/run-ui-tests.sh tab-stress` exercises two complete ten-Tab
lifecycles over the standard 500-note Triptych. It checks exact saved bytes through
cross-Tab Undo/Redo and records existing session/page/snapshot owners after closure.
These owner counts describe retained resources, not total process resident memory.
Set `SCHOLIUM_TAB_STRESS_OUTPUT` to a new JSON path inside repository `.build/`.

The wrapper builds an isolated QA app and copies the standard 500-note Triptych.
Only its window is captured. Existing Screen Recording access is required; the
helper fails without prompting or changing permissions. Requests, frames, logs,
app state and all build caches stay under repository `.build/`.

`note_open_to_visible` records AppKit mouseDown to native layout readiness.
It does not require editor focus or acknowledge rendered pixels. The older
`note_open_to_input` retains its separate focus requirement. The driver verifies
body pixels and exact save/Undo/Redo outside the timed action, following the same
ordinary replacement or retained-tab route selected for the timing samples.

`SCStreamFrameInfo.displayTime` is converted to the same uptime clock as the native
probe. Offline recognition of the unique body sentinel is required to identify
the first sampled matching frame. Capture requests 60 fps, so that timestamp is
an observed upper bound, not proof of the first refresh or physical panel scanout.
The driver waits for native layout readiness and a quiet interval before invoking
screenshot/Vision. Require the first matching frame to precede the recorded first
screenshot invocation; otherwise recognition could compete with rendering.
Report the preceding unmatched frame and actual sample interval. Reject overflow,
capture errors, pre-click target matches or mismatched sample/run identities.
The helper copies bounded pixel buffers during capture and encodes PNGs only after
capture stops. Its overhead is not zero. Web performance rings on retained pages
are cumulative session snapshots; do not attribute old records to each return.

Compile the offline recognizer with the selected Xcode toolchain, then run it
against one capture after the QA process has stopped:

```sh
mkdir -p .build/foreground-opening/module-cache
xcrun swiftc -module-cache-path .build/foreground-opening/module-cache \
  "$PWD/Tools/Diagnostics/RecognizeQAWindowFrames.swift" -o .build/foreground-opening/recognize-frames
.build/foreground-opening/recognize-frames /absolute/repository/.build/run/sample-0/frames 'synthetic body phrase'
```

The report supplies the actual body phrase and each sample's native completion
uptime and duration. Their difference is the AppKit action start; compare it with
frame display uptime. The recognizer retains match flags and timing metadata,
never OCR text. Small sample counts and any visible derived-index refresh must
be reported; this diagnostic is not a release benchmark.
