import AppKit
import ApplicationServices

enum FocusEvent {
    /// 应用 / 窗口切换
    case windowChanged
}

/// 通过辅助功能（AX）监听前台 App 的窗口与焦点变化
final class FocusMonitor {
    var onEvent: ((FocusEvent) -> Void)?

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var trustTimer: Timer?

    var isTrusted: Bool { AXIsProcessTrusted() }

    func start() {
        requestTrustIfNeeded()
        attach()
        startTrustPolling()
    }

    /// 授权后系统不会通知进程，轮询检测并自动挂载（免重启）
    private func startTrustPolling() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            UserDefaults.standard.set(self.isTrusted, forKey: "axTrusted")
            guard self.isTrusted, self.observer == nil else { return }
            DebugLog.write("trust granted, attaching")
            self.attach()
        }
    }

    /// 未授权时弹出系统授权引导（首次运行）
    func requestTrustIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        // 自动化测试时跳过授权弹框，避免干扰前台应用
        guard ProcessInfo.processInfo.environment["HUD_SKIP_TRUST_PROMPT"] == nil else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 前台 App 变化后重新挂载观察者
    func attach() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier, pid != observedPID else { return }

        detach()
        guard AXIsProcessTrusted() else {
            DebugLog.write("attach skipped: not trusted (pid=\(pid))")
            return
        }

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, focusObserverCallback, &newObserver) == .success,
              let newObserver else {
            DebugLog.write("AXObserverCreate failed (pid=\(pid))")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // 提前开启 Chromium / Electron 的 AX 树，后续事件才能拿到焦点元素
        AXContextReader.enableAccessibility(appElement)

        AXObserverAddNotification(newObserver, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, appElement, kAXMainWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)

        observer = newObserver
        observedPID = pid
        DebugLog.write("attached pid=\(pid) app=\(frontApp.localizedName ?? "?")")
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = 0
    }

    fileprivate func handle(_ name: String) {
        DebugLog.write("AX notification: \(name)")
        switch name {
        case "AXFocusedWindowChanged", "AXMainWindowChanged":
            onEvent?(.windowChanged)
        default:
            break
        }
    }
}

private let focusObserverCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    Unmanaged<FocusMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String)
}
