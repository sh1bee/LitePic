# LitePic — tài liệu kỹ thuật

Widget ảnh cho desktop macOS. Menu-bar app, AppKit thuần, **không dependency, không network, không chạm Finder**.

- Mã nguồn: `~/Downloads/code/LitePic`
- Bản chạy: `/Applications/LitePic.app`
- Ngôn ngữ: Swift 5, build bằng `swiftc` trực tiếp (không qua Xcode, không SPM)
- Quy mô: 11 file Swift (~2800 dòng), kiến trúc tối giản

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
Sau khi mở, click vào biểu tượng menu bar hoặc click vào widget để chọn thư mục ảnh hoặc kéo thả ảnh trực tiếp vào widget.

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

### Cửa sổ lớn hơn ảnh một chút — có chủ đích

```
┌─ cửa sổ ────────────────────────┐   viền trong suốt (liftRoom, 4%)
│                                  │
│   ┌──────────────────────────┐   │
│   │                          │   │   ┌─ ImageCanvas ────────────┐
│   │       vùng ảnh           │   │   │ tự vẽ ảnh trong draw(_:)  │
│   │      (KHÔNG phải khung)   │   │   │ • vừa khung / phủ kín    │
│   │                          │   │   │ • bo góc tự cắt         │
│   └──────────────────────────┘   │   │ • Retina: AppKit tự lo   │
│                                  │   └───────────────────────────┘
└──────────────────────────────────┘
```

Hai lý do, chung một hệ quả:

1. **Chỗ cho lúc widget "nâng" lên.** Giữ chuột thì `lift()` scale 1.06. Ảnh áp
   sát mép cửa sổ thì phần tràn ra bị cắt, ba góc thành vuông. Chừa viền trong
   suốt thì cả bốn góc còn nằm trong cửa sổ.
2. **Chỗ cho bóng đổ** (kiểu khung có bóng) — có sẵn từ trước, gọi là `pad`.

Vì cửa sổ lớn hơn ảnh, **lưới khe bám `imageSize` / `imageOrigin`, không bám
`window.frame`** — người dùng nhìn thấy và nhắm vào ảnh, không phải khung cửa sổ.

Đổi `liftRoom` thì phải chừa đủ cho `1.06`: mép ảnh dịch ra
`3% × khoảng cách từ tâm`, mà khoảng cách đó **tính cả phần đang chừa** — tức
cần `≥ 3.2% × cỡ ảnh`. Chừa thiếu thì góc lại vuông.

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

Điểm cốt lõi: `hitTest` trả về `self` cho mọi điểm trong biên, vì `ImageCanvas` phủ kín cửa sổ sẽ nuốt mọi sự kiện chuột.

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

### `GridSnapper.swift` (83 dòng) — lưới thuần toán

Không đụng AppKit: nhậc kích thước widget, kích thước màn hình, vị trí chuột → trả về danh sách ô và ô gần nhất. Tách riêng để so khớp được bằng phép thử.

**Ô đè lên nhau một nửa:** bước nhảy bằng `nửa cỡ widget`, nên đặt lệch được nửa ô — nhiều chọn hơn hẳn lưới thưa. Cộng 4 ô sát mép màn hình (chỗ hay chọn nhất).

Trên màn 1920×1175 với widget 360×203: **16 ô → 81 ô** (9×9). Có trần **240 ô**; widget nhỏ trên màn lớn thì giãn bước nhảy cho tới khi vừa, thay vì vẽ hàng trăm lớp chồng lên nhau.

Mỗi ô đúng bằng kích thước **ảnh**, lấy lúc giơ lưới — widget đổi ảnh (đổi tỉ lệ) thì ô bám theo.

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

---

## 6. Hiệu năng thực tế

Các chỉ số tài nguyên đo đạc thực tế trên macOS:

| Trạng thái | Kết quả |
|---|---|
| Rảnh (đo lúc đã ấm) | CPU **0.00 – 0.03%** |
| Rảnh — footprint | **9.6 – 15.8 MB**, phẳng trong mỗi lần đo |
| Rành giữa hai lần chạy | dao động do trúng/trượt cache đĩa, không phải rò |
| Rò rỉ | **không có** — `slope = +0.00` |
| Số luồng | 4 |
| Mở app → có cửa sổ | 0.8s (trung vị của 5 lần) |
| Đổi ảnh (crossfade) | ~9 CPU ms mỗi lần |

**Không rò rỉ — và cách chứng minh.** Tổng và `slope` không phân biệt nổi "rò rỉ"
với "LRU nhả-giữ". Phải nhìn **hình dạng đường đo**. Đo 8 phút, 32 mốc:

```
19.4 19.4 19.4 20.5 17.1 17.1 17.1 17.1 ... 17.1    ← phẳng tuyệt đối 7+ phút
```

Rò rỉ thật sẽ là đường thẳng dốc lên không dừng. Đây là đường phẳng.

**Warm-up phải đủ 90 giây — đo sớm hơn sẽ ra số sai.** Đo lúc 20s, cả cửa sổ đo
còn nằm trên đoạn lên lúc cache LRU đang đầy, và `slope` ra **cộng** dù app
không dính gì. Đó chính là lý do một lần đo 10 phút báo `+1.03 MB/phút` trong
khi app thực tế phẳng. Khi đo đạc cần chờ 90s và bỏ 25% đầu khi tính slope.

**Đo CPU sai chỗ sẽ ra số hoang đường.** Đo ngay sau khi mở app cho
`9.9%` — đó là lúc app đang quét thư mục và giải mã ảnh, không phải mức chạy
nền. Cùng app đó, đã chạy 14 phút, cho `0.12%`. Thứ tự chuẩn: **đo RAM
trước cho app ấm, rồi mới đo CPU**.

**`ps -o %cpu` không phải mức dùng hiện tại** — nó là trung bình cả đời tiến
trình. App chạy lâu thì số nhạt dần và che mất lúc CPU tăng vọt. Đúng phải là:

```bash
# CPU trung bình trong một khoảng thời gian
PID=$(pgrep -x LitePic)
a=$(ps -o time= -p $PID); sleep 60; b=$(ps -o time= -p $PID)   # giây CPU
```

**Footprint PHẢI đo lúc đã ấm, nhiều mốc, và có đường hồi quy.**

Vừa mở app xong đọc được ~9.6 MB, rồi tăng dần. Đo một lần đầu rồi kết luận
"chỉ 9.6MB" là sai. Biên độ vài MB là **hành vi đúng**: cache RAM của
`ImageStore` là LRU 3 ảnh, ảnh 4K giải mã ~10 MB một ảnh, nên giữ 2–3 ảnh rồi
nhả bớt. **Dấu hiệu thật của rò rỉ là leo đều không dừng** (19 → 21 → 23 → 25),
đường thẳng dốc lên — còn nhấp nhô kiểu bậc thang thì là LRU bình thường.

Vì vậy bộ đo báo thêm **slope** (hệ số hồi quy MB/phút): con số đó mới là thứ
phân biệt rò rỉ với nhả-giữ.

**Đo bằng `physical footprint`, không phải `ps rss`:**

```bash
vmmap -summary $(pgrep -x LitePic) | awk '/Physical footprint:/ && !/peak/{print $3}'
```

RSS đếm cả phần dùng chung với WindowServer. Trong đợt tối ưu, chỉ số này từng
dễ gây hiểu nhầm về một "rò rỉ" không tồn tại.

Lưu ý khi đọc `vmmap`: nó có **hai dòng** khớp `Physical footprint` (dòng hai
là `(peak)`), và **in tùy lúc** `18.1M`, `9724K` hay `1.2G`, cần lưu ý khi đọc dữ liệu.

**GPU:** Cần quyền `powermetrics` (chạy với sudo) để đo chi tiết nếu cần.

---

## 7. Nợ kỹ thuật còn lại

Đã hoàn thành tối ưu: loại bỏ cờ dư thừa, thống nhất nguồn sự thật cho bo góc, tối ưu `DragSession`, tách module độc lập (`DragSession.swift`, `GridSnapper.swift`, `LaunchAtLogin.swift`, `FolderWatcher.swift`), thêm màn hình hướng dẫn rỗng trực quan, điều hướng cử chỉ vuốt 2 ngón trackpad, và cơ chế tiết kiệm năng lượng khi bị che khuất.

Còn lại:

| Hạng mục cải tiến | Vị trí | Định hướng |
|---|---|---|
| Tiếp tục module hoá các view phụ | `Sources/WidgetWindow.swift` | Tách thêm `ShadowStyler` nếu mở rộng tính năng |
| Bo góc của kiểu khung trang trí (polaroid/kính) dùng `masksToBounds` | `Sources/FrameStyle.swift` | Tinh chỉnh bo góc theo đường path vẽ vector |

---

## 8. Bài học kỹ thuật cốt lõi

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
11. **Ảnh không được render bằng `NSImageView`, cũng không đặt tay `layer.contents`.** `imageScaling` không có `aspectFill` đúng cách; mà `layer.contents` đặt tay thì AppKit sở hữu và **xoá sạch** mỗi lần vẽ lại — widget mất trắng khi giữ chuột. Nay tự vẽ trong `ImageCanvas.draw(_:)`: tự tính vỉa cắt, tự bo góc, Retina do AppKit lo.
12. **Không được trộn `view.alphaValue` với `layer.opacity`** — crossfade phải animate `layer.opacity` bằng `CABasicAnimation` tường minh, hai lớp chồng nhau.

