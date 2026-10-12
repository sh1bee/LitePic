import AppKit
import ImageIO
import CryptoKit

/// Đọc ảnh từ đĩa.
///
/// Điểm mấu chốt cho việc tiết kiệm năng lượng: KHÔNG bao giờ giải mã ảnh ở kích thước gốc.
/// Ảnh 4K giải mã đầy đủ tốn ~32 MB RAM và ~0.4s CPU mỗi lần — quá đắt cho widget chạy nền.
///
/// Vì vậy hai lớp:
///   1. Giải mã bằng JPEG subsampling của ImageIO ở đúng độ phân giải hiển thị.
///   2. Lưu kết quả xuống ~/Library/Caches/LitePic. Lần xem lại chỉ tốn ~10ms.
enum ImageStore {
    static let supported: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp",
    ]

    private static let cacheDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LitePic", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

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

    /// Kích thước pixel gốc, đọc từ header — không giải mã ảnh.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0
        else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Các mức cache. Yêu cầu hiển thị được làm tròn lên mức gần nhất, nhờ vậy việc làm
    /// nóng cache ở 2048 cũng phục vụ được các yêu cầu nhỏ hơn (1200px…) — quan trọng,
    /// vì nếu tên cache mang kích thước riêng thì mỗi lần hiển thị đều lỡ cache và
    /// phải giải mã lại ảnh 4K gốc.
    private static let pixelBuckets = [512, 768, 1024, 1280, 1536, 2048, 3072, 4096]

    private static func bucket(for want: CGFloat) -> Int {
        for b in pixelBuckets where CGFloat(b) >= want { return b }
        return pixelBuckets[pixelBuckets.count - 1]
    }

    /// Ảnh đã giải mã ở độ phân giải vừa đủ cho khung hiển thị, có cache trên đĩa.
    static func thumbnail(of url: URL, maxPixel: CGFloat) -> NSImage? {
        let pixel = bucket(for: max(64, maxPixel))
        let cached = cacheDir.appendingPathComponent("\(cacheKey(for: url))-\(pixel).jpg")

        if let hit = NSImage(contentsOf: cached) {
            return hit
        }
        guard let fresh = decodeThumbnail(of: url, maxPixel: CGFloat(pixel)) else { return nil }

        // Ghi cache bất đồng bộ khỏi luồng chính để không trễ lúc đổi ảnh.
        let rep = NSBitmapImageRep(cgImage: fresh)
        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            DispatchQueue.global(qos: .utility).async {
                try? data.write(to: cached, options: .atomic)
            }
        }
        return NSImage(cgImage: fresh, size: NSSize(width: fresh.width, height: fresh.height))
    }

    private static func decodeThumbnail(of url: URL, maxPixel: CGFloat) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:  true, // tôn trọng EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize:         maxPixel,
            kCGImageSourceShouldCacheImmediately:        true,
            kCGImageSourceShouldCache:                   false,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
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

    /// Làm nóng cache trong nền khi vừa chọn thư mục, để lần xem đầu tiên của mỗi ảnh
    /// cũng nhanh. Chạy ở QoS utility và nhường CPU định kỳ để không giành ưu tiên với app
    /// đang dùng.
    static func prewarm(_ urls: [URL], maxPixel: CGFloat = 2048) {
        DispatchQueue.global(qos: .utility).async {
            for (i, u) in urls.enumerated() {
                autoreleasepool { _ = thumbnail(of: u, maxPixel: maxPixel) }
                if i % 8 == 7 { Thread.sleep(forTimeInterval: 0.05) }
            }
        }
    }

    /// Dung lượng cache hiện có (byte).
    static func cacheSize() -> Int64 {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return items.reduce(Int64(0)) { sum, u in
            sum + Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
    }
}