import AppKit

/// Kết quả của một lần nhấn chuột trái trên widget.
enum DropResult {
    case click  // bấm rồi thả, không di chuyển
    case free   // kéo ngay: đặt tự do
    case snap   // giữ đủ lâu rồi kéo/thả: khe vào lưới
}

/// View phủ kín cửa sổ widget: nhận chuột để kéo, chuột phải để mở menu,
/// rê chuột để hiện nút, và nhận file thả từ Finder.
///
/// Phần xử lý nhấn – giữ – kéo – thả nằm ở `DragSession`; class này chỉ làm
/// nhiệm vụ chuyển sự kiện của AppKit sang callback.
final class DraggableView: NSView {
    /// Menu hiện khi bấm chuột phải — AppController gắn vào sau init.
    var contextMenu: NSMenu?
    /// Báo rê chuột vào/ra widget để hiện/ẩn nút điều khiển.
    var onHover: ((Bool) -> Void)?
    /// Người dùng thả file/thư mục từ Finder vào widget.
    var onFilesDropped: (([URL]) -> Void)?

    /// Phiên kéo hiện tại.
    let session = DragSession()

    private var tracking: NSTrackingArea?
    private var hoverPushed = false

    var isPressed: Bool { session.isPressed }
    var isDragging: Bool { session.isDragging }

    /// Mấu chốt để kéo hoạt động: `ImageCanvas` phủ kín toàn bộ cửa sổ, nên mặc
    /// định hit-test trả về chính imageView và các sự kiện chuột không bao giờ
    /// tới `DraggableView`. Mọi điểm trong biên đều trả về `self`.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        session.begin(in: self, event: event)
    }

    // MARK: - Kéo thả từ Finder

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Thả đúng lên cụm nút thì không nhận — nếu không, thả ảnh lên nút
        // "giai tiếp" sẽ bị hiểu thành đổi ảnh thay vì nhận file.
        if let c = subviews.compactMap({ $0 as? WidgetControls }).first,
           !c.isHidden,
           c.frame.contains(convert(sender.draggingLocation, from: nil)) {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }

    // MARK: - Menu và rê chuột

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
        onHover?(true)
        guard !isPressed, !isDragging, !hoverPushed else { return }
        NSCursor.pointingHand.push()
        hoverPushed = true
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
        guard hoverPushed else { return }
        // Trong lúc kéo, cửa sổ trượt dưới con trỏ đứng yên cũng sinh ra
        // entered/exited — bỏ qua để không làm lệch ngăn xếp cursor.
        guard !isPressed, !isDragging else { return }
        popHoverCursorIfNeeded()
    }

    /// Trả con trỏ rê nếu đang giữ. Tách riêng vì `DragSession` cần gọi lúc
    /// kết thúc một lần nhấn, khi `mouseExited` có thể đã không tới.
    func popHoverCursorIfNeeded() {
        guard hoverPushed else { return }
        NSCursor.pop()
        hoverPushed = false
    }
}

/// Lớp phủ trong suốt hiện toàn bộ ô lưới khi đang ở chế độ lưới, để thấy rõ
/// widget sẽ rơi vào chỗ nào thay vì đoán mò.
/// Toàn cảnh vẽ ô lưới khi kéo.
///
/// Mặc định **không vẽ ô**. Người dùng bảo 81 ô trắng chồng nhau rối mắt, nên
/// chỉ còn vẽ ô đang ngắm. Muốn bật lại thì đổi `drawAllSlots` thành `true` —
/// phần vẽ vẫn còn nguyên, không xoá gì.
final class GridOverlay {
    /// Bật/tắt việc vẽ TOÀN BỘ ô. `false` = chỉ vẽ ô đang ngắm.
    private static let drawAllSlots = false

    private let window: NSWindow
    private let host = NSView()
    private var slotViews: [NSView] = []
    /// Ô đang sáng — để lần tới chỉ vẽ lại đúng ô vừa bỏ sáng và ô vừa sáng.
    private var highlighted: Int?

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

    /// Bám theo tầng của widget + 1 để lưới luôn nằm ngay trên nó.
    func setLevel(_ base: NSWindow.Level) { window.level = base + 1 }

    func show(slots: [NSPoint], size: NSSize, corner: CGFloat, on screen: NSScreen) {
        for v in host.subviews { v.removeFromSuperview() }
        highlighted = nil
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
            // Tắt vẽ thì ô không hiện, nhưng vẫn giữ trong `slotViews` để
            // `highlight()` tô sáng ô đang ngắm hoạt động như cũ.
            v.isHidden = !Self.drawAllSlots
            host.addSubview(v)
            return v
        }
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        // `display: true` trên đã đủ, nhưng `orderFrontRegardless` không bảo đảm
        // vẽ lại khi cửa sổ đã hiện sẵn từ trước. Gọi display rõ ràng để chắc.
        window.displayIfNeeded()
    }

    /// Tô sáng ô đang ngắm.
    ///
    /// Chỉ chạm vào tối đa 2 lớp thay vì cả 8. Bản cũ lặp qua toàn bộ ô và đặt
    /// lại `borderWidth`/`borderColor`/`backgroundColor` cho từng ô — mỗi lần
    /// đặt là một lần lớp phải vẽ lại. Hàm này được gọi theo MỌI sự kiện rê
    /// chuột trong lúc kéo chế độ lưới, tức hàng trăm lần mỗi lần kéo.
    func highlight(index: Int?) {
        if let was = highlighted, was != index {
            paint(slotViews[was], on: false)
        }
        if let now = index, slotViews.indices.contains(now) {
            paint(slotViews[now], on: true)
        }
        highlighted = index
    }

    private func paint(_ v: NSView, on: Bool) {
        guard let l = v.layer else { return }
        // Khi tắt vẽ toàn bộ ô thì ô đang ngắm vẫn phải hiện — nếu không,
        // người dùng không thấy chỗ nó sẽ rơi vào, và lưới thành vô dụng.
        v.isHidden = !on && !Self.drawAllSlots
        l.borderWidth = on ? 2.5 : 1.5
        l.borderColor = on
            ? NSColor.controlAccentColor.cgColor
            : NSColor.white.withAlphaComponent(0.5).cgColor
        l.backgroundColor = on
            ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
            : NSColor.white.withAlphaComponent(0.07).cgColor
    }

    func hide() {
        highlighted = nil
        window.orderOut(nil)
    }
}

/// Toan cảnh vẽ ảnh — tự vẽ trong `draw(_:)` thay vì đặt `layer.contents` tay.
///
/// VÌ SAO KHÔNG DÙNG `NSImageView`: `layer.contents` là ô nhớ do AppKit quản
/// lý. Mỗi lần AppKit vẽ lại view (rất dễ xảy ra khi lớp cha đổi transform —
/// tức lúc widget "nâng" lên khi bạn giữ chuột), `draw()` của `NSImageView`
/// chạy với không có `image` và **xoá sạch `contents`**. Widget mất trắng: cửa
/// sổ vẫn còn, vẫn bấm và chuột phải được, nhưng không còn gì để vẽ — và chỉ
/// tới lần đổi ảnh kế tiếp mới hiện lại.
///
/// Tự vẽ trong `draw(_:)` thì AppKit vẽ lại bao nhiêu lần cũng ra đúng ảnh.
/// Đổi lại là mỗi lần vẽ lại phải tự tính phép vỉa cắt, và AppKit tự lo phần
/// Retina nên không cần `contentsScale` đặt tay nữa.
///
/// Bo góc cũng vẽ tại đây, **không** dùng `layer.cornerRadius` + `masksToBounds`:
/// khi lớp cha có transform (đúng lúc widget "nâng" lên khi giữ chuột) thì cái
/// khoén bo của lớp con hay bị mất — chỉ một góc thoát được, ba góc thành vuông.
/// Cắt trong `draw` thì bo góc là một phần của nét vẽ nên luôn bền.
final class ImageCanvas: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    /// Phủ kín và cắt bớt phần thừu, thay vì vừa khung giữ nguyên tỉ lệ.
    var fill = false { didSet { needsDisplay = true } }
    /// Bán kính bo góc, vẽ tay trong `draw(_:)`.
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let img = image else { return }
        let sz = img.size
        guard sz.width > 0, sz.height > 0 else { return }
        let r = bounds
        if cornerRadius > 0 {
            NSBezierPath(roundedRect: r, xRadius: cornerRadius,
                         yRadius: cornerRadius).addClip()
        }
        // `isFlipped` nên `midY` của `bounds` vẫn là tâm — tính tâm là đủ, khỏi
        // phải nhớ chiều trục.
        let k = fill ? max(r.width / sz.width, r.height / sz.height)
                     : min(r.width / sz.width, r.height / sz.height)
        let target = NSRect(x: r.midX - sz.width * k / 2,
                            y: r.midY - sz.height * k / 2,
                            width: sz.width * k, height: sz.height * k)
        img.draw(in: target, from: .zero, operation: .copy, fraction: 1,
                 respectFlipped: true, hints: nil)
    }
}

/// Cửa sổ widget: bo tròn, có bóng, kéo tự do hoặc giữ 2s để khe lưới.
final class WidgetWindow {
    private let settings = Settings.shared
    let window: NSWindow
    private let container: DraggableView
    private let imageView: ImageCanvas
    /// Lớp ảnh thứ hai, chồm lên lớp đầu — dùng để chuyển ảnh mềm.
    private let topView: ImageCanvas
    private let overlay = GridOverlay(level: WidgetWindow.desktopLevel + 1)

    /// Tầng cho chế độ "Trên wallpaper (dưới app)".
    ///
    /// KHÔNG dùng `desktopWindow + 20`. Trên máy này:
    ///
    /// ```
    /// kCGDesktopWindowLevel     = -2147483623
    /// kCGDesktopIconWindowLevel = -2147483603
    /// kCGMinimumWindowLevel     = -2147483643
    /// kCGNormalWindowLevel      =          0
    /// ```
    ///
    /// `desktopWindow + 20` ra đúng `-2147483603` — **trùng khớp tầng desktop
    /// icon**. Đo thực nghiệm cho thấy mọi tầng ≤ `-2147483602` đều bị hệ thống
    /// xếp vào loại **"desktop element"**: cửa sổ biến mất khỏi `CGWindowList`
    /// với bộ lọc chuẩn, nên tự động hoá, công cụ chụp màn hình và trình quản
    /// lý cửa sổ đều không thấy nó.
    ///
    /// `desktopIcon + 2` là mức **thấp nhất** vẫn còn là cửa sổ bình thường, và
    /// vẫn nằm dưới mọi cửa sổ app (0) — đúng nghĩa "dưới app".
    private static let desktopLevel: NSWindow.Level = {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
    }()

    /// Tầng thực tế đang dùng — `floating` cao hơn cửa sổ app (0) nên luôn bấm được.
    private var activeLevel: NSWindow.Level {
        switch settings.levelMode {
        case .desktop:  return Self.desktopLevel
        case .floating: return .floating
        }
    }

    private let controls = WidgetControls()
    private var imageSize = NSSize(width: 400, height: 300)
    /// Ảnh đang hiện, để mở trong Finder.
    private var currentURL: URL?
    /// Ảnh đang hiện. Giữ riêng vì `imageView.image` để trống — phần vẽ do
    /// layer đảm nhiệm (xem `refreshImageLayer`).
    private var currentImage: NSImage?
    private var settled = false

    /// Số thứ tự lần hiện ảnh. Lần mới hơn làm lần cũ mất hiệu lực — cần khi
    /// người dùng bấm ‹ › liên tục trong lúc bộ giải mã còn đang chạy, nếu không
    /// ảnh sẽ về đúng thứ tự ngược với nút đã bấm.
    private var showToken = 0

    /// Khoảng trống chừa quanh ảnh cho khung hiện tại.
    private var frameInset: CGFloat { settings.frameStyle.inset }
    private var frameBottom: CGFloat { settings.frameStyle.extraBottom }
    private var framePad: CGFloat { settings.frameStyle.pad }
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

        // Vị trí thật do `layout()` đặt; ở đây chỉ cần một khung tạm cho tới lúc đó.
        let iv = ImageCanvas(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        iv.autoresizingMask = []
        iv.wantsLayer = true
        iv.layer?.opacity = 0      // lớp dưới: luôn trong suốt
        imageView = iv

        // Lớp trên: chỉ hiện khi đang chuyển ảnh. Hai lớp chồng nhau là cách
        // crossfade rẻ nhất — chỉ animate `opacity`, không đụng ảnh.
        let ivTop = ImageCanvas(frame: iv.frame)
        ivTop.autoresizingMask = []
        ivTop.wantsLayer = true
        ivTop.layer?.opacity = 1
        topView = ivTop

        w.contentView = view
        view.addSubview(iv)
        view.addSubview(topView)
        controls.isHidden = true
        view.addSubview(controls)

        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = activeLevel
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.hidesOnDeactivate = false
        w.alphaValue = settings.opacity
        w.ignoresMouseEvents = false
        w.orderOut(nil)

        let s = view.session
        s.onDrag = { [weak self] o in self?.dragFree(to: o) }
        s.onSnapDrag = { [weak self] o in self?.dragSnapped(to: o) }
        s.onDrop = { [weak self] r in self?.finishDrop(r) }
        s.onHint = { [weak self] in self?.holdHint() }
        s.onHintCancel = { [weak self] in self?.cancelHoldHint() }
        s.onArmed = { [weak self] in self?.armSnapMode() }
        // Chuột có thể đã ra ngoài view lúc thả — đồng bộ lại con trỏ rê.
        s.onEnd = { [weak view] in
            guard let v = view, let w = v.window,
                  !v.bounds.contains(v.convert(w.convertPoint(fromScreen: NSEvent.mouseLocation),
                                                from: nil)) else { return }
            v.popHoverCursorIfNeeded()
        }
        view.onHover = { [weak self] hovering in
            guard let self else { return }
            self.container.isHidden = false
            self.controls.isHidden = !hovering
        }
        s.onDoubleClick = { [weak self] in self?.revealCurrentInFinder() }
        view.registerForDraggedTypes([.fileURL])

        applyAppearance()
        overlay.setLevel(activeLevel)
        restorePosition()
        layout()
    }

    /// Menu chuột phải trên widget. AppController gắn menu riêng (không dùng
    /// chung instance với menu thanh menu để tránh xung đột hiển thị).
    func setContextMenu(_ menu: NSMenu?) { container.contextMenu = menu }

    // MARK: - Ngoại hình

    private func applyAppearance() {
        let f = settings.frameStyle
        let r = f.imageCorner

        // Lớp ngoài giữ vai trò nền: KHÔNG bo góc, KHÔNG cắt. Bo gốc và cắt là
        // việc của imageView. Nếu bo cả lớp ngoài thì bóng sẽ ôm theo mép cửa
        // sổ — tức là rộng hơn ảnh, nhìn ra ngay một dải tối quanh ảnh.
        container.layer?.cornerRadius = 0
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = false
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = f.shadowOpacity
        container.layer?.shadowRadius = 14
        container.layer?.shadowOffset = CGSize(width: 0, height: -6)

        // Bo góc do `ImageCanvas` tự cắt trong `draw(_:)` — đặt `cornerRadius` /
        // `masksToBounds` trên lớp thì không bền: lúc lớp cha có transform (widget
        // "nâng" lên khi giữ chuột) thì ba góc mất bo, chỉ góc dưới-trái còn.
        imageView.cornerRadius = r
        topView.cornerRadius = r
    }

    /// Đổ ảnh vào lớp theo chế độ điền đã chọn.
    ///
    /// `ImageCanvas` tự tính phép vỉa cắt trong `draw(_:)` nên ở đây chỉ cần
    /// tra ảnh vào và bảo nó vẽ lại. Phần Retina do AppKit lo trong `draw`.
    private func refreshImageLayer() {
        setContents(currentImage, on: imageView)
        imageView.layer?.opacity = 1
        topView.layer?.opacity = 0
    }

    private func setContents(_ img: NSImage?, on v: ImageCanvas) {
        guard let img else { return }
        v.image = img
        v.fill = (settings.fillMode == .fill)
        v.needsDisplay = true
    }

    /// Chuyển ảnh mềm: ảnh mới nằm ở lớp đang mờ, lớp cũ mờ dần.
    ///
    /// Chỉ animate `opacity` — không đụng `contents`, nên CoreAnimation không
    /// phải rasterize lại gì cả. Đo được ~9ms CPU mỗi lần, không đáng kể so
    /// với 30 giây giữa hai lần đổi ảnh.
    private func crossfade(to img: NSImage) {
        // Ảnh đang hiện nằm ở lớp nào? Lớp còn lại là lớp dưới, đang trong suốt.
        let topVisible = (topView.layer?.opacity ?? 0) > 0.5
        let under = topVisible ? imageView : topView
        let over  = topVisible ? topView  : imageView

        // Đặt ảnh mới vào lớp dưới rồi làm nó mờ dần lên.
        setContents(img, on: under)
        fade(under, to: 1)
        fade(over, to: 0)
    }

    /// Mờ dần một lớp, bằng `CABasicAnimation` tường minh.
    ///
    /// Không dùng `animator().layer?.opacity`: thuộc tính CALayer tự animate
    /// theo "implicit animation" của CoreAnimation, không theo
    /// `NSAnimationContext`, nên thời lượng và easing không kiểm soát được.
    /// Rõ hơn nữa, phải trộn `view.alphaValue` và `layer.opacity` là hỏng —
    /// hai thứ nhân với nhau.
    private func fade(_ view: ImageCanvas, to value: Float) {
        guard let l = view.layer else { return }
        l.removeAnimation(forKey: "fade")
        // Lấy giá trị đang hiển thị trên màn hình, không phải giá trị model —
        /// nếu không, lần fade thứ hai sẽ nhảy về 0 rồi mới mờ lên.
        let from = l.presentation()?.opacity ?? l.opacity
        if abs(from - value) < 0.001 { return }

        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = value
        a.duration = 0.30
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        l.add(a, forKey: "fade")

        // Giá trị model phải khớp ngay, nếu không animation chỉ chạy một lần.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.opacity = value
        CATransaction.commit()
    }

    private func lift(_ scale: CGFloat) {
        // Animation đặt thẳng trên lớp, không qua `NSAnimationContext` —
        // cùng cách `fade()` đang làm.
        //
        // Trước đây dùng `NSAnimationContext` và đặt ảnh bằng `layer.contents`
        // tay lên `NSImageView`. AppKit sở hữu ô nhớ đó: mỗi lần vẽ lại view
        // (rất dễ xảy ra khi lớp cha đổi transform — tức đúng lúc widget
        // "nâng" lên khi bạn giữ chuột) nó chạy `draw()` với không có image và
        // xoá sạch `contents`. Widget mất trắng, chỉ tới lần đổi ảnh kế tiếp mới
        // hiện lại. Nay `ImageCanvas` tự vẽ trong `draw(_:)` nên AppKit vẽ lại
        // bao nhiêu lần cũng ra đúng ảnh — ở đây không cần vá gì thêm.
        guard let l = container.layer else { return }
        let target = CATransform3DMakeScale(scale, scale, 1)
        l.removeAnimation(forKey: "lift")
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = l.transform
        a.toValue = target
        a.duration = 0.15
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        l.add(a, forKey: "lift")
        // Giá trị model phải khớp ngay, không thì animation chỉ chạy một lần.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.transform = target
        CATransaction.commit()
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

    /// Đổi tầng ngay khi người dùng đổi lựa chọn trong menu.
    func applyLevel() {
        window.level = activeLevel
        overlay.setLevel(activeLevel)
        // `floating` cao hơn hẳn tầng desktop — cần orderFront lại mới nhận
        // đúng thứ tự vẽ sau khi đổi tầng.
        window.orderFrontRegardless()
        Diag.describe(window, "  doi tang")
    }

    /// Tự chữa: nếu widget đang ở tầng desktop mà có cửa sổ khác che vùng đó,
    /// thì đổi sang tầng floating để người dùng bấm được.
    ///
    /// Bổ sung cho lựa chọn trong menu — không bắt ai phải nhớ bấm. Chỉ tự
    /// nâng lên, không tự hạ xuống (hạ xuống có thể khiến widget chui xuống dưới
    /// cửa sổ đúng lúc người dùng đang làm việc).
    @discardableResult
    func autoLiftIfOccluded() -> Bool {
        guard settings.levelMode == .desktop else { return false }
        let hidden = NSApp.windows.filter { window !== $0 && $0.isVisible
            && $0.frame.intersects(window.frame) && $0.level > window.level }
        guard !hidden.isEmpty else { return false }
        settings.levelMode = .floating
        applyLevel()
        return true
    }

    /// Khoảng trống chừa sẵn trong cửa sổ cho lúc widget "nâng" lên khi giữ chuột.
///
/// `lift()` scale cửa sổ lên tới 1.06. Trước đây ảnh áp **đúng mép cửa sổ**, nên
/// khi scale, phần tràn ra bị cửa sổ cắt và ba góc trông thành vuông. Chỉ góc
/// dưới-trái còn bo — vì AppKit đặt `anchorPoint = (0,0)` cho view, nên phép scale
/// quanh chính góc đó, nó đứng yên; ba góc kia thì dịch ra ngoài và bị cắt.
///
/// Chừa sẵn khoảng trống này thì cả bốn góc vẫn nằm trong cửa sổ khi nâng lên.
/// Khoảng trống trong suốt nên nhìn không thấy gì thay đổi lúc đứng yên.
///
/// Vì `anchorPoint` được đổi thành tâm (xem `layout()`), mỗi mép chỉ dịch ra
/// `3% × nửa cỡ ảnh`, nên chỉ cần chừa một nửa.
private func liftRoom(_ imageSize: NSSize) -> NSSize {
    // Mép ảnh dịch ra `3% × khoảng cách từ tâm`, mà khoảng cách đó tính cả phần
    // đang chừa. Giải ra: cần `room ≥ 3.2% × cỡ ảnh` — chừa 4% cho chắc ăn.
    let k: CGFloat = 0.04
    return NSSize(width: max(4, imageSize.width * k),
                  height: max(4, imageSize.height * k))
}

private func layout() {
        let i = frameInset, b = frameBottom, p = framePad
        let room = liftRoom(imageSize)
        window.setContentSize(NSSize(width: imageSize.width + (i + p) * 2 + room.width * 2,
                                     height: imageSize.height + (i + p) * 2 + b + room.height * 2))
        container.frame = container.bounds
        // AppKit đặt `anchorPoint = (0,0)` cho view, tức phép scale quanh góc
        // dưới-trái — widget "nâng" lên lệch hẳn sang một bên, và mép nào bị
        // đẩy ra ngoài cửa sổ thì thành góc vuông. Chuyển sang tâm: nâng lên từ
        // chính giữa (đúng nghĩa), và mỗi mép chỉ dịch ra nửa chừng nên chỗ
        // trống phải chừa cũng giảm được một nửa.
        if let cl = container.layer {
            cl.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            cl.position = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        }
        let r = NSRect(x: i + p + room.width, y: i + p + room.height,
                       width: imageSize.width, height: imageSize.height)
        imageView.frame = r
        topView.frame = r
        settings.frameStyle.decorate(in: container, imageRect: imageView.frame)
        layoutControls()
        updateShadowPath()
    }

    /// Cho biết chính xác hình dạng nào đổ bóng.
    ///
    /// Không có dòng này, CoreAnimation phải tự dựng bóng: rasterize nội dung
    /// lớp thành ảnh rồi áp bộ lọc Gaussian mỗi khi khung đổi — tức là MỖI
    /// lần kéo widget, vì kéo là đổi khung. Đo thì riêng bước dựng bóng này
    /// nặng hơn cả bước vẽ ảnh. Chỉ định `shadowPath` thì nó dùng luôn đường
    /// này, không phải làm gì.
    private func updateShadowPath() {
        guard let l = container.layer else { return }
        guard l.shadowOpacity > 0 else {
            l.shadowPath = nil
            return
        }
        // Bóng ôm mép ẢNH, không phải mép cửa sổ. Nhờ `pad` chừa sẵn chỗ nên
        // bông bóng lan ra được mà không bị mép cửa sổ cắt.
        //
        // Vì sao bo góc của đường bóng PHẢI rộng hơn bo góc của ảnh: bộ lọc
        // Gaussian lan ra mọi phía, nên nó lấn vào cả phần khuyết ở góc. Bo góc
        // 20pt gặp blur 14pt là bị lấn gần hết — nhìn ra bóng có hình chữ nhật
        // chứ không phải bo góc. Nới rộng đường bông bóng trước khi blur thì
        // kết quả sau blur mới tròn đúng như ảnh.
        let blur = CGFloat(l.shadowRadius)
        let r = settings.frameStyle.imageCorner + blur * 0.75
        let grow = blur * 0.35
        l.shadowPath = CGPath(
            roundedRect: imageView.frame.insetBy(dx: -grow, dy: -grow),
            cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// Đặt cụm nút trong góc trên phải của vùng ảnh, chồm lên viền.
    private func layoutControls() {
        let inset: CGFloat = 8
        controls.place(inside: NSSize(width: imageSize.width, height: imageSize.height),
                       offset: CGPoint(x: imageSize.width - inset, y: imageSize.height - inset))
    }

    /// Hiện / ẩn nút điều khiển.
    func setControlsVisible(_ v: Bool) {
        guard !container.isPressed else { return }
        controls.isHidden = !v
    }

    func setPinned(_ p: Bool) { controls.isPinned = p }

    /// Gắn hành động cho nút — AppController nối vào danh sách ảnh.
    func wireControls(onPrev: @escaping () -> Void,
                     onNext: @escaping () -> Void,
                     onPin: @escaping () -> Void) {
        controls.onPrev = onPrev
        controls.onNext = onNext
        controls.onTogglePin = onPin
    }

    /// Nối xử lý khi người dùng thả file/thư mục từ Finder vào widget.
    func wireDrop(_ handler: @escaping ([URL]) -> Void) {
        container.onFilesDropped = handler
    }

    /// Mở ảnh gốc trong Finder, tô sáng file đó.
    func revealCurrentInFinder() {
        guard let u = currentURL,
              FileManager.default.fileExists(atPath: u.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([u])
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

        // Ảnh còn trong RAM: đổi tức thì, không cần bố trí hẹn giờ.
        // Đây là đường đi của nút ‹ › và của mọi lần quay lại ảnh vừa xem.
        if let img = ImageStore.inMemory(url, maxPixel: displayMaxPixel) {
            applyImage(img, url: url, size: target)
            return
        }

        // Chưa có trong RAM: giải mã ngoài luồng chính.
        //
        // Trước đây việc này chạy thẳng trên luồng chính. Ảnh gốc 3840×2160 mất
        // 0.33s để giải mã — nghĩa là widget đứng hình gần nửa giây. Giờ luồng
        // chính giữ nguyên và ảnh về sau, không về trước.
        showToken += 1
        let token = showToken
        let pixel = displayMaxPixel
        ImageStore.load(url, maxPixel: pixel) { [weak self] img in
            guard let self, let img, self.showToken == token, !self.busy else { return }
            self.applyImage(img, url: url, size: target)
        }
    }

    /// Đặt ảnh vào khung: đổi ảnh và đổi kích thước cửa sổ trong một lần vẽ.
    /// Tách riêng là để ảnh không bao giờ bị thấy ở khung kia.
    private func applyImage(_ img: NSImage, url: URL, size target: NSSize) {
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)

        currentImage = img
        currentURL = url
        imageSize = target
        applyAppearance()
        layout()
        // Đặt khung trước rồi mới mờ ảnh — nếu mờ trước, giữa lúc chuyển sẽ
        // thấy ảnh cũ ở khung cũ rồi nhảy sang khung mới.
        crossfade(to: img)
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
        refreshImageLayer()
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

    /// Lưới tính theo kích thước widget, cộng bốn ô sát mép màn hình.
    /// Thuật toán nằm ở `GridSnapper` — không phụ thuộc AppKit nên kiểm chứng
    /// được bằng phép tính.
    private func snapSlots(size: NSSize, on s: NSScreen) -> [NSPoint] {
        GridSnapper.slots(widgetSize: size, visibleFrame: s.visibleFrame)
    }

    private func nearestIndex(in slots: [NSPoint], to origin: NSPoint) -> Int? {
        GridSnapper.nearest(in: slots, to: origin)
    }

    /// Tính lại lưới khi đổi màn hình giữa lúc kéo. Cùng một mảng `activeSlots`
    /// được dùng cho cả highlight lẫn thả — không bao giờ lệch nhau.
    /// Viền trong suốt quanh ảnh — lệch toạ độ từ góc cửa sổ tới góc ảnh.
///
/// Cửa sổ lớn hơn ảnh (xem `liftRoom`) nên góc cửa sổ KHÔNG phải góc ảnh. Mọi
/// thứ liên quan tới lưới phải dùng cỡ và vị trí của **ảnh**, vì đó mới là thứ
/// người dùng nhìn thấy và nhắm tới.
private var imageInset: NSPoint {
    let room = liftRoom(imageSize)
    return NSPoint(x: frameInset + framePad + room.width,
                   y: frameInset + framePad + room.height)
}

/// Góc trên-trái của ảnh theo toạ độ màn hình.
private var imageOrigin: NSPoint {
    NSPoint(x: window.frame.minX + imageInset.x,
            y: window.frame.minY + imageInset.y)
}

private func ensureSlots() {
        guard let s = currentScreen() else { return }
        if activeScreen !== s || activeSlots.isEmpty {
            activeScreen = s
            activeSlots = snapSlots(size: imageSize, on: s)
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

    /// Giữ ~0.25s: nhấc nhẹ widget để báo hiệu "đang giữ, sắp vào chế độ lưới".
    private func holdHint() { lift(1.04) }

    private func cancelHoldHint() { lift(1.0) }

    /// Giữ đủ 1.2s: bật chế độ lưới và hiện toàn bộ ô hợp lệ.
    private func armSnapMode() {
        lift(1.06)
        activeScreen = nil
        ensureSlots()
        guard let s = activeScreen, !activeSlots.isEmpty else { return }
        // Ô lưới bo góc theo CHÍNH widget, để hình khớp lúc thả.
        // Trước đây đọc `settings.cornerRadius` — một tuỳ chọn riêng, tách rời
        // khỏi kiểu khung, nên đổi khung xong ô lưới vẫn bo theo giá trị cũ.
        overlay.show(slots: activeSlots, size: imageSize,
                     corner: settings.frameStyle.imageCorner, on: s)
        overlay.highlight(index: nearestIndex(in: activeSlots, to: imageOrigin))
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
            overlay.show(slots: activeSlots, size: imageSize,
                         corner: settings.frameStyle.imageCorner, on: s)
        }
        overlay.highlight(index: nearestIndex(in: activeSlots, to: imageOrigin))
    }

    private func finishDrop(_ result: DropResult) {
        overlay.hide()
        lift(1.0)
        activeScreen = nil

        switch result {
        case .snap:
            ensureSlots()
            if let i = nearestIndex(in: activeSlots, to: imageOrigin) {
                // Lưới bám ảnh, nên khi khe phải dịch cửa sổ lùi lại đúng phần
                // viền trong suốt — nếu không, cửa sổ sẽ lệch so với ô.
                let inset = imageInset
                window.setFrameOrigin(NSPoint(x: activeSlots[i].x - inset.x,
                                              y: activeSlots[i].y - inset.y))
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

    /// Kéo widget về màn hình khi nó rơi ra ngoài mọi màn hình đang cắm.
    ///
    /// Xảy ra khi: kéo widget sang màn hình phụ rồi rút cáp. Toạ độ đã lưu trỏ
    /// tới vị trí không còn tồn tại, widget biến mất và người dùng tưởng app
    /// treo. Chỉ kiểm tra cắt qua `NSScreen.frame` — dùng `visibleFrame` thì
    /// widget nằm sát mép dưới sẽ bị coi là "ngoài" dù vẫn thấy được.
    @discardableResult
    func recoverIfOffscreen() -> Bool {
        let f = window.frame
        let onSomeScreen = NSScreen.screens.contains { NSIntersectsRect($0.frame, f) }
        guard !onSomeScreen else { return false }

        guard let s = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        else { return false }
        window.setFrameOrigin(NSPoint(
            x: min(max(f.minX, s.minX + 4), max(s.minX + 4, s.maxX - f.width - 4)),
            y: min(max(f.minY, s.minY + 4), max(s.minY + 4, s.maxY - f.height - 4))))
        settings.savedOrigin = window.frame.origin
        return true
    }
}
