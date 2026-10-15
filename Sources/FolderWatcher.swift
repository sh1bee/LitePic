import AppKit
import CoreServices

/// Theo dõi thư mục ảnh, tự cập nhật danh sách khi có file thêm/bớt.
///
/// Vì sao FSEvents chứ không phải `DispatchSource.makeFileSystemObjectSource`:
/// trên Darwin, descriptor của một thư mục chỉ báo được một phần sự kiện (đủ
/// cho thư mục con trực tiếp trong một số trường hợp, không đủ cho tạo/xoá file
/// ở mọi nơi). FSEvents là API đúng cho việc này — nó theo dõi cây thư mục
/// và gom các thay đổi dồn dập thành một sự kiện.
///
/// Quan trọng cho năng lượng: có `latency` nên nhiều thay đổi trong một khoảng
/// ngắn chỉ tạo ra MỘT lần thức tỉnh tiến trình — ví dụ copy 500 ảnh chỉ đánh
/// thức app một lần, chứ không phải 500 lần.
final class FolderWatcher {
    init() {}

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "local.litepic.watch", qos: .utility)
    /// Đường dẫn đang theo dõi — dùng để biết khi nào phải tạo lại stream.
    private(set) var paths: [String] = []

    /// Gọi khi có thay đổi (đã gom theo latency).
    var onChange: (() -> Void)?

    /// Bắt đầu theo dõi các thư mục đã cho.
    func watch(_ folders: [URL]) {
        let wanted = folders.map(\.standardizedFileURL.path)
        guard wanted != paths else { return }
        stop()
        guard !wanted.isEmpty else { return }
        paths = wanted

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagFileEvents
                           | kFSEventStreamCreateFlagNoDefer)

        // Chữ ký: (stream, info, soSuKien, conDuong, co, context)
        // `info` là con trỏ tuỳ ý (Optional), `conDuong` thì không — phải đọc
        // thẳng, không `guard let`.
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
            guard let info else { return }
            let self_ = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = rawPaths.bindMemory(to: CFString.self, capacity: count)
            var relevant = false
            for i in 0..<count {
                let p = paths[i] as String
                Diag.log("FSEvent: \(p)")
                let u = URL(fileURLWithPath: p)
                let name = u.lastPathComponent
                // Bỏ qua file ẩn (như .DS_Store, ._*) để việc mở Finder không làm kích hoạt reload
                if name.hasPrefix(".") { continue }
                let ext = u.pathExtension.lowercased()
                if ext.isEmpty || ImageStore.supported.contains(ext) {
                    relevant = true
                }
            }
            guard relevant else { return }
            // PHẢI bắn về main queue. FSEvents gọi callback trên `queue` (luồng
            // phụ), còn `onChange` lại đụng vào `rescanPending`/`rescanScheduled`
            // của AppController — những biến đó main thread cũng đọc/ghi. Gọi
            // thẳng từ luồng phụ là data race, AppKit cũng không an toàn khi bị
            // gọi sai luồng.
            DispatchQueue.main.async { self_.onChange?() }
        }

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, wanted as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,          // latency: gom thay đổi, đánh thức app ít lần
            flags)
        else {
            Diag.log("FSEventStreamCreate that bai")
            paths = []
            return
        }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        Diag.log("theo doi \(wanted.count) thu muc")
    }

    func stop() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        paths = []
    }
}
