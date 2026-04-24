import SwiftUI

struct FramedMenuView: View {
    @ObservedObject var model: FramedMenuModel
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Section("Aspect Ratio") {
            ForEach(AspectRatioPreset.allCases) { preset in
                Button {
                    model.selectPreset(preset)
                } label: {
                    if model.selectedPreset == preset {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
            }
        }

        Section("Visible Windows") {
            if model.visibleWindows.isEmpty {
                Text("No visible windows found.")
            } else {
                ForEach(model.visibleWindows) { window in
                    Button {
                        model.apply(to: window)
                    } label: {
                        if model.selectedWindowID == window.id {
                            Label(window.displayName, systemImage: "checkmark")
                        } else {
                            Text(window.displayName)
                        }
                    }
                }
            }

            Button("Refresh Windows") {
                model.refreshVisibleWindows()
            }
        }

        Section("Status") {
            Text("Default ratio: \(model.selectedPreset.title)")
            Text(model.permissionMessage())
            Text(model.statusMessage)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !model.hasAccessibilityPermission {
            Button("Grant Accessibility Access") {
                model.requestAccessibilityPermission()
            }

            Button("Open Accessibility Settings") {
                model.openAccessibilitySettings()
            }
        }

        Divider()

        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)

        Button("Quit Framed") {
            NSApplication.shared.terminate(nil)
        }
        .onAppear {
            model.refreshVisibleWindows()
        }
    }
}
