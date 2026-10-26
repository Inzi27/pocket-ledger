#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/config .build/security .build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/ModuleCache"
swift test --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --scratch-path .build/xcode-swiftpm
python3 scripts/validate_project.py
xcodebuild -project PocketLedger.xcodeproj -scheme PocketLedger -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath "$PWD/.build/DerivedData" \
    CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS=-disable-sandbox build
