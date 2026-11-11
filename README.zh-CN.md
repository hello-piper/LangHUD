# LangHUD

[English](README.md) | 中文

macOS 菜单栏小工具：切换应用、窗口或输入法时，在文本插入点旁弹一个「中 / En」。

## 功能

- 切应用 / 窗口 / 输入法时，在光标旁提示「中」或「En」1 秒
- 菜单栏图标实时显示当前状态
- 可选：按应用记忆输入法

## 触发时机

| 场景 | 是否提示 |
| --- | --- |
| 切换应用 / 窗口 | 提示 |
| 切换输入法（中英文） | 提示 |
| 同一窗口内切换输入框 | 不提示 |
| 打字导致光标移动 | 不提示 |

## 安装

### DMG

从 [Releases](https://github.com/hello-piper/LangHUD/releases) 下载最新版，拖入「应用程序」，再到系统设置 → 隐私与安全性 → 辅助功能 里授权。

> 未公证——首次打开右键 → 打开，或：
> `sudo xattr -dr com.apple.quarantine /Applications/LangHUD.app`

### 从源码

```bash
git clone https://github.com/hello-piper/LangHUD.git
cd LangHUD
./install.sh
```

## 权限与隐私

- 需要辅助功能权限，用于读取光标位置
- 不联网，不读取、不记录输入内容

## 构建

```bash
./build.sh          # arm64 开发构建
./package-dmg.sh    # universal dmg
./package.sh        # arm64 pkg
```

## 已知限制

- IDEA 需开启「Support screen readers」才能贴光标
- 终端 / 密码框回退到鼠标位置
- 内置拼音 Shift 切中英检测不到（输入源 ID 不变）

## License

[Apache-2.0](LICENSE)
