#!/bin/sh
set -eu
src=$(CDPATH= cd "$(dirname "$0")" && pwd)
controls="$src/../outputs/flclash-guard"
bundle=${1:?Supply a new path ending in .app}
mkdir "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
tmp=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$tmp"' EXIT
mkdir "$tmp/Guard.iconset"
/usr/bin/xcrun swiftc -O -swift-version 5 -target "$(/usr/bin/uname -m)-apple-macosx13.0" \
    "$src/main.swift" "$src/GuardService.swift" "$src/Localization.swift" "$src/GuardMessages.swift" -o "$bundle/Contents/MacOS/FlClashGuard"
/usr/bin/xcrun swiftc -O -swift-version 5 -target "$(/usr/bin/uname -m)-apple-macosx13.0" \
    "$src/GuardService.swift" "$src/GuardHelper.swift" -o "$bundle/Contents/Resources/guard-helper"
/usr/bin/codesign --force --options runtime --sign - "$bundle/Contents/Resources/guard-helper"
/usr/bin/xcrun swift "$src/Icon.swift" "$tmp/Guard.iconset"
/usr/bin/iconutil -c icns "$tmp/Guard.iconset" -o "$bundle/Contents/Resources/Guard.icns"
/bin/cp "$src/Info.plist" "$bundle/Contents/Info.plist"
/bin/cp -R "$src/Resources/en.lproj" "$src/Resources/zh-Hans.lproj" "$bundle/Contents/Resources/"
/bin/cp "$src/Authorize.applescript" "$src/guard-authorize" "$controls/egress-guard" "$controls/policy.pf" \
    "$controls/guard-guide" "$bundle/Contents/Resources/"
/bin/chmod 755 "$bundle/Contents/Resources/egress-guard" "$bundle/Contents/Resources/guard-guide" "$bundle/Contents/Resources/guard-authorize"
/usr/bin/plutil -lint "$bundle/Contents/Info.plist"
/usr/bin/codesign --options runtime --sign - "$bundle"
/usr/bin/codesign --verify --strict "$bundle"
