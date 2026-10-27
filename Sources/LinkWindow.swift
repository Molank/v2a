import SwiftUI
import AppKit

final class ToggleState: ObservableObject {
    @Published var on = false
}

/// 「下载链接」独立窗口的内容：右上角按钮和主窗口粘贴链接共用这一个窗口
struct LinkOptionsView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var l10n: Localization
    var onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var browserMenu = ToggleState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(l10n.t("输入链接"))
                    .font(.system(size: 15, weight: .semibold))
                Text(l10n.t("输入或粘贴 YouTube / Bilibili 等 1700+ 站点地址"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.v2aSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(WindowDragHandle())
            .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.v2aSecondary)
                    TextField(l10n.t("粘贴链接，或直接 ⌘V"), text: $model.linkField)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .tint(Color.v2aAccent)
                        .onSubmit { model.addLink(model.linkField) }
                }
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background { GlassButtonBackground(height: 34) }
                .clipShape(Capsule())

                previewBlock

                if let error = model.linkError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                Toggle(isOn: $model.audioOnlyDownload) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.t("仅下载音频"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(l10n.t("只保存音轨，不下载视频"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.v2aSecondary)
                            .frame(height: 15, alignment: .topLeading)
                    }
                }
                .toggleStyle(CapsuleSwitchStyle())
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                hairline

                hairline

                Toggle(isOn: $model.highQualityDownload) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.t("下载最高品质"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(l10n.t("默认最高 1080p；勾选后可取 4K / 8K 与最佳音轨"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.v2aSecondary)
                    }
                }
                .toggleStyle(CapsuleSwitchStyle())
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                hairline
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.t("选择浏览器"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(l10n.t("仅在勾选最高品质时用于读取 Cookie"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.v2aSecondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        browserMenu.on.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(cookieLabel)
                                .font(.system(size: 11.5))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.v2aSecondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                        }
                        .opacity(model.highQualityDownload ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $browserMenu.on, arrowEdge: .bottom) {
                        browserMenuList
                    }
                    .disabled(!model.highQualityDownload)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color.white.opacity(0.08)
                          : Color.white.opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.clear : Color.white.opacity(0.45),
                                  lineWidth: 0.6)
            }

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(needsAuthorization ? authorizationHint : "")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.v2aSecondary)
                Spacer(minLength: 4)
                Button(l10n.t("去授权")) {
                    onClose()
                    model.showGeneralSettings = true
                }
                .buttonStyle(SoftButtonStyle(compact: true))
            }
            .opacity(model.highQualityDownload && needsAuthorization ? 1 : 0)
            .frame(height: 24)
            .padding(.top, 2)

            HStack(spacing: 10) {
                Spacer()
                Button(l10n.t("取消")) { onClose() }
                    .buttonStyle(SoftButtonStyle(minWidth: 76))
                    .keyboardShortcut(.cancelAction)

                let empty = model.linkField.trimmingCharacters(in: .whitespaces).isEmpty
                Button {
                    model.addLink(model.linkField)
                } label: {
                    Text(l10n.t("下载"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(empty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                        .padding(.horizontal, 16)
                        .frame(minWidth: 76)
                        .frame(height: 30)
                        .background {
                            if empty {
                                Capsule().fill(Color.primary.opacity(0.055))
                            } else {
                                AccentGlassBackground()
                            }
                        }
                        .shadow(color: Color.black.opacity(empty ? 0 : 0.07), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(empty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(width: 420)
        .background(FrostedBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
        }
        .onAppear {
            model.refreshPermissions()
            model.requestLinkPreview()
        }
        .onChange(of: model.linkField) { _, _ in
            debouncePreview()
        }
    }

    private var browserMenuList: some View {
        VStack(alignment: .leading, spacing: 1) {
            browserOption(l10n.t("不使用 Cookie"), value: nil)
            Divider().padding(.vertical, 4)
            browserOption("Safari", value: "safari")
            browserOption("Chrome", value: "chrome")
            browserOption("Edge", value: "edge")
            browserOption("Firefox", value: "firefox")
        }
        .padding(6)
        .frame(width: 150)
    }

    private func browserOption(_ name: String, value: String?) -> some View {
        Button {
            model.cookieBrowser = value
            browserMenu.on = false
        } label: {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 11.5))
                Spacer(minLength: 0)
                if model.cookieBrowser == value {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .semibold))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 卡片

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.v2aSecondary)
                .padding(.leading, 2)
            VStack(spacing: 0) { content() }
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark
                              ? Color.white.opacity(0.08)
                              : Color.white.opacity(0.72))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.clear : Color.white.opacity(0.45),
                                      lineWidth: 0.6)
                }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.8)
            .padding(.leading, 14)
    }

    // MARK: - 预览

    @ViewBuilder
    private var previewBlock: some View {
        if model.linkPreviewLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(l10n.t("正在获取视频信息…"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.v2aSecondary)
                Spacer(minLength: 0)
            }
            .frame(height: 34)
        } else if let preview = model.linkPreview {
            HStack(spacing: 10) {
                AsyncImage(url: preview.thumbnail.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.primary.opacity(0.05)
                            Image(systemName: "photo")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.v2aTertiary)
                        }
                    }
                }
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([preview.durationText, preview.uploader]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.v2aSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func debouncePreview() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            model.requestLinkPreview()
        }
    }

    // MARK: - 辅助

    private var needsAuthorization: Bool {
        model.cookieBrowser == nil || model.fdaGranted != true
    }

    private var authorizationHint: String {
        model.cookieBrowser == nil
            ? "先在下方选一个浏览器"
            : "读取 Cookie 需要「完全磁盘访问」授权"
    }

    private var cookieLabel: String {
        switch model.cookieBrowser {
        case "safari": return l10n.t("Safari 的 Cookie")
        case "chrome": return l10n.t("Chrome 的 Cookie")
        case "edge": return l10n.t("Edge 的 Cookie")
        case "firefox": return l10n.t("Firefox 的 Cookie")
        default: return l10n.t("不使用 Cookie")
        }
    }
}
