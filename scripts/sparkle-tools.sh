#!/bin/zsh
# Fetches Sparkle's command-line tools (generate_keys, sign_update, generate_appcast) into
# build/sparkle/, verifying the archive against the SHA-256 GitHub publishes for it.
# Prints the bin/ directory. The version matches the Sparkle package in Package.swift.
set -euo pipefail

project_root="${0:A:h:h}"
version="2.10.0"
sha256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
dir="$project_root/build/sparkle/$version"

if [[ ! -x "$dir/bin/generate_appcast" ]]; then
    mkdir -p "$dir"
    archive="$dir/Sparkle-$version.tar.xz"
    curl -sfL -o "$archive" "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"
    echo "$sha256  $archive" | shasum -a 256 -c - >/dev/null || { echo "Sparkle archive checksum mismatch" >&2; rm -f "$archive"; exit 1; }
    tar -xJf "$archive" -C "$dir"
    rm "$archive"
fi
echo "$dir/bin"
