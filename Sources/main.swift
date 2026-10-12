import AppKit

// LitePic — widget ảnh nhẹ cho desktop macOS.
//
// Thiết kế: menu-bar app (không Dock icon), không network, không dependency.
// Ảnh chỉ được giải mã ở đúng độ phân giải hiển thị, và chỉ khi timer tới hạn.

let app = NSApplication.shared
let controller = AppController()

app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()