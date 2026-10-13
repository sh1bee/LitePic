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

let dir = NSHomeDirectory() + "/Downloads/alime/wallpaper/real dáng say"
let img = ((try! FileManager.default.contentsOfDirectory(atPath: dir))
    .first { $0.hasSuffix(".jpg") })!
let imageURL = URL(fileURLWithPath: dir + "/" + img)

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
print("")
print("Xong.")
exit(0)
