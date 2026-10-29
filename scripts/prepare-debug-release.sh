#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/debug/Auralim Debug.app"
info="$app/Contents/Info.plist"
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" != app.duskshift.mac.debug ] ||
   [ "$(/usr/libexec/PlistBuddy -c 'Print :AuralimDebugBuild' "$info")" != true ]; then
    printf '%s\n' 'Expected a debug-tools app. Run AURALIM_UNIVERSAL=1 make build-debug.' >&2; exit 1
fi
for key in CFBundleShortVersionString CFBundleVersion; do
    if [ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$info")" != "$(/usr/libexec/PlistBuddy -c "Print :$key" Resources/Info.plist)" ]; then
        printf '%s\n' 'Debug app version/build differs from source; rebuild first.' >&2; exit 1
    fi
done
architectures=$(lipo -archs "$app/Contents/MacOS/Auralim")
if [[ "$architectures" != *x86_64* ]] || [[ "$architectures" != *arm64* ]]; then
    printf '%s\n' 'Debug release assets require Intel and Apple silicon. Run AURALIM_UNIVERSAL=1 make build-debug.' >&2; exit 1
fi
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
output="$PWD/dist/debug-releases/$version"
archive="Auralim-$version-debug-macos-universal.zip"
if [ -e "$output/$archive" ] || [ -e "$output/SHA256SUMS-debug.txt" ]; then
    printf '%s\n' 'Debug assets already exist; refusing to overwrite.' >&2; exit 1
fi
mkdir -p "$output"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$archive"
(cd "$output" && shasum -a 256 "$archive" > SHA256SUMS-debug.txt)
printf 'Prepared: %s\nUpload the debug ZIP and SHA256SUMS-debug.txt alongside the stable assets in GitHub Release v%s. Do not add debug assets to appcast.xml.\n' "$output" "$version"
