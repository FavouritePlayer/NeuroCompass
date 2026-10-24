# ScreenShade

Native macOS menu-bar utility that draws a **click-through, full-screen overlay** with a **shared nonuniform gradient** controlling dimming and optional image metrics (contrast, saturation, sharpness, warmth).

> Overlay dimming cannot make pixels brighter than the panel’s native output. “Bright side” means the start of the shared gradient (usually less processed / less dimmed).

## Features

- Full-screen overlay on **all displays**, click-through, hidden from Dock / Cmd-Tab (`LSUIElement`)
- **One shared gradient geometry** drives every metric:
  - Angle / direction
  - Split / center
  - Transition falloff: **Hard / Short / Long / Custom** (+ continuous width)
  - Invert (swap sides)
- **Dimming** via cheap `CAGradientLayer` (no Screen Recording permission)
- **Metric channels** (Screen Recording + Core Image):
  | Metric | Range | Notes |
  |---|---|---|
  | Contrast | −1…1 per side | `CIColorControls` |
  | Saturation | −1…1 per side | `CIColorControls` |
  | Sharpness | −1…1 per side | Unsharp mask (+) / Gaussian blur (−) |
  | Warmth | −1…1 per side | `CITemperatureAndTint` (bonus) |
- Each metric: **enable** + **start (bright side)** + **end (dim side)** amounts
- Live settings panel + menu-bar presets; persists to `config.json`

### Geometry model

All enabled metrics share the **same** angle, center, transition mode/width, and invert. Per-metric splits are not exposed (keeps the UI coherent). Dual filtered frames are blended with a mask built from that shared gradient.

## Requirements

- macOS 13+
- Command Line Tools **or** Xcode (`swiftc` build path supported)
- **Screen Recording** permission only when contrast / saturation / sharpness / warmth are enabled  
  (System Settings → Privacy & Security → Screen Recording → ScreenShade)

## Build

```bash
cd ScreenShade
chmod +x Scripts/build.sh
./Scripts/build.sh
```

Output: `build/ScreenShade.app`

## Run

```bash
open build/ScreenShade.app
```

1. Menu-bar icon appears; settings panel opens
2. Adjust shared gradient (angle, split, Hard/Short/Long/Custom)
3. Enable metric channels as needed (macOS will prompt for Screen Recording the first time)
4. Use **Demo metrics** for a ready-made left→right contrast / sat / sharp / warmth ramp

Quit: menu bar → **Quit ScreenShade**.

### Offline metric demos (no permission)

```bash
screencapture /tmp/src.png
swift Scripts/render-metric-demos.swift /tmp/src.png ./demo-out
```

## Config

`~/Library/Application Support/ScreenShade/config.json`

```json
{
  "enabled": true,
  "angleDegrees": 0,
  "center": 0.5,
  "brightOpacity": 0,
  "dimOpacity": 0.55,
  "transitionMode": "short",
  "transitionWidth": 0.12,
  "inverted": false,
  "contrast":   { "enabled": true,  "start": 0.0,  "end": 0.55 },
  "saturation": { "enabled": true,  "start": 0.15, "end": -0.55 },
  "sharpness":  { "enabled": true,  "start": 0.35, "end": -0.35 },
  "warmth":     { "enabled": false, "start": 0.0,  "end": 0.25 }
}
```

`transitionMode`: `"hard"` | `"short"` | `"long"` | `"custom"`.  
Reload via menu bar → **Reload config.json**.

## Project layout

```text
ScreenShade/
  Sources/ScreenShade/   AppKit + ScreenCaptureKit + Core Image
  Resources/Info.plist
  Scripts/build.sh
  Scripts/render-metric-demos.swift
  config/config.json
  README.md
```

## Notes

- Dimming-only path needs no capture permission.
- Advanced metrics capture the display (excluding the overlay), filter start/end variants, and blend with the shared mask (~12 fps).
- If Screen Recording is denied, metric toggles turn off and dimming continues to work.
