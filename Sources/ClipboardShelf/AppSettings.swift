import AppKit
import Carbon.HIToolbox
import Foundation

struct AppInfo {
    static let name = "cc-pear"
    static let version = "0.1.0"
    static let bundleIdentifier = "app.cc-pear"
}

struct AppShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let defaultScreenshot = AppShortcut(
        keyCode: UInt32(kVK_ANSI_2),
        modifiers: UInt32(cmdKey)
    )

    static let legacyDefaultScreenshot = AppShortcut(
        keyCode: UInt32(kVK_ANSI_2),
        modifiers: UInt32(controlKey)
    )

    static let defaultPopover = AppShortcut(
        keyCode: UInt32(kVK_ANSI_1),
        modifiers: UInt32(controlKey)
    )

    var displayText: String {
        let parts = modifierNames + [Self.keyName(for: keyCode)]
        return parts.joined(separator: " + ")
    }

    private var modifierNames: [String] {
        var names: [String] = []
        if modifiers & UInt32(controlKey) != 0 { names.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { names.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { names.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { names.append("Command") }
        return names
    }

    static func from(event: NSEvent) -> AppShortcut? {
        var modifiers: UInt32 = 0
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else { return nil }
        return AppShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var validationMessage: String? {
        if modifiers == 0 {
            return "请至少搭配 Control、Option 或 Command。"
        }

        let hasStrongModifier = modifiers & UInt32(controlKey) != 0
            || modifiers & UInt32(optionKey) != 0
            || modifiers & UInt32(cmdKey) != 0
        if !hasStrongModifier {
            return "不能只使用 Shift，请搭配 Control、Option 或 Command。"
        }

        if Self.disallowedKeyCodes.contains(keyCode) {
            return "这个按键不适合作为快捷键，请换一个。"
        }

        if isForbiddenSystemShortcut {
            return "这是系统常用快捷键，请换一个。"
        }

        return nil
    }

    private var isForbiddenSystemShortcut: Bool {
        let commandOnly = modifiers & UInt32(cmdKey) != 0
        let controlOnly = modifiers == UInt32(controlKey)
        let optionOnly = modifiers == UInt32(optionKey)

        if commandOnly {
            let commonCommandKeys: Set<UInt32> = [
                UInt32(kVK_ANSI_A), UInt32(kVK_ANSI_C), UInt32(kVK_ANSI_Q),
                UInt32(kVK_ANSI_S), UInt32(kVK_ANSI_V), UInt32(kVK_ANSI_W),
                UInt32(kVK_ANSI_X), UInt32(kVK_ANSI_Z), UInt32(kVK_Tab),
                UInt32(kVK_Space)
            ]
            if commonCommandKeys.contains(keyCode) {
                return true
            }
        }

        if modifiers == UInt32(cmdKey | shiftKey) {
            let screenshotKeys: Set<UInt32> = [
                UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5)
            ]
            if screenshotKeys.contains(keyCode) {
                return true
            }
        }

        return (controlOnly || optionOnly) && keyCode == UInt32(kVK_Space)
    }

    private static let disallowedKeyCodes: Set<UInt32> = [
        UInt32(kVK_Escape), UInt32(kVK_Return), UInt32(kVK_Tab),
        UInt32(kVK_Delete), UInt32(kVK_ForwardDelete), UInt32(kVK_Space),
        UInt32(kVK_LeftArrow), UInt32(kVK_RightArrow),
        UInt32(kVK_UpArrow), UInt32(kVK_DownArrow)
    ]

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
        ]
        return names[keyCode] ?? "按键 \(keyCode)"
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var screenshotShortcut: AppShortcut
    @Published private(set) var popoverShortcut: AppShortcut
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published var launchAtLogin: Bool {
        didSet {
            if launchAtLogin != oldValue {
                LoginAtLaunch.setEnabled(launchAtLogin)
                UserDefaults.standard.set(launchAtLogin, forKey: Self.launchAtLoginKey)
            }
        }
    }

    private static let shortcutKey = "CCPear.screenshotShortcut"
    private static let popoverShortcutKey = "CCPear.popoverShortcut"
    private static let onboardingKey = "CCPear.hasCompletedOnboarding"
    private static let launchAtLoginKey = "CCPear.launchAtLogin"

    init() {
        Self.migrateLegacyDefaultsIfNeeded()
        var shouldSaveMigratedScreenshotShortcut = false

        if let data = UserDefaults.standard.data(forKey: Self.shortcutKey),
           let shortcut = try? JSONDecoder().decode(AppShortcut.self, from: data) {
            if shortcut == .legacyDefaultScreenshot {
                screenshotShortcut = .defaultScreenshot
                shouldSaveMigratedScreenshotShortcut = true
            } else {
                screenshotShortcut = shortcut
            }
        } else {
            screenshotShortcut = .defaultScreenshot
        }

        if let data = UserDefaults.standard.data(forKey: Self.popoverShortcutKey),
           let shortcut = try? JSONDecoder().decode(AppShortcut.self, from: data) {
            popoverShortcut = shortcut
        } else {
            popoverShortcut = .defaultPopover
        }

        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        launchAtLogin = UserDefaults.standard.bool(forKey: Self.launchAtLoginKey)

        if shouldSaveMigratedScreenshotShortcut {
            saveScreenshotShortcut()
        }
    }

    func setScreenshotShortcut(_ shortcut: AppShortcut) {
        screenshotShortcut = shortcut
        saveScreenshotShortcut()
    }

    func setPopoverShortcut(_ shortcut: AppShortcut) {
        popoverShortcut = shortcut
        savePopoverShortcut()
    }

    func markOnboardingComplete() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
    }

    func resetAllSettings() {
        LoginAtLaunch.setEnabled(false)
        UserDefaults.standard.removeObject(forKey: Self.shortcutKey)
        UserDefaults.standard.removeObject(forKey: Self.popoverShortcutKey)
        UserDefaults.standard.removeObject(forKey: Self.onboardingKey)
        UserDefaults.standard.removeObject(forKey: Self.launchAtLoginKey)

        screenshotShortcut = .defaultScreenshot
        popoverShortcut = .defaultPopover
        hasCompletedOnboarding = false
        launchAtLogin = false
    }

    private func saveScreenshotShortcut() {
        guard let data = try? JSONEncoder().encode(screenshotShortcut) else { return }
        UserDefaults.standard.set(data, forKey: Self.shortcutKey)
    }

    private func savePopoverShortcut() {
        guard let data = try? JSONEncoder().encode(popoverShortcut) else { return }
        UserDefaults.standard.set(data, forKey: Self.popoverShortcutKey)
    }

    private static func migrateLegacyDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "CCPear.didMigrateLegacyDefaults") else { return }
        let legacyDefaults = UserDefaults(suiteName: "local.clipboard-shelf")
        if UserDefaults.standard.object(forKey: "CCPear.isPaused") == nil,
           let paused = legacyDefaults?.object(forKey: "ClipboardShelf.isPaused") as? Bool {
            UserDefaults.standard.set(paused, forKey: "CCPear.isPaused")
        }
        UserDefaults.standard.set(true, forKey: "CCPear.didMigrateLegacyDefaults")
    }
}

enum LoginAtLaunch {
    static let label = "app.cc-pear.launch"

    static func setEnabled(_ enabled: Bool) {
        let fileManager = FileManager.default
        guard let agentsDirectory = try? fileManager.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("LaunchAgents", isDirectory: true) else {
            return
        }

        try? fileManager.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        let plistURL = agentsDirectory.appendingPathComponent("\(label).plist")

        if enabled {
            let appPath = Bundle.main.bundlePath
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", appPath],
                "RunAtLoad": true
            ]
            let data = try? PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try? data?.write(to: plistURL, options: .atomic)
        } else {
            try? fileManager.removeItem(at: plistURL)
        }
    }
}
