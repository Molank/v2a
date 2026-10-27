# 第三方组件

V2A 本身只调用命令行工具，不链接它们的代码。发布 App 时这些二进制会被打包进
`V2A.app/Contents/Resources/bin/`。

| 组件 | 版本 | 许可 | 用途 | 来源 |
| --- | --- | --- | --- | --- |
| ffmpeg | 6.0 (static, arm64) | GPL-3.0（含 x264 等 GPL 组件） | 转码、抽帧、封面抽取 | https://evermeet.cx/ffmpeg/ |
| ffprobe | 6.0 (static, arm64) | GPL-3.0 | 读取媒体信息 | https://evermeet.cx/ffmpeg/ |
| yt-dlp | 2026.10.26 (`yt-dlp_macos`, universal) | Unlicense | 链接解析与下载 | https://github.com/yt-dlp/yt-dlp/releases |

## 分发注意

- **ffmpeg 是 GPL 授权**：分发包含它的二进制包时，需要同时提供对应源码或源码获取方式
  （例如在 Release 说明里附上上面的源码链接）。
- 若希望 App 本体采用更宽松的许可（如 MIT），建议在 README 明确「App 代码 MIT，
  内置 ffmpeg 仍为 GPL」这类分界。
- yt-dlp 为 Unlicense，可自由分发。
