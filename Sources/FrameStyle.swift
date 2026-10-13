import AppKit

/// View trang trí của khung — đánh dấu bằng subclass để xoá sạch khi đổi kiểu
/// khung (thuộc tính `tag` của NSView trong Swift là get-only).
final class FrameDecoration: NSView {}

/// Kiểu khung quanh ảnh.
///
/// Mỗi kiểu trả về kích thước vùng trống cần thêm quanh ảnh (`inset`) và một
/// hàm vẽ lớp trang trí. Ảnh luôn nằm ở giữa khung, tỉ lệ không bị bóp méo.
enum FrameStyle: Int, CaseIterable {
    case none
    case shadow      // bo goc + bong (mac dinh)
    case polaroid    // vien trang day o duoi, giong anh cua la
    case film        // vien rang cua phim 35mm
    case glass       // kinh mo vien sang

    var title: String {
        switch self {
        case .none:    return "Không khung"
        case .shadow:  return "Bóng đổ"
        case .polaroid: return "Polaroid"
        case .film:    return "Phim 35mm"
        case .glass:   return "Kính mờ"
        }
    }

    /// Bề dày khung tính từ mép ảnh ra ngoài (điểm).
    var inset: CGFloat {
        switch self {
        case .none:    return 0
        case .shadow:  return 0
        case .polaroid: return 22   // vien duoi day -> can nhieu o duoi hon
        case .film:    return 26
        case .glass:   return 14
        }
    }

    /// Khoảng hở giữa mép khung và mép cửa sổ (điểm).
    ///
    /// Hở này là chỗ cho bóng đổ lan ra, chứ không phải viền trang trí. Bản cũ
    /// để cố định 20pt cho mọi kiểu — nên "Không khung" vẫn thấy một dải tối
    /// quanh ảnh, vì bóng được vẽ theo mép cửa sổ chứ không theo mép ảnh.
    ///
    /// Với bóng: Gaussian 14pt lan ra khoảng 1.5 lần bán kính mỗi phía, cộng
    /// thêm phần đường bóng được nới ra — tổng cỡ 24pt. Hở nhỏ hơn thì mép cửa
    /// sổ cắt bóng, để lại một cạnh thẳng cứng cắt ngang góc bo.
    var pad: CGFloat {
        switch self {
        case .none:    return 0    // không bóng -> ảnh áp sát mép cửa sổ
        case .shadow:  return 26
        case .glass:   return 10
        case .polaroid: return 8
        case .film:    return 8
        }
    }

    /// Độ đậm bóng. 0 = không bóng — dùng để "Không khung" thật sự trần.
    var shadowOpacity: Float {
        switch self {
        case .none:   return 0
        case .shadow: return 0.34
        case .glass:  return 0.16
        default:      return 0.26
        }
    }

    /// Phần thêm chiều cao o duoi (Polaroid co vien duoi day hon).
    var extraBottom: CGFloat {
        switch self {
        case .polaroid: return 46
        default:        return 0
        }
    }

    /// Bo goc cho o anh.
    var imageCorner: CGFloat {
        switch self {
        case .none, .shadow: return 20
        case .polaroid, .film: return 2
        case .glass:          return 14
        }
    }

    /// Vẽ lớp trang trí quanh anh. `imageRect` là vung anh trong toa do container.
    func decorate(in container: NSView, imageRect: NSRect) {
        container.subviews
            .filter { $0 is FrameDecoration }
            .forEach { $0.removeFromSuperview() }

        let i = inset
        guard i > 0 || extraBottom > 0 else { return }

        switch self {
        case .none, .shadow:
            break   // bo + bong do WidgetWindow lo

        case .polaroid:
            let r = NSRect(x: imageRect.minX - i, y: imageRect.minY - i - extraBottom,
                           width: imageRect.width + i * 2, height: imageRect.height + i * 2 + extraBottom)
            let bg = FrameDecoration(frame: r)
            bg.wantsLayer = true
            bg.layer?.backgroundColor = NSColor.white.cgColor
            bg.layer?.shadowColor = NSColor.black.cgColor
            bg.layer?.shadowOpacity = 0.30
            bg.layer?.shadowRadius = 12
            bg.layer?.shadowOffset = CGSize(width: 0, height: -5)
            container.addSubview(bg, positioned: .below, relativeTo: nil)

        case .film:
            let r = NSRect(x: imageRect.minX - i, y: imageRect.minY - i,
                           width: imageRect.width + i * 2, height: imageRect.height + i * 2)
            let bg = FrameDecoration(frame: r)
            bg.wantsLayer = true
            bg.layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
            bg.layer?.cornerRadius = 4
            // Rang cua: hai hang lo cham cach nhau doc hai ben trong.
            for side in [true, false] {
                for k in 0..<14 {
                    let d = CGFloat(k) * 7
                    let tooth = FrameDecoration(frame: CGRect(
                        x: side ? r.minX + 4 + d : r.maxX - 7 + d,
                        y: r.midY - 8, width: 4, height: 16))
                    tooth.wantsLayer = true
                    tooth.layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
                    bg.addSubview(tooth)
                }
            }
            container.addSubview(bg, positioned: .below, relativeTo: nil)

        case .glass:
            let r = NSRect(x: imageRect.minX - i, y: imageRect.minY - i,
                           width: imageRect.width + i * 2, height: imageRect.height + i * 2)
            let g = FrameDecoration(frame: r)
            g.wantsLayer = true
            g.layer?.cornerRadius = 16
            g.layer?.masksToBounds = true
            g.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            g.layer?.borderWidth = 1
            g.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
            container.addSubview(g, positioned: .below, relativeTo: nil)
        }
    }
}