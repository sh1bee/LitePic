# Bảng tra cứu lỗi — đọc TRƯỚC khi sửa

Cách dùng: gặp triệu chứng → tra bảng → đọc mục "Nhận ra" và "Đo thế nào".
Mỗi mục đều có **phép đo cụ thể đã chạy được**, không phải mô tả miệng.

## Mục lục

| # | Triệu chứng | Chỗ |
|---|---|---|
| 1 | Widget trống khi giữ chuột | `layer.contents` bị AppKit xoá |
| 2 | Ba góc vuông khi giữ | `anchorPoint` + cửa sổ bằng đúng cỡ ảnh |
| 3 | Bốn bẫy khi đo AppKit | mục tra cứu |
| 4 | Đo hiệu năng | `./bench.sh` |
| 5 | Chế độ "dưới app" — widget biến mất khỏi danh sách cửa sổ | tầng cửa sổ âm |
| 6 | **Crash** khi bấm ‹ ›, và khi đang ghim ảnh | `images[-1]` — **hai** chỗ |
| 7 | Kéo thả vào ô, khởi động thì lệch ô | `settle()` bỏ qua `imageInset` |
| 8 | Nút ‹ › 📌 tràn ra ngoài ảnh | `WidgetControls.place` |
| 9 | Răng cưa phim dồn cụm giữa ảnh | trục Y **+** hệ toạ độ con |
| 10 | Tranh chấp luồng khi thư mục đổi | FSEvents trên luồng phụ |
| 11 | Ảnh chụp dọc bị méo | EXIF `Orientation` bị bỏ qua |
| 12 | Widget mờ 25% lúc chuyển ảnh | hai lớp cùng mờ |

Mục 6, 9 và 12 đều có **hai nguyên nhân chồng nhau** — sửa một chưa đủ.

---

## 1. Widget biến mất khi giữ chuột (đã sửa)

**Triệu chứng.** Giữ widget → lưới hiện → widget trống. Cửa sổ vẫn còn, vẫn bấm
và chuột phải được, `CGWindowList` báo `onScreen=1, alpha=1.00`. Chỉ tới lúc
**đổi ảnh** nó mới hiện lại.

**Nhận ra.** Ảnh được vẽ bằng `layer.contents` **đặt tay** lên `NSImageView`.
Ô nhớ đó do AppKit sở hữu: mỗi lần AppKit vẽ lại view, `draw()` của
`NSImageView` chạy với không có `image` và **xoá sạch `contents`**. Đổi transform
của lớp cha thì đủ để kích hoạt lần vẽ đó — mà `lift()` làm đúng việc đó ở khoảnh
khắc bấm giữ.

**Đo thế nào (không đoán).** Đo trực tiếp `contents` chứ không đo pixel: pixel
chỉ nói *có/không*, `contents` nói *tại sao*.

```swift
let contents = imageView.layer?.contents != nil   // trước, trong và sau khi giữ
```

Cô lập từng bước bằng cách gọi callback của app một cách riêng lẻ (không cần
chuột thật):

```swift
view.session.onHint?()      // -> holdHint()  -> lift(1.04)   <- thu pham
view.session.onArmed?()     // -> armSnapMode()-> lift(1.06) + overlay
view.session.onDrop?(.click)// -> finishDrop() -> overlay.hide + lift(1.0)
```

**Cách sửa.** Thay `NSImageView` bằng `ImageCanvas` — `NSView` tự vẽ ảnh trong
`draw(_:)`. AppKit vẽ lại bao nhiêu lần thì ảnh vẫn còn. Bài học chung:

> **Đừng đặt tay vào `layer.contents` của view AppKit quản lý.** Ô nhớ đó của
> AppKit, AppKit xoá tuỳ ý. Muốn giữ thì phải tự vẽ trong `draw(_:)`.

**Bẫy đo đã dính (đáng nhớ nhất).** Tôi thử 3 kỹ thuật đặt transform và kết
luận "CABasicAnimation là cách an toàn". **Sai** — cả ba đều làm mất ảnh, nhưng
vì thứ tự thử đã làm sai lệch (sau khi ảnh mất thì `setContents` hồi lại được).
Chỉ khi đổi kiến trúc mới thấy cả bốn cách đều "giữ được". Đừng kết luận từ
phép thử có tham số bị nhiễm.

---

## 2. Ba góc vuông khi giữ, chỉ góc dưới-trái còn bo (đã sửa)

**Triệu chứng.** Lúc widget "nâng" lên (giữ chuột), ảnh bị cắt vuông ở ba góc.

**Nhận ra — hai nguyên nhân chồng nhau:**

1. **Cửa sổ đúng bằng kích thước ảnh.** `layout()` đặt `contentSize` khớp ảnh,
   nên khi scale 1.06, ảnh tràn ra ngoài mép cửa sổ và bị cắt.
2. **AppKit đặt `anchorPoint = (0,0)` cho view** (không phải `0.5,0.5` mặc định).
   Phép scale quanh góc dưới-trái nên **góc đó đứng yên**, ba góc kia bị đẩy ra
   ngoài — đúng bất đối xứng người dùng mô tả.

**Đo thế nào.** Dùng **ảnh xanh đặc** (ảnh thật có chi tiết nên không đo được),
rồi đếm pixel "nền lộ" ở mỗi góc:

```
Ảnh xanh đặc, bán kính 20pt = 40px ở ảnh 2x, đếm trong vùng 40×40 ở mỗi góc:
  bo tròn  -> có pixel nền lộ ra (vùng khuyết của hình tròn)
  vuông    -> toàn màu ảnh tới sát mép
```

Kết quả đo (bản cũ): `trên-trái 20.3% | trên-phải 20.2% | dưới-trái 20.2% |
dưới-phải 20.2%` → giữ: `0.0 | 0.0 | 22.7 | 0.0` = **1/4 bo tròn**.

**Cách sửa.**
- Chuyển `container.layer.anchorPoint` sang tâm (widget nâng lên từ chính giữa —
  vừa đúng nghĩa, vừa giảm một nửa chỗ trống phải chừa).
- Chừa viền trong suốt trong cửa sổ (`liftRoom`), đủ cho lúc nâng lên.
  **Chỗ chừa phải `≥ 3.2% × cỡ ảnh`**, không phải 1.5%: vì chỗ chừa *cũng bị
  scale theo*, nên khoảng cách từ tâm tới mép ảnh lớn hơn bạn tưởng.
- Bo góc vẽ tay trong `ImageCanvas.draw(_:)` thay vì `layer.cornerRadius` +
  `masksToBounds` — cùng nguyên tắc với mục 1.

**Hệ quả phải xử lý.** Cửa sổ giờ lớn hơn ảnh ~8%, nên **lưới phải bám ảnh**
(`imageSize`), không bám `window.frame.size`; khi khe phải dịch cửa sổ lùi lại
đúng phần viền. Dùng `imageOrigin` / `imageInset`.

---

## 3. Đo gì cho đúng (bốn bẫy đã dính)

| Bẫy | Sai lầm | Cách đúng |
|---|---|---|
| `ps -o %cpu` | Là **trung bình cả đời tiến trình**, không phải mức dùng hiện tại. App chạy lâu thì số nhạt dần, che mất CPU tăng vọt | `(t_CPU2 − t_CPU1) / Δgiây` × 100 |
| Đo RAM đúng một lần | Lần đầu luôn cao (ảnh vừa giải mã), rồi LRU nhả bớt | Đo **lúc ấm**, nhiều mốc; báo cả **slope** (hồi quy) — slope mới bắt rò rỉ |
| So toạ độ tuyệt đối | AppKit làm tròn góc cửa sổ ra số nguyên: lệch tới `√(0.75²+0.5²) ≈ 0.9pt` | Ngưỡng **≤ 1.5pt** |
| Event sót | Nhấp đúp trả về sớm, `mouseUp` đã post còn sót → tình huống sau nhận nhầm, ra `.click` | `drain` hàng đợi trước mỗi tình huống |

Hai bẫy nữa, không thuộc về đo số:

- **Bọc callback khi đo.** `s.onDrop = { gDrop?(r); /* đo */ }` — gán đè sẽ xoá
  wiring của app, phép đo trả về đúng những gì nó tự ghi vào.
- **"Đã hồi phục" có thể chỉ là tai nạn thời gian.** Tấm ảnh "sau khi thả" cho ra
  widget đã hiện lại — hoá ra trùng đúng lúc app đổi ảnh (chu kỳ 15s). Phải nhìn
  cả trạng thái *trước* khi tạo ra nó.

---

## 4. Đo hiệu năng — dùng `./bench.sh`, đừng đo tay

```bash
./bench.sh run     # chỉ đo
./bench.sh save    # đo rồi lưu thành mốc (làm khi app đang ở trạng thái tốt)
./bench.sh check   # đo rồi so với mốc — lỗi (thoát 1) nếu vượt ngưỡng 15%
```

Mỗi thay đổi nhỏ (đổi cách vẽ, thêm một lớp, đổi công thức lưới) nên chạy
`check` trước khi commit. Nếu vượt, đã biết ngay thứ vừa làm nặng thêm.

### Bộ đo phải "ổn định" trước khi nó đáng tin

Một `check` báo LOI thì **không đủ** để kết luận app nặng lên — phải hỏi ngược lại:
số đó có thật không, hay chính bộ đo đang nhiễu. Ở đây đã dính đúng một vụ, và nó
dẫn tới ba sửa trong chính `bench.sh`:

**1. Đo lúc app đang đổi ảnh thì con số là cái đồng xu.** Cấu hình mặc định của
app là `randomInterval` = ngẫu nhiên **15–300 giây** (khoá `interval` cố định bị
bỏ qua hoàn toàn khi bật random). Trong 8 phút đo, số lần đổi ảnh là ngẫu nhiên,
mỗi lần giải mã ảnh mới → LRU nhả-giữ → footprint nhảy bậc thang.

```
cùng một binary, cùng 8 phút, 4 lần chạy:
  median 9.9 / 13.5 / 14.2 / 15.3 MB      ← tất cả đều "đúng", không có binary nào khác
```

Cách chữa: **tạm tắt vòng đổi ảnh trong lúc đo, và khôi phục lại sau đó** (biến
`SAVED_RANDOM`/`SAVED_INTERVAL` + `trap`). Đây là trạng thái *đầu*, dùng để so hai
bản với nhau — không phải trạng thái *chạy*, nên đừng so mốc này với cảm nhận
thường ngày. Muốn giữ nguyên cấu hình thì chạy với `BENCH_KEEP_SETTINGS=1`.

**2. `cfprefsd` cache, nên ghi xong phải chờ.** Ghi `defaults` rồi mở app ngay thì
app đọc **giá trị cũ** trong cache của `cfprefsd` và vẫn chạy 15–300s. Cùng mã,
cùng phép đo, kết quả `9.7 … 13.3 … 14.2` (có bước nhảy) ở lần này và `9.8` phẳng
suốt 6 phút ở lần kế — khác nhau **chỉ ở thời điểm đọc cấu hình**. Vì vậy `bench.sh`
ghi lại trước *mỗi* lần mở và nghỉ 3s sau lần ghi đầu.

**3. Một lần đo launch quá nhiễu cho ngưỡng 15%.** 14 lần đo trong một phiên:
`0.57 / 0.61 / 0.62 / 0.67 / 0.68 / 0.71 / 0.74 / 0.75 / 0.76 / 0.76 / 0.78 /
0.78 / 0.80 / 0.88` — biên độ **±25%**, lớn hơn ngưỡng. Mốc lấy từ một lần rất
nhanh thì mọi lần đo bình thường đều LOI. Nay đo **5 lần, lấy trung vị**.
Riêng lần mở **đầu tiên sau khi cài** còn chậm hơn nữa (LaunchServices phải đăng
ký lại): đo được `2.17s` ngay sau `cp -R` vào `/Applications`. `bench.sh` hứt một
lần trước khi bắt đầu đo.

### Cách trích "trạng thái đi ngang"

Footprint **không lên đều rồi phẳng**, mà **nhảy một bước** (~3MB) tại thời điểm
không xác định rồi mới đi ngang — cửa sổ đo có thể rơi vào trước hoặc sau bước đó.
Cắt cứng "bỏ 25% đầu" không cứu được, vì bước có thể rơi vào giữa lát cắt.

Cách dùng hiện tại: **bỏ mọi mẫc trước khi chuỗi chạm 95% đỉnh cuối**. Đây là
trạng thái đã ổn định — đúng câu hỏi "chạy lâu còn tồn tại bao nhiêu".

Nó **không** bỏ sót rò rỉ: rò rỉ đi *liên tục*, không bao giờ chạm đỉnh sớm, nên
gần như toàn bộ mẫu được giữ lại và `slope` bắt được.

### Khi nào tin được phép đo, khi nào phải đo A/B

Nếu `check` báo LOI ở **RAM hoặc launch**, hãy chạy lại trước. Còn muốn so **hai
bản build**, đừng so hai lần `check` rời rạc — hãy **xoay vòng A/B với cùng một
cửa sổ**:

```bash
./ab.sh truoc <app-bản-cũ> 20     # mỗi bản một lần, 20 mốc, cùng điều kiện
./ab.sh sau   <app-bản-mới> 20
```

Chính tôi đã kết luận sai ở đây: một vòng cho thấy bản mới leo tới 21.2 MB còn
bản cũ phẳng 14.8 — tưởng 7 sửa đổi gây hồi quy. Lặp lại thì **cả hai** đều leo
tới ~19–20. Chỉ khi lặp lại mới biết cái nào là nhiễu.

**Kết luận sau khi sửa bộ đo: KHÔNG rò rỉ, và KHÔNG hồi quy.** Đo 8 phút, 32 mốc,
biến động 0.1 MB:

```
9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8
9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8
slope = +0.00
```

Về **7 lỗi đã sửa**: A/B hai lần, mỗi bản 20 mốc, cùng cửa sổ — `truoc`
(1b53191) và `sau` (168bdec) cho median lần lượt 14.8/13.5 và 17.3/13.7, tức
**không phân biệt được**, nằm trong biên độ nhiễu. Cùng kết luận cho `build.sh`
`-target`: bản cũ `minos 15.0` median 13.6, bản mới `minos 13.0` median 12.4.

**Nhưng `build.sh` từng build ra `minos 15.0` trong khi `Info.plist` khai
`LSMinimumSystemVersion = 13.0`** — app sẽ không chạy trên macOS 13/14 dù tự khai
là chạy được. Nay đã ghim `-target`. Đây là lỗi thật, không phải chuyện thẩm mỹ.

Mỗi lần đo lại bộ đo đã dính và tự sửa các lỗi sau — đừng viết lại từ đầu:

- `ps -o %cpu` sai ý nghĩa → dùng chênh lệch thời gian CPU.
- Đo CPU **ngay sau khi mở app** ra `9.9%` — đó là lúc quét thư mục và giải mã ảnh,
  không phải mức chạy nền. Cùng app đó, đã chạy 14 phút, cho `0.12%`.
  **Đo RAM cho app ấm trước, rồi mới đo CPU.**
- **Warm-up phải đủ 90s.** Đo lúc 20s, cửa sổ đo còn nằm trên đoạn lên của
  cache LRU và `slope` ra **cộng giả** — một lần đo 10 phút báo `+1.03 MB/phút`
  trong khi app phẳng tuyệt đối. Đây là loại số sai nguy hiểm nhất: trông rất
  "có vấn đề" nhưng thật ra là phép đo sai.
- `vmmap` in **tùy lúc** `18.1M`, `9724K`, `1.2G` — quy đổi để ở Python.
- `vmmap` có **hai dòng** khớp `Physical footprint` (dòng thứ hai là `(peak)`).
- `AppleScript` đếm cửa sổ cần quyền Accessibility → dùng `CGWindowList`.

**Tổng và `slope` không phân biệt được "rò rỉ" với "LRU nhả-giữ".** Muốn kết
luận thì phải nhìn **chuỗi mốc theo thời gian** (xem `bench/baseline.txt` và lệnh
mẫu ở `README.md` mục 6), đừng chỉ nhìn một con số tổng.

**GPU không đo được nếu không có `sudo`** cho `powermetrics`. Bộ đo in thẳng
`khong do duoc` chứ không in số 0 — số 0 sẽ khiến người đọc tưởng app không dùng
GPU. Cần đo thì chạy khi có `sudo`.
---

# Vòng 2 — sáu lỗi mới (đều đã sửa và đã đo)

## 5. Chế độ "dưới app": widget bị hệ thống xếp thành *desktop element*

**Triệu chứng.** Bấm "hiển thị dưới app" → widget vẫn hiện, nhưng **biến mất khỏi
mọi công cụ liệt kê cửa sổ** dùng bộ lọc chuẩn.

**Nhận ra.** Code cũ dùng `CGWindowLevelForKey(.desktopWindow) + 20`. Trên máy này:

```
kCGDesktopWindowLevel     = -2147483623
kCGDesktopIconWindowLevel = -2147483603   ← +20 ra ĐÚNG bằng số này
kCGMinimumWindowLevel     = -2147483643
kCGNormalWindowLevel      =          0
```

Tức widget nằm **trùng tầng desktop icon**. Ngưỡng thật không nằm ở con số khai
báo mà phải dò: bước dần tầng lên và xem cửa sổ còn trong danh sách không.

| Tầng | `CGWindowList` (bộ lọc chuẩn) |
|---|---|
| ≤ −2147483602 | **mất** — bị xếp thành desktop element |
| ≥ −2147483601 | còn |

**Đo thế nào (đã chạy).** Dò 14 mức tầng, mỗi mức đợi 0.35s rồi tra
`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` xem
cửa sổ còn không. Trên app đang chạy: trước khi sửa widget chỉ hiện ở lần liệt
kèm desktop elements; sau khi sửa hiện ở **cả hai** lần liệt.

**Cách sửa.** `desktopIcon + 2` — mức thấp nhất còn là cửa sổ bình thường, vẫn nằm
dưới mọi cửa sổ app (0). Bài học:

> **Số "+20" trông hợp lý thì vẫn sai.** Ở đây nó trùng đúng một mốc hệ thống.
> Với tầng cửa sổ, phải **đo ngưỡng thật**, không suy từ tên hằng số.

---

## 6. Crash `images[-1]` — có **hai** chỗ, một chỗ dễ kích hoạt hơn hẳn

**Triệu chứng.** Bấm ‹ › ngay lúc mở app → crash văng.

**Nhận ra.** `lastIndex` khởi tạo `-1`, và `reload()` đặt lại `-1` mỗi lần quét
lại thư mục. Hai chỗ đọc `images[lastIndex]` mà không chặn:

1. `step(_:)` — đúng như báo cáo.
2. **`showPinnedIfNeeded()` — không nằm trong báo cáo, và dễ trúng hơn nhiều.**
   `reload()` → `advance()` → `if isPinned { showPinnedIfNeeded() }`. Nghĩa là
   **chỉ cần ghim một ảnh rồi có bất kỳ lần quét lại nào là crash**, không cần
   bấm gì. Đây là lý do dễ gặp hơn, dù báo cáo chỉ nêu `step()`.

**Đo thế nào (đã chạy, không suy luận).** Tái hiện trên app thật:

```bash
defaults write local.litepic.widget pinnedURL -string "<đường dẫn ảnh trong thư mục>"
open -a LitePic.app        # bản cũ: chết ngay
```

Báo cáo crash xác nhận đúng chỗ:

```
EXC_BAD_INSTRUCTION — Illegal instruction: 4
  AppController.showPinnedIfNeeded()
```

Sau khi sửa: cùng kịch bản đó, app sống.

**Cách sửa.** `images.indices.contains(lastIndex)` trước mọi lần lấy phần tử.
Dòng 455 (`togglePin`) vốn đã có chặn sẵn — nên cái sai là **hai chỗ sót**, không
phải thiếu hoàn toàn. Khi săn lỗi index, đừng dừng ở chỗ đầu tiên tìm ra.

---

## 7. `settle()` lệch ô lưới — chỉ lệch lúc khởi động, không lệch lúc kéo thả

**Nhận ra.** `finishDrop()` đã được sửa để bám **ảnh** (`imageOrigin`), nhưng
`settle()` vẫn dùng `window.frame.origin` và `setFrameOrigin(activeSlots[i])` —
quên `imageInset`.

**Đo thế nào (đã chạy).** Dời widget lệch chỗ, gọi `settle()`, đo khoảng cách từ
`imageOrigin` tới ô gần nhất:

```
cách cũ (window.frame.origin) : lệch 17.00pt
cách mới (imageOrigin)        : lệch  0.61pt   ← ngưỡng làm tròn AppKit 1.5pt
```

**Cách sửa.** `settle()` y hệt `finishDrop()`: neo theo ô rồi lùi cửa sổ lại
đúng `imageInset`.

---

## 8. Cụm nút ‹ › 📌 rơi ra ngoài ảnh

**Nhận ra — hai lỗi cộng dồn trong một dòng:**

```swift
origin = CGPoint(x: offset.x - w - gap, y: offset.y + size.height - w - gap)
```

`offset.y` đã là toạ độ tính từ đáy, lại cộng thêm `size.height` → cụm nút rơi
xuống tầm **hai lần chiều cao ảnh**, tức ngoài màn hình. Và chỉ lùi `side + gap`
(32pt) trong khi cụm rộng `26×3 + 6×2 = 90pt` → thò ra ngoài mép phải 50pt.

**Đo thế nào (đã chạy).** So khung cụm nút với khung ảnh thật:

```
cụm nút ngang [276..366]  ⊂  ảnh [14..374]
cụm nút dọc  [177..203]  ⊂  ảnh [8..211]
điểm neo (276,177) — nằm trong container, không bay ra ngoài
bề rộng 90pt = đúng 3 nút + 2 khe
```

**Cách sửa.** Bỏ hẳn việc tự tính `origin`: `place(atTopRightOf: imageView.frame)`
— dán theo khung **thật** của ảnh.

---

## 9. Răng cưa phim 35mm — **hai** lỗi chồng lên nhau, sửa một chỉ thấy một

**Triệu chứng.** 28 lỗ chấm dồn thành một cụm ngang ở giữa ảnh.

**Lỗi 1 (đã thấy).** Trục Y đứng yên: `y: r.midY - 8`, cả hai bên lại tăng theo
trục X → cụm ngang.

**Lỗi 2 (chỉ lộ ra khi sửa xong lỗi 1).** Răng là **subview của `bg`**, nên khung
của nó phải tính trong `bg.bounds`. Code lấy `r.minX`/`r.maxX` — toạ độ của
`container` — nên **mọi lỗ bị dịch đúng bằng `bg.origin`** và trượt ra ngoài dải
phim, lên thành viền trong suốt.

**Đo thế nào (đã chạy).** Đo bằng cả cây view lẫn pixel thật:

```
toạ độ view (đã quy về view gốc):  trái x=26..38,  phải x=418..430
nền phim:                          x=22..434          → cả hai cột đều TRONG nền
phân tích pixel ảnh chụp (2x):     11 hàng trang mỗi bên,
                                    y = 56,103,149,…,520 (đều tăm 23pt),
                                    0 vệt trắng ngoài dải
```

**Cách sửa.** Toàn bộ hình học lấy từ `bg.frame`; x = `margin` hoặc
`bg.frame.width − margin − toothW`; y rải đều theo `k * step`.

> **Sửa lỗi hiển thị đôi khi làm lộ lỗi toạ độ đã ẩn.** Hai lỗi này cùng nằm ở
> một khối 6 dòng; nếu chỉ nhìn "lỗ chấm dồn cụm" thì sửa xong vẫn còn lỗi kia.

**Bẫy đo liên quan.** Bản sửa đầu tiên của tôi theo đúng công thức đề xuất
(`x = r.minX − 18` / `r.maxX + 6`) đặt răng **ngoài dải phim**. Số đo cây view đã
bắt được (`trong nền? KHONG`) — nhìn ảnh thì dễ tưởng ổn.

---

## 10. Data race: FSEvents gọi callback trên luồng phụ

**Nhận ra.** `FSEventStreamSetDispatchQueue(s, queue)` đưa callback về luồng phụ,
nhưng `onChange` lại đụng `rescanPending`/`rescanScheduled` của AppController —
hai biến main thread cũng đọc/ghi.

**Đo thế nào (đã chạy).** Bọc callback ghi `Thread.isMainThread` vào ô có khoá,
chạm một file trong thư mục đang theo dõi, chờ nhận:

```
✓ có nhận FolderWatcher
✓ callback chạy trên MAIN
```

**Cách sửa.** `DispatchQueue.main.async { self_.onChange?() }` — cả vì race, vì
AppKit cũng không an toàn khi bị gọi sai luồng.

---

## 11. Ảnh dọc có cờ EXIF bị méo tỉ lệ khung

**Nhận ra.** `pixelSize(of:)` đọc `PixelWidth/PixelHeight` — kích thước **thô** của
file. Ảnh chụp dọc từ điện thoại vẫn lưu ngang (4032×3024). Nhưng `decodeThumbnail`
bật `kCGImageSourceCreateThumbnailWithTransform: true` nên ảnh thật sự được xoay
về dọc. Khung cửa sổ bám khổ ngang, ảnh bên trong dọc → méo hoặc thừa lề đen.

**Đo thế nào (đã chạy).** Tự tạo một JPEG có `Orientation = 6` rồi đối chiếu ba
đường đo:

```
file thô 800×600, orientation=6
  pixelSize sau khi sửa   : 600×800
  ảnh app thực sự giải mã  : 600×800   → tỉ lệ khớp
```

Trước khi sửa, `pixelSize` trả `800×600` còn ảnh là `600×800` — lệch tỉ lệ.

**Cách sửa.** Xét `kCGImagePropertyOrientation`; giá trị `5...8` là xoay 90°/270°
nên đổi hai cạnh.

---

## 12. Widget mờ 25% giữa lúc chuyển ảnh

**Nhận ra.** `crossfade` chạy đồng thời `under: 0→1` và `over: 1→0`. Giữa chừng
cả hai đều ở 0.5, tổng độ đục là `1 − (1−0,5)(1−0,5)` = **0,75**.

**Đo thế nào (đã chạy).** Không cần chụp màn hình — đo trực tiếp hai lớp. Tổng độ
đục của hai lớp chồng nhau **chính là** `1 − (1−a)(1−b)`; lấy mẫu `presentation()`
của cả hai mỗi 4ms suốt lúc chuyển:

```
92 mẫu, độ đục thấp nhất = 1.0000   (cách cũ: 0.750)
```

**Cách sửa — có điều kiện mà mô tả ban đầu chưa nói.** Chỉ mờ *một* lớp: đặt lớp
nhận ảnh mới ở 1.0 **tức thì, không animate**, rồi mờ lớp cũ. Nhưng thứ tự view là
`imageView` → `topView`, nên lớp nhận ảnh mới **bắt buộc phải nằm dưới** — nếu nó
ở trên và bật đục tức thì thành cắt hình chứ không chuyển mềm. Vì vậy sau mỗi lần
chuyển phải đưa lớp đang hiện lên trên, để lần sau lớp trống nằm ở dưới.

---

# Bẫy đo mới của vòng này

Bốn cái này làm tôi **kết luận sai trước khi sửa phép đo**:

| Bẫy | Sai lầm | Cách đúng |
|---|---|---|
| Hàm generic ở top-level `main.swift` | `func mir<T>(...)` rồi gọi `mir<NSView>(...)` → *"cannot explicitly specialize global function"*. Trùng tên với hàm global sẵn có cũng báo vậy | Trả `Any?`, ép kiểu ở nơi gọi |
| `Mirror` không thấy thuộc tính **tính** | `imageInset`/`imageOrigin` là `var` có body → `Mirror` trả nil, tôi tưởng app sai | Tính lại từ khung thật: cửa sổ → container → ảnh |
| `s2.frame` của **châu** | Răng là subview của nền nền; lấy `frame` thô là toạ độ **của cha**, tôi kết luận "nằm trong nền" rồi hoá ra sai | `s2.convert(s2.bounds, to: viewGốc)` |
| Chặn main thread chờ callback | `ImageStore.load` bắn completion qua `DispatchQueue.main.async`; `semaphore.wait` ở main → **deadlock**, đo ra ảnh `0×0` và tôi tưởng app giải mã hỏng | Để vòng lặp chạy, không chặn main |

Thêm một: `UIAlert`/thông báo crash của hệ thống không cần — `open` app rồi hỏi
`pgrep` là biết còn sống hay không, nhanh hơn mở báo cáo.

**Về việc bấm nút tự động.** Thử tái hiện riêng crash của `step()` bằng `CGEvent`
đã **thất bại**: post sự kiện sang app khác cần quyền Accessibility, và cửa sổ
chưa kịp hiện. Tôi **không** ghi nhận là đã tái hiện được chỗ đó. Bằng chứng cho
nhánh `images[-1]` đến từ crash *thật* ở `showPinnedIfNeeded()` — cùng nguyên nhân,
cùng biểu thức, đã tái hiện trên app thật và xác nhận bằng báo cáo crash.

---

# Vòng 3 — năm điểm rà soá (đã sửa, có phép đo)

Kết quả: **3 đúng hoàn toàn, 1 đúng phần nguyên nhân nhưng sai phần cơ chế, 1
đúng nhưng hậu quả thật sự thấp hơn mô tả.** Đều đã sửa.

## 13. Vòng lặp kéo chỉ thoát khi nhận `.leftMouseUp`

**Phần đúng.** `begin()` có `while true`, chỉ ra khỏi vòng lặp ở nhánh
`e.type == .leftMouseUp`. Không có đường thoát nào khác.

**Phần sai: kịch bản "mất focus là mất `mouseUp`".** Trên macOS, app đã nhận
`mouseDown` thì **giữ mouse grab** — kéo và thả vẫn về app đó dù Cmd+Tab, dù
Mission Control. Nên kịch bản Zalo hiện lên rồi thả chuột **không gây kẹt**.

**Phần đúng và đáng sửa: nếu `mouseUp` thất lạc thì treo vô hạn.** Đo trước khi
sửa — thả chuột "cứu tinh" post vào giây thứ 6 thì vòng lặp mới ra (6.30s); không
có nó thì treo. Hậu quả: `isDragging` kẹt `true`, widget dính theo con trỏ, và
con trỏ bàn tay nắm kẹt trong ngăn xếp đến hết phiên.

**Cách sửa — chó canh, và cố tình hẹp.** Khi đã bật lưới thì hẹn mốc 0.3s thay vì
chặn vô hạn; mỗi lần tỉnh dậy kiểm tra hai điều:

| điều kiện | ngưỡng | vì sao |
|---|---|---|
| mất focus liên tục | 1.0s | đúng kịch bản "kéo bị bỏ rơi" |
| không có sự kiện nào | 30s | bịt lỗ hổng còn lại khi app **vẫn** active |

Hai ngưỡng phải dài: người dùng cầm widget lên suy nghĩ vài giây là chuyện thường
(đó là lý do có `settleDuration`), nên không thể chặn theo thời gian im lặng thuần.

**Đo cả hai chiều** (bổ sung vào `Tests/main.swift` mục I):

```
im lang, khong co su kien nao   -> 2.90s   (truoc khi sua: 6.30s, chi do cuu tinh)
keo that 4s, vuot qua nguong   -> 4.01s   (khong bi cat ngao)
```

## 14. "Bỏ thư mục" xong ảnh vẫn nằm vĩnh viễn

Xác nhận bằng đọc: `clearFolders()` xoá `images`, dừng timer, dựng lại menu — và
**không bao giờ ra lệnh cho `WidgetWindow`**. Danh sách rỗng nên không còn gì đổi
ảnh, timer đã tắt → tấm ảnh cuối nằm đó mãi mãi.

Chỉ `orderOut` thì chưa đủ: hai `ImageCanvas` vẫn giữ `NSImage` cũ. Thêm
`WidgetWindow.clear()` xoá cả hai lớp + ẩn lưới + ẩn nút + ẩn cửa sổ.
Hồi quy ở mục J: trước `clear()` có ảnh và cửa sổ hiện, sau đó cả hai đều không.

## 15. Đua luồng trên đĩa cache

`clearCache()` xoá thư mục cache **trên luồng gọi** (main, từ menu), trong khi
`writeCache` ghi vào đó trên `decodeQueue`. Đây là hàng đợi nối tiếp, nên chỉ việc
đưa thao tác xoá vào cùng hàng đợi là hết đường tranh chấp: việc dọn luôn nằm
**sau** mọi việc giải mã đang dở.

`pruneCache()` cũng xoá file nên chuyển theo (`pruneCacheNow` chạy trong hàng đợi).

Hồi quy ở mục K: bắn 12 lượt nạp xen kẽ 4 lần xoá cache, rồi kiểm tra thư mục
cache còn nguyên.

## 16. Observer closure không tự giỡ

Đúng: `addObserver(forName:...)` trả về `NSObjectProtocol` **không có gì tự gỡ nó**.

Nhưng cần nói đúng mức độ: hiện tại **chưa rò gì** — `AppController` là singleton
sống suốt đời app và `watchScreenState()` chỉ gọi **một** lần. Đây là lỗi âm ỉ
(hôm nay gọi một lần, ngày sau gọi hai lần khi tái cấu trúc thì nhân lên mà
không có gì báo). Giữ `observerTokens` và gỡ trong `deinit` — gần như miễn phí.

## 17. Con trỏ: bỏ `push`/`pop` tay, chuyển sang `addCursorRect`

Đúng, và đáng làm hơn cả gợi ý: ngăn xếp con trỏ của macOS là **toàn cục cho cả
máy**, lệch một lần là con trỏ cả hệ thống còn kẹt. `addCursorRect` không có
đường nào để lệch vì AppKit tự trả về nguyên trạng khi ra khỏi `bounds`.

Code cũ **đã có** hai lớp phòng thủ (`hoverPushed` và `popHoverCursorIfNeeded()`
gọi lúc kết thúc kéo), nên rủi ro thấp hơn mô tả — nhưng `mouseExited` rớt là có
thật khi cửa sổ trượt dưới con trỏ đứng yên. Đổi hẳn sang `resetCursorRects`, bỏ
hai cờ trạng thái.

---

## Sai lầm ở chính phép đo của vòng này

**Lần "chứng minh lỗi kẹt chuột" đầu tiên của tôi vô giá trị.** Tôi đo thời gian
`begin()` kết thúc bằng cách bọc `pump(12)` — nên luôn ra ~12s, đo cái gì không
liên quan. Đúng phải đo thời điểm `onEnd` chạy.

**Hồi quy mục I fail một lần — và lỗi là ở test, không ở app.** Chiều (2) cho
2.51s thay vì 4.01s. Nguyên nhân: lần thả chuột "cứu tinh" hẹn ở giây 6 của chiều
(1) **vẫn còn treo**, và nó bay sang vòng kéo của chiều (2) để kết thúc giữa
chừng. Chính là bẫy "event sót" đã ghi ở mục 3 — lần này sót là **timer đã hẹn**,
chứ không phải sự kiện chuột. Sửa bằng cách cho hết giờ rồi `drainEvents()`.

> **Bài học đã lặp lại lần thứ hai:** đo xong phải hỏi "phép đo này có đang đo đúng
> thứ không" trước khi tin kết luận.
