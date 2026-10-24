import Foundation

/// Stub for a future BrainFlow / Unicorn live path (Windows/Linux per design A7).
/// On Mac this never connects; source label stays honest if somehow selected.
final class BrainFlowEEGStub: EEGSource {
    let sourceKind: EEGSourceKind = .live
    private(set) var isConnected = false
    private(set) var qualityOK = false
    private(set) var sampleCount = 0
    private(set) var lastError: String = "BrainFlow/Unicorn live path not implemented on this build (Mac default is mock)."

    func start() {
        // PLUG-IN: BrainFlow board_id = 8 (Unicorn), 250 Hz, dongle serial.
        // Supported on Windows/Linux; BrainFlow does not list Unicorn for macOS.
        isConnected = false
        qualityOK = false
        lastError = "Live Unicorn acquisition requires Windows BrainFlow build — use mock on Mac."
    }

    func stop() {
        isConnected = false
    }

    func window(from start: TimeInterval, to end: TimeInterval) -> EEGWindow {
        EEGWindow(
            sampleRate: 250,
            startTime: start,
            endTime: end,
            samples: Array(repeating: [], count: 8),
            source: .live
        )
    }
}
