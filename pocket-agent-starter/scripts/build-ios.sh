#!/bin/bash
set -euo pipefail

# Run from the repository root on a Mac with Xcode and XcodeGen installed.
xcodebuild -version
xcodegen generate --spec project.json
xcodebuild \
  -project PocketAgent.xcodeproj \
  -scheme PocketAgent \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  build

app_path="build/Build/Products/Release-iphoneos/PocketAgent.app"
test -f "$app_path/Info.plist"
test -f "$app_path/PocketAgent"
mkdir -p build/package/Payload
ditto "$app_path" build/package/Payload/PocketAgent.app
(
  cd build/package
  /usr/bin/zip -qry ../PocketAgent.ipa Payload
)
echo "Created build/PocketAgent.ipa for signing in SideStore."
