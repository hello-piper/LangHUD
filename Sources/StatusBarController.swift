import AppKit

/// 菜单栏图标：显示当前中/英，提供设置入口、隐藏与退出
final class StatusBarController: NSObject {
    var onCheckPermission: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var currentItem: NSMenuItem?
    private var rememberInputSourceItem: NSMenuItem?

    func setup() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .systemFont(ofSize: 12, weight: .semibold)
        item.button?.title = "中"

        let menu = NSMenu()

        let current = NSMenuItem(title: "当前输入法", action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        currentItem = current

        menu.addItem(.separator())

        rememberInputSourceItem = addToggle(to: menu,
                                            title: "按应用记忆输入法",
                                            isOn: Settings.rememberPerAppInputSource,
                                            action: #selector(toggleRememberInputSource))

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let hide = NSMenuItem(title: "隐藏菜单栏图标", action: #selector(hideStatusBar), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

        let permission = NSMenuItem(title: "辅助功能权限…",
                                    action: #selector(checkPermission),
                                    keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    func update(state: InputSourceState) {
        statusItem?.button?.title = AXIsProcessTrusted() ? state.glyph : "⚠"
        currentItem?.title = "当前：\(state.isChinese ? "中文" : "英文")（\(state.name)）"
    }

    /// 显示 / 隐藏菜单栏图标，App 本身继续运行
    func setVisible(_ visible: Bool) {
        if visible { show() } else { hide() }
    }

    private func hide() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
        currentItem = nil
        rememberInputSourceItem = nil
    }

    private func show() {
        guard statusItem == nil else { return }
        setup()
        update(state: InputSourceReader.current())
    }

    // MARK: - 菜单构建

    private func addToggle(to menu: NSMenu, title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        menu.addItem(item)
        return item
    }

    // MARK: - 动作

    @objc private func toggleRememberInputSource() {
        Settings.rememberPerAppInputSource.toggle()
        rememberInputSourceItem?.state = Settings.rememberPerAppInputSource ? .on : .off
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func hideStatusBar() {
        Settings.showInMenuBar = false
        hide()
    }

    @objc private func checkPermission() {
        onCheckPermission?()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url { NSWorkspace.shared.open(url) }
    }

    @objc private func quit() {
        onQuit?()
    }
}
