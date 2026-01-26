import AppKit

/// A full-screen transparent window for selecting a screen region.
final class RegionSelectorWindow: NSWindow, NSWindowDelegate {
    private var overlayView: RegionOverlayView!
    private var completion: ((CGRect?) -> Void)?

    static func present(completion: @escaping (CGRect?) -> Void) {
        guard let screen = NSScreen.main else { return }
        let window = RegionSelectorWindow(screen: screen, completion: completion)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(window.overlayView)
    }

    convenience init(screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        let frame = screen.frame
        self.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.completion = completion
        isOpaque = false
        backgroundColor = NSColor.clear
        ignoresMouseEvents = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self

        overlayView = RegionOverlayView(frame: frame)
        contentView = overlayView

        overlayView.onFinish = { [weak self] rect in
            guard let self = self else { return }
            self.orderOut(nil)
            self.completion?(rect)
            self.completion = nil
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func windowDidResignKey(_ notification: Notification) {
        overlayView.cancelSelection()
    }
}

final class RegionOverlayView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var didFinish = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.3).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC
            cancelSelection()
        case 36: // Enter - confirm current selection
            confirmSelection()
        default:
            break
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
        // Don't auto-finish on mouse up - wait for Enter key
    }

    private func confirmSelection() {
        guard !didFinish else { return }
        guard let start = startPoint, let end = currentPoint else {
            finishSelection(with: nil)
            return
        }

        let rectAppKit = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        guard rectAppKit.width > 10 && rectAppKit.height > 10 else {
            finishSelection(with: nil)
            return
        }

        // Convert to Quartz/CG coordinates (origin top-left)
        guard let screen = self.window?.screen else {
            finishSelection(with: rectAppKit)
            return
        }

        let screenHeight = screen.frame.height
        let cgRect = CGRect(
            x: rectAppKit.origin.x,
            y: screenHeight - rectAppKit.origin.y - rectAppKit.height,
            width: rectAppKit.width,
            height: rectAppKit.height
        )

        finishSelection(with: cgRect)
    }

    private func finishSelection(with rect: CGRect?) {
        guard !didFinish else { return }
        didFinish = true
        onFinish?(rect)
    }

    func cancelSelection() {
        finishSelection(with: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw instructions
        let instructions = "Drag to select region. Enter to confirm, ESC to cancel."
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = instructions.size(withAttributes: attrs)
        let point = CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 60)
        instructions.draw(at: point, withAttributes: attrs)

        guard let start = startPoint, let current = currentPoint else { return }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // Draw selection rectangle
        let path = NSBezierPath(rect: rect)
        NSColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()

        // Dim area outside selection
        let outside = NSBezierPath(rect: bounds)
        outside.appendRect(rect)
        outside.windingRule = .evenOdd
        NSColor(calibratedWhite: 0, alpha: 0.35).setFill()
        outside.fill()

        // Show dimensions
        let dimensionText = "\(Int(rect.width)) × \(Int(rect.height))"
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        let dimSize = dimensionText.size(withAttributes: dimAttrs)
        let dimPoint = CGPoint(
            x: rect.midX - dimSize.width / 2,
            y: rect.midY - dimSize.height / 2
        )
        dimensionText.draw(at: dimPoint, withAttributes: dimAttrs)
    }
}
