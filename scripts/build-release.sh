#!/bin/zsh
# Builds a universal Scrub.app and packages it as dist/Scrub.dmg and dist/Scrub.zip.
#
#   ./scripts/build-release.sh [version]
#
# With SCRUB_TEAM_ID set, the app is archived, signed with that team's Developer ID certificate
# (Xcode's cloud-managed certificate works) and notarized through the Apple ID signed in to Xcode.
# The notarization ticket is stapled to the app. To also notarize the disk image, provide notarytool
# credentials: SCRUB_NOTARY_PROFILE (a `notarytool store-credentials` profile) or
# SCRUB_NOTARY_KEY, SCRUB_NOTARY_KEY_ID and SCRUB_NOTARY_ISSUER (an App Store Connect API key).
#
# Without SCRUB_TEAM_ID, the app is ad-hoc signed so anyone can build it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(grep 'MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')}"
BUILD="build/release"
DIST="dist"
TEAM="${SCRUB_TEAM_ID:-}"

command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
xcodegen generate --quiet
rm -rf "$BUILD" "$DIST" && mkdir -p "$BUILD" "$DIST"

COMMON=(-project Scrub.xcodeproj -scheme Scrub -configuration Release -destination "generic/platform=macOS"
        ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO MARKETING_VERSION="$VERSION")

if [[ -n "$TEAM" ]]; then
  echo "› Archiving for team $TEAM"
  xcodebuild "${COMMON[@]}" -archivePath "$BUILD/Scrub.xcarchive" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" -quiet archive

  sed "s/__TEAM__/$TEAM/" scripts/ExportOptions.plist > "$BUILD/ExportOptions.plist"
  echo "› Signing with Developer ID and uploading to Apple's notary service"
  xcodebuild -exportArchive -archivePath "$BUILD/Scrub.xcarchive" -exportOptionsPlist "$BUILD/ExportOptions.plist" \
    -exportPath "$BUILD/upload" -allowProvisioningUpdates -quiet

  echo "› Waiting for notarization"
  for attempt in {1..90}; do
    if xcodebuild -exportNotarizedApp -archivePath "$BUILD/Scrub.xcarchive" -exportPath "$BUILD/notarized" \
         -allowProvisioningUpdates -quiet >/dev/null 2>&1; then break; fi
    (( attempt == 90 )) && { echo "Notarization did not finish in time"; exit 1; }
    sleep 20
  done
  APP="$BUILD/notarized/Scrub.app"
  xcrun stapler validate "$APP"
  spctl -a -t exec -vv "$APP"
else
  echo "› Building ad-hoc signed app (set SCRUB_TEAM_ID to sign and notarize)"
  xcodebuild "${COMMON[@]}" -derivedDataPath "$BUILD/dd" -quiet clean build
  APP="$BUILD/dd/Build/Products/Release/Scrub.app"
  codesign --force --deep --options runtime --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Scrub"

ditto -c -k --keepParent "$APP" "$DIST/Scrub.zip"

STAGE="$BUILD/dmg"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Scrub.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Scrub" -srcfolder "$STAGE" -ov -format UDZO -fs APFS "$DIST/Scrub.dmg" >/dev/null

notary_args=()
if [[ -n "${SCRUB_NOTARY_PROFILE:-}" ]]; then
  notary_args=(--keychain-profile "$SCRUB_NOTARY_PROFILE")
elif [[ -n "${SCRUB_NOTARY_KEY:-}" && -n "${SCRUB_NOTARY_KEY_ID:-}" && -n "${SCRUB_NOTARY_ISSUER:-}" ]]; then
  notary_args=(--key "$SCRUB_NOTARY_KEY" --key-id "$SCRUB_NOTARY_KEY_ID" --issuer "$SCRUB_NOTARY_ISSUER")
fi
if (( ${#notary_args} )); then
  echo "› Notarizing the disk image"
  xcrun notarytool submit "$DIST/Scrub.dmg" "${notary_args[@]}" --wait
  xcrun stapler staple "$DIST/Scrub.dmg"
fi

(cd "$DIST" && shasum -a 256 Scrub.dmg Scrub.zip > SHA256SUMS.txt)
echo "Built Scrub $VERSION"
ls -lh "$DIST"
