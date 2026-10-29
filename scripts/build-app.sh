#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
build_root="$PWD/.build"
app="$PWD/dist/Auralim.app"
if [ "${AURALIM_DEBUG_TOOLS:-0}" = 1 ]; then
    build_root="$PWD/.build/debug-tools"
    app="$PWD/dist/debug/Auralim Debug.app"
fi
flags=(-c release --disable-sandbox --scratch-path "$build_root" --cache-path "$PWD/.build/cache")
if [ "${AURALIM_DEBUG_TOOLS:-0}" = 1 ]; then
    flags+=(-Xswiftc -DAURALIM_DEBUG_TOOLS)
fi
if [ "${AURALIM_UNIVERSAL:-0}" = 1 ]; then
    swift build "${flags[@]}" --arch x86_64
    intel_bin=$(swift build "${flags[@]}" --arch x86_64 --show-bin-path)
    swift build "${flags[@]}" --arch arm64
    arm_bin=$(swift build "${flags[@]}" --arch arm64 --show-bin-path)
    bin_dir="$intel_bin"
else
    swift build "${flags[@]}"
    bin_dir=$(swift build "${flags[@]}" --show-bin-path)
fi
for previous in "$PWD/dist/DuskShift.app" "$PWD/dist/Dusk Shift.app"; do
    if [ ! -e "$app" ] && [ -d "$previous" ]; then mv "$previous" "$app"; fi
done
rm -f "$app/Contents/MacOS/DuskShift"
rm -rf "$app/Contents/Resources/DuskShift_DuskShift.bundle" "$app/Contents/Resources/DuskShift_DuskShiftCore.bundle"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
if [ "${AURALIM_UNIVERSAL:-0}" = 1 ]; then
    lipo -create "$intel_bin/Auralim" "$arm_bin/Auralim" -output "$app/Contents/MacOS/Auralim"
else
    cp "$bin_dir/Auralim" "$app/Contents/MacOS/Auralim"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :AuralimDebugBuild bool false' "$app/Contents/Info.plist"
if [ "${AURALIM_DEBUG_TOOLS:-0}" = 1 ]; then
    /usr/libexec/PlistBuddy -c 'Set :AuralimDebugBuild true' "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.duskshift.mac.debug' "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName Auralim Debug' "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Auralim Debug' "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :SUEnableAutomaticChecks false' "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :SUAutomaticallyUpdate false' "$app/Contents/Info.plist"
fi
cp Resources/Auralim.icns "$app/Contents/Resources/Auralim.icns"
cp -R "$bin_dir/Auralim_Auralim.bundle" "$app/Contents/Resources/"
cp -R "$bin_dir/Auralim_AuralimCore.bundle" "$app/Contents/Resources/"
for localization in Resources/*.lproj; do
    language=$(basename "$localization" .lproj)
    mkdir -p "$app/Contents/Resources/$language.lproj"
    cp "$localization/InfoPlist.strings" "$app/Contents/Resources/$language.lproj/"
    if [ "${AURALIM_DEBUG_TOOLS:-0}" = 1 ]; then
        display_name="Auralim Debug"
        if [ "$language" = zh-Hans ]; then display_name="晦明 调试版"; fi
        if [ "$language" = zh-Hant ]; then display_name="晦明 除錯版"; fi
        /usr/libexec/PlistBuddy -c "Set :CFBundleName $display_name" "$app/Contents/Resources/$language.lproj/InfoPlist.strings"
        /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $display_name" "$app/Contents/Resources/$language.lproj/InfoPlist.strings"
    fi
done
# Frameworks contain version symlinks and signed helpers: preserve their layout.
framework="$app/Contents/Frameworks/Sparkle.framework"
rm -rf "$framework"
ditto "$build_root"/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$framework"
identity="${AURALIM_SIGN_IDENTITY:-${DUSK_SHIFT_SIGN_IDENTITY:--}}"
entitlements=Resources/Auralim.entitlements
if [ "$identity" = - ]; then
    # Ad-hoc hosts have no Team ID. Keep upstream Sparkle signatures and permit
    # loading that framework for local/unnotarized builds only.
    mkdir -p .build/signing
    entitlements=.build/signing/AdHoc.entitlements
    cp Resources/Auralim.entitlements "$entitlements"
    /usr/libexec/PlistBuddy -c 'Add :com.apple.security.cs.disable-library-validation bool true' "$entitlements"
else
    # Developer ID distribution: sign nested helpers first, retaining validation.
    codesign --force --sign "$identity" --options runtime "$framework/Versions/B/Autoupdate"
    for helper in "$framework"/Versions/B/XPCServices/*.xpc "$framework/Versions/B/Updater.app"; do
        codesign --force --sign "$identity" --options runtime "$helper"
    done
    codesign --force --sign "$identity" --options runtime "$framework"
fi
codesign --force --sign "$identity" --options runtime --entitlements "$entitlements" "$app"
codesign --verify --deep --strict "$app"
printf 'Built: %s\n' "$app"
