#!/bin/sh
# Re-renders the README screenshots in docs/images from the app's real SwiftUI
# views (app/main.swift) with sample data in Chinese and English.
#
# Safe to run on a protected Mac: it compiles a throwaway binary in a temporary
# folder. Nothing starts the controller, the system helper or pfctl, and nothing
# touches the network, FlClash or system settings. Requires Xcode Command Line Tools.
#
#   sh docs/tools/render-screenshots.sh [output-dir]
# Produces Chinese ui-*.png / ui-demo.gif and English ui-*.en.png / ui-demo.en.gif.
set -eu
root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
out=${1:-"$root/docs/images"}
tmp=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$tmp"' EXIT

# Reuse main.swift up to (not including) its top-level launch code.
line=$(/usr/bin/grep -n '^let application = NSApplication.shared$' "$root/app/main.swift" | /usr/bin/cut -d: -f1)
if [ -z "$line" ]; then
    echo "Could not find the launch code at the end of app/main.swift; update this script." >&2
    exit 1
fi
/usr/bin/head -n $((line - 1)) "$root/app/main.swift" > "$tmp/main.swift"
/bin/cat "$root/docs/tools/RenderScreenshots.swift" >> "$tmp/main.swift"
/bin/mkdir -p "$tmp/Renderer.app/Contents/MacOS" "$tmp/Renderer.app/Contents/Resources"
/bin/cp "$root/app/Info.plist" "$tmp/Renderer.app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string local.flclash.egressguard.screenshots "$tmp/Renderer.app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleExecutable -string render "$tmp/Renderer.app/Contents/Info.plist"
/bin/cp -R "$root/app/Resources/en.lproj" "$root/app/Resources/zh-Hans.lproj" "$tmp/Renderer.app/Contents/Resources/"
/usr/bin/xcrun swiftc -swift-version 5 -target "$(/usr/bin/uname -m)-apple-macosx13.0" \
    "$tmp/main.swift" "$root/app/GuardService.swift" "$root/app/Localization.swift" "$root/app/GuardMessages.swift" \
    -o "$tmp/Renderer.app/Contents/MacOS/render"

/bin/mkdir -p "$out"
# Language and time formatting are in-memory overrides, never system preferences.
"$tmp/Renderer.app/Contents/MacOS/render" "$out" "$root/docs/tools/palette.json" zh-Hans
"$tmp/Renderer.app/Contents/MacOS/render" "$out" "$root/docs/tools/palette.json" en
