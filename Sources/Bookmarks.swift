import AppKit

/// Quyền đọc thư mục bền vững.
///
/// Lưu ý quan trọng: option `.withSecurityScope` **chỉ hoạt động trong app đã
/// sandbox**. LitePic cố tình không sandbox (cần đọc thư mục tùy ý và cập nhật
/// app tại chỗ), nên dùng option đó sẽ luôn thất bại — đã kiểm chứng bằng đo:
/// `withSecurityScope` → FAIL, `minimalBookmark` → OK 1060 byte.
///
/// Vì vậy ở đây dùng bookmark thường, vốn vẫn bám theo khi file bị move/rename
/// trên đĩa. Cái bookmark thật sự cần thiết là cho ổ chưa mount hoặc thư mục
/// đồng bộ — `resolve()` kiểm tra trước khi dùng và `missing()` cho biết thư mục
/// nào cần người dùng mở lại.
enum Bookmarks {
    private static let domain = "local.litepic.folders"

    /// Lưu bookmark cho các thư mục đang chọn. Trả về số thư mục đã ghi được.
    @discardableResult
    static func save(_ folders: [URL]) -> Int {
        var blobs: [Data] = []
        for f in folders {
            guard let d = try? f.bookmarkData(options: .minimalBookmark,
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: nil) else { continue }
            blobs.append(d)
        }
        if blobs.isEmpty { return 0 }
        UserDefaults.standard.set(blobs, forKey: domain)
        return blobs.count
    }

    /// Đọc lại bookmark. Bỏ qua thư mục không còn tồn tại (đã xoá, hoặc ở ổ chưa
    /// mount) — `Settings.folders` sẽ tự rơi về đường dẫn thường cho phần đó.
    static func resolve() -> [URL] {
        guard let blobs = UserDefaults.standard.array(forKey: domain) as? [Data] else {
            return []
        }
        var out: [URL] = []
        for data in blobs {
            var stale = false
            guard let u = try? URL(resolvingBookmarkData: data,
                                   options: [],   // không có .minimalBookmark ở phía đọc
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &stale),
                  FileManager.default.isReadableFile(atPath: u.path) else { continue }
            out.append(u)
        }
        return out
    }

    /// Thư mục đã lưu nhưng hiện không đọc được — thường là ổ chưa mount.
    /// Người dùng cần mở lại thư mục đó một lần trong hộp thoại chọn.
    static func missing() -> [String] {
        let fm = FileManager.default
        return UserDefaults.standard.stringArray(forKey: "folders") ?? []
            .filter { !fm.isReadableFile(atPath: $0) }
    }
}