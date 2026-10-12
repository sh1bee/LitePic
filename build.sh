#!/bin/bash
# Build LitePic.app hoàn toàn cục bộ — không tải bất kỳ dependency nào.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/LitePic.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "==> Bien dich Swift..."
swiftc -O -swift-version 5 \
  -o "$APP/Contents/MacOS/LitePic" \
  Sources/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LitePic</string>
  <key>CFBundleDisplayName</key><string>LitePic</string>
  <key>CFBundleIdentifier</key><string>local.litepic.widget</string>
  <key>CFBundleExecutable</key><string>LitePic</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ký ad-hoc: app build cục bộ không có thuộc tính quarantine,
# nhưng ký vẫn giúp binary là hợp lệ với hệ thống.
codesign --force --sign - "$APP" 2>/dev/null || echo "  (bo qua codesign)"

echo "==> Xong: $APP"