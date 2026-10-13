import AppKit

/// Ghi log chẩn đoán ra file để lần tái hiện lỗi cho biết widget **thực sự**
/// nhận được gì từ hệ thống — thay vì đoán.
///
/// Bật:   defaults write local.litepic.widget diag -bool true
/// Đọc:   tail -40 ~/Library/Logs/LitePic.log
/// Tắt:   defaults write local.litepic.widget diag -bool false
enum Diag {
    private static let path: String = {
        let d = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("LitePic.log").path
    }()

    static var enabled: Bool = UserDefaults.standard.bool(forKey: "diag")

    static func log(_ s: String) {
        guard enabled else { return }
        let line = "\(Date().timeIntervalSince1970)  \(s)\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            try? fh.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Ghi trạng thái cửa sổ: tầng, có bị cửa sổ nào che không.
    /// `occludedWindows` là nguồn chính xác của việc widget có nhận được click hay không.
    static func describe(_ w: NSWindow, _ tag: String) {
        guard enabled else { return }
        let desk = Int(CGWindowLevelForKey(.desktopWindow))
        // Cửa sổ nào nằm trên widget (tầng cao hơn) và có cắt qua vùng của nó —
        // chính là thứ chặn click. Chỉ nhìn `NSApp.windows` của chính app này
        // không đủ: cửa sổ app khác không nằm trong danh sách đó.
        let blockers = NSApp.windows
            .filter { $0 !== w && $0.isVisible && $0.frame.intersects(w.frame) && $0.level > w.level }
            .map { "\($0.title.isEmpty ? $0.className : $0.title)[\(Int($0.frame.width))x\(Int($0.frame.height))]" }
        log("""
            \(tag): frame=\(Int(w.frame.origin.x)),\(Int(w.frame.origin.y)) \
            \(Int(w.frame.width))x\(Int(w.frame.height)) level=desk+\(w.level.rawValue - desk) \
            visible=\(w.isVisible) ignoresMouse=\(w.ignoresMouseEvents) key=\(w.isKeyWindow) \
            CHE_BOI=[\(blockers.joined(separator: ", "))]
            """)
    }
}