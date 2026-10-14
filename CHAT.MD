# CHAT.MD — LitePic

Nơi hai AI cùng thảo luận ý tưởng và truy bug. Ghi lại để không mất mạch.

**Quy tắc:** mỗi vấn đề ghi 4 mục — *Triệu chứng* / *Đã loại trừ* / *Giả thuyết* / *Việc tiếp*.
Không sửa code khi chưa ghi rõ vì sao sửa. Ưu tiên đo trước, sửa sau.

---

## VẤN ĐỀ 1 — Widget thi thoảng không kéo được (ĐÃ GIẢI)

**Triệu chứng**
- Bấm kéo widget: đôi lúc được, đôi lúc không. Không có mẫu hình rõ ràng.
- Giữ 2s để hiện lưới: từng hoạt động, giờ không thấy.

**Đã loại trừ (có bằng chứng)**
- `hitTest` trả về đúng `DraggableView` — test trực tiếp, xác nhận.
- Logic khe lưới chạy đúng khi gọi tay — khe cách ô 0pt.
- Lưới hiện đúng lúc giữ đủ 2s — **chụp màn hình thật**, đối chiếu trước/sau.
- Overlay ẩn đúng sau khi thả — cũng bằng ảnh chụp.

**Nguyên nhân thật: H1 — widget bị cửa sổ khác che.**

Đã xác nhận bằng chứng: `levelMode = 0` (tầng desktop, dưới tầng 0) khiến widget
**bị che và bấm không ăn**; đổi sang `1` (floating) thì mọi thao tác chạy bình thường.
Đây là lý do "không có mẫu hình rõ ràng" — tùy cửa sổ app nào đang mở mà widget bị che
hay không.

Hai thứ bổ sung cho nhau:
- `levelMode` mặc định là `1`. Không còn để `0` làm mặc định.
- `autoLiftIfOccluded()` — nếu người dùng cố ý chọn `0` mà có cửa sổ khác đè lên,
  app tự nâng lên tầng nổi. **Chỉ nâng, không tự hạ** (hạ xuống có thể khiến widget
  chui xuống đúng lúc người dùng đang làm việc).

**H2, H3 không còn cần kiểm** — đã có nguyên nhân giải thích được triệu chứng,
và mô hình đó khớp với việc lỗi "đôi lúc" chứ không phải "luôn".

### Bài học từ lỗi này

Cách mô tả "đôi lúc được đôi lúc không" là **một chỉ dấu** chứ không phải lời phàn nàn
vô nghĩa: nó thường nghĩa là điều kiện bên ngoài thay đổi (cửa sổ nào đang mở, widget
ở tầng nào, màn hình nào), chứ không phải logic bên trong có chỗ sai. Tôi đã dành
nhiều thời gian tìm lỗi trong vòng lặp chuột trong khi lỗi nằm ở tầng cửa sổ.

### Kiểm chứng bằng bộ test thật (7 tình huống)

Đã dựng `Tests/main.swift` + `test.sh`, chạy trên vòng lặp sự kiện thật — không gọi
hàm nội bộ. Cả 7 tình huống đạt, gồm cả **thả chuột ra ngoài cửa sổ** (tình huống E)
vốn là chỗ dễ kẹt trạng thái. Chi tiết và 3 bẫy khi viết phép đo: xem README mục 5 và 7.


## GHI CHÚ ĐÃ BIẾT

**Sự cố mất source (23:42)** — toàn bộ `~/Documents/Default Project/LitePic/` bị xoá,
chỉ còn app đã build trong `/Applications`. Khôi phục từ `~/Downloads/code/LitePic`.
Đã `git init` + commit ngay để không lặp lại.
Bài học: dọn dẹp phải có đường dẫn tuyệt đối và xác nhận trước; không dùng mẫu rộng.

**Phép đo `CGWindowList` không đáng tin với app accessory ở tầng desktop.**
Cả lúc hiện lẫn lúc ẩn, nó đều trả kết quả sai. Đã bị nó dắt dối một lần.
→ Dùng `screencapture` chụp thật, hoặc so `NSWindow.isVisible`.

---

## Ý TƯỞNG TÍNH NĂNG (chưa làm, chờ bug xong)

Ghi từ ý tưởng ban đầu — xếp sau bug kéo.

1. **Chủ động chọn tần suất**: Apple Photos Widget đổi ảnh hoàn toàn tự quyết.
   Cho chọn: 15 phút / 1 giờ / mỗi ngày / mỗi lần thức Mac. *→ LitePic đã có sẵn,
   nhưng thiếu chế độ "đổi khi thức dậy".*
2. **Hỗ trợ thư mục ngoài**: chọn thư mục Finder bất kỳ, kể cả Google Drive /
   Dropbox / iCloud Drive. *→ LitePic đã hỗ trợ thư mục ngoài, nhưng chưa có
   security-scoped bookmark nên mất quyền sau khi restart.*
3. **Nút trên widget**: Next / Previous, Ghim ảnh, tim, "Show in Finder".
   Lưu ý kỹ thuật của bài học này: nếu chuyển sang WidgetKit thì giới hạn RAM
   widget ~30MB, phải nạp thumbnail đúng kích thước, và cần sandbox bookmark.
   *→ Với kiến trúc cửa sổ AppKit hiện tại thì không bị giới hạn này.*
4. **Khung ảnh**: Polaroid, film strip 35mm, glassmorphism, viền theo màu chủ đạo.
   *→ Đã làm 4 kiểu: Bóng đổ / Polaroid / Phim 35mm / Kính mờ.*
5. **Layout lai**: ảnh + đồng hồ tối giản, ảnh + lịch tháng, ảnh + châm ngôn.

---

## BÀI HỌC ĐO HIỆU NĂNG (sau đợt tối ưu 13/10)

### 1. ĐỪNG TIN `ps rss` — đó là bẫy

Tôi đo bằng `ps rss` suốt buổi và tưởng app phình từ 26 MB lên 109 MB rồi
săn tìm "rò rỉ". Hoá ra:

| Cách đo | Cho ra |
|---|---|
| `ps rss` | 64 MB |
| `vmmap` → `Physical footprint` | **26 MB** |

RSS đếm cả trang bộ nhớ dùng chung với WindowServer và các framework hệ thống
— cộng vào đó là phần có thể thu hồi. Muốn biết máy thật sự mất bao nhiêu cho
app thì phải đọc `phys_footprint`:

```
vmmap -summary <pid> | awk '/Physical footprint:/{print $3}'
```

Hệ quả: **một số thứ tôi sửa theo cảm tính hoá ra không có ích gì.** Bản "tối ưu"
giải mã 2 bước + `CGContext` + vùng đệm tái dùng làm RAM *tệ hơn* bản gốc
(109 MB vs 91 MB theo RSS). Đã hoàn nguyên hết. Chỉ giữ lại những gì đo được là
có ích.

### 2. Test cô lập có thể đảo ngược kết luận

Vòng lặp test gọi `widget.show()` liên tục cho thấy RAM tăng đều 3 MB/ảnh, tới
133 MB. Chạy đúng code đó trên **run loop thật** lại phẳng 34 MB. Nguyên nhân:
không có autorelease pool + không có run loop nên mọi `NSImage` tạo ra đều bị giữ.

→ Bài đợt trước (`display: false` làm lưới không hiện) cũng dính bẫy này: test bằng
cách gọi thẳng hàm bỏ qua đường đi chuột thật.

### 3. Những gì thực sự đo được là có ích

| Việc | Đo được |
|---|---|
| Bỏ `prewarm` (giải mã hết 43 ảnh lúc mở) | CPU lúc mở 1.25s → 0.18s |
| Giải mã ngoài luồng chính | không còn đứng hình 0.33s mỗi lần đổi ảnh |
| Cache RAM LRU (3 ảnh) | bấm ‹ › tức thì, không giải mã lại |
| `shadowPath` | CoreAnimation không còn rasterize + blur lại bóng mỗi lần kéo |
| `highlight()` chỉ chạm 2 lớp | thay vì 8, mỗi sự kiện rê chuột lúc khe lưới |
| Dọn cache theo bucket | 4 bucket rác (9.7 MB) → 1 bucket (0.3 MB) |
| `Diag.log` dạng autoclosure | không cấp phát chuỗi khi log đang tắt |

### 4. Con số cuối

- **Rảnh:** 27/28 mốc đọc CPU = 0.0%, một mốc 0.1% (đúng lúc timer 60s đổi ảnh).
  Về mặt năng lượng thì không khác gì một widget nền tĩnh của macOS.
- **Footprint là BƯỚC THANG, không phải đường phẳng.** 28 mốc trong ~10 phút:
  nhỏ nhất 19.4 MB, lớn nhất 23.5 MB, trung bình 22.1 MB, biên độ 4.1 MB.
- RAM **không phình theo thời gian** — biên độ 4MB là LRU nhả-giữ, không phải rò rỉ.

**Lỗi tôi từng mắc khi ghi con số này:** viết "footprint phẳng 19 MB" sau khi đo
đúng 5 lần. Đo tiếp 28 lần mới thấy nó dao động 19.4–23.5 theo bậc thang. Hai lời
phán sai, theo hai hướng ngược nhau:
- Đo 1 lần lúc mới mở → "chỉ 11 MB" (thiếu phần nạp cache).
- Đo 5 lần lúc yên → "nó phẳng 23.2 MB" (hên đúng lúc cache chưa đổi).

Phải đo **nhiều mốc**, và phải hiểu hình dạng đường đo. Rò rỉ thật là **đường
thẳng dốc lên đều**; LRU là **bậc thang lên xuống**.

- 4 luồng, 0 dependency, 0 network, 0 Finder.

### 6. Ba bẫy khi viết phép đo (gặp thật khi dựng bộ test kéo)

**a) Gán đè callback để quan sát — xoá luôn thứ đang đo.**
```swift
view.session.onDrop = { r in ... }   // SAI: đè wiring của app
```
`onDrop` vốn được `WidgetWindow.init` gán cho `finishDrop` — ghi đè thì `finishDrop`
không bao giờ chạy, widget không bao giờ khe vào ô — nhưng phép đo **vẫn "đạt"** vì
nó chỉ ghi lại đúng thứ chính nó vừa ghi vào. Tôi đã mất rất nhiều thời gian vì việc
này: cả 2 phiên bản (cũ và mới) đều cho "0 ô lưới", tưởng refactor làm hỏng.
Đúng cách:
```swift
let g = s.onDrop
s.onDrop = { g?($0); /* phần quan sát của mình */ }
```

**b) So toạ độ tuyệt đối — AppKit làm tròn góc cửa sổ ra số nguyên.**
Ô lưới ở (526.75, 437.5), widget khe đúng nhưng `window.frame.origin` thành
(526.0, 437.0) → lệch 0.901pt. Ngưỡng 0.5pt sẽ báo "KHÔNG khe" cho một cú khe
hoàn toàn đúng. Ngưỡng đúng: **≤ 1.5pt** (= √(0.75² + 0.5²)).

**c) Event sót chảy sang tình huống test kế tiếp.**
Nhấp đúp (`clickCount == 2`) **trả về sớm**, không đi vào vòng lặp, nên không ăn
`mouseUp` mà chính test đã post. Sự kiện đó còn trong hàng đợi và làm tình huống
tiếp theo kết thúc ngay bằng `.click`. Tôi từng kết luận "lưới không bật" trong
khi chỉ là hàng đợi bị bẩn. Cần `drain` hàng đợi trước mỗi tình huống.


### 5. Bug tìm ra khi tối ưu

`Bookmarks.resolve()` trả về danh sách riêng của nó và **thay thế hoàn toàn**
`folders` trong tuỳ chọn; `Bookmarks.save([])` lại không xoá giá trị cũ. Hệ quả:
bấm "Bỏ thư mục" rồi mở lại app thì app vẫn tự giải mã 24 ảnh cũ. Đã sửa: `folders`
là nguồn sự thật, bookmark chỉ dùng để *sửa đường dẫn* khi thư mục bị di chuyển.
---

## 6. Vấn đề 6 (2026-10-13): widget biến mất khi giữ chuột để bật lưới

> Bản tra cứu đầy đủ (kèm phép đo chạy được cho từng lỗi) nằm ở **`BUGS.md`**.
> Mục này chỉ ghi lại quá trình để hiểu vì sao mất 2 tiếng.

**Triệu chứng.** Giữ widget → lưới hiện → widget trống trơn. Cửa sổ vẫn còn, vẫn
bấm/chuột phải được, `CGWindowList` báo `onScreen=1, alpha=1.00`. Chỉ tới lúc app
**đổi ảnh** nó mới hiện lại.

**Nguyên nhân.** Ảnh được đổ bằng cách gán `layer.contents` **tay** lên
`NSImageView`. Ô nhớ đó do AppKit sở hữu: mỗi lần AppKit vẽ lại view, `draw()`
của `NSImageView` chạy với không có `image` và **xoá sạch `contents`**. Mà đổi
transform của lớp cha thì đủ để kích hoạt lần vẽ đó — và `lift()` làm đúng việc
đó ngay khoảnh khắc bấm giữ, **trước cả khi lưới hiện**.

**Cách sửa.** Thay `NSImageView` bằng `ImageCanvas` — `NSView` tự vẽ ảnh trong
`draw(_:)`. AppKit vẽ lại bao nhiêu lần thì ảnh vẫn còn. Bài học chung:

> **Đừng đặt tay vào `layer.contents` của view AppKit quản lý.** Ô nhớ đó của
> AppKit, AppKit xoá tuỳ ý. Muốn giữ thì phải tự vẽ trong `draw(_:)`.

### Những chỗ đi sai (vì đều đáng lẽ phải dễ hơn)

* **Nghi overlay che widget** → đo thật: overlay trong suốt, không che gì.
* **Nghi transform 3D phá lớp** → đo thật: nội dung vẫn hiện.
* Đo bằng `screencapture -R` vùng widget → dễ đo nhầm cửa sổ của chính mình.
  Bắt buộc `precondition(widget.window.isVisible)` trước khi đo, vì `init()` gọi
  `orderOut(nil)`.
* Thử 3 kỹ thuật đặt transform rồi kết luận "CABasicAnimation là cách an toàn".
  **Sai** — cả ba đều làm mất ảnh, nhưng vì thứ tự thử làm sai lệch (sau khi ảnh
  đã mất thì `setContents` hồi lại được). Chỉ khi đổi kiến trúc mới thấy cả bốn
  cách đều "giữ được". **Đừng kết luận từ phép thử có tham số bị nhiễm.**
* Bản sửa đầu tiên của tôi (`container.wantsLayer = true`) **không ăn**. May là
  tôi kiểm chứng trước khi báo cáo.

**Bẫy thứ tư khi đo — bẫy này đáng nhớ nhất.** Tấm ảnh "sau khi thả" cho thấy
widget đã hiện lại, và tôi suýt kết luận lỗi tự hết. Hoá ra tấm đó **trùng đúng
lúc app đổi ảnh** (chu kỳ người dùng đặt là 15s) — tai nạn thời gian, không phải
hành vi của lỗi. Người dùng phải nhắc mới thấy.

> **"Đã hồi phục" có thể chỉ là trùng hợp.** Luôn nhìn cả trạng thái *trước* khi
> tạo ra nó.

### Lỗi kèm theo phát hiện ra từ đây: ba góc vuông khi giữ

Sửa xong lỗi trên thì thấy thêm: lúc widget "nâng" lên, ảnh bị cắt vuông ở ba
góc, chỉ góc dưới-trái còn bo. **Hai nguyên nhân chồng nhau:**

1. Cửa sổ đúng bằng kích thước ảnh → ảnh scale 1.06 tràn ra, bị cửa sổ cắt.
2. AppKit đặt `anchorPoint = (0,0)` cho view (không phải `0.5,0.5`) → scale quanh
   góc dưới-trái nên góc đó đứng yên, ba góc kia bị đẩy ra ngoài. **Đúng bất đối
   xứng người dùng mô tả.**

Cách sửa: đổi `anchorPoint` sang tâm, chừa viền trong suốt trong cửa sổ, và bo
góc vẽ tay trong `ImageCanvas.draw(_:)` — cùng nguyên tắc "đừng tin lớp của
AppKit".

**Bẫy khi tính chỗ trống.** Ban đầu tôi chừa 2.2% rồi 3.5% — vẫn thiếu. Vì **chỗ
trống cũng bị scale theo**, nên khoảng cách từ tâm tới mép ảnh lớn hơn bạn tưởng,
và cần `≥ 3.2% × cỡ ảnh`. Thiếu thì góc lại vuông — đo lại thấy ngay.

Hệ quả: cửa sổ lớn hơn ảnh ~8%, nên **lưới phải bám ảnh** (`imageSize`,
`imageOrigin`) chứ không bám `window.frame` — người dùng nhìn thấy ảnh, không
phải khung cửa sổ.

---

## 7. Đợt 14/10: sáu lỗi, và bài học lớn nhất là về **phép đo**

Cả sáu lỗi đều do người dùng báo, và cả sáu đều đúng. Nhưng đáng kể hơn: **năm
trong số đó tôi tự kết luận sai trước khi sửa phép đo.**

### Sửa hiển thị làm lộ lỗi toạ độ đã ẩn

Răng cưa phim 35mm "dồn cụm giữa ảnh" — đúng là trục Y đứng yên. Tôi sửa xong, đo
lại, thấy răng **vẫn nằm sai chỗ**: vì răng là subview của nền nền mà khung lại lấy
toạ độ của cha. Hai lỗi trong cùng một khối 6 dòng. Sửa mỗi lỗi một, mỗi lần lại
lộ lỗi kia.

> **Sửa xong phải đo lại từ đầu, không tin phép đo cũ.**

### Đề xuất của người dùng: đúng một nửa

Báo cáo lỗi răng cưa kèm sẵn đoạn code sửa đặt răng ở `r.minX - 18` và
`r.maxX + 6`. Tôi đo được: hai cột nằm **ngoài dải phim**, lên thành viền trong
suốt. Nguyên nhân đúng (trục Y), nhưng **công thức trục X của đề xuất đặt sai chỗ**.
Nếu tôi dán thẳng vào báo cáo thành công, người dùng sẽ nhận một widget trông
lạ. Suy luận "đề xuất có lỗ hổng" là được — nhưng phải **đo**, không phải cảm.

### Tầng cửa sổ: số "+20" trông hợp lý thì vẫn sai

`CGWindowLevelForKey(.desktopWindow) + 20` nghe rất hợp lý. Kết quả:
`-2147483603` — **trùng đúng tầng desktop icon**, và mọi tầng ≤ `-2147483602` bị hệ
thống xếp thành desktop element, tức biến mất khỏi mọi danh sách cửa sổ chuẩn.

Ngưỡng đó không có trong tài liệu, tôi phải **dò thử 14 mức tầng** mới biết. Với
tầng cửa sổ, đừng suy từ tên hằng số — hãy đo.

### Đừng dừng ở chỗ hỏng đầu tiên

`lastIndex = -1` gây crash ở `step()` — đúng như báo cáo. Nhưng ngay cạnh đó còn
`showPinnedIfNeeded()`, cũng đọc `images[lastIndex]`, và **dễ trúng hơn hẳn**: chỉ
cần ghim ảnh rồi có lần quét lại thư mục nào là chết, không cần bấm gì.

Tái hiện được trên app thật trong 5 giây: ghim ảnh → mở app → chết. Báo cáo crash
chỉ đúng `AppController.showPinnedIfNeeded()`. Sửa xong chạy lại đúng kịch bản đó:
app sống.

> **Săn lỗi index phải grep hết, không dừng ở lỗi đầu.** Dòng 455 vốn đã có
> chặn sẵn — nghĩa là đây không phải "quên chặn", mà là "chặn sót".

### Bốn cái tôi đo sai trước khi sửa

| Sai lầm | Vì sao |
|---|---|
| `func mir<T>` ở top-level `main.swift` | Swift không cho specialize hàm global ở `main.swift` — báo lỗi rất khó hiểu |
| `Mirror` tìm `imageInset` | Đó là thuộc tính **có thân hàm**, `Mirror` không thấy; tôi tưởng app sai |
| `s2.frame` của view cháu | Toạ độ **của cha**, lệch đúng bằng `bg.origin` |
| `semaphore.wait` chờ callback | `ImageStore.load` bắn qua `DispatchQueue.main.async` → **deadlock**, đo ra ảnh `0×0`, tôi kết luận app giải mã hỏng |

Cái cuối đáng nhớ nhất: **phép đo hỏng trông giống hệt app hỏng.** Đo sai mà
kết luận sai thì còn tệ hơn không đo.

### Một việc tôi **không** làm được

Tái hiện riêng crash của `step()` bằng cách bấm nút tự động: **thất bại**. Post
`CGEvent` sang app khác cần quyền Accessibility, và cửa sổ chưa kịp hiện. Không
ghi nhận là đã tái hiện được chỗ đó. Bằng chứng cho nhánh `images[-1]` đến từ crash
*thật* ở chỗ kia — cùng nguyên nhân, cùng biểu thức.

### Lưới: bỏ 83/84 ô nhưng phải giữ ô đang ngắm

Người dùng bảo 84 ô trắng chồng nhau rối mắt, chỉ ẩn đừng xoá. Làm bằng cờ
`drawAllSlots = false`, không xoá dòng nào. Nhưng phải sửa thêm `paint()`: nếu chỉ
ẩn ở chỗ tạo ô thì **ô đang ngắm cũng biến mất**, và lưới thành vô dụng vì
người dùng không thấy chỗ nó sẽ rơi vào. Đo lại: 84 ô, **hiện đúng 1**.

### Hiệu năng sau tất cả

```
cpu_idle_pct        0.0  → 0.0     (không đổi)
ram_median          9.5  → 9.7 MB  (+2.1%)
ram_slope           0.00 → 0.00    (phẳng)
threads             3    → 3
```

Không hồi quy. Số luồng không đổi dù thêm `DispatchQueue.main.async` — đo mới tin,
đoán thì không.

---

## 8. Đợt 14/10 (tiếp): ba điểm rà soá, và bài học lớn nhất của dự án

Ba điểm được nêu: test dính đường dẫn cứng, `build.sh` không ghim target, và
`bench.sh` có dead code + bẫy đếm cửa sổ. Tất cả đều đúng — **nhưng phần "đúng"
này dẫn tới một sai lầm lớn hơn nhiều**.

### Hai trong ba: đúng, và sửa xong thì phải đo lại từ đầu

**Đường dẫn cứng trong test.** Đúng. Tôi tự tạo ảnh JPEG trong thư mục tạm rồi
chạy lại: 28/28 vẫn đạt, dù ảnh giả 400×300 khác tỉ lệ ảnh thật.

Nhưng lần đầu tôi "chứng minh" bằng cách chạy test với `HOME` trỏ vào thư mục
giả — và **bản cũ vẫn chạy qua**. Vì `NSHomeDirectory()` trên macOS đọc từ cơ sở
dữ liệu mật khẩu chứ không đọc `$HOME`. Phép chứng minh của tôi **không có giá
trị**, suýt thành bằng chứng ngược. Chạy lại bằng cách chạy đúng hai dòng code cũ
trỏ tới thư mục không tồn tại: `exit 132` — SIGILL, `try!` trap đúng như báo cáo.

**`build.sh` không ghim target.** Đúng, và nặng hơn tưởng:

```
bản cũ:  minos 15.0      ← swiftc lấy target theo máy đang build
bản mới: minos 13.0      ← đã ghim, khớp LSMinimumSystemVersion
```

Tức app từng **không chạy được trên macOS 13/14** dù `Info.plist` khai là chạy
được. Sửa bằng `-target $(uname -m)-apple-macos13.0`.

Một chỗ tôi **không** sửa theo lập luận đưa ra: "rm -rf không xoá sạch inode bị
lock, WindowServer giữ cache chữ ký". Trên macOS `rm -rf` xoá được nhị phân đang
chạy — tiến trình giữ inode cũ, chuyện đó không gây lỗi. Cái thật sự gây hiểu
nhầm là **bản đang chạy vẫn thực thi mã cũ**: build xong, `cp` sang
`/Applications`, mở lên thấy y hệt, tưởng sửa không ăn. `pkill` trước khi build
thì đúng mục đích, nhưng phải ghi đúng lý do — nếu ghi sai lý do thì lần sau rắc
rối lại sẽ sửa nhầm.

**Bẫy đếm cửa sổ.** Đây là chỗ **suy đoán đúng, nhưng không còn thành vấn đề**.
Ở chế độ dưới app, helper của `bench.sh` trả về `2` — 10/10 lần — vì bản sửa tầng
đã đưa widget lên `-2147483601`, trên ngưỡng desktop element. Nên tôi **không** làm
`defaults write levelMode -int 1`: làm vậy là **sửa cấu hình của người dùng**, và
còn đo nhầm — mốc phải phản ánh cấu hình thật. Thay vào đó vá **phép đo** cho
không thể trượt: đếm bằng bộ lọc chuẩn, ra 0 thì đếm lại không loại desktop.

### Bài học lớn: `bench.sh` báo LOI, và tôi gần như tin nó

Sau khi sửa 7 lỗi, chạy `check`: **RAM median 17.5 MB so với mốc 9.5, +84%, LOI**,
kèm `slope +1.53 MB/phút` — đúng chữ ký rò rỉ. Trong hai phút, bốn lần đo, tôi
đã viết vào `BUGS.md` rằng không hồi quy.

Run lại: `9.7 MB, OK`. Cùng binary, cùng mốc.

Tôi đã sai ở chỗ quen thuộc nhất của dự án này: **kết luận từ phép đo mà chưa hỏi
phép đo có đáng tin không.**

Đào ra nguyên nhân, từng bước:

1. Xem chuỗi mốc (đúng bài học cũ) → dao động `10.8 ↔ 16.2`, **không** có xu hướng
   tăng. Không phải rò.
2. Giữ màn hình không ngủ bằng `caffeinate` → vẫn dao động. Không phải ngủ/tỉnh.
3. Đếm sự kiện FSEvents trong 120s → **0**. Không phải quét lại thư mục.
4. Đọc cấu hình → `randomInterval = 1`, còn `minInterval`/`maxInterval` **chưa đặt**
   nên mặc định **15 và 300 giây**. Nghĩa là `interval = 1800` của người dùng bị
   **bỏ qua hoàn toàn**, và app đổi ảnh ngẫu nhiên mỗi 15–300s. Mỗi lần đổi =
   giải mã ảnh mới = LRU nhả-giữ = đúng nhịp bậc thang tôi đo được.

Đó là **cấu hình của chính người dùng**, không phải lỗi. Và nó có nghĩa là con số
trung vị vốn dĩ là cái đồng xu:

```
cùng một binary, cùng 8 phút, 4 lần chạy:
  median 9.9 / 13.5 / 14.2 / 15.3 MB
```

Ngưỡng 15% trên một số biên độ 55% thì bắt nhiễu nhiều hơn bắt lỗi thật.

### Ba sửa trong chính bộ đo

- **Tạm tắt đổi ảnh khi đo, rồi khôi phục** (biến `SAVED_*` + `trap`). Đây là
  trạng thái *đầu* — dùng để so hai bản, không phải trạng thái *chạy*.
- **`cfprefsd` cache.** Ghi `defaults` xong mở app ngay thì app đọc **giá trị cũ**
  và vẫn chạy 15–300s. Cùng mã, lần này `9.7 … 13.3 … 14.2`, lần kia `9.8` phẳng
  6 phút — khác nhau *chỉ* ở thời điểm đọc cấu hình. Nay ghi trước **mỗi** lần mở.
- **Đo launch 5 lần, lấy trung vị.** 14 lần đo được `0.57 … 0.88`, biên độ ±25%
  — lớn hơn ngưỡng. Thêm bẫy nữa: lần mở **đầu tiên sau khi cài** ra `2.17s`
  (LaunchServices phải đăng ký lại bundle). Nay hứt một lần trước khi đo.

Và cách trích trạng thái đi ngang: **bỏ mọi mẫc trước khi chuỗi chạm 95% đỉnh
cuối**. Cắt cứng "bỏ 25% đầu" không cứu được vì bước nhảy rơi ở thời điểm không
xác định. Nó không bỏ sót rò rỉ: rò rỉ đi liên tục, không bao giờ chạm đỉnh sớm.

Kết quả sau khi sửa bộ đo — 32 mốc/8 phút, **biến động 0.1 MB**:

```
9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 9.8 ...
slope = +0.00
```

### Về việc "sửa 7 lỗi có làm app nặng lên không"

Đây mới là câu hỏi thật, và tôi trả lời sai **hai lần** trước khi trả lời đúng.

Vòng 1: bản cũ phẳng 14.8, bản mới leo tới 21.2 → kết luận 7 sửa đổi gây hồi
quy. Vòng 2 (lặp lại): **cả hai** đều leo tới 19–20. Vậy vòng 1 mới là ngoại lệ.

Tôi đã viết kết luận "không hồi quy" vào `BUGS.md` **trước khi** lặp lại. Chỉ
lặp lại mới biết cái nào là nhiễu.

Sau khi bộ đo ổn định:

| so sánh | trước | sau |
|---|---|---|
| 7 sửa lỗi (1b53191 vs 168bdec) | median 14.8 / 13.5 | 17.3 / 13.7 — không phân biệt được |
| `build.sh -target` | 13.6 | 12.4 |

> **So hai bản build thì phải xoay vòng A/B với cùng cửa sổ đo, không so hai lần
> `check` rời rạc.** Và phải lặp lại trước khi tin kết luận âm — "không thấy hồi
> quy" cũng là một kết luận, và nó cũng cần bằng chứng.

### Tự sửa: tôi đã làm hỏng `bench.sh` giữa chừng

Một lần tôi đặt `oldString` sai, `edit` khớp nhầm chỗ, và nó **xoá mất khối tính
toán rồi chèn sai khối khác vào**. `bash -n` báo lỗi cú pháp — may mà có kiểm tra.
Khôi phục bằng `git checkout` rồi làm lại từng bước, mỗi bước `bash -n`.

Cũng có lần tôi sửa một dòng "không đổi gì" và nó **nhân bản** dòng đó lên hai
bản. Một sửa không đổi gì mà sinh ra thay đổi — loại sai mà `git diff` mới bắt
được, chứ không phải đọc code.

> **Sửa "không đổi gì" là loại sửa nguy hiểm nhất:** dễ tin là vô hại, dễ để sót.
