#!/bin/bash
# Builds hdmi-defubar and wraps it into an app bundle. A real bundle is
# required for user notifications and launch-at-login registration.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/hdmi-defubar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/hdmi-defubar "$APP/Contents/MacOS/hdmi-defubar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>dk.ulrik.hdmi-defubar</string>
    <key>CFBundleName</key>
    <string>hdmi-defubar</string>
    <key>CFBundleExecutable</key>
    <string>hdmi-defubar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
echo "Install with: cp -R $APP /Applications/"
