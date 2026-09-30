#!/bin/zsh
# Builds build/Switchyard.noindex/Switchyard.app from the Swift package.
# The .noindex folder keeps Spotlight (and launchers like Alfred) from listing this
# intermediate copy next to the installed app.
# Signing-identity detection adapted from jdsimcoe/dia-router (MIT); see THIRD_PARTY_NOTICES.md.
set -euo pipefail

project_root="${0:A:h:h}"
app_name="Switchyard"
app_bundle="$project_root/build/$app_name.noindex/$app_name.app"
contents="$app_bundle/Contents"

[[ -f "$project_root/scripts/signing.local.zsh" ]] && source "$project_root/scripts/signing.local.zsh"

# Prefer a stable Apple Development identity (keeps Automation/Keychain grants across rebuilds).
signing_identity="${SWITCHYARD_SIGNING_IDENTITY:-$(
    security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1
)}"

swift build --package-path "$project_root" -c release

rm -rf "$project_root/build/$app_name.app" "$app_bundle"   # also clears the old, indexed location
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$project_root/.build/release/Switchyard" "$contents/MacOS/$app_name"
cp "$project_root/Resources/Info.plist" "$contents/Info.plist"

# Liquid Glass app icon (Icon Composer bundle) → Assets.car + AppIcon.icns.
xcrun actool "$project_root/Resources/AppIcon.icon" \
    --compile "$contents/Resources" \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --include-all-app-icons \
    --output-partial-info-plist "$project_root/build/icon-info.plist" >/dev/null

if [[ -n "$signing_identity" ]]; then
    codesign --force --timestamp=none --sign "$signing_identity" "$app_bundle"
    echo "Signed with $signing_identity"
else
    codesign --force --sign - "$app_bundle"
    echo "Ad-hoc signed. macOS will re-ask for Automation/Keychain access after each rebuild."
fi

echo "Built $app_bundle"
