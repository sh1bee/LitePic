import AppKit

/// Thanh nút nhỏ trên widget: ảnh trước / kế tiếp / ghim.
///
/// Các nút nằm trong một hàng dọc ở góc trên phải, chỉ hiện khi rê chuột vào
/// widget (hoặc lúc kéo) — giống cách widget macOS ẩn điều khiển khi rời chuột.
final class WidgetControls: NSView {
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    var onTogglePin: (() -> Void)?

    /// Có đang ghim ảnh hiện tại không — quyết định màu nút ghim.
    var isPinned = false {
        didSet { pinBtn.contentTintColor = isPinned ? .systemYellow : .white }
    }

    private let prevBtn = NSButton()
    private let nextBtn = NSButton()
    private let pinBtn = NSButton()

    /// Kích thước nút — nhỏ nhất có thể mà vẫn bấm được bằng chuột.
    private static let side: CGFloat = 26
    private static let gap: CGFloat = 6
    private static let pad: CGFloat = 8

    private var origin = CGPoint.zero

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        configure(prevBtn, "chevron.left", #selector(pressPrev))
        configure(nextBtn, "chevron.right", #selector(pressNext))
        configure(pinBtn, "pin", #selector(pressPin))
        addSubview(prevBtn)
        addSubview(nextBtn)
        addSubview(pinBtn)
    }

    required init?(coder: NSCoder) { fatalError("khong dung") }

    private func configure(_ b: NSButton, _ symbol: String, _ sel: Selector) {
        b.wantsLayer = true
        b.bezelStyle = .texturedRounded
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.contentTintColor = .white
        b.target = self
        b.action = sel
        b.setButtonType(.momentaryChange)
    }

    /// Vị trí trong hệ toạ độ của widget (widget đặt góc trên phải).
    func place(inside size: NSSize, offset: CGPoint) {
        let w = Self.side, gap = Self.gap
        origin = CGPoint(x: offset.x - w - gap, y: offset.y + size.height - w - gap)
        layoutButtons()
    }

    private func layoutButtons() {
        prevBtn.frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        nextBtn.frame = CGRect(x: prevBtn.frame.maxX + Self.gap, y: 0,
                               width: Self.side, height: Self.side)
        pinBtn.frame = CGRect(x: nextBtn.frame.maxX + Self.gap, y: 0,
                              width: Self.side, height: Self.side)
        let total = pinBtn.frame.maxX
        frame = CGRect(origin: origin, size: NSSize(width: total, height: Self.side))
        // Nền nửa trong suốt để nút đọc được trên cả ảnh sáng lẫn tối.
        wantsLayer = true
        layer?.cornerRadius = Self.side / 2
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
    }

    func show() { isHidden = false }
    func hide() { isHidden = true }

    @objc private func pressPrev() { onPrev?() }
    @objc private func pressNext() { onNext?() }
    @objc private func pressPin() { onTogglePin?() }
}