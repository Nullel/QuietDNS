#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
"$task_root/scripts/build.sh"
"$task_root/Install and Open.command"
