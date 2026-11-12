import AppKit

/// IDEA New UI Dark 配色
enum IDEATheme {
    static let background = NSColor(srgbRed: 0.169, green: 0.176, blue: 0.188, alpha: 1) // #2B2D30
    /// 深色背景上勾出气泡轮廓；浅色背景上只是一层很淡的灰，不刺眼
    static let border = NSColor.white.withAlphaComponent(0.28)
    static let glyph = NSColor(srgbRed: 0.875, green: 0.882, blue: 0.898, alpha: 1)      // #DFE1E5
}

/// 单行文本精确居中绘制（NSTextField 的 alignment 对单行文本垂直居中不可靠）
final class GlyphView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }
    var textColor: NSColor = .white {
        didSet { needsDisplay = true }
    }
    var font: NSFont = .systemFont(ofSize: 20, weight: .medium) {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()

        let origin = NSPoint(x: (bounds.width - size.width) / 2,
                             y: (bounds.height - size.height) / 2)
        attributed.draw(at: origin)
    }
}

/// 无边框、不抢焦点、可浮在全屏应用之上的小提示窗
final class HUDWindow: NSPanel {
    static let contentSize = NSSize(width: 36, height: 36)

    private let containerView = NSView()
    private let effectView = NSVisualEffectView()
    private let glyphView = GlyphView()

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        setupContent()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(state: InputSourceState) {
        glyphView.text = state.glyph
        glyphView.textColor = IDEATheme.glyph
    }

    /// 调试用：把当前外观渲染成 PNG
    func snapshot(to path: String) {
        guard let view = contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    // step1 圆角裁剪容器 + 1px 描边
    // step2 毛玻璃材质（系统 HUD 风格，模糊背后内容）
    // step3 主字符（中 / En）
    private func setupContent() {
        containerView.frame = NSRect(origin: .zero, size: Self.contentSize)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 5
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = IDEATheme.border.cgColor
        containerView.autoresizingMask = [.width, .height]
        contentView = containerView

        effectView.frame = containerView.bounds
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        containerView.addSubview(effectView)

        glyphView.frame = containerView.bounds
        glyphView.font = .systemFont(ofSize: 20, weight: .medium)
        glyphView.textColor = IDEATheme.glyph
        glyphView.autoresizingMask = [.width, .height]
        containerView.addSubview(glyphView)
    }
}
