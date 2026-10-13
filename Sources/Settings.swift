import AppKit

/// Cách widget tính kích thước cửa sổ.
enum SizeMode: Int, CaseIterable {
    case fitImage  // cả hai cạnh bám tỉ lệ ảnh, co về cạnh lớn nhất
    case fitWidth  // cống chiều rộng, chiều cao bám tỉ lệ ảnh
    case fixed     // kích thước cứng, ảnh co vừa

    var title: String {
        switch self {
        case .fitImage: return "Tự động theo ảnh"
        case .fitWidth: return "Cống chiều rộng"
        case .fixed:    return "Kích thước cứng"
        }
    }
}

/// Tầng hiển thị của widget.
///
/// Vì sao cần: widget đặt ở tầng `desktop + 20` (-2147483603) thì **luôn nằm dưới
/// mọi cửa sổ app** (tầng 0). Chỉ cần một cửa sổ trình duyệt phủ qua vùng đó là
/// mọi cú click rơi vào cửa sổ kia, widget không bao giờ nhận được sự kiện chuột —
/// biểu hiện là "bấm vào widget thì dính desktop".
///
/// Đây là hành vi đúng như widget macOS, nhưng khó chịu khi màn hình bị phủ kín,
/// nên mặc định đặt là `floating`.
enum LevelMode: Int, CaseIterable {
    case desktop   // trên wallpaper, dưới cửa sổ app (giống widget macOS)
    case floating  // nổi trên cửa sổ app — luôn bấm/kéo được

    var title: String {
        switch self {
        case .desktop:  return "Trên wallpaper (dưới app)"
        case .floating: return "Luôn nổi (dễ bấm)"
        }
    }
}

/// Toàn bộ tuỳ chọn nằm trong UserDefaults — không file cấu hình phức tạp.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private enum K {
        static let folders       = "folders"
        static let interval      = "interval"
        static let randomOn      = "randomInterval"
        static let minInterval   = "minInterval"
        static let maxInterval   = "maxInterval"
        static let sizeMode      = "sizeMode"
        static let width         = "width"
        static let height        = "height"
        static let maxEdge       = "maxEdge"
        static let opacity       = "opacity"
        static let interactive   = "interactive"
        static let snapToGrid   = "snapToGrid"
        static let renderScale  = "renderScale"
        static let cornerRadius = "cornerRadius"
        static let levelMode    = "levelMode"
        static let changeOnWake = "changeOnWake"
        static let pinned     = "pinnedURL"
        static let frameStyle = "frameStyle"
        static let posX          = "posX"
        static let posY          = "posY"
    }

    // MARK: - Nguồn ảnh

    /// Thư mục ảnh.
    ///
    /// `folderPaths` là nguồn sự thật về thứ tự và thành phần. Bookmark chỉ dùng
    /// để sửa đường dẫn khi thư mục đã bị di chuyển — không bao giờ thay thế danh
    /// sách, vì nếu thay thế thì "Bỏ thư mục" sẽ không bao giờ có tác dụng.
    var folders: [URL] {
        let paths = folderPaths
        let located = Bookmarks.resolve(paths)
        return paths.map { located[$0] ?? URL(fileURLWithPath: $0) }
    }

    var folderPaths: [String] {
        get { d.stringArray(forKey: K.folders) ?? [] }
        set {
            d.set(newValue, forKey: K.folders)
            Bookmarks.save(newValue.map { URL(fileURLWithPath: $0) })
        }
    }

    /// Thư mục đã chọn nhưng hiện không đọc được (ổ chưa mount, thư mục đã xoá).
    var missingFolders: [String] { Bookmarks.missing(folderPaths) }

    // MARK: - Tần suất đổi ảnh

    var interval: TimeInterval {
        get { d.object(forKey: K.interval) == nil ? 30 : d.double(forKey: K.interval) }
        set { d.set(newValue, forKey: K.interval) }
    }

    var randomInterval: Bool {
        get { d.bool(forKey: K.randomOn) }
        set { d.set(newValue, forKey: K.randomOn) }
    }

    var minInterval: TimeInterval {
        get { d.object(forKey: K.minInterval) == nil ? 15 : d.double(forKey: K.minInterval) }
        set { d.set(newValue, forKey: K.minInterval) }
    }

    var maxInterval: TimeInterval {
        get { d.object(forKey: K.maxInterval) == nil ? 300 : d.double(forKey: K.maxInterval) }
        set { d.set(newValue, forKey: K.maxInterval) }
    }

    // MARK: - Hiển thị

    var sizeMode: SizeMode {
        get { SizeMode(rawValue: d.integer(forKey: K.sizeMode)) ?? .fitImage }
        set { d.set(newValue.rawValue, forKey: K.sizeMode) }
    }

    var width: CGFloat {
        get { d.object(forKey: K.width) == nil ? 480 : CGFloat(d.double(forKey: K.width)) }
        set { d.set(Double(newValue), forKey: K.width) }
    }

    var height: CGFloat {
        get { d.object(forKey: K.height) == nil ? 480 : CGFloat(d.double(forKey: K.height)) }
        set { d.set(Double(newValue), forKey: K.height) }
    }

    /// Cạnh dài tối đa cho chế độ fitImage.
    var maxEdge: CGFloat {
        get { d.object(forKey: K.maxEdge) == nil ? 600 : CGFloat(d.double(forKey: K.maxEdge)) }
        set { d.set(Double(newValue), forKey: K.maxEdge) }
    }

    var opacity: CGFloat {
        get { d.object(forKey: K.opacity) == nil ? 1 : CGFloat(d.double(forKey: K.opacity)) }
        set { d.set(Double(newValue), forKey: K.opacity) }
    }

    var interactive: Bool {
        get { d.bool(forKey: K.interactive) }
        set { d.set(newValue, forKey: K.interactive) }
    }

    /// Bật thì widget luôn "hít" vào ô lưới gần nhất khi thả — không đặt tùy ý.
    var snapToGrid: Bool {
        get { d.object(forKey: K.snapToGrid) == nil ? true : d.bool(forKey: K.snapToGrid) }
        set { d.set(newValue, forKey: K.snapToGrid) }
    }

    /// Hệ số render: 2 = sắc nét trên Retina nhưng giải mã nặng hơn ~4 lần;
    /// 1 = nhẹ hơn nhiều, đổi lại hơi mềm trên màn Retina.
    var renderScale: CGFloat {
        get { d.object(forKey: K.renderScale) == nil ? 2 : CGFloat(d.double(forKey: K.renderScale)) }
        set { d.set(Double(newValue), forKey: K.renderScale) }
    }

    var cornerRadius: CGFloat {
        get { d.object(forKey: K.cornerRadius) == nil ? 20 : CGFloat(d.double(forKey: K.cornerRadius)) }
        set { d.set(Double(newValue), forKey: K.cornerRadius) }
    }

    var levelMode: LevelMode {
        get { LevelMode(rawValue: d.integer(forKey: K.levelMode)) ?? .floating }
        set { d.set(newValue.rawValue, forKey: K.levelMode) }
    }

    /// Đổi ảnh mỗi lần thức Mac khỏi chế độ ngủ.
    var changeOnWake: Bool {
        get { d.bool(forKey: K.changeOnWake) }
        set { d.set(newValue, forKey: K.changeOnWake) }
    }

    var frameStyle: FrameStyle {
        get { FrameStyle(rawValue: d.integer(forKey: K.frameStyle)) ?? .shadow }
        set { d.set(newValue.rawValue, forKey: K.frameStyle) }
    }

    /// Ảnh đang ghim — không bị đổi bởi timer cho tới khi bỏ ghim.
    var pinnedURL: String? {
        get { d.string(forKey: K.pinned) }
        set { d.set(newValue, forKey: K.pinned) }
    }

    var savedOrigin: NSPoint? {
        get {
            guard d.object(forKey: K.posX) != nil, d.object(forKey: K.posY) != nil else { return nil }
            return NSPoint(x: CGFloat(d.double(forKey: K.posX)),
                           y: CGFloat(d.double(forKey: K.posY)))
        }
        set {
            guard let newValue else { return }
            d.set(Double(newValue.x), forKey: K.posX)
            d.set(Double(newValue.y), forKey: K.posY)
        }
    }
}