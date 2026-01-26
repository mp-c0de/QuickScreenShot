import SwiftUI
import ScreenCaptureKit
import CoreImage

enum CaptureQuality: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case best = "Best"

    var scale: CGFloat {
        switch self {
        case .low: return 0.5
        case .medium: return 1.0
        case .best: return 2.0  // Native Retina
        }
    }
}

class ScreenshotManager: ObservableObject {
    @Published var selectedRegion: CGRect?
    @Published var saveDirectory: URL?
    @Published var screenshotCount: Int = 0
    @Published var isSelectingRegion: Bool = false
    @Published var statusMessage: String = "Set region and save location to start"
    @Published var quality: CaptureQuality = .best {
        didSet {
            // Restart stream with new quality
            if isStreamRunning {
                Task {
                    await stopStream()
                }
            }
            UserDefaults.standard.set(quality.rawValue, forKey: "captureQuality")
        }
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var captureStream: SCStream?
    private var streamOutput: ScreenCaptureOutput?
    private var isStreamRunning = false
    private var captureScale: CGFloat = 2.0

    init() {
        loadSettings()
        setupHotkeys()
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupHotkeys() {
        // Global hotkey for "0" key (needs Accessibility permission)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 29 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                DispatchQueue.main.async {
                    self?.takeScreenshot()
                }
            }
        }

        // Local hotkey for when app is focused (no permission needed)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 29 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                DispatchQueue.main.async {
                    self?.takeScreenshot()
                }
                return nil
            }
            return event
        }
    }

    func startRegionSelection() {
        isSelectingRegion = true
    }

    func setRegion(_ rect: CGRect) {
        selectedRegion = rect
        isSelectingRegion = false
        saveSettings()
        updateStatus()
    }

    func cancelRegionSelection() {
        isSelectingRegion = false
    }

    func selectSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select folder to save screenshots"

        if panel.runModal() == .OK {
            saveDirectory = panel.url
            saveSettings()
            updateStatus()
        }
    }

    func takeScreenshot() {
        guard let region = selectedRegion else {
            statusMessage = "No region selected"
            return
        }

        guard let saveDir = saveDirectory else {
            statusMessage = "No save location set"
            return
        }

        Task {
            do {
                guard let screenshot = try await captureRegion(region) else {
                    await MainActor.run {
                        statusMessage = "Failed to capture"
                    }
                    return
                }

                await MainActor.run {
                    screenshotCount += 1
                    let filename = "\(screenshotCount).png"
                    let fileURL = saveDir.appendingPathComponent(filename)

                    if savePNG(image: screenshot, to: fileURL) {
                        statusMessage = "Saved: \(filename)"
                        saveSettings()
                    } else {
                        statusMessage = "Failed to save"
                        screenshotCount -= 1
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Capture error"
                }
            }
        }
    }

    private func captureRegion(_ rect: CGRect) async throws -> NSImage? {
        // Start stream if not running
        if !isStreamRunning {
            try await startCaptureStream()
        }

        // Wait a moment for frame to be available
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        guard let fullImage = streamOutput?.latestFrame else {
            return nil
        }

        // Scale rect for Retina capture resolution
        let scaledRect = CGRect(
            x: rect.origin.x * captureScale,
            y: rect.origin.y * captureScale,
            width: rect.width * captureScale,
            height: rect.height * captureScale
        )

        // Crop to the requested region
        guard let croppedImage = fullImage.cropping(to: scaledRect) else {
            return nil
        }

        return NSImage(cgImage: croppedImage, size: rect.size)
    }

    private func stopStream() async {
        if let stream = captureStream {
            try? await stream.stopCapture()
        }
        captureStream = nil
        streamOutput = nil
        isStreamRunning = false
    }

    private func startCaptureStream() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let mainDisplay = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            throw CaptureError.noDisplay
        }

        // Use quality setting for capture scale
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.captureScale = quality.scale * (screenScale / 2.0)  // Adjust for non-Retina

        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(mainDisplay.width) * captureScale)
        config.height = Int(CGFloat(mainDisplay.height) * captureScale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.scalesToFit = false

        let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        let output = ScreenCaptureOutput()
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive))

        try await stream.startCapture()

        self.captureStream = stream
        self.streamOutput = output
        self.isStreamRunning = true

        // Wait for first frame
        for _ in 0..<30 {
            if output.latestFrame != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func savePNG(image: NSImage, to url: URL) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        do {
            try pngData.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private func updateStatus() {
        if selectedRegion != nil && saveDirectory != nil {
            statusMessage = "Ready! Press 0 to capture"
        } else if selectedRegion == nil {
            statusMessage = "Set region to continue"
        } else {
            statusMessage = "Set save location to continue"
        }
    }

    // MARK: - Persistence
    private func saveSettings() {
        if let region = selectedRegion {
            UserDefaults.standard.set(region.origin.x, forKey: "regionX")
            UserDefaults.standard.set(region.origin.y, forKey: "regionY")
            UserDefaults.standard.set(region.width, forKey: "regionWidth")
            UserDefaults.standard.set(region.height, forKey: "regionHeight")
        }
        if let dir = saveDirectory {
            UserDefaults.standard.set(dir.path, forKey: "saveDirectory")
        }
        UserDefaults.standard.set(screenshotCount, forKey: "screenshotCount")
    }

    private func loadSettings() {
        let x = UserDefaults.standard.double(forKey: "regionX")
        let y = UserDefaults.standard.double(forKey: "regionY")
        let w = UserDefaults.standard.double(forKey: "regionWidth")
        let h = UserDefaults.standard.double(forKey: "regionHeight")

        if w > 0 && h > 0 {
            selectedRegion = CGRect(x: x, y: y, width: w, height: h)
        }

        if let path = UserDefaults.standard.string(forKey: "saveDirectory") {
            saveDirectory = URL(fileURLWithPath: path)
        }

        if let qualityRaw = UserDefaults.standard.string(forKey: "captureQuality"),
           let savedQuality = CaptureQuality(rawValue: qualityRaw) {
            quality = savedQuality
        }

        screenshotCount = UserDefaults.standard.integer(forKey: "screenshotCount")
        updateStatus()
    }

    func resetCounter() {
        screenshotCount = 0
        saveSettings()
        updateStatus()
    }

    enum CaptureError: Error {
        case noDisplay
    }
}

// MARK: - Screen Capture Output
private final class ScreenCaptureOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var _latestFrame: CGImage?

    var latestFrame: CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return _latestFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let imageBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()

        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            lock.lock()
            _latestFrame = cgImage
            lock.unlock()
        }
    }
}
