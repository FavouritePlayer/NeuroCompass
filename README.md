# ScreenShade

Native macOS menu-bar utility that draws a **click-through, full-screen overlay** with a **nonuniform brightness gradient** (relative dimming). Bright and dim regions are adjustable live — direction, split position, strength, and transition falloff.

> Overlay dimming cannot make pixels brighter than the panel’s native output. “Bright” means *less dimmed*; “dim” means a stronger black alpha overlay.

## Features

- Full-screen overlay on **all displays**
- Click-through (`ignoresMouseEvents`) so other apps stay usable
- Stays above normal windows; **hidden from Dock / Cmd-Tab** (`LSUIElement`)
- Gradient axis by **angle** (horizontal, vertical, or arbitrary)
- **Split / center** position for the bright↔dim boundary
- **Bright opacity** and **dim opacity** (strength)
- **Transition / falloff modes** (first-class):
  | Mode | Behavior |
  |---|---|
  | **Hard** | Sharp cutoff (step edge) at the split |
  | **Short** | Narrow soft ramp |
  | **Long** | Wide soft ramp across much of the screen |
  | **Custom** | Continuous **transition width** between hard and long |
- Live settings panel + menu-bar presets
- Persists to `~/Library/Application Support/ScreenShade/config.json` (and `UserDefaults`)

## Requirements

- macOS 13+
- Apple Silicon or Intel Mac
- **Either** Xcode, **or** Command Line Tools (`xcode-select --install`) — this repo builds with `swiftc` without a full Xcode.app

## Build

```bash
cd ScreenShade
chmod +x Scripts/build.sh
./Scripts/build.sh
```

Output: `build/ScreenShade.app`

### Open / build in Xcode (optional)

If you have Xcode installed, you can also create a macOS App target and add the sources under `Sources/ScreenShade/` plus `Resources/Info.plist`, or:

```bash
# From an Xcode-generated project wrapping these sources:
xcodebuild -scheme ScreenShade -configuration Release
```

The included `Scripts/build.sh` path is the supported one on machines with only Command Line Tools.

## Run

```bash
open build/ScreenShade.app
```

On launch:

1. A menu-bar icon appears (half-filled circle)
2. The settings panel opens
3. The overlay covers the screen(s)

Use **Left bright** / **Right bright** presets, or adjust sliders — changes apply immediately.

Quit from the menu-bar menu → **Quit ScreenShade**.

## Settings

| Control | Meaning |
|---|---|
| Enable overlay | Show / hide shade |
| Invert | Swap bright and dim sides |
| Angle | Gradient direction (0° = left→right, 90° = top→bottom) |
| Split / center | Where the transition sits (0…1) |
| Bright opacity | Overlay alpha on the bright side (usually 0) |
| Dim opacity | Overlay alpha on the dim side (strength) |
| Transition mode | **Hard** / **Short** / **Long** / **Custom** |
| Transition width | Continuous step size (0 = hard, ~0.12 = short, ~0.75 = long) |

Choosing a named mode sets width to that preset. Dragging the width slider switches to **Custom** (or snaps back to a named mode when you land on a preset value).

### Config file / CLI without rebuilding

Edit:

```text
~/Library/Application Support/ScreenShade/config.json
```

Example:

```json
{
  "enabled": true,
  "angleDegrees": 0,
  "center": 0.5,
  "brightOpacity": 0,
  "dimOpacity": 0.6,
  "transitionMode": "hard",
  "transitionWidth": 0,
  "inverted": false
}
```

`transitionMode` values: `"hard"` | `"short"` | `"long"` | `"custom"`.

Then choose **Reload config.json** from the menu bar (or restart the app).

A sample file also lives at `config/config.json` in the repo.

## Project layout

```text
ScreenShade/
  Sources/ScreenShade/   Swift + AppKit sources
  Resources/Info.plist   LSUIElement overlay utility plist
  Scripts/build.sh       swiftc → .app bundle
  config/config.json     sample settings
  README.md
```

## Notes

- Implementation uses `CAGradientLayer` (Core Animation) for a solid, live-updating axial gradient. Full Xcode’s `metal` toolchain is not required.
- True panel brightening above native luminance is not possible with a software overlay; this app does relative nonuniform dimming.
