import Foundation

/// 用户可调项，持久化在 UserDefaults
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let rememberPerAppInputSource = "rememberPerAppInputSource"
    }

    /// 按应用记忆输入法，切应用时自动恢复
    static var rememberPerAppInputSource: Bool {
        get { defaults.object(forKey: Key.rememberPerAppInputSource) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.rememberPerAppInputSource) }
    }
}
