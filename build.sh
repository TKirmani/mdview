#!/bin/bash
# Build MDView.app from the SPM executable.
# Usage: ./build.sh [--sandbox]
#   --sandbox  sign with the App Sandbox, as an App Store build must be. Local
#              images then need a one-time folder grant, so it is off by default.
set -euo pipefail
cd "$(dirname "$0")"

SANDBOX=0
[ "${1:-}" = "--sandbox" ] && SANDBOX=1

swift build -c release

APP=build/MDView.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/mdview "$APP/Contents/MacOS/mdview"
# Copy resources flat into Contents/Resources. The SwiftPM bundle is NOT used:
# its generated accessor looks beside the .app, misses, and falls back to a
# hardcoded .build path that exists only on the build machine.
cp Sources/mdview/Resources/* "$APP/Contents/Resources/"
[ -f AppIcon.icns ] || swift icon.swift
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"

# Quick Look preview extension (.appex), assembled manually — no Xcode here
swiftc -O -parse-as-library -application-extension -module-name MDPreview \
    Sources/mdview-quicklook/PreviewProvider.swift \
    -framework Foundation -framework QuickLookUI -framework JavaScriptCore \
    -Xlinker -application_extension -Xlinker -e -Xlinker _NSExtensionMain \
    -o .build/mdpreview
APPEX="$APP/Contents/PlugIns/MDPreview.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp .build/mdpreview "$APPEX/Contents/MacOS/mdpreview"
cp MDPreview-Info.plist "$APPEX/Contents/Info.plist"
cp Sources/mdview/Resources/{marked.min.js,marked-footnote.min.js,highlight.min.js,style.css,hljs-github.css,hljs-github-dark.css} \
   "$APPEX/Contents/Resources/"

# sign inside-out: sandboxed appex first, then the app
codesign --force -s - --entitlements mdpreview.entitlements "$APPEX"
if [ "$SANDBOX" = 1 ]; then
    codesign --force -s - --entitlements mdview.entitlements "$APP"
else
    codesign --force -s - "$APP"
fi
[ "$SANDBOX" = 1 ] && echo "(sandboxed build)"
echo "Built $APP ($(du -sh "$APP" | cut -f1)), binary $(du -h "$APP/Contents/MacOS/mdview" | cut -f1)"
