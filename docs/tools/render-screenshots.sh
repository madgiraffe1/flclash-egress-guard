#!/bin/sh
# Re-renders the README screenshots in docs/images from the app's real SwiftUI
# views (app/main.swift) with sample data, plus the app icon from app/Icon.swift.
#
# Safe to run on a protected Mac: it compiles a throwaway binary in a temporary
# folder. Nothing starts the controller, the system helper or pfctl, and nothing
# touches the network, FlClash or system settings. Requires Xcode Command Line Tools.
#
#   sh docs/tools/render-screenshots.sh [output-dir]
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
/bin/cp "$root/app/GuardService.swift" "$tmp/"
/usr/bin/xcrun swiftc -swift-version 5 -target "$(/usr/bin/uname -m)-apple-macosx13.0" \
    "$tmp/main.swift" "$tmp/GuardService.swift" -o "$tmp/render"

/bin/mkdir -p "$out"
# The UI is Simplified Chinese; pin the locale so times render the same way everywhere.
"$tmp/render" "$out" "$root/docs/tools/palette.json" -AppleLocale zh_CN -AppleLanguages '(zh-Hans)'

# The real app icon, drawn by the same code app/build.sh uses.
/bin/mkdir "$tmp/Guard.iconset"
/usr/bin/xcrun swift "$root/app/Icon.swift" "$tmp/Guard.iconset"
/bin/cp "$tmp/Guard.iconset/icon_128x128@2x.png" "$out/app-icon.png"
echo "wrote app-icon.png"
