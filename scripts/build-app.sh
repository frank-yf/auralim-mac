#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
bin_dir=$(swift build -c release --show-bin-path --cache-path "$PWD/.build/cache")
app="$PWD/dist/Dusk Shift.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/DuskShift" "$app/Contents/MacOS/DuskShift"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${DUSK_SHIFT_SIGN_IDENTITY:--}" --options runtime --entitlements Resources/DuskShift.entitlements "$app"
codesign --verify --strict "$app"
printf 'Built: %s\n' "$app"
