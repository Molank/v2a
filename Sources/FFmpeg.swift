import Foundation
import AppKit
import QuickLookThumbnailing
import AppKit

enum V2AError: LocalizedError {
    case missingTool
    case message(String)

    var errorDescription: String? {
        switch self {
        case .missingTool:
            return "找不到 ffmpeg / ffprobe。请确认 App 内的 Resources/bin 完整。"
        case .message(let m):
            return m
        }
    }
}

enum Tools {
    static let ffmpeg = locate("ffmpeg")
    static let ffprobe = locate("ffprobe")

    static func locate(_ name: String) -> URL? {
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("bin/\(name)"))
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/\(name)"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

struct ProcResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ d: Data) {
        lock.lock(); data.append(d); lock.unlock()
    }
    var string: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// 可取消的正在运行的进程
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldKill = cancelled
        lock.unlock()
        if shouldKill { process.terminate() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        running?.terminate()
    }
}

enum Proc {
    static func run(_ exe: URL,
                    _ args: [String],
                    token: CancelToken? = nil,
                    onLine: (@Sendable (String) -> Void)? = nil) async throws -> ProcResult {
        let process = Process()
        process.executableURL = exe
        process.arguments = args
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outBox = DataBox()
        let errBox = DataBox()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outBox.append(chunk)
            if let onLine, let text = String(data: chunk, encoding: .utf8) {
                for line in text.split(separator: "\n") { onLine(String(line)) }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errBox.append(chunk)
        }

        let launch = DataBox()
        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
                token?.attach(process)
            } catch {
                launch.append(Data(error.localizedDescription.utf8))
                continuation.resume(returning: -1)
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        if let rest = try? outPipe.fileHandleForReading.readToEnd() { outBox.append(rest) }
        if let rest = try? errPipe.fileHandleForReading.readToEnd() { errBox.append(rest) }

        if status == -1, !launch.string.isEmpty {
            throw V2AError.message(launch.string)
        }
        return ProcResult(status: status, stdout: outBox.string, stderr: errBox.string)
    }
}

enum FFmpeg {
    // MARK: 探测

    static func probe(_ url: URL) async throws -> ProbeInfo {
        guard let exe = Tools.ffprobe else { throw V2AError.missingTool }
        let args = ["-v", "error", "-print_format", "json",
                    "-show_format", "-show_streams", url.path]
        let result = try await Proc.run(exe, args)
        guard result.status == 0 else {
            throw V2AError.message(result.stderr.isEmpty ? "无法读取该文件" : result.stderr)
        }
        return parse(result.stdout)
    }

    /// 用系统 QuickLook 取缩略图，和 Finder 里看到的一致
    static func quickLookThumbnail(_ url: URL, size: CGFloat = 256) async -> URL? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: 2,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                guard let rep else {
                    continuation.resume(returning: nil)
                    return
                }
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("v2a-covers", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let target = dir.appendingPathComponent(UUID().uuidString + ".png")
                guard let tiff = rep.nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    continuation.resume(returning: nil)
                    return
                }
                try? png.write(to: target)
                continuation.resume(returning: target)
            }
        }
    }

    /// 兜底：抽一张封面（视频取第 1 秒，音频取内嵌封面）
    static func extractCover(_ url: URL, fromVideo: Bool, hasCover: Bool) async -> URL? {
        guard let exe = Tools.ffmpeg, fromVideo || hasCover else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v2a-covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent(UUID().uuidString + ".jpg")

        var args: [String] = []
        if fromVideo {
            args = ["-ss", "1", "-i", url.path, "-frames:v", "1",
                    "-vf", "scale=320:-2", "-y", target.path]
        } else {
            args = ["-i", url.path, "-map", "0:v:0", "-frames:v", "1",
                    "-vf", "scale=320:-2", "-y", target.path]
        }
        guard let result = try? await Proc.run(exe, args), result.status == 0,
              FileManager.default.fileExists(atPath: target.path) else { return nil }
        return target
    }

    static func parse(_ json: String) -> ProbeInfo {
        var info = ProbeInfo()
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return info
        }

        if let format = root["format"] as? [String: Any] {
            info.duration = Double(format["duration"] as? String ?? "") ?? 0
            info.containerBitRate = Int(format["bit_rate"] as? String ?? "") ?? 0
        }

        if let streams = root["streams"] as? [[String: Any]] {
            func attachedPicture(_ stream: [String: Any]) -> Bool {
                guard let disposition = stream["disposition"] as? [String: Any] else { return false }
                return (disposition["attached_pic"] as? Int ?? 0) == 1
            }
            let allVideo = streams.filter { ($0["codec_type"] as? String) == "video" }
            let video = allVideo.filter { !attachedPicture($0) }
            info.hasVideo = !video.isEmpty
            info.hasCover = allVideo.contains(where: attachedPicture)
            info.videoBitRate = video.compactMap { Int($0["bit_rate"] as? String ?? "") }.first ?? 0
            let audio = streams.filter { ($0["codec_type"] as? String) == "audio" }
            for (offset, stream) in audio.enumerated() {
                var item = AudioStream(index: offset)
                item.codec = stream["codec_name"] as? String ?? ""
                item.channels = stream["channels"] as? Int ?? 0
                item.sampleRate = Int(stream["sample_rate"] as? String ?? "") ?? 0
                item.bitRate = Int(stream["bit_rate"] as? String ?? "") ?? 0
                item.layout = stream["channel_layout"] as? String ?? ""
                item.profile = stream["profile"] as? String ?? ""
                if let tags = stream["tags"] as? [String: Any] {
                    item.language = tags["language"] as? String
                    item.title = tags["title"] as? String
                }
                if info.duration == 0 {
                    info.duration = Double(stream["duration"] as? String ?? "") ?? 0
                }
                info.streams.append(item)
            }
        }
        return info
    }

    /// 读前若干音频包估算码率：mkv 这类容器不写 per-stream bit_rate
    static func estimateAudioBitRate(_ url: URL, track: Int = 0) async throws -> Int {
        guard let exe = Tools.ffprobe else { throw V2AError.missingTool }
        let args = ["-v", "error", "-select_streams", "a:\(track)",
                    "-read_intervals", "%+#400",
                    "-show_entries", "packet=size,duration_time",
                    "-of", "json", url.path]
        let result = try await Proc.run(exe, args)
        guard result.status == 0,
              let data = result.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packets = root["packets"] as? [[String: Any]] else { return 0 }

        var bytes = 0.0
        var seconds = 0.0
        for packet in packets {
            guard let size = Double(packet["size"] as? String ?? ""),
                  let duration = Double(packet["duration_time"] as? String ?? ""),
                  duration > 0 else { continue }
            bytes += size
            seconds += duration
        }
        guard seconds > 0 else { return 0 }
        return Int(bytes / seconds * 8)
    }

    // MARK: 提取

    static func extract(source: URL,
                        duration: Double,
                        plan: ConversionPlan,
                        to output: URL,
                        token: CancelToken? = nil,
                        progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let exe = Tools.ffmpeg else { throw V2AError.missingTool }

        var args = ["-hide_banner", "-nostdin", "-loglevel", "error", "-y",
                    "-progress", "pipe:1", "-nostats"]

        // 裁剪：-ss 起点 + -t 长度，都放在输入侧，定位更快
        if let start = plan.start, start > 0 {
            args += ["-ss", String(format: "%.3f", start)]
        }
        if let end = plan.end {
            let span = max(end - (plan.start ?? 0), 0.01)
            args += ["-t", String(format: "%.3f", span)]
        }

        args += ["-i", source.path,
                 "-map", "0:a:\(plan.track)", "-vn", "-sn", "-dn"]

        if plan.copy {
            args += ["-c:a", "copy"]
        } else {
            switch plan.format {
            case .m4a: args += ["-c:a", "aac", "-b:a", "\(plan.bitrate)k"]
            case .mp3: args += ["-c:a", "libmp3lame", "-b:a", "\(plan.bitrate)k"]
            case .wav: args += ["-c:a", "pcm_s16le"]
            case .flac: args += ["-c:a", "flac", "-compression_level", "8"]
            }
            if plan.sampleRate > 0 {
                args += ["-ar", "\(plan.sampleRate)"]
            }
            if plan.channels > 0 {
                args += ["-ac", "\(plan.channels)"]
            }
        }

        if plan.format == .wav {
            args += ["-map_metadata", "-1"]
        } else {
            args += ["-map_metadata", "0"]
        }
        args.append(output.path)

        // 进度分母用源文件总时长
        let total = max(duration, 0.001)
        let result = try await Proc.run(exe, args, token: token) { line in
            if let time = parseTime(line) {
                progress(min(1, max(0, time / total)))
            }
        }

        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: output)
            if token?.isCancelled == true { throw V2AError.message("已取消") }
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw V2AError.message(message.isEmpty ? "提取失败" : message)
        }
        progress(1)
    }

    private static func parseTime(_ line: String) -> Double? {
        if line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") {
            guard let value = Double(line.split(separator: "=", maxSplits: 1).last ?? "") else { return nil }
            return value / 1_000_000
        }
        if line.hasPrefix("out_time=") {
            let raw = line.dropFirst("out_time=".count).replacingOccurrences(of: ",", with: ".")
            let parts = raw.split(separator: ":")
            guard parts.count == 3,
                  let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
            return h * 3600 + m * 60 + s
        }
        return nil
    }
}
