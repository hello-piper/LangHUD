import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hud = HUDController()
    private let focusMonitor = FocusMonitor()
    private let coordinator = TriggerCoordinator()
    private let statusBar = StatusBarController()
    private let inputSourceMemory = InputSourceMemory()
    /// 上一次收到的输入法 ID，用于过滤「输入法没变但系统仍发通知」的假事件
    private var lastInputSourceID: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.reset()
        DebugLog.write("launch trusted=\(focusMonitor.isTrusted)")
        UserDefaults.standard.set(focusMonitor.isTrusted, forKey: "axTrusted")
        lastInputSourceID = InputSourceReader.current().id

        // step1 菜单栏
        statusBar.onCheckPermission = { [weak self] in self?.focusMonitor.requestTrustIfNeeded() }
        statusBar.onQuit = { NSApp.terminate(nil) }
        statusBar.setup()
        statusBar.update(state: InputSourceReader.current())

        // step1.1 记录启动时前台应用的输入法，作为它的初始状态
        if Settings.rememberPerAppInputSource,
           let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            inputSourceMemory.remember(bundleID: bundleID, inputSourceID: InputSourceReader.current().id)
        }

        // step2 提示出口
        coordinator.onShow = { [weak self] state, caretRect in
            self?.statusBar.update(state: state)
            self?.hud.show(state: state, caretRect: caretRect)
        }

        // step3 应用切换 → 重挂 AX 观察者 + 窗口级提示
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(handleAppActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil)

        // step4 窗口 / 焦点切换（调试预览时不挂 AX，避免弹权限框）
        let isDemo = ProcessInfo.processInfo.environment["HUD_DEMO"] != nil
        if !isDemo {
            focusMonitor.onEvent = { [weak self] event in self?.coordinator.handle(event) }
            focusMonitor.start()
        }

        // step5 输入法 / 中英文切换
        DistributedNotificationCenter.default().addObserver(self,
                                                            selector: #selector(handleInputSourceChanged(_:)),
                                                            name: NSNotification.Name("AppleSelectedInputSourcesChangedNotification"),
                                                            object: nil)

        // step6 调试预览：HUD_DEMO=zh|en
        if let demo = ProcessInfo.processInfo.environment["HUD_DEMO"] {
            hud.show(state: demoState(demo), caretRect: nil)
            if let snapshotPath = ProcessInfo.processInfo.environment["HUD_DEMO_SNAPSHOT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.hud.snapshot(to: snapshotPath)
                }
            }
        }
    }

    @objc private func handleAppActivated(_ notification: Notification) {
        let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        DebugLog.write("app activated: \(activated?.localizedName ?? "?") bundle=\(activated?.bundleIdentifier ?? "?")")
        focusMonitor.attach()

        // step1 先恢复该应用上次的输入法，再弹窗
        if Settings.rememberPerAppInputSource,
           let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let bundleID = app.bundleIdentifier {
            inputSourceMemory.applyIfNeeded(bundleID: bundleID)
        }

        // step2 弹窗
        coordinator.handle(.windowChanged)
    }

    @objc private func handleInputSourceChanged(_ notification: Notification) {
        let state = InputSourceReader.current()

        // 输入法 ID 没变：只是焦点切换触发的重复通知，忽略
        guard state.id != lastInputSourceID else { return }
        lastInputSourceID = state.id

        statusBar.update(state: state)
        DebugLog.write("input source changed: \(state.id) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

        // step1 自己触发的切换：不记录、不重复弹窗
        if inputSourceMemory.isSelfTriggered(inputSourceID: state.id) {
            return
        }

        // step2 记录到当前应用
        if Settings.rememberPerAppInputSource,
           let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            inputSourceMemory.remember(bundleID: bundleID, inputSourceID: state.id)
        }

        // step3 弹窗
        coordinator.handleInputSourceChange()
    }

    private func demoState(_ demo: String) -> InputSourceState {
        switch demo.lowercased() {
        case "zh", "cn":
            return InputSourceState(id: "demo.zh", name: "拼音 - 简体", isChinese: true)
        case "en":
            return InputSourceState(id: "demo.en", name: "ABC", isChinese: false)
        default:
            return InputSourceReader.current()
        }
    }
}
