import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipboardStore
    @ObservedObject var app: AppDelegate

    @State private var draftShortcut: AppShortcut
    @State private var draftPopoverShortcut: AppShortcut
    @State private var message = ""
    @State private var showClearConfirmation = false

    init(settings: AppSettings, store: ClipboardStore, app: AppDelegate) {
        self.settings = settings
        self.store = store
        self.app = app
        _draftShortcut = State(initialValue: settings.screenshotShortcut)
        _draftPopoverShortcut = State(initialValue: settings.popoverShortcut)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("设置")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("关于 \(AppInfo.name)") {
                    app.showAbout()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("小窗快捷键")
                    .font(.system(size: 13, weight: .medium))
                ShortcutRecorder(shortcut: $draftPopoverShortcut)
                HStack {
                    Button("保存小窗快捷键") {
                        savePopoverShortcut()
                    }
                    Button("恢复默认 Control + 1") {
                        draftPopoverShortcut = .defaultPopover
                        savePopoverShortcut()
                    }
                    Spacer()
                }

                Divider()
                    .padding(.vertical, 2)

                Text("截图快捷键")
                    .font(.system(size: 13, weight: .medium))
                ShortcutRecorder(shortcut: $draftShortcut)
                HStack {
                    Button("保存快捷键") {
                        saveShortcut()
                    }
                    Button("恢复默认 Command + 2") {
                        draftShortcut = .defaultScreenshot
                        saveShortcut()
                    }
                    Spacer()
                }
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(message.contains("已保存") ? Color.secondary : Color.red)
                }
            }

            Divider()

            Toggle("开机自动启动", isOn: $settings.launchAtLogin)

            HStack {
                Button("打开数据文件夹") {
                    app.openDataFolder()
                }
                Button("清空全部数据", role: .destructive) {
                    showClearConfirmation = true
                }
            }

            Text("普通历史保留七天，收藏内容永久保留。所有数据只保存在本机。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 390)
        .confirmationDialog("清空全部数据？", isPresented: $showClearConfirmation) {
            Button("清空并恢复首次设置", role: .destructive) {
                app.clearAllDataAndSettings()
                draftShortcut = settings.screenshotShortcut
                draftPopoverShortcut = settings.popoverShortcut
                message = "已清空，已恢复默认 Control + 1 和 Command + 2。"
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除历史、收藏、图片缓存、快捷键和开机自启设置。")
        }
    }

    private func saveShortcut() {
        if let validation = draftShortcut.validationMessage {
            message = validation
            return
        }

        if app.updateScreenshotShortcut(draftShortcut) {
            settings.setScreenshotShortcut(draftShortcut)
            message = "已保存：\(draftShortcut.displayText)"
        } else {
            draftShortcut = settings.screenshotShortcut
            message = "这个快捷键被占用，请换一个"
        }
    }

    private func savePopoverShortcut() {
        if let validation = draftPopoverShortcut.validationMessage {
            message = validation
            return
        }

        if app.updatePopoverShortcut(draftPopoverShortcut) {
            settings.setPopoverShortcut(draftPopoverShortcut)
            message = "已保存小窗快捷键：\(draftPopoverShortcut.displayText)"
        } else {
            draftPopoverShortcut = settings.popoverShortcut
            message = "这个快捷键被占用，请换一个"
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var app: AppDelegate

    @State private var draftShortcut: AppShortcut
    @State private var message = ""
    @State private var accessibilityTrusted = false

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(settings: AppSettings, app: AppDelegate) {
        self.settings = settings
        self.app = app
        _draftShortcut = State(initialValue: settings.screenshotShortcut)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("欢迎使用 \(AppInfo.name)")
                                .font(.system(size: 20, weight: .semibold))
                            Text("第一次启动先完成这 3 步，就可以正常截图和顺序粘贴。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("cc-pear 可以做什么")
                            .font(.system(size: 13, weight: .semibold))
                        OnboardingLine(icon: "doc.on.clipboard", text: "自动记录复制过的文字、链接、图片和文件。")
                        OnboardingLine(icon: "rectangle.on.rectangle", text: "默认按 Control + 1 可以随时打开或收起小窗。")
                        OnboardingLine(icon: "star", text: "点星标收藏，收藏内容会永久保留。")
                        OnboardingLine(icon: "camera.viewfinder", text: "按截图快捷键截取屏幕，截图会进入 cc-pear。")
                        OnboardingLine(icon: "return", text: "按顺序选择多条内容，按 Enter 确认，然后到目标位置按 Command + V 粘贴。")
                    }

                    PermissionStepCard(
                        number: 1,
                        title: "打开辅助功能权限",
                        icon: "hand.raised",
                        statusText: accessibilityTrusted ? "已开启" : "需要开启",
                        statusColor: accessibilityTrusted ? .green : .orange,
                        reason: "用于多条内容按顺序自动粘贴。不开也能记录剪贴板，但选择多条后一键顺序粘贴会失败。",
                        buttonTitle: "打开辅助功能设置"
                    ) {
                        app.openAccessibilitySettings()
                    }

                    PermissionStepCard(
                        number: 2,
                        title: "允许录屏与系统录音",
                        icon: "record.circle",
                        statusText: "按系统弹窗确认",
                        statusColor: .blue,
                        reason: "用于截图快捷键截取屏幕。第一次截图时，macOS 可能会弹权限提示，请允许 cc-pear。",
                        tip: "如果权限列表里还没有 cc-pear，先点一次截图快捷键触发系统提示，再回到这里打开权限。",
                        buttonTitle: "打开录屏权限设置"
                    ) {
                        app.openScreenRecordingSettings()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("3")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.accentColor))
                            Text("设置截图快捷键")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        ShortcutRecorder(shortcut: $draftShortcut)
                        Text("小窗默认 Control + 1，截图默认 Command + 2；截图快捷键也可以直接按新的组合键设置。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        OnboardingLine(icon: "lock", text: "所有历史只保存在本机，不上传。")
                        OnboardingLine(icon: "clock", text: "普通历史保留 7 天，收藏内容永久保留。")
                    }

                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(22)
            }

            Divider()

            HStack {
                Button("稍后设置，先使用 Command + 2") {
                    useDefault()
                }
                Spacer()
                Button("开始使用") {
                    saveAndContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(.regularMaterial)
        }
        .frame(width: 560, height: 680)
        .onAppear {
            accessibilityTrusted = app.isAccessibilityTrusted
        }
        .onReceive(permissionTimer) { _ in
            accessibilityTrusted = app.isAccessibilityTrusted
        }
    }

    private func useDefault() {
        _ = app.updateScreenshotShortcut(.defaultScreenshot)
        settings.setScreenshotShortcut(.defaultScreenshot)
        settings.markOnboardingComplete()
        app.finishOnboarding()
    }

    private func saveAndContinue() {
        if let validation = draftShortcut.validationMessage {
            message = validation
            return
        }

        if app.updateScreenshotShortcut(draftShortcut) {
            settings.setScreenshotShortcut(draftShortcut)
            settings.markOnboardingComplete()
            app.finishOnboarding()
        } else {
            message = "这个快捷键被占用，请换一个"
        }
    }
}

private struct PermissionStepCard: View {
    let number: Int
    let title: String
    let icon: String
    let statusText: String
    let statusColor: Color
    let reason: String
    var tip: String?
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.accentColor))
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(statusColor.opacity(0.12))
                    )
            }

            Text(reason)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let tip {
                Text(tip)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            }

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct OnboardingLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: AppShortcut

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let view = ShortcutRecorderField()
        view.onShortcut = { shortcut in
            self.shortcut = shortcut
        }
        view.shortcut = shortcut
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderField, context: Context) {
        nsView.shortcut = shortcut
    }
}

final class ShortcutRecorderField: NSView {
    var shortcut: AppShortcut = .defaultScreenshot {
        didSet {
            needsDisplay = true
        }
    }
    var onShortcut: ((AppShortcut) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 34))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 360, height: 34)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard let shortcut = AppShortcut.from(event: event) else {
            NSSound.beep()
            return
        }
        onShortcut?(shortcut)
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let active = window?.firstResponder === self
        (active ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let text = active ? "直接按新的组合键..." : shortcut.displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: active ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: 12, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
