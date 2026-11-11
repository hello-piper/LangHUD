import AppKit

/// 事件合并 + 触发提示
final class TriggerCoordinator {
    var onShow: ((InputSourceState, CGRect?) -> Void)?

    private let axQueue = DispatchQueue(label: "com.langhud.mac.ax")
    private let mergeDelay: TimeInterval = 0.08

    private var mergeWorkItem: DispatchWorkItem?
    private var inputWorkItem: DispatchWorkItem?
    private var generation = 0
    /// 最近一次弹出提示的窗口 key，用于「同一窗口只弹一次」
    private var lastWindowKey: String?

    // MARK: - 应用 / 窗口切换

    /// 只在窗口级事件上提示；同一窗口内的焦点变化不再监听
    func handle(_ event: FocusEvent) {
        DebugLog.write("event: \(event)")
        scheduleMerge()
    }

    /// 合并 80ms 内的多次触发（切窗口常连发 focusedWindow / mainWindow），只处理一次
    private func scheduleMerge() {
        mergeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.fire() }
        mergeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + mergeDelay, execute: workItem)
    }

    private func fire() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }

        generation += 1
        let currentGeneration = generation

        axQueue.async { [weak self] in
            let context = AXContextReader.current(pid: pid)
            DispatchQueue.main.async {
                guard let self, self.generation == currentGeneration else { return }

                // 同一窗口只弹一次；切到别的窗口（key 变化）才再弹。
                // 输入法切换走独立路径，不受此约束。
                guard context.windowKey != self.lastWindowKey else {
                    DebugLog.write("skip: same window \(context.windowKey)")
                    return
                }
                self.lastWindowKey = context.windowKey

                DebugLog.write("show key=\(context.windowKey) textInput=\(context.isTextInput) caret=\(String(describing: context.caretRect))")
                // 有插入点贴插入点；没有（含焦点不在输入框、AX 不可用）由 HUD 退到鼠标位置
                self.onShow?(InputSourceReader.current(), context.caretRect)
            }
        }
    }

    // MARK: - 输入法切换

    /// 输入法 / 中英文切换：仅做 120ms 合并防连按
    func handleInputSourceChange() {
        inputWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.fireInputSourceChange() }
        inputWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func fireInputSourceChange() {
        let state = InputSourceReader.current()
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            onShow?(state, nil)
            return
        }

        generation += 1
        let currentGeneration = generation

        axQueue.async { [weak self] in
            let context = AXContextReader.current(pid: pid)
            DispatchQueue.main.async {
                guard let self, self.generation == currentGeneration else { return }
                self.onShow?(state, context.caretRect)
            }
        }
    }
}
