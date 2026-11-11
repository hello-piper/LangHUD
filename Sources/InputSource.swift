import Carbon
import Foundation

/// 当前输入法状态
struct InputSourceState {
    let id: String
    let name: String
    let isChinese: Bool

    /// 提示窗主字符
    var glyph: String { isChinese ? "中" : "En" }
}

enum InputSourceReader {
    /// 读取当前（前台 App 生效的）输入法
    static func current() -> InputSourceState {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return InputSourceState(id: "", name: "未知输入法", isChinese: false)
        }

        let id = stringProperty(source, kTISPropertyInputSourceID) ?? ""
        let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
        let languages = arrayProperty(source, kTISPropertyInputSourceLanguages)

        return InputSourceState(id: id, name: name, isChinese: isChinese(id: id, languages: languages))
    }

    // step1 语言列表优先判断（zh-Hans / zh-Hant / zh）
    // step2 兜底按输入法 ID 关键字判断（部分三方输入法不带 languages）
    private static func isChinese(id: String, languages: [String]) -> Bool {
        if languages.contains(where: { $0.lowercased().hasPrefix("zh") }) {
            return true
        }
        let keywords = ["SCIM", "TCIM", "Pinyin", "Zhuyin", "Cangjie", "Wubi",
                        "Sogou", "Baidu", "Rime", "Squirrel", "iFlytek", "QQInput"]
        let lowercasedID = id.lowercased()
        return keywords.contains { lowercasedID.contains($0.lowercased()) }
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func arrayProperty(_ source: TISInputSource, _ key: CFString) -> [String] {
        guard let raw = TISGetInputSourceProperty(source, key) else { return [] }
        let value = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as NSArray
        return value.compactMap { $0 as? String }
    }
}

extension InputSourceReader {
    /// 指定输入源的 ID
    static func id(of source: TISInputSource) -> String {
        stringProperty(source, kTISPropertyInputSourceID) ?? ""
    }
}
