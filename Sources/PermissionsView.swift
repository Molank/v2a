import SwiftUI
import AppKit

/// 权限状态检测。macOS 没有公开 API，这里用"能否读取受 TCC 保护的文件"来判断。
enum PermissionCheck {
    /// 完全磁盘访问
    static func fullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let probes = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/Bookmarks.plist",
            home + "/Library/Messages/chat.db"
        ]
        for path in probes where FileManager.default.isReadableFile(atPath: path) {
            return true
        }
        return false
    }

    /// 读取浏览器 Cookie 加密密钥，验证钥匙串授权。
    /// 已授权时静默成功；未授权会弹一次系统授权框。
    static func keychainAccess(for browser: String?) -> Bool? {
        let service: String
        switch browser {
        case "chrome":  service = "Chrome Safe Storage"
        case "edge":    service = "Microsoft Edge Safe Storage"
        case "brave":   service = "Brave Safe Storage"
        default:        return nil      // Safari 不靠钥匙串，Firefox 不加密
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess
    }
}

/// 偏好设置：权限 / 下载 / 关于
struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var l10n: Localization
    @StateObject private var languageMenu = ToggleState()
    var onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.v2aAccent.opacity(0.12))
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.v2aAccent)
                }
                .frame(width: 40, height: 40)

                Text(l10n.t("偏好设置"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            section(l10n.t("权限")) {
                permissionRow(icon: "lock.shield.fill",
                              title: l10n.t("完全磁盘访问"),
                              detail: l10n.t("只有勾选「下载最高品质」时才需要：读浏览器 Cookie 才能拿会员 / Hi-Res 内容。不开启也能正常下载公开内容。"),
                              granted: model.fdaGranted,
                              actionTitle: model.fdaGranted == false ? l10n.t("去授权") : nil,
                              action: { model.openFullDiskAccessSettings() })

                hairline

                permissionRow(icon: "key.fill",
                              title: l10n.t("浏览器 Cookie"),
                              detail: l10n.t("Chrome / Edge 的 Cookie 是加密的，首次读取时系统会弹一次授权框；Safari / Firefox 不需要这一步。"),
                              granted: model.keychainGranted,
                              actionTitle: model.keychainGranted == false
                                    ? l10n.t("重新授权")
                                    : (model.keychainGranted == nil && model.cookieBrowser != nil ? l10n.t("检测") : nil),
                              action: { model.probeKeychain() })
            }

            if model.fdaGranted == true {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("第一步完成，接下来是浏览器 Cookie"))
                            .font(.system(size: 11, weight: .medium))
                        Text(l10n.t("去下载一条会员 / Hi-Res 内容，第一次读取浏览器 Cookie 时系统会弹授权框，点「允许」即可。"))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.v2aSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.10)))
            }

            section(l10n.t("下载")) {
                HStack(spacing: 12) {
                    iconTile("folder.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.t("保存到"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(model.downloadDirectory.path)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.v2aSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if model.downloadFolderPath != nil {
                        Button(l10n.t("恢复默认")) { model.resetDownloadFolder() }
                            .buttonStyle(SoftButtonStyle(compact: true))
                    }
                    Button(l10n.t("更改…")) { model.chooseDownloadFolder() }
                        .buttonStyle(SoftButtonStyle(compact: true))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                hairline

                Toggle(isOn: $model.autoRevealDownload) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.t("下载完成后在 Finder 中显示"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(l10n.t("自动打开下载文件所在的文件夹"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.v2aSecondary)
                    }
                }
                .toggleStyle(CapsuleSwitchStyle())
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            section(l10n.t("语言")) {
                HStack(spacing: 12) {
                    iconTile("globe")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.t("界面语言"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(l10n.t("跟随系统语言，或手动选择"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.v2aSecondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        languageMenu.on.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(Localization.shared.language.label)
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
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $languageMenu.on, arrowEdge: .bottom) {
                        languageList
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            section(l10n.t("关于")) {
                HStack(spacing: 12) {
                    Image(nsImage: AppIconImage.shared)
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("V2A · Video to Audio")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(l10n.isEnglish ? "Version \(model.appVersion) · by @Bowie" : "版本 \(model.appVersion) · 作者 @Bowie")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.v2aSecondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            HStack {
                Spacer()
                Button(l10n.t("完成")) { onClose() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 460)
        .background(FrostedBackground())
        .background(ClearWindowBackground())
        .onAppear {
            model.refreshPermissions()
            if model.fdaGranted == true, model.cookieBrowser != nil {
                model.probeKeychain()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }

    private var languageList: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    Localization.shared.language = lang
                    languageMenu.on = false
                } label: {
                    HStack(spacing: 6) {
                        Text(lang.label)
                            .font(.system(size: 11.5))
                        if !lang.isAvailable {
                            Text("即将支持")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.v2aSecondary)
                        }
                        Spacer(minLength: 0)
                        if Localization.shared.language == lang {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!lang.isAvailable)
                .opacity(lang.isAvailable ? 1 : 0.45)
            }
        }
        .padding(6)
        .frame(width: 170)
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
            .padding(.leading, 56)
    }

    private func iconTile(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.v2aAccent.opacity(0.12))
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.v2aAccent)
        }
        .frame(width: 30, height: 30)
    }

    // MARK: - 行

    private func permissionRow(icon: String, title: String, detail: String,
                               granted: Bool?,
                               actionTitle: String? = nil,
                               action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            iconTile(icon)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    statusPill(granted)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.v2aSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle) { action() }
                    .buttonStyle(SoftButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func statusPill(_ granted: Bool?) -> some View {
        switch granted {
        case .some(true):  pill(l10n.t("已授权"), color: .green)
        case .some(false): pill(l10n.t("未授权"), color: .orange)
        case .none:        pill(l10n.t("按需询问"), color: .secondary)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}
