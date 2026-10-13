# Bảng tra cứu lỗi — đọc TRƯỚC khi sửa

Cách dùng: gặp triệu chứng → tra bảng → đọc mục "Nhận ra" và "Đo thế nào".
Mỗi mục đều có **phép đo cụ thể đã chạy được**, không phải mô tả miệng.

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

Bộ đo này đã dính và tự sửa các lỗi sau — đừng viết lại từ đầu:

- `ps -o %cpu` sai ý nghĩa → dùng chênh lệch thời gian CPU.
- Đo CPU **ngay sau khi mở app** ra `9.9%` — đó là lúc quét thư mục và giải mã ảnh,
  không phải mức chạy nền. Cùng app đó, đã chạy 14 phút, cho `0.12%`.
  **Bộ đo đã sửa thứ tự: đo RAM trước (cho app ấm), đo CPU sau.**
- `vmmap` in **tung đơn vị**: `18.1M`, `9724K`, `1.2G` — quy đổi để ở Python.
- `vmmap` có **hai dòng** khớp `Physical footprint` (dòng thứ hai là `(peak)`) —
  phải loại `(peak)`, nếu không sẽ đọc trúng số đỉnh.
- `AppleScript` đếm cửa sổ cần quyền Accessibility → dùng `CGWindowList` thay thế.

**GPU không đo được nếu không có `sudo`** cho `powermetrics`. Bộ đo in thẳng
`khong do duoc` chứ không in số 0 — số 0 sẽ khiến người đọc tưởng app không dùng
GPU. Cần đo thì chạy khi có `sudo`.