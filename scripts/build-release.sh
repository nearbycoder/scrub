#!/bin/zsh
# Builds a universal, ad-hoc signed Scrub.app and packages it as dist/Scrub.dmg and dist/Scrub.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(grep 'MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')}"
BUILD="build/release"
DIST="dist"
APP="$BUILD/Build/Products/Release/Scrub.app"

command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

rm -rf "$DIST" && mkdir -p "$DIST"
xcodebuild -project Scrub.xcodeproj -scheme Scrub -configuration Release \
  -derivedDataPath "$BUILD" -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  -quiet clean build

[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

# Ad-hoc signature: no Apple Developer account required. Users clear quarantine once (see README).
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Scrub"

ditto -c -k --keepParent "$APP" "$DIST/Scrub.zip"

STAGE="$BUILD/dmg"
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Scrub" -srcfolder "$STAGE" -ov -format UDZO -fs APFS "$DIST/Scrub.dmg" >/dev/null

(cd "$DIST" && shasum -a 256 Scrub.dmg Scrub.zip > SHA256SUMS.txt)
echo "Built Scrub $VERSION"
ls -lh "$DIST"
