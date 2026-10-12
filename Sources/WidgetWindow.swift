import AppKit

/// Kết quả của một lần nhấn chuột trái trên widget.
enum DropResult {
    case click  // bấm rồi thả, không di chuyển
    case free   // kéo ngay: đặt tự do
    case snap   // giữ đủ lâu rồi kéo/thả: khe vào lưới
}

/// View nhận chuột để kéo widget, và nhận chuột phải để mở menu.
///
/// Tương tác lai, giống widget macOS:
///   - Kéo ngay        -> đặt tự do, không bám lưới.
///   - Giữ yên 2 giây -> hiện toàn bộ lưới, thả xuống tự khe vào ô gần nhất.
///
/// Toàn bộ một lần nhấn (giữ -> kéo -> thả) được xử lý trong vòng lặp theo dõi
/// sự kiện ngay bên trong `mouseDown`. Cách này đảm bảo `mouseUp` luôn được
/// nhận — kể cả khi thả chuột ở ngoài cửa sổ — nên không bao giờ kẹt ở trạng
/// thái dở dang (lưới ma, widget phóng to kẹt, khe sai ở lần kéo sau).
final class DraggableView: NSView {
    var onDrag: ((NSPoint) -> Void)?
    var onSnapDrag: ((NSPoint) -> Void)?
    var onDrop: ((DropResult) -> Void)?
    /// Sau ~0.45s giữ yên: báo "sắp vào chế độ lưới".
    var onHoldTick: (() -> Void)?
    /// Đã báo chờ nhưng người dùng kéo luôn trước 2s: gỡ hiệu ứng chờ.
    var onHoldCancel: (() -> Void)?
    /// Giữ đủ 2s: bật chế độ lưới và hiện toàn bộ ô.
    var onLongPress: (() -> Void)?
    /// Menu hiện khi bấm chuột phải — AppController gắn vào sau init.
    var contextMenu: NSMenu?

    static let holdDuration: TimeInterval = 2.0
    private static let hintDelay: TimeInterval = 0.45
    private static let moveThreshold: CGFloat = 3

    /// Đang giữ chuột / đang kéo. WidgetWindow dùng để hoãn đổi ảnh giữa chừng.
    private(set) var isPressed = false
    private(set) var isDragging = false

    private var grabOffset: NSPoint = .zero
    private var tracking: NSTrackingArea?
    private var hoverPushed = false
    private var dragCursorPushed = false

    /// Mấu chốt để kéo hoạt động: `NSImageView` phủ kín toàn bộ cửa sổ, nên mặc
    /// định hit-test trả về chính imageView và các sự kiện chuột không bao giờ
    /// tới `DraggableView`. Mọi điểm trong biên đều trả về `self`.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    /// Bấm chuột phải: AppKit tự gọi hàm này và hiện menu trả về.
    override func menu(for event: NSEvent) -> NSMenu? { contextMenu }

    override func rightMouseDown(with event: NSEvent) {
        guard let m = contextMenu else { return }
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let area = NSTrackingArea(rect: bounds,
                                 options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isPressed, !isDragging, !hoverPushed else { return }
        NSCursor.pointingHand.push()
        hoverPushed = true
    }

    override func mouseExited(with event: NSEvent) {
        guard hoverPushed else { return }
        // Trong lúc kéo, cửa sổ trượt dưới con trỏ đứng yên cũng sinh ra
        // entered/exited — bỏ qua để không làm lệch ngăn xếp cursor.
        guard !isPressed, !isDragging else { return }
        NSCursor.pop()
        hoverPushed = false
    }

    /// Vị trí chuột theo toạ độ màn hình.
    ///
    /// Ưu tiên toạ độ trong event (đúng khi event thuộc về cửa sổ này, gồm cả
    /// event dựng sẵn trong kiểm thử). Nếu event thuộc cửa sổ khác — xảy ra khi
    /// rê ra ngoài màn hình nền giữa lúc kéo — dùng vị trí con trỏ toàn cục.
    private func screenPoint(_ event: NSEvent) -> NSPoint? {
        guard let w = window else { return nil }
        if event.windowNumber == w.windowNumber {
            return w.convertPoint(toScreen: event.locationInWindow)
        }
        return NSEvent.mouseLocation
    }

    override func mouseDown(with event: NSEvent) {
        guard let w = window, let p0 = screenPoint(event) else { return }
        w.makeKey()
        grabOffset = NSPoint(x: p0.x - w.frame.origin.x, y: p0.y - w.frame.origin.y)

        isPressed = true
        isDragging = false
        var hinted = false
        var armed = false
        var moved = false
        let t0 = Date()

        // Mọi đường thoát đều đi qua đây: trả cursor, hạ cờ.
        defer {
            if dragCursorPushed { NSCursor.pop(); dragCursorPushed = false }
            // Chuột có thể đã ra ngoài view lúc thả: đồng bộ lại hover.
            if hoverPushed, let w2 = window,
               !bounds.contains(convert(w2.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)) {
                NSCursor.pop()
                hoverPushed = false
            }
            isPressed = false
            isDragging = false
        }

        while true {
            // Hạn chờ cho mốc tiếp theo — chỉ khi chưa di chuyển.
            var deadline: Date? = nil
            if !moved {
                if !hinted { deadline = t0.addingTimeInterval(Self.hintDelay) }
                else if !armed { deadline = t0.addingTimeInterval(Self.holdDuration) }
            }
            guard let e = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                          until: deadline,
                                          inMode: .eventTracking,
                                          dequeue: true) else {
                if !moved {
                    if !hinted { hinted = true; onHoldTick?(); continue }
                    if !armed { armed = true; onLongPress?(); continue }
                }
                continue
            }

            if e.type == .leftMouseUp {
                if moved {
                    onDrop?(armed ? .snap : .free)
                } else if armed {
                    onDrop?(.snap)   // giữ đủ lâu rồi thả tại chỗ: khe tại chỗ
                } else {
                    if hinted { onHoldCancel?() }
                    onDrop?(.click)
                }
                return
            }

            guard e.type == .leftMouseDragged, let p = screenPoint(e) else { continue }
            if !moved {
                if hypot(p.x - p0.x, p.y - p0.y) <= Self.moveThreshold { continue }
                moved = true
                isDragging = true
                NSCursor.closedHand.push()
                dragCursorPushed = true
                // Di chuyển trước khi giữ đủ lâu -> huỷ hẹn giữ, kéo tự do.
                if !armed, hinted { onHoldCancel?() }
            }
            let origin = NSPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y)
            if armed { onSnapDrag?(origin) } else { onDrag?(origin) }
        }
    }
}

/// Lớp phủ trong suốt hiện toàn bộ ô lưới khi đang ở chế độ lưới, để thấy rõ
/// widget sẽ rơi vào chỗ nào thay vì đoán mò.
final class GridOverlay {
    private let window: NSWindow
    private let host = NSView()
    private var slotViews: [NSView] = []

    init(level: NSWindow.Level) {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = level
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        host.wantsLayer = true
        window.contentView = host
    }

    var isVisible: Bool { window.isVisible }

    func show(slots: [NSPoint], size: NSSize, corner: CGFloat, on screen: NSScreen) {
        for v in host.subviews { v.removeFromSuperview() }
        slotViews = slots.map { origin in
            let v = NSView(frame: NSRect(x: origin.x - screen.frame.minX,
                                         y: origin.y - screen.frame.minY,
                                         width: size.width, height: size.height))
            v.wantsLayer = true
            v.layer?.cornerRadius = corner
            v.layer?.cornerCurve = .continuous
            v.layer?.borderWidth = 1.5
            v.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
            v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            host.addSubview(v)
            return v
        }
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
    }

    func highlight(index: Int?) {
        for (i, v) in slotViews.enumerated() {
            let on = (i == index)
            v.layer?.borderWidth = on ? 2.5 : 1.5
            v.layer?.borderColor = on
                ? NSColor.controlAccentColor.cgColor
                : NSColor.white.withAlphaComponent(0.5).cgColor
            v.layer?.backgroundColor = on
                ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
                : NSColor.white.withAlphaComponent(0.07).cgColor
        }
    }

    func hide() { window.orderOut(nil) }
}

/// Cửa sổ widget: bo tròn, có bóng, kéo tự do hoặc giữ 2s để khe lưới.
final class WidgetWindow {
    private let settings = Settings.shared
    let window: NSWindow
    private let container: DraggableView
    private let imageView: NSImageView
    private let overlay = GridOverlay(level: NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 21))

    private static let pad: CGFloat = 20
    private static let widgetLevel: NSWindow.Level = {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 20)
    }()

    private var imageSize = NSSize(width: 400, height: 300)
    private var settled = false
    private var snapMode = false
    private var activeSlots: [NSPoint] = []
    private weak var activeScreen: NSScreen?

    /// Đang giữ chuột hoặc đang kéo — AppController hoãn đổi ảnh lúc này để
    /// cửa sổ không bị giật khỏi tay người dùng.
    var busy: Bool { container.isPressed || container.isDragging }

    init() {
        let view = DraggableView(frame: NSRect(x: 0, y: 0, width: 440, height: 340))
        container = view

        let w = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        window = w

        let iv = NSImageView(frame: NSRect(x: Self.pad, y: Self.pad, width: 400, height: 300))
        iv.autoresizingMask = []
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.imageAlignment = .alignCenter
        iv.wantsLayer = true
        imageView = iv

        w.contentView = view
        view.addSubview(iv)

        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = Self.widgetLevel
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.hidesOnDeactivate = false
        w.alphaValue = settings.opacity
        w.ignoresMouseEvents = false
        w.orderOut(nil)

        view.onDrag = { [weak self] o in self?.dragFree(to: o) }
        view.onSnapDrag = { [weak self] o in self?.dragSnapped(to: o) }
        view.onDrop = { [weak self] r in self?.finishDrop(r) }
        view.onHoldTick = { [weak self] in self?.holdHint() }
        view.onHoldCancel = { [weak self] in self?.cancelHoldHint() }
        view.onLongPress = { [weak self] in self?.armSnapMode() }

        applyAppearance()
        restorePosition()
        layout()
    }

    /// Menu chuột phải trên widget. AppController gắn menu riêng (không dùng
    /// chung instance với menu thanh menu để tránh xung đột hiển thị).
    func setContextMenu(_ menu: NSMenu?) { container.contextMenu = menu }

    // MARK: - Ngoại hình

    private func applyAppearance() {
        let r = settings.cornerRadius
        container.layer?.cornerRadius = r
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = false
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.34
        container.layer?.shadowRadius = 14
        container.layer?.shadowOffset = CGSize(width: 0, height: -6)

        imageView.layer?.cornerRadius = r
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
    }

    private func lift(_ scale: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            container.layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    var displayMaxPixel: CGFloat {
        let scale = settings.renderScale
        switch settings.sizeMode {
        case .fitImage: return settings.maxEdge * scale
        case .fitWidth: return settings.width * scale
        case .fixed:    return max(settings.width, settings.height) * scale
        }
    }

    func applyOpacity() { window.alphaValue = settings.opacity }

    private func layout() {
        window.setContentSize(NSSize(width: imageSize.width + Self.pad * 2,
                                     height: imageSize.height + Self.pad * 2))
        container.frame = container.bounds
        imageView.frame = NSRect(x: Self.pad, y: Self.pad,
                                 width: imageSize.width, height: imageSize.height)
    }

    // MARK: - Hiển thị

    func show(_ url: URL, evenIfBusy: Bool = false) {
        // Đang kéo mà đổi ảnh thì cửa sổ đổi kích thước và giật khỏi tay
        // người dùng — hoãn lại (AppController sẽ thử lại sau vài giây).
        guard evenIfBusy || !busy else { return }
        guard let px = ImageStore.pixelSize(of: url) else { return }
        let aspect = px.width / px.height
        guard aspect.isFinite, aspect > 0 else { return }

        let target: NSSize
        switch settings.sizeMode {
        case .fixed:
            target = NSSize(width: settings.width, height: settings.height)
        case .fitWidth:
            target = NSSize(width: settings.width, height: (settings.width / aspect).rounded())
        case .fitImage:
            let m = settings.maxEdge
            target = aspect >= 1
                ? NSSize(width: m, height: (m / aspect).rounded())
                : NSSize(width: (m * aspect).rounded(), height: m)
        }

        guard let img = ImageStore.thumbnail(of: url, maxPixel: displayMaxPixel) else { return }
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)

        imageView.image = nil
        imageView.image = img
        imageSize = target
        applyAppearance()
        layout()
        window.alphaValue = settings.opacity

        var f = window.frame
        f.origin = NSPoint(x: center.x - f.width / 2, y: center.y - f.height / 2)
        window.setFrameOrigin(clampToVisibleScreen(f.origin))
        // Vị trí thực đã đổi theo kích thước ảnh mới — lưu lại để lần mở sau
        // không nhảy về chỗ cũ.
        settings.savedOrigin = window.frame.origin
        window.orderFrontRegardless()

        if !settled {
            settled = true
            settle()
        }
    }

    func applyAll() {
        applyAppearance()
        layout()
        window.alphaValue = settings.opacity
    }

    // MARK: - Lưới

    /// Màn hình đang chứa widget — không phải lúc nào cũng là `NSScreen.main`
    /// (main là màn hình có menu bar, còn widget có thể bị kéo sang màn khác).
    private func currentScreen() -> NSScreen? {
        let c = NSPoint(x: window.frame.midX, y: window.frame.midY)
        return NSScreen.screens.first { NSMouseInRect(c, $0.frame, false) } ?? NSScreen.main
    }

    /// Lưới tính theo kích thước widget (ô phải vừa để chứa), cộng thêm bốn ô
    /// sát mép màn hình vì đó là chỗ đặt người dùng hay chọn nhất.
    private func snapSlots(size: NSSize, on s: NSScreen) -> [NSPoint] {
        let vf = s.visibleFrame
        let margin: CGFloat = 36
        let gutter: CGFloat = 18
        let usableW = vf.width - margin * 2
        let usableH = vf.height - margin * 2

        let cols = max(1, min(6, Int((usableW + gutter) / (size.width + gutter))))
        let rows = max(1, min(4, Int((usableH + gutter) / (size.height + gutter))))
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
        for p in edges where !out.contains(where: { abs($0.x - p.x) < 0.5 && abs($0.y - p.y) < 0.5 }) {
            out.append(p)
        }
        return out
    }

    private func nearestIndex(in slots: [NSPoint], to origin: NSPoint) -> Int? {
        var best: Int? = nil
        var bd = CGFloat.greatestFiniteMagnitude
        for (i, p) in slots.enumerated() {
            let d = hypot(p.x - origin.x, p.y - origin.y)
            if d < bd { bd = d; best = i }
        }
        return best
    }

    /// Tính lại lưới khi đổi màn hình giữa lúc kéo. Cùng một mảng `activeSlots`
    /// được dùng cho cả highlight lẫn thả — không bao giờ lệch nhau.
    private func ensureSlots() {
        guard let s = currentScreen() else { return }
        if activeScreen !== s || activeSlots.isEmpty {
            activeScreen = s
            activeSlots = snapSlots(size: window.frame.size, on: s)
        }
    }

    private func settle() {
        // Người dùng tắt khe lưới thì lần mở sau giữ đúng chỗ cũ, chỉ kẹp
        // trong màn hình — không ép vào ô.
        guard settings.snapToGrid else {
            window.setFrameOrigin(clampToVisibleScreen(window.frame.origin))
            return
        }
        ensureSlots()
        if let i = nearestIndex(in: activeSlots, to: window.frame.origin) {
            window.setFrameOrigin(activeSlots[i])
            settings.savedOrigin = window.frame.origin
        }
    }

    /// Kéo về ô lưới ngay — dùng khi người dùng bật chế độ khe từ menu.
    func settleNow() { settle() }

    // MARK: - Kéo

    /// Giữ ~0.45s: nhấc nhẹ widget để báo hiệu "đang chờ vào chế độ lưới".
    private func holdHint() { lift(1.03) }

    private func cancelHoldHint() { lift(1.0) }

    /// Giữ đủ 2s: bật chế độ lưới và hiện toàn bộ ô hợp lệ.
    private func armSnapMode() {
        snapMode = true
        lift(1.06)
        activeScreen = nil
        ensureSlots()
        guard let s = activeScreen, !activeSlots.isEmpty else { return }
        overlay.show(slots: activeSlots, size: window.frame.size,
                     corner: settings.cornerRadius, on: s)
        overlay.highlight(index: nearestIndex(in: activeSlots, to: window.frame.origin))
    }

    private func dragFree(to origin: NSPoint) {
        window.setFrameOrigin(clampToVisibleScreen(origin))
    }

    private func dragSnapped(to origin: NSPoint) {
        window.setFrameOrigin(clampToVisibleScreen(origin))
        // Kéo sang màn hình khác giữa chừng thì tính lại lưới cho màn đó.
        let before = activeScreen
        ensureSlots()
        if activeScreen !== before, let s = activeScreen {
            overlay.show(slots: activeSlots, size: window.frame.size,
                         corner: settings.cornerRadius, on: s)
        }
        overlay.highlight(index: nearestIndex(in: activeSlots, to: window.frame.origin))
    }

    private func finishDrop(_ result: DropResult) {
        overlay.hide()
        lift(1.0)
        snapMode = false
        activeScreen = nil

        switch result {
        case .snap:
            ensureSlots()
            if let i = nearestIndex(in: activeSlots, to: window.frame.origin) {
                window.setFrameOrigin(activeSlots[i])
            }
            settings.savedOrigin = window.frame.origin
        case .free:
            // Kéo tự do: giữ đúng chỗ người dùng thả.
            settings.savedOrigin = window.frame.origin
        case .click:
            break
        }
    }

    // MARK: - Vị trí

    private func restorePosition() {
        if let o = settings.savedOrigin {
            window.setFrameOrigin(o)
            return
        }
        guard let s = NSScreen.main?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(x: s.maxX - window.frame.width - 36,
                                     y: s.maxY - window.frame.height - 36))
    }

    private func clampToVisibleScreen(_ origin: NSPoint) -> NSPoint {
        guard let s = currentScreen()?.visibleFrame else { return origin }
        let f = window.frame.size
        let m: CGFloat = 4
        return NSPoint(
            x: min(max(origin.x, s.minX + m), max(s.minX + m, s.maxX - f.width - m)),
            y: min(max(origin.y, s.minY + m), max(s.minY + m, s.maxY - f.height - m))
        )
    }
}
