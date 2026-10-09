#!/usr/bin/env bash
# Builds a release Spyre.app under .build/app/ with an ad-hoc signature.
# Local use and CI only. Release signing and notarization: see docs/release.md.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release
bin="$(swift build -c release --show-bin-path)"
app=".build/app/Spyre.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp App/Info.plist "$app/Contents/Info.plist"
cp "$bin/Spyre" "$app/Contents/MacOS/Spyre"
# Bundle.module finds the SwiftPM resource bundle in Contents/Resources.
cp -R "$bin/Spyre_SpyreCore.bundle" "$app/Contents/Resources/"

plutil -lint "$app/Contents/Info.plist" >/dev/null
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "Built $app"
