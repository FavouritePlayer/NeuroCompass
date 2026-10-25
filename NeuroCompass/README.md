# NeuroCompass

EEG-driven adaptive cue MVP — **same Mac AppKit UI**, calibrated parameter is **HRTF sound angle** (not left-contrast darkness).

## Primary story

Grid `trySetting` over HRTF azimuths `{no-sound, −30°, −45°, −60°}`.  
Mock EEG peaks at **−45°** so Quick Demo locks a sensible angle. Darkness veil is disabled in this flow.

## Run

```bash
./Scripts/build.sh
open build/NeuroCompass.app
```

Headphones recommended for spatial cues (`AVAudioEnvironmentNode` HRTF — not L/R volume pan).

| Button | What |
|---|---|
| Preview cue at −45° | Plays HRTF cue at mock optimum |
| Quick Demo Grid (3/setting) | Fast mock calibration → results + lock (~−45°) |
| Start Grid Calibration | 4 trials/setting over angle grid |
| Run Neutral / No-Sound Block | Silent baseline |
| Run Held-out Block | Separate locked + no-sound comparison |

Keys: **f/←** left, **j/→** right. CSV: `~/Library/Application Support/NeuroCompass/sessions/`

## Mock EEG rule

Deterministic peak at **−45°**:

`gain = exp(-((angleDeg - (-45)) / 18)^2)` for sound angles; **no-sound** (`0`) → gain `0`.

Always labeled `eeg_source=mock`. Never reports live.

## Ready for EEG hookup

Fill these only — do not invent DSP elsewhere:

1. `Sources/NeuroCompass/Decoder/ModulationDecoder.swift` — Welch PO7/PO8 (A7)
2. `Sources/NeuroCompass/EEG/BrainFlowEEGStub.swift` — Unicorn/BrainFlow (Windows)
3. `Sources/NeuroCompass/EEG/EEGSource.swift` — protocol already stable
4. `UI/MainWindowController.init` — construct live source only when connected

## Architecture

- `SpatialAudioEngine` — HRTF via `AVAudioEnvironmentNode`
- `TrialEngine` — A4 protocol (cue L/R, anticipatory window, targets, catch trials)
- `CalibrationLoop.trySetting(angle)` → play HRTF + block + `ModulationResult`
- `ExperimentCanvas` — stage chrome; sound angle badge (veil unused)
