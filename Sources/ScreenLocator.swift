import AppKit

enum ScreenLocator {
    /// 光标所在屏幕，取不到时退回鼠标所在屏幕
    static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return screen(containing: center)
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? mouseScreen()
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// 降级位置用：优先前台窗口所在屏幕，其次鼠标所在屏幕
    static func activeScreen() -> NSScreen? {
        frontAppWindowScreen() ?? mouseScreen() ?? NSScreen.main ?? NSScreen.screens.first
    }

    // step1 取前台 App 面积最大的窗口
    // step2 CGWindow 坐标（左上原点、y 向下）转成 AppKit 坐标后匹配屏幕
    private static func frontAppWindowScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                 kCGNullWindowID) as? [[String: Any]] ?? []
        let mainScreenHeight = NSScreen.screens.first?.frame.maxY ?? 0

        let largestWindow = windows
            .filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
            .compactMap { info -> CGRect? in
                guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
                return CGRect(dictionaryRepresentation: bounds as CFDictionary)
            }
            .max { $0.width * $0.height < $1.width * $1.height }

        guard let window = largestWindow, window.width > 0, window.height > 0 else { return nil }
        let center = CGPoint(x: window.midX, y: mainScreenHeight - window.midY)
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
    }

    private static func mouseScreen() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }
}
