import Foundation

/// Turns an anticipatory-window EEG slice into a lateralization sample.
///
/// **PLUG-IN (design A7):** replace `decode` body with:
/// 1. Band-pass ~0.5–40 Hz on PO7/PO8 (preserve raw elsewhere)
/// 2. Welch power 8–13 Hz
/// 3. lateralization = (P_PO8 − P_PO7) / (P_PO8 + P_PO7 + eps)
/// Do not invent tuned DSP here — mock path uses band energy proxies only.
protocol ModulationDecoder {
    func decode(window: EEGWindow) -> LateralizationSample
}

struct StubModulationDecoder: ModulationDecoder {
    private let po7 = 5
    private let po8 = 7

    func decode(window: EEGWindow) -> LateralizationSample {
        // Stub: RMS energy as a stand-in for alpha power — NOT a real Welch estimate.
        let a7 = rms(window.samples[safe: po7] ?? [])
        let a8 = rms(window.samples[safe: po8] ?? [])
        let eps = 1e-6
        let lat = (a8 - a7) / (a8 + a7 + eps)
        let ok = (window.samples[safe: po7]?.count ?? 0) > 10
        return LateralizationSample(alphaPO7: a7, alphaPO8: a8, lateralization: lat, qualityOK: ok)
    }

    private func rms(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let m = xs.reduce(0, +) / Double(xs.count)
        let v = xs.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)
        return sqrt(v)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
