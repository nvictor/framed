import SwiftUI

struct FramedMenuView: View {
    @ObservedObject var model: FramedMenuModel
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Section("Aspect Ratio") {
            ForEach(AspectRatioPreset.allCases) { preset in
                Toggle(isOn: Binding(
                    get: { model.selectedPreset == preset },
                    set: { _ in model.selectPreset(preset) }
                )) {
                    Text(preset.title)
                }
            }
        }

        Section("Width") {
            Toggle(isOn: Binding(
                get: { model.selectedWidthRatio == nil },
                set: { _ in model.selectWidthRatio(nil) }
            )) {
                Text("Current Width")
            }

            ForEach(ScreenWidthRatioPreset.allCases) { preset in
                Toggle(isOn: Binding(
                    get: { model.selectedWidthRatio == preset },
                    set: { _ in model.selectWidthRatio(preset) }
                )) {
                    Text(preset.title)
                }
            }
        }

        Section("Application Groups") {
            if model.visibleWindowGroups.isEmpty {
                Text("No application groups found.")
            } else {
                ForEach(model.visibleWindowGroups) { group in
                    Toggle(isOn: Binding(
                        get: { model.selectedGroupID == group.id },
                        set: { _ in model.apply(to: group) }
                    )) {
                        Text(group.menuDisplayName)
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
