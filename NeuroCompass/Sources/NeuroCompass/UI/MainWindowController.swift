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
    private var busy = false

    init() {
        let participant = "P001"
        // Mac default: labeled mock. Swap to BrainFlowEEGStub on Windows live builds.
        let mock = MockEEGSource()
        self.eeg = mock
        self.decoder = StubModulationDecoder()
        self.logger = TrialLogger(participantId: participant)

        let win = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1100, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "NeuroCompass"
        win.minSize = NSSize(width: 900, height: 600)
        super.init(window: win)
        win.delegate = self
        buildUI()
        wireEngine()
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
        // 4 trials/setting keeps the mock grid demo under a few minutes; raise for pilot.
        loop = CalibrationLoop(trialEngine: trialEngine, shade: shade, trialsPerSetting: 4)
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
                self?.multiplierField.stringValue = String(format: "Contrast ×%.2f", result.multiplier)
            }
        }
        eeg.start()
        KeyMonitor.shared.install()
        shade.setNeutral()
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
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        stack.addArrangedSubview(header("Operator"))
        modeField = label("Mode: neutral")
        multiplierField = label("Contrast ×1.00")
        trialField = label("Trials: 0")
        modulationField = label("Modulation: —")
        eegSourceField = label("EEG source: \(eeg.sourceKind.rawValue)")
        eegSourceField.textColor = eeg.sourceKind == .mock ? .systemOrange : .systemGreen
        statusField = wrappingLabel("Ready. Start ScreenShade, then run calibration.")
        for v in [modeField!, multiplierField!, trialField!, modulationField!, eegSourceField!, statusField!] {
            stack.addArrangedSubview(v)
        }

        stack.addArrangedSubview(button("Start Grid Calibration", #selector(runCalibration)))
        stack.addArrangedSubview(button("Run Neutral Block (4)", #selector(runNeutral)))
        stack.addArrangedSubview(button("Run Left-Degraded Block (4)", #selector(runDegraded)))
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
        let srcNote = wrappingLabel("Decoder is a stub (RMS proxy). Plug real Welch/PO7/PO8 at StubModulationDecoder / A7.")
        srcNote.font = .systemFont(ofSize: 10)
        stack.addArrangedSubview(srcNote)

        stack.addArrangedSubview(header("Results"))
        resultsView = makeTextView()
        let resultsScroll = NSScrollView()
        resultsScroll.documentView = resultsView
        resultsScroll.hasVerticalScroller = true
        resultsScroll.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.heightAnchor.constraint(equalToConstant: 140).isActive = true
        stack.addArrangedSubview(resultsScroll)

        stack.addArrangedSubview(header("Held-out (placeholder)"))
        heldOutView = makeTextView()
        heldOutView.string = "Held-out block not run yet.\nAfter lock, run a separate evaluation block and analyze separately from calibration."
        let heldScroll = NSScrollView()
        heldScroll.documentView = heldOutView
        heldScroll.hasVerticalScroller = true
        heldScroll.translatesAutoresizingMaskIntoConstraints = false
        heldScroll.heightAnchor.constraint(equalToConstant: 80).isActive = true
        stack.addArrangedSubview(heldScroll)

        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            canvas.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),

            sidebar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 320),

            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 12),
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
        f.preferredMaxLayoutWidth = 290
        return f
    }

    private func button(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        return b
    }

    private func makeTextView() -> NSTextView {
        let tv = NSTextView()
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.string = "(no calibration yet)"
        return tv
    }

    private func refreshOperator() {
        modeField.stringValue = "Mode: \(currentMode.displayName)"
        multiplierField.stringValue = String(format: "Contrast ×%.2f", currentMultiplier)
        eegSourceField.stringValue = "EEG source: \(eeg.sourceKind.rawValue)"
    }

    private func refreshPhysiology() {
        physSampleField.stringValue = "Samples: \(eeg.sampleCount) · connected=\(eeg.isConnected)"
        physQualityField.stringValue = "Quality: \(eeg.qualityOK ? "placeholder OK" : "placeholder FAIL") · source=\(eeg.sourceKind.rawValue)"
    }

    private func setBusy(_ v: Bool) {
        busy = v
        window?.toolbar?.items.forEach { _ in }
    }

    @objc private func runCalibration() {
        guard !busy else { return }
        setBusy(true)
        currentMode = .adjusted
        refreshOperator()
        statusField.stringValue = "Grid calibration starting…"
        Task { @MainActor in
            let outcome = await loop.runGrid()
            self.calibrationResults = outcome.results
            self.lockedMultiplier = outcome.lockedMultiplier
            self.currentMultiplier = outcome.lockedMultiplier
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
        refreshOperator()
        shade.apply(leftContrastMultiplier: 1.0)
        Task { @MainActor in
            _ = await loop.trySetting(1.0, mode: .neutral)
            self.statusField.stringValue = "Neutral block done."
            self.setBusy(false)
        }
    }

    @objc private func runDegraded() {
        guard !busy else { return }
        setBusy(true)
        currentMode = .leftDegraded
        currentMultiplier = 0.85
        refreshOperator()
        Task { @MainActor in
            _ = await loop.trySetting(0.85, mode: .leftDegraded)
            self.statusField.stringValue = "Left-degraded block done."
            self.setBusy(false)
        }
    }

    @objc private func applyLocked() {
        let m = lockedMultiplier ?? 1.0
        shade.apply(leftContrastMultiplier: m)
        currentMultiplier = m
        refreshOperator()
        statusField.stringValue = String(format: "Applied locked ×%.2f to ScreenShade.", m)
    }

    @objc private func shadeNeutral() {
        shade.setNeutral()
        currentMultiplier = 1.0
        refreshOperator()
        statusField.stringValue = "ScreenShade set to neutral ×1.00."
    }

    private func renderResults(_ outcome: CalibrationOutcome) {
        var lines: [String] = ["modulation per setting (calibration):"]
        for r in outcome.results {
            lines.append(String(
                format: "  ×%.2f  mod=%+.3f  hitL=%.0f%% hitR=%.0f%% medRT=%.0f  %@%@",
                r.multiplier,
                r.modulation,
                r.hitRateLeft * 100,
                r.hitRateRight * 100,
                r.medianRTMs,
                r.uncertain ? "UNCERTAIN " : "",
                r.multiplier == outcome.lockedMultiplier ? "← LOCKED" : ""
            ))
        }
        lines.append(outcome.message)
        lines.append("CSV: \(logger.sessionDirectory.path)")
        resultsView.string = lines.joined(separator: "\n")

        heldOutView.string = """
        Held-out placeholder
        Locked ×\(String(format: "%.2f", outcome.lockedMultiplier)) from calibration only.
        Run a separate held-out block next; do not treat calibration performance as the independent result.
        """
    }

    func windowWillClose(_ notification: Notification) {
        trialEngine.stop()
        eeg.stop()
        KeyMonitor.shared.remove()
        physTimer?.invalidate()
    }
}
