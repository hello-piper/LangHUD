# LangHUD

English | [中文](README.zh-CN.md)

A macOS menu bar utility that pops a "中 / En" badge next to the text caret when you switch apps, windows, or input sources.

## What it does

- Shows "中" or "En" at the text caret for 1 second when switching apps, windows, or input sources
- Menu bar icon shows the current state live
- Optional: remember input source per app

## When it shows

| Scenario | Shows? |
| --- | --- |
| Switch app / window | Yes |
| Switch input source (Chinese/English) | Yes |
| Move between fields in the same window | No |
| Typing moves the caret | No |

## Install

### DMG

Download the latest from [Releases](https://github.com/hello-piper/LangHUD/releases), drag the app into **Applications**, then grant Accessibility permission in System Settings → Privacy & Security → Accessibility.

> Not notarized — on first launch right-click → Open, or:
> `sudo xattr -dr com.apple.quarantine /Applications/LangHUD.app`

### From source

```bash
git clone https://github.com/hello-piper/LangHUD.git
cd LangHUD
./install.sh
```

## Permissions & privacy

- Needs Accessibility permission to read the caret position
- No network access; never reads or records your typing

## Build

```bash
./build.sh          # arm64 dev build
./package-dmg.sh    # universal dmg
./package.sh        # arm64 pkg
```

## Known limitations

- IntelliJ IDEA needs "Support screen readers" enabled for caret positioning
- Terminal and password fields fall back to the mouse position
- Built-in Pinyin Shift toggle is undetectable (the input source ID doesn't change)

## License

[Apache-2.0](LICENSE)
