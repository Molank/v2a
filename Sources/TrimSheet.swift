import SwiftUI
import AppKit
import AVFoundation

/// 裁剪编辑器的播放、波形与时间轴状态
@MainActor
final class TrimEditor: ObservableObject {
    let url: URL
    let duration: Double

    @Published var start: Double
    @Published var end: Double
    @Published var current: Double = 0
    @Published var isPlaying = false
    @Published var peaks: [Float] = []
    @Published var waveformLoaded = false
    @Published var startDraft: String
    @Published var endDraft: String

    private let player: AVPlayer
    private var observer: Any?
    private static let bucketCount = 900

    init(url: URL, duration: Double, start: Double, end: Double) {
        let span = max(duration, 0.01)
        let lower = min(max(start, 0), span)
        let upper = min(max(end, lower), span)
        self.url = url
        self.duration = span
        self.start = lower
        self.end = upper
        self.startDraft = MediaItem.timeText(lower)
        self.endDraft = MediaItem.timeText(upper)

        player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause

        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                self.current = min(max(seconds, 0), self.duration)
                if self.isPlaying, self.current >= self.end - 0.02 {
                    self.stopPlayback()
                    self.seek(self.end)
                }
            }
        }

        loadWaveform()
    }

    deinit {
        if let observer { player.removeTimeObserver(observer) }
    }

    // MARK: 播放

    func togglePlay() {
        if isPlaying {
            stopPlayback()
        } else {
            if current < start || current >= end - 0.05 { seek(start) }
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        stopPlayback()
        player.pause()
    }

    private func stopPlayback() {
        player.pause()
        isPlaying = false
    }

    func seek(_ time: Double) {
        let clamped = min(max(time, 0), duration)
        current = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: 区间

    func setStart(_ value: Double) {
        start = min(max(value, 0), end - 0.1)
        startDraft = MediaItem.timeText(start)
        if current < start { seek(start) }
    }

    func setEnd(_ value: Double) {
        end = max(min(value, duration), start + 0.1)
        endDraft = MediaItem.timeText(end)
        if current > end { seek(end) }
    }

    func commitDrafts() {
        if let value = MediaItem.parseTime(startDraft) {
            setStart(value)
        } else {
            startDraft = MediaItem.timeText(start)
        }
        if let value = MediaItem.parseTime(endDraft) {
            setEnd(value)
        } else {
            endDraft = MediaItem.timeText(end)
        }
    }

    var isFullRange: Bool {
        start <= 0.01 && end >= duration - 0.01
    }

    // MARK: 波形

    private func loadWaveform() {
        let url = self.url
        let duration = self.duration
        let buckets = Self.bucketCount
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let peaks = TrimEditor.computePeaks(url: url, duration: duration, buckets: buckets)
            DispatchQueue.main.async {
                self?.peaks = peaks
                self?.waveformLoaded = true
            }
        }
    }

    /// 用自带的 ffmpeg 把音轨解码成 8 kHz 单声道 PCM，再取每个桶的峰值
    nonisolated private static func computePeaks(url: URL, duration: Double, buckets: Int) -> [Float] {
        var peaks = [Float](repeating: 0, count: buckets)
        guard let ffmpeg = Tools.ffmpeg else { return peaks }

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-v", "error", "-i", url.path,
                             "-map", "0:a:0", "-ac", "1", "-ar", "8000",
                             "-f", "s16le", "-"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return peaks
        }

        let totalSamples = max(Int(duration * 8000), 1)
        var pending = Data()
        var read = 0

        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)

            let usable = pending.count - (pending.count % 2)
            guard usable > 0 else { continue }
            pending.withUnsafeBytes { raw in
                var offset = 0
                while offset + 1 < usable {
                    let value = Int16(bitPattern: UInt16(raw[offset]) | (UInt16(raw[offset + 1]) << 8))
                    let amplitude = Float(abs(Int(value))) / 32768.0
                    let bucket = min(Int(Double(read) / Double(totalSamples) * Double(buckets)),
                                     buckets - 1)
                    if amplitude > peaks[bucket] { peaks[bucket] = amplitude }
                    read += 1
                    offset += 2
                }
            }
            pending = pending.subdata(in: usable..<pending.count)
        }

        process.waitUntilExit()

        // 偏安静的素材按峰值适度放大，最多 4 倍，避免波形细成一条线
        if let maxPeak = peaks.max(), maxPeak > 0.0001, maxPeak < 0.5 {
            let scale = min(1.0 / maxPeak, 4.0)
            for index in peaks.indices {
                peaks[index] = min(peaks[index] * scale, 1.0)
            }
        }
        return peaks
    }
}

/// iOS 相册风格的裁剪面板（波形时间轴 + 左右拉手 + 试听）
struct TrimSheet: View {
    @ObservedObject var app: AppModel
    @EnvironmentObject private var l10n: Localization
    let item: MediaItem
    @StateObject private var editor: TrimEditor
    @FocusState private var focus: Field?

    private enum Field: Hashable { case start, end }

    init(app: AppModel, item: MediaItem) {
        self.app = app
        self.item = item
        let duration = item.info?.duration ?? 0
        _editor = StateObject(wrappedValue: TrimEditor(url: item.url,
                                                       duration: duration,
                                                       start: item.trimStart ?? 0,
                                                       end: item.trimEnd ?? duration))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            timeline
            controls
            Text(l10n.t("拖动两侧拉手选择范围，拖播放头试听；空格播放/暂停，时间码可直接输入。"))
                .font(.system(size: 10.5))
                .foregroundStyle(Color.v2aTertiary)
            footer
        }
        .padding(20)
        .frame(width: 560)
        .background(FrostedBackground())
        .background(ClearWindowBackground())
        .onExitCommand {
            if focus != nil {
                focus = nil                      // 第一次 Esc：退出输入态
                NSApp.keyWindow?.makeFirstResponder(nil)
            } else {
                app.trimmingItemID = nil         // 再按一次：关闭面板
            }
        }
        .onAppear {
            // 打开时不要停在输入态，保证空格能直接控制播放
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onDisappear { editor.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(l10n.t("裁剪"))
                .font(.system(size: 14, weight: .semibold))
            Text(item.fileName)
                .font(.system(size: 11))
                .foregroundStyle(Color.v2aSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var timeline: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 7
            let width = max(geometry.size.width - inset * 2, 1)
            let height = geometry.size.height
            let startX = CGFloat(editor.start / editor.duration) * width
            let endX = CGFloat(editor.end / editor.duration) * width
            let playX = CGFloat(editor.current / editor.duration) * width

            ZStack(alignment: .topLeading) {
                // 轨道本体：背景 + 波形 + 压暗 + 选中描边，统一裁成圆角
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.055))

                    waveform

                    if !editor.waveformLoaded {
                        Text(l10n.t("正在生成波形…"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.v2aTertiary)
                            .frame(width: width, height: height)
                    }

                    Rectangle()
                        .fill(Color.black.opacity(0.30))
                        .frame(width: max(startX, 0), height: height)
                    Rectangle()
                        .fill(Color.black.opacity(0.30))
                        .frame(width: max(width - endX, 0), height: height)
                        .offset(x: endX)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
                        .frame(width: max(endX - startX, 2), height: height)
                        .offset(x: startX)
                        .allowsHitTesting(false)
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // 播放头
                Rectangle()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 1.5, height: height)
                    .offset(x: playX)
                    .allowsHitTesting(false)
                Circle()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 7, height: 7)
                    .offset(x: playX - 2.75, y: -3)
                    .allowsHitTesting(false)

                // 空白处拖动 = 拖动播放头
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
                            .onChanged { value in
                                editor.seek(Double(value.location.x / width) * editor.duration)
                            }
                    )

                handle(x: startX, width: width, height: height, isLeft: true)
                handle(x: endX, width: width, height: height, isLeft: false)
            }
            .frame(width: width, height: height)
            .coordinateSpace(name: "strip")
            .offset(x: inset)
        }
        .frame(height: 68)
    }

    private var waveform: some View {
        Canvas { context, size in
            let peaks = editor.peaks
            guard !peaks.isEmpty else { return }
            let mid = size.height / 2
            let barWidth = max(size.width / CGFloat(peaks.count), 0.6)
            var path = Path()
            for (index, peak) in peaks.enumerated() {
                let x = (CGFloat(index) + 0.5) / CGFloat(peaks.count) * size.width
                let amplitude = CGFloat(pow(max(peak, 0.0001), 0.6)) * mid * 0.86
                path.move(to: CGPoint(x: x, y: mid - amplitude))
                path.addLine(to: CGPoint(x: x, y: mid + amplitude))
            }
            context.stroke(path, with: .color(Color.v2aAccent.opacity(0.85)),
                           lineWidth: barWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func handle(x: CGFloat, width: CGFloat, height: CGFloat, isLeft: Bool) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 13, height: height)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .overlay(
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(Color.black.opacity(0.22))
                            .frame(width: 3, height: 12)
                    }
                }
            )
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .position(x: x, y: height / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
                    .onChanged { value in
                        let time = Double(value.location.x / width) * editor.duration
                        if isLeft {
                            editor.setStart(time)
                        } else {
                            editor.setEnd(time)
                        }
                    }
            )
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                editor.togglePlay()
            } label: {
                Image(systemName: editor.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(CircleGlass())
            .keyboardShortcut(.space, modifiers: [])
            .help(editor.isPlaying ? "暂停（空格）" : "试听选中片段（空格）")

            Text(MediaItem.timeText(editor.current))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.v2aSecondary)
            Text("/ \(MediaItem.timeText(editor.duration))")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.v2aTertiary)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text(l10n.t("开始"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.v2aSecondary)
                TextField("0:00", text: $editor.startDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(width: 66, height: 24)
                    .background { GlassButtonBackground(height: 24) }
                    .clipShape(Capsule())
                    .focused($focus, equals: .start)
                    .onSubmit {
                        editor.commitDrafts()
                        focus = nil
                    }
                Text(l10n.t("结束"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.v2aSecondary)
                TextField("0:00", text: $editor.endDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(width: 66, height: 24)
                    .background { GlassButtonBackground(height: 24) }
                    .clipShape(Capsule())
                    .focused($focus, equals: .end)
                    .onSubmit {
                        editor.commitDrafts()
                        focus = nil
                    }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(l10n.t("清除裁剪")) {
                app.clearTrim(item.id)
            }
            .buttonStyle(SoftButtonStyle(compact: true))
            .disabled(!item.isTrimmed)

            Spacer()

            Button(l10n.t("取消")) {
                app.trimmingItemID = nil
            }
            .buttonStyle(SoftButtonStyle(minWidth: 72))

            Button(l10n.t("应用")) {
                editor.commitDrafts()
                app.applyTrim(itemID: item.id, start: editor.start, end: editor.end)
            }
            .buttonStyle(PillButtonStyle(minWidth: 72))
            .keyboardShortcut(.defaultAction)
        }
    }
}
