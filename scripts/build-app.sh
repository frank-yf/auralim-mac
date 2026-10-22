#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
bin_dir=$(swift build -c release --show-bin-path --cache-path "$PWD/.build/cache")
app="$PWD/dist/Auralim.app"
# Keep the existing bundle directory and identity when upgrading either old name.
for previous in "$PWD/dist/DuskShift.app" "$PWD/dist/Dusk Shift.app"; do
    if [ ! -e "$app" ] && [ -d "$previous" ]; then
        mv "$previous" "$app"
    fi
done
# Remove only obsolete generated products after the module/executable rename.
rm -f "$app/Contents/MacOS/DuskShift"
rm -rf "$app/Contents/Resources/DuskShift_DuskShift.bundle" "$app/Contents/Resources/DuskShift_DuskShiftCore.bundle"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Auralim" "$app/Contents/MacOS/Auralim"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Auralim.icns "$app/Contents/Resources/Auralim.icns"
cp -R "$bin_dir/Auralim_Auralim.bundle" "$app/Contents/Resources/"
cp -R "$bin_dir/Auralim_AuralimCore.bundle" "$app/Contents/Resources/"
for language in en zh-Hans zh-Hant; do
    mkdir -p "$app/Contents/Resources/$language.lproj"
    cp "Resources/$language.lproj/InfoPlist.strings" "$app/Contents/Resources/$language.lproj/"
done
codesign --force --sign "${AURALIM_SIGN_IDENTITY:-${DUSK_SHIFT_SIGN_IDENTITY:--}}" --options runtime --entitlements Resources/Auralim.entitlements "$app"
codesign --verify --strict "$app"
printf 'Built: %s\n' "$app"
