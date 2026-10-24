# NeuroCompass

EEG-driven adaptive display MVP (Neurotech @ Berkeley Hackathon). Owns the **timed cued-attention task**; drives **ScreenShade** as the full-screen left-contrast output surface.

## Architecture

| Piece | Role |
|---|---|
| **NeuroCompass.app** | Experiment window + operator/results/physiology panels. Timing-critical stimuli live only here. |
| **ScreenShade.app** | Full-screen overlay. Loop writes left-contrast via IPC; ScreenShade does not run the task. |
| **Calibration loop** | `trySetting(multiplier) → ModulationResult` over grid `[0.85, 1.00, 1.15, 1.30]`. |
| **Decoder** | `StubModulationDecoder` — RMS proxy only. Real Welch/PO7/PO8 plugs in at A7 (see comments). |
| **EEG** | **Mock** stream by default on Mac (always labeled). `BrainFlowEEGStub` for future Windows live. |

### IPC (how the loop drives ScreenShade)

NeuroCompass writes:

```text
~/Library/Application Support/ScreenShade/loop.json
```

```json
{
  "leftContrastMultiplier": 1.15,
  "enabled": true,
  "updatedAt": "…"
}
```

ScreenShade’s `LoopCommandWatcher` polls every 0.25s and maps the multiplier onto the **left-side contrast** channel (angle 0°, start=left). Other ScreenShade metrics are unused by the loop. Left dimming is also applied when `m < 1` so degraded settings are visible without Screen Recording.

## Build

```bash
# From repo root (ScreenShade)
./Scripts/build.sh
./NeuroCompass/Scripts/build.sh
```

## Demo run (mock EEG)

1. Start overlay: `open build/ScreenShade.app`
2. Start task: `open NeuroCompass/build/NeuroCompass.app`
3. Confirm sidebar shows **EEG source: mock**
4. Click **Start Grid Calibration** — loop steps multipliers, updates `loop.json`, ScreenShade follows
5. Results panel lists modulation per setting + locked value (uncertain → defaults to 1.00)
6. CSV + session meta under `~/Library/Application Support/NeuroCompass/sessions/`

Keys during response window: **f / ←** = left, **j / →** = right.

## Objective

Maximize **modulation** = mean(lat \| cue=left) − mean(lat \| cue=right) (leftward swing). Not equal alpha.

## Decoder plug-in (A7)

See `Sources/NeuroCompass/Decoder/ModulationDecoder.swift`. Replace stub with band-pass → Welch 8–13 Hz → `(P_PO8−P_PO7)/(P_PO8+P_PO7+eps)`.

## Optimizer hook

`CalibrationLoop.runStepBasedOptimizerPlaceholder` — future step search should only call `trySetting`.
