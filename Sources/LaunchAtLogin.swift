import AppKit

/// Tự chạy cùng macOS khi đăng nhập.
///
/// Vì sao KHÔNG dùng `SMAppService.mainApp` (dù API này gọn hơn nhiều):
/// nó từ chối app ký ad-hoc. Đã kiểm chứng — app build cục bộ của LitePic gọi
/// `register()` trả về `Operation not permitted`. `SMAppService` cần chữ ký
/// Developer ID hợp lệ, còn LitePic build tại chỗ bằng `codesign --sign -`.
///
/// Dùng LaunchAgent plist thay thế. Cách này chỉ GHI FILE, không gọi launchd
/// ngay — có chủ đích:
///
///   - launchd nạp `~/Library/LaunchAgents` khi đăng nhập, nên file là đủ.
///   - Nếu gọi `launchctl bootstrap` lúc này thì launchd sẽ khởi chạy MỘT
///     instance thứ hai, trong khi bản người dùng đang bấm menu vẫn chạy —
///     hai instance cùng tranh một ô menu bar.
///   - Đổi lại tính năng có hiệu lực từ lần đăng nhập kế tiếp. Đây là chuyện
///     bình thường với mọi ứng dụng loại này.
enum LaunchAtLogin {
    private static let label = "local.litepic.widget"

    private static var plistURL: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let dir = lib.appendingPathComponent("LaunchAgents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(label).plist")
    }

    /// Đường dẫn binary — launchd chạy chính file này, không qua `open`.
    private static var executable: String {
        Bundle.main.bundlePath + "/Contents/MacOS/LitePic"
    }

    /// Đang đăng ký tự chạy không.
    ///
    /// Phải kiểm tra cả nội dung plist, không chỉ "file tồn tại": mỗi lần build
    /// lại app có thể nằm ở đường dẫn khác, plist cũ sẽ trỏ vào chỗ không có
    /// — mà vẫn hiện "đang bật" trong menu.
    static var isEnabled: Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let pl = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let args = pl["ProgramArguments"] as? [String]
        else { return false }
        return args.first == executable
            && FileManager.default.isExecutableFile(atPath: executable)
    }

    /// Bật/tắt tự chạy. Trả về thông báo lỗi nếu thất bại.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        let fm = FileManager.default
        let url = plistURL

        if !on {
            // Gỡ job đã nạp nếu có (trường hợp bật rồi tắt cùng phiên đăng nhập).
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            do { try fm.removeItem(at: url) } catch {
                Diag.log("xoa plist that bai: \(error)")
                return "Không xoá được: \(error.localizedDescription)"
            }
            return nil
        }

        guard fm.isExecutableFile(atPath: executable) else {
            return "Chưa thấy app tại \(executable)."
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            // Như app bình thường: không phải daemon nền, cũng không bị hệ
            // thống kéo chậm khi người dùng đang bận việc.
            "ProcessType": "Interactive",
        ]
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        } catch {
            Diag.log("ghi plist that bai: \(error)")
            return "Không ghi được: \(error.localizedDescription)"
        }
        Diag.log("LaunchAtLogin: da ghi \(url.path)")
        return nil
    }
}
