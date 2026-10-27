import SwiftUI
import AppKit

extension Color {
    var nsColor: NSColor { NSColor(self) }

    /// 主题色：和 icon 的紫色一致
    static let v2aAccent = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)

    /// 完成态用的绿色（重命名后的名字、转换后体积）
    static let v2aGreen = Color(red: 0x38 / 255, green: 0xC1 / 255, blue: 0x7F / 255)

    /// 界面里的灰色文字：统一 92% 不透明度
    static let v2aSecondary = Color(nsColor: .secondaryLabelColor).opacity(0.92)
    static let v2aTertiary = Color(nsColor: .tertiaryLabelColor).opacity(0.92)
}

/// 只负责拖窗口的一块透明区域（不影响输入框等控件）
struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

// MARK: - 弹窗背景

/// 和主窗口标题栏一样的毛玻璃
struct FrostedBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
    }
}

/// 把所在窗口设成透明，让底下的毛玻璃透出来
struct ClearWindowBackground: NSViewRepresentable {
    final class ClearView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isOpaque = false
            window?.backgroundColor = .clear
        }
    }

    func makeNSView(context: Context) -> ClearView { ClearView() }
    func updateNSView(_ view: ClearView, context: Context) {}
}

// MARK: - 按钮底

/// 白色液态玻璃按钮底：真玻璃 + 白色薄层，胶囊形
struct GlassButtonBackground: View {
    var height: CGFloat = 30
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule()
            .fill(colorScheme == .dark
                  ? Color.white.opacity(0.08)
                  : Color.white.opacity(0.50))
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8)
            }
            .modifier(ButtonGlassLayer())
    }
}

private struct ButtonGlassLayer: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint), in: Capsule())
            } else {
                content.glassEffect(.regular, in: Capsule())
            }
        } else {
            content
        }
    }
}

/// 强调色按钮底：纯色，不加渐变
struct AccentGlassBackground: View {
    var tint: Color = .v2aAccent

    var body: some View {
        Capsule()
            .fill(tint)
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.10)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8)
            }
    }
}

// MARK: - 开关

/// 胶囊型滑动开关（替代默认 checkbox）
struct CapsuleSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            ZStack {
                Capsule()
                    .fill(configuration.isOn
                          ? AnyShapeStyle(Color.v2aAccent)
                          : AnyShapeStyle(Color.primary.opacity(0.16)))
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 1.5, y: 0.5)
                    .padding(2)
                    .offset(x: configuration.isOn ? 10 : -10)
            }
            .frame(width: 48, height: 28)
            .animation(.spring(response: 0.24, dampingFraction: 1.0), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityAddTraits(.isButton)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 按钮样式

/// 次按钮：白色液态玻璃胶囊
struct SoftButtonStyle: ButtonStyle {
    var compact = false
    var tint: Color?
    var minWidth: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat = 30
        return configuration.label
            .font(.system(size: compact ? 11.5 : 12, weight: tint == nil ? .medium : .semibold))
            .foregroundStyle(tint == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            .padding(.horizontal, compact ? 12 : 16)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background {
                if let tint {
                    AccentGlassBackground(tint: tint)
                } else {
                    GlassButtonBackground(height: height)
                }
            }
            .shadow(color: Color.black.opacity(0.07), radius: 2, y: 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .contentShape(Capsule())
    }
}

/// 主按钮：强调色纯色胶囊
struct PillButtonStyle: ButtonStyle {
    var tint: Color = .v2aAccent
    var height: CGFloat = 30
    var minWidth: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background { AccentGlassBackground(tint: tint) }
            .shadow(color: Color.black.opacity(0.07), radius: 2, y: 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .contentShape(Capsule())
    }
}
