#!/bin/zsh
# Builds, installs to /Applications, and (re)launches Switchyard.
set -euo pipefail

project_root="${0:A:h:h}"
app_name="Switchyard"
installed="/Applications/$app_name.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$project_root/scripts/build-app.sh"

osascript -e "tell application id \"dev.kev.Switchyard\" to quit" 2>/dev/null || true
sleep 0.5
pkill -x "$app_name" 2>/dev/null || true

rm -rf "$installed"
built="$project_root/build/$app_name.noindex/$app_name.app"
ditto "$built" "$installed"
"$lsregister" -f "$installed"
# Only the installed copy should be known to macOS (link handling, Spotlight, Alfred).
"$lsregister" -u "$built" 2>/dev/null || true
open "$installed"
echo "Installed and launched $installed"
