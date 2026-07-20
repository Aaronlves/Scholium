#!/bin/zsh
set -euo pipefail

# Read one native window frame through macOS Accessibility. This is a QA probe:
# it never moves, resizes, or otherwise mutates the target application.
bundle_identifier="${1:-com.scholium.qa}"

/usr/bin/osascript - "${bundle_identifier}" <<'APPLESCRIPT'
on run arguments
    set targetBundleIdentifier to item 1 of arguments
    tell application "System Events"
        set matchingProcesses to every application process whose bundle identifier is targetBundleIdentifier
        if (count of matchingProcesses) is 0 then
            error "No running application has bundle identifier " & targetBundleIdentifier
        end if

        tell first item of matchingProcesses
            if (count of windows) is 0 then
                error "The application is running but has no window."
            end if
            set windowPosition to position of front window
            set windowSize to size of front window
        end tell
    end tell

    set windowX to item 1 of windowPosition
    set windowY to item 2 of windowPosition
    set windowWidth to item 1 of windowSize
    set windowHeight to item 2 of windowSize
    return (windowWidth as text) & " × " & (windowHeight as text) & " pt (x=" & (windowX as text) & ", y=" & (windowY as text) & ")"
end run
APPLESCRIPT
