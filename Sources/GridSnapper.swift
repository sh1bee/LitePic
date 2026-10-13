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
    /// **Ô đè lên nhau một nửa**: bước nhảy bằng `nửa cỡ widget`, nên widget
    /// đặt được lệch ra nửa ô — chọn được nhiều chỗ hơn hẳn lưới thưa (bước =
    /// cả cỡ widget), vốn chỉ cho vài vị trí "bắt vào".
    ///
    /// Cộng thêm bốn ô sát mép màn hình — đó là chỗ người dùng hay đặt widget
    /// nhất. Ô sát mép trùng với ô lưới thì bỏ, tránh hai chỗ chồng nhau.
    ///
    /// Mỗi ô đúng bằng `size`. Cỡ này do `WidgetWindow` truyền vào lúc giơ
    /// lưới nên widget vừa đổi ảnh (đổi tỉ lệ, đổi cỡ) thì ô bám theo ngay —
    /// không phải kích thước cứng từ lúc dựng.
    static func slots(widgetSize size: NSSize, visibleFrame vf: NSRect) -> [NSPoint] {
        let margin: CGFloat = 36
        guard size.width > 0, size.height > 0 else { return [] }
        // Widget to hơn vùng dùng được thì không ô nào vừa — trả rỗng để
        // `armSnapMode` bỏ qua lưới, thay vì vẽ ô tràn ra ngoài màn hình.
        let spanX = vf.width - margin * 2 - size.width
        let spanY = vf.height - margin * 2 - size.height
        guard spanX >= 0, spanY >= 0 else { return [] }

        // Widget nhỏ trên màn hình lớn thì lưới nửa-ô có thể lên hàng trăm ô,
        // mỗi ô một lớp — vừa nặng vừa rối mắt. Có trần số ô; vượt trần thì
        // giãn bước nhảy cho tới khi vừa. Khi số ô vừa phải thì giữ nguyên
        // nửa-ô.
        let maxCells = 240
        func count(span: CGFloat, step: CGFloat) -> Int {
            span <= 0 ? 1 : Int(span / step) + 1
        }
        var stepX = size.width / 2
        var stepY = size.height / 2
        while count(span: spanX, step: stepX) * count(span: spanY, step: stepY) > maxCells {
            stepX *= 1.2
            stepY *= 1.2
        }

        let nx = count(span: spanX, step: stepX)
        let ny = count(span: spanY, step: stepY)
        var out: [NSPoint] = []
        out.reserveCapacity(nx * ny + 4)
        for r in 0..<ny {
            for c in 0..<nx {
                out.append(NSPoint(
                    x: vf.minX + margin + CGFloat(c) * stepX,
                    y: vf.maxY - margin - size.height - CGFloat(r) * stepY))
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