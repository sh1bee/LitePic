# LitePic — tài liệu kỹ thuật

Widget ảnh cho desktop macOS. Menu-bar app, AppKit thuần, **không dependency, không network, không chạm Finder**.

- Mã nguồn: `~/Downloads/code/LitePic`
- Bản chạy: `/Applications/LitePic.app`
- Ngôn ngữ: Swift 5, build bằng `swiftc` trực tiếp (không qua Xcode, không SPM)
- Quy mô: ~2100 dòng / 9 file Swift

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
                    ┌──────────────────────────────┐
                    │        AppController          │
                    │  • NSApplicationDelegate     │
                    │  • status item + menu         │
                    │  • Timer đổi ảnh              │
                    │  • danh sách ảnh, chọn ảnh    │
                    └───────┬──────────────┬───────┘
                            │              │
              gọi widget.show(url)         │ đọc/ghi tuỳ chọn
                            │              ▼
                    ┌───────▼──────────┐  ┌──────────────┐
                    │   WidgetWindow   │  │   Settings   │
                    │  • cửa sổ widget │  │ UserDefaults │
                    │  • kéo + lưới    │  └──────┬───────┘
                    │  • bóng, khung   │         │
                    └───────┬──────────┘         │
                            │                    │
              ┌─────────────┼──────────┐         │
              ▼             ▼          ▼         ▼
     ┌──────────────┐ ┌───────────┐ ┌──────────┐ ┌───────────┐
     │DraggableView │ │GridOverlay│ │WidgetCtl │ │ Bookmarks │
     │ (kéo, hover) │ │ (ô lưới)  │ │ (3 nút)  │ └───────────┘
     └──────────────┘ └───────────┘ └──────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │  ImageStore  │  RAM LRU → đĩa cache → ảnh gốc
                    └──────────────┘
```

Không có dependency injection, không có protocol abstraction — mọi thứ là class cụ thể nối trực tiếp. Với quy mô này thì đơn giản hơn là trừu tượng hoá.

---

## 3. Từng file

### `main.swift` (13 dòng)
Điểm vào. Tạo `AppController`, đặt làm delegate, chạy run loop.

```swift
app.setActivationPolicy(.accessory)   // không Dock icon
```

### `AppController.swift` (462 dòng) — bộ não
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

**Vì sao timer không lặp:** nếu dùng `repeats: true`, nhịp ngẫu nhiên sẽ thành nhịp cố định. Tự hẹn lại sau mỗi lần đổi thì ngẫu nhiên thật sự ngẫu nhiên.

### `WidgetWindow.swift` (761 dòng) — file lớn nhất, chứa 3 lớp

**a) `DraggableView: NSView`** — nhận chuột, xử lý kéo.

Điểm cốt lõi: `hitTest` trả về `self` cho mọi điểm trong biên, vì `NSImageView` phủ kín cửa sổ sẽ nuốt mọi sự kiện chuột.

Toàn bộ một lần nhấn được xử lý trong **vòng lặp bên trong `mouseDown`**, gọi `NSApp.nextEvent(until:inMode:)` thay vì dùng `sendEvent`. Lý do: `mouseUp` luôn được nhận kể cả khi thả ra ngoài cửa sổ — nếu không, widget dễ kẹt trạng thái dở dang (lưới còn mà, widget phóng to kẹt).

Bốn mốc thời gian:

| Mốc | Giá trị | Việc |
|---|---|---|
| `hintDelay` | 0.25s | nhấc widget 1.04× — báo "đang giữ" |
| `holdDuration` | 1.2s | bật chế độ lưới (chưa kéo) |
| `moveThreshold` | 3pt | ngưỡng coi là "đã kéo" |
| `settleDuration` | 1.2s | **đã kéo xong, đứng yên** → bật lưới |

`settleDuration` là kết quả của một hiểu lầm: ban đầu chỉ hỗ trợ "giữ trước rồi kéo", người dùng muốn "kéo trước rồi đứng yên". Giờ cả hai đều chạy.

**b) `GridOverlay`** — cửa sổ trong suốt phủ toàn màn hình, vẽ các ô lưới.

Mấu chốt lịch sử: `window.setFrame(display: false)` khiến lưới **không bao giờ hiện** — phải là `display: true` + `displayIfNeeded()`.

**c) `WidgetWindow`** — bọc cửa sổ, quản lý ảnh, kéo, bóng, khung.

`show(url:)` tách làm hai đường:
1. Ảnh còn trong RAM → hiện tức thì, đồng bộ.
2. Chưa có → `ImageStore.load` bất đồng bộ, có `showToken` để lần gọi mới hơn huỷ lần cũ (tránh ảnh về ngược thứ tự khi bấm ‹ › liên tục).

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

### `Settings.swift` (197 dòng)
Wrapper quanh `UserDefaults`, mỗi tuỳ chọn là một computed property có default. Danh sách thư mục là nguồn sự thật; bookmark chỉ dùng để sửa đường dẫn khi thư mục bị di chuyển.

### `Bookmarks.swift` (82 dòng)
Bám theo thư mục khi nó bị move/rename.

Lưu ý: `.withSecurityScope` **chỉ hoạt động trong app sandbox**. LitePic cố tình không sandbox nên dùng option đó luôn thất bại — đã đo: `withSecurityScope` → FAIL, `minimalBookmark` → OK.

### `WidgetControls.swift` (79 dòng)
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
| `randomInterval` | bật nhịp ngẫu nhiên | 0 |
| `minInterval` / `maxInterval` | khoảng ngẫu nhiên | 15 / 300 |
| `sizeMode` | 0 = theo ảnh, 1 = cống rộng, 2 = cứng | 0 |
| `maxEdge` | cạnh lớn nhất (chế độ 0) | 600 |
| `width` / `height` | kích thước (chế độ 1, 2) | 480 / 480 |
| `renderScale` | 1 = nhẹ, 2 = sắc nét | 2 |
| `opacity` | độ mờ 0.4–1.0 | 1 |
| `frameStyle` | 0 không khung · 1 bóng · 2 polaroid · 3 phim · 4 kính | 1 |
| `levelMode` | **0 = trên wallpaper, 1 = luôn nổi** | 1 |
| `snapToGrid` | có tự khe vào lưới khi thả không | 1 |
| `posX` / `posY` | vị trí widget | góc trên phải |
| `pinnedURL` | ảnh đang ghim | — |
| `changeOnWake` | đổi ảnh mỗi lần thức Mac | 0 |
| `diag` | bật log chẩn đoán | 0 |

### ⚠ Về `levelMode`
`0` (trên wallpaper, dưới cửa sổ app) **gây ra triệu chứng "bấm widget không ăn, bị dính desktop"**: ở tầng đó mọi cú click đều rơi vào cửa sổ app phủ bên trên (tầng 0). Đây là hành vi đúng như widget macOS, nhưng khó chịu.

Mặc định là `1`. App còn có cơ chế **tự chữa** (`autoLiftIfOccluded`): nếu phát hiện có cửa sổ khác che widget thì tự nâng lên tầng nổi. Chỉ nâng, không tự hạ.

---

## 5. Tương tác kéo — thứ dễ hỏng nhất

| Thao tác | Kết quả |
|---|---|
| Bấm giữ yên 1.2s | lưới hiện, thả → khe vào ô gần nhất |
| **Kéo đi, dừng yên 1.2s** | **lưới hiện, thả → khe vào ô gần nhất** |
| Kéo và thả luôn | đặt tự do, không khe |
| Bấm rồi thả tại chỗ | không làm gì |
| Rê chuột vào | hiện 3 nút ‹ › 📌 |
| Chuột phải | menu đầy đủ |

Lưới: tối đa 6×4 ô tính theo kích thước widget, cộng 4 ô sát mép màn hình (chỗ hay chọn nhất). Kéo sang màn hình khác giữa chừng sẽ tính lại lưới cho màn đó.

---

## 6. Hiệu năng (đo trên máy này)

| Trạng thái | Kết quả |
|---|---|
| Rảnh (không đổi ảnh) | **0.0000% CPU**, footprint phẳng 19 MB |
| Đổi ảnh mỗi 15s | footprint đi ngang 16–25 MB |
| 43 ảnh, 5 phút | 1.97s CPU tổng (≈0.12% trung bình) |
| Số luồng | 4 |
| Mở app lần đầu | 0.18s CPU (trước khi tối ưu: 1.25s) |

**Đo bằng `physical footprint`, không phải `ps rss`:**

```bash
vmmap -summary $(pgrep -x LitePic) | awk '/Physical footprint:/{print $3}'
```

RSS đếm cả phần dùng chung với WindowServer. Trong đợt tối ưu, chỉ số này từng làm tôi săn nhầm một "rò rỉ" không tồn tại — đã ghi trong `CHAT.MD`.

---

## 7. Nợ kỹ thuật còn lại

| Vấn đề | Vị trí | Mức độ |
|---|---|---|
| `snapMode` được ghi nhưng không bao giờ đọc | `WidgetWindow.swift:335` | vô hại, nên gỡ |
| `debugHooks` còn sót từ lúc debug | `WidgetWindow.swift:36` | nên gỡ |
| `Diag.log` còn trong `mouseDown` | `WidgetWindow.swift:122-190` | tốn 0 nhờ autoclosure, nhưng nên gỡ |
| `settings.cornerRadius` chỉ còn dùng cho góc ô lưới | `WidgetWindow.swift:699,714` | widget giờ dùng `frameStyle.imageCorner` — hai nguồn sự thật |
| `WidgetControls.show()/hide()` không ai gọi | `WidgetControls.swift:74-75` | vô hại |
| `WidgetWindow.swift` 761 dòng | — | nên tách `DragHandler` / `ShadowStyler` |
| **Chưa tự chạy khi đăng nhập** | — | mỗi lần bật Mac phải mở tay |

---

## 8. Bài học đã ghi trong `CHAT.MD`

1. **`CGWindowListCopyWindowInfo` không đáng tin** với app phụ ở tầng desktop — trả sai toạ độ cả lúc hiện lúc ẩn. Phải dùng `screencapture -l<windowNumber>`.
2. **`ps rss` không phải bộ nhớ thật** — dùng `physical footprint`.
3. **Test phải chạy trên run loop thật.** Vòng lặp gọi hàm trực tiếp thiếu autorelease pool và cho kết quả ngược hẳn.
4. **Phải chụp màn hình thật** để xác minh thị giác — suy luận từ log thường sai.
5. **`.withSecurityScope` cần sandbox** — app không sandbox thì luôn FAIL.
6. **Chốt chỉ số đo trước khi tối ưu**, và đo lại cùng điều kiện sau khi sửa.
