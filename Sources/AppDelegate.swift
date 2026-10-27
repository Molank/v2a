import AppKit
import SwiftUI

/// 无边框面板默认不能成为 key window，需要重写才能输入文字
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// 输入光标用主题紫
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)
        if let editor = responder as? NSTextView {
            editor.insertionPointColor = NSColor(red: 0x7C / 255,
                                                 green: 0x3A / 255,
                                                 blue: 0xED / 255,
                                                 alpha: 1)
        }
        return result
    }
}

/// 无边框窗口里，让背景也能拖动
final class MovableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var helperPanel: NSPanel?
    private var linkPanel: NSPanel?
    private let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 每次启动清掉上次的封面缓存，避免 /tmp 堆积
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("v2a-covers", isDirectory: true)
        )
        NSApp.mainMenu = makeMenu()
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(showDragHelper),
                                               name: .v2aShowDragHelper,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(showLinkWindow),
                                               name: .v2aShowLinkWindow,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(closeLinkWindow),
                                               name: .v2aCloseLinkWindow,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(dragAccepted),
                                               name: .v2aDragAccepted,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(resizeLinkWindow),
                                               name: .v2aLinkWindowResize,
                                               object: nil)

        // 主窗口没有可聚焦控件，SwiftUI 的 onPasteCommand 收不到 ⌘V，
        // 这里在 AppKit 层接一次：只在主窗口、且不在编辑文本时生效。
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handlePasteShortcut(event) ?? event
        }
        handleLaunchArguments()
    }

    /// 调试用：--snapshot <png> [--files <视频...>] [--convert] [--popover]
    private func handleLaunchArguments() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count else { return }
        let outputPath = arguments[flag + 1]

        if let filesFlag = arguments.firstIndex(of: "--files") {
            let paths = arguments[(filesFlag + 1)...].filter { $0 != outputPath && !$0.hasPrefix("--") }
            model.add(urls: paths.map { URL(fileURLWithPath: $0) })
        }

        if let setFlag = arguments.firstIndex(of: "--set"), setFlag + 1 < arguments.count {
            applySettings(arguments[setFlag + 1])
        }

        if let presetFlag = arguments.firstIndex(of: "--save-preset"), presetFlag + 1 < arguments.count {
            model.savePreset(named: arguments[presetFlag + 1])
        }

        // 调试：--trim 2/5 走真实的裁剪流程
        if let trimFlag = arguments.firstIndex(of: "--trim"), trimFlag + 1 < arguments.count {
            let parts = arguments[trimFlag + 1].split(separator: "/").map(String.init)
            if parts.count == 2, let item = model.items.first,
               let start = MediaItem.parseTime(parts[0]),
               let end = MediaItem.parseTime(parts[1]) {
                model.applyTrim(itemID: item.id, start: start, end: end)
            }
        }

        // 调试：--name "新名字" 走真实的重命名流程
        if let linkFlag = arguments.firstIndex(of: "--link"), linkFlag + 1 < arguments.count {
            let link = arguments[linkFlag + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.model.addLink(link)
            }
        }

        if let nameFlag = arguments.firstIndex(of: "--name"), nameFlag + 1 < arguments.count {
            if let item = model.items.first {
                model.beginRename(item)
                model.renameDraft = arguments[nameFlag + 1]
                model.applyRename()
            }
        }

        let autoConvert = arguments.contains("--convert")
        if autoConvert {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.model.convertAll()
            }
        }

        if arguments.contains("--show-trim") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, let current = self.model.items.first else { return }
                self.model.beginTrim(current)
            }
        }

        if arguments.contains("--show-rename"), let item = model.items.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.model.beginRename(item)
            }
        }

        if arguments.contains("--hq") { model.highQualityDownload = true }
        if let cookieFlag = arguments.firstIndex(of: "--cookies"), cookieFlag + 1 < arguments.count {
            model.cookieBrowser = arguments[cookieFlag + 1]
        }

        if let kc = arguments.firstIndex(of: "--keychain"), kc + 1 < arguments.count {
            model.keychainGranted = arguments[kc + 1] == "true"
        }

        if arguments.contains("--dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if let langFlag = arguments.firstIndex(of: "--lang"), langFlag + 1 < arguments.count {
            Localization.shared.language = AppLanguage(rawValue: arguments[langFlag + 1]) ?? .system
        }
        if arguments.contains("--light") {
            NSApp.appearance = NSAppearance(named: .aqua)
        }

        if arguments.contains("--permissions") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.model.showGeneralSettings = true
            }
        }

        if arguments.contains("--draghelper") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showDragHelper()
            }
        }

        if let pre = arguments.firstIndex(of: "--prefill"), pre + 1 < arguments.count {
            model.linkField = arguments[pre + 1]
        }

        if arguments.contains("--linkui") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.model.beginLink(nil)
            }
        }

        if arguments.contains("--popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.model.showSettings = true
            }
        }

        let overlays = arguments.contains("--popover") || arguments.contains("--linkui")
            || arguments.contains("--draghelper") || arguments.contains("--permissions")
            || arguments.contains("--show-trim")
            || arguments.contains("--show-rename")
        if let iconsFlag = arguments.firstIndex(of: "--icons"), iconsFlag + 1 < arguments.count {
            let path = arguments[iconsFlag + 1]
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            panel.contentView = NSHostingView(rootView: FormatBadgeGallery())
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if let view = panel.contentView { self.save(view: view, to: path) }
                exit(0)
            }
            return
        }

        if arguments.contains("--dump") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                if let view = self?.window?.contentView { self?.dump(view) }
                exit(0)
            }
            return
        }

        var delay: TimeInterval = autoConvert ? 6.0 : (overlays ? 2.6 : 2.0)
        if arguments.contains("--link") { delay = 6.0 }
        if let delayFlag = arguments.firstIndex(of: "--delay"),
           delayFlag + 1 < arguments.count,
           let value = Double(arguments[delayFlag + 1]) {
            delay = value
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.writeSnapshot(to: outputPath)
            self?.writeExtraWindowSnapshots(base: outputPath)
            exit(0)   // 有 sheet/alert 挂着时 terminate 会被拦，直接退出
        }
    }

    /// 调试用：--set "mp3/320/44100/1" 直接设定格式/码率/采样率/音轨
    private func applySettings(_ spec: String) {
        let parts = spec.split(separator: "/").map(String.init)
        if parts.count > 0, let format = OutputFormat(rawValue: parts[0]) { model.settings.format = format }
        if parts.count > 1, let bitrate = Int(parts[1]) { model.settings.bitrate = bitrate }
        if parts.count > 2, let rate = Int(parts[2]) { model.settings.sampleRate = rate }
        if parts.count > 3, let track = Int(parts[3]) { model.settings.track = track }
        if parts.count > 4, let channels = Int(parts[4]) { model.settings.channels = channels }
    }

    private func dump(_ view: NSView, depth: Int = 0) {
        let pad = String(repeating: "  ", count: depth)
        print("\(pad)\(type(of: view)) frame=\(view.frame) bounds=\(view.bounds)")
        if depth == 0, let window { print("WINDOW frame=\(window.frame) contentRect=\(window.contentRect(forFrameRect: window.frame))") }
        for sub in view.subviews { dump(sub, depth: depth + 1) }
    }

    private func writeSnapshot(to path: String) {
        guard let window, let view = window.contentView else { return }
        save(view: view, to: path)
    }

    /// 弹窗等独立窗口单独存一张，方便检查
    private func writeExtraWindowSnapshots(base: String) {
        var index = 1
        for other in NSApp.windows where other !== window && other.isVisible {
            guard let view = other.contentView, view.bounds.width > 40 else { continue }
            let url = URL(fileURLWithPath: base)
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let path = url.deletingLastPathComponent()
                .appendingPathComponent("\(name)-window\(index).\(ext)")
            save(view: view, to: path.path)
            index += 1
        }
    }

    private func save(view: NSView, to path: String) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.add(urls: urls)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildWindow() {
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active

        // 标题栏区域垫一层 Liquid Glass（macOS 26+），和系统默认窗口一致
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                glass.topAnchor.constraint(equalTo: effect.topAnchor),
                glass.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
            ])
        }

        let host = NSHostingView(rootView: ContentView().environmentObject(model).environmentObject(Localization.shared))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "V2A"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.minSize = NSSize(width: 620, height: 540)
        window.contentView = effect
        window.center()
        window.setFrameAutosaveName("V2AMainWindow")
        // 恢复的位置若已不在任何屏幕上（拔掉外接屏等），回到主屏居中
        let screens = NSScreen.screens
        if !screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 V2A",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        let permissions = appMenu.addItem(withTitle: "偏好设置…",
                                          action: #selector(showPermissions(_:)),
                                          keyEquivalent: "")
        permissions.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 V2A",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 V2A",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        let open = fileMenu.addItem(withTitle: "添加文件…",
                                    action: #selector(addFiles(_:)),
                                    keyEquivalent: "o")
        open.target = self
        let clear = fileMenu.addItem(withTitle: "清空列表",
                                     action: #selector(clearList(_:)),
                                     keyEquivalent: "k")
        clear.target = self
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return main
    }

    @objc private func showDragHelper() {
        if helperPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 96),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: DragHelperView { [weak self] in
                self?.helperPanel?.orderOut(nil)
            }
            .environmentObject(Localization.shared))
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                // 没有窗口坐标权限时的锚点：左侧垂直居中，绝不和居中的系统设置窗口重叠
                panel.setFrameOrigin(NSPoint(x: frame.minX + 24, y: frame.midY - 48))
            }
            helperPanel = panel
        }
        helperPanel?.orderFrontRegardless()
        trackSystemSettings(attempts: 12)
    }

    /// 等系统设置窗口出现，把拖拽条贴到它下方
    private func trackSystemSettings(attempts: Int) {
        if let frame = systemSettingsFrame() {
            placeHelper(below: frame)
            return
        }
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.trackSystemSettings(attempts: attempts - 1)
        }
    }

    private func placeHelper(below settings: CGRect) {
        guard let panel = helperPanel else { return }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        // CGWindow 坐标是以主屏左上角为原点，这里翻成 Cocoa 的下左原点
        let cocoaY = mainHeight - settings.origin.y - settings.height
        let cocoaRect = CGRect(x: settings.origin.x, y: cocoaY,
                               width: settings.width, height: settings.height)

        let size = panel.frame.size
        var x = cocoaRect.midX - size.width / 2
        var y = cocoaRect.minY - size.height - 10

        let screen = NSScreen.screens.first { $0.frame.intersects(cocoaRect) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if y < visible.minY + 8 {
                y = cocoaRect.maxY + 10          // 下面放不下就放上面
            }
            x = min(max(x, visible.minX + 12), visible.maxX - size.width - 12)
            y = min(max(y, visible.minY + 12), visible.maxY - size.height - 12)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func systemSettingsFrame() -> CGRect? {
        // optionAll：系统设置可能在其他 Space，只取 onScreen 会漏掉主窗口
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var best: CGRect?
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String else { continue }
            guard owner == "System Settings" || owner == "系统设置" else { continue }
            let rawBounds = info[kCGWindowBounds as String]
            guard let bounds = rawBounds as? NSDictionary else {
                continue
            }
            func value(_ key: String) -> CGFloat {
                (bounds[key] as? NSNumber)?.doubleValue ?? 0
            }
            let rect = CGRect(x: value("X"), y: value("Y"),
                              width: value("Width"), height: value("Height"))
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0, rect.width > 400, rect.height > 260 else { continue }
            if best == nil || rect.width * rect.height > best!.width * best!.height {
                best = rect
            }
        }
        return best
    }

    private func handlePasteShortcut(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v",
              let key = NSApp.keyWindow, key === window else { return event }
        // 正在输入框里（字段编辑器）编辑时，把 ⌘V 还给系统
        if key.firstResponder is NSTextView { return event }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard let link = AppModel.extractLink(from: text) else { return event }
        model.beginLink(link)
        return nil
    }

    @objc private func showLinkWindow() {
        if linkPanel == nil {
            let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                                     styleMask: [.borderless],
                                     backing: .buffered,
                                     defer: false)
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(
                rootView: LinkOptionsView(model: model) { [weak self] in
                    self?.linkPanel?.orderOut(nil)
                }
                .environmentObject(Localization.shared)
            )
            linkPanel = panel
        }
        if let host = linkPanel?.contentView {
            linkPanel?.setContentSize(host.fittingSize)
        }
        positionLinkPanel()
        linkPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func resizeLinkWindow() {
        guard let panel = linkPanel, let host = panel.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.height > 0 else { return }
        panel.setContentSize(size)
    }

    /// 默认出现在主窗口正中，可拖动
    private func positionLinkPanel() {
        guard let panel = linkPanel, let main = window else {
            linkPanel?.center()
            return
        }
        let size = panel.frame.size
        let x = main.frame.midX - size.width / 2
        let y = main.frame.midY - size.height / 2
        var origin = NSPoint(x: x, y: y)
        if let screen = main.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 16), visible.maxX - size.width - 16)
            origin.y = min(max(origin.y, visible.minY + 16), visible.maxY - size.height - 16)
        }
        panel.setFrameOrigin(origin)
    }

    @objc private func closeLinkWindow() {
        linkPanel?.orderOut(nil)
    }

    /// 拖进「完全磁盘访问」后收起浮窗，并刷新一次权限状态
    @objc private func dragAccepted() {
        helperPanel?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.model.refreshPermissions()
        }
    }

    @objc private func showPermissions(_ sender: Any?) {
        model.refreshPermissions()
        model.showGeneralSettings = true
    }

    @objc private func addFiles(_ sender: Any?) {
        model.presentOpenPanel()
    }

    @objc private func clearList(_ sender: Any?) {
        model.clear()
    }
}
