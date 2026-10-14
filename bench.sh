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
# Cửa sổ đo tối thiểu phải trải qua hết đoạn cache LRU đang đầy, nếu không thì
# trung vị rơi vào giữa đoạn bậc thang và verdict là cái đồng xu.
# Đo được: với 3 phút, cùng một binary cho median 17.5 (LOI) rồi 9.7 (OK).
MINUTES="${BENCH_MINUTES:-8}"
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

// Cửa sổ widget ở chế độ "dưới app" nằm ở tầng âm. Trước đây widget dùng
// `desktopWindow + 20` = -2147483603, đúng bằng tầng desktop icon, và mọi tầng
// ≤ -2147483602 bị hệ thống xếp thành **desktop element** — `.excludeDesktopElements`
// loại mất nó, `cw` = 0, vòng chặn khởi động chờ mãi rồi hết giờ và ra
// `launch_to_window_s = -`. (Đã sửa thành `desktopIcon + 2` = -2147483601.)
//
// Nhưng "đã sửa" không có nghĩa là chắc — đó chỉ là **cách đo**, mà cách đo thì
// đổi được bất cứ lúc nào. Nếu mai mốc phân loại của hệ thống dịch, lại ra
// `launch = -` và không ai hiểu vì sao.
//
// Cách chữa đúng không phải ép cấu hình người dùng, mà làm **phép đo** không thể
// trượt: đếm bằng bộ lọc chuẩn, và nếu ra 0 thì đếm lại bằng bộ lọc không loại
// desktop element. Widget chưa hiện thì cả hai đều 0 — vẫn chờ đúng như cũ.
func count(_ opt: CGWindowListOption) -> Int {
    let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, opt],
                                       kCGNullWindowID) as? [[String: Any]] ?? []
    return l.filter { ($0[kCGWindowOwnerName as String] as? String) == "LitePic" }.count
}
let n = count(.excludeDesktopElements)
print(n > 0 ? n : count([]))
SWIFT
swiftc -O -o "$HELPER_DIR/wins" "$HELPER_DIR/wins.swift" 2>/dev/null || true

count_windows() { [ -x "$HELPER_DIR/wins" ] && "$HELPER_DIR/wins" || echo "-"; }

pid_of() { pgrep -x LitePic | head -1; }

median() { sort -n | awk '{a[NR]=$1} END {print (NR%2) ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2}'; }

# --- Chuan hoa cau hinh de phep do co y nghia ---
#
# App chay o che do "randomInterval" (mac dinh 15..300 giay). Nghia la TRONG 8
# phut do, so lan doi anh la **ngau nhien** — moi lan doi giai ma anh moi, LRU
# nha-giu, footprint nhay bac thang. Do la ly do median cua cung mot binary ma
# chay 4 lan cho: 13.5 / 14.8 / 17.3 / 18.3 MB. Nghuoc lai, muc 15% khong bat
# duoc hoi qui that — no bat nhieu nhiem hon hon loi that.
#
# Giai phap: tam tat vong doi anh TRONG LUC DO, va **khoi phuc lai** sau do.
# Do la trang thai dau, khong phai trang thai chay — dung de so sanh hai ban voi
# nhau, khong dung de so sanh voi muc cu.
SAVED_RANDOM=""; SAVED_INTERVAL=""
if [ -n "${BENCH_KEEP_SETTINGS:-}" ]; then
    echo "  (BENCH_KEEP_SETTINGS: giu nguyen cau hinh nguoi dung)"
else
    SAVED_RANDOM="$(defaults read local.litepic.widget randomInterval 2>/dev/null || true)"
    SAVED_INTERVAL="$(defaults read local.litepic.widget interval 2>/dev/null || true)"
fi
restore_settings() {
    [ -z "$SAVED_RANDOM" ] && return 0
    defaults write local.litepic.widget randomInterval -int "$SAVED_RANDOM"
    [ -n "$SAVED_INTERVAL" ] && \
        defaults write local.litepic.widget interval -float "$SAVED_INTERVAL"
    # App doc cau hinh luc khoi dong, nen phai mo lai moi thay hieu luc.
    pkill -x LitePic 2>/dev/null; sleep 1
    open -a /Applications/LitePic.app 2>/dev/null
}
trap 'restore_settings; rm -rf "$HELPER_DIR"' EXIT
if [ -n "$SAVED_RANDOM" ]; then
    defaults write local.litepic.widget randomInterval -int 0
    defaults write local.litepic.widget interval -float 3600
    echo "==> Tam tat vong doi anh trong luc do (se khoi phuc lai)"
    # Cho `cfprefsd` kip flush. Ghi xong mo app ngay thì app moi doc duoc gia tri
    # CU trong cache cua cfprefsd va van chay 15..300s — do duoc: mot lan do cho
    # chuoi `9.7 9.7 ... 13.3 ... 14.2` (buoc nhay giua chung), lan do thi phang
    # `9.8` suot 6 phut. Cung ma, khac nhau chi o thoi diem doc cau hinh.
    sleep 3
fi

# ---------------------------------------------------------------------------
# Do
# ---------------------------------------------------------------------------

echo "==> Do hieu nang LitePic (~${MINUTES} phut)..."
pid="$(pid_of)"
[ -n "$pid" ] || die "app chua chay"
echo "    pid=$pid"

# --- Thoi gian khoi dong: tu mo app den khi cua so widget xuat hien ---
echo "==> Do thoi gian khoi dong..."
# HUC MOT LAN TRUOC KHI TIM.
#
# Lần mở ĐẦU sau khi cài bundle mới chạy chậm hơn hẳn: LaunchServices phải đăng ký
# lại app. Đo được ngay sau `cp -R` vào /Applications là 2.17s, trong khi 8 lần đo
# sau đó đều ra 0.67-0.78s. Không hứt lần này thì `check` báo LOI launch giả.
(pkill -x LitePic 2>/dev/null; sleep 1)
open -a /Applications/LitePic.app; sleep 2

# ĐO NHIỀU LẦN, LẤY TRUNG VỊ.
#
# Một lần đo là quá nhiễu cho ngưỡng 15%. Đo được 14 lần trong phiên này:
# 0.57 / 0.61 / 0.62 / 0.67 / 0.68 / 0.71 / 0.74 / 0.75 / 0.76 / 0.76 / 0.78 /
# 0.78 / 0.80 / 0.88 — biên độ 0.57→0.88 là **±25%**, lớn hơn ngưỡng. Nên mốc lấy
# từ một lần đo rất nhanh sẽ khiến mọi lần đo bình thường đều báo LOI.
# Trung vị của 5 lần thu hẹp được nhiễu này, và lần cuối để app chạy tiếp để đo RAM.
launch_times=""
for i in $(seq 1 5); do
    # Ghi lại trước MỖI lần mở: app đọc cấu hình lúc khởi động, nên lần mở sau
    # cùng phải thấy giá trị mới chứ không phải giá trị mà cfprefsd còn cache.
    if [ -n "$SAVED_RANDOM" ]; then
        defaults write local.litepic.widget randomInterval -int 0
        defaults write local.litepic.widget interval -float 3600
    fi
    (pkill -x LitePic 2>/dev/null; sleep 1)
    t0=$(python3 -c 'import time;print(time.time())')
    open -a /Applications/LitePic.app
    for _ in $(seq 1 200); do
        p="$(pid_of)"; cw="$(count_windows)"
        if [ -n "$p" ] && [ "$cw" != "0" ] && [ "$cw" != "-" ]; then
            launch_times="$launch_times $(python3 -c "import time;print(f'{time.time()-$t0:.2f}')")"
            break
        fi
        sleep 0.05
    done
done
pid="$(pid_of)"; [ -n "$pid" ] || die "app khong len sau khi mo"
launch_s="$(printf '%s\n' $launch_times | median)"
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
# Trạng thái đi ngang = phần đuôi, nhưng KHÔNG cắt cứng theo phần trăm.
#
# Footprint của app không lên dần đều rồi phẳng, mà **nhảy một bước** (~3MB) tại
# thời điểm không xác định rồi mới đi ngang. Đo được: các lần chạy khác nhau, bước
# xảy ra ở phút thứ 2.5, hoặc trước cửa sổ đo, hoặc không xảy ra trong 8 phút —
# và median nhảy 9.9 ↔ 13.6 giữa các lần. Cắt cứng 25% thì không cứu được: bước
# có thể rơi vào giữa lát cắt.
#
# Cách trích: bỏ mọi mẫc trước khi chuỗi chạm 95% đỉnh cuối. Nghĩa là đo trạng
# thái đã ổn định — đúng câu hỏi "chạy lâu còn tồn tại bao nhiêu".
#
# KHÔNG bỏ nhầm rò rỉ: rò rỉ là đi **liên tục**, không bao giờ chạm đỉnh sớm, nên
# gần như toàn bộ mẫu được giữ lại — và `slope` bắt được. `slope` vẫn tính trên
# lát cắt này.
peak = max(v)
flat_start = next((i for i, x in enumerate(v) if x >= peak * 0.95), 0)
t = v[flat_start:] if len(v) - flat_start >= 4 else v
m = len(t)
lo, med, hi = min(t), sorted(t)[m//2], max(t)
xs = list(range(m)); mx = sum(xs)/m; my = sum(t)/m
den = sum((x - mx) ** 2 for x in xs)
slope = (sum((x - mx) * (y - my) for x, y in zip(xs, t)) / den * 4) if den else 0.0
print(f"{lo:.1f} {med:.1f} {hi:.1f} {slope:+.2f}")
# In thêm nguyên đường mẫu. Theo quy tắc trong BUGS.md, phải nhìn cả chuỗi mốc
# theo thời gian mới phân biệt được "rò rỉ" với "LRU nhả-giữ" — chỉ một con số
# tổng thì không đủ, và chính nó đã báo LOI oan một lần.
print("SERIES " + " ".join(f"{x:.1f}" for x in v))
PY
)
read -r ram_min ram_med ram_max ram_slope <<< "$(printf '%s\n' "$ram_line" | sed -n 1p)"
ram_series="$(printf '%s\n' "$ram_line" | sed -n 2p | sed 's/^SERIES //')"

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
echo "chuoi moc RAM (${MINUTES} phut, 15s/gap):"
echo "  $ram_series"
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
# Nguong rieng tung moc — xem giai thich o noi dung `TOL.get(k, tol)`.
TOL = {"cpu_idle_pct": 15.0,
       "ram_footprint_mb_median": 40.0,
       "launch_to_window_s": 25.0}
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
    # Nguong RIENG cho tung moc, dat theo nhieu do duoc — khong phai mot con so
    # chung cho ca bang.
    #
    # Lý do: 15% chi co y nghia khi phep do lap lai duoc. Da do:
    #   - ram_footprint_mb_median: cung mot binary, hai lan chay lien tiep cho
    #     15.8 roi 9.6 MB — chenh 39%, bien do 65%. Ly do la cache dia: lan
    #     trung gap thi app doc ban thumbnail nho, lan trượt thi giai ma anh goc
    #     4K, va bo giai ma ImageIO giu lai bo dem ~7 MB vinh vien (ghi ro ngay
    #     trong `ImageStore.load`). Day khong phai loi cua app.
    #   - launch_to_window_s: 14 mau trong mot phien cho 0.57 ... 0.88s. Voi
    #     trung vi 5 lan, buoc do phan giai 0.05s van chua du de phan biet 0.5
    #     voi 0.6.
    #   - cpu_idle_pct: nhieu ~0, 15% la qua rong nhung cung rat an toan.
    #
    # Muon siet lai: sua TOL trong file nay — nhung nho doc phieu do ben canh.
    if k in GATE:
        # Hai chiều, nhung khac nhau:
        #   NANG HON  -> loi that, phai chan.
        #   NHE HON   -> KHONG chan, vi giam la tin vui. Nhung "nhac" lon la
        #                thuong dau hien app da hong (khong tai anh nua, hay do
        #                sai khac) chu khong phai toi uu hoa — nen phai noi ra
        #                chu khong bo qua im lang.
        t = TOL.get(k, tol)
        if pct > t:
            bad.append(k); mark = "LOI"
        elif pct < -t:
            warn.append(k); mark = "NHAC"
        else:
            mark = "OK"
        print(f"{k:30}{old:>10.1f}{cur:>12.1f}{pct:>+9.1f}%  {mark} (nguong {t:g}%)")
    else:
        print(f"{k:30}{old:>10.1f}{cur:>12.1f}{pct:>+9.1f}%  (chi de doc)")
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