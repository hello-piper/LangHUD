import Carbon
import Foundation

/// 按应用记忆输入法，切换应用时自动恢复
final class InputSourceMemory {
    private let defaults = UserDefaults.standard
    private let storageKey = "perAppInputSourceMap"

    /// 最近一次由本程序触发的切换，用于忽略自己产生的通知
    private var pendingAppliedID: String?
    private var pendingAppliedAt: Date?

    private var map: [String: String] {
        get {
            let raw = defaults.dictionary(forKey: storageKey) ?? [:]
            return raw.compactMapValues { $0 as? String }
        }
        set {
            defaults.set(newValue, forKey: storageKey)
        }
    }

    // MARK: - 记录

    func remember(bundleID: String, inputSourceID: String) {
        guard !bundleID.isEmpty, !inputSourceID.isEmpty else { return }
        var currentMap = map
        guard currentMap[bundleID] != inputSourceID else { return }
        currentMap[bundleID] = inputSourceID
        map = currentMap
    }

    // MARK: - 恢复

    /// 切到该应用时恢复上次输入法，返回是否真的切换了
    @discardableResult
    func applyIfNeeded(bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        let currentID = InputSourceReader.current().id

        // step1 首次遇到该应用：把当前输入法记为它的初始状态
        guard let targetID = map[bundleID] else {
            remember(bundleID: bundleID, inputSourceID: currentID)
            return false
        }

        // step2 已经是目标输入法，无需切换
        guard targetID != currentID else { return false }

        // step3 切换（TISSelectInputSource 同步生效）
        guard selectInputSource(id: targetID) else { return false }
        pendingAppliedID = targetID
        pendingAppliedAt = Date()
        return true
    }

    /// 这次输入法变化是否由本程序触发（用于跳过记录与重复弹窗）
    func isSelfTriggered(inputSourceID: String) -> Bool {
        guard let pendingID = pendingAppliedID,
              pendingID == inputSourceID,
              let appliedAt = pendingAppliedAt,
              Date().timeIntervalSince(appliedAt) < 1.0 else {
            return false
        }
        pendingAppliedID = nil
        pendingAppliedAt = nil
        return true
    }

    // MARK: - 切换输入源

    // step1 只遍历已启用的输入源
    // step2 按 ID 匹配后切换
    private func selectInputSource(id: String) -> Bool {
        guard let rawList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return false }
        let count = CFArrayGetCount(rawList)
        for index in 0..<count {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(rawList, index), to: TISInputSource.self)
            guard InputSourceReader.id(of: source) == id else { continue }
            return TISSelectInputSource(source) == noErr
        }
        return false
    }
}
