#!/bin/zsh
# Rehearse Switchyard's first-run setup with throwaway settings, API key, rules and history.
# Your real setup is untouched and comes back when you quit the rehearsal.
#
# The default browser and the Automation permission are system-wide, so the rehearsal sees
# them as they really are. Pass --reset-permission to clear Switchyard's Automation grant
# first, so the "Let Switchyard open tabs in Dia" step starts from scratch.
set -euo pipefail

app="/Applications/Switchyard.app"
bundle_id="com.kevinebaugh.switchyard"
reset_permission=false

for arg in "$@"; do
    case "$arg" in
        --reset-permission) reset_permission=true ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [[ ! -d "$app" ]]; then
    echo "Install Switchyard first: ./scripts/install-app.sh" >&2
    exit 1
fi

osascript -e "tell application id \"$bundle_id\" to quit" 2>/dev/null || true
sleep 0.5
pkill -x Switchyard 2>/dev/null || true

if $reset_permission; then
    tccutil reset AppleEvents "$bundle_id"
fi

rehearsal_dir="$(mktemp -d -t switchyard-rehearsal)"
echo "Rehearsing setup (storage: $rehearsal_dir)."
echo "When you're done, quit Switchyard from its menu bar icon; your normal setup relaunches."

open -W -n "$app" --args --rehearsal "$rehearsal_dir"

rm -rf "$rehearsal_dir"
open "$app"
echo "Rehearsal over; Switchyard is back to your normal setup."
