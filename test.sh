#!/bin/bash
# Biên dịch và chạy bộ kiểm thử kéo thật của LitePic.
#
# Khác build.sh ở chỗ: LOẠI Sources/main.swift, vì nó cũng có code cấp
# top-level (tạo NSApplication + app.run()) — Swift chỉ cho phép MỘT file
# top-level mỗi module. Tests/main.swift sẽ thay chỗ nó.
set -euo pipefail
cd "$(dirname "$0")"

OUT="${TMPDIR:-/tmp}/litepic-dragtest"
mkdir -p "$OUT"

# Lọc bớt main.swift của app.
SOURCES=()
for f in Sources/*.swift; do
  [ "$(basename "$f")" = "main.swift" ] && continue
  SOURCES+=("$f")
done

ARCH="$(uname -m)"
MIN_MACOS="13.0"

echo "==> Bien dich bo test keo ($ARCH-apple-macos$MIN_MACOS)..."
swiftc -O -swift-version 5 \
  -target "$ARCH-apple-macos$MIN_MACOS" \
  -o "$OUT/run" "${SOURCES[@]}" Tests/main.swift

echo "==> Chay..."
"$OUT/run"
