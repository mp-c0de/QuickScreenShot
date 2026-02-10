import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            HowToUseTab()
                .tabItem {
                    Label("How to Use", systemImage: "questionmark.circle")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 320)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @EnvironmentObject var manager: ScreenshotManager
    @State private var isRecording = false
    @State private var recordingMonitor: Any?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Capture Shortcut")
                .font(.headline)

            Text(manager.shortcutDisplayString)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(isRecording ? "Press a key..." : "Record New Shortcut") {
                startRecording()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRecording)

            if isRecording {
                Text("Press any key combination. Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc cancels
                stopRecording()
                return nil
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            manager.updateHotkey(keyCode: event.keyCode, modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
    }
}

// MARK: - How to Use Tab

private struct HowToUseTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Getting Started")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    stepRow(number: 1, title: "Set Coordinates", description: "Click \"Set Coordinates\" and drag to select the screen region you want to capture.")
                    stepRow(number: 2, title: "Set Location", description: "Choose a folder where screenshots will be saved.")
                    stepRow(number: 3, title: "Capture", description: "Press your shortcut key or click Capture. Screenshots are numbered automatically.")
                    stepRow(number: 4, title: "Reset Counter", description: "Click Reset to start numbering from 1 again.")
                }

                Divider()

                Text("Permissions")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("**Screen Recording** — Required for capturing screen content. Grant in System Settings > Privacy & Security.")
                            .font(.callout)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("**Accessibility** — Required for global hotkey to work when other apps are focused. Grant in System Settings > Privacy & Security.")
                            .font(.callout)
                    }
                }
            }
            .padding()
        }
    }

    private func stepRow(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(width: 24, height: 24)
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // mpcode branding
            HStack(spacing: 0) {
                Text("mp")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
                Text("code")
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text("QUICKSCREENSHOT")
                .font(.system(size: 11, weight: .medium))
                .tracking(3)
                .foregroundStyle(.secondary)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
                .frame(height: 8)

            HStack(spacing: 16) {
                Link("www.mpcode.dev", destination: URL(string: "https://www.mpcode.dev")!)
                    .font(.callout)

                Link("mpcode@mpcode.dev", destination: URL(string: "mailto:mpcode@mpcode.dev")!)
                    .font(.callout)
            }

            Spacer()

            Text("Made with care by mpcode")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

#Preview {
    SettingsView()
        .environmentObject(ScreenshotManager())
}
