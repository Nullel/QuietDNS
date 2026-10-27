#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_stage="$(mktemp -d /private/tmp/QuietDNS-restore.XXXXXX)"
trap '/bin/rm -rf "$task_stage"' EXIT
task_helper="$HOME/Applications/QuietDNS.app/Contents/MacOS/quietdns-helper"
if [ ! -x "$task_helper" ] && [ -x "/Applications/QuietDNS.app/Contents/MacOS/quietdns-helper" ]; then
    task_helper="/Applications/QuietDNS.app/Contents/MacOS/quietdns-helper"
fi
if [ ! -x "$task_helper" ] && [ -f "$task_root/dist/QuietDNS.app.zip" ]; then
    /usr/bin/ditto -x -k --norsrc --noextattr "$task_root/dist/QuietDNS.app.zip" "$task_stage"
    /usr/bin/codesign --verify --deep --strict "$task_stage/QuietDNS.app"
    task_helper="$task_stage/QuietDNS.app/Contents/MacOS/quietdns-helper"
fi
if [ ! -x "$task_helper" ]; then
    printf '%s\n' 'QuietDNS helper not found. Rebuild with scripts/build.sh, then retry. Keep the recovery.plist file.'
    read -r -p 'Press Return to close.' task_reply
    exit 1
fi
printf '%s\n' 'Restore the original DNS settings saved by QuietDNS.' 'macOS asks for an administrator password. Nothing is downloaded.'
sudo -- "$task_helper" --restore
printf '\n%s\n' 'Original DNS restored. Restart BlueStacks and any app with cached DNS.'
read -r -p 'Press Return to close.' task_reply
