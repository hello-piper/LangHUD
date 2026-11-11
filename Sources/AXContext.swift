import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

/// 当前焦点上下文
struct FocusContext {
    /// 冷冻期 key：pid + 窗口号
    let windowKey: String
    /// 焦点是否落在可输入文本（拿不到 AX 信息时按 true 处理，走降级位置）
    let isTextInput: Bool
    /// 文本插入点矩形（AppKit 全局坐标），nil 表示取不到
    let caretRect: CGRect?
}

/// 插入点取值策略，按 App 缓存，避免每次切换都盲试多条 IPC。
/// 只缓存"确实取到了字符级矩形"的路径，估算不缓存。
private enum CaretStrategy: String {
    /// AXBoundsForRange（相邻字符边界）
    case axRange
    /// AXTextMarkerRangeForRange + AXBoundsForTextMarkerRange（Chromium / WebKit）
    case textMarker
}

enum AXContextReader {
    /// 记录曾经成功拿到过焦点元素的 App，用于区分"焦点丢失"和"AX 树不可用"
    private static let axTreeLock = NSLock()
    private static var appsWithAXTree: Set<pid_t> = []

    /// 每个 App 最近一次成功的取值策略
    private static let strategyLock = NSLock()
    private static var strategyCache: [String: CaretStrategy] = [:]

    /// 必须在后台队列调用，避免 AX 同步 IPC 卡住主线程
    static func current(pid: pid_t) -> FocusContext {
        let appElement = AXUIElementCreateApplication(pid)

        // step0 Chromium / Electron 应用默认不暴露 AX 树，需显式开启
        enableAccessibility(appElement)

        // step1 焦点窗口 → 冷冻期 key
        let windowElement = element(appElement, kAXFocusedWindowAttribute as CFString)
        let windowKey = makeWindowKey(pid: pid, window: windowElement)

        // step2 焦点元素；开启 AX 树是异步的，Chromium 重建可能要几百毫秒，最多重试两次
        var focusedElement = element(appElement, kAXFocusedUIElementAttribute as CFString)
        if focusedElement == nil {
            for _ in 0..<2 {
                usleep(120_000)
                focusedElement = element(appElement, kAXFocusedUIElementAttribute as CFString)
                if focusedElement != nil { break }
            }
        }

        // step3 仍拿不到焦点元素，分两种情况
        //   a) 该 App 曾经拿到过 → AX 树正常，nil 说明焦点落在窗口空白处，不提示
        //   b) 从未拿到过 → AX 树不可用（如 IDEA 未开 screen reader），按可输入降级提示
        guard let focusedElement else {
            let hasAXTree = axTreeLock.withLock { appsWithAXTree.contains(pid) }
            DebugLog.write("focusedElement=nil hasAXTree=\(hasAXTree)")
            return FocusContext(windowKey: windowKey, isTextInput: !hasAXTree, caretRect: nil)
        }

        axTreeLock.withLock {
            if appsWithAXTree.count > 200 { appsWithAXTree.removeAll() }
            appsWithAXTree.insert(pid)
        }

        // step4 焦点不在可输入文本上则不提示
        guard isTextInputElement(focusedElement) else {
            return FocusContext(windowKey: windowKey, isTextInput: false, caretRect: nil)
        }

        // step5 取插入点矩形
        let caret = caretRect(of: focusedElement, appKey: appKey(for: pid))
        return FocusContext(windowKey: windowKey, isTextInput: true, caretRect: caret)
    }

    /// Chromium / Electron 应用需要显式开启才暴露完整 AX 树：
    /// - Electron 认 AXManualAccessibility
    /// - Chromium 只认 AXEnhancedUserInterface（VoiceOver 打开时系统设的就是它）
    static func enableAccessibility(_ appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    // MARK: - 元素判定

    // step1 容器类角色直接排除：Safari 起始页的 AXWebArea 也带 selectedTextRange，
    //       当成输入框会把提示钉在页面左上角
    // step2 明确的文本控件角色
    // step3 其余自定义控件仍按 selectedTextRange 兜底判定
    private static func isTextInputElement(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? ""

        let containers = ["AXWebArea", "AXGroup", "AXScrollArea", "AXWindow",
                          "AXApplication", "AXList", "AXOutline", "AXTable"]
        if containers.contains(role) {
            return false
        }

        let textRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        if textRoles.contains(role) {
            return true
        }

        return copyAttribute(element, kAXSelectedTextRangeAttribute as CFString) != nil
    }

    // MARK: - 插入点

    private static func appKey(for pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid:\(pid)"
    }

    /// AX 坐标（左上原点、y 向下）→ AppKit 全局坐标（左下原点）
    private static func caretRect(of element: AXUIElement, appKey: String) -> CGRect? {
        guard let axRect = rawCaretRect(of: element, appKey: appKey) else { return nil }

        let mainScreenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let rect = CGRect(x: axRect.minX,
                          y: mainScreenHeight - axRect.maxY,
                          width: max(axRect.width, 2),
                          height: max(axRect.height, 1))

        return isValidCaretRect(rect) ? rect : nil
    }

    // step1 该 App 上次成功的策略优先，省掉无效 IPC
    // step2 探测：AX 相邻字符 → 文本标记 → 整行比例 → 位置估算
    // step3 成功的策略写入缓存
    private static func rawCaretRect(of element: AXUIElement, appKey: String) -> CGRect? {
        let range = selectedRange(of: element)
        let cached = strategyLock.withLock { strategyCache[appKey] }

        if let cached {
            switch cached {
            case .axRange:
                if let rect = caretViaAX(element, range) { return rect }
            case .textMarker:
                if let rect = caretViaMarker(element, range) { return rect }
            }
        }

        if let rect = caretViaAX(element, range) {
            store(.axRange, for: appKey)
            return rect
        }
        if let rect = caretViaMarker(element, range) {
            store(.textMarker, for: appKey)
            return rect
        }

        // 估算值不写缓存：AX 树可能只是首次未就绪，固化降级会让该 App 永远只剩估算
        if let rect = lineCaretRect(element, range) ?? estimatedCaretRect(of: element) {
            return rect
        }

        DebugLog.write("caret: all methods failed")
        return nil
    }

    /// 标准 AX 方式：取插入点后一个字符的左边缘，行尾退回前一个字符的右边缘。
    /// 比"按字符数比例切整行"准得多，多行、换行、全角都不跑偏。
    private static func caretViaAX(_ element: AXUIElement, _ range: CFRange?) -> CGRect? {
        guard let range else { return nil }
        let index = caretIndex(range)

        // 后一个字符的左边缘：行中、行首都准；换行符本身宽度为 0，会被 isCharRect 拒掉
        if let rect = boundsForRange(element, CFRange(location: index, length: 1)), isCharRect(rect) {
            return CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
        }

        // 行尾：退到前一个字符的右边缘
        if index > 0,
           let rect = boundsForRange(element, CFRange(location: index - 1, length: 1)), isCharRect(rect) {
            return CGRect(x: rect.maxX, y: rect.minY, width: 2, height: rect.height)
        }

        return nil
    }

    /// Chromium / WebKit：先由 CFRange 换出标记范围，再取矩形。Electron 上比 AXBoundsForRange 可靠。
    private static func caretViaMarker(_ element: AXUIElement, _ range: CFRange?) -> CGRect? {
        guard let range else { return nil }
        let index = caretIndex(range)

        if let rect = boundsViaTextMarker(element, CFRange(location: index, length: 1)), isCharRect(rect) {
            return CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
        }

        if index > 0,
           let rect = boundsViaTextMarker(element, CFRange(location: index - 1, length: 1)), isCharRect(rect) {
            return CGRect(x: rect.maxX, y: rect.minY, width: 2, height: rect.height)
        }

        return nil
    }

    /// 插入点字符位置：有选区时取末端，否则取起点
    private static func caretIndex(_ range: CFRange) -> Int {
        range.length > 0 ? range.location + range.length : range.location
    }

    /// 单字符矩形合理性：宽度过大多半是整行，不能拿 maxX 当光标
    private static func isCharRect(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0 && rect.width <= 100 && rect.height <= 200
    }

    /// 拿不到字符级矩形时，取整行矩形按字符位置比例收窄（兜底）
    private static func lineCaretRect(_ element: AXUIElement, _ range: CFRange?) -> CGRect? {
        guard let range else { return nil }
        let index = caretIndex(range)

        let line = boundsForRange(element, CFRange(location: index, length: 1))
            ?? boundsForRange(element, CFRange(location: index, length: 0))
        guard let line, line.width > 0, line.height > 0, line.height <= 500 else { return nil }

        guard let narrowed = narrowToCaret(line, range: range, element: element) else { return line }
        return narrowed
    }

    /// 整行矩形按字符位置比例收窄到插入点
    private static func narrowToCaret(_ rect: CGRect, range: CFRange, element: AXUIElement) -> CGRect? {
        var total = 0
        if let countValue = copyAttribute(element, kAXNumberOfCharactersAttribute as CFString) as? NSNumber {
            total = countValue.intValue
        }
        guard total > 0 else { return nil }

        let ratio = min(max(CGFloat(caretIndex(range)) / CGFloat(total), 0), 1)
        let caretX = rect.minX + rect.width * ratio
        return CGRect(x: caretX, y: rect.minY, width: 2, height: rect.height)
    }

    private static func boundsForRange(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var mutableRange = range
        guard let rangeParam = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element,
                                                               kAXBoundsForRangeParameterizedAttribute as CFString,
                                                               rangeParam,
                                                               &result)
        guard error == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Chromium / WebKit 的文本标记 API：CFRange → AXTextMarkerRange → bounds
    private static func boundsViaTextMarker(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var mutableRange = range
        guard let rangeParam = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var markerRange: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element,
                                                         "AXTextMarkerRangeForRange" as CFString,
                                                         rangeParam,
                                                         &markerRange) == .success,
              let markerRange else { return nil }

        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element,
                                                               "AXBoundsForTextMarkerRange" as CFString,
                                                               markerRange,
                                                               &result)
        guard error == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// 全都不可用时，用输入框位置估算插入点：左侧内边距、垂直居中
    private static func estimatedCaretRect(of element: AXUIElement) -> CGRect? {
        guard let position = axPoint(element, kAXPositionAttribute as CFString),
              let size = axSize(element, kAXSizeAttribute as CFString),
              size.width > 0, size.height > 0 else { return nil }

        let lineHeight = min(size.height, 24)
        let padding = min(size.width * 0.02, 12)
        return CGRect(x: position.x + padding,
                      y: position.y + (size.height - lineHeight) / 2,
                      width: 2,
                      height: lineHeight)
    }

    private static func store(_ strategy: CaretStrategy, for key: String) {
        strategyLock.withLock {
            if strategyCache.count > 200 { strategyCache.removeAll() }
            strategyCache[key] = strategy
        }
    }

    /// 过滤掉异常值（0 尺寸、整块文本区域高度、屏幕外）
    private static func isValidCaretRect(_ rect: CGRect) -> Bool {
        guard rect.width > 0, rect.height > 0, rect.height <= 500, rect.width <= 500 else { return false }
        return activeDisplayBounds().contains { $0.intersects(rect) }
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.map { CGDisplayBounds($0) }
    }

    // MARK: - 窗口标识

    private static func makeWindowKey(pid: pid_t, window: AXUIElement?) -> String {
        guard let window else { return "\(pid)" }
        if let windowNumber = windowNumber(of: window) {
            return "\(pid)-\(windowNumber)"
        }
        if let title = stringAttribute(window, kAXTitleAttribute as CFString), !title.isEmpty {
            return "\(pid)-title:\(title)"
        }
        return "\(pid)"
    }

    private static func windowNumber(of window: AXUIElement) -> CGWindowID? {
        guard let axGetWindowFunction else { return nil }
        var windowID: CGWindowID = 0
        guard axGetWindowFunction(window, &windowID) == .success, windowID != 0 else { return nil }
        return windowID
    }

    // MARK: - 属性读取

    private static func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        return value as? String
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = copyAttribute(element, kAXSelectedTextRangeAttribute as CFString),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func axPoint(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func axSize(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        guard let value = copyAttribute(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    // MARK: - 诊断

    /// 输出当前焦点元素的 AX 细节，用于排查插入点取不到的原因。
    /// 当前没有 UI 入口，需要时临时在调试代码里调用。
    static func diagnose(pid: pid_t) -> String {
        var lines: [String] = []
        let appElement = AXUIElementCreateApplication(pid)
        let key = appKey(for: pid)
        let strategy = strategyLock.withLock { strategyCache[key] }
        lines.append("pid=\(pid) trusted=\(AXIsProcessTrusted())")
        lines.append("appKey=\(key) strategy=\(strategy?.rawValue ?? "none")")
        lines.append("frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")

        let window = element(appElement, kAXFocusedWindowAttribute as CFString)
        lines.append("windowKey=\(makeWindowKey(pid: pid, window: window))")

        guard let focused = element(appElement, kAXFocusedUIElementAttribute as CFString) else {
            lines.append("focusedElement=nil")
            return lines.joined(separator: "\n")
        }

        lines.append("role=\(stringAttribute(focused, kAXRoleAttribute as CFString) ?? "?")")
        lines.append("subrole=\(stringAttribute(focused, kAXSubroleAttribute as CFString) ?? "?")")

        if let range = selectedRange(of: focused) {
            lines.append("range=\(range.location),\(range.length)")

            var target = CFRange(location: range.location, length: 1)
            let param = AXValueCreate(.cfRange, &target)!
            var out: CFTypeRef?
            let error = AXUIElementCopyParameterizedAttributeValue(focused,
                                                                   kAXBoundsForRangeParameterizedAttribute as CFString,
                                                                   param,
                                                                   &out)
            lines.append("boundsForRange err=\(error.rawValue)")
            if let out, CFGetTypeID(out) == AXValueGetTypeID() {
                var axRect = CGRect.zero
                AXValueGetValue(out as! AXValue, .cgRect, &axRect)
                lines.append("axRect=\(axRect)")
                let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
                let converted = CGRect(x: axRect.minX,
                                       y: mainHeight - axRect.maxY,
                                       width: max(axRect.width, 1),
                                       height: max(axRect.height, 1))
                lines.append("appKitRect=\(converted) valid=\(isValidCaretRect(converted))")
            }

            // 相邻字符
            if let prevRect = boundsForRange(focused, CFRange(location: max(range.location - 1, 0), length: 1)) {
                lines.append("prevCharRect=\(prevRect) isChar=\(isCharRect(prevRect))")
            }
            if let markerRect = boundsViaTextMarker(focused, CFRange(location: range.location, length: 1)) {
                lines.append("markerRect=\(markerRect) isChar=\(isCharRect(markerRect))")
            }
        } else {
            lines.append("selectedTextRange=nil")
        }

        if let lineNumber = copyAttribute(focused, "AXInsertionPointLineNumber" as CFString) {
            lines.append("insertionPointLine=\(lineNumber)")
        }
        if let charCount = copyAttribute(focused, kAXNumberOfCharactersAttribute as CFString) {
            lines.append("numberOfCharacters=\(charCount)")
        }

        if let position = copyAttribute(focused, kAXPositionAttribute as CFString),
           CFGetTypeID(position) == AXValueGetTypeID() {
            var point = CGPoint.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &point)
            lines.append("elementPosition=\(point)")
        }
        if let size = copyAttribute(focused, kAXSizeAttribute as CFString),
           CFGetTypeID(size) == AXValueGetTypeID() {
            var elementSize = CGSize.zero
            AXValueGetValue(size as! AXValue, .cgSize, &elementSize)
            lines.append("elementSize=\(elementSize)")
        }
        lines.append("finalCaret=\(String(describing: caretRect(of: focused, appKey: key)))")
        lines.append("displays=\(activeDisplayBounds())")
        return lines.joined(separator: "\n")
    }
}

// 私有 API：取 AX 窗口对应的 CGWindowID，用于稳定标识窗口
private typealias AXGetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

private let axGetWindowFunction: AXGetWindowFunction? = {
    guard let handle = dlopen(nil, RTLD_NOW),
          let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
    return unsafeBitCast(symbol, to: AXGetWindowFunction.self)
}()
