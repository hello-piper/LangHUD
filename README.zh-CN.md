# LangHUD

[English](README.md) | 中文

macOS 菜单栏小工具：切换应用、窗口或输入法时，在文本插入点旁弹一个「中 / En」，1 秒后淡出。

只做一件事——让你在敲字之前知道现在是中文还是英文。

## 触发时机与位置

| 场景 | 是否提示 | 位置 |
| --- | --- | --- |
| 切换应用 | 提示（先恢复该应用上次的输入法） | 插入点，取不到用鼠标 |
| 切换窗口 | 提示 | 插入点，取不到用鼠标 |
| 切换输入法 / 中英文 | 提示 | 插入点，取不到用鼠标 |
| 同一窗口内输入框之间切换 | 不提示 | - |
| 焦点离开输入框（点窗口其他位置） | 不提示 | - |
| 打字导致插入点移动 | 不提示 | - |

同一窗口只弹一次：切到某个窗口时提示一次，之后在该窗口内不再重复；切走再切回（或切到别的窗口）才再次提示。切输入法不受此限制，每次都提示。

弹窗落点：

1. 能拿到插入点矩形：贴在插入点右下方，右侧/下方空间不足时翻转到左侧/上方，最后夹进屏幕可视区。
2. 拿不到插入点（非文本焦点、AX 信息不足、矩形异常）：贴在鼠标右下方。

## 安装

### DMG（推荐）

1. 双击 `LangHUD-2.0.dmg`，把 App 拖进「应用程序」（**必须拖进去**，不要在挂载的卷里直接运行）
2. 首次启动会请求辅助功能权限
3. 系统设置 → 隐私与安全性 → 辅助功能 → 勾选 LangHUD

未做 Apple 公证，首次打开可能提示「无法验证开发者」：右键 → 打开。若仍被拦截：

```bash
sudo xattr -dr com.apple.quarantine /Applications/LangHUD.app
```

DMG 不配置开机自启，需要的话在「系统设置 → 通用 → 登录项」里手动添加。

### 从源码

```bash
git clone https://github.com/hello-piper/LangHUD.git
cd LangHUD
./install.sh
```

安装到 `~/Applications`，并写入 `~/Library/LaunchAgents/com.langhud.mac.plist` 实现登录自启。卸载：`./uninstall.sh`。

只编译不安装：`./build.sh`，产物在 `build/LangHUD.app`。

## 权限

需要「辅助功能」（Accessibility），用途只有一个：通过 AX API 读取当前焦点元素类型与插入点矩形，用来判断该不该提示、提示放哪。

授权后不需要重启，程序每 3 秒轮询一次授权状态，检测到就自动挂上观察者。

## 隐私

- 不上传任何数据，不发起网络请求
- 不读取、不记录输入内容，只在需要定位时读插入点矩形
- 本地仅保存开关状态、以及「应用 bundle id → 输入法 id」映射（UserDefaults）
- 调试日志默认关闭，开启后写到 `$TMPDIR/LangHUD-debug.log`

## 菜单栏

- 图标实时显示「中 / En」，未授权时显示 ⚠
- 唯一开关：按应用记忆输入法（提示时机固定，不提供开关）
- 「辅助功能权限…」跳转系统设置

## 按应用记忆输入法

每个应用单独记住自己的输入法，切应用时先切输入法、再弹提示。IDEA 用英文、Chrome 用中文，来回切会自动跟着变。

- 记录时机：你在某个应用里切换输入法时，记到该应用名下
- 首次遇到某个应用：把当时的输入法记为初始状态，之后按记录恢复
- 程序自己触发的切换不会反过来覆盖记录

## 构建与打包

```bash
./build.sh          # arm64，开发构建，产物 build/LangHUD.app
./install.sh        # 编译 + 安装到 ~/Applications + 配置登录自启
./package.sh        # pkg，装到 /Applications，写入全局 LaunchAgent
./package-dmg.sh    # dmg（universal），拖拽式安装
```

| 脚本 | 产物 | 架构 |
| --- | --- | --- |
| `package.sh` | `dist/LangHUD-<版本>.pkg` | arm64 |
| `package-dmg.sh` | `dist/LangHUD-<版本>.dmg` | universal（arm64 + x86_64） |

两个分发包都用 ad-hoc 签名——没有 Apple 开发者证书，所以有 Gatekeeper 提示。

## 调试

**日志**（不重编译即可开关）：

```bash
defaults write com.langhud.mac debugLog -bool YES   # 开启
defaults write com.langhud.mac debugLog -bool NO    # 关闭
# 改完重启 App 生效，日志在 $TMPDIR/LangHUD-debug.log
```

也可以用环境变量 `HUD_DEBUG=1` 启动。

**调试预览**（跳过 AX）：

| 变量 | 作用 |
| --- | --- |
| `HUD_DEMO=zh\|en` | 不挂 AX，直接弹一次提示 |
| `HUD_DEMO_SNAPSHOT=/path.png` | 配合 DEMO，把提示窗渲染成 PNG |
| `HUD_DEMO_HOLD=1` | 提示窗保持不消失，便于截图 |
| `HUD_SKIP_TRUST_PROMPT=1` | 跳过首次授权弹框 |

## 插入点是怎么定位的

系统自带的输入法指示器能永远贴住光标，是因为它在输入法管线里，能拿到 `NSTextInputClient.firstRectForCharacterRange` 的回调。普通 App 没有这条通道，只能通过 AX 反查，质量取决于对方实现。

取值按三级降级，成功的策略按 bundleID 缓存：

1. **相邻字符边界**（最准）
   取插入点后一个字符的矩形，用它的 `minX` 当光标 x；行尾（后一个字符是换行符）退到前一个字符的 `maxX`。比「按字符数比例切整行」准得多，多行、换行、全角都不跑偏。
2. **文本标记**（Chromium / WebKit）
   `AXTextMarkerRangeForRange` 把 `CFRange` 换成标记范围，再 `AXBoundsForTextMarkerRange` 取矩形。Electron 上比 `AXBoundsForRange` 可靠。
3. **整行 + 比例 / 元素位置估算**（兜底）
   拿不到字符级矩形时按字符位置比例切整行，最后退到输入框左上角。

矩形拿到后还要过一道校验：宽高必须像光标（≤120），且与某块屏幕的可视区相交，否则视为无效，直接退回鼠标位置。

## 已知限制

| 场景 | 表现 | 原因 |
| --- | --- | --- |
| IDEA / Swing | 只能估算或贴鼠标 | 默认不开 AX 树，需在 IDEA 里开启 Settings → Appearance & Behavior → System Settings → Support screen readers |
| 终端（Terminal / iTerm） | 只能估算 | 光标是字符格子，AX 没有文本插入点概念 |
| 密码框 | 走鼠标兜底 | secure input 下 AX 拒绝返回插入点 |
| 内置拼音按 Shift 切中英 | 检测不到 | 输入源 ID 不变，系统不发切换通知；Ctrl+Space 切输入法、切到 ABC 可正常检测 |
| 无输入框的窗口 | 贴鼠标 | 设计如此，先知道当前中英状态比知道位置重要 |

## 维护者笔记

排查「不弹 / 位置不对」时先看这几条，能省掉大半时间：

1. **先确认实例只有一个**。dmg 挂载副本 + `/Applications` 副本会各弹一个，视觉上就是两个方块叠在一起。
2. **从只读卷运行会假死**。双击 dmg 里的 App 能用，但卸载卷后进程消失，表现就是「装完没效果」。
3. **ad-hoc 签名每次重编 cdhash 都变**，已授予的辅助功能权限随之失效，必须在系统设置里删掉旧条目重新添加。这是反复「没效果」的最常见原因。
4. **`AXIsProcessTrusted()` 不能当唯一判据**。它可能返回 false，但部分 AX 属性仍能读——表现为「有的 App 能定位，有的不能」，别急着怀疑定位逻辑。
5. **Chromium 只认 `AXEnhancedUserInterface`**，`AXManualAccessibility` 是 Electron 的开关。两个都设，别只设一个。
6. **`AXBoundsForRange` 常返回整行**而不是光标矩形，直接拿 `maxX` 会偏到行尾。要么取相邻字符，要么显式判断宽度。
7. **Safari 起始页的 `AXWebArea` 也带 `AXSelectedTextRange`**，会被误判成输入框，然后从页面里取到 `(0, 350)` 这类矩形，把提示钉在屏幕左边。必须先按 role 黑名单排除容器角色。
8. **降级结果不要写进策略缓存**。AX 树首次未就绪是暂时的，把「估算」缓存下来会让这个 App 永远只剩估算。
9. **同一窗口的焦点变化通知没必要监听**。每次点击、每次输入都会唤醒一次，而按现在规则本来就不弹，纯浪费。
10. **「跟随鼠标」这类覆盖性开关会掩盖真正的定位 bug**。开关一开，插入点取到了也不用，排查时先确认没有被短路。

## 项目结构

```
Sources/
  main.swift                入口（无 Dock 图标）
  AppDelegate.swift         事件串联：应用切换、输入法切换、HUD 出口
  InputSource.swift         当前输入法读取与中英判定
  InputSourceMemory.swift   按应用记忆输入法
  AXContext.swift           焦点元素判定 / 插入点矩形 / 窗口标识
  FocusMonitor.swift        AX 观察者（窗口级）
  TriggerCoordinator.swift  事件合并 + 触发调度
  HUDWindow.swift           提示窗外观（IDEA Dark 配色）
  HUDController.swift       淡入淡出节奏 + 定位
  ScreenLocator.swift       屏幕定位
  StatusBarController.swift 菜单栏
  Settings.swift            UserDefaults 配置项
  DebugLog.swift            调试日志
```

## License

MIT
