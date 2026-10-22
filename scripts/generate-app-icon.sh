#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep the original artwork; generate the complete macOS 1x/2x icon family.
icon_tmp=$(mktemp -d "${TMPDIR:-/tmp}/auralim-icon.XXXXXX")
trap 'rm -rf "$icon_tmp"' EXIT
iconset="$icon_tmp/Auralim.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/Icons/Auralim.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" Resources/Icons/Auralim.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/Auralim.icns
printf 'Generated: %s/Resources/Auralim.icns\n' "$PWD"
