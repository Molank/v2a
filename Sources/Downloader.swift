import Foundation
import AppKit

/// yt-dlp 的薄封装：解析标题、下载并用自带 ffmpeg 合并成 mp4
enum YtDlp {
    static let binary: URL? = Tools.locate("yt-dlp")

    struct Metadata {
        var title: String
        var duration: Double
        var thumbnail: String?
        var uploader: String?
    }

    static var isAvailable: Bool { binary != nil }

    static func metadata(_ url: URL, cookiesFrom browser: String?) async throws -> Metadata {
        guard let exe = binary else { throw V2AError.message("缺少 yt-dlp") }
        let args = ["--no-playlist", "--skip-download", "--no-warnings", "--no-progress",
                    "--print", "%(.{title,duration,thumbnail,uploader})j", url.absoluteString]
        var fullArgs = args
        if let browser { fullArgs += ["--cookies-from-browser", browser] }
        let result = try await Proc.run(exe, fullArgs)
        guard result.status == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw V2AError.message(message.isEmpty ? "解析链接失败" : message)
        }
        let line = result.stdout
            .split(separator: "\n")
            .last(where: { $0.hasPrefix("{") })
            .map(String.init) ?? "{}"
        let json = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
        let title = (json["title"] as? String) ?? "未命名视频"
        let duration = (json["duration"] as? Double) ?? 0
        return Metadata(title: title.isEmpty ? "未命名视频" : title,
                        duration: duration,
                        thumbnail: json["thumbnail"] as? String,
                        uploader: json["uploader"] as? String)
    }

    /// 下载到指定目录，返回落地文件
    static func download(_ url: URL,
                         into directory: URL,
                         cookiesFrom browser: String?,
                         audioOnly: Bool,
                         maxHeight: Int?,
                         token: CancelToken?,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let exe = binary else { throw V2AError.message("缺少 yt-dlp") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var args = ["--no-playlist", "--newline", "--no-warnings"]
        if audioOnly {
            // ba = bestaudio，B 站有 Hi-Res 时会选到 30251 FLAC
            args += ["-f", "ba/b"]
        } else {
            // mp4/mkv：音频是 FLAC 时 mp4 装不下，让 yt-dlp 退回 mkv
            let cap = maxHeight.map { "[height<=\($0)]" } ?? ""
            args += ["-f", "bv*\(cap)+ba/b\(cap)/b",
                     "--merge-output-format", "mp4/mkv"]
        }
        if let ffmpeg = Tools.ffmpeg {
            args += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
        }
        if let browser { args += ["--cookies-from-browser", browser] }
        args += ["-o", directory.appendingPathComponent("%(title)s.%(ext)s").path,
                 url.absoluteString]

        let result = try await Proc.run(exe, args, token: token) { line in
            guard line.hasPrefix("[download]"), let percentRange = line.range(of: "%") else { return }
            let prefix = line[line.startIndex..<percentRange.lowerBound]
                .components(separatedBy: " ")
                .compactMap { Double($0) }
                .last
            if let value = prefix { progress(min(max(value / 100, 0), 1)) }
        }

        if token?.isCancelled == true { throw V2AError.message("已取消") }
        guard result.status == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw V2AError.message(message.isEmpty ? "下载失败" : message)
        }

        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: [.fileSizeKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        let media = files
            .filter { ["mp4", "mkv", "webm", "mov", "m4a"].contains($0.pathExtension.lowercased()) }
            .sorted { a, b in
                let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let sb = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sa > sb
            }
            .first
        guard let file = media else { throw V2AError.message("下载完成但没找到文件") }
        return file
    }
}
