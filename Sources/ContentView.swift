import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var l10n: Localization
    @StateObject private var dropState = DropState()
    @StateObject private var layout = LayoutState()
    @FocusState private var linkFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                content
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
            }
            footer
        }
        .frame(minWidth: 620, minHeight: 540)
        .onPreferenceChange(BarHeightKey.self) { layout.barHeight = $0 }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropState.targeted, perform: handleDrop)
        .overlay {
            if dropState.targeted { dropOverlay }
        }
        .animation(.easeInOut(duration: 0.15), value: dropState.targeted)
        .sheet(isPresented: trimPresented) {
            if let item = model.trimTargetItem {
                TrimSheet(app: model, item: item)
            }
        }
        .alert("存储为预设", isPresented: $model.savingPreset) {
            TextField(l10n.t("预设名称"), text: $model.presetName)
            Button("取消", role: .cancel) { }
            Button(l10n.t("存储")) {
                model.savePreset(named: model.presetName)
            }
        } message: {
            Text(l10n.t("当前的格式、比特率、采样率、声道与音轨会被保存，之后可在预设菜单里随时调用。"))
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("V2A")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Video to Audio")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.v2aTertiary)
                }
                Text(l10n.t("音视频下载 ｜ 视频提取音频"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.v2aSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !model.items.isEmpty {
                CircleIconButton(symbol: "trash", size: 34, help: l10n.t("清空列表")) {
                    model.clear()
                }
                .disabled(model.isRunning)
            }
            CircleIconButton(symbol: "link", size: 34, help: l10n.t("粘贴视频链接（YouTube / B 站等）")) {
                model.beginLink(nil)
            }
            .disabled(model.isRunning || !model.canAcceptLinks)

            CircleIconButton(symbol: "plus", size: 34, help: l10n.t("添加视频（⌘O）")) {
                model.presentOpenPanel()
            }
            .disabled(model.isRunning)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 13)
        .background(Color.clear)
        .sheet(isPresented: $model.showOnboarding) {
            onboardingSheet
        }
    }

    // MARK: - 首次启动的权限说明

    private var onboardingSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: AppIconImage.shared)
                    .resizable()
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("下载授权"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(l10n.t("不开启也能使用，但无法下载需要会员登录的内容"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.v2aSecondary)
                }
            }

            permissionRow(icon: "lock.shield.fill",
                          title: l10n.t("完全磁盘访问"),
                          detail: l10n.t("下载会员内容的必要权限。"))

            Text(l10n.t("路径：系统设置 → 隐私与安全性 → 完全磁盘访问，把 V2A 打开后重启 App。"))
                .font(.system(size: 10.5))
                .foregroundStyle(Color.v2aTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(l10n.t("打开系统设置")) { model.openFullDiskAccessSettings() }
                    .buttonStyle(SoftButtonStyle())
                Spacer()
                Button(l10n.t("知道了")) { model.dismissOnboarding() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(FrostedBackground())
        .background(ClearWindowBackground())
    }

    private func permissionRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.v2aAccent.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.v2aAccent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.v2aSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.45))
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty && model.downloads.isEmpty {
            emptyState
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, layout.barHeight + 29)
        } else {
            fileList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Color.v2aAccent.opacity(0.16),
                                                Color.v2aAccent.opacity(0.07)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(Color.v2aAccent)
                    .offset(y: 0.5)
            }
            .frame(width: 76, height: 76)
            .shadow(color: Color.v2aAccent.opacity(0.10), radius: 8, y: 2)
            VStack(spacing: 5) {
                Text(l10n.t("拖入视频，或直接粘贴链接"))
                    .font(.system(size: 14, weight: .medium))
                Text(l10n.t("视频支持 MP4、MOV、MKV、AVI、WebM、TS 等，也可整个文件夹拖入\n按 ⌘V 粘贴 YouTube / B 站 等链接"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.v2aSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            Button(l10n.t("选择文件…")) {
                model.presentOpenPanel()
            }
            .buttonStyle(SoftButtonStyle())
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10),
                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.downloads) { task in
                    DownloadRow(task: task,
                                onCancel: { model.cancelDownload(task.id) },
                                onDismiss: { model.dismissDownloadError(task.id) })
                }
                ForEach(model.items) { item in
                    FileRow(item: item,
                            locked: model.isRunning,
                            estimateText: model.sizeColumnText(for: item),
                            outputName: model.outputFileName(for: item),
                            showsOutputName: item.customName != nil || item.outputURL != nil,
                            onRename: { model.beginRename(item) },
                            onTrim: { model.beginTrim(item) },
                            onRemove: { model.remove(item.id) },
                            onReveal: {
                                // 已转换优先显示输出文件，否则显示源文件（含网络下载的视频）
                                model.reveal(item.outputURL ?? item.url)
                            })
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, layout.barHeight + 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: renamePresented) {
            renameSheet
        }
    }

    // MARK: - 重命名

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("重命名输出"))
                    .font(.system(size: 15, weight: .semibold))
                Text(l10n.t("只需要写文件名，扩展名会自动保留"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.v2aSecondary)
            }

            HStack(spacing: 7) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.v2aSecondary)
                TextField(l10n.t("文件名"), text: $model.renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit { model.applyRename() }
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background { GlassButtonBackground(height: 34) }
            .clipShape(Capsule())

            if let error = model.renameError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Spacer()
                Button(l10n.t("取消")) { model.renamingItemID = nil }
                    .buttonStyle(SoftButtonStyle(minWidth: 76))
                    .keyboardShortcut(.cancelAction)
                Button(l10n.t("重命名")) { model.applyRename() }
                    .buttonStyle(PillButtonStyle(minWidth: 76))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(width: 380)
        .background(FrostedBackground())
        .background(ClearWindowBackground())
    }

    // MARK: - 底部面板

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                audioSettingsButton

                Spacer(minLength: 0)

                CircleIconButton(symbol: "gearshape", size: 30, help: l10n.t("偏好设置")) {
                    model.showGeneralSettings = true
                }
                .disabled(model.isRunning)
            }

            HStack(spacing: 10) {
                destinationMenu
                Spacer(minLength: 0)
                Text(model.summary ?? statusHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.v2aSecondary)
                    .lineLimit(1)
                if model.isRunning {
                    Button(l10n.t("取消")) { model.cancel() }
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                }
                convertButton
            }

            if model.isRunning {
                ProgressView(value: model.batchProgress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.03))
                    .blur(radius: 4)
                    .offset(y: 1)
                    .padding(-1)
                BarGlassBackground(cornerRadius: 22)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: BarHeightKey.self, value: proxy.size.height)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .sheet(isPresented: $model.showGeneralSettings) {
            GeneralSettingsView(model: model) { model.showGeneralSettings = false }
        }
    }

    private var statusHint: String {
        guard !model.items.isEmpty else { return l10n.t("尚未添加文件") }
        let done = model.items.filter { $0.status.isDone }.count
        if done == model.items.count { return "全部完成" }
        return "\(model.items.count) 个待处理"
    }

    private var convertButton: some View {
        let disabled = model.items.isEmpty || model.isRunning
        return Button {
            model.convertAll()
        } label: {
            HStack(spacing: 6) {
                if model.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "waveform")
                }
                Text(model.isRunning
                     ? "\(l10n.t("提取中")) \(Int(model.batchProgress * 100))%"
                     : l10n.t("开始提取"))
                    .font(.system(size: 12.5, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(disabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            .frame(minWidth: 104)
            .frame(height: 30)
            .padding(.horizontal, 10)
            .background {
                if disabled {
                    Capsule().fill(Color.primary.opacity(0.055))
                } else {
                    AccentGlassBackground()
                }
            }
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(disabled ? 0 : 0.18), lineWidth: 0.6)
            }
            .shadow(color: Color.black.opacity(disabled ? 0 : 0.06), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .keyboardShortcut(.defaultAction)
    }

    private var destinationMenu: some View {
        Menu {
            Button {
                model.useSourceFolder = true
            } label: {
                Label(l10n.t("与源文件同目录"), systemImage: "doc")
            }
            Button {
                model.presentOutputPanel()
            } label: {
                Label("选择文件夹…", systemImage: "folder")
            }
        } label: {
            Label(model.destinationLabel, systemImage: "folder")
                .font(.system(size: 11.5))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isRunning)
    }

    /// 底栏左侧：格式 + 参数摘要，点开是完整的音频设置
    private var audioSettingsButton: some View {
        Button {
            model.showSettings.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(model.settings.format.label)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(summaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.v2aSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color.v2aTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color.primary.opacity(0.055)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $model.showSettings, arrowEdge: .bottom) {
            settingsPopover
        }
        .help("格式 / 比特率 / 采样率 / 声道 / 音轨 / 预设")
        .disabled(model.isRunning)
    }

    private var summaryText: String {
        var parts: [String] = []
        parts.append(model.settings.format.isLossless ? "无损" : "\(model.settings.bitrate) kbps")
        switch model.settings.channels {
        case 1: parts.append("单声道")
        case 2: parts.append("立体声")
        default: break
        }
        if model.settings.sampleRate > 0 { parts.append("\(model.settings.sampleRate / 1000) kHz") }
        return parts.joined(separator: " · ")
    }

    private var presetMenu: some View {
        Menu {
            if model.presets.isEmpty {
                Text(l10n.t("还没有预设"))
            } else {
                ForEach(model.presets) { preset in
                    Button {
                        model.applyPreset(preset)
                    } label: {
                        if model.matchingPreset?.id == preset.id {
                            Label(preset.name, systemImage: "checkmark")
                        } else {
                            Text(preset.name)
                        }
                    }
                }
                Divider()
                Menu("删除预设") {
                    ForEach(model.presets) { preset in
                        Button(preset.name) { model.deletePreset(preset) }
                    }
                }
                Divider()
            }
            Button(l10n.t("存储当前设置为预设…")) {
                model.presetName = ""
                model.savingPreset = true
            }
        } label: {
            Label(model.matchingPreset?.name ?? "自定义设置",
                  systemImage: model.matchingPreset == nil ? "bookmark" : "bookmark.fill")
                .font(.system(size: 11.5))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isRunning)
        .help("调用或保存音频预设")
    }

    // MARK: - 设置弹窗

    private var hintText: String {
        if model.settings.format.isLossless {
            return l10n.t("无损格式不使用比特率；采样率、声道选「跟随源」时保持原样。")
        }
        return l10n.t("比特率只作用于有损格式。采样率和声道都选「跟随源」、且源音轨已是目标编码时，会直接抽流不重新编码；一旦改动就会强制重编码。")
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("音频设置"))
                .font(.system(size: 12, weight: .semibold))

            SettingRow(l10n.t("格式")) {
                FormatSegmented(selection: $model.settings.format)
            }

            SettingRow(l10n.t("预设")) {
                presetMenu
            }

            SettingRow(l10n.t("比特率")) {
                Menu {
                    ForEach(AudioSettings.bitrateChoices, id: \.self) { value in
                        menuItem("\(value) kbps", selected: model.settings.bitrate == value) {
                            model.settings.bitrate = value
                        }
                    }
                } label: {
                    Text(model.settings.format.isLossless ? "无损" : "\(model.settings.bitrate) kbps")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.settings.format.isLossless)
            }

            SettingRow(l10n.t("采样率")) {
                Menu {
                    menuItem("跟随源", selected: model.settings.sampleRate == 0) {
                        model.settings.sampleRate = 0
                    }
                    ForEach([22050, 44100, 48000, 96000], id: \.self) { value in
                        menuItem(sampleRateText(value), selected: model.settings.sampleRate == value) {
                            model.settings.sampleRate = value
                        }
                    }
                } label: {
                    Text(sampleRateText(model.settings.sampleRate))
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            SettingRow(l10n.t("输出声道")) {
                Menu {
                    menuItem("跟随源", selected: model.settings.channels == 0) {
                        model.settings.channels = 0
                    }
                    menuItem("单声道", selected: model.settings.channels == 1) {
                        model.settings.channels = 1
                    }
                    menuItem("立体声", selected: model.settings.channels == 2) {
                        model.settings.channels = 2
                    }
                } label: {
                    Text(model.settings.channelLabel)
                        .font(.system(size: 11.5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            SettingRow(l10n.t("音轨")) {
                Menu {
                    ForEach(model.trackChoices, id: \.self) { index in
                        menuItem(model.trackLabel(index), selected: model.settings.track == index) {
                            model.settings.track = index
                        }
                    }
                } label: {
                    Text(model.trackLabel(model.settings.track))
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Divider()

            Text(hintText)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.v2aTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 350)
    }

    private func menuItem(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func sampleRateText(_ rate: Int) -> String {
        switch rate {
        case 0: return "跟随源"
        case 22050: return "22.05 kHz"
        default: return "\(rate / 1000) kHz"
        }
    }

    // MARK: - 裁剪面板

    private var trimPresented: Binding<Bool> {
        Binding(get: { model.trimmingItemID != nil },
                set: { if !$0 { model.trimmingItemID = nil } })
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { model.renamingItemID != nil },
                set: { if !$0 { model.renamingItemID = nil } })
    }

    private var dropOverlay: some View {
        ZStack {
            Color.v2aAccent.opacity(0.05)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.v2aAccent.opacity(0.85),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .padding(9)
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.v2aAccent)
                Text(l10n.t("松手即可添加"))
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(18)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .allowsHitTesting(false)
    }

    // MARK: - 拖放

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let model = model
        let lock = NSLock()
        var received: [URL] = []
        let group = DispatchGroup()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let text = item as? String, let parsed = URL(string: text) {
                    url = parsed
                } else if let direct = item as? URL {
                    url = direct
                }
                if let url {
                    lock.lock()
                    received.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            let urls = received
            Task { @MainActor in
                model.add(urls: urls)
            }
        }
        return true
    }
}

// MARK: - 拖拽助手

enum AppIconImage {
    static let shared: NSImage = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }()
}

/// 悬浮长条：白色内板是拖拽源，外框拖动整个面板
struct DragHelperView: View {
    @EnvironmentObject private var l10n: Localization
    var onDone: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        innerPlate
            .padding(10)
            .frame(width: 540, height: 96)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
    }

    private var innerPlate: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconImage.shared)
                .resizable()
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("拖我到右侧的「完全磁盘访问」列表"))
                    .font(.system(size: 12, weight: .medium))
                Text(l10n.t("松开即可添加 V2A"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.v2aSecondary)
            }

            Spacer(minLength: 8)

            Button(l10n.t("完成")) { onDone() }
                .controlSize(.small)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: Color.black.opacity(hover.on ? 0.14 : 0.08), radius: 3, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            // 盖一层原生拖拽区：右侧留出「完成」按钮，不抢点击
            AppDragArea()
                .padding(.trailing, 92)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { hover.on = $0 }
        .help("按住白色区域，拖到「完全磁盘访问」列表里")
    }
}

/// 用 NSDraggingSession 拖 .app 本身，比 NSItemProvider 更容易被系统设置接受
struct AppDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragSourceView {
        DragSourceView()
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {}
}

final class DragSourceView: NSView, NSDraggingSource {
    override func mouseDown(with event: NSEvent) {
        let url = Bundle.main.bundleURL
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(
            NSRect(x: 0, y: 0, width: 48, height: 48),
            contents: icon
        )
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    /// 拖放被接收（operation 非空）说明真的落进了列表
    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        guard operation != [] else { return }
        NotificationCenter.default.post(name: .v2aDragAccepted, object: nil)
    }
}

// MARK: - 下载行

private struct DownloadRow: View {
    let task: DownloadTask
    var onCancel: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.v2aAccent.opacity(0.12))
                Image(systemName: "globe")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.v2aAccent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let error = task.error {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 8) {
                        ProgressView(value: task.progress)
                            .progressViewStyle(.linear)
                            .frame(width: 160)
                        Text(task.progress > 0 ? "\(Int(task.progress * 100))%" : "连接中…")
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(Color.v2aSecondary)
                    }
                }
            }
            Spacer(minLength: 8)

            Button(action: task.error == nil ? onCancel : onDismiss) {
                Image(systemName: task.error == nil ? "xmark.circle.fill" : "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.v2aTertiary)
            }
            .buttonStyle(.borderless)
            .help(task.error == nil ? "取消下载" : "移除")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
    }
}

// MARK: - 圆形玻璃图标按钮

private struct CircleIconButton: View {
    let symbol: String
    var size: CGFloat = 34
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .regular))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(CircleGlass())
        .help(help)
    }
}

/// macOS 26 起叠加原生 Liquid Glass；底衬保证任何系统上都是一颗清楚的圆形按钮
struct CircleGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Circle()
                    .fill(Color.primary.opacity(0.055))
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.10)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.8)
                    )
            }
            .clipShape(Circle())
            .modifier(LiquidGlassLayer())
            .shadow(color: Color.black.opacity(0.07), radius: 2, y: 1)
    }
}

private struct LiquidGlassLayer: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
        }
    }
}

// MARK: - 格式分段控件

/// 自绘分段控件：白色滑块 + 缓动移动
/// 行内小图标：自带宽高与 hover 背景
private struct RowIconButton: View {
    let symbol: String
    let help: String
    var disabled = false
    let action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hover.on && !disabled ? 0.09 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(disabled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.v2aSecondary))
        .disabled(disabled)
        .onHover { hover.on = $0 }
        .help(help)
    }
}

private struct FormatSegmented: View {
    @Binding var selection: OutputFormat
    @Namespace private var namespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OutputFormat.allCases) { format in
                let selected = format == selection
                Text(format.label)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .frame(width: 53, height: 24)
                    .contentShape(Rectangle())
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                .fill(colorScheme == .dark
                                      ? Color.white.opacity(0.16)
                                      : Color.white)
                                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.12),
                                        radius: 2, y: 1)
                                .matchedGeometryEffect(id: "formatThumb", in: namespace)
                        }
                    }
                    .onTapGesture {
                        guard !selected else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            selection = format
                        }
                    }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: selection)
    }
}

// MARK: - 底部栏玻璃

@available(macOS 26.0, *)
/// 直接用 AppKit 的 NSGlassEffectView：真正的 Liquid Glass，带边缘折射。
/// macOS 27 起额外开启指针交互（effectIsInteractive）。
struct GlassPanel: NSViewRepresentable {
    var cornerRadius: CGFloat = 22
    var tint: NSColor?
    var interactive = true

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        view.tintColor = tint
        applyInteraction(to: view)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.style = .regular
        view.cornerRadius = cornerRadius
        view.tintColor = tint
        applyInteraction(to: view)
    }

    private func applyInteraction(to view: NSGlassEffectView) {
        if #available(macOS 27.0, *) {
            view.effectIsInteractive = interactive
        }
    }
}

/// 新系统走液态玻璃，旧系统退回毛玻璃材质
struct BarGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassPanel(cornerRadius: cornerRadius, tint: nil, interactive: true)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )
        }
    }
}

// MARK: - 设置行

private struct SettingRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.v2aSecondary)
                .frame(width: 52, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 单行

private struct FileRow: View {
    @EnvironmentObject private var l10n: Localization
    let item: MediaItem
    let locked: Bool
    let estimateText: String
    let outputName: String
    let showsOutputName: Bool
    var onRename: () -> Void
    var onTrim: () -> Void
    var onRemove: () -> Void
    var onReveal: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                metaLine
                    .font(.system(size: 10.8))
                    .foregroundStyle(Color.v2aSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            sizeColumn
            statusView
            if !locked {
                HStack(spacing: 2) {
                    rowIcon("pencil", help: l10n.t("重命名"), action: onRename)
                    rowIcon("scissors", help: l10n.t("裁剪"), action: onTrim, disabled: item.info == nil)
                    rowIcon("trash", help: l10n.t("删除"), action: onRemove)
                }
                .opacity(hover.on ? 1 : 0.55)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hover.on ? Color.primary.opacity(0.055) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
        .contextMenu {
            Button(l10n.t("重命名…")) { onRename() }
            Button(l10n.t("裁剪…")) { onTrim() }
                .disabled(item.info == nil)
            Divider()
            Button(l10n.t("在 Finder 中显示")) { onReveal() }
            if !locked {
                Divider()
                Button(l10n.t("移除")) { onRemove() }
            }
        }
    }

    private var metaLine: Text {
        guard showsOutputName else { return Text(item.metaText) }
        return Text(item.metaText + " → ")
            + Text(outputName).foregroundColor(Color.v2aGreen)
    }

    private func rowIcon(_ symbol: String, help: String,
                         action: @escaping () -> Void,
                         disabled: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(disabled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
        .disabled(disabled)
        .help(help)
    }

    private var sizeColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(AppModel.sizeText(item.size))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(Color.v2aSecondary)
            Text(estimateText)
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(item.status.isDone && item.outputSize > 0
                                 ? AnyShapeStyle(Color.v2aGreen)
                                 : AnyShapeStyle(Color.v2aTertiary))
        }
        .frame(width: 68, alignment: .trailing)
        .help(item.outputURL?.lastPathComponent ?? "转换后的预估大小")
    }

    private var thumbnail: some View {
        Group {
            if let cover = item.coverURL, let image = NSImage(contentsOf: cover) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
                    }
            } else {
                FormatBadge(ext: item.url.pathExtension, size: 38)
            }
        }
        .frame(width: 38, height: 38, alignment: .center)
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .pending:
            Text(item.probing ? l10n.t("读取中") : l10n.t("待处理"))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.v2aTertiary)
                .frame(width: 66, alignment: .center)
        case .running(let fraction):
            let clamped = min(max(fraction, 0), 1)
            HStack(spacing: 6) {
                ProgressView(value: clamped)
                    .progressViewStyle(.linear)
                    .frame(width: 40)
                Text("\(Int(clamped * 100))%")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.v2aSecondary)
                    .frame(width: 24, alignment: .trailing)
            }
            .frame(width: 66, alignment: .center)
        case .done:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text(l10n.t("完成"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.v2aSecondary)
            }
            .frame(width: 66, alignment: .center)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .help(message)
                .frame(width: 66, alignment: .center)
        }
    }
}

// MARK: - 轻量视图状态（避免使用 @State 宏）

final class DropState: ObservableObject {
    @Published var targeted = false
}

final class HoverState: ObservableObject {
    @Published var on = false
}

final class LayoutState: ObservableObject {
    @Published var barHeight: CGFloat = 0
}

struct BarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
