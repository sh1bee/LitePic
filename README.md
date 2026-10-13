# LitePic — tài liệu kỹ thuật

Widget ảnh cho desktop macOS. Menu-bar app, AppKit thuần, **không dependency, không network, không chạm Finder**.

- Mã nguồn: `~/Downloads/code/LitePic`
- Bản chạy: `/Applications/LitePic.app`
- Ngôn ngữ: Swift 5, build bằng `swiftc` trực tiếp (không qua Xcode, không SPM)
- Quy mô: 2605 dòng app (13 file) + 314 dòng kiểm thử

---

## 1. Chạy thử

```bash
cd ~/Downloads/code/LitePic
./build.sh                       # tạo build/LitePic.app
pkill -x LitePic                 # tắt bản cũ (nếu đang chạy)
cp -R build/LitePic.app /Applications/
open /Applications/LitePic.app
```

Không có icon trên Dock (`LSUIElement` trong Info.plist). Icon nằm trên thanh menu.

---

## 2. Kiến trúc

```
                    ┌───────────────────────────────────────────┐
                    │             AppController                │
                    │  • NSApplicationDelegate                 │
                    │  • status item + menu                    │
                    │  • Timer đổi ảnh (tự hẹn lại)           │
                    │  • nhận file thả từ Finder              │
                    └──┬─────────┬─────────┬─────────┬─────────┘
                       │         │         │         │
        widget.show()  │         │         │         │  đọc/ghi
                       ▼         │         │         ▼
             ┌─────────────────┐ │         │   ┌──────────────┐
             │  WidgetWindow   │ │         │   │   Settings   │
             │  • cửa sổ       │ │         │   │ UserDefaults │
             │  • bóng, khung  │ │         │   └──────┬───────┘
             └──┬──────────┬───┘ │         │          │
                │          │     │         │          ▼
      ┌─────────▼───┐ ┌────▼──────────┐  ┌─▼────────────┐ ┌───────────┐
      │DraggableView│ │  GridOverlay  │  │ WidgetControls│ │ Bookmarks │
      │ (chuột phải,│ │  (ô lưới,     │  │  (3 nút ‹ › 📌)│ └───────────┘
      │  hover, thả │ │   toàn màn)   │  └──────────────┘
      │  file)      │ └────┬──────────┘
      └──────┬──────┘      │
             │ delegate    │ thuần toán, không AppKit
             ▼             ▼
      ┌────────────┐ ┌────────────┐   ┌─────────────────┐ ┌──────────────┐
      │DragSession │ │GridSnapper │   │  LaunchAtLogin  │ │FolderWatcher │
      │(vòng lặp   │ │(tính ô,    │   │ (LaunchAgent    │ │ (FSEvents)   │
      │ mouseDown) │ │ so khớp)   │   │  plist)         │ └──────┬───────┘
      └────────────┘ └────────────┘   └─────────────────┘        │
                            │                                     │
                            ▼                                     │
                    ┌──────────────┐                             │
                    │  ImageStore  │ ◄───────────────────────────┘
                    │ RAM LRU →    │   ảnh mới/xoá → dọn cache
                    │ đĩa → gốc    │
                    └──────────────┘
```

Không có dependency injection, không có protocol abstraction — mọi thứ là class cụ thể nối trực tiếp. Với quy mô này thì đơn giản hơn là trừu tượng hoá.

---

## 3. Từng file

### `main.swift` (12 dòng)
Điểm vào. Tạo `AppController`, đặt làm delegate, chạy run loop.

```swift
app.setActivationPolicy(.accessory)   // không Dock icon
```

### `AppController.swift` (589 dòng) — bộ não
Giữ toàn bộ logic ứng dụng:

| Phần | Nội dung |
|---|---|
| `applicationDidFinishLaunching` | dựng status item, theo dõi ngủ/tỉnh, nạp ảnh |
| `installStatusItem` / `buildMenu` | dựng menu (2 bản riêng: thanh menu + chuột phải) |
| `reload` | quét thư mục → danh sách ảnh, dọn cache, hiện ảnh đầu |
| `scheduleTimer` | hẹn đổi ảnh lần tới (timer **không lặp**, tự hẹn lại) |
| `advance` | chọn ảnh ngẫu nhiên, tránh lặp liên tiếp |
| `step` / `togglePin` | xử lý nút ‹ › 📌 |
| `watchScreenState` | `screensDidSleep` → huỷ timer; `screensDidWake` → đổi ảnh |
| `adoptDroppedFiles` | xử lý file thả từ Finder (thư mục → thêm; ảnh → thêm thư mục cha + ghim) |
| `startWatching` | ghép `FolderWatcher` với thư mục đang theo |

**Vì sao timer không lặp:** nếu dùng `repeats: true`, nhịp ngẫu nhiên sẽ thành nhịp cố định. Tự hẹn lại sau mỗi lần đổi thì ngẫu nhiên thật sự ngẫu nhiên.

### `WidgetWindow.swift` (759 dòng) — file lớn nhất, chứa 3 lớp

**a) `DraggableView: NSView`** (~90 dòng) — chỉ là lớp chuyển tiếp: nhận chuột của AppKit, giao thẳng cho `DragSession`, cộng phần `hitTest`, hover, menu chuột phải, và nhận file thả.

Điểm cốt lõi: `hitTest` trả về `self` cho mọi điểm trong biên, vì `NSImageView` phủ kín cửa sổ sẽ nuốt mọi sự kiện chuột.

**b) `GridOverlay`** — cửa sổ trong suốt phủ toàn màn hình, vẽ các ô lưới.

Mấu chốt lịch sử: `window.setFrame(display: false)` khiến lưới **không bao giờ hiện** — phải là `display: true` + `displayIfNeeded()`.

**c) `WidgetWindow`** — bọc cửa sổ, quản lý ảnh, kéo, bóng, khung.

`show(url:)` tách làm hai đường:
1. Ảnh còn trong RAM → hiện tức thì, đồng bộ.
2. Chưa có → `ImageStore.load` bất đồng bộ, có `showToken` để lần gọi mới hơn huỷ lần cũ (tránh ảnh về ngược thứ tự khi bấm ‹ › liên tục).

### `DragSession.swift` (147 dòng) — vòng lặp kéo

Toàn bộ một lần nhấn chuột, từ lúc nhấn xuống đến lúc thả, nằm trong **một hàm `begin(in:event:)`**. Nó tự chạy vòng lặp gọi `NSApp.nextEvent(until:inMode:)` thay vì để AppKit rải sự kiện ra nhiều handler.

Vì sao phải tự viết vòng lặp: vì `mouseUp` **luôn** được nhận kể cả khi thả chuột ra ngoài cửa sổ. Nếu rải ra `mouseDown` / `mouseDragged` / `mouseUp` rời rạc, một cú thả ngoài cửa sổ sẽ không gọi được `mouseUp` → widget kẹt trạng thái dở dang (lưới còn mà, widget phóng to kẹt, lần kéo sau khe sai chỗ). Đây là lỗi đã từng thật sự xảy ra.

Mốc thời gian của `DragSession`:

| Hằng | Giá trị | Việc |
|---|---|---|
| `hintDelay` | 0.25s | nhấc widget nhẹ — báo "đang giữ" |
| `holdDuration` | 1.2s | bật chế độ lưới (chưa kéo) |
| `moveThreshold` | 3pt | ngưỡng coi là "đã kéo" |
| `settleDuration` | 1.2s | **đã kéo xong, đứng yên** → bật lưới |

`settleDuration` là kết quả của một hiểu lầm: ban đầu chỉ hỗ trợ "giữ trước rồi kéo", người dùng muốn "kéo trước rồi đứng yên". Giờ cả hai đều chạy — `begin` đếm hạn `deadline` từ `t0` khi chưa kéo, và từ `lastMove` khi đã kéo.

Nhấp đúp kiểm **trước** vòng lặp, vì `mouseDown` thứ hai của một cú nhấp đúp vẫn mang `clickCount == 2` và sẽ rơi vào vòng kéo.

### `GridSnapper.swift` (73 dòng) — lưới thuần toán

Không đụng AppKit: nhận kích thước widget, kích thước màn hình, vị trí chuột → trả về danh sách ô và ô gần nhất. Tách riêng để so khớp được bằng phép thử.

Mô tả lưới: 6×4 ô tính theo kích thước widget, cộng 4 ô sát mép màn hình (chỗ hay chọn nhất).

### `LaunchAtLogin.swift` (94 dòng)
Ghi file LaunchAgent `~/Library/LaunchAgents/local.litepic.widget.plist`.

**Không dùng `SMAppService.mainApp`** — đã đo: nó từ chối app ký ad-hoc (`Operation not permitted`). Chỉ ghi plist, **không `bootstrap` ngay** để tránh hai instance tranh thanh menu; hiệu lực từ lần đăng nhập kế tiếp.

### `FolderWatcher.swift` (79 dòng) — FSEvents
Theo dõi thư mục ảnh, latency 2s, gom sự kiện trước khi báo.

**Không dùng `DispatchSource.makeFileSystemObjectSource`** — đã đo: trên Darwin nó chỉ bắt được **một phần** sự kiện, nên ảnh thêm/bớt bị lọt.

### `ImageStore.swift` (292 dòng) — đọc ảnh, 3 tầng

| Tầng | Tốc độ | Chi phí |
|---|---|---|
| RAM LRU (3 ảnh) | tức thì | ~4 MB |
| Đĩa cache (`~/Library/Caches/LitePic`) | ~5ms | ghi một lần |
| Ảnh gốc (4K) | 70–330ms | ngoài luồng chính |

Chi tiết đáng chú ý:
- **Giải mã ngoài luồng chính.** Ảnh gốc 3840×2160 mất 0.33s — làm trên luồng chính thì widget đứng hình nửa giây mỗi lần đổi ảnh.
- **Hàng đợi nối tiếp** (`decodeQueue`), không phải song song: hai ảnh 4K giải mã cùng lúc là 60 MB, một ảnh thì 10.
- **Bucket kích thước** `[512, 768, 1024, 1280, 1536, 2048, 3072, 4096]`, làm tròn lên. Bucket lớn phục vụ được bucket nhỏ hơn — quan trọng, nếu không mỗi lần hiện đều lỡ cache.
- **`kCGImageSourceShouldCacheImmediately: false`** — tắt bộ nhớ đệm của ImageIO, vì ta đã có cache riêng.
- **Khoá cache = SHA256(path + mtime + size)** — sửa ảnh gốc thì tự sinh cache mới.
- **`pruneCache`** xoá các bucket không còn dùng + trần 64 MB.

### `FrameStyle.swift` (143 dòng) — 5 kiểu khung

Mỗi kiểu trả về 4 số độc lập:

| Thuộc tính | Ý nghĩa |
|---|---|
| `inset` | bề dày khung tính từ mép ảnh ra |
| `pad` | khoảng hở mép khung ↔ mép cửa sổ = **chỗ cho bóng lan ra** |
| `shadowOpacity` | 0 khi "Không khung" |
| `imageCorner` | bo góc của ảnh |

Hai chỗ dễ sai đã sửa:
- Bóng phải ôm **mép ảnh**, không phải mép cửa sổ — nếu không "Không khung" vẫn thấy dải tối.
- Bo góc đường bóng phải **rộng hơn** bo góc ảnh (`+ blur × 0.75`), vì Gaussian lấn vào phần khuyết ở góc; bằng không bóng sẽ thành hình chữ nhật.

### `Settings.swift` (206 dòng)
Wrapper quanh `UserDefaults`, mỗi tuỳ chọn là một computed property có default. Danh sách thư mục là nguồn sự thật; bookmark chỉ dùng để sửa đường dẫn khi thư mục bị di chuyển.

Chứa thêm `FillMode` (vừa khung / cắt đầy khung, chỉ ở chế độ kích thước cứng) và `LevelMode`.

### `Bookmarks.swift` (82 dòng)
Bám theo thư mục khi nó bị move/rename.

Lưu ý: `.withSecurityScope` **chỉ hoạt động trong app sandbox**. LitePic cố tình không sandbox nên dùng option đó luôn thất bại — đã đo: `withSecurityScope` → FAIL, `minimalBookmark` → OK.

### `WidgetControls.swift` (76 dòng)
3 nút (‹ › 📌) hiện khi rê chuột vào widget, ẩn khi rời đi.

### `Diag.swift` (53 dòng)
Log chẩn đoán. `log()` nhận `@autoclosure` — khi tắt log thì biểu thức nội tuyến không được dựng, không tốn heap.

```bash
defaults write local.litepic.widget diag -bool true
tail -40 ~/Library/Logs/LitePic.log
```

---

## 4. Tuỳ chọn (UserDefaults `local.litepic.widget`)

| Khoá | Ý nghĩa | Mặc định |
|---|---|---|
| `folders` | danh sách thư mục ảnh | — |
| `litepic.folderBookmarks` | bookmark bám thư mục (sinh tự động) | — |
| `interval` | giây giữa hai lần đổi ảnh | 30 |
| `randomOn` | bật nhịp ngẫu nhiên | 0 |
| `minInterval` / `maxInterval` | khoảng ngẫu nhiên | 15 / 300 |
| `sizeMode` | 0 = theo ảnh, 1 = cống rộng, 2 = cứng | 0 |
| `maxEdge` | cạnh lớn nhất (chế độ 0) | 600 |
| `width` / `height` | kích thước (chế độ 1, 2) | 480 / 480 |
| `renderScale` | 1 = nhẹ, 2 = sắc nét | 2 |
| `opacity` | độ mờ 0.4–1.0 | 1 |
| `snapToGrid` | có tự khe vào lưới khi thả không | 1 |
| `frameStyle` | 0 không khung · 1 bóng · 2 polaroid · 3 phim · 4 kính | 1 |
| `fillMode` | 0 = vừa khung, 1 = cắt đầy khung (chỉ ở `sizeMode` 2) | 0 |
| `levelMode` | **0 = trên wallpaper, 1 = luôn nổi** | 1 |
| `changeOnWake` | đổi ảnh mỗi lần thức Mac | 0 |
| `pinned` | ảnh đang ghim (đường dẫn) | — |
| `posX` / `posY` | vị trí widget | góc trên phải |
| `diag` | bật log chẩn đoán | 0 |

Tên khoá đôi khi khác tên property — ví dụ property là `randomInterval` nhưng khoá là `randomOn`, property là `pinnedURL` nhưng khoá là `pinned`. Bảng trên liệt kê **khoá**, không phải tên property.

Tự chạy khi đăng nhập **không nằm trong UserDefaults** — trạng thái đọc từ chính file LaunchAgent, xem `LaunchAtLogin.swift`.


### ⚠ Về `levelMode`
`0` (trên wallpaper, dưới cửa sổ app) **gây ra triệu chứng "bấm widget không ăn, bị dính desktop"**: ở tầng đó mọi cú click đều rơi vào cửa sổ app phủ bên trên (tầng 0). Đây là hành vi đúng như widget macOS, nhưng khó chịu.

Mặc định là `1`. App còn có cơ chế **tự chữa** (`autoLiftIfOccluded`): nếu phát hiện có cửa sổ khác che widget thì tự nâng lên tầng nổi. Chỉ nâng, không tự hạ.

---

## 5. Tương tác kéo — thứ dễ hỏng nhất

| Thao tác | Kết quả |
|---|---|
| Bấm giữ yên 1.2s | lưới hiện, thả → khe vào ô gần nhất |
| **Kéo đi, dừng yên 1.2s** | **lưới hiện, thả → khe vào ô gần nhất** |
| Bật lưới trước, **rồi kéo** | widget hít theo ô, ô dưới chuột được tô sáng |
| Kéo và thả luôn | đặt tự do, không khe |
| Bấm rồi thả tại chỗ | không làm gì |
| Thả chuột **ra ngoài cửa sổ** | vẫn nhận `mouseUp`, widget không kẹt |
| Nhấp đúp | mở Finder tại ảnh hiện tại |
| Rê chuột vào | hiện 3 nút ‹ › 📌 |
| Chuột phải | menu đầy đủ |
| Thả **thư mục** từ Finder | thêm thư mục đó vào danh sách |
| Thả **ảnh** từ Finder | thêm thư mục cha của nó, rồi hiện + ghim ảnh đó |

Lưới: tối đa 6×4 ô tính theo kích thước widget, cộng 4 ô sát mép màn hình (chỗ hay chọn nhất). Kéo sang màn hình khác giữa chừng sẽ tính lại lưới cho màn đó.

**Chỗ dễ hiểu sai khi đo:** AppKit làm tròn góc cửa sổ ra số nguyên khi `setFrameOrigin`, nên một ô ở (526.75, 437.5) sẽ thành (527, 437). So vị trí tuyệt đối sẽ thấy "khe sai 0.9pt" trong khi thực ra khe đúng. Ngưỡng đúng là **≤ 1.5pt**.

### Kiểm thử kéo thật

Bộ test nằm ở `Tests/main.swift`, chạy bằng `./test.sh`.

7 tình huống — giữ 1.2s, kéo-rồi-dừng, kéo nhanh, bấm đơn, thả ngoài cửa sổ, nhấp đúp, bật lưới rồi kéo — mỗi tình huống tạo widget mới và kiểm toạ độ cuối so với ô lưới gần nhất. Phải chạy trên vòng lặp sự kiện thật (`NSApp.nextEvent`) với cửa sổ thật; gọi hàm nội bộ không cho kết quả có nghĩa.

**Bẫy đã mắc phải khi viết phép đo:** gán callback để quan sát sẽ **đè wiring của app** (`onDrop → finishDrop`, `onArmed → armSnapMode`), khiến `finishDrop` không bao giờ chạy. Phép đo vẫn "đạt" vì nó chỉ ghi lại đúng thứ mình tự ghi vào. Phải **bọc** callback (`let g = s.onDrop; s.onDrop = { g?($0); ... }`), không thay thế. Hai bẫy nữa liệt kê ở mục 7.

---

## 6. Hiệu năng (đo trên máy này)

| Trạng thái | Kết quả |
|---|---|
| Rảnh | CPU **gần như 0** — 27/28 mốc đọc được 0.0%, một mốc 0.1% (đúng lúc timer 60s đổi ảnh) |
| Rảnh — footprint | dao động **19.4 – 23.5 MB** (trung bình 22.1 MB), **không leo đều** |
| Số luồng | 4 |
| Đĩa cache ảnh | ~1 MB |
| Mở app lần đầu | 0.18s CPU (trước khi tối ưu: 1.25s) |
| Đổi ảnh (crossfade) | ~9 CPU ms mỗi lần |
| FSEvents khi thêm 1 ảnh | 0.0167% CPU trung bình sau đó |

**Footprint PHẢI đo lúc đã ấm, và phải đo NHIỀU mốc.**

Vừa mở app xong đọc được ~11 MB, rồi tăng dần. Đo một lần đầu rồi kết luận "chỉ 11MB" là sai. Nhưng đo vài lần rồi phán "nó phẳng 23.2MB" **cũng sai** — tôi đã từng viết như vậy, rồi đo tiếp 27 mốc và thấy nó dao động.

Đo thật 28 mốc trong ~10 phút, mỗi 20 giây:

```
nhỏ nhất 19.4M · lớn nhất 23.5M · trung bình 22.1M · biên độ 4.1M
```

Biên độ 4MB này **là hành vi đúng**: cache RAM của `ImageStore` là LRU 3 ảnh, giữ ảnh nào tuỳ thuộc timer chọn ảnh nào gần nhất. Ảnh 4K giải mã ~10MB một ảnh, nên giữ 2–3 ảnh là vài chục MB rồi nhả bớt. Đường đo đi thành **bậc thang** (23.2 → 23.5 → 21.5 → 19.4 → 21.5) đúng theo kiểu nhả-giữ của LRU; rò rỉ thật sẽ là một đường thẳng dốc lên.

**Dấu hiệu thật của rò rỉ là leo đều không dừng**, chứ không phải "có lúc tăng":

```bash
PID=$(pgrep -x LitePic)
for i in $(seq 1 27); do
  printf "%s  footprint=%s  cpu=%s%%\n" "$(date +%H:%M:%S)" \
    "$(vmmap -summary "$PID" | awk '/Physical footprint:/{print $3}')" \
    "$(ps -o %cpu= -p "$PID" | tr -d ' ')"
  sleep 20
done
```

Nếu các mốc tăng đều nhau (19 → 21 → 23 → 25 → …) thì mới là rò rỉ. Còn 19.4 → 23.2 → 23.2 → 19.4 → 21.5 là bình thường.

**Đo bằng `physical footprint`, không phải `ps rss`:**

```bash
vmmap -summary $(pgrep -x LitePic) | awk '/Physical footprint:/{print $3}'
```

RSS đếm cả phần dùng chung với WindowServer. Trong đợt tối ưu, chỉ số này từng làm tôi săn nhầm một "rò rỉ" không tồn tại — đã ghi trong `CHAT.MD`.

---

## 7. Nợ kỹ thuật còn lại

Đã gỡ xong trong đợt này: `snapMode` (ghi nhưng không bao giờ đọc), `debugHooks`, `settings.cornerRadius` (hai nguồn sự thật cho bo góc), `WidgetControls.show()/hide()` (không ai gọi), `settings.interactive` (không ai đọc), và `Diag.log` sót trong `mouseDown`. Việc tách file cũng đã xong: `DragSession.swift`, `GridSnapper.swift`, `LaunchAtLogin.swift`, `FolderWatcher.swift`. Bộ test kéo đã chuyển vào repo (`Tests/` + `test.sh`).

Còn lại:

| Vấn đề | Vị trí | Mức độ |
|---|---|---|
| `WidgetWindow.swift` còn 759 dòng (3 lớp) | `Sources/WidgetWindow.swift` | nên tách tiếp `ShadowStyler` |
| `build.sh` chỉ build app — phải chạy `test.sh` riêng | — | nên gộp thành một lệnh |

### Bộ test kéo — `./test.sh`

7 tình huống thật (A..G), mỗi tình huống tạo widget mới, kiểm toạ độ widget cuối so với ô lưới gần nhất:

| # | Tình huống | Kiểm |
|---|---|---|
| A | Kéo trước, dừng 1.2s | lưới bật, thả `.snap`, **widget nằm trên ô** |
| B | Giữ 1.2s không kéo | lưới bật, thả tại chỗ, vị trí không đổi |
| C | Kéo nhanh rồi thả (<1.2s) | `.free`, **không** bật lưới, widget đi theo chuột |
| D | Bấm đơn ngắn | `.click`, không đổi vị trí |
| E | Thả chuột **ra ngoài cửa sổ** | vẫn nhận `mouseUp`, `isPressed`/`isDragging` = false, overlay không kẹt |
| F | Nhấp đúp | gọi `onDoubleClick`, không rơi vào vòng kéo |
| G | Bật lưới trước, **rồi kéo** | có `onSnapDrag`, thả `.snap`, widget nằm trên ô |

`test.sh` phải **loại `Sources/main.swift`** khi biên dịch — file đó cũng có code cấp top-level (tạo `NSApplication` + `app.run()`), mà Swift chỉ cho phép một file top-level mỗi module.

Ba bẫy đã mắc phải khi viết bộ test này (ghi sẵn trong header của `Tests/main.swift`):

1. **Gán đè callback sẽ xoá wiring của app.** `s.onDrop = {...}` thay luôn `finishDrop`, nên phép đo chỉ ghi lại đúng thứ mình tự ghi vào — và vẫn "đạt". Phải **bọc** callback.
2. **So toạ độ tuyệt đối sẽ báo sai.** AppKit làm tròn góc cửa sổ ra số nguyên; ô ở (526.75, 437.5) thành (527, 437) — lệch 0.9pt mà khe vẫn đúng. Ngưỡng 1.5pt.
3. **Event sót chảy sang tình huống sau.** Nhấp đúp trả về sớm nên không ăn `mouseUp` đã post; sự kiện đó làm tình huống kế tiếp thành `.click` ngay lập tức. Phải `drain` hàng đợi trước mỗi tình huống.


---

## 8. Bài học đã ghi trong `CHAT.MD`

1. **`CGWindowListCopyWindowInfo` không đáng tin** với app phụ ở tầng desktop — trả sai toạ độ cả lúc hiện lúc ẩn. Phải dùng `screencapture -l<windowNumber>`.
2. **`ps rss` không phải bộ nhớ thật** — dùng `physical footprint`.
3. **Test phải chạy trên run loop thật.** Vòng lặp gọi hàm trực tiếp thiếu autorelease pool và cho kết quả ngược hẳn.
4. **Phải chụp màn hình thật** để xác minh thị giác — suy luận từ log thường sai.
5. **`.withSecurityScope` cần sandbox** — app không sandbox thì luôn FAIL.
6. **Chốt chỉ số đo trước khi tối ưu**, và đo lại cùng điều kiện sau khi sửa.
7. **Ghi đè callback để "quan sát" thì không đo được gì** — nó thay luôn wiring của app. Phải bọc callback.
8. **Đo footprint phải đo lúc đã ấm.** Mới mở app đọc ~11MB rồi tăng dần tới ~23MB và đứng yên — đó là cache nạp dần, không phải rò rỉ. Đo một mốc rồi kết luận là sai.
9. **`DispatchSource.makeFileSystemObjectSource` bắt thiếu sự kiện trên Darwin** — dùng FSEvents.
10. **`SMAppService` cần chữ ký Developer ID** — app ký ad-hoc thì dùng LaunchAgent plist.
11. **Ảnh không được render bằng `NSImageView.imageScaling`** — không có `aspectFill` đúng cách, và `contentsScale` Retina phải tự tính. Vẽ bằng `layer.contents`.
12. **Không được trộn `view.alphaValue` với `layer.opacity`** — crossfade phải animate `layer.opacity` bằng `CABasicAnimation` tường minh, hai lớp chồng nhau.

