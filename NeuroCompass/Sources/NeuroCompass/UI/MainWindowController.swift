import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let canvas = ExperimentCanvas()
    private var modeField: NSTextField!
    private var angleField: NSTextField!
    private var trialField: NSTextField!
    private var modulationField: NSTextField!
    private var eegSourceField: NSTextField!
    private var statusField: NSTextField!
    private var physSampleField: NSTextField!
    private var physPO7Field: NSTextField!
    private var physPO8Field: NSTextField!
    private var physQualityField: NSTextField!
    private var resultsView: NSTextView!
    private var heldOutView: NSTextView!
    private var heldOutHeader: NSTextField!

    private let eeg: EEGSource
    private let decoder: ModulationDecoder
    private let logger: TrialLogger
    private let audio = SpatialAudioEngine()
    private var trialEngine: TrialEngine!
    private var loop: CalibrationLoop!
    private var physTimer: Timer?

    private(set) var currentAngleDeg: Double = SoundAngle.none
    private(set) var currentMode: ExperimentMode = .neutral
    private var lockedAngleDeg: Double?
    private var busy = false

    init() {
        let mock = MockEEGSource()
        self.eeg = mock
        self.decoder = StubModulationDecoder()
        self.logger = TrialLogger(participantId: "P001")

        let win = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1100, height: 740),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "NeuroCompass"
        win.minSize = NSSize(width: 900, height: 620)
        super.init(window: win)
        win.delegate = self
        buildUI()
        wireEngine()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func wireEngine() {
        trialEngine = TrialEngine(
            eeg: eeg,
            decoder: decoder,
            logger: logger,
            audio: audio,
            participantId: logger.participantId
        )
        trialEngine.onPhaseChange = { [weak self] phase in
            self?.canvas.setPhase(phase)
        }
        trialEngine.onTrialComplete = { [weak self] record in
            guard let self else { return }
            self.trialField.stringValue = "Trials: \(record.trialId)"
            self.physPO7Field.stringValue = String(format: "α PO7 (stub): %.3f", record.alphaPo7)
            self.physPO8Field.stringValue = String(format: "α PO8 (stub): %.3f", record.alphaPo8)
        }
        loop = makeLoop(trialsPerSetting: 4)
        eeg.start()
        KeyMonitor.shared.install()
        applyAngle(SoundAngle.none)
        refreshOperator()
        physTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshPhysiology()
        }
    }

    private func makeLoop(trialsPerSetting: Int) -> CalibrationLoop {
        let loop = CalibrationLoop(trialEngine: trialEngine, audio: audio, trialsPerSetting: trialsPerSetting)
        loop.onApplySoundAngle = { [weak self] a in
            self?.applyAngle(a)
        }
        loop.onProgress = { [weak self] msg in
            DispatchQueue.main.async { self?.statusField.stringValue = msg }
        }
        loop.onModulation = { [weak self] result in
            DispatchQueue.main.async {
                self?.modulationField.stringValue = String(
                    format: "Modulation: %.3f%@",
                    result.modulation,
                    result.uncertain ? " (uncertain)" : ""
                )
                self?.applyAngle(result.soundAngleDeg)
                if var text = self?.resultsView.string,
                   text.contains("calibration") || text.contains("Running") || text.hasPrefix("(") || text.hasPrefix("Running") {
                    if text.hasPrefix("(") { text = "Running calibration:\n" }
                    let line = String(
                        format: "  %@  mod=%+.3f  hitL=%.0f%% hitR=%.0f%% medRT=%.0f FA=%.0f%%%@\n",
                        SoundAngle.label(result.soundAngleDeg),
                        result.modulation,
                        result.hitRateLeft * 100,
                        result.hitRateRight * 100,
                        result.medianRTMs,
                        result.falseAlarmRate * 100,
                        result.uncertain ? " UNCERTAIN" : ""
                    )
                    self?.resultsView.string = text + line
                }
            }
        }
        return loop
    }

    private func applyAngle(_ deg: Double) {
        currentAngleDeg = deg
        canvas.setSoundAngleDeg(deg)
        angleField?.stringValue = "Sound: \(SoundAngle.label(deg))"
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        canvas.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(canvas)

        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        stack.addArrangedSubview(header("Operator"))
        modeField = label("Mode: neutral (no sound)")
        angleField = label("Sound: no-sound")
        trialField = label("Trials: 0")
        modulationField = label("Modulation: —")
        eegSourceField = label("EEG source: mock")
        eegSourceField.textColor = .systemOrange
        eegSourceField.font = .boldSystemFont(ofSize: 13)
        statusField = wrappingLabel("Dot task: watch the cross; optional HRTF chirp; press F/J for which side the dot flashed. Mock peak −45°.")
        for v in [modeField!, angleField!, trialField!, modulationField!, eegSourceField!, statusField!] {
            stack.addArrangedSubview(v)
        }

        stack.addArrangedSubview(button("Start Grid Calibration", #selector(runCalibration)))
        stack.addArrangedSubview(button("Quick Demo Grid (3/setting)", #selector(runQuickDemo)))
        stack.addArrangedSubview(button("Run Neutral Block (no sound)", #selector(runNeutral)))
        stack.addArrangedSubview(button("Run No-Sound Block (4)", #selector(runNoSound)))
        stack.addArrangedSubview(button("Preview cue at −45°", #selector(previewOptimum)))
        stack.addArrangedSubview(button("Run Held-out Block", #selector(runHeldOut)))

        stack.addArrangedSubview(header("Physiology"))
        physSampleField = label("Samples: 0")
        physPO7Field = label("α PO7 (stub): —")
        physPO8Field = label("α PO8 (stub): —")
        physQualityField = label("Quality: placeholder OK")
        for v in [physSampleField!, physPO7Field!, physPO8Field!, physQualityField!] {
            stack.addArrangedSubview(v)
        }
        let note = wrappingLabel("Decoder stub (RMS). Mock L/R swing follows dot side (no arrow). Peak −45°. Veil off.")
        note.font = .systemFont(ofSize: 10)
        stack.addArrangedSubview(note)

        stack.addArrangedSubview(header("Results (calibration)"))
        resultsView = makeTextView()
        resultsView.string = "(no calibration yet — run Quick Demo or Start Grid)"
        let resultsScroll = wrapScroll(resultsView, height: 150)
        stack.addArrangedSubview(resultsScroll)

        heldOutHeader = header("Held-out (separate)")
        stack.addArrangedSubview(heldOutHeader)
        heldOutView = makeTextView()
        heldOutView.string = "Not run yet.\nAfter lock, click Run Held-out Block.\nHeld-out is NEVER the same as calibration."
        stack.addArrangedSubview(wrapScroll(heldOutView, height: 100))

        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            canvas.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 330),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 10),
            resultsScroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func header(_ t: String) -> NSTextField {
        let f = NSTextField(labelWithString: t)
        f.font = .boldSystemFont(ofSize: 13)
        return f
    }
    private func label(_ t: String) -> NSTextField {
        let f = NSTextField(labelWithString: t)
        f.font = .systemFont(ofSize: 12)
        return f
    }
    private func wrappingLabel(_ t: String) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: t)
        f.font = .systemFont(ofSize: 11)
        f.preferredMaxLayoutWidth = 300
        return f
    }
    private func button(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        return b
    }
    private func makeTextView() -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.backgroundColor = .textBackgroundColor
        return tv
    }
    private func wrapScroll(_ tv: NSTextView, height: CGFloat) -> NSScrollView {
        let s = NSScrollView()
        s.documentView = tv
        s.hasVerticalScroller = true
        s.translatesAutoresizingMaskIntoConstraints = false
        s.heightAnchor.constraint(equalToConstant: height).isActive = true
        return s
    }

    private func refreshOperator() {
        modeField.stringValue = "Mode: \(currentMode.displayName)"
        angleField.stringValue = "Sound: \(SoundAngle.label(currentAngleDeg))"
        eegSourceField.stringValue = "EEG source: \(eeg.sourceKind.rawValue)"
        eegSourceField.textColor = eeg.sourceKind == .mock ? .systemOrange : .systemGreen
    }

    private func refreshPhysiology() {
        physSampleField.stringValue = "Samples: \(eeg.sampleCount) · connected=\(eeg.isConnected)"
        physQualityField.stringValue = "Quality: \(eeg.qualityOK ? "placeholder OK" : "FAIL") · source=\(eeg.sourceKind.rawValue)"
    }

    @objc private func runCalibration() {
        guard !busy else { return }
        runGrid(trials: 4, label: "Grid calibration")
    }

    @objc private func runQuickDemo() {
        guard !busy else { return }
        runGrid(trials: 3, label: "Quick demo grid")
    }

    private func runGrid(trials: Int, label: String) {
        busy = true
        currentMode = .adjusted
        refreshOperator()
        resultsView.string = "Running \(label):\n"
        heldOutView.string = "Held-out not started."
        statusField.stringValue = "\(label) — mock peak \(SoundAngle.label(SoundAngle.demoOptimum))"
        loop = makeLoop(trialsPerSetting: trials)
        Task { @MainActor in
            let outcome = await self.loop.runGrid()
            self.lockedAngleDeg = outcome.lockedAngleDeg
            self.applyAngle(outcome.lockedAngleDeg)
            self.statusField.stringValue = outcome.message
            self.refreshOperator()
            self.renderResults(outcome)
            self.logger.writeSessionMeta(
                eegSource: self.eeg.sourceKind,
                lockedAngleDeg: outcome.lockedAngleDeg,
                note: outcome.message
            )
            self.busy = false
        }
    }

    @objc private func runNeutral() {
        guard !busy else { return }
        busy = true
        currentMode = .neutral
        applyAngle(SoundAngle.none)
        refreshOperator()
        Task { @MainActor in
            let r = await loop.trySetting(SoundAngle.none, mode: .neutral)
            self.appendSummary("Neutral (no sound)", r)
            self.statusField.stringValue = "Neutral block done."
            self.busy = false
        }
    }

    @objc private func runNoSound() {
        guard !busy else { return }
        busy = true
        currentMode = .leftDegraded
        applyAngle(SoundAngle.none)
        refreshOperator()
        Task { @MainActor in
            let r = await loop.trySetting(SoundAngle.none, mode: .leftDegraded)
            self.appendSummary("No-sound block", r)
            self.statusField.stringValue = "No-sound block done."
            self.busy = false
        }
    }

    @objc private func previewOptimum() {
        applyAngle(SoundAngle.demoOptimum)
        currentMode = .adjusted
        refreshOperator()
        audio.play(azimuthDegrees: SoundAngle.demoOptimum)
        statusField.stringValue = "Preview HRTF cue at −45° (mock optimum). Headphones recommended."
        canvas.setPhase(.idle)
    }

    @objc private func runHeldOut() {
        guard !busy else { return }
        guard let locked = lockedAngleDeg else {
            statusField.stringValue = "Run calibration first."
            heldOutView.string = "Blocked: no locked angle yet."
            return
        }
        busy = true
        currentMode = .heldOut
        refreshOperator()
        heldOutView.string = "Running held-out…\n"
        heldOutHeader.stringValue = "Held-out (separate — running)"
        let saved = loop.onModulation
        loop.onModulation = { [weak self] result in
            DispatchQueue.main.async {
                self?.heldOutView.string += String(
                    format: "  … %@ mod=%+.3f\n",
                    SoundAngle.label(result.soundAngleDeg),
                    result.modulation
                )
            }
        }
        Task { @MainActor in
            defer { self.loop.onModulation = saved }
            let lockedResult = await self.loop.trySetting(locked, mode: .heldOut)
            let comparison = await self.loop.trySetting(SoundAngle.none, mode: .heldOut)
            self.applyAngle(locked)
            self.heldOutHeader.stringValue = "Held-out (separate — complete)"
            self.heldOutView.string = """
            HELD-OUT (separate from calibration)
            eeg_source=\(self.eeg.sourceKind.rawValue)
              locked  \(SoundAngle.label(locked))  mod=\(String(format: "%+.3f", lockedResult.modulation))  hitL=\(String(format: "%.0f", lockedResult.hitRateLeft * 100))%  medRT=\(String(format: "%.0f", lockedResult.medianRTMs))
              compare no-sound  mod=\(String(format: "%+.3f", comparison.modulation))  hitL=\(String(format: "%.0f", comparison.hitRateLeft * 100))%
            Calibration lock unchanged at \(SoundAngle.label(locked)).
            """
            self.statusField.stringValue = "Held-out done. Lock \(SoundAngle.label(locked))."
            self.refreshOperator()
            self.busy = false
        }
    }

    private func appendSummary(_ title: String, _ r: ModulationResult) {
        let line = String(
            format: "%@: %@ mod=%+.3f hitL=%.0f%% medRT=%.0f FA=%.0f%%\n",
            title, SoundAngle.label(r.soundAngleDeg), r.modulation, r.hitRateLeft * 100, r.medianRTMs, r.falseAlarmRate * 100
        )
        resultsView.string = resultsView.string.hasPrefix("(") ? line : resultsView.string + line
    }

    private func renderResults(_ outcome: CalibrationOutcome) {
        var lines = [
            "CALIBRATION (sound angle — not held-out)",
            "eeg_source=\(eeg.sourceKind.rawValue)  mock_peak=\(SoundAngle.label(SoundAngle.demoOptimum))",
            "modulation per setting:"
        ]
        for r in outcome.results {
            lines.append(String(
                format: "  %@  mod=%+.3f  hitL=%.0f%% hitR=%.0f%% medRT=%.0f FA=%.0f%%  %@%@",
                SoundAngle.label(r.soundAngleDeg),
                r.modulation,
                r.hitRateLeft * 100,
                r.hitRateRight * 100,
                r.medianRTMs,
                r.falseAlarmRate * 100,
                r.uncertain ? "UNCERTAIN " : "",
                abs(r.soundAngleDeg - outcome.lockedAngleDeg) < 0.001 ? "← LOCKED" : ""
            ))
        }
        lines.append(outcome.message)
        lines.append("CSV: \(logger.sessionDirectory.path)")
        resultsView.string = lines.joined(separator: "\n")
        heldOutHeader.stringValue = "Held-out (separate — not run)"
        heldOutView.string = """
        Held-out NOT run yet.
        Calibration locked \(SoundAngle.label(outcome.lockedAngleDeg)).
        Click “Run Held-out Block” for a separate locked + no-sound comparison.
        """
    }

    func windowWillClose(_ notification: Notification) {
        trialEngine.stop()
        eeg.stop()
        audio.shutdown()
        KeyMonitor.shared.remove()
        physTimer?.invalidate()
    }
}
