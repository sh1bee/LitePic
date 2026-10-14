import AppKit

/// Một lần nhấn chuột lên widget, từ lúc nhấn xuống đến lúc thả.
///
/// Tách khỏi `DraggableView` để phần rắc rối nhất của ứng dụng — vòng lặp
/// theo dõi sự kiện, ngưỡng thời gian, ngưỡng chuyển động — nằm riêng một chỗ.
///
/// Vì sao tự viết vòng lặp thay vì dùng `sendEvent`:
/// toàn bộ nhấn → giữ → kéo → thả nằm trong một hàm, nên `mouseUp` LUÔN được
/// nhận kể cả khi thả ra ngoài cửa sổ. Nếu rải ra nhiều hàm, một lần thả
/// chuột ở ngoài sẽ làm widget kẹt trạng thái dở dang — lưới còn hiện, widget
/// phóng to kẹt, lần kéo sau khe sai chỗ.
final class DragSession {
    /// Giữ bao lâu thì vào chế độ lưới.
    ///
    /// Đã giảm từ 2.0s xuống 1.2s: ở 2 giây người dùng dễ tưởng app treo và
    /// thả chuột sớm. Log thực đo cho thấy mọi lần thử đều dưới 2s — không ai
    /// chạm tới mốc cũ. 1.2s vẫn đủ dài để phân biệt với kéo tự do.
    static let holdDuration: TimeInterval = 1.2
    /// Đã nhấn, chưa di chuyển bao lâu thì báo "đang giữ" (nhấc nhẹ widget).
    private static let hintDelay: TimeInterval = 0.25
    /// Đã kéo xong, đứng yên bao lâu thì vẫn vào chế độ lưới.
    ///
    /// Sửa theo cách hiểu của người dùng: kéo đi đâu cũng được, nhưng dừng lại
    /// thì lưới hiện. Trước đây cứ chuyển động là huỷ lịch giữ — nên "bấm giữ
    /// rồi kéo" chạy được, còn "kéo rồi dừng" thì không. Giờ cả hai.
    static let settleDuration: TimeInterval = 1.2
    /// Dịch chuyển bao nhiêu thì coi là "đã kéo" (điểm).
    private static let moveThreshold: CGFloat = 3
    /// Bao lâu thức dậy một lần khi vòng lặp không có việc gì để làm.
    private static let watchdogTick: TimeInterval = 0.3
    /// Mất focus liên tục bao lâu thì coi như lần kéo bị bỏ rơi.
    private static let lostFocusGrace: TimeInterval = 1.0
    /// Không có sự kiện nào trong bao lâu thì thả bất kể focus.
    ///
    /// Khoảng này cố tình dài: người dùng cầm widget lên suy nghĩ vài giây là
    /// chuyện thường (đó là lý do có `settleDuration`), còn 30 giây cầm yên
    /// không nhấn nữa thì không phải tương tác thật. Nó bịt nốt lỗ hổng còn
    /// lại: mất focus thì đã xử lý, còn `mouseUp` thất lạc khi app vẫn active
    /// thì chỉ có đồng hồ này bắt được.
    private static let hungTimeout: TimeInterval = 30

    /// Kéo tự do — di chuyển đến đâu đặt bấy nhiêu.
    var onDrag: ((NSPoint) -> Void)?
    /// Kéo trong chế độ lưới — vẫn di chuyển tự do nhưng cần tô sáng ô.
    var onSnapDrag: ((NSPoint) -> Void)?
    var onHint: (() -> Void)?
    var onHintCancel: (() -> Void)?
    var onArmed: (() -> Void)?
    var onDrop: ((DropResult) -> Void)?
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    /// Bấm chuột phải — AppKit gọi thẳng hàm này, không đi qua vòng lặp.
    var onDoubleClick: (() -> Void)?

    private(set) var isPressed = false
    private(set) var isDragging = false

    /// Lệch giữa điểm nhấn và góc cửa sổ, để widget không nhảy khi kéo.
    private var grabOffset: NSPoint = .zero
    private var cursorPushed = false

    /// Bắt đầu theo dõi một lần nhấn. `view` dùng để lấy toạ độ và con trỏ.
    func begin(in view: NSView, event: NSEvent) {
        // Nhấp đúp không vào vòng kéo — cần kiểm trước vì `mouseDown` thứ hai
        // của một cú nhấp đúp vẫn có `clickCount == 2`.
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        guard let w = view.window, let p0 = screenPoint(event, in: w) else { return }
        w.makeKey()
        grabOffset = NSPoint(x: p0.x - w.frame.origin.x, y: p0.y - w.frame.origin.y)

        onBegin?()
        isPressed = true
        isDragging = false
        var hinted = false
        var armed = false
        var moved = false
        var lastMove = Date()
        let t0 = Date()
        /// Lúc bắt đầu có một khoảng lặng dài bất thường — dùng để đòi lại
        /// quyền kiểm soát nếu app đã mất focus.
        var silentSince: Date? = nil

        // Mọi đường thoát đều đi qua đây: trả cursor, hạ cờ.
        defer {
            if cursorPushed { NSCursor.pop(); cursorPushed = false }
            isPressed = false
            isDragging = false
            onEnd?()
        }

        while true {
            // Hẹn mốc cho lần giữ/đứng yên kế tiếp.
            // Chưa kéo  -> đếm từ lúc nhấn.
            // Đã kéo    -> đếm từ lần chuyển động gần nhất, nên kéo xong dừng
            //              lại vẫn bật được lưới.
            var deadline: Date? = nil
            if !moved {
                if !hinted { deadline = t0.addingTimeInterval(Self.hintDelay) }
                else if !armed { deadline = t0.addingTimeInterval(Self.holdDuration) }
            } else if !armed {
                deadline = lastMove.addingTimeInterval(Self.settleDuration)
            } else {
                // Đã kéo và đã bật lưới: không còn mốc hẹn nào, nên `nextEvent`
                // sẽ chặn vô hạn đợi `mouseUp`. Đó là chỗ dễ kẹt — xem bên dưới.
                deadline = Date().addingTimeInterval(Self.watchdogTick)
            }

            guard let e = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                          until: deadline,
                                          inMode: .eventTracking,
                                          dequeue: true) else {
                if !armed {
                    if !hinted {
                        hinted = true
                        onHint?()
                    } else {
                        armed = true
                        onArmed?()
                    }
                    continue
                }
                // Chó canh: đã bật lưới mà không nhận được sự kiện nào.
                //
                // Vì sao cần: `begin()` chỉ ra khỏi vòng lặp khi nhận
                // `.leftMouseUp`. Đo được trước khi sửa: thả chuột "cứu tinh"
                // post vào giây thứ 6 thì vòng lặp mới ra; không có nó thì treo
                // — `isDragging` kẹt `true`, widget dính theo con trỏ, và con
                // trỏ bàn tay nắm kẹt trong ngăn xếp đến hết phiên.
                //
                // Cần nói rõ điều KHÔNG phải nguyên nhân: trên macOS, `mouseUp`
                // không bị mất khi app mất focus — app đã nhận `mouseDown` thì giữ
                // mouse grab, nên Cmd+Tab rồi thả chuột vẫn thả bình thường. Nên
                // kịch bản "mất focus là kẹt" không thành. Cái thật sự treo là khi
                // sự kiện bị mất theo kiểu khác (màn hình ngủ giữa chừng chẳng
                // hạn), và nó không phản ứng gì với Cmd+Tab.
                //
                // Vì vậy chỉ thả khi **mất focus** — lúc đang kéo bình thường
                // (app luôn active vì `makeKey()` ở trên) thì không bao giờ bị
                // đụng, và người dùng cứ cầm widget lên suy nghĩ bao lâu cũng được.
                if silentSince == nil { silentSince = Date() }
                else if let s = silentSince {
                    let quiet = Date().timeIntervalSince(s)
                    if quiet > Self.hungTimeout || (!NSApp.isActive && quiet > Self.lostFocusGrace) {
                        onDrop?(.free)  // coi nhu bo roi: tha tu do, khong khe
                        return
                    }
                }
                continue
            }
            silentSince = nil

            if e.type == .leftMouseUp {
                if moved {
                    onDrop?(armed ? .snap : .free)
                } else if armed {
                    onDrop?(.snap)   // giữ đủ lâu rồi thả tại chỗ: khe tại chỗ
                } else {
                    if hinted { onHintCancel?() }
                    onDrop?(.click)
                }
                return
            }

            guard e.type == .leftMouseDragged, let p = screenPoint(e, in: w) else { continue }
            if !moved {
                if hypot(p.x - p0.x, p.y - p0.y) <= Self.moveThreshold { continue }
                moved = true
                isDragging = true
                NSCursor.closedHand.push()
                cursorPushed = true
                if !armed, hinted { onHintCancel?() }
            }
            lastMove = Date()
            let origin = NSPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y)
            if armed { onSnapDrag?(origin) } else { onDrag?(origin) }
        }
    }

    /// Vị trí chuột theo toạ độ màn hình.
    ///
    /// Ưu tiên toạ độ trong event (đúng khi event thuộc về cửa sổ này, gồm cả
    /// event dựng sẵn trong kiểm thử). Nếu event thuộc cửa sổ khác — xảy ra khi
    /// rê ra ngoài màn hình nền giữa lúc kéo — dùng vị trí con trỏ toàn cục.
    private func screenPoint(_ event: NSEvent, in w: NSWindow) -> NSPoint? {
        if event.windowNumber == w.windowNumber {
            return w.convertPoint(toScreen: event.locationInWindow)
        }
        return NSEvent.mouseLocation
    }
}
