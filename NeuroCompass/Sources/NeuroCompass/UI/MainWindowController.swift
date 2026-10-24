import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let canvas = ExperimentCanvas()
    private var modeField: NSTextField!
    private var multiplierField: NSTextField!
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
    private let shade = ScreenShadeDriver()
    private var trialEngine: TrialEngine!
    private var loop: CalibrationLoop!
    private var physTimer: Timer?

    private(set) var currentMultiplier: Double = 1.0
    private(set) var currentMode: ExperimentMode = .neutral
    private(set) var lastModulation: Double = 0
    private var calibrationResults: [ModulationResult] = []
    private var lockedMultiplier: Double?
    private var lastCalibrationOutcome: CalibrationOutcome?
    private var heldOutResults: [ModulationResult] = []
    private var busy = false

    init() {
        let participant = "P001"
        let mock = MockEEGSource()
        self.eeg = mock
        self.decoder = StubModulationDecoder()
        self.logger = TrialLogger(participantId: participant)

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

        if ProcessInfo.processInfo.environment["NEUROCOMPASS_DEMO_SHADE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.previewDegraded()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func wireEngine() {
        trialEngine = TrialEngine(eeg: eeg, decoder: decoder, logger: logger, participantId: logger.participantId)
        trialEngine.onPhaseChange = { [weak self] phase in
            self?.canvas.setPhase(phase)
        }
        trialEngine.onTrialComplete = { [weak self] record in
            guard let self else { return }
            self.trialField.stringValue = "Trials: \(record.trialId)"
            self.physPO7Field.stringValue = String(format: "α PO7 (stub): %.3f", record.alphaPo7)
            self.physPO8Field.stringValue = String(format: "α PO8 (stub): %.3f", record.alphaPo8)
        }
        loop = CalibrationLoop(trialEngine: trialEngine, shade: shade, trialsPerSetting: 4)
        loop.pushToDesktop = false
        loop.onApplyInAppShade = { [weak self] m in
            self?.canvas.setLeftContrastMultiplier(m)
            self?.currentMultiplier = m
            self?.multiplierField.stringValue = String(format: "Contrast ×%.2f (in-app)", m)
            self?.modeField.stringValue = "Mode: \(self?.currentMode.displayName ?? "?")"
        }
        loop.onProgress = { [weak self] msg in
            DispatchQueue.main.async { self?.statusField.stringValue = msg }
        }
        loop.onModulation = { [weak self] result in
            DispatchQueue.main.async {
                self?.lastModulation = result.modulation
                self?.modulationField.stringValue = String(
                    format: "Modulation: %.3f%@",
                    result.modulation,
                    result.uncertain ? " (uncertain)" : ""
                )
                self?.currentMultiplier = result.multiplier
                self?.multiplierField.stringValue = String(format: "Contrast ×%.2f (in-app)", result.multiplier)
                // Live progress line in results while grid runs
                if var text = self?.resultsView.string, text.contains("calibration") || text.contains("Running") || text.hasPrefix("(") {
                    let line = String(
                        format: "  … ×%.2f → mod=%+.3f hitL=%.0f%% FA=%.0f%%%@\n",
                        result.multiplier,
                        result.modulation,
                        result.hitRateLeft * 100,
                        result.falseAlarmRate * 100,
                        result.uncertain ? " UNCERTAIN" : ""
                    )
                    if text.hasPrefix("(") { text = "Running calibration:\n" }
                    self?.resultsView.string = text + line
                }
            }
        }
        eeg.start()
        KeyMonitor.shared.install()
        canvas.setLeftContrastMultiplier(1.0)
        refreshOperator()
        physTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshPhysiology()
        }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.wantsLayer = true
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
        modeField = label("Mode: neutral")
        multiplierField = label("Contrast ×1.00 (in-app)")
        trialField = label("Trials: 0")
        modulationField = label("Modulation: —")
        eegSourceField = label("EEG source: \(eeg.sourceKind.rawValue)")
        eegSourceField.textColor = eeg.sourceKind == .mock ? .systemOrange : .systemGreen
        statusField = wrappingLabel("Ready. In-app left shade updates each grid step. Mock peaks at ×1.15.")
        for v in [modeField!, multiplierField!, trialField!, modulationField!, eegSourceField!, statusField!] {
            stack.addArrangedSubview(v)
        }

        stack.addArrangedSubview(button("Start Grid Calibration", #selector(runCalibration)))
        stack.addArrangedSubview(button("Quick Demo Grid (2/setting)", #selector(runQuickDemo)))
        stack.addArrangedSubview(button("Run Neutral Block (4)", #selector(runNeutral)))
        stack.addArrangedSubview(button("Run Left-Degraded Block (4)", #selector(runDegraded)))
        stack.addArrangedSubview(button("Preview Left-Degraded Shade", #selector(previewDegraded)))
        stack.addArrangedSubview(button("Run Held-out Block", #selector(runHeldOut)))

        stack.addArrangedSubview(header("Optional desktop"))
        stack.addArrangedSubview(button("Apply Locked → ScreenShade", #selector(applyLocked)))
        stack.addArrangedSubview(button("ScreenShade Neutral", #selector(shadeNeutral)))

        stack.addArrangedSubview(header("Physiology"))
        physSampleField = label("Samples: 0")
        physPO7Field = label("α PO7 (stub): —")
        physPO8Field = label("α PO8 (stub): —")
        physQualityField = label("Quality: placeholder OK")
        for v in [physSampleField!, physPO7Field!, physPO8Field!, physQualityField!] {
            stack.addArrangedSubview(v)
        }
        let srcNote = wrappingLabel("Decoder stub (RMS). Plug Welch/PO7/PO8 in StubModulationDecoder. Mock bias → ×1.15.")
        srcNote.font = .systemFont(ofSize: 10)
        stack.addArrangedSubview(srcNote)

        stack.addArrangedSubview(header("Results (calibration)"))
        resultsView = makeTextView()
        resultsView.string = "(no calibration yet — run Start Grid or Quick Demo)"
        let resultsScroll = NSScrollView()
        resultsScroll.documentView = resultsView
        resultsScroll.hasVerticalScroller = true
        resultsScroll.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        stack.addArrangedSubview(resultsScroll)

        heldOutHeader = header("Held-out (separate)")
        stack.addArrangedSubview(heldOutHeader)
        heldOutView = makeTextView()
        heldOutView.string = "Not run yet.\nAfter calibration locks a setting, click Run Held-out Block.\nHeld-out is NEVER the same as calibration."
        let heldScroll = NSScrollView()
        heldScroll.documentView = heldOutView
        heldScroll.hasVerticalScroller = true
        heldScroll.translatesAutoresizingMaskIntoConstraints = false
        heldScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        stack.addArrangedSubview(heldScroll)

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
            resultsScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            heldScroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
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
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.drawsBackground = true
        tv.backgroundColor = NSColor.textBackgroundColor
        return tv
    }

    private func refreshOperator() {
        modeField.stringValue = "Mode: \(currentMode.displayName)"
        multiplierField.stringValue = String(format: "Contrast ×%.2f (in-app)", currentMultiplier)
        eegSourceField.stringValue = "EEG source: \(eeg.sourceKind.rawValue)"
        eegSourceField.textColor = eeg.sourceKind == .mock ? .systemOrange : .systemGreen
    }

    private func refreshPhysiology() {
        physSampleField.stringValue = "Samples: \(eeg.sampleCount) · connected=\(eeg.isConnected)"
        physQualityField.stringValue = "Quality: \(eeg.qualityOK ? "placeholder OK" : "placeholder FAIL") · source=\(eeg.sourceKind.rawValue)"
    }

    private func setBusy(_ v: Bool) { busy = v }

    @objc private func runCalibration() {
        guard !busy else { return }
        runGrid(trialsPerSetting: 4, label: "Grid calibration")
    }

    @objc private func runQuickDemo() {
        guard !busy else { return }
        // 3 trials/setting keeps the demo short while usually covering both cue sides.
        runGrid(trialsPerSetting: 3, label: "Quick demo grid")
    }

    private func runGrid(trialsPerSetting: Int, label: String) {
        setBusy(true)
        currentMode = .adjusted
        refreshOperator()
        resultsView.string = "Running \(label):\n"
        heldOutView.string = "Held-out not started (calibration in progress)."
        statusField.stringValue = "\(label) starting — mock optimum ×\(String(format: "%.2f", MockEEGSource.demoOptimumMultiplier))…"
        loop = CalibrationLoop(trialEngine: trialEngine, shade: shade, trialsPerSetting: trialsPerSetting)
        loop.pushToDesktop = false
        loop.onApplyInAppShade = { [weak self] m in
            self?.canvas.setLeftContrastMultiplier(m)
            self?.currentMultiplier = m
            self?.multiplierField.stringValue = String(format: "Contrast ×%.2f (in-app)", m)
        }
        loop.onProgress = { [weak self] msg in
            DispatchQueue.main.async { self?.statusField.stringValue = msg }
        }
        loop.onModulation = { [weak self] result in
            DispatchQueue.main.async {
                self?.lastModulation = result.modulation
                self?.modulationField.stringValue = String(
                    format: "Modulation: %.3f%@",
                    result.modulation,
                    result.uncertain ? " (uncertain)" : ""
                )
                let line = String(
                    format: "  ×%.2f  mod=%+.3f  hitL=%.0f%% hitR=%.0f%% medRT=%.0f FA=%.0f%%%@\n",
                    result.multiplier,
                    result.modulation,
                    result.hitRateLeft * 100,
                    result.hitRateRight * 100,
                    result.medianRTMs,
                    result.falseAlarmRate * 100,
                    result.uncertain ? " UNCERTAIN" : ""
                )
                self?.resultsView.string += line
            }
        }
        Task { @MainActor in
            let outcome = await self.loop.runGrid()
            self.calibrationResults = outcome.results
            self.lockedMultiplier = outcome.lockedMultiplier
            self.lastCalibrationOutcome = outcome
            self.currentMultiplier = outcome.lockedMultiplier
            self.canvas.setLeftContrastMultiplier(outcome.lockedMultiplier)
            self.statusField.stringValue = outcome.message
            self.refreshOperator()
            self.renderResults(outcome)
            self.logger.writeSessionMeta(
                eegSource: self.eeg.sourceKind,
                lockedMultiplier: outcome.lockedMultiplier,
                note: outcome.message
            )
            self.setBusy(false)
        }
    }

    @objc private func runNeutral() {
        guard !busy else { return }
        setBusy(true)
        currentMode = .neutral
        currentMultiplier = 1.0
        canvas.setLeftContrastMultiplier(1.0)
        refreshOperator()
        Task { @MainActor in
            let r = await loop.trySetting(1.0, mode: .neutral)
            self.appendBlockSummary(title: "Neutral block", result: r)
            self.statusField.stringValue = "Neutral block done (in-app ×1.00)."
            self.setBusy(false)
        }
    }

    @objc private func runDegraded() {
        guard !busy else { return }
        setBusy(true)
        currentMode = .leftDegraded
        currentMultiplier = 0.85
        canvas.setLeftContrastMultiplier(0.85)
        refreshOperator()
        Task { @MainActor in
            let r = await loop.trySetting(0.85, mode: .leftDegraded)
            self.appendBlockSummary(title: "Left-degraded block", result: r)
            self.statusField.stringValue = "Left-degraded block done (in-app ×0.85)."
            self.setBusy(false)
        }
    }

    @objc private func previewDegraded() {
        currentMode = .leftDegraded
        currentMultiplier = 0.85
        canvas.setLeftContrastMultiplier(0.85)
        canvas.setPhase(.target(.left))
        refreshOperator()
        statusField.stringValue = "Preview: left hemifield degraded ×0.85 (right untouched)."
    }

    /// Separate held-out evaluation: locked setting + one comparison. Not calibration.
    @objc private func runHeldOut() {
        guard !busy else { return }
        guard let locked = lockedMultiplier else {
            statusField.stringValue = "Run calibration first — held-out needs a locked setting."
            heldOutView.string = "Blocked: no locked multiplier yet.\nRun Start Grid Calibration or Quick Demo first."
            return
        }
        setBusy(true)
        currentMode = .heldOut
        refreshOperator()
        heldOutView.string = "Running held-out (separate from calibration)…\n"
        statusField.stringValue = "Held-out: locked ×\(String(format: "%.2f", locked)) + comparison ×1.00"
        // Do not append held-out rows into the calibration results panel.
        let savedMod = loop.onModulation
        loop.onModulation = { [weak self] result in
            DispatchQueue.main.async {
                self?.heldOutView.string += String(
                    format: "  … ×%.2f mod=%+.3f\n",
                    result.multiplier,
                    result.modulation
                )
            }
        }
        Task { @MainActor in
            defer { self.loop.onModulation = savedMod }
            // Short held-out: locked setting then neutral comparison
            let lockedResult = await self.loop.trySetting(locked, mode: .heldOut)
            let comparison = await self.loop.trySetting(1.0, mode: .heldOut)
            self.heldOutResults = [lockedResult, comparison]
            self.canvas.setLeftContrastMultiplier(locked)
            self.currentMultiplier = locked
            self.renderHeldOut(locked: locked, lockedResult: lockedResult, comparison: comparison)
            self.logger.writeSessionMeta(
                eegSource: self.eeg.sourceKind,
                lockedMultiplier: locked,
                note: "Held-out complete; calibration lock=\(locked)"
            )
            self.statusField.stringValue = "Held-out done. Calibration lock unchanged at ×\(String(format: "%.2f", locked))."
            self.refreshOperator()
            self.setBusy(false)
        }
    }

    @objc private func applyLocked() {
        let m = lockedMultiplier ?? currentMultiplier
        shade.apply(leftContrastMultiplier: m)
        canvas.setLeftContrastMultiplier(m)
        currentMultiplier = m
        refreshOperator()
        statusField.stringValue = String(format: "Optional desktop: wrote ×%.2f to ScreenShade loop.json", m)
    }

    @objc private func shadeNeutral() {
        shade.setNeutral()
        canvas.setLeftContrastMultiplier(1.0)
        currentMultiplier = 1.0
        canvas.setPhase(.idle)
        refreshOperator()
        statusField.stringValue = "In-app neutral ×1.00 (ScreenShade loop.json also reset)."
    }

    private func appendBlockSummary(title: String, result: ModulationResult) {
        let line = String(
            format: "%@: ×%.2f mod=%+.3f hitL=%.0f%% hitR=%.0f%% medRT=%.0f FA=%.0f%%%@\n",
            title,
            result.multiplier,
            result.modulation,
            result.hitRateLeft * 100,
            result.hitRateRight * 100,
            result.medianRTMs,
            result.falseAlarmRate * 100,
            result.uncertain ? " UNCERTAIN" : ""
        )
        if resultsView.string.hasPrefix("(") {
            resultsView.string = line
        } else {
            resultsView.string += line
        }
    }

    private func renderResults(_ outcome: CalibrationOutcome) {
        var lines: [String] = [
            "CALIBRATION (not held-out)",
            "eeg_source=\(eeg.sourceKind.rawValue)  mock_peak=×\(String(format: "%.2f", MockEEGSource.demoOptimumMultiplier))",
            "modulation per setting:"
        ]
        for r in outcome.results {
            lines.append(String(
                format: "  ×%.2f  mod=%+.3f  hitL=%.0f%% hitR=%.0f%% medRT=%.0f FA=%.0f%%  %@%@",
                r.multiplier,
                r.modulation,
                r.hitRateLeft * 100,
                r.hitRateRight * 100,
                r.medianRTMs,
                r.falseAlarmRate * 100,
                r.uncertain ? "UNCERTAIN " : "",
                abs(r.multiplier - outcome.lockedMultiplier) < 0.001 ? "← LOCKED" : ""
            ))
        }
        lines.append(outcome.message)
        lines.append(String(
            format: "Locked ×%.2f%@ | CSV: %@",
            outcome.lockedMultiplier,
            outcome.lockedUncertain ? " (uncertain→neutral)" : "",
            logger.sessionDirectory.path
        ))
        resultsView.string = lines.joined(separator: "\n")

        heldOutView.string = """
        Held-out NOT run yet (this panel is separate).
        Calibration locked ×\(String(format: "%.2f", outcome.lockedMultiplier)).
        Click “Run Held-out Block” for a separate locked + comparison evaluation.
        Do not treat the numbers above as held-out.
        """
        heldOutHeader.stringValue = "Held-out (separate — not run)"
    }

    private func renderHeldOut(locked: Double, lockedResult: ModulationResult, comparison: ModulationResult) {
        heldOutHeader.stringValue = "Held-out (separate — complete)"
        heldOutView.string = """
        HELD-OUT (separate from calibration)
        eeg_source=\(eeg.sourceKind.rawValue)
          locked  ×\(String(format: "%.2f", locked))  mod=\(String(format: "%+.3f", lockedResult.modulation))  hitL=\(String(format: "%.0f", lockedResult.hitRateLeft * 100))%  medRT=\(String(format: "%.0f", lockedResult.medianRTMs))  FA=\(String(format: "%.0f", lockedResult.falseAlarmRate * 100))%
          compare ×1.00  mod=\(String(format: "%+.3f", comparison.modulation))  hitL=\(String(format: "%.0f", comparison.hitRateLeft * 100))%  medRT=\(String(format: "%.0f", comparison.medianRTMs))  FA=\(String(format: "%.0f", comparison.falseAlarmRate * 100))%
        Calibration lock unchanged at ×\(String(format: "%.2f", locked)).
        """
    }

    func windowWillClose(_ notification: Notification) {
        trialEngine.stop()
        eeg.stop()
        KeyMonitor.shared.remove()
        physTimer?.invalidate()
    }
}
