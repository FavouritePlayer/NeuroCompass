# NeuroCompass

EEG-driven adaptive display MVP — **pre-EEG spine complete**.

## Primary story

**In-app left contrast** in the experiment window, driven by grid `trySetting`.  
ScreenShade desktop overlay is **optional** (`Apply Locked → ScreenShade`).

## Run

```bash
./Scripts/build.sh
open build/NeuroCompass.app
```

| Button | What |
|---|---|
| Preview Left-Degraded Shade | Left veil ×0.85, right untouched |
| Quick Demo Grid (2/setting) | Fast mock calibration → filled results + lock |
| Start Grid Calibration | 4 trials/setting |
| Run Held-out Block | Separate locked + ×1.00 comparison |
| Apply Locked → ScreenShade | Optional desktop IPC |

Keys: **f/←** left, **j/→** right. CSV: `~/Library/Application Support/NeuroCompass/sessions/`

## Mock EEG rule

Deterministic peak at **×1.15**: `gain = exp(-((m - 1.15) / 0.22)^2)`.  
Always labeled `eeg_source=mock`. Never reports live.

## Ready for EEG hookup

Fill these only — do not invent DSP elsewhere:

1. `Sources/NeuroCompass/Decoder/ModulationDecoder.swift` — Welch PO7/PO8 (A7)
2. `Sources/NeuroCompass/EEG/BrainFlowEEGStub.swift` — Unicorn/BrainFlow (Windows)
3. `Sources/NeuroCompass/EEG/EEGSource.swift` — protocol already stable
4. `UI/MainWindowController.init` — construct live source only when connected

## Architecture

- `TrialEngine` — A4 protocol (~fixation 500–800, cue 200, anticipatory 1000–1500, target 120, response ≤1500, catch ~18%)
- `CalibrationLoop.trySetting` → in-app shade + block + `ModulationResult`
- `ExperimentCanvas` — left hemifield veil; right untouched
