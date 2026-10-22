#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
bin_dir=$(swift build -c release --show-bin-path --cache-path "$PWD/.build/cache")
app="$PWD/dist/DuskShift.app"
# Preserve the existing bundle directory when adopting the new canonical name.
if [ ! -e "$app" ] && [ -d "$PWD/dist/Dusk Shift.app" ]; then
    mv "$PWD/dist/Dusk Shift.app" "$app"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/DuskShift" "$app/Contents/MacOS/DuskShift"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R "$bin_dir/DuskShift_DuskShift.bundle" "$app/Contents/Resources/"
cp -R "$bin_dir/DuskShift_DuskShiftCore.bundle" "$app/Contents/Resources/"
for language in en zh-Hans zh-Hant; do
    mkdir -p "$app/Contents/Resources/$language.lproj"
    cp "Resources/$language.lproj/InfoPlist.strings" "$app/Contents/Resources/$language.lproj/"
done
codesign --force --sign "${DUSK_SHIFT_SIGN_IDENTITY:--}" --options runtime --entitlements Resources/DuskShift.entitlements "$app"
codesign --verify --strict "$app"
printf 'Built: %s\n' "$app"
