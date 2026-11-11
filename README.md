# LangHUD

English | [中文](README.zh-CN.md)

A macOS menu bar utility that pops a "中 / En" badge next to the text caret when you switch apps, windows, or input sources — fading out after 1 second.

It does one thing: shows you whether you're about to type Chinese or English.

## When it shows and where

| Scenario | Shows? | Position |
| --- | --- | --- |
| Switch app | Yes (restores that app's last input source first) | caret, or mouse if unavailable |
| Switch window | Yes | caret, or mouse if unavailable |
| Switch input source / Chinese-English | Yes | caret, or mouse if unavailable |
| Move between text fields in the same window | No | - |
| Focus leaves a text field | No | - |
| Typing moves the caret | No | - |

It shows once per window: switching to a window triggers one badge, then stays silent within that window; only switching away and back (or to another window) triggers again. Input source switching is exempt — it always shows.

Badge placement:

1. Caret available: placed at the caret's bottom-right; flips to the left/top when there's no room, then clamped into the visible screen area.
2. Caret unavailable (non-text focus, insufficient AX info, invalid rect): placed at the mouse's bottom-right.

## Install

### DMG (recommended)

1. Open `LangHUD-2.0.dmg` and drag the app into **Applications** (drag it in — don't run it from the mounted volume)
2. On first launch it asks for Accessibility permission
3. System Settings → Privacy & Security → Accessibility → enable LangHUD

Not notarized by Apple; the first open may warn "cannot verify the developer": right-click → Open. If still blocked:

```bash
sudo xattr -dr com.apple.quarantine /Applications/LangHUD.app
```

The DMG does not set up launch-at-login; add it manually in System Settings → General → Login Items if you want it.

### From source

```bash
git clone https://github.com/hello-piper/LangHUD.git
cd LangHUD
./install.sh
```

Installs to `~/Applications` and writes `~/Library/LaunchAgents/com.langhud.mac.plist` for launch-at-login. Uninstall with `./uninstall.sh`.

Build without installing: `./build.sh`, output at `build/LangHUD.app`.

## Permissions

It needs Accessibility for exactly one reason: reading the focused element type and caret rectangle via the AX API, to decide whether to show the badge and where to place it.

No restart needed after granting — it polls the trust status every 3 seconds and attaches the observer automatically once granted.

## Privacy

- Uploads nothing, makes no network requests
- Never reads or records typed content — only the caret rectangle, when positioning is needed
- Stores only toggle state and an "app bundle id → input source id" map locally (UserDefaults)
- Debug logging is off by default; when enabled it writes to `$TMPDIR/LangHUD-debug.log`

## Menu bar

- Icon shows "中 / En" live; shows ⚠ when not authorized
- Single toggle: remember input source per app (triggering is fixed, no switch)
- "Accessibility permission…" jumps to System Settings

## Per-app input source memory

Each app remembers its own input source; switching apps first switches the input source, then shows the badge. IDEA in English, Chrome in Chinese — toggling between them follows automatically.

- Records when you switch the input source inside an app, under that app's name
- First time an app is seen: its current input source becomes the initial state, restored thereafter
- Switches triggered by the program itself don't overwrite the record

## Build & package

```bash
./build.sh          # arm64 dev build, output build/LangHUD.app
./install.sh        # build + install to ~/Applications + launch-at-login
./package.sh        # pkg, installs to /Applications, writes a global LaunchAgent
./package-dmg.sh    # dmg (universal), drag-to-install
```

| Script | Output | Architecture |
| --- | --- | --- |
| `package.sh` | `dist/LangHUD-<version>.pkg` | arm64 |
| `package-dmg.sh` | `dist/LangHUD-<version>.dmg` | universal (arm64 + x86_64) |

Both packages are ad-hoc signed — no Apple Developer certificate, hence the Gatekeeper prompt.

## Debugging

**Logging** (toggle without rebuilding):

```bash
defaults write com.langhud.mac debugLog -bool YES   # on
defaults write com.langhud.mac debugLog -bool NO    # off
# restart the app for it to take effect; log at $TMPDIR/LangHUD-debug.log
```

You can also launch with `HUD_DEBUG=1`.

**Debug preview** (skips AX):

| Variable | Purpose |
| --- | --- |
| `HUD_DEMO=zh\|en` | skip AX, show the badge once |
| `HUD_DEMO_SNAPSHOT=/path.png` | with DEMO, render the badge to PNG |
| `HUD_DEMO_HOLD=1` | keep the badge visible for screenshotting |
| `HUD_SKIP_TRUST_PROMPT=1` | skip the first-launch permission prompt |

## How caret positioning works

The system's own input source indicator always hugs the cursor because it sits inside the input method pipeline and gets `NSTextInputClient.firstRectForCharacterRange` callbacks. A normal app has no such channel and must query AX instead, whose quality depends on the target app's implementation.

Three-tier fallback, with the successful strategy cached per bundle ID:

1. **Adjacent character boundary** (most accurate)
   Take the rectangle of the character after the caret and use its `minX` as the caret x; at end-of-line (next char is a newline) fall back to the previous character's `maxX`. Far more accurate than "scale the whole line by character ratio" — correct across line wraps, CJK full-width chars.
2. **Text markers** (Chromium / WebKit)
   `AXTextMarkerRangeForRange` converts a `CFRange` into a marker range, then `AXBoundsForTextMarkerRange` returns the rect. More reliable than `AXBoundsForRange` on Electron.
3. **Line ratio / element estimate** (last resort)
   When no character-level rect is available, scale the whole line by character position, then fall back to the text field's top-left.

The rect is then validated: width/height must look like a caret (≤120) and intersect some screen's visible frame, otherwise it's discarded and the badge falls back to the mouse position.

## Known limitations

| Scenario | Behavior | Reason |
| --- | --- | --- |
| IDEA / Swing | estimate or mouse only | AX tree off by default; enable Settings → Appearance & Behavior → System Settings → Support screen readers |
| Terminal / iTerm | estimate only | cursor is a character cell, no text-insertion-point concept in AX |
| Password fields | mouse fallback | AX refuses to return the caret under secure input |
| Built-in Pinyin Shift toggling Chinese-English | undetectable | input source ID unchanged, system sends no notification; Ctrl+Space or switching to ABC works |
| Windows with no text field | mouse position | by design — knowing the current state matters more than the position |

## Maintainer notes

Check these first when debugging "doesn't show / wrong position" — saves most of the time:

1. **Make sure there's only one instance.** A mounted DMG copy + the `/Applications` copy each show a badge — looks like two overlapping blocks.
2. **Running from a read-only volume looks dead.** Double-clicking the app inside a DMG works, but the process dies when the volume unmounts — "installed but no effect".
3. **ad-hoc signing changes the cdhash on every rebuild**, which invalidates the granted Accessibility permission — you must remove and re-add the entry in System Settings. The most common cause of recurring "no effect".
4. **`AXIsProcessTrusted()` is not a reliable single source of truth.** It can return false while some AX attributes are still readable — "some apps position, some don't". Don't immediately blame the positioning logic.
5. **Chromium only honors `AXEnhancedUserInterface`**; `AXManualAccessibility` is Electron's switch. Set both.
6. **`AXBoundsForRange` often returns the whole line**, not the caret rect — taking `maxX` directly lands you at the end of the line. Use adjacent characters or explicitly check the width.
7. **Safari's start page `AXWebArea` also carries `AXSelectedTextRange`**, gets misjudged as a text field, and yields rects like `(0, 350)` that pin the badge to the left edge. Exclude container roles via a blacklist first.
8. **Don't cache fallback results.** The AX tree being unready is transient; caching "estimate" would permanently degrade that app.
9. **Same-window focus-change notifications aren't worth observing.** Every click and keystroke wakes you, and by current rules it wouldn't show anyway.
10. **Override switches like "follow mouse" mask real positioning bugs.** When enabled, the caret is fetched but ignored. Confirm nothing is short-circuited first.

## Project structure

```
Sources/
  main.swift                entry (no Dock icon)
  AppDelegate.swift         wires app switch, input source switch, HUD output
  InputSource.swift         current input source read + Chinese-English detection
  InputSourceMemory.swift   per-app input source memory
  AXContext.swift           focused element / caret rect / window identity
  FocusMonitor.swift        AX observer (window level)
  TriggerCoordinator.swift  event merge + trigger scheduling
  HUDWindow.swift           badge appearance (IDEA Dark palette)
  HUDController.swift       fade timing + placement
  ScreenLocator.swift       screen lookup
  StatusBarController.swift menu bar
  Settings.swift            UserDefaults keys
  DebugLog.swift            debug logging
```

## License

MIT
