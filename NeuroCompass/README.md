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

## Participant task

Watch the fixation cross. A short HRTF chirp may play. When a **dot** flashes left or right, press **F** (left) or **J** (right). Catch trials (~18%): no dot — don’t press. No attention arrow.

CSV: `~/Library/Application Support/NeuroCompass/sessions/`

## Mock EEG rule

Deterministic peak at **−45°**:

`gain = exp(-((angleDeg - (-45)) / 18)^2)` for sound angles; **no-sound** (`0`) → gain `0`.

L/R laterality swing follows **dot side** (logged as `cue_side`) — not a visible arrow.

Always labeled `eeg_source=mock`. Never reports live.

## Ready for EEG hookup

Fill these only — do not invent DSP elsewhere:

1. `Sources/NeuroCompass/Decoder/ModulationDecoder.swift` — Welch PO7/PO8 (A7)
2. `Sources/NeuroCompass/EEG/BrainFlowEEGStub.swift` — Unicorn/BrainFlow (Windows)
3. `Sources/NeuroCompass/EEG/EEGSource.swift` — protocol already stable
4. `UI/MainWindowController.init` — construct live source only when connected

## Architecture

- `SpatialAudioEngine` — HRTF chirp via `AVAudioEnvironmentNode`
- `TrialEngine` — fixation → optional chirp → delay → L/R dot → F/J
- `CalibrationLoop.trySetting(angle)` → block + `ModulationResult`
- `ExperimentCanvas` — cross + dot; instruction banner; veil unused
