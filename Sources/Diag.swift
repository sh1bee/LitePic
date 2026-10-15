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

    /// `s` là autoclosure: khi tắt log, biểu thức nội tuyến KHÔNG được dựng.
    ///
    /// Quan trọng về hiệu năng: Swift dựng sẵn đối số trước khi gọi hàm. Với
    /// `log("chuột xuống tại \(x)")`, chuỗi được cấp phát và nối lại ở MỌI lần
    /// bấm chuột kể cả khi log đang tắt — thứ vốn không nên tốn một byte heap.
    static func log(_ s: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(Date().timeIntervalSince1970)  \(s())\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            try? fh.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Ghi trạng thái cửa sổ: tầng, có bị cửa sổ nào che không.
    /// Truy vấn danh sách cửa sổ toàn hệ thống qua CGWindowListCopyWindowInfo để thấy cả cửa sổ app khác.
    static func describe(_ w: NSWindow, _ tag: String) {
        guard enabled else { return }
        let desk = Int(CGWindowLevelForKey(.desktopWindow))
        var blockers: [String] = []
        let wid = CGWindowID(w.windowNumber)
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], wid) as? [[String: Any]],
           let mainScreen = NSScreen.screens.first {
            let screenHeight = mainScreen.frame.height
            let appKitFrame = w.frame
            let myPID = ProcessInfo.processInfo.processIdentifier

            for info in list {
                if let pid = info[kCGWindowOwnerPID as String] as? Int32, pid == myPID { continue }
                if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.1 { continue }
                guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                      let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
                guard cgRect.width > 20, cgRect.height > 20 else { continue }
                let appKitRect = NSRect(x: cgRect.origin.x,
                                        y: screenHeight - cgRect.origin.y - cgRect.height,
                                        width: cgRect.width,
                                        height: cgRect.height)
                if appKitRect.intersects(appKitFrame) {
                    let owner = info[kCGWindowOwnerName as String] as? String ?? "App"
                    let name = info[kCGWindowName as String] as? String ?? ""
                    let label = name.isEmpty ? owner : "\(owner):\(name)"
                    blockers.append("\(label)[\(Int(cgRect.width))x\(Int(cgRect.height))]")
                }
            }
        }
        log("""
            \(tag): frame=\(Int(w.frame.origin.x)),\(Int(w.frame.origin.y)) \
            \(Int(w.frame.width))x\(Int(w.frame.height)) level=desk+\(w.level.rawValue - desk) \
            visible=\(w.isVisible) ignoresMouse=\(w.ignoresMouseEvents) key=\(w.isKeyWindow) \
            CHE_BOI=[\(blockers.joined(separator: ", "))]
            """)
    }
}