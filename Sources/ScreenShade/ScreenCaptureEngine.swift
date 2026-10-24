import AppKit
import CoreImage
@preconcurrency import ScreenCaptureKit
import CoreMedia
import CoreVideo

/// Captures one display (excluding overlay windows) and delivers frames for metric filtering.
final class ScreenCaptureEngine: NSObject {
    private(set) var hasPermission: Bool = CGPreflightScreenCaptureAccess()
    private var stream: SCStream?
    private var output: FrameOutput?
    private var displayID: CGDirectDisplayID?
    var onFrame: ((CGImage) -> Void)?
    var onPermissionChange: ((Bool) -> Void)?

    /// Request Screen Recording permission if needed. Returns whether capture may proceed.
    @discardableResult
    func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            hasPermission = true
            onPermissionChange?(true)
            return true
        }
        let granted = CGRequestScreenCaptureAccess()
        hasPermission = granted
        onPermissionChange?(granted)
        NotificationCenter.default.post(name: .shadeCapturePermissionDidChange, object: granted)
        return granted
    }

    func stop() {
        let existing = stream
        stream = nil
        output = nil
        displayID = nil
        Task {
            try? await existing?.stopCapture()
        }
    }

    func start(displayID: CGDirectDisplayID, excludingWindowIDs: [CGWindowID]) {
        if self.displayID == displayID, stream != nil { return }
        stop()
        self.displayID = displayID

        guard ensurePermission() else { return }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID })
                        ?? content.displays.first else {
                    return
                }

                let exclude = content.windows.filter { excludingWindowIDs.contains(CGWindowID($0.windowID)) }
                let filter = SCContentFilter(display: display, excludingWindows: exclude)

                let config = SCStreamConfiguration()
                config.minimumFrameInterval = CMTime(value: 1, timescale: 12)
                config.queueDepth = 2
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false

                var width = display.width
                var height = display.height
                if let screen = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
                }) {
                    let scale = screen.backingScaleFactor
                    width = Int(CGFloat(display.width) * scale)
                    height = Int(CGFloat(display.height) * scale)
                }
                config.width = width
                config.height = height

                let frameOutput = FrameOutput { [weak self] image in
                    DispatchQueue.main.async {
                        self?.onFrame?(image)
                    }
                }
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(
                    frameOutput,
                    type: .screen,
                    sampleHandlerQueue: DispatchQueue(label: "com.screenshade.capture", qos: .userInitiated)
                )
                try await stream.startCapture()

                DispatchQueue.main.async {
                    self.output = frameOutput
                    self.stream = stream
                }
            } catch {
                DispatchQueue.main.async {
                    self.hasPermission = CGPreflightScreenCaptureAccess()
                    self.onPermissionChange?(self.hasPermission)
                }
            }
        }
    }
}

private final class FrameOutput: NSObject, SCStreamOutput {
    let handler: (CGImage) -> Void
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(handler: @escaping (CGImage) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = ciContext.createCGImage(ci, from: ci.extent) else { return }
        handler(image)
    }
}
