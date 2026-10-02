#!/bin/zsh
# Builds, notarizes and packages a release into build/release/:
#   Switchyard-<version>.dmg   drag-to-Applications disk image (notarized, stapled)
#   Switchyard-<version>.zip   the stapled app, for the updater and Homebrew
#
# Needs a "Developer ID Application" identity (see build-app.sh) and notarization
# credentials stored once with:
#   xcrun notarytool store-credentials switchyard-notary --apple-id <Apple ID> --team-id <team ID>
# (override the profile name with SWITCHYARD_NOTARY_PROFILE).
set -euo pipefail

project_root="${0:A:h:h}"
app_name="Switchyard"
app="$project_root/build/$app_name.noindex/$app_name.app"
out="$project_root/build/release"
profile="${SWITCHYARD_NOTARY_PROFILE:-switchyard-notary}"

"$project_root/scripts/build-app.sh"

if ! codesign -dv "$app" 2>&1 | grep -q "^Authority=Developer ID Application:"; then
    echo "The app isn't signed with a Developer ID identity, so it can't be notarized." >&2
    echo "Create one in Xcode → Settings → Accounts → Manage Certificates, then run this again." >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
identity="$(codesign -dv "$app" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)/\1/p' | head -n 1)"
rm -rf "$out" && mkdir -p "$out"

notarize() {
    echo "Notarizing $(basename "$1")…"
    xcrun notarytool submit "$1" --keychain-profile "$profile" --wait
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

spctl --assess --type open --context context:primary-signature -v "$dmg"
echo
echo "Release $version ready in $out:"
(cd "$out" && shasum -a 256 *.dmg *.zip)
