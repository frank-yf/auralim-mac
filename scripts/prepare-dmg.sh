#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/Auralim.app"
info="$app/Contents/Info.plist"
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" != app.duskshift.mac ] ||
   [ "$(/usr/libexec/PlistBuddy -c 'Print :AuralimDebugBuild' "$info")" != false ]; then
    printf '%s\n' 'Expected a standard app, not a debug build.' >&2; exit 1
fi
for key in CFBundleShortVersionString CFBundleVersion; do
    if [ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$info")" != "$(/usr/libexec/PlistBuddy -c "Print :$key" Resources/Info.plist)" ]; then
        printf '%s\n' 'App version/build differs from source; rebuild first.' >&2; exit 1
    fi
done
architectures=$(lipo -archs "$app/Contents/MacOS/Auralim")
if [[ "$architectures" != *x86_64* ]] || [[ "$architectures" != *arm64* ]]; then
    printf '%s\n' 'DMG release assets require a universal app.' >&2; exit 1
fi
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
output="$PWD/dist/updates/$version"
dmg="Auralim-$version-macos-universal.dmg"
if [ -e "$output/$dmg" ]; then
    printf '%s\n' 'DMG already exists; refusing to overwrite.' >&2; exit 1
fi
# The signed ZIP and appcast must exist before their checksum list is extended.
test -f "$output/Auralim-$version-macos-universal.zip"
test -f "$output/appcast.xml"
mkdir -p artifacts
staging=$(mktemp -d "$PWD/artifacts/dmg-$version.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Auralim.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Auralim $version" -srcfolder "$staging" -format UDZO "$output/$dmg"
(cd "$output" && shasum -a 256 "$dmg" "Auralim-$version-macos-universal.zip" appcast.xml > SHA256SUMS.txt)
printf 'Prepared DMG: %s\n' "$output/$dmg"
