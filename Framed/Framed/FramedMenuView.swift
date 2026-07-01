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

        Section("Screen Width") {
            Button {
                model.selectWidthRatio(nil)
            } label: {
                if model.selectedWidthRatio == nil {
                    Label("Current Size", systemImage: "checkmark")
                } else {
                    Text("Current Size")
                }
            }

            ForEach(ScreenWidthRatioPreset.allCases) { preset in
                Button {
                    model.selectWidthRatio(preset)
                } label: {
                    if model.selectedWidthRatio == preset {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
            }
        }

        Section("Application Groups") {
            if model.visibleWindowGroups.isEmpty {
                Text("No application groups found.")
            } else {
                ForEach(model.visibleWindowGroups) { group in
                    Button {
                        model.apply(to: group)
                    } label: {
                        if model.selectedGroupID == group.id {
                            Label(group.menuDisplayName, systemImage: "checkmark")
                        } else {
                            Text(group.menuDisplayName)
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
