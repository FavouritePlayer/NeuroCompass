import AVFoundation
import Foundation

/// HRTF spatialized cue via `AVAudioEnvironmentNode` (not L/R volume panning).
final class SpatialAudioEngine {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
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
        buffer = Self.makeToneBuffer(format: format, frequency: 440, seconds: 0.5)
        try engine.start()
        started = true
    }

    /// Azimuth degrees: 0 = front, negative = left. Nil / call `stop` = silence.
    func play(azimuthDegrees: Double, distance: Float = 1.2) {
        do { try prepare() } catch { return }
        guard let buffer else { return }
        let rad = Float(azimuthDegrees) * .pi / 180
        // AVAudio3D: +X right, −Z front → negative azimuth → left (−X).
        player.position = AVAudio3DPoint(x: distance * sin(rad), y: 0, z: -distance * cos(rad))
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
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
