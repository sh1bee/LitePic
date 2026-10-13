import AppKit

/// Bám theo thư mục ảnh khi nó bị di chuyển/đổi tên trên đĩa.
///
/// Vì sao cần: nếu người dùng đổi tên thư mục ảnh (hay mount ổ ra rồi tắt),
/// đường dẫn lưu trong tuỳ chọn sẽ hỏng và LitePic im lặng không hiện ảnh nào.
/// Bookmark của Foundation trỏ tới đúng thứ đó.
///
/// Lưu ý quan trọng: option `.withSecurityScope` **chỉ hoạt động trong app đã
/// sandbox**. LitePic cố tình không sandbox (cần đọc thư mục tùy ý và cập nhật
/// app tại chỗ), nên dùng option đó sẽ luôn thất bại — đã kiểm chứng bằng đo:
/// `withSecurityScope` → FAIL, `minimalBookmark` → OK 1060 byte.
///
/// Điểm mấu chốt về thiết kế: bookmark KHÔNG phải nguồn sự thật. Danh sách
/// `folders` trong tuỳ chọn mới là nguồn sự thật (thứ tự, thành phần); bookmark
/// chỉ dùng để SỬA đường dẫn mỗi mục. Bản cũ làm ngược lại — `resolve()` trả
/// về danh sách riêng của nó và thay thế hoàn toàn `folders`, nên khi người dùng
/// bỏ hết thư mục thì app vẫn cứ lấy thư mục cũ ra hiển thị. Đo được: bỏ hết
/// thư mục rồi khởi động lại, app vẫn tự giải mã 24 ảnh (CPU 1.25s) dù danh
/// sách trong tuỳ chọn đã rỗng.
enum Bookmarks {
    private static let key = "litepic.folderBookmarks"

    /// Một cặp: đường dẫn đã chọn + bookmark của nó.
    ///
    /// Cần cặp chứ không chỉ bookmark, vì phải ánh xạ ngược bookmark về đúng mục
    /// trong danh sách mà người dùng đã chọn.
    private struct Entry: Codable {
        let path: String
        let data: Data
    }

    /// Ghi lại bookmark cho danh sách thư mục vừa chọn.
    ///
    /// Ghi kèm danh sách rỗng thì phải XOÁ luôn mục cũ, không được giữ lại — nếu
    /// không thì "Bỏ thư mục" trong menu chỉ dọn đúng một nửa vụ việc.
    static func save(_ folders: [URL]) {
        guard !folders.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let entries: [[String: Any]] = folders.compactMap { f in
            guard let d = try? f.bookmarkData(options: .minimalBookmark,
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: nil) else { return nil }
            return ["path": f.path, "data": d]
        }
        UserDefaults.standard.set(entries, forKey: key)
    }

    /// Ánh xạ `đường dẫn đã chọn` → `vị trí hiện tại`.
    ///
    /// Chỉ trả về mục nào còn đọc được; mục không còn thì không có entry nào, và
    /// người dùng đơn giản là điều khiển thay cho giá trị cũ.
    private static func currentLocations() -> [String: URL] {
        let fm = FileManager.default
        var out: [String: URL] = [:]
        for e in UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? [] {
            guard let path = e["path"] as? String, let data = e["data"] as? Data else { continue }
            var stale = false
            guard let u = try? URL(resolvingBookmarkData: data,
                                   options: [],   // không có .minimalBookmark ở phía đọc
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &stale),
                  fm.isReadableFile(atPath: u.path) else { continue }
            out[path] = u
        }
        return out
    }

    /// Vị trí hiện tại cho từng thư mục đã chọn — giữ nguyên thứ tự của danh
    /// sách gốc.
    static func resolve(_ paths: [String]) -> [String: URL] {
        paths.isEmpty ? [:] : currentLocations()
    }

    /// Thư mục đã chọn mà hiện không đọc được — thường là ổ chưa mount.
    static func missing(_ paths: [String]) -> [String] {
        let fm = FileManager.default
        return paths.filter { !fm.isReadableFile(atPath: $0) }
    }
}
