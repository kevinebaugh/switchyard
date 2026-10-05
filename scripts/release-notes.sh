#!/bin/zsh
# Prints the GitHub release notes for a version: its CHANGELOG.md section plus install steps.
#   scripts/release-notes.sh 0.9.4
set -euo pipefail

project_root="${0:A:h:h}"
version="$1"

notes="$(awk -v v="$version" '
    $0 ~ "^## \\[" v "\\]" { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' "$project_root/CHANGELOG.md" | sed -e '/./,$!d')"
[[ -n "$notes" ]] || { echo "CHANGELOG.md has no section for $version" >&2; exit 1; }

cat <<NOTES
$notes

### Install

Already using Switchyard? Settings → **Check for Updates…**. New here: download **Switchyard-$version.dmg**, open it, and drag Switchyard to Applications. Needs macOS 26 or later, on Apple silicon or Intel.
NOTES
