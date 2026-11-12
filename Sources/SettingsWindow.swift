import AppKit

/// 设置窗口：菜单栏显隐、按应用记忆
final class SettingsWindowController: NSWindowController {
    /// 任一开关变化时回调，供外部同步状态栏
    var onChange: (() -> Void)?

    private var menuBarCheckbox: NSButton?
    private var memoryCheckbox: NSButton?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "LangHUD"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let menuBarCheckbox = NSButton(checkboxWithTitle: "在菜单栏显示图标",
                                       target: self,
                                       action: #selector(toggleMenuBar))
        menuBarCheckbox.state = Settings.showInMenuBar ? .on : .off
        self.menuBarCheckbox = menuBarCheckbox

        let memoryCheckbox = NSButton(checkboxWithTitle: "按应用记忆输入法",
                                      target: self,
                                      action: #selector(toggleMemory))
        memoryCheckbox.state = Settings.rememberPerAppInputSource ? .on : .off
        self.memoryCheckbox = memoryCheckbox

        let stack = NSStackView(views: [menuBarCheckbox, memoryCheckbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28)
        ])
    }

    /// 显示并置前（无 Dock 图标，需要显式激活）
    func show() {
        menuBarCheckbox?.state = Settings.showInMenuBar ? .on : .off
        memoryCheckbox?.state = Settings.rememberPerAppInputSource ? .on : .off
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleMenuBar() {
        Settings.showInMenuBar = menuBarCheckbox?.state == .on
        onChange?()
    }

    @objc private func toggleMemory() {
        Settings.rememberPerAppInputSource = memoryCheckbox?.state == .on
        onChange?()
    }
}
