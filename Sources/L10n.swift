import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zhHans, en, zhHant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .zhHant: return "繁體中文"
        }
    }

    /// 繁体暂未提供
    var isAvailable: Bool { self != .zhHant }
}

/// 轻量本地化：以中文原文为 key，只维护一份英文表
final class Localization: ObservableObject {
    static let shared = Localization()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "v2a.language")
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "v2a.language") ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// 当前是否用英文
    var isEnglish: Bool {
        switch language {
        case .en: return true
        case .zhHans, .zhHant: return false
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.lowercased().hasPrefix("en")
        }
    }

    func t(_ chinese: String) -> String {
        guard isEnglish else { return chinese }
        return Self.english[chinese] ?? chinese
    }

    // MARK: - 英文对照

    private static let english: [String: String] = [
        "音视频下载 ｜ 视频提取音频": "Video & audio download ｜ Audio extraction",
        "清空列表": "Clear list",
        "粘贴视频链接（YouTube / B 站等）": "Paste a video link (YouTube, Bilibili…)",
        "添加视频（⌘O）": "Add videos (⌘O)",
        "拖入视频，或直接粘贴链接": "Drop a video, or paste a link",
        "视频支持 MP4、MOV、MKV、AVI、WebM、TS 等，也可整个文件夹拖入\n按 ⌘V 粘贴 YouTube / B 站 等链接": "MP4, MOV, MKV, AVI, WebM, TS and more — folders work too\nPress ⌘V to paste a YouTube / Bilibili link",
        "选择文件…": "Choose Files…",
        "松手即可添加": "Release to add",
        "尚未添加文件": "No files yet",
        "全部完成": "All done",
        "开始提取": "Extract",
        "与源文件同目录": "Same folder as source",
        "选择文件夹…": "Choose Folder…",
        "提取中": "Extracting",
        "待处理": "Pending",
        "读取中": "Reading…",
        "完成": "Done",
        "重命名": "Rename",
        "裁剪": "Trim",
        "删除": "Delete",
        "移除": "Remove",
        "重命名输出": "Rename output",
        "只需要写文件名，扩展名会自动保留": "Just the file name — the extension is kept",
        "文件名": "File name",
        "取消": "Cancel",
        "下载": "Download",
        "应用": "Apply",
        "知道了": "Got it",
        "打开系统设置": "Open System Settings",
        "偏好设置": "Preferences",
        "完成 ": "Done ",
        "下载授权": "Download access",
        "不开启也能使用，但无法下载需要会员登录的内容": "Works without it, but member-only content can't be downloaded",
        "完全磁盘访问": "Full Disk Access",
        "下载会员内容的必要权限。": "Required for member-only content.",
        "路径：系统设置 → 隐私与安全性 → 完全磁盘访问，把 V2A 打开后重启 App。": "Path: System Settings → Privacy & Security → Full Disk Access, enable V2A, then relaunch.",
        "音频设置": "Audio settings",
        "格式 / 比特率 / 采样率 / 声道 / 音轨 / 预设": "Format / bitrate / sample rate / channels / track / presets",
        "格式": "Format",
        "预设": "Preset",
        "比特率": "Bitrate",
        "采样率": "Sample rate",
        "跟随源": "Follow source",
        "输出声道": "Output channels",
        "音轨": "Track",
        "无损": "Lossless",
        "单声道": "Mono",
        "立体声": "Stereo",
        "自定义设置": "Custom",
        "还没有预设": "No presets yet",
        "删除预设": "Delete preset",
        "存储当前设置为预设…": "Save current settings as preset…",
        "存储为预设": "Save as preset",
        "预设名称": "Preset name",
        "存储": "Save",
        "当前的格式、比特率、采样率、声道与音轨会被保存，之后可在预设菜单里随时调用。": "The current format, bitrate, sample rate, channels and track are saved and can be recalled from the preset menu.",
        "无损格式不使用比特率；采样率、声道选「跟随源」时保持原样。": "Lossless formats ignore bitrate; sample rate and channels stay untouched when set to Follow source.",
        "比特率只作用于有损格式。采样率和声道都选「跟随源」、且源音轨已是目标编码时，会直接抽流不重新编码；一旦改动就会强制重编码。": "Bitrate only applies to lossy formats. If sample rate and channels follow the source and the audio is already in the target codec, the stream is copied; any change forces a re-encode.",
        "调用或保存音频预设": "Apply or save an audio preset",
        "输入链接": "Enter a link",
        "输入或粘贴 YouTube / Bilibili 等 1700+ 站点地址": "Enter or paste a link from YouTube, Bilibili and 1700+ sites",
        "粘贴链接，或直接 ⌘V": "Paste a link, or press ⌘V",
        "仅下载音频": "Audio only",
        "只保存音轨，不下载视频": "Save the audio track only",
        "下载最高品质": "Best quality",
        "默认最高 1080p；勾选后可取 4K / 8K 与最佳音轨": "Up to 1080p by default; enable for 4K / 8K and the best audio",
        "选择浏览器": "Browser",
        "仅在勾选最高品质时用于读取 Cookie": "Used to read cookies when Best quality is on",
        "去授权": "Authorize",
        "不使用 Cookie": "No cookies",
        "Safari 的 Cookie": "Safari cookies",
        "Chrome 的 Cookie": "Chrome cookies",
        "Edge 的 Cookie": "Edge cookies",
        "Firefox 的 Cookie": "Firefox cookies",
        "正在获取视频信息…": "Fetching video info…",
        "先在下方选一个浏览器": "Pick a browser below first",
        "读取 Cookie 需要「完全磁盘访问」授权": "Reading cookies needs Full Disk Access",
        "这个站点需要登录": "This site requires signing in",
        "权限": "Permissions",
        "只有勾选「下载最高品质」时才需要：读浏览器 Cookie 才能拿会员 / Hi-Res 内容。不开启也能正常下载公开内容。": "Only needed when “Best quality” is on: reading browser cookies unlocks member / Hi-Res content. Public content downloads fine without it.",
        "浏览器 Cookie": "Browser cookies",
        "Chrome / Edge 的 Cookie 是加密的，首次读取时系统会弹一次授权框；Safari / Firefox 不需要这一步。": "Chrome / Edge cookies are encrypted, so macOS asks once on first read. Safari / Firefox don't need this.",
        "重新授权": "Authorize again",
        "检测": "Check",
        "第一步完成，接下来是浏览器 Cookie": "Step 1 done — next: browser cookies",
        "去下载一条会员 / Hi-Res 内容，第一次读取浏览器 Cookie 时系统会弹授权框，点「允许」即可。": "Download a member / Hi-Res item. macOS will ask for keychain access once — choose Allow.",
        "保存到": "Save to",
        "恢复默认": "Reset",
        "更改…": "Change…",
        "下载完成后在 Finder 中显示": "Reveal in Finder after download",
        "自动打开下载文件所在的文件夹": "Open the folder containing the download",
        "关于": "About",
        "已授权": "Granted",
        "未授权": "Not granted",
        "按需询问": "Ask when needed",
        "语言": "Language",
        "跟随系统": "System",
        "简体中文": "简体中文",
        "English": "English",
        "繁體中文": "繁體中文",
        "界面语言": "App language",
        "检查更新": "Check for updates",
        "检查": "Check",
        "前往下载": "Download",
        "重试": "Retry",
        "正在检查…": "Checking…",
        "已是最新版本": "You're up to date",
        "当前版本 ": "Version ",
        "跟随系统语言，或手动选择": "Follow the system language, or pick one",
        "即将支持": "Coming soon",
        "跟随系统语言，或在英文之间切换": "Follow the system language, or pick one",
        "松开即可添加 V2A": "Release to add V2A",
        "按住白色区域，拖到「完全磁盘访问」列表里": "Drag the white area into the Full Disk Access list",
        "暂停（空格）": "Pause (Space)",
        "试听选中片段（空格）": "Preview selection (Space)",
        "开始": "Start",
        "结束": "End",
        "清除裁剪": "Clear trim",
        "拖动两侧拉手选择范围，拖播放头试听；空格播放/暂停，时间码可直接输入。": "Drag the handles to pick a range, drag the playhead to preview. Space plays/pauses; time codes are editable.",
        "正在解析链接…": "Resolving link…",
        "链接下载失败": "Download failed",
        "已取消": "Cancelled",
        "没有音频轨道": "No audio track",
        "没有完成任何文件": "Nothing was converted",
        "未读取到信息": "No info",
        "正在读取…": "Reading…",
        "这些文件已经在列表里了": "These files are already in the list",
        "没有找到视频文件": "No video files found",
        "这不像一个视频链接": "That doesn't look like a video link",
        "App 内缺少 yt-dlp": "yt-dlp is missing from the app",
        "最高品质需要先在「登录站点」里选一个浏览器": "Best quality needs a browser selected first",
        "读取浏览器 Cookie 需要「完全磁盘访问」授权": "Reading browser cookies needs Full Disk Access",
    ]
}
