#!/bin/bash
# Build LitePic.app hoàn toàn cục bộ — không tải bất kỳ dependency nào.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/LitePic.app"

# Tắt bản đang chạy TRƯỚC khi build.
#
# Ghi chú cho đúng: trên macOS `rm -rf` vẫn xoá được nhị phân đang chạy (tiến
# trình giữ inode cũ), nên không có chuyện "xoá không sạch inode" hay "WindowServer
# giữ cache chữ ký". Cái thật sự gây hiểu nhầm là **bản đang chạy vẫn thực thi
# mã cũ** — build xong, `cp` sang /Applications, mở lên thấy y hệt bản trước,
# tưởng sửa không có tác dụng. Giết trước cho lần mở sau luôn là lần mở của
# mã vừa build.
pkill -x LitePic 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Ghim đúng phiên bản macOS thấp nhất mà app khai trong Info.plist
# (LSMinimumSystemVersion). Không có cờ này, swiftc lấy target theo máy đang
# build — build trên macOS 15 sẽ âm thầm sinh mã gọi API chỉ có ở 14/15, rồi
# app chết ngay trên máy người dùng đang chạy 13.0.
ARCH="$(uname -m)"
MIN_MACOS="13.0"

echo "==> Bien dich Swift ($ARCH-apple-macos$MIN_MACOS)..."
swiftc -O -swift-version 5 \
  -target "$ARCH-apple-macos$MIN_MACOS" \
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