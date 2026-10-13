#!/bin/bash
# Bộ đo hiệu năng cho LitePic.
#
# Mục đích: mỗi thay đổi nhỏ (đổi cách vẽ, thêm một lớp, đổi công thức lưới)
# đều có thể làm app nặng thêm mà không ai nhận ra. Script này đo thật rồi so
# với một mốc đã lưu, nên hỏng hiệu năng thì thấy ngay thay vì đoán.
#
#   ./bench.sh save     đo rồi lưu thành mốc (mốc = hiện trạng tốt)
#   ./bench.sh check    đo rồi so với mốc — lỗi (thoát 1) nếu vượt ngưỡng
#   ./bench.sh run      chỉ đo, không so
#
# Ba bẫy khi đo (đã dính trong dự án này, đừng lặp lại):
#
#   1. `ps -o %cpu` KHÔNG phải mức dùng hiện tại — nó là trung bình cả đời
#      tiến trình. App chạy lâu thì số này nhạt dần đi và che mất việc CPU
#      tăng vọt. Ở đây đo bằng: (thời gian CPU tích luỹ t2-t1) / (giây thực).
#
#   2. Đo RAM đúng một lần là vô nghĩa. Lần đầu luôn cao hơn (Ảnh vừa giải mã),
#      rồi LRU nhả bớt. Phải đo lúc ấm và nhiều mốc, rồi báo cả đường hồi quy
#      (slope) — slope mới là thứ phát hiện rò rỉ, không phải đỉnh đơn lẻ.
#
#   3. Muốn nói "không đo được" thì phải nói ra. GPU cần quyền root cho
#      `powermetrics`; không có thì in "khong do duoc", đừng in số 0 rồi tưởng
#      là app không dùng GPU.

set -uo pipefail
cd "$(dirname "$0")"

APP="/Applications/LitePic.app/Contents/MacOS/LitePic"
BASE="bench/baseline.txt"
MODE="${1:-check}"

# Bao nhiêu phút đo RAM. Mặc định 3 — đủ để vài vòng đổi ảnh (chu kỳ 30s).
MINUTES="${BENCH_MINUTES:-3}"
# Ngưỡng cho phép vượt mốc (%). 15% RAM là nới rộng có chủ đích cho việc
# thỉnh thoảng; vượt là đáng nghi.
TOL_PCT="${BENCH_TOL:-15}"

die() { echo "LOI: $*" >&2; exit 2; }
[ -x "$APP" ] || die "khong thay $APP — hay ./build.sh roi cai app truoc"

# ---------------------------------------------------------------------------
# Cac tro giup do
# ---------------------------------------------------------------------------

# Thoi gian CPU tich luỹ (giây) cua tien trinh.
cpu_seconds() { ps -o time= -p "$1" 2>/dev/null | tr -d ' ' | awk -F: '{
    if (NF==3) print $1*3600 + $2*60 + $3;
    else if (NF==2) print $1*60 + $2;
    else print $1 + 0 }'; }

# Dung luong thuc su trong RAM. `ps rss` tinh theo kieu tinh khac voi thu mac
# thuong cua AppKit nen ra so nho/cao lung tung — dung physical footprint.
# Luu y: `vmmap` in kèm đuôi "M" (vd "20.7M") — phai bo di.
# GIU NGUYEN đơn vị gốc: `vmmap` có in "18.1M", "9724K", "1.2G" tuỳ lúc — đã dính
# lỗi này ở chính dự án này. Việc quy đổi đơn vị để ở phía Python.
footprint_raw() { vmmap -summary "$1" 2>/dev/null \
    | awk '/Physical footprint:/ && !/peak/{print $3; exit}'; }

# So cua so LitePic dang hien. Dung CGWindowList chu khong dung AppleScript:
# AppleScript can quyen Accessibility cho tung app, ma may hinh nguoi dung
# thuong khong cap — se bao loi thay vi tra so.
HELPER_DIR="$(mktemp -d)"
trap 'rm -rf "$HELPER_DIR"' EXIT
cat > "$HELPER_DIR/wins.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                   kCGNullWindowID) as? [[String: Any]] ?? []
print(l.filter { ($0[kCGWindowOwnerName as String] as? String) == "LitePic" }.count)
SWIFT
swiftc -O -o "$HELPER_DIR/wins" "$HELPER_DIR/wins.swift" 2>/dev/null || true

count_windows() { [ -x "$HELPER_DIR/wins" ] && "$HELPER_DIR/wins" || echo "-"; }

pid_of() { pgrep -x LitePic | head -1; }

median() { sort -n | awk '{a[NR]=$1} END {print (NR%2) ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2}'; }

# ---------------------------------------------------------------------------
# Do
# ---------------------------------------------------------------------------

echo "==> Do hieu nang LitePic (~${MINUTES} phut)..."
pid="$(pid_of)"
[ -n "$pid" ] || die "app chua chay"
echo "    pid=$pid"

# --- Thoi gian khoi dong: tu mo app den khi cua so widget xuat hien ---
echo "==> Do thoi gian khoi dong..."
( pkill -x LitePic 2>/dev/null; sleep 1 )
t0=$(python3 -c 'import time;print(time.time())')
open -a /Applications/LitePic.app
launch_s=""
for _ in $(seq 1 200); do
    p="$(pid_of)"; cw="$(count_windows)"
    if [ -n "$p" ] && [ "$cw" != "0" ] && [ "$cw" != "-" ]; then
        launch_s=$(python3 -c "import time;print(f'{time.time()-$t0:.2f}')")
        break
    fi
    sleep 0.05
done
pid="$(pid_of)"; [ -n "$pid" ] || die "app khong len sau khi mo"
[ -n "$launch_s" ] || launch_s="-"
# Cho app chạy 90s trước khi tính RAM. Con số này không phải tùy ý:
#
#   - 20s: đoán dở, ảnh chưa giải mã xong, cache LRU chưa đầy
#   - 45s: vẫn chưa đủ — đo ra min 9.7 / max 13.4, tức cả cửa sổ đo còn nằm trên
#           đoạn lên của warm-up
#   - 90s: đo thật cho thấy app phẳng 17.1MB suốt 7 phút không dứt
#
# Trên máy khởi động nhanh hơn thì con số này có thể giảm.
sleep 90

# --- RAM: nhieu moc theo thoi gian, co slope de bat ro ri ---
# Thu tu co y nghia: do RAM truoc, do CPU sau. App vua mo con lam viec nong
# (quet thu muc, giai ma anh, dung menu) — do CPU luc do ra con so cao gia lap.
# Do lai thuc te: app da chay 14 phut cho 0.12%, con o ngay sau khi mo 9.9%.
# Cau hoi dang hoi la "chay may con ton tai bao nhieu", nen phai do luc am.
echo "==> Do RAM trong ${MINUTES} phut (dong thoi app cung 'am' dan)..."
n=$((MINUTES * 4))
SAMPLES="$HELPER_DIR/samples.txt"; : > "$SAMPLES"
for i in $(seq 1 "$n"); do
    footprint_raw "$pid" >> "$SAMPLES"
    [ "$i" -lt "$n" ] && sleep 15
done
# Giao viec tinh cho Python: no doc mau tu file (chu nhung chuoi vao ma nguon
# — cach do khong chay khi mau rong).
ram_line=$(python3 - "$SAMPLES" <<'PY'
import sys
def to_mb(s):
    """`vmmap` in tung don vi tuy luc: 18.1M, 9724K, 1.2G. Chu hoa ve MB."""
    s = s.strip()
    k = 1.0
    if s.endswith("K") or s.endswith("k"): k, s = 1/1024, s[:-1]
    elif s.endswith("M") or s.endswith("m"): s = s[:-1]
    elif s.endswith("G") or s.endswith("g"): k, s = 1024, s[:-1]
    return float(s) * k
v = [to_mb(x) for x in open(sys.argv[1]).read().split() if x.strip()]
if not v:
    print("- - - -"); raise SystemExit
n = len(v)
# min/trung vị/max lấy trên TOÀN BỘ mẫu.
lo, med, hi = min(v), sorted(v)[n//2], max(v)
# Slope chỉ lấy phần ĐUÔI của đường mẫu — bỏ 25% đầu, vì đoạn đầu còn thuộc về
# warm-up (cache LRU đang đầy). Tính cả đường mẫu sẽ ra "rò rỉ" giả: app thật
# phẳng 17.1MB suốt 7 phút, nhưng đoạn lên 10.7 -> 25.4 làm slope ra cộng.
t = v[max(1, int(n * 0.25)):] if n >= 6 else v
m = len(t)
xs = list(range(m)); mx = sum(xs)/m; my = sum(t)/m
den = sum((x - mx) ** 2 for x in xs)
slope = (sum((x - mx) * (y - my) for x, y in zip(xs, t)) / den * 4) if den else 0.0
print(f"{lo:.1f} {med:.1f} {hi:.1f} {slope:+.2f}")
PY
)
read -r ram_min ram_med ram_max ram_slope <<< "$ram_line"

# --- CPU luc nghi, do bang chenh lech thoi gian CPU (diem 1 o tren) ---
echo "==> Do CPU luc nghi (60s, app da am)..."
c1=$(cpu_seconds "$pid"); w1=$(python3 -c 'import time;print(time.time())')
sleep 60
c2=$(cpu_seconds "$pid"); w2=$(python3 -c 'import time;print(time.time())')
cpu_idle=$(python3 -c "print(f'{100*($c2-$c1)/max(0.001,$w2-$w1):.3f}')" 2>/dev/null || echo "-")

threads=$(ps -M "$pid" 2>/dev/null | wc -l | tr -d ' ')
[ "$threads" = "1" ] && threads="-"
wins=$(count_windows)

# --- GPU: can root cho powermetrics. Khong co thi noi ro, khong doan. ---
gpu="khong do duoc (can sudo cho powermetrics)"
if sudo -n true 2>/dev/null; then
    g=$(sudo powermetrics --samplers gpu_power -i 3000 -n 1 2>/dev/null | awk '/GPU Power/{print $NF}')
    [ -n "$g" ] && gpu="$g"
fi

# --- Bao cao ---
echo
echo "metric                         value"
echo "cpu_idle_pct                   $cpu_idle"
echo "ram_footprint_mb_min           $ram_min"
echo "ram_footprint_mb_median        $ram_med"
echo "ram_footprint_mb_max           $ram_max"
echo "ram_slope_mb_per_min           $ram_slope"
echo "launch_to_window_s             $launch_s"
echo "threads                        $threads"
echo "windows                        $wins"
echo "gpu                            $gpu"
echo

snapshot() {
    echo "cpu_idle_pct=$cpu_idle"
    echo "ram_footprint_mb_min=$ram_min"
    echo "ram_footprint_mb_median=$ram_med"
    echo "ram_footprint_mb_max=$ram_max"
    echo "ram_slope_mb_per_min=$ram_slope"
    echo "launch_to_window_s=$launch_s"
}

case "$MODE" in
    run) snapshot ;;
    save)
        mkdir -p bench
        { echo "# Moc hieu nang — tao bang ./bench.sh save"
          echo "# So sanh bang ./bench.sh check (nguong ${TOL_PCT}%)"
          snapshot; } > "$BASE"
        echo "==> Da luu moc: $BASE" ;;
    check)
        [ -f "$BASE" ] || die "chua co moc. Chay: ./bench.sh save"
        now=$(mktemp); snapshot > "$now"
        python3 - "$BASE" "$now" "$TOL_PCT" <<'PY'
import sys
base_p, now_p, tol = sys.argv[1], sys.argv[2], float(sys.argv[3])
def load(p):
    d = {}
    for line in open(p):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line: continue
        k, v = line.split("=", 1)
        try: d[k] = float(v)
        except ValueError: pass
    return d
b, n = load(base_p), load(now_p)
bad, warn = [], []
# Chỉ những moc NAO DUNG de phan "dat/khong dat". Cac moc con lai chi de DOC:
# min/max no theo nha-giu cua LRU, slope nhac theo do dai cua cua so do — ca hai
# deu quay phien lung khi chang mot thu gi len. Phan tren chung se bao loi sai.
GATE = {"cpu_idle_pct", "ram_footprint_mb_median", "launch_to_window_s"}
print(f"{'metric':30}{'moc':>10}{'hien tai':>12}{'chenh %':>10}")
for k in b:
    if k not in n: continue
    old, cur = b[k], n[k]
    pct = 100 * (cur - old) / old if old else 0
    if k in GATE:
        # Hai chiều, nhung khac nhau:
        #   NANG HON  -> loi that, phai chan.
        #   NHE HON   -> KHONG chan, vi giam la tin vui. Nhung "nhac" lon la
        #                thuong dau hien app da hong (khong tai anh nua, hay do
        #                sai khac) chu khong phai toi uu hoa — nen phai noi ra
        #                chu khong bo qua im lang.
        if pct > tol:
            bad.append(k); mark = "LOI"
        elif pct < -tol:
            warn.append(k); mark = "NHAC"
        else:
            mark = "OK"
        print(f"{k:30}{old:>10.1f}{cur:>12.1f}{pct:>+9.1f}%  {mark}")
    else:
        print(f"{k:30}{old:>10.1f}{cur:>12.1f}{pct:>+9.1f}%  (chi de doc)")
    if k not in GATE and False: bad.append(k)
print()
if warn:
    print("NHAC — cac moc sau GIAM manh so voi moc. Thường là tin vui, nhưng "
          "cũng hay là app đã hỏng chứ không phải tối ưu hơn:")
    print("       " + ", ".join(warn))
if bad:
    print("LOI — vuot nguong tren cac moc: " + ", ".join(bad)); sys.exit(1)
print("OK — khong vuot nguong.")
PY
        rc=$?; rm -f "$now"; exit $rc ;;
    *) die "lenh khong hop le: $MODE (run | save | check)" ;;
esac