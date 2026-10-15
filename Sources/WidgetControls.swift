import AppKit

/// Thanh nút nhỏ trên widget: ảnh trước / kế tiếp / ghim.
///
/// Các nút nằm thành một hàng ngang ở góc trên phải, chỉ hiện khi rê chuột vào
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
        b.imagePosition = .imageOnly
        b.imageScaling = .scaleProportionallyDown
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.contentTintColor = .white
        b.target = self
        b.action = sel
        b.setButtonType(.momentaryChange)
    }

    /// Dán cụm nút vào góc trên phải của vùng ảnh `imageRect`.
    ///
    /// `imageRect` là `imageView.frame` — hệ toạ độ của `container`, cùng hệ với
    /// `self`. Trước đây hàm này nhận `(inside:offset:)` và tự tính `origin`:
    /// nó cộng thêm `size.height` vào `offset.y` trong khi `offset.y` đã là toạ độ
    /// tính từ đáy, nên cụm nút rơi xuống tầm **hai lần chiều cao ảnh** — nằm ngoài
    /// màn hình; và nó chỉ lùi `side + gap` nên cụm rộng 90pt bị thò ra ngoài mép
    /// phải.
    func place(atTopRightOf imageRect: NSRect) {
        let total = Self.side * 3 + Self.gap * 2
        let margin = Self.pad
        frame = CGRect(x: imageRect.maxX - total - margin,
                       y: imageRect.maxY - Self.side - margin,
                       width: total, height: Self.side)
        layoutButtons()
    }

    private func layoutButtons() {
        prevBtn.frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        nextBtn.frame = CGRect(x: prevBtn.frame.maxX + Self.gap, y: 0,
                               width: Self.side, height: Self.side)
        pinBtn.frame = CGRect(x: nextBtn.frame.maxX + Self.gap, y: 0,
                              width: Self.side, height: Self.side)
        // Nền nửa trong suốt để nút đọc được trên cả ảnh sáng lẫn tối.
        wantsLayer = true
        layer?.cornerRadius = Self.side / 2
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
    }

    @objc private func pressPrev() { onPrev?() }
    @objc private func pressNext() { onNext?() }
    @objc private func pressPin() { onTogglePin?() }
}