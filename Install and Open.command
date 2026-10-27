#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_archive="$task_root/dist/QuietDNS.app.zip"
if [ "$EUID" -eq 0 ]; then
    printf '%s\n' 'Run this installer as your normal Mac user, without sudo.'
    exit 1
fi
if /usr/bin/pgrep -x QuietDNS >/dev/null 2>&1; then
    printf '%s\n' 'QuietDNS is already running. Quit it from its shield menu, then run this installer again.'
    read -r -p 'Press Return to close.' task_reply
    exit 1
fi
if [ ! -f "$task_archive" ]; then
    printf '%s\n' 'Build the app first with Build QuietDNS.command.'
    exit 1
fi
task_stage="$(mktemp -d /private/tmp/QuietDNS-install.XXXXXX)"
trap '/bin/rm -rf "$task_stage"' EXIT
/usr/bin/ditto -x -k --norsrc --noextattr "$task_archive" "$task_stage"
/usr/bin/codesign --verify --deep --strict "$task_stage/QuietDNS.app"
task_destination="$HOME/Applications/QuietDNS.app"
/bin/mkdir -p "$HOME/Applications"
if [ -e "$task_destination" ]; then
    # Preserve an older build for rollback instead of deleting it during an update.
    task_previous="$HOME/Applications/QuietDNS.previous.$(date +%Y%m%d-%H%M%S).app"
    /bin/mv "$task_destination" "$task_previous"
    printf 'Previous build kept at: %s\n' "$task_previous"
fi
/usr/bin/ditto --norsrc --noextattr "$task_stage/QuietDNS.app" "$task_destination"
/usr/bin/codesign --verify --deep --strict "$task_destination"
/usr/bin/open "$task_destination" --args --show-panel
printf '\nInstalled: %s\nDNS is changed only when you click Turn On Ad Blocking and approve macOS.\n' "$task_destination"
