import AppKit

final class AppController: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let widget = WidgetWindow()

    private var status: NSStatusItem?
    private var timer: Timer?
    private var images: [URL] = []
    private var lastIndex: Int = -1

    /// Ảnh đang ghim — bộ đếm bỏ qua nó để không đổi vô ích.
    private var isPinned: Bool { settings.pinnedURL != nil }
    private var paused = false
    private var screenAsleep = false
    /// Đang có một lần thử đổi ảnh hoãn vì người dùng đang kéo widget.
    private var retryScheduled = false

    private static let intervalChoices: [(String, Int)] = [
        ("15 giây", 15), ("30 giây", 30), ("1 phút", 60),
        ("5 phút", 300), ("10 phút", 600), ("30 phút", 1800),
    ]

    private static let maxEdgeChoices = [360, 520, 700, 900]
    private static let widthChoices: [CGFloat] = [320, 480, 700]
    private static let fixedChoices: [(String, CGFloat, CGFloat)] = [
        ("Dọc 360×480", 360, 480),
        ("Ngang 480×360", 480, 360),
        ("Vuông 480×480", 480, 480),
        ("Rộng 640×360", 640, 360),
    ]
    private static let opacityChoices: [Int] = [40, 60, 80, 100]

    // MARK: - Vòng đời

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        watchScreenState()
        reload()
        widget.wireControls(onPrev: { [weak self] in self?.step(-1) },
                            onNext: { [weak self] in self?.step(1) },
                            onPin: { [weak self] in self?.togglePin() })
        widget.setControlsVisible(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Thanh menu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "LitePic")
        item.button?.imagePosition = .imageOnly
        status = item
        rebuildMenu()
    }

    private func watchScreenState() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) {
            [weak self] _ in
            self?.screenAsleep = true
            self?.timer?.invalidate()
            self?.timer = nil
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) {
            [weak self] _ in
            guard let self else { return }
            self.screenAsleep = false
            // Thức dậy là dịp tự nhiên để đổi ảnh — người dùng vừa từ chỗ
            // tối sang, một bức mới hợp lý hơn bức đang chiếu lúc ngủ.
            if settings.changeOnWake { self.advance() }
            self.scheduleTimer()
        }
    }

    private func rebuildMenu() {
        // Widget và thanh menu dùng hai instance riêng — dùng chung một NSMenu
        // cho hai nơi hiển thị dễ gây xung đột khi menu đang mở.
        status?.menu = buildMenu()
        widget.setContextMenu(buildMenu())
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false

        let levelMenu = NSMenu()
        for mode in LevelMode.allCases {
            add(levelMenu, mode.title, #selector(pickLevel), tag: mode.rawValue,
                state: settings.levelMode == mode ? .on : .off)
        }
        m.addItem(submenu("Hiển thị", levelMenu))
        m.addItem(.separator())

        add(m, "Chọn thư mục ảnh…", #selector(chooseFolders))
        if !settings.folderPaths.isEmpty {
            add(m, "Bỏ thư mục (\(images.count) ảnh)", #selector(clearFolders))
        }
        // Báo thẳng thư mục nào hỏng, thay vì im lặng cho người dùng tưởng hỏng app.
        let gone = settings.missingFolders
        if !gone.isEmpty {
            let note = NSMenuItem(
                title: "\(gone.count) thư mục không mở được (ổ chưa mount?)",
                action: nil, keyEquivalent: "")
            note.isEnabled = false
            m.addItem(note)
        }
        m.addItem(.separator())

        m.addItem(submenu("Đổi ảnh", intervalMenu()))
        m.addItem(submenu("Kích thước", sizeMenu()))

        let qualityMenu = NSMenu()
        for (label, value) in [("Sắc nét (2×)", 2), ("Tiết kiệm (1×)", 1)] {
            add(qualityMenu, label, #selector(pickRenderScale), tag: value,
                state: Int(settings.renderScale) == value ? .on : .off)
        }
        m.addItem(submenu("Chất lượng", qualityMenu))

        let opacityMenu = NSMenu()
        for pct in Self.opacityChoices {
            add(opacityMenu, "\(pct)%", #selector(pickOpacity), tag: pct,
                state: Int(settings.opacity * 100) == pct ? .on : .off)
        }
        m.addItem(submenu("Độ mờ", opacityMenu))

        let frameMenu = NSMenu()
        for f in FrameStyle.allCases {
            add(frameMenu, f.title, #selector(pickFrame), tag: f.rawValue,
                state: settings.frameStyle == f ? .on : .off)
        }
        m.addItem(submenu("Khung ảnh", frameMenu))

        add(m, "Đổi ảnh khi thức dậy", #selector(toggleChangeOnWake),
            state: settings.changeOnWake ? .on : .off)
        m.addItem(.separator())

        let hint = NSMenuItem(title: "Kéo xong là tự khe vào lưới", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        m.addItem(hint)
        add(m, "Đặt tự do (không khe lưới)", #selector(toggleSnap),
            state: settings.snapToGrid ? .off : .on)
        add(m, paused ? "Tiếp tục phát" : "Tạm dừng",
            #selector(togglePause), state: paused ? .on : .off)

        m.addItem(.separator())
        add(m, "Xoá cache ảnh", #selector(clearImageCache))
        add(m, "Thoát LitePic", #selector(quitApp))

        return m
    }

    private func intervalMenu() -> NSMenu {
        let sub = NSMenu()
        add(sub, "Ngẫu nhiên", #selector(toggleRandom), state: settings.randomInterval ? .on : .off)
        sub.addItem(.separator())
        for (label, secs) in Self.intervalChoices {
            add(sub, label, #selector(pickInterval), tag: secs,
                state: !settings.randomInterval && settings.interval == Double(secs) ? .on : .off)
        }
        return sub
    }

    private func sizeMenu() -> NSMenu {
        let sub = NSMenu()
        for mode in SizeMode.allCases {
            add(sub, mode.title, #selector(pickSizeMode), tag: mode.rawValue,
                state: settings.sizeMode == mode ? .on : .off)
        }
        sub.addItem(.separator())

        switch settings.sizeMode {
        case .fitImage:
            for edge in Self.maxEdgeChoices {
                add(sub, "Cạnh lớn \(edge)pt", #selector(pickMaxEdge), tag: edge,
                    state: Int(settings.maxEdge) == edge ? .on : .off)
            }
        case .fitWidth:
            for w in Self.widthChoices {
                add(sub, "Rộng \(Int(w))pt", #selector(pickWidth), tag: Int(w),
                    state: Int(settings.width) == Int(w) ? .on : .off)
            }
        case .fixed:
            for (label, w, h) in Self.fixedChoices {
                let mi = NSMenuItem(title: label, action: #selector(pickFixed), keyEquivalent: "")
                mi.target = self
                mi.tag = Int(w)
                mi.representedObject = ["w": w, "h": h]
                mi.state = (Int(settings.width), Int(settings.height)) == (Int(w), Int(h)) ? .on : .off
                sub.addItem(mi)
            }
        }
        return sub
    }

    /// `addItem` trả về Void, nên không thể gắn `.state` kiểu nối chuỗi — dựng item trước.
    private func add(_ menu: NSMenu,
                     _ title: String,
                     _ action: Selector,
                     tag: Int = 0,
                     state: NSControl.StateValue = .off) {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.tag = tag
        mi.state = state
        menu.addItem(mi)
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.submenu = menu
        return mi
    }

    // MARK: - Nguồn ảnh

    private func reload() {
        images = ImageStore.files(in: settings.folders)
        lastIndex = -1
        rebuildMenu()
        scheduleTimer()
        pruneCache()
        if !images.isEmpty {
            // KHÔNG giải mã hết loạt ảnh lúc mở. Bản cũ làm vậy và đo được:
            // CPU +1.25s, RAM 24 MB -> 52 MB, trong khi phần lớn ảnh đó không
            // bao giờ được xem. Ảnh giờ được giải mã khi thật sự cần, ngoài luồng
            // chính, và nhớ lại trong RAM cho lần xem sau.
            ImageStore.clearMemory()
            advance()
            // Cửa sổ khác đang che widget? Tự nâng lên tầng nổi để bấm được.
            if widget.autoLiftIfOccluded() { rebuildMenu() }
        }
    }

    @objc private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Chọn"
        panel.message = "Chọn một hoặc nhiều thư mục chứa ảnh"
        guard panel.runModal() == .OK else { return }
        settings.folderPaths = panel.urls.map(\.path)
        reload()
    }

    @objc private func clearFolders() {
        settings.folderPaths = []
        images = []
        timer?.invalidate()
        timer = nil
        rebuildMenu()
    }

    // MARK: - Timer

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard !paused, !screenAsleep, images.count > 1 else { return }

        let interval: TimeInterval
        if settings.randomInterval {
            let lo = min(settings.minInterval, settings.maxInterval)
            let hi = max(settings.minInterval, settings.maxInterval)
            interval = Double.random(in: lo...max(lo + 1, hi))
        } else {
            interval = settings.interval
        }

        // Timer không lặp: hẹn lại sau mỗi lần đổi, nên nhịp ngẫu nhiên thực sự ngẫu nhiên.
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.advance()
            self.scheduleTimer()
        }
        // Cho phép hệ thống gom lại để tiết kiệm năng lượng.
        t.tolerance = interval * 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func advance() {
        guard !images.isEmpty else { return }
        // Đang giữ/kéo widget mà đổi ảnh thì cửa sổ đổi kích thước và giật
        // khỏi tay người dùng — thử lại sau 5 giây thay vì đổi ngay.
        //
        // Chỉ hẹn MỘT lần thử lại. Bản cũ hẹn mới mỗi lần gặp: nếu người dùng
        // giữ chuột kéo widget, cứ 5 giây lại dồn thêm một hẹn giờ, và khi thả
        // ra cả đống cùng chạy — mỗi cái lại tự hẹn thêm một cái nữa.
        if widget.busy {
            guard !retryScheduled else { return }
            retryScheduled = true
            Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                self?.retryScheduled = false
                self?.advance()
            }
            return
        }
        // Ảnh đã ghim: đứng yên.
        if isPinned { showPinnedIfNeeded(); return }
        var idx: Int
        if images.count == 1 {
            idx = 0
        } else {
            idx = Int.random(in: 0..<images.count)
            if idx == lastIndex { idx = (idx + 1) % images.count }  // tránh lặp lại liên tiếp
        }
        lastIndex = idx
        widget.show(images[idx])
    }

    private func showPinnedIfNeeded() {
        guard let p = settings.pinnedURL,
              images.contains(where: { $0.path == p }) else { return }
        if images[lastIndex].path != p, let i = images.firstIndex(where: { $0.path == p }) {
            lastIndex = i
            widget.show(images[i])
        }
    }

    /// Bước tới ảnh kế tiếp/trước — có xét ảnh ghim.
    private func step(_ delta: Int) {
        guard !images.isEmpty else { return }
        // pool các ảnh được phép hiện (bỏ ảnh đang ghim nếu còn ảnh khác)
        var pool = images
        if isPinned, images.count > 1 {
            pool = images.filter { $0.path != settings.pinnedURL }
        }
        guard !pool.isEmpty else { return }
        let cur = images[lastIndex]
        let curInPool = pool.firstIndex(of: cur) ?? 0
        let next = ((curInPool + delta) % pool.count + pool.count) % pool.count
        if let i = images.firstIndex(of: pool[next]) {
            lastIndex = i
            widget.show(images[i])
        }
        rebuildMenu()
    }

    private func togglePin() {
        if isPinned {
            settings.pinnedURL = nil
        } else if images.indices.contains(lastIndex) {
            settings.pinnedURL = images[lastIndex].path
        }
        widget.setPinned(isPinned)
        rebuildMenu()
    }

    private func applyAppearance() {
        widget.applyAll()
        // Đổi cỡ từ menu là chủ động của người dùng nên áp dụng ngay kể cả khi bận.
        if lastIndex >= 0 && lastIndex < images.count { widget.show(images[lastIndex], evenIfBusy: true) }
        pruneCache()
        rebuildMenu()
    }

    /// Dọn cache của các mức kích thước không còn dùng.
    ///
    /// Mỗi mức là một bộ file riêng, nên đổi cỡ widget hay hạ chất lượng sẽ để lại
    /// mức cũ mãi mãi. Gọi ở mọi lần đổi kích thước hiển thị.
    private func pruneCache() {
        ImageStore.pruneCache(keepPixels: ImageStore.pixelBucket(for: widget.displayMaxPixel))
    }

    // MARK: - Hành động menu

    @objc private func toggleRandom() {
        settings.randomInterval.toggle()
        scheduleTimer()
        rebuildMenu()
    }

    @objc private func pickInterval(_ sender: NSMenuItem) {
        settings.interval = Double(sender.tag)
        settings.randomInterval = false
        scheduleTimer()
        rebuildMenu()
    }

    @objc private func pickSizeMode(_ sender: NSMenuItem) {
        settings.sizeMode = SizeMode(rawValue: sender.tag) ?? .fitImage
        applyAppearance()
    }

    @objc private func pickMaxEdge(_ sender: NSMenuItem) {
        settings.maxEdge = CGFloat(sender.tag)
        applyAppearance()
    }

    @objc private func pickWidth(_ sender: NSMenuItem) {
        settings.width = CGFloat(sender.tag)
        applyAppearance()
    }

    @objc private func pickFixed(_ sender: NSMenuItem) {
        if let d = sender.representedObject as? [String: CGFloat] {
            settings.width = d["w"] ?? 480
            settings.height = d["h"] ?? 480
        }
        applyAppearance()
    }

    @objc private func pickOpacity(_ sender: NSMenuItem) {
        settings.opacity = CGFloat(sender.tag) / 100
        widget.applyOpacity()
        rebuildMenu()
    }

    @objc private func pickRenderScale(_ sender: NSMenuItem) {
        settings.renderScale = CGFloat(sender.tag)
        pruneCache()
        rebuildMenu()
        if lastIndex >= 0 && lastIndex < images.count { widget.show(images[lastIndex], evenIfBusy: true) }
    }

    @objc private func pickFrame(_ sender: NSMenuItem) {
        settings.frameStyle = FrameStyle(rawValue: sender.tag) ?? .shadow
        widget.applyAll()
        if lastIndex >= 0 && lastIndex < images.count { widget.show(images[lastIndex], evenIfBusy: true) }
        rebuildMenu()
    }

    @objc private func toggleChangeOnWake() {
        settings.changeOnWake.toggle()
        rebuildMenu()
    }

    @objc private func pickLevel(_ sender: NSMenuItem) {
        settings.levelMode = LevelMode(rawValue: sender.tag) ?? .floating
        widget.applyLevel()
        rebuildMenu()
    }

    @objc private func toggleSnap() {
        settings.snapToGrid.toggle()
        if settings.snapToGrid {
            // Bật lại thì kéo widget về đúng ô luôn.
            widget.settleNow()
        }
        rebuildMenu()
    }

    @objc private func togglePause() {
        paused.toggle()
        scheduleTimer()
        rebuildMenu()
    }

    @objc private func clearImageCache() {
        ImageStore.clearCache()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}