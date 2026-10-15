# 🖼️ LitePic

> **Widget ảnh desktop siêu nhẹ, thuần native cho macOS.**  
> AppKit thuần túy · Không dependencies · Không Electron · Tiêu thụ dưới 15 MB RAM và 0% CPU khi nghỉ.

---

## ✨ Điểm nổi bật

- ⚡️ **Cực kỳ nhẹ & tiết kiệm pin:** Viết hoàn toàn bằng Swift + AppKit thuần (không WebKit, không Electron). Tiêu thụ chỉ ~10–15 MB RAM, 0% CPU lúc nghỉ, tự động tạm dừng bộ đếm đổi ảnh khi widget bị che khuất hoặc màn hình tắt.
- 🖼️ **Trình chiếu ảnh mượt mà:** Hiệu ứng chuyển cảnh crossfade 60fps mượt mà, giải mã ảnh ngầm (background queue) với bộ nhớ đệm 3 tầng thông minh (RAM LRU ➔ Cache đĩa ➔ File gốc), không làm khựng giao diện.
- 🧲 **Lưới hít thông minh (Smart Grid Snapping):** Bấm giữ 1.2s (hoặc kéo rồi dừng yên 1.2s) để kích hoạt hệ thống lưới ô desktop, tự động hít widget vào vị trí ngay ngắn, cân đối.
- 🎨 **Phong cách khung ảnh đa dạng:** 5 kiểu khung tích hợp (Không khung viền, Bóng đổ mềm, Polaroid kinh điển, Cuộn phim hoài cổ, Kính mờ Frosted Glass).
- 👆 **Thao tác tương tác tự nhiên:**
  - **Vuốt 2 ngón Trackpad** (hoặc cuộn chuột) sang trái/phải để lật ảnh Trước / Kế tiếp.
  - **Rê chuột** vào widget để hiện cụm nút điều khiển nhanh (`‹`, `›`, `📌`).
  - **Click đúp chuột** để mở ngay thư mục và chọn đúng file ảnh trong Finder.
  - **Kéo thả trực tiếp** ảnh hoặc thư mục từ Finder vào widget.
- 📁 **Tự động đồng bộ thư mục:** Tích hợp FSEvents theo dõi thư mục ảnh theo thời gian thực — thêm, đổi tên hoặc xoá ảnh sẽ tự động cập nhật mà không cần khởi động lại. Hỗ trợ duyệt đệ quy thư mục con.
- 📌 **Ghim & Tùy biến:** Dễ dàng ghim bức ảnh yêu thích, tùy chỉnh kích thước cố định hoặc theo tỷ lệ ảnh gốc, điều chỉnh thời gian chuyển ảnh ngẫu nhiên hoặc theo chu kỳ.
- 🔒 **Riêng tư & An toàn:** 100% offline, không kết nối mạng, không gửi telemetry, không can thiệp vào file của người dùng.

---

## 🚀 Cài đặt & Sử dụng

### Yêu cầu hệ thống
- **macOS:** 13.0 (Ventura) trở lên.
- **Nền tảng:** Hỗ trợ cả Apple Silicon (M1/M2/M3/M4) và Intel Mac (Universal Binary).

### Biên dịch từ mã nguồn

Dự án không phụ thuộc Xcode hay CocoaPods/SPM, có thể biên dịch trực tiếp bằng `swiftc` có sẵn trên macOS:

```bash
# 1. Clone repository
git clone https://github.com/sh1bee/LitePic.git
cd LitePic

# 2. Biên dịch (tạo build/LitePic.app)
./build.sh

# 3. Cài đặt vào thư mục Applications
pkill -x LitePic 2>/dev/null || true
cp -R build/LitePic.app /Applications/
open /Applications/LitePic.app
```

> **Lưu ý:** LitePic là ứng dụng menu bar (chạy nền không hiện icon Dock). Biểu tượng của LitePic sẽ nằm trên thanh Menu Bar ở góc trên màn hình.

---

## 📖 Hướng dẫn sử dụng

### 1. Bắt đầu lần đầu
Khi mở ứng dụng lần đầu (chưa chọn thư mục ảnh nào), LitePic sẽ hiển thị khung hướng dẫn trực quan trên màn hình. Bạn chỉ cần:
- **Click chuột vào khung** để chọn thư mục ảnh trên máy.
- Hoặc **kéo thả thư mục/file ảnh từ Finder** thả trực tiếp vào khung.

### 2. Các thao tác chuột & cử chỉ

| Thao tác | Tác dụng |
|---|---|
| **Vuốt 2 ngón Trackpad** (hoặc lăn chuột) | Lật ảnh Kế tiếp hoặc Quay lại ảnh trước |
| **Rê chuột vào ảnh** | Hiện 3 nút điều khiển nhanh (`‹` lùi ảnh, `›` qua ảnh, `📌` ghim ảnh) |
| **Nhấp đúp chuột** | Mở Finder và chọn ảnh đang hiển thị |
| **Kéo thả tự do** | Di chuyển widget đến bất kỳ vị trí nào trên màn hình |
| **Bấm giữ chuột 1.2s** (hoặc kéo rồi dừng 1.2s) | Bật lưới căn chỉnh desktop; thả chuột để hít vào ô gần nhất |
| **Chuột phải vào widget** | Mở menu tuỳ chỉnh nhanh (Chuyển ảnh, Sao chép ảnh, Bỏ qua ảnh này, Kiểu khung...) |
| **Kéo thả thư mục từ Finder vào** | Thêm thư mục đó vào danh sách trình chiếu |
| **Kéo thả 1 bức ảnh từ Finder vào** | Thêm thư mục cha và ghim ngay bức ảnh đó lên desktop |

### 3. Bảng điều khiển Menu Bar
Nhấp vào biểu tượng LitePic trên Menu Bar để tùy chỉnh:
- **Thư mục ảnh:** Thêm/xoá thư mục ảnh, bật/tắt tuỳ chọn "Bao gồm cả thư mục con".
- **Nhịp đổi ảnh:** Chọn chu kỳ đổi ảnh (5s đến 1 giờ) hoặc bật đổi ngẫu nhiên.
- **Kích thước widget:** 
  - *Tự động theo ảnh:* Giữ đúng tỉ lệ ảnh gốc, giới hạn theo cạnh lớn nhất.
  - *Cố định:* Đặt kích thước chiều rộng/chiều cao cố định, hỗ trợ chế độ vừa khung (Fit) hoặc lấp đầy khung (Fill).
- **Kiểu khung:** Đổi qua lại giữa 5 phong cách khung ảnh.
- **Tầng hiển thị (Window Level):** 
  - *Luôn nổi:* Nằm trên các cửa sổ ứng dụng khác.
  - *Trên Wallpaper:* Nằm phẳng dưới các cửa sổ ứng dụng (tự động nâng lên khi bị che khuất).
- **Khởi động cùng máy:** Tự động mở LitePic mỗi khi bạn đăng nhập vào macOS.

---

## 🛠️ Kiến trúc & Thiết kế kỹ thuật

LitePic được thiết kế theo triết lý tối giản: không framework trung gian, tận dụng tối đa API cấp thấp của macOS để đạt hiệu năng tối ưu.

```
                    ┌───────────────────────────────────────────┐
                    │             AppController                │
                    │  • Quản lý vòng đời & Menu Bar           │
                    │  • Điều phối timer đổi ảnh                │
                    │  • Tiếp nhận file kéo thả                │
                    └──┬─────────┬─────────┬─────────┬─────────┘
                       │         │         │         │
                       ▼         │         │         ▼
              ┌─────────────────┐│         │   ┌──────────────┐
              │  WidgetWindow   ││         │   │   Settings   │
              │  • Cửa sổ widget││         │   │ UserDefaults │
              │  • Khung, bóng  ││         │   └──────┬───────┘
              └──┬──────────┬───┘│         │          │
                 │          │    │         │          ▼
       ┌─────────▼───┐ ┌────▼──────────┐ ┌─▼────────────┐ ┌───────────┐
       │DraggableView│ │  GridOverlay  │ │WidgetControls│ │ Bookmarks │
       │• Kéo thả    │ │• Ô lưới desktop│ │(‹  ›  📌)    │ └───────────┘
       │• Cử chỉ vuốt│ └───────────────┘ └──────────────┘
       └──────┬──────┘
              ▼
       ┌────────────┐  ┌────────────┐  ┌─────────────────┐ ┌──────────────┐
       │DragSession │  │GridSnapper │  │  LaunchAtLogin  │ │FolderWatcher │
       │(vòng lặp   │  │(tính ô lưới│  │ (LaunchAgent    │ │ (FSEvents    │
       │ sự kiện)   │  │ toán học)  │  │  plist)         │ │  thư mục)    │
       └────────────┘  └────────────┘  └─────────────────┘ └──────┬───────┘
                                                                  │
                                       ┌──────────────┐           │
                                       │  ImageStore  │ ◄─────────┘
                                       │• RAM LRU     │
                                       │• Disk Cache  │
                                       │• Decode ngầm │
                                       └──────────────┘
```

### Bộ nhớ đệm 3 tầng (ImageStore)
1. **RAM Cache (LRU 3 ảnh):** Giữ tối đa 3 ảnh đã giải mã để lật ảnh tức thì mà không tiêu tốn RAM (chỉ chiếm ~4–8 MB).
2. **Disk Cache (`~/Library/Caches/LitePic`):** Lưu ảnh đã resize theo kích thước khung hình, truy xuất nhanh ~5ms.
3. **Ảnh gốc:** Giải mã tuần tự ngầm trên `decodeQueue` (phân luồng QoS `.utility` khi chạy tự động và `.userInitiated` khi người dùng bấm lật ảnh), không khóa Main Thread.

---

## 📄 Giấy phép

Dự án được phân phối dưới giấy phép MIT License.
