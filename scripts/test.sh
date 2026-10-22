#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
flags=()
# Some Command Line Tools distributions ship Testing as a framework while
# SwiftPM only adds this directory as an import (-I) path.
frameworks="$(xcode-select -p)/Library/Developer/Frameworks"
if [ -d "$frameworks/Testing.framework" ]; then
    flags=(-Xswiftc -F -Xswiftc "$frameworks" -Xlinker -F -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$(xcode-select -p)/Library/Developer/usr/lib")
fi
swift test --disable-sandbox --disable-xctest --enable-swift-testing --cache-path "$PWD/.build/cache" "${flags[@]}"
