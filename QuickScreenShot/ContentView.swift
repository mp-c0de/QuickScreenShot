import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var manager: ScreenshotManager

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                regionSection

                saveLocationSection

                qualitySection

                counterSection

                // Capture button
                Button(action: {
                    manager.takeScreenshot()
                }) {
                    Text("Capture")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(manager.selectedRegion == nil || manager.saveDirectory == nil)

                // Status and shortcut hint
                VStack(spacing: 4) {
                    Text(manager.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Press \(manager.shortcutDisplayString) or click Capture")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .glassEffect(.clear, in: .rect(cornerRadius: 10))
            }
            .padding(24)
            .frame(width: 300)
        }
        .toolbar(removing: .title)
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gear")
                }
                .buttonStyle(.glass)
            }
        }
        .onChange(of: manager.isSelectingRegion) { _, isSelecting in
            if isSelecting {
                showRegionSelector()
            }
        }
    }

    // MARK: - Sections

    private var regionSection: some View {
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
            .buttonStyle(.glassProminent)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var saveLocationSection: some View {
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
            .buttonStyle(.glass)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var qualitySection: some View {
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
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var counterSection: some View {
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
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    // MARK: - Region Selector

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
