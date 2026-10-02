#!/bin/zsh
# Builds, notarizes and packages a release into build/release/:
#   Switchyard-<version>.dmg   drag-to-Applications disk image (notarized, stapled)
#   Switchyard-<version>.zip   the stapled app, for the updater and Homebrew
#   appcast.xml                the update feed (signed with the Sparkle key in your keychain);
#                              upload all three to the GitHub release for v<version>
#
# Needs a "Developer ID Application" identity (see build-app.sh) and notarization credentials,
# either (preferred, works from any shell or CI) an App Store Connect API key:
#   SWITCHYARD_NOTARY_KEY_ID=… SWITCHYARD_NOTARY_ISSUER=… (e.g. in scripts/signing.local.zsh),
#   with the key at ~/.appstoreconnect/private_keys/AuthKey_<key ID>.p8 (or SWITCHYARD_NOTARY_KEY)
# or a keychain profile stored once with:
#   xcrun notarytool store-credentials switchyard-notary --apple-id <Apple ID> --team-id <team ID>
#   (override the profile name with SWITCHYARD_NOTARY_PROFILE).
set -euo pipefail

project_root="${0:A:h:h}"
app_name="Switchyard"
app="$project_root/build/$app_name.noindex/$app_name.app"
out="$project_root/build/release"

[[ -f "$project_root/scripts/signing.local.zsh" ]] && source "$project_root/scripts/signing.local.zsh"
if [[ -n "${SWITCHYARD_NOTARY_KEY_ID:-}" && -n "${SWITCHYARD_NOTARY_ISSUER:-}" ]]; then
    key="${SWITCHYARD_NOTARY_KEY:-$HOME/.appstoreconnect/private_keys/AuthKey_$SWITCHYARD_NOTARY_KEY_ID.p8}"
    [[ -f "$key" ]] || { echo "No API key at $key" >&2; exit 1; }
    notary_auth=(--key "$key" --key-id "$SWITCHYARD_NOTARY_KEY_ID" --issuer "$SWITCHYARD_NOTARY_ISSUER")
else
    notary_auth=(--keychain-profile "${SWITCHYARD_NOTARY_PROFILE:-switchyard-notary}")
fi

"$project_root/scripts/build-app.sh"

# Capture first: `codesign | grep -q` can fail under pipefail when grep exits early.
signature="$(codesign -dvv "$app" 2>&1)"   # -dvv lists the certificate chain (Authority=…)
if [[ "$signature" != *$'\n'"Authority=Developer ID Application:"* ]]; then
    echo "The app isn't signed with a Developer ID identity, so it can't be notarized." >&2
    echo "Create one in Xcode → Settings → Accounts → Manage Certificates, then run this again." >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
public_key="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$app/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "$public_key" ]]; then
    echo "SUPublicEDKey is empty in Resources/Info.plist, so this build couldn't verify its own updates." >&2
    echo "Run \$(scripts/sparkle-tools.sh)/generate_keys and put the public key there." >&2
    exit 1
fi
identity="$(print -r -- "$signature" | sed -n 's/^Authority=\(Developer ID Application:.*\)/\1/p' | sed -n 1p)"
rm -rf "$out" && mkdir -p "$out"

notarize() {
    echo "Notarizing $(basename "$1")…"
    xcrun notarytool submit "$1" "${notary_auth[@]}" --wait
}

# 1. Notarize the app itself and staple the ticket, so it verifies offline.
ditto -c -k --keepParent "$app" "$out/notarize.zip"
notarize "$out/notarize.zip"
xcrun stapler staple "$app"
rm "$out/notarize.zip"

# 2. Disk image with an Applications shortcut; signed, notarized and stapled too.
staging="$out/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/$app_name.app"
ln -s /Applications "$staging/Applications"
dmg="$out/$app_name-$version.dmg"
hdiutil create -volname "$app_name" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$staging"
codesign --force --timestamp --sign "$identity" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"

# 3. Zip of the stapled app, for the updater and Homebrew.
zip="$out/$app_name-$version.zip"
ditto -c -k --keepParent "$app" "$zip"

# 4. Update feed. Release notes come from this version's CHANGELOG.md section.
feed="$out/feed"
mkdir -p "$feed"
cp "$zip" "$feed/"
python3 - "$project_root/CHANGELOG.md" "$version" > "$feed/$app_name-$version.html" <<'PY'
import html, re, sys
text = open(sys.argv[1]).read()
match = re.search(rf"^## \[{re.escape(sys.argv[2])}\].*?\n(.*?)(?=^## |\Z)", text, re.S | re.M)
lines = [l.strip() for l in (match.group(1) if match else "").splitlines() if l.strip()]
paragraphs = [f"<p>{html.escape(l)}</p>" for l in lines if not l.startswith("- ")]
items = [f"<li>{html.escape(l[2:])}</li>" for l in lines if l.startswith("- ")]
print("\n".join(paragraphs) + (f"\n<ul>{''.join(items)}</ul>" if items else ""))
PY
sparkle_bin="$("$project_root/scripts/sparkle-tools.sh")"
"$sparkle_bin/generate_appcast" \
    --download-url-prefix "https://github.com/kevinebaugh/switchyard/releases/download/v$version/" \
    --embed-release-notes \
    -o "$out/appcast.xml" "$feed"
rm -rf "$feed"

spctl --assess --type open --context context:primary-signature -v "$dmg"
echo
echo "Release $version ready in $out:"
(cd "$out" && shasum -a 256 *.dmg *.zip && ls appcast.xml)
echo "Next: create the GitHub release v$version and attach the DMG, zip and appcast.xml."
