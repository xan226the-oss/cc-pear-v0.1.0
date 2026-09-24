import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

final class ClipboardShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var isPinned = false {
        didSet {
            panel?.level = isPinned ? .statusBar : .normal
        }
    }
    @Published var isTakingScreenshot = false
    @Published private(set) var clearShelfSelectionRequest = 0
    @Published private(set) var confirmShelfSelectionRequest = 0

    private let settings = AppSettings()
    private let store = ClipboardStore()
    private lazy var editorStore = ImageEditorStore(output: store)
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var screenshotMonitor = ScreenshotMonitor(store: store)
    private lazy var commandSignalMonitor = CommandSignalMonitor { [weak self] in
        self?.showPopover()
    }
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var editorWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var hasPositionedPanel = false
    private var lastExternalApp: NSRunningApplication?
    private var screenshotReturnApp: NSRunningApplication?
    private var screenshotStartChangeCount = 0
    private var localShortcutMonitor: Any?
    private var globalShortcutMonitor: Any?
    private var screenshotProcess: Process?
    private var pendingPasteEntries: [ClipboardEntry] = []
    private var pendingFirstPasteWait: TimeInterval = 0.12
    private var isCompletingPendingPaste = false
    private var popoverHotKeyRef: EventHotKeyRef?
    private var screenshotHotKeyRef: EventHotKeyRef?
    private var pendingPasteHotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var hasShelfSelection = false
    private var screenshotWindowVisibility = ScreenshotWindowVisibility()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
        installHotKeyHandlerIfNeeded()
        registerPopoverHotKey()
        registerScreenshotHotKey()
        setupScreenshotShortcutMonitors()
        observeActiveApp()
        monitor.start()
        screenshotMonitor.start()
        commandSignalMonitor.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if !self.settings.hasCompletedOnboarding {
                self.showOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        screenshotMonitor.stop()
        commandSignalMonitor.stop()
        if let localShortcutMonitor {
            NSEvent.removeMonitor(localShortcutMonitor)
        }
        if let globalShortcutMonitor {
            NSEvent.removeMonitor(globalShortcutMonitor)
        }
        unregisterPopoverHotKey()
        unregisterScreenshotHotKey()
        unregisterPendingPasteHotKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    func togglePopover() {
        if panel?.isVisible == true {
            forceClosePopover()
        } else {
            showPopover()
        }
    }

    func showPopover(reposition: Bool = false, preferFloating: Bool = false) {
        if panel == nil {
            setupPanel()
        }

        guard let panel else { return }
        if reposition || !hasPositionedPanel {
            positionPanel(panel)
            hasPositionedPanel = true
        }
        panel.level = isPinned || preferFloating ? .statusBar : .normal
        if PopoverPresentationPolicy.activatesApplication {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            NSApp.unhideWithoutActivation()
            panel.orderFrontRegardless()
        }
    }

    func closePopover() {
        panel?.orderOut(nil)
    }

    func forceClosePopover() {
        panel?.orderOut(nil)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func updateShelfSelectionState(hasSelection: Bool) {
        hasShelfSelection = hasSelection
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 390),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "cc-pear 设置"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SettingsView(settings: settings, store: store, app: self)
            )
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showImageEditor(path: String, title: String) {
        guard FileManager.default.fileExists(atPath: path), NSImage(contentsOfFile: path) != nil else {
            let alert = NSAlert()
            alert.messageText = "图片已不可用"
            alert.informativeText = "找不到该图片文件，无法进入编辑。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }

        setupEditorWindowIfNeeded()
        editorStore.prepare(
            recentScreenshots: store.recentScreenshots(limit: 10),
            selectedPath: path,
            selectedTitle: title.isEmpty ? "图片" : title
        )
        NSApp.activate(ignoringOtherApps: true)
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) v\(AppInfo.version)"
        alert.informativeText = "轻量剪贴板与截图小工具。\n\n所有数据仅保存在本地，不上传任何内容。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func openDataFolder() {
        guard let directory = try? AppPaths.supportDirectory() else { return }
        NSWorkspace.shared.open(directory)
    }

    func clearAllDataAndSettings() {
        unregisterPopoverHotKey()
        unregisterScreenshotHotKey()
        unregisterPendingPasteHotKey()
        store.clearAll()
        settings.resetAllSettings()
        registerPopoverHotKey()
        registerScreenshotHotKey()
        showOnboarding()
    }

    func finishOnboarding() {
        onboardingWindow?.orderOut(nil)
    }

    func updateScreenshotShortcut(_ shortcut: AppShortcut) -> Bool {
        let previous = settings.screenshotShortcut
        unregisterScreenshotHotKey()
        let success = registerScreenshotHotKey(shortcut)
        if !success {
            _ = registerScreenshotHotKey(previous)
        }
        return success
    }

    func updatePopoverShortcut(_ shortcut: AppShortcut) -> Bool {
        let previous = settings.popoverShortcut
        unregisterPopoverHotKey()
        let success = registerPopoverHotKey(shortcut)
        if !success {
            _ = registerPopoverHotKey(previous)
        }
        return success
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    func showOnboardingGuide() {
        showOnboarding()
    }

    func takeScreenshotToClipboard() {
        guard !isTakingScreenshot else { return }

        isTakingScreenshot = true
        screenshotStartChangeCount = NSPasteboard.general.changeCount
        screenshotReturnApp = lastExternalApp
        screenshotWindowVisibility = ScreenshotWindowVisibility(
            panel: panel?.isVisible == true,
            editor: editorWindow?.isVisible == true,
            settings: settingsWindow?.isVisible == true,
            onboarding: onboardingWindow?.isVisible == true
        )
        hideOwnWindowsForScreenshot()
        NSApp.hide(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.startInteractiveScreenshot()
        }
    }

    func pasteOrderedEntries(_ entries: [ClipboardEntry]) {
        guard !entries.isEmpty else { return }
        prepareManualPaste(entries)
    }

    func confirmOrderedEntriesForManualPaste(_ entries: [ClipboardEntry]) {
        guard !entries.isEmpty else { return }
        prepareManualPaste(entries)
    }

    private func prepareManualPaste(_ entries: [ClipboardEntry]) {
        if entries.count > 1, !ensureAccessibilityTrusted() {
            showAccessibilityHelp()
            return
        }

        pendingPasteEntries = Array(entries.dropFirst())
        pendingFirstPasteWait = entries[0].kind == .image || entries[0].kind == .file ? 0.30 : 0.05
        store.copyToPasteboard(entries[0])

        if pendingPasteEntries.isEmpty {
            unregisterPendingPasteHotKey()
        } else {
            registerPendingPasteHotKey()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            NSApp.hide(nil)
            self?.panel?.orderOut(nil)
        }
    }

    private func continuePendingPasteAfterUserCommandV(shouldSendFirstPaste: Bool = false) {
        guard !pendingPasteEntries.isEmpty, !isCompletingPendingPaste else { return }

        let entries = pendingPasteEntries
        let firstPasteWait = pendingFirstPasteWait
        pendingPasteEntries.removeAll()
        isCompletingPendingPaste = true
        unregisterPendingPasteHotKey()

        if shouldSendFirstPaste {
            sendCommandV()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + firstPasteWait) { [weak self] in
            self?.pasteNext(entries, index: 0) { [weak self] in
                self?.isCompletingPendingPaste = false
            }
        }
    }

    private func registerPendingPasteHotKey() {
        unregisterPendingPasteHotKey()
        installHotKeyHandlerIfNeeded()

        HotKeyDispatcher.pendingPasteAction = { [weak self] in
            self?.continuePendingPasteAfterUserCommandV(shouldSendFirstPaste: true)
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: "PSTV".fourCharCode, id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            pendingPasteHotKeyRef = ref
        }
    }

    private func registerPopoverHotKey() {
        _ = registerPopoverHotKey(settings.popoverShortcut)
    }

    @discardableResult
    private func registerPopoverHotKey(_ shortcut: AppShortcut) -> Bool {
        unregisterPopoverHotKey()
        installHotKeyHandlerIfNeeded()

        HotKeyDispatcher.popoverAction = { [weak self] in
            self?.showPopover(reposition: true, preferFloating: true)
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: "PEAR".fourCharCode, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            popoverHotKeyRef = ref
            return true
        }
        return false
    }

    private func registerScreenshotHotKey() {
        _ = registerScreenshotHotKey(settings.screenshotShortcut)
    }

    @discardableResult
    private func registerScreenshotHotKey(_ shortcut: AppShortcut) -> Bool {
        unregisterScreenshotHotKey()
        installHotKeyHandlerIfNeeded()

        HotKeyDispatcher.screenshotAction = { [weak self] in
            self?.takeScreenshotToClipboard()
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: "SHOT".fourCharCode, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            screenshotHotKeyRef = ref
            return true
        }
        return false
    }

    private func unregisterScreenshotHotKey() {
        if let screenshotHotKeyRef {
            UnregisterEventHotKey(screenshotHotKeyRef)
            self.screenshotHotKeyRef = nil
        }
        HotKeyDispatcher.screenshotAction = nil
    }

    private func unregisterPopoverHotKey() {
        if let popoverHotKeyRef {
            UnregisterEventHotKey(popoverHotKeyRef)
            self.popoverHotKeyRef = nil
        }
        HotKeyDispatcher.popoverAction = nil
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandler == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                if let event {
                    GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                }

                DispatchQueue.main.async {
                    Task { @MainActor in
                        HotKeyDispatcher.handle(hotKeyID)
                    }
                }
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &hotKeyHandler
        )
    }

    private func unregisterPendingPasteHotKey() {
        if let pendingPasteHotKeyRef {
            UnregisterEventHotKey(pendingPasteHotKeyRef)
            self.pendingPasteHotKeyRef = nil
        }
        HotKeyDispatcher.pendingPasteAction = nil
    }

    private func pasteNext(_ entries: [ClipboardEntry], index: Int, onComplete: (() -> Void)? = nil) {
        guard entries.indices.contains(index) else {
            onComplete?()
            return
        }

        let entry = entries[index]
        store.copyToPasteboard(entry)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            self.sendCommandV()

            let wait: TimeInterval = entry.kind == .image || entry.kind == .file ? 0.30 : 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.pasteNext(entries, index: index + 1, onComplete: onComplete)
            }
        }
    }

    private func ensureAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    private func showAccessibilityHelp() {
        let alert = NSAlert()
        alert.messageText = "需要打开“辅助功能”权限"
        alert.informativeText = "自动按顺序粘贴需要允许“cc-pear”控制电脑。\n\n请在“系统设置 > 隐私与安全性 > 辅助功能”里打开“cc-pear”。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func sendCommandV() {
        sendKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    private func startInteractiveScreenshot() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishInteractiveScreenshot()
            }
        }

        screenshotProcess = process

        do {
            try process.run()
        } catch {
            screenshotProcess = nil
            finishInteractiveScreenshot()
        }
    }

    private func finishInteractiveScreenshot() {
        screenshotProcess = nil
        isTakingScreenshot = false

        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != screenshotStartChangeCount,
           NSImage(pasteboard: pasteboard) != nil {
            _ = store.addCurrentPasteboardImageAsScreenshot(changeCount: pasteboard.changeCount)
            restoreAfterInteractiveScreenshot(outcome: .captured)
            return
        }

        restoreAfterInteractiveScreenshot(outcome: .cancelled)
    }

    private func cancelInteractiveScreenshotIfNeeded() {
        guard isTakingScreenshot else { return }
        screenshotProcess?.terminate()
        screenshotProcess = nil
        isTakingScreenshot = false
        restoreAfterInteractiveScreenshot(outcome: .cancelled)
    }

    private func waitForScreenshotResult(until deadline: Date) {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != screenshotStartChangeCount,
           NSImage(pasteboard: pasteboard) != nil {
            isTakingScreenshot = false
            _ = store.addCurrentPasteboardImageAsScreenshot(changeCount: pasteboard.changeCount)
            restoreAfterInteractiveScreenshot(outcome: .captured)
            return
        }

        guard Date() < deadline else {
            isTakingScreenshot = false
            restoreAfterInteractiveScreenshot(outcome: .cancelled)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForScreenshotResult(until: deadline)
        }
    }

    private func restoreAfterInteractiveScreenshot(outcome: ScreenshotCompletionOutcome) {
        let returnApp = screenshotReturnApp
        screenshotReturnApp = nil
        NSApp.unhideWithoutActivation()
        let visibilityToRestore = ScreenshotRestorePolicy.visibility(
            after: outcome,
            before: screenshotWindowVisibility
        )

        var restoredOwnWindow = false
        if visibilityToRestore.panel {
            panel?.orderFrontRegardless()
            restoredOwnWindow = true
        }
        if visibilityToRestore.editor {
            editorWindow?.makeKeyAndOrderFront(nil)
            restoredOwnWindow = true
        }
        if visibilityToRestore.settings {
            settingsWindow?.orderFrontRegardless()
            restoredOwnWindow = true
        }
        if visibilityToRestore.onboarding {
            onboardingWindow?.orderFrontRegardless()
            restoredOwnWindow = true
        }
        screenshotWindowVisibility = ScreenshotWindowVisibility()

        if restoredOwnWindow {
            NSApp.activate(ignoringOtherApps: true)
        } else if let returnApp, !returnApp.isTerminated {
            returnApp.activate(options: [])
        }
    }

    private func hideOwnWindowsForScreenshot() {
        panel?.orderOut(nil)
        editorWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        onboardingWindow?.orderOut(nil)
    }

    private func sendKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func setupScreenshotShortcutMonitors() {
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalShortcutEvent(event)
        }

        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalShortcutEvent(event)
            }
        }
    }

    private func handleLocalShortcutEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .rightMouseDown, confirmShelfSelectionIfNeeded(for: event) {
            return nil
        }

        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
            if clearShelfSelectionIfNeeded() {
                return nil
            }
            cancelInteractiveScreenshotIfNeeded()
        }
        return event
    }

    private func handleGlobalShortcutEvent(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            cancelInteractiveScreenshotIfNeeded()
        }
    }

    private func clearShelfSelectionIfNeeded() -> Bool {
        guard panel?.isVisible == true, hasShelfSelection else { return false }
        hasShelfSelection = false
        clearShelfSelectionRequest += 1
        return true
    }

    private func confirmShelfSelectionIfNeeded(for event: NSEvent) -> Bool {
        guard let panel,
              panel.isVisible,
              hasShelfSelection,
              event.window === panel else {
            return false
        }
        confirmShelfSelectionRequest += 1
        return true
    }

    private func setupPanel() {
        let panel = ClipboardShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.borderless, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "cc-pear"
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 280, height: 220)
        panel.setFrameAutosaveName("CCPearPanel")
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentViewController = NSHostingController(
            rootView: ShelfView(store: store, app: self)
        )
        self.panel = panel
    }

    private func setupEditorWindowIfNeeded() {
        guard editorWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "cc-pear 图片编辑"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("CCPearImageEditor")
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: ImageEditorView(store: editorStore)
        )
        window.center()
        editorWindow = window
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "欢迎使用 cc-pear"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: OnboardingView(settings: settings, app: self)
            )
            onboardingWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func positionPanel(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let mouse = NSEvent.mouseLocation
        let x = min(max(mouse.x - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(mouse.y - size.height - 18, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "cc-pear")
        item.button?.title = "梨"
        item.button?.toolTip = "cc-pear"
        item.menu = makeStatusMenu()
        statusItem = item
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开/关闭小窗", action: #selector(openPopoverFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "截图", action: #selector(takeScreenshotFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettingsFromMenu), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "新手指引", action: #selector(showOnboardingFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "关于 cc-pear", action: #selector(showAboutFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitFromMenu), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    private func observeActiveApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                guard app.processIdentifier != NSRunningApplication.current.processIdentifier else {
                    return
                }
                self?.lastExternalApp = app
            }
        }
        lastExternalApp = NSWorkspace.shared.frontmostApplication
    }

    @objc private func openPopoverFromMenu() { showPopover() }
    @objc private func takeScreenshotFromMenu() { takeScreenshotToClipboard() }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func showOnboardingFromMenu() { showOnboardingGuide() }
    @objc private func showAboutFromMenu() { showAbout() }
    @objc private func quitFromMenu() { quit() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard editorStore.hasDirtySessions else { return .terminateNow }
        switch runUnsavedEditorAlert(message: "退出前要保存图片标注吗？") {
        case .save:
            return editorStore.saveAllDirty() ? .terminateNow : .terminateCancel
        case .discard:
            editorStore.discardAllChanges()
            return .terminateNow
        case .cancel:
            return .terminateCancel
        }
    }

    private func runUnsavedEditorAlert(message: String) -> UnsavedEditorChoice {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "未保存的标注不会自动保留为草稿。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存全部")
        alert.addButton(withTitle: "放弃修改")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === editorWindow {
            guard editorStore.hasDirtySessions else {
                sender.orderOut(nil)
                return false
            }
            switch runUnsavedEditorAlert(message: "关闭编辑器前要保存标注吗？") {
            case .save:
                if editorStore.saveAllDirty() {
                    sender.orderOut(nil)
                }
            case .discard:
                editorStore.discardAllChanges()
                sender.orderOut(nil)
            case .cancel:
                break
            }
            return false
        }
        sender.orderOut(nil)
        return false
    }
}

private enum UnsavedEditorChoice {
    case save
    case discard
    case cancel
}

@MainActor
private enum HotKeyDispatcher {
    static var popoverAction: (() -> Void)?
    static var screenshotAction: (() -> Void)?
    static var pendingPasteAction: (() -> Void)?

    static func handle(_ hotKeyID: EventHotKeyID) {
        switch hotKeyID.signature {
        case "PEAR".fourCharCode:
            popoverAction?()
        case "SHOT".fourCharCode:
            screenshotAction?()
        case "PSTV".fourCharCode:
            pendingPasteAction?()
        default:
            break
        }
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for scalar in unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}
