import AppKit

// 入口：无 Dock 图标的菜单栏常驻程序
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
