#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="${QUIETDNS_BUILD_ROOT:-$task_root/work/build}"
mkdir -p "$task_build/modules" "$task_build/cache"
export CLANG_MODULE_CACHE_PATH="$task_build/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_build/modules"
cd "$task_root"
task_flags=()
task_developer="$(xcode-select -p)"
task_swift_bin="$(dirname "$(xcrun --find swift)")"
task_frameworks="$task_developer/Library/Developer/Frameworks"
task_macro="$task_swift_bin/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
# Standalone Command Line Tools supply Swift Testing outside the SDK's default search path.
if [ -d "$task_frameworks/Testing.framework" ]; then
    task_flags+=(-Xswiftc -F -Xswiftc "$task_frameworks" -Xlinker -rpath -Xlinker "$task_frameworks")
fi
if [ -f "$task_macro" ]; then
    task_flags+=(-Xswiftc -load-plugin-library -Xswiftc "$task_macro")
fi
swift test --build-system native --disable-sandbox --disable-xctest --scratch-path "$task_build/package" --cache-path "$task_build/cache" "${task_flags[@]}"
