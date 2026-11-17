#!/bin/sh
# Localisation and documentation checks. Never launches the app, controller or helper.
set -eu
root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$tmp"' EXIT

for file in "$root/outputs/flclash-guard/egress-guard" "$root/outputs/flclash-guard/guard-guide" "$root/app/guard-authorize"; do
    /usr/bin/python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])' "$file"
done
for file in "$root/app/build.sh" "$root/docs/tools/render-screenshots.sh" "$root"/outputs/flclash-guard/*.command; do
    sh -n "$file"
done
for file in "$root/app/Info.plist" "$root"/app/Resources/*.lproj/*.strings; do
    /usr/bin/plutil -lint "$file"
done

# Include the shipping views and models, excluding all top-level app launch code.
line=$(/usr/bin/awk '/^let application = NSApplication.shared$/ { print NR; exit }' "$root/app/main.swift")
test -n "$line"
/usr/bin/head -n $((line - 1)) "$root/app/main.swift" > "$tmp/main.swift"
/bin/cat "$root/tests/LocalizationTests.swift" >> "$tmp/main.swift"
/usr/bin/xcrun swiftc -swift-version 5 -target "$(/usr/bin/uname -m)-apple-macosx13.0" \
    "$tmp/main.swift" "$root/app/GuardService.swift" "$root/app/Localization.swift" \
    "$root/app/GuardMessages.swift" -o "$tmp/localization-tests"
"$tmp/localization-tests" "${1:-"$root/app/Resources"}"
/usr/bin/python3 -I "$root/tests/verify_docs.py" "$root"
