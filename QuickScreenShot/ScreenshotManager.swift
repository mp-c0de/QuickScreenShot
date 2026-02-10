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
    @Published var hotkeyKeyCode: UInt16 = 29
    @Published var hotkeyModifiers: NSEvent.ModifierFlags = []
    @Published var quality: CaptureQuality = .best {
        didSet {
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

    // MARK: - Hotkey Management

    private func setupHotkeys() {
        removeHotkeyMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            if event.keyCode == self.hotkeyKeyCode &&
                event.modifierFlags.intersection(.deviceIndependentFlagsMask) == self.hotkeyModifiers {
                DispatchQueue.main.async {
                    self.takeScreenshot()
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == self.hotkeyKeyCode &&
                event.modifierFlags.intersection(.deviceIndependentFlagsMask) == self.hotkeyModifiers {
                DispatchQueue.main.async {
                    self.takeScreenshot()
                }
                return nil
            }
            return event
        }
    }

    private func removeHotkeyMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    func updateHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hotkeyModifiers")
        setupHotkeys()
        updateStatus()
    }

    // MARK: - Shortcut Display

    var shortcutDisplayString: String {
        Self.shortcutDisplayString(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    static func shortcutDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)

        return parts.joined()
    }

    private static func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "Tab", 49: "Space", 50: "`", 51: "Delete",
            53: "Esc", 36: "Return",
            76: "Enter", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13",
            107: "F14", 109: "F10", 111: "F12", 113: "F15",
            118: "F4", 120: "F2", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }

    // MARK: - Region & Directory

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

    // MARK: - Capture

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

                    let accessGranted = saveDir.startAccessingSecurityScopedResource()
                    defer {
                        if accessGranted { saveDir.stopAccessingSecurityScopedResource() }
                    }

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
        if !isStreamRunning {
            try await startCaptureStream()
        }

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        guard let fullImage = streamOutput?.latestFrame else {
            return nil
        }

        let scaledRect = CGRect(
            x: rect.origin.x * captureScale,
            y: rect.origin.y * captureScale,
            width: rect.width * captureScale,
            height: rect.height * captureScale
        )

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

        let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.captureScale = quality.scale * (screenScale / 2.0)

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
            statusMessage = "Ready! Press \(shortcutDisplayString) to capture"
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
            // Save security-scoped bookmark
            if let bookmarkData = try? dir.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmarkData, forKey: "saveDirectoryBookmark")
            }
            // Keep plain path as fallback
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

        // Try security-scoped bookmark first
        if let bookmarkData = UserDefaults.standard.data(forKey: "saveDirectoryBookmark") {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    if let freshBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        UserDefaults.standard.set(freshBookmark, forKey: "saveDirectoryBookmark")
                    }
                }
                saveDirectory = url
            }
        }

        // Fallback to plain path if bookmark failed
        if saveDirectory == nil, let path = UserDefaults.standard.string(forKey: "saveDirectory") {
            saveDirectory = URL(fileURLWithPath: path)
        }

        if let qualityRaw = UserDefaults.standard.string(forKey: "captureQuality"),
           let savedQuality = CaptureQuality(rawValue: qualityRaw) {
            quality = savedQuality
        }

        // Load hotkey settings
        if UserDefaults.standard.object(forKey: "hotkeyKeyCode") != nil {
            hotkeyKeyCode = UInt16(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
            hotkeyModifiers = NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: "hotkeyModifiers")))
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
