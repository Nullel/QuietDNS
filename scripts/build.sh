#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="${QUIETDNS_BUILD_ROOT:-$task_root/work/build}"
mkdir -p "$task_build/modules" "$task_build/cache"
export CLANG_MODULE_CACHE_PATH="$task_build/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_build/modules"
cd "$task_root"
# Build the two executables without external packages or build plugins.
swift build --build-system native --disable-sandbox -c release --scratch-path "$task_build/package" --cache-path "$task_build/cache"
task_bin="$(swift build --build-system native --disable-sandbox -c release --scratch-path "$task_build/package" --cache-path "$task_build/cache" --show-bin-path | tail -1)"
task_stage="$(mktemp -d /private/tmp/QuietDNS-package.XXXXXX)"
trap '/bin/rm -rf "$task_stage"' EXIT
task_app="$task_stage/QuietDNS.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_bin/QuietDNS" "$task_app/Contents/MacOS/QuietDNS"
cp "$task_bin/quietdns-helper" "$task_app/Contents/MacOS/quietdns-helper"
cp "$task_root/START-HERE.html" "$task_app/Contents/Resources/START-HERE.html"
cp "$task_root/README.md" "$task_app/Contents/Resources/README.md"
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>QuietDNS</string>
<key>CFBundleDisplayName</key><string>QuietDNS</string>
<key>CFBundleIdentifier</key><string>local.quietdns.menubar</string>
<key>CFBundleExecutable</key><string>QuietDNS</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
chmod 755 "$task_app/Contents/MacOS/QuietDNS" "$task_app/Contents/MacOS/quietdns-helper"
# Local ad-hoc signing; distribution to other Macs requires Developer ID signing + notarization.
/usr/bin/codesign --force --sign - "$task_app/Contents/MacOS/quietdns-helper"
/usr/bin/codesign --force --sign - "$task_app"
/usr/bin/codesign --verify --deep --strict "$task_app"
mkdir -p "$task_root/dist"
# Keep the signed bundle in an archive; iCloud/File Provider may add Finder metadata to a loose .app.
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$task_app" "$task_root/dist/QuietDNS.app.zip"
printf '\nBuilt: %s\nRun Install and Open.command, then click the shield in the menu bar.\n' "$task_root/dist/QuietDNS.app.zip"
