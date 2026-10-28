import Foundation
import AppKit

// MARK: - 输出格式

enum OutputFormat: String, CaseIterable, Codable, Identifiable {
    case m4a, mp3, wav, flac

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var isLossless: Bool { self == .wav || self == .flac }

    var detail: String {
        switch self {
        case .m4a: return "AAC · 兼容性最好"
        case .mp3: return "MP3 · 到处都能放"
        case .wav: return "WAV · 无损未压缩"
        case .flac: return "FLAC · 无损压缩"
        }
    }
}

// MARK: - 音轨

struct AudioStream: Codable, Equatable, Identifiable {
    var index: Int
    var codec: String = ""
    var channels: Int = 0
    var sampleRate: Int = 0
    var bitRate: Int = 0
    var language: String?
    var title: String?
    var layout: String = ""
    var profile: String = ""

    var id: Int { index }

    /// 声道标识：单声道 / 立体声 / 5.1 / 7.1 / 杜比全景声
    var channelLabel: String {
        let profileText = profile.lowercased()
        if profileText.contains("atmos") { return "杜比全景声" }

        let base: String
        switch channels {
        case 0:  base = ""
        case 1:  base = "单声道"
        case 2:  base = "立体声"
        default:
            if layout.contains("7.1")      { base = "7.1" }
            else if layout.contains("5.1") { base = "5.1" }
            else if layout.contains("4.0") { base = "4.0" }
            else if layout.contains("3.0") { base = "3.0" }
            else                           { base = "\(channels) 声道" }
        }

        let dolby = ["ac3", "eac3", "truehd"]
        if dolby.contains(codec.lowercased()), channels > 2 {
            return "杜比 " + base
        }
        return base
    }

    var label: String {
        var parts = ["第 \(index + 1) 条"]
        if let title, !title.isEmpty {
            parts.append(title)
        } else if let language, !language.isEmpty, language != "und" {
            parts.append(Locale(identifier: "zh_CN").localizedString(forLanguageCode: language) ?? language)
        }
        if channels > 0, !channelLabel.isEmpty { parts.append(channelLabel) }
        return parts.joined(separator: " · ")
    }
}

struct ProbeInfo: Equatable {
    var duration: Double = 0
    var streams: [AudioStream] = []
    var containerBitRate: Int = 0
    var hasVideo: Bool = false
    var hasCover: Bool = false
    var videoBitRate: Int = 0
    var estimatedBitRate: Int = 0

    /// 展示用的音频码率：流字段缺失（mkv）或不可信（B 站 m4a）时用容器均值兜底
    var displayBitRate: Int {
        guard let first = streams.first else { return 0 }
        if streams.count == 1 && !hasVideo && containerBitRate > 0 {
            return containerBitRate
        }
        if first.bitRate > 0 { return first.bitRate }
        if hasVideo, videoBitRate > 0, containerBitRate > videoBitRate {
            return containerBitRate - videoBitRate
        }
        return estimatedBitRate
    }

    var hasAudio: Bool { !streams.isEmpty }
    var first: AudioStream? { streams.first }
    var codec: String { first?.codec ?? "" }
    var bitRate: Int { first?.bitRate ?? containerBitRate }

    func stream(at index: Int) -> AudioStream? {
        guard !streams.isEmpty else { return nil }
        return streams[min(max(index, 0), streams.count - 1)]
    }
}

// MARK: - 设置与预设

struct AudioSettings: Codable, Equatable {
    var format: OutputFormat = .m4a
    var bitrate: Int = 192
    var sampleRate: Int = 0      // 0 = 跟随源
    var channels: Int = 0        // 0 = 跟随源，1 = 单声道，2 = 立体声
    var track: Int = 0

    static let bitrateChoices = [64, 96, 128, 160, 192, 256, 320]
    static let sampleRateChoices = [0, 22050, 44100, 48000, 96000]
    static let channelChoices = [0, 1, 2]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case format, bitrate, sampleRate, channels, track
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        format = try box.decodeIfPresent(OutputFormat.self, forKey: .format) ?? .m4a
        bitrate = try box.decodeIfPresent(Int.self, forKey: .bitrate) ?? 192
        sampleRate = try box.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 0
        channels = try box.decodeIfPresent(Int.self, forKey: .channels) ?? 0
        track = try box.decodeIfPresent(Int.self, forKey: .track) ?? 0
    }

    var isDefault: Bool { self == AudioSettings() }

    var summary: String {
        if format.isLossless { return "\(format.label) · " + Localization.shared.t("无损") }
        return "\(format.label) · \(bitrate) kbps"
    }

    var channelLabel: String {
        switch channels {
        case 1: return Localization.shared.t("单声道")
        case 2: return Localization.shared.t("立体声")
        default: return Localization.shared.t("跟随源")
        }
    }
}

struct AudioPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var settings: AudioSettings
}

/// 每个文件最终执行的转换方案（估算与执行共用，保证两者一致）
struct ConversionPlan {
    var format: OutputFormat
    var bitrate: Int
    var sampleRate: Int
    var channels: Int
    var track: Int
    var copy: Bool
    var start: Double?
    var end: Double?

    var outputDuration: Double {
        max((end ?? .greatestFiniteMagnitude) - (start ?? 0), 0)
    }
}

extension Notification.Name {
    static let v2aShowDragHelper = Notification.Name("V2A.ShowDragHelper")
    static let v2aShowLinkWindow = Notification.Name("V2A.ShowLinkWindow")
    static let v2aCloseLinkWindow = Notification.Name("V2A.CloseLinkWindow")
    static let v2aDragAccepted = Notification.Name("V2A.DragAccepted")
    static let v2aLinkWindowResize = Notification.Name("V2A.LinkWindowResize")
}

// MARK: - 链接下载

struct DownloadTask: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var title: String
    var progress: Double = 0
    var error: String?
}

// MARK: - 列表条目

enum ItemStatus: Equatable {
    case pending
    case running(Double)
    case done
    case failed(String)

    var isDone: Bool {
        if case .done = self { return true }
        return false
    }
}

struct MediaItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var info: ProbeInfo?
    var size: Int64 = 0
    var status: ItemStatus = .pending
    var outputURL: URL?
    var outputSize: Int64 = 0
    var probing = true
    var coverURL: URL?
    var customName: String?
    var trimStart: Double?
    var trimEnd: Double?

    var fileName: String { url.lastPathComponent }

    var isTrimmed: Bool { trimStart != nil || trimEnd != nil }

    var trimRangeText: String? {
        guard isTrimmed else { return nil }
        let start = trimStart ?? 0
        let end = trimEnd ?? (info?.duration ?? 0)
        return "\(Self.timeText(start))–\(Self.timeText(end))"
    }

    /// 用户指定或自动推导的输出文件名（不含扩展名）
    var outputBaseName: String {
        if let customName, !customName.isEmpty { return customName }
        return url.deletingPathExtension().lastPathComponent
    }

    var metaText: String {
        guard let info else { return probing ? "正在读取…" : "未读取到信息" }
        var parts: [String] = []
        if let range = trimRangeText { parts.append("裁剪 \(range)") }
        if info.duration > 0 { parts.append(Self.timeText(info.duration)) }
        if let stream = info.first {
            if !stream.codec.isEmpty { parts.append(stream.codec.uppercased()) }
            let bitRate = info.displayBitRate
            if bitRate > 0 { parts.append("\(bitRate / 1000) kbps") }
            if stream.channels > 0, !stream.channelLabel.isEmpty {
                parts.append(stream.channelLabel)
            }
        }
        if info.streams.count > 1 { parts.append("\(info.streams.count) 条音轨") }
        return parts.joined(separator: " · ")
    }

    static func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1:23"、"01:02:03" 或 "83" 都认
    static func parseTime(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "：", with: ":")
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: ":")
        switch parts.count {
        case 1:
            return Double(parts[0])
        case 2:
            if let m = Double(parts[0]), let s = Double(parts[1]) { return m * 60 + s }
        case 3:
            if let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) {
                return h * 3600 + m * 60 + s
            }
        default:
            return nil
        }
        return nil
    }
}

// MARK: - 主模型

@MainActor
final class AppModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var settings = AudioSettings() {
        didSet { persistSettings() }
    }
    @Published var presets: [AudioPreset] = [] {
        didSet { persistPresets() }
    }
    @Published var useSourceFolder = true
    @Published var outputFolder: URL?
    @Published var isRunning = false
    @Published var batchProgress: Double = 0
    @Published var summary: String?

    // 界面状态（设置弹窗、预设命名、重命名、裁剪）
    @Published var downloads: [DownloadTask] = []
    @Published var showOnboarding = false
    @Published var showPermissions = false
    @Published var showGeneralSettings = false

    var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
    @Published var fdaGranted: Bool?
    /// nil = 还没验证过；Safari/Firefox 没有钥匙串项，保持 nil
    @Published var keychainGranted: Bool?
    @Published var linkField = ""
    @Published var linkError: String?
    /// 自定义下载目录（nil = 系统「下载」）
    @Published var downloadFolderPath: String? {
        didSet { store.set(downloadFolderPath, forKey: "v2a.downloadFolder") }
    }
    /// 下载完成后在 Finder 中显示
    @Published var autoRevealDownload: Bool = false {
        didSet { store.set(autoRevealDownload, forKey: "v2a.autoReveal") }
    }

    /// true = 只下载音轨，不下载视频
    @Published var audioOnlyDownload: Bool = false {
        didSet { store.set(audioOnlyDownload, forKey: "v2a.audioOnly") }
    }

    /// 链接预览（标题 / 封面 / 时长 / UP 主）
    struct LinkPreview: Equatable {
        var title: String
        var duration: Double
        var thumbnail: String?
        var uploader: String?

        var durationText: String? {
            guard duration > 0 else { return nil }
            let total = Int(duration.rounded())
            let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                         : String(format: "%d:%02d", m, sec)
        }
    }

    @Published var linkPreview: LinkPreview?
    @Published var linkPreviewLoading = false
    private var previewTask: Task<Void, Never>?
    private var previewURL: String?

    /// true = 下载最高品质：不限 1080p + 取最佳音轨 + 用浏览器 Cookie
    @Published var highQualityDownload: Bool = false {
        didSet { store.set(highQualityDownload, forKey: "v2a.highQuality") }
    }

    /// nil = 不用浏览器 Cookie；否则是 safari / chrome / edge / firefox
    @Published var cookieBrowser: String? {
        didSet { store.set(cookieBrowser, forKey: "v2a.cookieBrowser") }
    }

    private var downloadTokens: [UUID: CancelToken] = [:]

    @Published var showSettings = false
    @Published var savingPreset = false
    @Published var presetName = ""
    @Published var renamingItemID: UUID?
    @Published var renameDraft = ""
    @Published var renameError: String?
    @Published var trimmingItemID: UUID?

    private var token: CancelToken?
    private let store = UserDefaults.standard

    private enum Key {
        static let presets = "v2a.presets"
        static let settings = "v2a.settings"
    }

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "flv", "webm", "ts", "m2ts",
        "wmv", "mpg", "mpeg", "3gp", "rmvb", "vob", "ogv", "mxf", "asf"
    ]

    init() {
        restore()
    }

    // MARK: 文案

    var subtitle: String {
        if items.isEmpty { return "从视频里取出音频" }
        if isRunning { return "正在提取… \(Int(batchProgress * 100))%" }
        let base = "\(items.count) 个视频 · \(settings.summary)"
        if let preset = matchingPreset { return base + " · \(preset.name)" }
        return base
    }

    var destinationLabel: String {
        if useSourceFolder { return Localization.shared.t("与源文件同目录") }
        return outputFolder?.lastPathComponent ?? "选择文件夹…"
    }

    var matchingPreset: AudioPreset? {
        presets.first { $0.settings == settings }
    }

    var trackChoices: [Int] {
        guard let info = items.compactMap({ $0.info }).first, !info.streams.isEmpty else { return [0] }
        return info.streams.map(\.index)
    }

    func trackLabel(_ index: Int) -> String {
        guard let info = items.compactMap({ $0.info }).first,
              let stream = info.streams.first(where: { $0.index == index }) else {
            return index == 0 ? "第 1 条音轨" : "第 \(index + 1) 条音轨"
        }
        return stream.label
    }

    // MARK: 文件大小

    static func sizeText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }

    func plan(for item: MediaItem) -> ConversionPlan {
        let track = min(max(settings.track, 0),
                        max((item.info?.streams.count ?? 1) - 1, 0))
        let stream = item.info?.stream(at: track)
        let forced = settings.sampleRate > 0 || settings.channels > 0
        let copy = !forced && Self.canCopy(codec: stream?.codec ?? "", to: settings.format)
        return ConversionPlan(format: settings.format,
                              bitrate: settings.bitrate,
                              sampleRate: settings.sampleRate,
                              channels: settings.channels,
                              track: track,
                              copy: copy,
                              start: item.trimStart,
                              end: item.trimEnd)
    }

    /// 裁剪后的有效时长（未裁剪则为源时长）
    func effectiveDuration(_ item: MediaItem) -> Double {
        guard let total = item.info?.duration, total > 0 else { return 0 }
        let start = max(item.trimStart ?? 0, 0)
        let end = min(item.trimEnd ?? total, total)
        return max(end - start, 0)
    }

    private static func canCopy(codec: String, to format: OutputFormat) -> Bool {
        switch format {
        case .m4a: return codec == "aac" || codec == "alac"
        case .mp3: return codec == "mp3"
        case .flac: return codec == "flac"
        case .wav: return false
        }
    }

    /// 转换后的体积预估
    func estimatedSize(_ item: MediaItem) -> Int64? {
        guard item.info != nil else { return nil }
        let plan = plan(for: item)
        let duration = effectiveDuration(item)
        guard duration > 0 else { return nil }
        let stream = item.info?.stream(at: plan.track)

        if plan.copy {
            let bitRate = stream?.bitRate ?? item.info?.bitRate ?? 0
            if bitRate > 0 { return Int64(Double(bitRate) / 8 * duration) }
            return nil
        }

        switch plan.format {
        case .m4a, .mp3:
            return Int64(Double(plan.bitrate) * 1000 / 8 * duration)
        case .wav, .flac:
            let rate = plan.sampleRate > 0 ? plan.sampleRate : (stream?.sampleRate ?? 48000)
            let channels = plan.channels > 0 ? plan.channels : max(stream?.channels ?? 2, 1)
            let raw = Double(rate * 2 * channels) * duration
            return plan.format == .wav ? Int64(raw) + 44 : Int64(raw * 0.55)
        }
    }

    /// 右侧大小列：转换前显示预估，转换后显示实际
    func sizeColumnText(for item: MediaItem) -> String {
        if item.status.isDone, item.outputSize > 0 {
            return "→ " + Self.sizeText(item.outputSize)
        }
        if let estimated = estimatedSize(item) {
            return "≈ " + Self.sizeText(estimated)
        }
        return "—"
    }

    // MARK: 预设

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[index].settings = settings
        } else {
            presets.append(AudioPreset(name: trimmed, settings: settings))
        }
    }

    func applyPreset(_ preset: AudioPreset) {
        settings = preset.settings
    }

    func deletePreset(_ preset: AudioPreset) {
        presets.removeAll { $0.id == preset.id }
    }

    private func restore() {
        if let data = store.data(forKey: Key.settings),
           let decoded = try? JSONDecoder().decode(AudioSettings.self, from: data) {
            settings = decoded
        }
        showOnboarding = !store.bool(forKey: "v2a.onboarded")
        cookieBrowser = store.string(forKey: "v2a.cookieBrowser")
        highQualityDownload = store.bool(forKey: "v2a.highQuality")
        audioOnlyDownload = store.bool(forKey: "v2a.audioOnly")
        downloadFolderPath = store.string(forKey: "v2a.downloadFolder")
        autoRevealDownload = store.bool(forKey: "v2a.autoReveal")
        if let data = store.data(forKey: Key.presets),
           let decoded = try? JSONDecoder().decode([AudioPreset].self, from: data) {
            presets = decoded
        }
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            store.set(data, forKey: Key.settings)
        }
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            store.set(data, forKey: Key.presets)
        }
    }

    // MARK: 列表操作

    func add(urls: [URL]) {
        var found: [URL] = []
        let fm = FileManager.default

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey]
                if let enumerator = fm.enumerator(at: url,
                                                  includingPropertiesForKeys: keys,
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let file as URL in enumerator
                    where Self.videoExtensions.contains(file.pathExtension.lowercased()) {
                        found.append(file)
                    }
                }
            } else {
                found.append(url)
            }
        }

        found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        let before = items.count
        for url in found {
            guard !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { continue }
            var item = MediaItem(url: url)
            item.size = Self.fileSize(url)
            item.probing = true
            items.append(item)
            startProbe(id: item.id, url: url)
        }

        if items.count == before, !urls.isEmpty {
            summary = found.isEmpty ? Localization.shared.t("没有找到视频文件") : Localization.shared.t("这些文件已经在列表里了")
        } else {
            summary = nil
        }
    }

    func remove(_ id: UUID) {
        guard !isRunning else { return }
        items.removeAll { $0.id == id }
        // 清空后提示文字要复位，不能留着上一次的「已提取 N 个」
        if items.isEmpty { summary = nil }
    }

    func clear() {
        guard !isRunning else { return }
        items.removeAll()
        summary = nil
        batchProgress = 0
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    // MARK: 面板

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "添加"
        panel.message = "选择视频，或选择包含视频的文件夹"
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    func presentOutputPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选用"
        panel.message = "选择音频输出的文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url
            useSourceFolder = false
        }
    }

    // MARK: 提取

    private func startProbe(id: UUID, url: URL) {
        Task {
            do {
                var info = try await FFmpeg.probe(url)
                if info.hasAudio && info.displayBitRate == 0 {
                    let estimate = (try? await FFmpeg.estimateAudioBitRate(url)) ?? 0
                    if estimate > 0 { info.estimatedBitRate = estimate }
                }
                update(id) { item in
                    item.info = info
                    item.probing = false
                    if !info.hasAudio { item.status = .failed("没有音频轨道") }
                }
                // 优先用系统缩略图（与 Finder 一致），失败再退回 ffmpeg 抽帧
                var cover = await FFmpeg.quickLookThumbnail(url)
                if cover == nil {
                    cover = await FFmpeg.extractCover(url, fromVideo: info.hasVideo, hasCover: info.hasCover)
                }
                if let cover {
                    update(id) { $0.coverURL = cover }
                }
            } catch {
                update(id) { item in
                    item.probing = false
                    item.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    func convertAll() {
        guard !isRunning, !items.isEmpty else { return }
        isRunning = true
        summary = nil
        batchProgress = 0

        let token = CancelToken()
        self.token = token

        let snapshot = items
        let plans = snapshot.map { plan(for: $0) }

        Task {
            var success = 0
            var cancelled = false

            for (index, item) in snapshot.enumerated() {
                if token.isCancelled { cancelled = true; break }
                if item.status.isDone {
                    batchProgress = Double(index + 1) / Double(snapshot.count)
                    continue
                }
                update(item.id) { $0.status = .running(0); $0.outputURL = nil; $0.outputSize = 0 }

                do {
                    guard item.info?.hasAudio ?? true else {
                        throw V2AError.message("没有音频轨道")
                    }
                    let output = destinationURL(for: item, format: plans[index].format)
                    try await FFmpeg.extract(source: item.url,
                                             duration: effectiveDuration(item),
                                             plan: plans[index],
                                             to: output,
                                             token: token) { fraction in
                        Task { @MainActor in
                            self.update(item.id) { $0.status = .running(fraction) }
                        }
                    }
                    let size = Self.fileSize(output)
                    update(item.id) { $0.status = .done; $0.outputURL = output; $0.outputSize = size }
                    success += 1
                } catch {
                    if token.isCancelled {
                        update(item.id) { $0.status = .pending }
                    } else {
                        update(item.id) { $0.status = .failed(error.localizedDescription) }
                    }
                }
                batchProgress = Double(index + 1) / Double(snapshot.count)
            }

            if token.isCancelled { cancelled = true }
            isRunning = false
            self.token = nil
            batchProgress = 0

            if cancelled {
                summary = success > 0 ? "Cancelled · \(success) done" : Localization.shared.t("已取消")
            } else {
                summary = success > 0 ? "\(success) audio file(s) extracted" : Localization.shared.t("没有完成任何文件")
            }
        }
    }

    func cancel() {
        token?.cancel()
    }

    // MARK: 权限引导

    func refreshPermissions() {
        fdaGranted = PermissionCheck.fullDiskAccess()
    }

    /// 主动验证浏览器 Cookie 的钥匙串授权（可能弹一次系统授权框）
    func probeKeychain() {
        guard let browser = cookieBrowser else {
            keychainGranted = nil
            return
        }
        // 放到后台：如果系统弹授权框，主线程不会卡住
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = PermissionCheck.keychainAccess(for: browser)
            DispatchQueue.main.async { self?.keychainGranted = result }
        }
    }

    func dismissOnboarding() {
        store.set(true, forKey: "v2a.onboarded")
        showOnboarding = false
    }

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
        dismissOnboarding()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NotificationCenter.default.post(name: .v2aShowDragHelper, object: nil)
        }
    }

    // MARK: 链接

    var canAcceptLinks: Bool { YtDlp.isAvailable }

    /// 解析链接，拿到标题与封面用于预览
    func requestLinkPreview() {
        let link = Self.extractLink(from: linkField)
            ?? linkField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard link.lowercased().hasPrefix("http") else {
            linkPreview = nil
            linkPreviewLoading = false
            previewURL = nil
            return
        }
        guard link != previewURL else { return }
        previewURL = link
        previewTask?.cancel()
        linkPreview = nil
        linkPreviewLoading = true

        let cookies = highQualityDownload ? cookieBrowser : nil
        previewTask = Task { [weak self] in
            let result = try? await YtDlp.metadata(URL(string: link) ?? URL(fileURLWithPath: "/"),
                                                   cookiesFrom: cookies)
            if Task.isCancelled { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.linkPreviewLoading = false
                self.linkPreview = result.map {
                    LinkPreview(title: $0.title,
                                duration: $0.duration,
                                thumbnail: $0.thumbnail,
                                uploader: $0.uploader)
                }
                NotificationCenter.default.post(name: .v2aLinkWindowResize, object: nil)
            }
        }
    }

    /// 打开「下载链接」窗口；传 nil 时用当前输入框内容
    func beginLink(_ prefill: String?) {
        if let prefill, !prefill.isEmpty {
            linkField = Self.extractLink(from: prefill) ?? prefill
        }
        linkError = nil
        refreshPermissions()
        NotificationCenter.default.post(name: .v2aShowLinkWindow, object: nil)
    }

    func addLink(_ text: String) {
        guard let trimmed = Self.extractLink(from: text) else {
            linkError = "没有找到可用的 http(s) 链接"
            return
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            linkError = "这不像一个视频链接"
            return
        }
        guard YtDlp.isAvailable else {
            linkError = "App 内缺少 yt-dlp"
            return
        }
        if highQualityDownload {
            refreshPermissions()
            if cookieBrowser == nil {
                linkError = "最高品质需要先在「登录站点」里选一个浏览器"
                return
            }
            if fdaGranted != true {
                linkError = "读取浏览器 Cookie 需要「完全磁盘访问」授权"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.showGeneralSettings = true
                }
                return
            }
        }

        let task = DownloadTask(url: url, title: "正在解析链接…")
        downloads.insert(task, at: 0)
        linkField = ""
        linkError = nil
        NotificationCenter.default.post(name: .v2aCloseLinkWindow, object: nil)
        startDownload(task)
    }

    func cancelDownload(_ id: UUID) {
        downloadTokens[id]?.cancel()
        downloadTokens[id] = nil
        downloads.removeAll { $0.id == id }
    }

    func dismissDownloadError(_ id: UUID) {
        downloads.removeAll { $0.id == id }
    }

    private func startDownload(_ task: DownloadTask) {
        let token = CancelToken()
        downloadTokens[task.id] = token

        Task {
            var tempDir: URL?
            do {
                let cookies = highQualityDownload ? cookieBrowser : nil
                let meta = try await YtDlp.metadata(task.url, cookiesFrom: cookies)
                updateDownload(task.id) { $0.title = meta.title }

                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("v2a-dl-\(task.id.uuidString)")
                tempDir = dir

                let file = try await YtDlp.download(task.url, into: dir,
                                                    cookiesFrom: cookies,
                                                    audioOnly: audioOnlyDownload,
                                                    maxHeight: highQualityDownload ? nil : 1080,
                                                    token: token) { fraction in
                    Task { @MainActor in
                        self.updateDownload(task.id) { $0.progress = fraction }
                    }
                }

                if cookies != nil { keychainGranted = true }
                let destination = try self.moveToDownloads(file, title: meta.title)
                if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
                downloads.removeAll { $0.id == task.id }
                downloadTokens[task.id] = nil
                add(urls: [destination])
                summary = "Downloaded \(destination.lastPathComponent)"
                if autoRevealDownload {
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                }
            } catch {
                if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
                downloadTokens[task.id] = nil
                if token.isCancelled {
                    downloads.removeAll { $0.id == task.id }
                } else {
                    let message = Self.friendlyError(error.localizedDescription)
                    updateDownload(task.id) {
                        $0.error = message
                        if $0.title == "正在解析链接…" {
                            $0.title = $0.url.host ?? "链接下载失败"
                        }
                    }
                }
            }
        }
    }

    var downloadDirectory: URL {
        if let path = downloadFolderPath, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    var downloadFolderLabel: String {
        guard let path = downloadFolderPath, !path.isEmpty else { return "下载" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选用"
        panel.message = "选择下载保存的文件夹"
        panel.directoryURL = downloadDirectory
        if panel.runModal() == .OK, let url = panel.url {
            downloadFolderPath = url.path
        }
    }

    func resetDownloadFolder() {
        downloadFolderPath = nil
    }

    /// 从分享文案里抠出第一个 http(s) 链接
    static func extractLink(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http"),
           !trimmed.contains(" ") {
            return trimmed
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return trimmed.lowercased().hasPrefix("http") ? trimmed : nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return detector.firstMatch(in: trimmed, options: [], range: range)
            .flatMap { Range($0.range, in: trimmed) }
            .map { String(trimmed[$0]) }
    }

    /// 把 yt-dlp 的原始报错翻成能照着做的中文
    static func friendlyError(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "ERROR: ", with: "")
        let lower = text.lowercased()
        if lower.contains("cookies database") || lower.contains("could not find") && lower.contains("cookies") {
            return "读不到浏览器的 Cookie 数据库。请到「系统设置 → 隐私与安全性 → 完全磁盘访问」授权 V2A（菜单栏「权限说明…」里有拖拽条），重启 App 后重试；也可以改用「不使用 Cookie」。"
        }
        if lower.contains("operation not permitted") {
            return "系统拒绝了访问，多半是缺少「完全磁盘访问」权限。"
        }
        if lower.contains("decrypt") || lower.contains("keyring") || lower.contains("keychain") {
            return "Cookie 解密失败：请在系统弹窗里允许访问钥匙串，或改用 Safari。"
        }
        if lower.contains("logged-in") || lower.contains("login required") || lower.contains("sign in") {
            return "这个站点需要登录，请在「登录站点」里选择你的浏览器读取 Cookie。"
        }
        return text
    }

    private func updateDownload(_ id: UUID, _ mutate: (inout DownloadTask) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        mutate(&downloads[index])
    }

    private func moveToDownloads(_ file: URL, title: String) throws -> URL {
        let fm = FileManager.default
        let downloads = downloadDirectory
        try? fm.createDirectory(at: downloads, withIntermediateDirectories: true)

        var base = title.replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: ":", with: "-")
        if base.count > 80 { base = String(base.prefix(80)) }
        if base.isEmpty { base = "video" }

        let ext = file.pathExtension.isEmpty ? "mp4" : file.pathExtension
        var candidate = downloads.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = downloads.appendingPathComponent("\(base) (\(counter))")
                .appendingPathExtension(ext)
            counter += 1
        }
        try fm.moveItem(at: file, to: candidate)
        return candidate
    }

    // MARK: 重命名

    func beginRename(_ item: MediaItem) {
        renamingItemID = item.id
        renameDraft = item.outputBaseName
        renameError = nil
    }

    func applyRename() {
        guard let id = renamingItemID,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        var name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "/", with: "-")
                       .replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty else {
            renameError = "名字不能为空"
            return
        }

        var item = items[index]
        let ext = item.outputURL?.pathExtension ?? settings.format.rawValue
        if name.lowercased().hasSuffix("." + ext) {
            name = String(name.dropLast(ext.count + 1))
        }

        if let oldURL = item.outputURL {
            let newURL = oldURL.deletingLastPathComponent()
                .appendingPathComponent(name)
                .appendingPathExtension(ext)
            if newURL != oldURL {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    renameError = "同目录下已有同名文件"
                    return
                }
                do {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                } catch {
                    renameError = error.localizedDescription
                    return
                }
                item.outputURL = newURL
            }
        }

        item.customName = name
        items[index] = item
        renamingItemID = nil
        renameError = nil
    }

    // MARK: 裁剪

    var trimTargetItem: MediaItem? {
        guard let id = trimmingItemID else { return nil }
        return items.first { $0.id == id }
    }

    func beginTrim(_ item: MediaItem) {
        guard (item.info?.duration ?? 0) > 0 else {
            summary = "还在读取时长，稍等一下"
            return
        }
        trimmingItemID = item.id
    }

    func itemIsTrimmed(_ id: UUID?) -> Bool {
        guard let id, let item = items.first(where: { $0.id == id }) else { return false }
        return item.isTrimmed
    }

    func applyTrim(itemID: UUID, start: Double, end: Double) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        let total = item.info?.duration ?? 0
        let clampedStart = max(start, 0)
        let clampedEnd = total > 0 ? min(end, total) : end

        if clampedStart <= 0.001 && (total <= 0 || clampedEnd >= total - 0.001) {
            item.trimStart = nil
            item.trimEnd = nil
        } else {
            item.trimStart = clampedStart > 0.001 ? clampedStart : nil
            item.trimEnd = (total <= 0 || clampedEnd < total - 0.001) ? clampedEnd : nil
        }
        if item.status.isDone {
            item.status = .pending
            item.outputURL = nil
            item.outputSize = 0
        }
        items[index] = item
        trimmingItemID = nil
    }

    func clearTrim(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        item.trimStart = nil
        item.trimEnd = nil
        if item.status.isDone {
            item.status = .pending
            item.outputURL = nil
            item.outputSize = 0
        }
        items[index] = item
        trimmingItemID = nil
    }

    /// 列表里展示的输出文件名：已转换用真实文件名，重命名过则用预测名
    func outputFileName(for item: MediaItem) -> String {
        if let output = item.outputURL { return output.lastPathComponent }
        return item.outputBaseName + "." + settings.format.rawValue
    }

    private func destinationURL(for item: MediaItem, format: OutputFormat) -> URL {
        let directory: URL
        if useSourceFolder || outputFolder == nil {
            directory = item.url.deletingLastPathComponent()
        } else {
            directory = outputFolder!
        }
        let base = item.outputBaseName
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(format.rawValue)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base) (\(counter))")
                .appendingPathExtension(format.rawValue)
            counter += 1
        }
        return candidate
    }

    private func update(_ id: UUID, _ mutate: (inout MediaItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }
}
