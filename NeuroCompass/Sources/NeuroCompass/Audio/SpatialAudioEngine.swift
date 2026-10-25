import AVFoundation
import Foundation

/// HRTF spatialized cue via `AVAudioEnvironmentNode` (not L/R volume panning).
final class SpatialAudioEngine {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private var chirpBuffer: AVAudioPCMBuffer?
    private var started = false

    func prepare() throws {
        guard !started else { return }
        let main = engine.mainMixerNode
        engine.attach(environment)
        engine.attach(player)

        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        if #available(macOS 14.0, *) {
            environment.renderingAlgorithm = .HRTFHQ
        } else {
            environment.renderingAlgorithm = .HRTF
        }
        environment.reverbParameters.enable = false

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.connect(player, to: environment, format: format)
        engine.connect(environment, to: main, format: nil)
        chirpBuffer = Self.makeChirpBuffer(format: format, seconds: 0.18)
        try engine.start()
        started = true
    }

    /// Short HRTF chirp at azimuth degrees (0 = front, negative = left). Used once per trial.
    func playChirp(azimuthDegrees: Double, distance: Float = 1.2) {
        do { try prepare() } catch { return }
        guard let chirpBuffer else { return }
        place(azimuthDegrees: azimuthDegrees, distance: distance)
        player.stop()
        player.scheduleBuffer(chirpBuffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Longer preview tone (operator “Preview cue at −45°”).
    func play(azimuthDegrees: Double, distance: Float = 1.2) {
        do { try prepare() } catch { return }
        guard let format = chirpBuffer?.format else { return }
        place(azimuthDegrees: azimuthDegrees, distance: distance)
        guard let buf = Self.makeToneBuffer(format: format, frequency: 880, seconds: 0.45) else { return }
        player.stop()
        player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    func stop() {
        player.stop()
    }

    func shutdown() {
        player.stop()
        engine.stop()
        started = false
    }

    private func place(azimuthDegrees: Double, distance: Float) {
        let rad = Float(azimuthDegrees) * .pi / 180
        // AVAudio3D: +X right, −Z front → negative azimuth → left (−X).
        player.position = AVAudio3DPoint(x: distance * sin(rad), y: 0, z: -distance * cos(rad))
    }

    /// Brief rising chirp for per-trial spatial cue.
    private static func makeChirpBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(seconds * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        guard let ch = buf.floatChannelData?[0] else { return nil }
        let f0 = 600.0
        let f1 = 1200.0
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let frac = t / seconds
            let freq = f0 + (f1 - f0) * frac
            let env = min(1, t * 40) * min(1, (seconds - t) * 25)
            ch[i] = Float(sin(2 * Double.pi * freq * t) * 0.4 * env)
        }
        return buf
    }

    private static func makeToneBuffer(format: AVAudioFormat, frequency: Double, seconds: Double) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(seconds * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        guard let ch = buf.floatChannelData?[0] else { return nil }
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let env = min(1, t * 12) * min(1, (seconds - t) * 8)
            ch[i] = Float(sin(2 * Double.pi * frequency * t) * 0.35 * env)
        }
        return buf
    }
}
