#!/bin/bash
set -e
cd "$(dirname "$0")/.."

echo "Building Words Hunter (release)..."
swift build -c release

APP_DIR="dist/Words Hunter.app/Contents"
MACOS_DIR="$APP_DIR/MacOS"

echo "Creating .app bundle..."
rm -rf "dist/Words Hunter.app"
mkdir -p "$MACOS_DIR"

cp ".build/release/WordsHunter" "$MACOS_DIR/Words Hunter"

cat > "$APP_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Words Hunter</string>
    <key>CFBundleDisplayName</key>
    <string>Words Hunter</string>
    <key>CFBundleIdentifier</key>
    <string>com.wordshunter.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Words Hunter</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Words Hunter needs Accessibility access to detect Option+double-click and copy selected text from any app.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "✓ Built: dist/Words Hunter.app"
echo "  Drag to /Applications to install."
