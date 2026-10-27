import SwiftUI
import AppKit

/// 按参考图标（48×48 画板）的实测几何还原：
/// 画板圆角 15、纸片 30.545×38.18 @ (8.727, 14.182)、顶右 45° 斜切 8.727、
/// 折角三角 8.727、纸片不透明度 0.8、折角白 50%、文字白。
struct FormatBadge: View {
    let ext: String
    var size: CGFloat = 34

    private var palette: FormatPalette { FormatPalette.palette(for: ext) }

    /// 以 48pt 参考画板为基准的缩放
    private var s: CGFloat { size / 48 }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 15 * s, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            tileShape
                .fill(
                    LinearGradient(
                        colors: [palette.tileLight, palette.tileDark],
                        startPoint: UnitPoint(x: 0.1795, y: 0.0825),
                        endPoint: UnitPoint(x: 0.9282, y: 0.9592)
                    )
                )

            document
                .clipShape(tileShape)
        }
        .frame(width: size, height: size)
    }

    private var document: some View {
        ZStack(alignment: .topLeading) {
            DocumentShape(fold: 8.727 * s, corner: 5 * s)
                .fill(
                    LinearGradient(
                        colors: [palette.docDark, palette.docLight],
                        startPoint: UnitPoint(x: 0.0747, y: 0.0199),
                        endPoint: UnitPoint(x: 0.9270, y: 1.0)
                    )
                )
                .frame(width: 30.545 * s, height: 38.182 * s)
                .shadow(color: palette.shadow, radius: 4 * s, x: 2 * s, y: 4 * s)
                .opacity(0.8)
                .offset(x: 8.727 * s, y: 14.182 * s)

            FoldShape()
                .fill(Color.white.opacity(0.5))
                .frame(width: 8.727 * s, height: 8.727 * s)
                .offset(x: 30.545 * s, y: 14.182 * s)

            Text(palette.label)
                .font(.system(size: labelSize * s, weight: .semibold))
                .tracking(palette.label.count > 3 ? 0 : 0.35 * s)
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .position(x: 24 * s, y: 29.8 * s)
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }

    /// 参考图标里字形高度约 12.5/48，四字母缩一档
    private var labelSize: CGFloat {
        switch palette.label.count {
        case 0...2: return 11.6
        case 3: return 10.2
        default: return 8.8
        }
    }
}

/// 带 45° 斜切角的文稿轮廓（顶右被切，其余为圆角/直角）
private struct DocumentShape: Shape {
    var fold: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: corner, y: 0))
        path.addLine(to: CGPoint(x: w - fold, y: 0))
        path.addLine(to: CGPoint(x: w, y: fold))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: corner))
        path.addQuadCurve(to: CGPoint(x: corner, y: 0),
                          control: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }
}

/// 折角三角：左上 → 右下 → 左下（左下角略圆）
private struct FoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// 配色取自参考图标组的实测值：
/// 蓝/紫/红/橙系文档 B≈0.94–0.95、S≈0.55–0.75；
/// 绿/青系明显更暗（B≈0.75–0.85），否则会发荧光、压不住白字。
struct FormatPalette {
    let label: String
    let hue: Double
    let saturation: Double

    /// 每个色相域给一个基准明度，模拟参考图里"绿色比蓝色暗"的处理
    private var baseBrightness: Double {
        switch hue {
        case 0.26..<0.46:  return 0.78   // 绿
        case 0.46..<0.55:  return 0.80   // 青 / 蓝绿
        case 0.10..<0.26:  return 0.90   // 黄
        case 0.55..<0.60:  return 0.93   // 天蓝
        default:           return 0.94   // 蓝 / 紫 / 品红 / 红 / 橙
        }
    }

    /// 绿/青系在参考图里饱和度更高（Excel 77%），低饱和会显脏
    private var satScale: Double {
        switch hue {
        case 0.26..<0.55: return 1.22
        default: return 1.0
        }
    }

    var tileLight: Color {
        Color(hue: hue, saturation: min(saturation * satScale * 0.32, 0.32),
              brightness: min(baseBrightness + 0.04, 0.985))
    }

    var tileDark: Color {
        Color(hue: hue, saturation: min(saturation * satScale * 0.88, 0.86),
              brightness: baseBrightness - 0.02)
    }

    var docDark: Color {
        Color(hue: hue, saturation: min(saturation * satScale * 1.12, 0.88),
              brightness: baseBrightness)
    }

    var docLight: Color {
        Color(hue: hue, saturation: min(saturation * satScale * 0.68, 0.72),
              brightness: min(baseBrightness + 0.02, 0.975))
    }

    var shadow: Color {
        Color(hue: hue, saturation: saturation, brightness: baseBrightness * 0.62)
            .opacity(0.26)
    }

    static func palette(for ext: String) -> FormatPalette {
        let key = ext.lowercased()
        let label = key.isEmpty ? "FILE" : key.uppercased()

        func make(_ hue: Double, _ saturation: Double) -> FormatPalette {
            FormatPalette(label: label, hue: hue, saturation: saturation)
        }

        switch key {
        // 视频（蓝 → 青绿，饱和度参考图标组）
        case "mp4", "m4v":      return make(0.63, 0.62)
        case "mov":             return make(0.58, 0.70)
        case "mkv":             return make(0.68, 0.58)
        case "avi":             return make(0.65, 0.26)
        case "webm":            return make(0.47, 0.52)
        case "flv":             return make(0.52, 0.55)
        case "wmv", "asf":      return make(0.64, 0.28)
        case "ts", "m2ts":      return make(0.66, 0.50)
        case "3gp":             return make(0.56, 0.58)
        case "ogv":             return make(0.44, 0.52)
        case "mpg", "mpeg", "vob", "rmvb", "mxf":
            return make(0.64, 0.26)
        // 音频
        case "mp3":             return make(0.75, 0.52)
        case "m4a", "aac":      return make(0.71, 0.52)
        case "wav":             return make(0.96, 0.60)
        case "flac":            return make(0.87, 0.52)
        case "ogg", "opus":     return make(0.40, 0.60)
        case "aiff", "aif":     return make(0.08, 0.68)
        default:                return make(0.63, 0.26)
        }
    }
}

/// 调试用：大尺寸图标对照页
struct FormatBadgeGallery: View {
    private let formats = ["mp4", "mov", "mkv", "avi", "webm", "ts",
                           "mp3", "m4a", "wav", "flac", "aiff", "ogg"]

    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(0..<4, id: \.self) { column in
                        let index = row * 4 + column
                        FormatBadge(ext: formats[index], size: 96)
                    }
                }
            }
        }
        .padding(28)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
