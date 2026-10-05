#!/bin/zsh
# Builds build/Switchyard.noindex/Switchyard.app from the Swift package.
# The .noindex folder keeps Spotlight (and launchers like Alfred) from listing this
# intermediate copy next to the installed app.
#
# Signing, in order of preference:
#   1. SWITCHYARD_SIGNING_IDENTITY, if set (e.g. in the gitignored scripts/signing.local.zsh)
#   2. a "Developer ID Application" identity (for releases), pinned with SWITCHYARD_TEAM_ID
#      when the keychain holds more than one (say, a personal team and an employer's)
#   3. an "Apple Development" identity (stable local builds)
#   4. ad-hoc (macOS re-asks for permissions after each rebuild)
# Signing-identity detection adapted from jdsimcoe/dia-router (MIT); see THIRD_PARTY_NOTICES.md.
set -euo pipefail

project_root="${0:A:h:h}"
app_name="Switchyard"
app_bundle="$project_root/build/$app_name.noindex/$app_name.app"
contents="$app_bundle/Contents"
plist_buddy=/usr/libexec/PlistBuddy

[[ -f "$project_root/scripts/signing.local.zsh" ]] && source "$project_root/scripts/signing.local.zsh"

identities() {
    security find-identity -v -p codesigning 2>/dev/null | sed -n "s/.*\"\($1:[^\"]*\)\".*/\1/p"
}

signing_identity="${SWITCHYARD_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    developer_ids=("${(@f)$(identities 'Developer ID Application')}")
    developer_ids=(${developer_ids:#})
    if [[ -n "${SWITCHYARD_TEAM_ID:-}" ]]; then
        developer_ids=(${(M)developer_ids:#*\($SWITCHYARD_TEAM_ID\)})
    fi
    if (( ${#developer_ids} > 1 )); then
        echo "Several Developer ID identities found; set SWITCHYARD_TEAM_ID (scripts/signing.local.zsh) to pick one:" >&2
        printf '  %s\n' "${developer_ids[@]}" >&2
        exit 1
    fi
    signing_identity="${developer_ids[1]:-$(identities 'Apple Development' | head -n 1)}"
fi

# Version: the latest v* tag (v0.9.0 → 0.9.0), else Info.plist's; build number: commit count.
version="$(git -C "$project_root" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || true)"
build_number="$(git -C "$project_root" rev-list --count HEAD 2>/dev/null || echo 1)"

# Universal: Apple silicon and Intel (the last Intel Macs run macOS 26). Sparkle's framework is
# already universal.
build_flags=(--package-path "$project_root" -c release --arch arm64 --arch x86_64)
swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"

rm -rf "$project_root/build/$app_name.app" "$app_bundle"   # also clears the old, indexed location
mkdir -p "$contents/MacOS" "$contents/Resources" "$contents/Frameworks"
cp "$bin_dir/Switchyard" "$contents/MacOS/$app_name"
ditto "$bin_dir/Sparkle.framework" "$contents/Frameworks/Sparkle.framework"   # in-app updates
cp "$project_root/Resources/Info.plist" "$contents/Info.plist"
[[ -n "$version" ]] && "$plist_buddy" -c "Set :CFBundleShortVersionString $version" "$contents/Info.plist"
"$plist_buddy" -c "Set :CFBundleVersion $build_number" "$contents/Info.plist"
version="$("$plist_buddy" -c "Print :CFBundleShortVersionString" "$contents/Info.plist")"

# Licenses travel with the app (shown in the About window).
cp "$project_root/LICENSE" "$project_root/THIRD_PARTY_NOTICES.md" "$contents/Resources/"

# Liquid Glass app icon (Icon Composer bundle) → Assets.car + AppIcon.icns.
xcrun actool "$project_root/Resources/AppIcon.icon" \
    --compile "$contents/Resources" \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --include-all-app-icons \
    --output-partial-info-plist "$project_root/build/icon-info.plist" >/dev/null

entitlements="$project_root/Resources/Switchyard.entitlements"
case "$signing_identity" in
    "Developer ID Application:"*)
        # Release signing: hardened runtime + secure timestamp, both required for notarization.
        sign_flags=(--force --options runtime --timestamp --sign "$signing_identity") ;;
    "")
        # Hardened runtime here too, so local builds behave like releases (e.g. Apple Events
        # only work because of the entitlement).
        sign_flags=(--force --options runtime --sign -) ;;
    *)
        sign_flags=(--force --options runtime --timestamp=none --sign "$signing_identity") ;;
esac

# Sign inside-out, as Sparkle documents: its helpers, then the framework, then the app.
sparkle="$contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${sign_flags[@]}" "$sparkle/XPCServices/Installer.xpc"
codesign "${sign_flags[@]}" --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
codesign "${sign_flags[@]}" "$sparkle/Autoupdate"
codesign "${sign_flags[@]}" "$sparkle/Updater.app"
codesign "${sign_flags[@]}" "$contents/Frameworks/Sparkle.framework"
codesign "${sign_flags[@]}" --entitlements "$entitlements" "$app_bundle"

if [[ -n "$signing_identity" ]]; then
    echo "Signed with $signing_identity"
else
    echo "Ad-hoc signed. macOS will re-ask for Automation/Keychain access after each rebuild."
fi

echo "Built $app_name $version ($build_number), $(lipo -archs "$contents/MacOS/$app_name"): $app_bundle"
