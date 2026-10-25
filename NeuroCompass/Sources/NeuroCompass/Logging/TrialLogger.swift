import Foundation

final class TrialLogger {
    let sessionDirectory: URL
    let participantId: String
    private var records: [TrialRecord] = []
    private let metaURL: URL
    private let csvURL: URL

    init(participantId: String = "P001") {
        self.participantId = participantId
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NeuroCompass/sessions/\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        sessionDirectory = root
        metaURL = root.appendingPathComponent("session_meta.json")
        csvURL = root.appendingPathComponent("trials.csv")
        writeHeader()
    }

    func append(_ record: TrialRecord) {
        records.append(record)
        let line = [
            record.participantId,
            "\(record.trialId)",
            record.mode,
            String(format: "%.4f", record.soundAngleDeg),
            record.cueSide,
            record.targetSide,
            record.targetPresent ? "1" : "0",
            String(format: "%.4f", record.cueOnset),
            String(format: "%.4f", record.anticipatoryStart),
            String(format: "%.4f", record.anticipatoryEnd),
            String(format: "%.4f", record.targetOnset),
            record.responseOnset.map { String(format: "%.4f", $0) } ?? "",
            record.correct.map { $0 ? "1" : "0" } ?? "",
            record.reactionTimeMs.map { String(format: "%.1f", $0) } ?? "",
            record.artifactFlag ? "1" : "0",
            String(format: "%.6f", record.alphaPo7),
            String(format: "%.6f", record.alphaPo8),
            String(format: "%.6f", record.lateralization),
            record.eegSource
        ].joined(separator: ",")
        if let data = (line + "\n").data(using: .utf8), let handle = try? FileHandle(forWritingTo: csvURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    func writeSessionMeta(eegSource: EEGSourceKind, lockedMultiplier: Double?, note: String) {
        writeSessionMeta(eegSource: eegSource, lockedAngleDeg: lockedMultiplier, note: note)
    }

    func writeSessionMeta(eegSource: EEGSourceKind, lockedAngleDeg: Double?, note: String) {
        let meta: [String: Any] = [
            "participant_id": participantId,
            "sample_rate": 250,
            "montage": ["Fz", "C3", "Cz", "C4", "Pz", "PO7", "Oz", "PO8"],
            "eeg_source": eegSource.rawValue,
            "locked_sound_angle_deg": lockedAngleDeg as Any,
            "chosen_angle_deg": (lockedAngleDeg.flatMap { SoundAngle.isNone($0) ? nil : $0 }) as Any,
            "calibration_parameter": "hrtf_sound_angle",
            "code_version": "neurocompass-sound-0.1",
            "note": note,
            "trial_count": records.count,
            "session_directory": sessionDirectory.path
        ]
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: metaURL, options: .atomic)
        }
        if let a = lockedAngleDeg {
            let export: [String: Any] = [
                "chosen_angle_deg": SoundAngle.isNone(a) ? NSNull() : a,
                "label": SoundAngle.label(a),
                "eeg_source": eegSource.rawValue
            ]
            if let data = try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: sessionDirectory.appendingPathComponent("chosen_angle.json"), options: .atomic)
                let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("NeuroCompass/chosen_angle.json")
                try? FileManager.default.createDirectory(at: support.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: support, options: .atomic)
            }
        }
    }

    var allRecords: [TrialRecord] { records }

    private func writeHeader() {
        let header = "participant_id,trial_id,mode,sound_angle_deg,cue_side,target_side,target_present,cue_onset,anticipatory_start,anticipatory_end,target_onset,response_onset,correct,reaction_time_ms,artifact_flag,alpha_po7,alpha_po8,lateralization,eeg_source\n"
        try? header.write(to: csvURL, atomically: true, encoding: .utf8)
    }
}
