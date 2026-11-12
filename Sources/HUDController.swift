import AppKit

/// 提示窗展示节奏：淡入 → 停留 1s → 淡出
final class HUDController {
    private let fadeInDuration: TimeInterval = 0.06
    /// 正常 1s；HUD_DEMO_HOLD 存在时保持不消失，仅用于调试截图
    private var holdDuration: TimeInterval {
        ProcessInfo.processInfo.environment["HUD_DEMO_HOLD"] != nil ? 60 : 1.0
    }
    private let fadeOutDuration: TimeInterval = 0.25

    private var panel: HUDWindow?
    private var fadeOutWorkItem: DispatchWorkItem?
    private var generation = 0

    func show(state: InputSourceState, caretRect: CGRect?) {
        let panel = self.panel ?? HUDWindow()
        self.panel = panel
        panel.update(state: state)
        panel.place(near: caretRect)

        generation += 1
        let currentGeneration = generation
        fadeOutWorkItem?.cancel()

        // step1 已可见时只续期（淡出中也能平滑回到 1），避免重复淡入闪烁
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeInDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeInDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        // step2 停留 1s 后淡出
        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel, self.generation == currentGeneration else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = self.fadeOutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                guard self.generation == currentGeneration else { return }
                panel.orderOut(nil)
            })
        }
        fadeOutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: workItem)
    }

    func snapshot(to path: String) {
        panel?.snapshot(to: path)
    }
}

extension HUDWindow {
    /// 贴在插入点旁；拿不到插入点或矩形异常时退回鼠标旁
    func place(near caretRect: CGRect?) {
        if let caret = caretRect, isValidCaret(caret) {
            placeAtCaret(caret)
        } else {
            placeAtMouse()
        }
    }

    /// 插入点矩形合理性：应当窄而矮（光标形状），整块区域或越界值一律不要
    private func isValidCaret(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0
            && rect.width <= 120 && rect.height <= 120
            && NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
    }

    // step1 默认放插入点右下方
    // step2 下方空间不足翻到上方
    // step3 右侧空间不足翻到左侧
    // step4 兜底夹进屏幕
    private func placeAtCaret(_ caret: CGRect) {
        guard let screen = ScreenLocator.screen(containing: caret) else { return }
        let visible = screen.visibleFrame
        let size = frame.size

        var x = caret.minX + 2
        var y = caret.minY - size.height - 6

        if y < visible.minY + 8 {
            y = caret.maxY + 6
        }
        if x + size.width > visible.maxX - 8 {
            x = caret.minX - size.width - 2
        }

        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    // step1 默认放鼠标右下方
    // step2 贴边翻转到上方 / 左侧
    // step3 兜底夹进屏幕
    private func placeAtMouse() {
        let mouse = NSEvent.mouseLocation
        guard let screen = ScreenLocator.screen(containing: mouse) else { return }
        let visible = screen.visibleFrame
        let size = frame.size

        var x = mouse.x + 14
        var y = mouse.y - size.height - 14

        if y < visible.minY + 8 {
            y = mouse.y + 14
        }
        if x + size.width > visible.maxX - 8 {
            x = mouse.x - size.width - 14
        }

        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
        DebugLog.write("placeAtMouse mouse=\(mouse) frame=\(frame)")
    }
}
