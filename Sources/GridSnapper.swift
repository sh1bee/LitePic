import AppKit

/// Thuật toán hình học của lưới khe: tính vị trí các ô và tìm ô gần nhất.
///
/// Tách riêng khỏi `WidgetWindow` vì đây là phần **thuần toán** — không chạm
/// gì tới AppKit, cửa sổ hay chuột. Nhờ vậy kiểm chứng được bằng phép tính tay
/// thay vì phải kéo chuột thật trên màn hình.
enum GridSnapper {
    /// Một ô lưới: toạ độ góc dưới-trái theo toạ độ màn hình.
    struct Slot {
        var origin: NSPoint
        var size: NSSize
    }

    /// Bố cục lưới cho widget cỡ `size` trên màn hình `visible`.
    ///
    /// Tối đa 6×4 ô (ô phải vừa để chứa), cộng thêm bốn ô sát mép màn hình —
    /// đó là chỗ người dùng hay đặt widget nhất. Ô sát mép trùng với ô lưới
    /// thì bỏ, tránh hai chỗ chồng nhau.
    static func slots(widgetSize size: NSSize, visibleFrame vf: NSRect) -> [NSPoint] {
        let margin: CGFloat = 36
        let gutter: CGFloat = 18
        let usableW = vf.width - margin * 2
        let usableH = vf.height - margin * 2

        // Widget to hơn vùng dùng được thì vẫn phải có ít nhất một ô, và ô
        // phải vừa chứa widget — không phải ô bằng phần chia sẻ lưới.
        guard size.width > 0, size.height > 0 else { return [] }

        let cols = max(1, min(6, Int((usableW + gutter) / (size.width + gutter))))
        let rows = max(1, min(4, Int((usableH + gutter) / (size.height + gutter))))
        // Cố tình KHÔNG ép `cw >= size.width`: khi widget rộng hơn ô lưới, gốc
        // tính `(cw - size.width)/2` âm, đẩy widget dịch sang trái — và đó mới
        // là điều đúng, vì nó giữ widget nằm trọn trong màn hình. Thử "sửa"
        // bằng `max()` đã làm widget tràn ra ngoài mép phải.
        let cw = (usableW - gutter * CGFloat(cols - 1)) / CGFloat(cols)
        let ch = (usableH - gutter * CGFloat(rows - 1)) / CGFloat(rows)

        var out: [NSPoint] = []
        for r in 0..<rows {
            for c in 0..<cols {
                out.append(NSPoint(
                    x: vf.minX + margin + CGFloat(c) * (cw + gutter) + (cw - size.width) / 2,
                    y: vf.maxY - margin - CGFloat(r) * (ch + gutter) - ch + (ch - size.height) / 2))
            }
        }

        let edges: [NSPoint] = [
            NSPoint(x: vf.minX + margin, y: vf.maxY - margin - size.height),
            NSPoint(x: vf.maxX - margin - size.width, y: vf.maxY - margin - size.height),
            NSPoint(x: vf.minX + margin, y: vf.minY + margin),
            NSPoint(x: vf.maxX - margin - size.width, y: vf.minY + margin),
        ]
        for p in edges
        where !out.contains(where: { abs($0.x - p.x) < 0.5 && abs($0.y - p.y) < 0.5 }) {
            out.append(p)
        }
        return out
    }

    /// Ô gần `origin` nhất — chính là chỗ widget sẽ rơi vào khi thả.
    ///
    /// Trả nil khi không có ô nào (widget to hơn màn hình, chẳng hạn).
    static func nearest(in slots: [NSPoint], to origin: NSPoint) -> Int? {
        var best: Int?
        var bd = CGFloat.greatestFiniteMagnitude
        for (i, p) in slots.enumerated() {
            let d = hypot(p.x - origin.x, p.y - origin.y)
            if d < bd { bd = d; best = i }
        }
        return best
    }
}
