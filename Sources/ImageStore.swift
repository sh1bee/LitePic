import AppKit
import ImageIO
import CryptoKit

/// Đọc ảnh từ đĩa, tiết kiệm năng lượng và RAM.
///
/// Ba tầng, từ nhanh nhất tới chậm nhất:
///
///   1. RAM        — vài ảnh vừa xem, LRU giữ `memLimit` ảnh. Lật lại ảnh cũ tức thì.
///   2. Đĩa cache  — JPEG nhỏ, giải mã ~5ms.
///   3. Ảnh gốc    — giải mã trên luồng phụ, KHÔNG bao giờ trên luồng chính.
///
/// Vì sao tầng 3 phải nằm ngoài luồng chính: ảnh gốc là 3840×2160. Giải mã đầy
/// đủ tạo buffer 31.6 MB và tốn 0.33s — đo thực tế trên máy này. Làm việc đó
/// trên luồng chính nghĩa là widget đứng hình 0.33s mỗi lần đổi ảnh.
///
/// Vì sao KHÔNG giải mã hết loạt lúc mở app (`prewarm` cũ): 43 ảnh làm CPU
/// tăng 1.25s và RSS tăng từ 24 MB lên 52 MB — phần lớn là bộ nhớ đã giải phóng
/// mà malloc không trả lại cho hệ điều hành. Đổi lại tốn đúng mười mili giây
/// cho lần xem đầu tiên của mỗi ảnh, và chỉ những ảnh thật sự được xem.
enum ImageStore {
    static let supported: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp",
    ]

    /// Mỗi ảnh giữ trong RAM bao nhiêu byte: rộng × cao × 4.
    /// 768px ngang ≈ 1.3 MB, nên 3 ảnh là ~4 MB.
    private static let memLimit = 3

    /// Tổng dung lượng cache trên đĩa được phép. 64 MB là dư cho vài trăm ảnh
    /// ở mức 1280px; vượt ngưỡng thì xoá bản cũ nhất.
    private static let diskCap: Int64 = 64 * 1024 * 1024

    private static let defaultCacheDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LitePic", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Bộ test trỏ cache sang thư mục tạm.
    ///
    /// Không có nó thì phép thử "xoá cache lúc đang giải mã" xoá luôn cache thật
    /// của người dùng. Hậu quả đo được, không phải giả định: sau một lần chạy
    /// test, footprint đi ngang của app nhảy từ **9.8 lên 21.0 MB**. Lý do nằm
    /// ngay trong `load()` — đọc cache đĩa thì không tốn gì, còn giải mã ảnh gốc
    /// 4K thì tăng ~7 MB **vĩnh viễn** do bộ giải mã ImageIO giữ bộ đệm. Xoá
    /// cache một lần là app phải giải mã gốc ở mọi lần chạy sau, và mọi phép đo
    /// hiệu năng về sau đều bị thổi lên ~11 MB — cũng tức là mốc đo cũ không còn
    /// dùng được nữa.
    static var cacheDirOverride: URL?

    static var cacheDir: URL { cacheDirOverride ?? defaultCacheDir }

    // MARK: - Đồng bộ

    /// RAM và cache đĩa đều bị đụng từ nhiều luồng (chính + luồng giải mã).
    private static let lock = NSLock()
    private static var memCache: [String: NSImage] = [:]
    private static var memOrder: [String] = []
    private static var sizeMemo: [String: CGSize] = [:]

    /// Hàng đợi giải mã nối tiếp — chỉ một ảnh được giải mã tại một thời điểm.
    /// Quan trọng cho RAM: hai ảnh 4K giải mã chồng nhau là 60 MB, một ảnh thì 10.
    private static let decodeQueue = DispatchQueue(
        label: "local.litepic.decode", qos: .userInitiated)

    // MARK: - Liệt kê

    /// Liệt kê file ảnh trong các thư mục đã chọn (hỗ trợ nhiều thư mục / nhiều "album").
    static func files(in folders: [URL]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { continue }
            for u in items where supported.contains(u.pathExtension.lowercased()) {
                out.append(u)
            }
        }
        return out
    }

    // MARK: - Kích thước gốc

    /// Kích thước pixel gốc, đọc từ header — không giải mã ảnh.
    ///
    /// Có ghi nhớ theo đường dẫn: mỗi lần đổi ảnh cần tỉ lệ này TRƯỚC khi biết
    /// kích thước cửa sổ, và `load()` lại mở đúng file đó lần nữa. Ghi nhớ giúp
    /// mỗi lần đổi ảnh chỉ mở file một lần thay vì hai.
    static func pixelSize(of url: URL) -> CGSize? {
        let k = url.path
        lock.lock()
        if let hit = sizeMemo[k] { lock.unlock(); return hit }
        lock.unlock()

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0
        else { return nil }

        // PHẢI xét cờ Orientation. `PixelWidth/PixelHeight` là kích thước THÔ
        // của file: ảnh chụp dọc từ điện thoại vẫn lưu 4032×3024 ngang. Nhưng
        // `decodeThumbnail` bên dưới bật
        // `kCGImageSourceCreateThumbnailWithTransform: true` nên ảnh thật sự
        // được xoay về dọc. Không sửa ở đây thì tỉ lệ khung lệch với ảnh:
        // cửa sổ bị co theo khổ ngang còn ảnh bên trong lại dọc → méo hoặc
        // thừa lề đen.
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)   // 5,6,7,8 = xoay 90°/270°
        let size = rotated ? CGSize(width: h, height: w) : CGSize(width: w, height: h)

        lock.lock()
        if sizeMemo.count > 512 { sizeMemo.removeAll() }   // đừng phình vô hạn
        sizeMemo[k] = size
        lock.unlock()
        return size
    }

    // MARK: - Tải ảnh

    /// Các mức cache. Yêu cầu hiển thị được làm tròn lên mức gần nhất, nhờ vậy việc làm
    /// nóng cache ở 2048 cũng phục vụ được các yêu cầu nhỏ hơn (1200px…) — quan trọng,
    /// vì nếu tên cache mang kích thước riêng thì mỗi lần hiển thị đều lỡ cache và
    /// phải giải mã lại ảnh 4K gốc.
    private static let pixelBuckets = [512, 768, 1024, 1280, 1536, 2048, 3072, 4096]

    /// Mức cache phục vụ một yêu cầu hiển thị `want` px — AppController dùng để
    /// biết mức nào còn cần giữ lại khi dọn cache.
    static func pixelBucket(for want: CGFloat) -> Int { bucket(for: max(64, want)) }

    private static func bucket(for want: CGFloat) -> Int {
        for b in pixelBuckets where CGFloat(b) >= want { return b }
        return pixelBuckets[pixelBuckets.count - 1]
    }

    /// Trả ảnh ngay nếu đang có trong RAM — không chặn, không giải mã.
    static func inMemory(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        let key = "\(cacheKey(for: url))-\(bucket(for: max(64, maxPixel)))"
        lock.lock()
        defer { lock.unlock() }
        if let hit = memCache[key] {
            memOrder.removeAll { $0 == key }
            memOrder.append(key)      // chạm lần cuối -> giữ lâu hơn
            return hit
        }
        return nil
    }

    /// Tải ảnh, gọi `completion` trên luồng chính.
    ///
    /// Trả ngay tức thì (không cần bố trí hẹn giờ) nếu ảnh còn trong RAM — đường
    /// này chiếm đa số lượt bấm nút Next/Previous.
    static func load(_ url: URL, maxPixel: CGFloat, completion: @escaping (NSImage?) -> Void) {
        if let hit = inMemory(url, maxPixel: maxPixel) {
            completion(hit)
            return
        }
        let key = "\(cacheKey(for: url))-\(bucket(for: max(64, maxPixel)))"
        let file = cacheDir.appendingPathComponent("\(key).jpg")
        let pixel = bucket(for: max(64, maxPixel))

        decodeQueue.async {
            // Cache đĩa: JPEG nhỏ, giải mã nhanh. Không cần đụng ảnh gốc.
            if let hit = NSImage(contentsOf: file) {
                self.remember(key, hit)
                DispatchQueue.main.async { completion(hit) }
                return
            }
            // Lạnh: giải mã ảnh gốc — ở đây, không phải trên luồng chính.
            //
            // Đo được: mỗi lần giải mã ảnh gốc 4K làm tiến trình tăng ~7 MB
            // và KHÔNG bao giờ xuống lại, dù ảnh đó sau đó bị bỏ khỏi RAM. Đó là
            // bộ giải mã JPEG của ImageIO giữ lại bộ đệm giải mã đầy đủ
            // (3840×2160×4 = 31.6 MB) cho lần đọc kế tiếp cùng file đó.
            //
            // `CACHE_RESOLVED_IMAGES` bật thì ImageIO cache lại ảnh đã giải mã
            // theo đường dẫn — tức là giữ nguyên ảnh 4K trong RAM. Tắt hẳn:
            // ta đã có cache riêng ở tầng trên, không cần ImageIO nhớ gì thêm.
            guard let cg = self.decodeThumbnail(of: url, maxPixel: CGFloat(pixel)) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            self.remember(key, img)
            self.writeCache(cg, to: file)
            DispatchQueue.main.async { completion(img) }
        }
    }

    // MARK: - Bộ nhớ

    private static func remember(_ key: String, _ img: NSImage) {
        lock.lock()
        defer { lock.unlock() }
        if memCache[key] == nil { memOrder.append(key) }
        memCache[key] = img
        // LRU: bỏ ảnh cũ nhất cho tới khi vừa đủ chỗ.
        while memOrder.count > memLimit {
            let drop = memOrder.removeFirst()
            memCache.removeValue(forKey: drop)
        }
    }

    /// Xoá toàn bộ bộ nhớ — gọi khi đổi thư mục ảnh.
    static func clearMemory() {
        lock.lock()
        memCache.removeAll()
        memOrder.removeAll()
        sizeMemo.removeAll()
        lock.unlock()
    }

    // MARK: - Giải mã và ghi cache

    private static func decodeThumbnail(of url: URL, maxPixel: CGFloat) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:  true, // tôn trọng EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize:         maxPixel,
            kCGImageSourceShouldCacheImmediately:        false,
            kCGImageSourceShouldCache:                   false,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Ghi cache bằng chính ImageIO.
    ///
    /// Không dùng `NSBitmapImageRep(cgImage:)` vì hàm đó tạo thêm một bản sao
    /// bitmap đúng kích thước ảnh trước khi encode — thừa ~1.3 MB mỗi lần ghi.
    ///
    /// Ghi "public.jpeg" thay vì `UTType.jpeg.identifier`: dùng UTType kéo
    /// cả framework UniformTypeIdentifiers vào bộ nhớ dù chỉ cần một chuỗi,
    /// và đo được nó tăng ~8 MB RSS của cả app.
    private static func writeCache(_ cg: CGImage, to file: URL) {
        guard let dest = CGImageDestinationCreateWithURL(
            file as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, [
            kCGImageDestinationLossyCompressionQuality: 0.82,
        ] as CFDictionary)
        if !CGImageDestinationFinalize(dest) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Khoá cache theo đường dẫn + mtime + size: sửa ảnh gốc thì tự sinh cache mới.
    private static func cacheKey(for url: URL) -> String {
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mtime = Int(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let size = v?.fileSize ?? 0
        let raw = "\(url.path)|\(mtime)|\(size)"
        let hex = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    // MARK: - Dọn cache

    /// Xoá cache không còn dùng.
    ///
    /// Đổi kích thước widget hay hạ chất lượng là đổi mức cache, mà mỗi mức là
    /// một bộ file riêng. Không dọn thì cache phình vô hạn — đo được 4 mức cùng
    /// tồn tại từ các lần đổi cấu hình, tốn gấp đôi dung lượng cần thiết.
    /// `keepPixels == nil` nghĩa là giữ tất cả (chỉ còn chặn trần dung lượng).
    static func pruneCache(keepPixels pixels: Int?) {
        // Cùng lý do như `clearCache()`: đây là thao tác **xoá file**, mà file
        // đó có thể đang được `writeCache` ghi trên `decodeQueue`. Đưa cùng một
        // hàng đợi nối tiếp thì không còn việc xoá nhầm file đang gửi.
        decodeQueue.async { pruneCacheNow(keepPixels: pixels) }
    }

    private static func pruneCacheNow(keepPixels pixels: Int?) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var keep: [URL] = []
        for u in items {
            if let p = pixels, !u.lastPathComponent.hasSuffix("-\(p).jpg") {
                try? fm.removeItem(at: u)          // mức cache không còn dùng
            } else {
                keep.append(u)
            }
        }

        var sized: [(url: URL, size: Int, date: Date)] = []
        var total: Int64 = 0
        for u in keep {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let s = Int(v?.fileSize ?? 0)
            total += Int64(s)
            sized.append((u, s, v?.contentModificationDate ?? .distantPast))
        }
        guard total > diskCap else { return }
        for e in sized.sorted(by: { $0.date < $1.date }) {
            guard total > diskCap else { break }
            try? fm.removeItem(at: e.url)
            total -= Int64(e.size)
        }
    }

    /// Dung lượng cache hiện có (byte).
    static func cacheSize() -> Int64 {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(Int64(0)) { sum, u in
            sum + Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    static func clearCache() {
        clearMemory()
        // PHẢI xếp vào `decodeQueue`, không làm thẳng trên luồng gọi.
        //
        // `decodeQueue` là hàng đợi **nối tiếp**: mọi ghi cache đều chạy trên đó.
        // Nếu `clearCache()` xoá thư mục ngay trên luồng menu (main) thì nó có
        // thể chen giữa lúc một ảnh đang giải mã, và `writeCache` sau đó ghi vào
        // thư mục vừa bị xoá — ghi hỏng, hoặc tạo file mồ côi ngoài sự quản lý.
        // Bằng cách xếp hàng, việc dọn dẹp luôn nằm **sau** mọi việc giải mã
        // đang dở, không còn đường tranh chấp nào trên đĩa.
        decodeQueue.async {
            try? FileManager.default.removeItem(at: cacheDir)
            try? FileManager.default.createDirectory(at: cacheDir,
                                                     withIntermediateDirectories: true)
        }
    }
}
