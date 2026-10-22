#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${AURALIM_UPDATE_APP:-$PWD/dist/Auralim.app}"
info="$app/Contents/Info.plist"
tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
account=app.duskshift.mac
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")
source_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
source_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
if [ "$version" != "$source_version" ] || [ "$build" != "$source_build" ]; then
    printf '%s\n' 'App version/build differs from source; run make build first.' >&2; exit 1
fi
architectures=$(lipo -archs "$app/Contents/MacOS/Auralim")
if [[ "$architectures" != *x86_64* ]] || [[ "$architectures" != *arm64* ]]; then
    printf '%s\n' 'Release updates require a universal app. Run AURALIM_UNIVERSAL=1 make build.' >&2; exit 1
fi
codesign --verify --deep --strict "$app"
public_key=$("$tools/generate_keys" --account "$account" -p)
app_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info")
if [ "$public_key" != "$app_key" ]; then
    printf '%s\n' 'Signing key does not match the public key in the app. Refusing to publish an unusable update.' >&2; exit 1
fi
output="$PWD/dist/updates/$version"
mkdir -p "$output"
archive="$output/Auralim-$version-macos-universal.zip"
if [ -e "$archive" ] || [ -e "$output/appcast.xml" ]; then
    printf '%s\n' 'Update artifacts already exist. Use a new version/build or explicitly move the old artifacts before generating again.' >&2; exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
"$tools/generate_appcast" --account "$account" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/frank-yf/auralim-mac/releases/download/v$version/" \
    --link "https://github.com/frank-yf/auralim-mac/releases/tag/v$version" "$output"
"$tools/sign_update" --account "$account" --verify "$output/appcast.xml"
python3 scripts/verify-update.py "$output/appcast.xml" "$archive" "$info"
(cd "$output" && shasum -a 256 "$(basename "$archive")" appcast.xml > SHA256SUMS.txt)
printf '\nPrepared signed update assets: %s\nUpload the ZIP, appcast.xml and SHA256SUMS.txt to GitHub Release v%s, and mark it Latest.\n' "$output" "$version"
