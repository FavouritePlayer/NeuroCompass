# NeuroCompass

EEG-driven left-contrast adaptive display (Neurotech @ Berkeley hackathon) **plus** the ScreenShade full-screen overlay utility.

| App | Role |
|---|---|
| **[NeuroCompass](NeuroCompass/)** | Timed cued-attention experiment + mock EEG + grid calibration. **In-app** left contrast shade. |
| **ScreenShade** | Optional click-through desktop overlay (metrics + `loop.json` IPC). |

macOS 13+ · Swift / AppKit · Command Line Tools or Xcode (`swiftc` build scripts included).

## Quick start (hackathon demo)

```bash
git clone https://github.com/FavouritePlayer/NeuroCompass.git
cd NeuroCompass

# Experiment app (primary)
./NeuroCompass/Scripts/build.sh
open NeuroCompass/build/NeuroCompass.app

# Optional desktop overlay
./Scripts/build.sh
open build/ScreenShade.app
```

In NeuroCompass:

1. Confirm **EEG source: mock**
2. **Preview Left-Degraded Shade** — left hemifield veiled, right untouched
3. **Quick Demo Grid (2/setting)** — calibrates multipliers `[0.85, 1.00, 1.15, 1.30]`, locks ~×1.15 (mock peak)
4. **Run Held-out Block** — separate from calibration
5. Optional: **Apply Locked → ScreenShade** writes `~/Library/Application Support/ScreenShade/loop.json`

Keys during response: **f / ←** = left, **j / →** = right.  
CSV: `~/Library/Application Support/NeuroCompass/sessions/`

## NeuroCompass (primary)

In-app left contrast is driven by `CalibrationLoop.trySetting`. ScreenShade is **not** required to run the loop.

- Trial protocol ≈ design A4 (fixation → cue → anticipatory → target/catch → response)
- Mock EEG always labeled `eeg_source=mock` (deterministic peak at **×1.15**)
- Decoder + BrainFlow are **stubs** — see [NeuroCompass/README.md](NeuroCompass/README.md) for EEG hookup points

```bash
./NeuroCompass/Scripts/build.sh
open NeuroCompass/build/NeuroCompass.app
```

## ScreenShade (optional overlay)

Full-screen click-through shade with shared gradient geometry and metric channels (dim / contrast / saturation / sharpness / warmth).

```bash
./Scripts/build.sh
open build/ScreenShade.app
```

NeuroCompass can optionally drive left contrast via:

```text
~/Library/Application Support/ScreenShade/loop.json
```

```json
{ "leftContrastMultiplier": 1.15, "enabled": true }
```

Manual controls: menu-bar icon → Settings. Screen Recording permission only needed for contrast/sat/sharp/warmth capture path; dimming alone does not.

## Layout

```text
.
├── NeuroCompass/          # Experiment app
│   ├── Scripts/build.sh
│   ├── Sources/NeuroCompass/
│   └── README.md
├── Sources/ScreenShade/   # Overlay app
├── Scripts/build.sh
├── config/config.json
└── README.md
```

## Notes

- Overlay dimming cannot brighten beyond native panel output.
- No secrets or credentials belong in this repo.
- Pre-EEG checklist and design docs may live in the hackathon project store; code hookup points are in `NeuroCompass/README.md`.
