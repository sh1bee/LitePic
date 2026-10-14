// Kiểm thử kéo thật cho LitePic — 7 tình huống (A..G).
//
// Ten file PHAI la main.swift: Swift chi cho phep code cap top-level trong file
// ten chinh xac "main.swift" khi bien dich nhieu file cung luc.
//
// Chay: ./test.sh
//
// KHONG chay duoc trong SPM vi can vong lap su kien that cua AppKit
// (NSApp.nextEvent) va cua so that — nen bien dich truc tiep bang swiftc.
//
// BO CAI TRONG PHEP DO NAY (dang gap that khi viet no):
//   1. Gan de callback de quan sat se XOA wiring cua app (onDrop -> finishDrop,
//      onArmed -> armSnapMode). Phep do van "dat" vi no ghi lai dung minh tu
//      ghi vao — bong ma finishDrop khong chay luon. Phai BOC: let g = s.onDrop;
//      s.onDrop = { g?($0); ... }.
//   2. So sanh toa DO TUYET DOI. AppKit lam trui goc cua so ra so nguyen, nen
//      o tai (526.75, 437.5) tro thanh (527, 437) — lech 0.9pt ma van khe dung.
//      Dung nguong 1.5pt.
//   3. Event sót. Nhap dup tra ve som ma khong an mouseUp da post, va su kien
//      do con sót sang tinh huong ke tiep lam no thanh .click ngay lap tuc.
//      Phai drain hang doi truoc moi tinh huong.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Kiểm thử kéo thật cho DragSession — chạy trên vòng lặp sự kiện thật, không
// phải gọi hàm nội bộ. Mỗi tình huống tạo widget mới để không dính trạng thái.
//
// GHI CHU QUAN TRONG VE CACH DO: phai BOC callback da co (goc?()) truoc khi
// them phep do. Gan de callback se xoa wiring cua app (finishDrop, armSnapMode)
// va phep do se tra ve dung nhung gi minh tu ghi vao — bong ma khong con gi de
// do. Day la loi da that mat rat nhieu thoi gian lan truoc.
Diag.enabled = true
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Settings.shared.levelMode = .floating

/// Sinh ảnh JPEG thử riêng trong thư mục tạm.
///
/// Trước đây bộ test trỏ thẳng vào thư mục ảnh thật của máy và dùng `try!` +
/// ép `!`. Dọn Downloads, đổi tên thư mục hay chạy trên máy khác là **crash
/// ngay ở dòng đầu tiên** của bộ test — và crash ở đó thì không phân biệt được
/// với lỗi thật của app.
///
/// Ảnh màu xanh đặc 400×300 là đủ: các phép thử kéo-thả chỉ so **vị trí quy đổi
/// sang ô lưới** (tương đối, không phụ thuộc cỡ ảnh), còn hồi quy "ảnh còn mất
/// không" đo `image != nil` chứ không đo pixel — nên không cần ảnh có chi tiết.
///
/// Ghi lại khi file thiếu HOẶC đọc ra sai kích thước. Như vậy lần chạy thường
/// không đụng mtime, không sinh rác cache đĩa (`ImageStore.cacheKey` khoá theo
/// path + mtime + size), mà vẫn tự chữa nếu lần trước bị đứt giữa chừng.
func makeDummyTestImage() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("litepic-dragtest.jpg")
    let want = CGSize(width: 400, height: 300)

    if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
       let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
       img.width == Int(want.width), img.height == Int(want.height) {
        return url            // đã có bản tốt — giữ nguyên để không đổi mtime
    }

    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(want.width), height: Int(want.height),
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Nửa trên đỏ, nửa dưới xanh: nếu có lúc nào ảnh bị xoay nhầm thì nhìn thấy
    // ngay bằng mắt, thay vì xanh một màu không phân biệt được chiều.
    ctx.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: want.height / 2, width: want.width, height: want.height / 2))
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: want.width, height: want.height / 2))

    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("khong gia lai duoc anh thu: \(url.path)")
    }
    return url
}

let imageURL = makeDummyTestImage()

/// Ghi lai moi su kien callback cua mot widget, dong thoi van chay wiring goc.
final class Recorder {
    var armed = false, hinted = false, hintCancelled = false
    var dragCount = 0, snapCount = 0
    var drop: DropResult? = nil
    var dropTime: Date? = nil
    var began = false, ended = false
    var slotsAtArm: [NSPoint] = []
    var doubleClicked = false

    init(_ view: DraggableView, _ w: WidgetWindow) {
        let s = view.session
        let gHint = s.onHint
        s.onHint = { gHint?(); self.hinted = true }
        let gHintCancel = s.onHintCancel
        s.onHintCancel = { gHintCancel?(); self.hintCancelled = true }
        let gArmed = s.onArmed
        s.onArmed = {
            gArmed?()
            self.armed = true
            self.slotsAtArm = Mirror(reflecting: w).children
                .first { $0.label == "activeSlots" }?.value as? [NSPoint] ?? []
        }
        let gDrag = s.onDrag
        s.onDrag = { o in gDrag?(o); self.dragCount += 1 }
        let gSnap = s.onSnapDrag
        s.onSnapDrag = { o in gSnap?(o); self.snapCount += 1 }
        let gDrop = s.onDrop
        s.onDrop = { r in gDrop?(r); self.drop = r; self.dropTime = Date() }
        let gBegin = s.onBegin
        s.onBegin = { gBegin?(); self.began = true }
        let gEnd = s.onEnd
        s.onEnd = { gEnd?(); self.ended = true }
        let gDbl = s.onDoubleClick
        s.onDoubleClick = { gDbl?(); self.doubleClicked = true }
    }
}

/// Rut sach su kien chuot con sót trong hang doi truoc khi bat tinh huong moi.
///
/// Can thiet: nhap dup tra ve som ma khong an mouseUp da post, nen su kien do
/// con sót. Tinh huong sau se nhan phai va ket qua thanh .click ngay lap tuc —
/// hieu ung lam sai chu, khong phai loi cua ung dung.
func drainEvents() {
    // Cho cac lenh asyncAfter con sót cua tinh huong truoc chay xong da,
    // moi rut sach — khong thi no post ra sau khi minh da rut.
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    while NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                     .rightMouseDown, .otherMouseDown],
                          until: Date(), inMode: .eventTracking, dequeue: true) != nil {}
}

func makeWidget() -> (WidgetWindow, DraggableView) {
    drainEvents()
    let w = WidgetWindow()
    let view = w.window.contentView as! DraggableView
    w.show(imageURL, evenIfBusy: true)
    let vf = NSScreen.main!.visibleFrame
    w.window.setFrameOrigin(NSPoint(x: vf.midX - 180, y: vf.midY - 110))
    Thread.sleep(forTimeInterval: 0.4)
    return (w, view)
}

func ev(_ t: NSEvent.EventType, _ s: NSPoint, _ w: NSWindow,
        _ click: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(with: t, location: w.convertPoint(fromScreen: s),
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: w.windowNumber, context: nil,
        eventNumber: 1, clickCount: click, pressure: 1)!
}
func post(_ e: NSEvent) { NSApp.postEvent(e, atStart: false) }
func after(_ d: TimeInterval, _ f: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: f)
}

/// So sanh vi tri cuoi cua widget voi o luoi gan nhat.
///
/// Canh bao: AppKit lam trui goc cua so ra so nguyen khi setFrameOrigin, nen o
/// tai (526.75, 437.5) tro thanh (527, 437). Do lech toi da khi khe dung la
/// sqrt(0.75^2 + 0.5^2) ~ 0.91pt, nen dung nguong 1.5pt.
func snapReport(_ w: WidgetWindow, _ slots: [NSPoint]) -> (Bool, String) {
    // Cửa sổ có viền trong suốt (chừa chỗ cho lúc widget nâng lên), nên phải
    // so vị trí của ẢNH — cùng cách `WidgetWindow` bám lưới theo ảnh.
    let M = { (o: Any, _ l: String) -> Any? in
        Mirror(reflecting: o).children.first { $0.label == l }?.value }
    let container = M(w, "container") as! NSView
    let inset = container.subviews.first { $0 is ImageCanvas }?.frame.origin ?? .zero
    let pos = NSPoint(x: w.window.frame.minX + inset.x,
                      y: w.window.frame.minY + inset.y)
    guard let n = slots.min(by: {
        hypot($0.x - pos.x, $0.y - pos.y) < hypot($1.x - pos.x, $1.y - pos.y)
    }) else { return (false, "khong co o nao de so") }
    let d = hypot(n.x - pos.x, n.y - pos.y)
    return (d <= 1.5,
            String(format: "vi tri cuoi (%.1f, %.1f) vs o gan nhat (%.2f, %.2f) — lech %.3fpt",
                   pos.x, pos.y, n.x, n.y, d))
}

func line(_ ok: Bool, _ label: String, _ detail: String = "") {
    print("  \(ok ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  —  " + detail)")
}

// ============================================================
print("A) Keo truoc, dung lai 1.2s -> luoi hien, tha khe vao o")
// ============================================================
do {
    let (w, view) = makeWidget()
    let r = Recorder(view, w)
    let s0 = NSPoint(x: w.window.frame.minX + 70, y: w.window.frame.minY + 70)
    let dest = NSPoint(x: s0.x - 180, y: s0.y - 120)
    for i in 1...6 {
        let f = Double(i) / 6
        after(0.10 + 0.03 * Double(i)) {
            post(ev(.leftMouseDragged,
                    NSPoint(x: s0.x + (dest.x - s0.x) * f,
                            y: s0.y + (dest.y - s0.y) * f), w.window))
        }
    }
    after(2.6) { post(ev(.leftMouseUp, dest, w.window)) }
    let t0 = Date()
    view.mouseDown(with: ev(.leftMouseDown, s0, w.window))

    let (hit, detail) = snapReport(w, r.slotsAtArm)
    line(r.armed, "luoi co bat", "o tai luc bat: \(r.slotsAtArm.count)")
    // O phuong an nay luoi chi bat SAU khi dung lai nen khong co phat
    // onSnapDrag — do la dung. Phep do keo trong khi da bat luoi nam o G).
    line(r.snapCount == 0, "dung: khong co phat snap luc nay",
         "luoi bat luc \(String(format: "%.2f", r.dropTime!.timeIntervalSince(Date().addingTimeInterval(0))))s — sau khi keo xong")
    line(r.drop == .snap, "ket qua la .snap", "tho: \(r.drop.map { "\($0)" } ?? "nil")")
    line(hit, "widget THAT SU khe vao o", detail)
    line(r.ended, "ket thuc sach (onEnd chay)")
    print("     thoi gian keo→tha: \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
    w.window.close()
}

// ============================================================
print("B) Nhan giu 1.2s khong keo -> luoi hien, tha tai cho khe tai cho")
// ============================================================
do {
    let (w, view) = makeWidget()
    let r = Recorder(view, w)
    let s0 = NSPoint(x: w.window.frame.minX + 70, y: w.window.frame.minY + 70)
    after(1.6) { post(ev(.leftMouseUp, s0, w.window)) }
    view.mouseDown(with: ev(.leftMouseDown, s0, w.window))

    line(r.armed, "luoi co bat", "o: \(r.slotsAtArm.count)")
    line(r.drop == .snap, "ket qua la .snap", "tho: \(r.drop.map { "\($0)" } ?? "nil")")
    line(r.dragCount == 0, "khong co phat keo thua", "dragCount: \(r.dragCount)")
    let (hit, detail) = snapReport(w, r.slotsAtArm)
    line(hit, "vi tri khong doi (khe tai cho)", detail)
    w.window.close()
}

// ============================================================
print("C) Keo nhanh roi tha ngay (duoi 1.2s) -> .free, khong bat luoi")
// ============================================================
do {
    let (w, view) = makeWidget()
    let r = Recorder(view, w)
    let originTruoc = w.window.frame.origin
    let s0 = NSPoint(x: w.window.frame.minX + 70, y: w.window.frame.minY + 70)
    let dest = NSPoint(x: s0.x - 200, y: s0.y - 60)
    for i in 1...4 {
        let f = Double(i) / 4
        after(0.05 + 0.04 * Double(i)) {
            post(ev(.leftMouseDragged,
                    NSPoint(x: s0.x + (dest.x - s0.x) * f,
                            y: s0.y + (dest.y - s0.y) * f), w.window))
        }
    }
    after(0.45) { post(ev(.leftMouseUp, dest, w.window)) }
    view.mouseDown(with: ev(.leftMouseDown, s0, w.window))

    line(!r.armed, "KHONG bat luoi (qua nhanh)", "hinted: \(r.hinted)")
    line(r.drop == .free, "ket qua la .free", "tho: \(r.drop.map { "\($0)" } ?? "nil")")
    let daDi = hypot(w.window.frame.origin.x - originTruoc.x,
                     w.window.frame.origin.y - originTruoc.y)
    line(daDi > 100, "widget da di chuyen theo chuot", "khoang \(Int(daDi))pt")
    w.window.close()
}

// ============================================================
print("D) Nhan don ngan -> .click, khong bat luoi, khong di chuyen")
// ============================================================
do {
    let (w, view) = makeWidget()
    let r = Recorder(view, w)
    let originTruoc = w.window.frame.origin
    let s0 = NSPoint(x: w.window.frame.minX + 70, y: w.window.frame.minY + 70)
    after(0.15) { post(ev(.leftMouseUp, s0, w.window)) }
    view.mouseDown(with: ev(.leftMouseDown, s0, w.window))

    line(r.drop == .click, "ket qua la .click", "tho: \(r.drop.map { "\($0)" } ?? "nil")")
    line(!r.armed && !r.hinted, "khong bat luoi, khong hien goi y",
         "hinted: \(r.hinted)")
    let d = hypot(w.window.frame.origin.x - originTruoc.x,
                  w.window.frame.origin.y - originTruoc.y)
    line(d < 0.5, "vi tri khong doi", "lech \(String(format: "%.2f", d))pt")
    w.window.close()
}

// ============================================================
print("E) Keo ra NGOAI cua so roi tha -> van nhan mouseUp, khong ket trang thai")
// ============================================================
do {
    let (w, view) = makeWidget()
    let r = Recorder(view, w)
    let s0 = NSPoint(x: w.window.frame.minX + 70, y: w.window.frame.minY + 70)
    // Keo ra xa kieu bien man hinh — chuot van nam trong man hinh nhung ngoai cua so.
    let vf = NSScreen.main!.visibleFrame
    let ngoai = NSPoint(x: vf.minX + 20, y: vf.minY + 20)
    for i in 1...8 {
        let f = Double(i) / 8
        after(0.06 + 0.03 * Double(i)) {
            post(ev(.leftMouseDragged,
                    NSPoint(x: s0.x + (ngoai.x - s0.x) * f,
                            y: s0.y + (ngoai.y - s0.y) * f), w.window))
        }
    }
    after(0.60) { post(ev(.leftMouseUp, ngoai, w.window)) }
    view.mouseDown(with: ev(.leftMouseDown, s0, w.window))

    line(r.drop != nil, "van nhan duoc mouseUp", "tho: \(r.drop.map { "\($0)" } ?? "nil")")
    line(!view.isPressed, "isPressed = false (khong ket)")
    line(!view.isDragging, "isDragging = false (khong ket)")
    line(r.ended, "onEnd duoc goi (cursor tra lai)")
    let overlay = Mirror(reflecting: w).children
        .first { $0.label == "overlay" }?.value as! GridOverlay
    line(!overlay.isVisible, "overlay khong bi khet sau khi tha ngoai")
    w.window.close()
}

// ============================================================
print("F) Nhap dup -> mo Finder, khong vao vong keo")
// ============================================================
do {
    let (w, view) = makeWidget()
    let r = Recorder(view, w)
    let s0 = NSPoint(x: w.window.frame.minX + 70, y: w.window.frame.minY + 70)
    // Khong post mouseUp: nhap dup tra ve som nen co khong an, va su kien do
    // se con sót sang tinh huong ke tiep lam no ket qua .click sai.
    view.mouseDown(with: ev(.leftMouseDown, s0, w.window, 2))

    line(r.doubleClicked, "co goi onDoubleClick")
    line(r.drop == nil, "khong vao vong keo (khong co .click)", "drop: \(r.drop.map { "\($0)" } ?? "nil")")
    w.window.close()
}

// ============================================================
print("G) Bat luoi truoc (giu 1.2s), ROI keo -> co onSnapDrag, tha khe vao o")
// ============================================================
do {
    let (w, view) = makeWidget()
    let r = Recorder(view, w)
    let s0 = NSPoint(x: w.window.frame.minX + 70, y: w.window.frame.minY + 70)
    let dest = NSPoint(x: s0.x - 170, y: s0.y + 130)

    // Giu yen 1.4s de luoi bat truoc.
    for i in 1...6 {
        let f = Double(i) / 6
        after(1.40 + 0.04 * Double(i)) {
            post(ev(.leftMouseDragged,
                    NSPoint(x: s0.x + (dest.x - s0.x) * f,
                            y: s0.y + (dest.y - s0.y) * f), w.window))
        }
    }
    after(1.90) { post(ev(.leftMouseUp, dest, w.window)) }
    view.mouseDown(with: ev(.leftMouseDown, s0, w.window))

    line(r.armed, "luoi co bat TRUOC khi keo", "o: \(r.slotsAtArm.count)")
    line(r.snapCount > 0, "CO onSnapDrag (keo trong che do luoi)", "lan: \(r.snapCount)")
    line(r.drop == .snap, "ket qua la .snap", "tho: \(r.drop.map { "\($0)" } ?? "nil")")
    let (hit, detail) = snapReport(w, r.slotsAtArm)
    line(hit, "widget THAT SU khe vao o", detail)
    w.window.close()
}

// ============================================================
print("H) Giu cho luoi bat roi tha -> ANH PHAI CON (khong mat trang)")
// ============================================================
// Hoi quy cho loi "giu widget la no bien mat, chi hoi lai khi doi anh".
//
// `imageView`/`topView` ve anh bang `layer.contents`. Neu `contents` bi xoa
// ve nil, cua so van con (chuot phai bat duoc, van nhin thay vi tri) nhung
// KHONG CON GI DE VE -> widget trong trang. Do truc tiep `contents`, khong
// do pixel: pixel chi cho biet "co/khong", `contents` cho biet TAI SAO.
do {
    let (w, view) = makeWidget()
    let M = { (o: Any, _ l: String) -> Any? in
        Mirror(reflecting: o).children.first { $0.label == l }?.value }
    let imageView = M(w, "imageView") as! ImageCanvas
    let topView = M(w, "topView") as! ImageCanvas
    func hasImage() -> Bool {
        imageView.image != nil || topView.image != nil
    }

    // Anh nap xong truoc khi do — do qua `contents` ma anh chua nap thi vo nghia.
    let t0 = Date()
    while !hasImage() && Date().timeIntervalSince(t0) < 8 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }


    let s0 = NSPoint(x: w.window.frame.minX + 70, y: w.window.frame.minY + 70)
    var imageAfterDrop = false
    let gDrop = view.session.onDrop
    view.session.onDrop = { r in
        gDrop?(r)                      // giữ nguyên wiring của app
        // finishDrop đã chạy xong; đợi nét vẽ chính rồi mới đo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            imageAfterDrop = hasImage()
        }
    }

    after(1.6) { post(ev(.leftMouseUp, s0, w.window)) }
    view.mouseDown(with: ev(.leftMouseDown, s0, w.window))
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))

    line(hasImage(), "anh con ngay khi luoi bat (khong mat lúc giơ luoi)")
    line(imageAfterDrop, "anh con sau khi tha chuot",
         imageAfterDrop ? "" : "contents = nil — widget trong trang")
    w.window.close()
}

// ============================================================
print("I) Keo ma khong co mouseUp -> PHAI TU THOAT (khong kiet)")
// ============================================================
// Hoi quy cho loi "vong lap while true chi thoat khi nhan .leftMouseUp".
//
// Do duoc truoc khi sua: tha chuot "cuu tinh" post vao giay thu 6 thi vong lap
// moi ra (6.30s); khong co no thi treo vo han — isDragging ket true, widget din
// theo con tro, va con tro bam ket trong ngan xep den het phien.
//
// Canh bao chi ban khi KHONG co su kien nao VA app mat focus, nen phai kiem
// ca hai chieu: (1) im lang thi thoat, (2) keo that 4 giay thi KHONG bi cat.
do {
    let (w, view) = makeWidget()
    let p0 = NSPoint(x: w.window.frame.midX, y: w.window.frame.midY)
    let p1 = NSPoint(x: p0.x + 40, y: p0.y - 40)

    // --- chieu (1): im lang, khong co su kien nao ---
    after(0.15) { post(ev(.leftMouseDragged, p1, w.window)) }
    // Lan THOA TAI: neu canh bao hong, chinh su kien nay moi ket thuc vong lap.
    after(6.0) { post(ev(.leftMouseUp, p1, w.window)) }
    let t0 = Date()
    view.mouseDown(with: ev(.leftMouseDown, p0, w.window))
    let quiet = Date().timeIntervalSince(t0)
    line(quiet < 5.5, "im lang thi vong lap tu thoat",
         String(format: "%.2fs (khong can den mouseUp cuu tinh o 6s)", quiet))
    line(!view.session.isDragging, "isDragging da ve false sau khi thoat")
    w.window.close()
    // QUAN TRONG: lan thoat tai 6s cua chieu (1) van con treo. Neu khong cho
    // no ban, no se bay sang vong keo cua chieu (2) va lam phép do sai.
    // (Da that: 4.0s -> 2.51s, do chinh su kien cuu tinh ket thuc vong keo.)
    RunLoop.current.run(until: Date().addingTimeInterval(6.0))
    drainEvents()

    // --- chieu (2): keo that 4 giay, vuot qua nguong canh bao ---
    let (w2, v2) = makeWidget()
    let q0 = NSPoint(x: w2.window.frame.midX, y: w2.window.frame.midY)
    final class C { var n = 0 }
    let c = C()
    let dragTimer = Timer(timeInterval: 0.1, repeats: true) { _ in
        c.n += 1
        let k = CGFloat(c.n)
        post(ev(.leftMouseDragged, NSPoint(x: q0.x + k * 3, y: q0.y - k * 2), w2.window))
    }
    RunLoop.main.add(dragTimer, forMode: .common)
    after(4.0) {
        dragTimer.invalidate()
        let k = CGFloat(c.n)
        post(ev(.leftMouseUp, NSPoint(x: q0.x + k * 3, y: q0.y - k * 2), w2.window))
    }
    let t1 = Date()
    v2.mouseDown(with: ev(.leftMouseDown, q0, w2.window))
    let real = Date().timeIntervalSince(t1)
    line(real > 3.8, "keo that 4s thi canh bao KHONG cat ngao",
         String(format: "%.2fs", real))
    w2.window.close()
}

// ============================================================
print("J) Bo thu muc -> anh phai bien mat, khong phai 'bong ma'")
// ============================================================
do {
    let (w, _) = makeWidget()
    let M = { (o: Any, _ l: String) -> Any? in
        Mirror(reflecting: o).children.first { $0.label == l }?.value }
    let iv = M(w, "imageView") as! ImageCanvas
    let tv = M(w, "topView") as! ImageCanvas
    func hasImage() -> Bool { iv.image != nil || tv.image != nil }
    let t0 = Date()
    while !hasImage() && Date().timeIntervalSince(t0) < 8 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    line(hasImage(), "truoc khi bo thu muc co anh")
    line(w.window.isVisible, "truoc khi bo thu muc cua so hien")

    w.clear()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    line(!hasImage(), "sau clear() khong con anh nao giu lai")
    line(!w.window.isVisible, "sau clear() cua so da an")
    w.window.close()
}

// ============================================================
print("K) Xoa cache luc dang giai ma -> thu muc cache phai con nguyen")
// ============================================================
do {
    let dir = makeDummyTestImage().deletingLastPathComponent()
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        .filter { $0.hasSuffix(".jpg") }.sorted().map { dir.appendingPathComponent($0) }
    let cacheDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Caches/LitePic")

    // Ban nhip nhieu luot nap roi xoa cache xen ke — truoc day day la cuoc dua tren
    // dia giua `writeCache` (tren decodeQueue) va `removeItem` (tren luong menu).
    for i in 0..<12 {
        ImageStore.clearMemory()
        ImageStore.load(files[i % max(1, files.count)], maxPixel: 360) { _ in }
        if i % 3 == 0 { ImageStore.clearCache() }
    }
    // Cho moi viec tren hang doi chay het.
    let t0 = Date()
    while Date().timeIntervalSince(t0) < 4 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: cacheDir.path, isDirectory: &isDir)
    line(exists && isDir.boolValue, "thu muc cache van con sau khi xoa rac",
         cacheDir.path)
}

// ============================================================
print("")
print("Xong.")
exit(0)
