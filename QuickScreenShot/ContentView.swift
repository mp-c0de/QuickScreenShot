import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var manager: ScreenshotManager

    var body: some View {
        VStack(spacing: 20) {
            Text("QuickScreenShot")
                .font(.title2)
                .fontWeight(.semibold)

            Divider()

            // Region selection
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Region:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let region = manager.selectedRegion {
                        Text("\(Int(region.width))×\(Int(region.height))")
                            .monospacedDigit()
                    } else {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Set Coordinates") {
                    manager.startRegionSelection()
                }
                .buttonStyle(.borderedProminent)
            }

            // Save location
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Save to:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let dir = manager.saveDirectory {
                        Text(dir.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Set Location") {
                    manager.selectSaveDirectory()
                }
            }

            // Quality picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Quality:")
                    .foregroundStyle(.secondary)

                Picker("Quality", selection: $manager.quality) {
                    ForEach(CaptureQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // Counter and status
            HStack {
                Text("Screenshots:")
                    .foregroundStyle(.secondary)
                Text("\(manager.screenshotCount)")
                    .monospacedDigit()
                    .fontWeight(.medium)
                Spacer()
                Button("Reset") {
                    manager.resetCounter()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Capture button
            Button(action: {
                manager.takeScreenshot()
            }) {
                Text("Capture")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(manager.selectedRegion == nil || manager.saveDirectory == nil)
            .keyboardShortcut("0", modifiers: [])

            Text(manager.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("Press 0 or click Capture")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 280)
        .onChange(of: manager.isSelectingRegion) { _, isSelecting in
            if isSelecting {
                showRegionSelector()
            }
        }
    }

    private func showRegionSelector() {
        RegionSelectorWindow.present { [weak manager] rect in
            if let rect = rect {
                manager?.setRegion(rect)
            } else {
                manager?.cancelRegionSelection()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScreenshotManager())
}
