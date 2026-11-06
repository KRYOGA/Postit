#!/bin/sh
set -eu
cd "$(dirname "$0")"

staging=$(mktemp -d "${TMPDIR:-/tmp}/postit-build.XXXXXX")
trap 'rm -r "$staging"' EXIT
app="$staging/Postit.app"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -module-cache-path "${TMPDIR:-/tmp}/postit-swift-modules" \
    -target "$(uname -m)-apple-macosx13.0" -parse-as-library -O \
    Sources/Postit.swift -o "$app/Contents/MacOS/Postit"
cp -X Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp -X Assets/Postit.icns "$app/Contents/Resources/"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/ditto --noextattr --norsrc "$app" Postit.app
/usr/bin/codesign --verify Postit.app
