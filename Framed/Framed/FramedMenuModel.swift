import AppKit
import Combine
import Foundation

@MainActor
final class FramedMenuModel: ObservableObject {
    @Published var selectedPreset: AspectRatioPreset
    @Published var selectedWidthRatio: ScreenWidthRatioPreset?
    @Published var statusMessage: String
    @Published var hasAccessibilityPermission: Bool
    @Published var visibleWindowGroups: [VisibleWindowGroup]
    @Published var selectedGroupID: VisibleWindowGroup.ID?

    private let resizer = WindowResizer()
    private let userDefaults: UserDefaults
    private let selectedPresetKey = "selectedAspectRatioPreset"
    private let selectedWidthRatioKey = "selectedScreenWidthRatioPreset"
    private var resetTask: Task<Void, Never>?
    private var permissionPollTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedPreset = userDefaults.string(forKey: selectedPresetKey)
            .flatMap(AspectRatioPreset.init(rawValue:))
        let storedWidthRatio = userDefaults.string(forKey: selectedWidthRatioKey)
            .flatMap(ScreenWidthRatioPreset.init(rawValue:))
        let initialWindows = resizer.visibleWindows()
        self.selectedPreset = storedPreset ?? .default
        self.selectedWidthRatio = storedWidthRatio
        self.hasAccessibilityPermission = resizer.accessibilityPermissionGranted()
        self.visibleWindowGroups = VisibleWindowGroup.groups(from: initialWindows)
        self.selectedGroupID = nil
        self.statusMessage = "Choose a ratio, then choose an application group."

        logRuntimeIdentity()
        startPermissionPolling()
    }

    deinit {
        resetTask?.cancel()
        permissionPollTask?.cancel()
    }

    func selectPreset(_ preset: AspectRatioPreset) {
        selectedPreset = preset
        userDefaults.set(preset.rawValue, forKey: selectedPresetKey)
    }

    func selectWidthRatio(_ preset: ScreenWidthRatioPreset?) {
        selectedWidthRatio = preset

        if let preset {
            userDefaults.set(preset.rawValue, forKey: selectedWidthRatioKey)
        } else {
            userDefaults.removeObject(forKey: selectedWidthRatioKey)
        }
    }

    func refreshVisibleWindows() {
        let windows = resizer.visibleWindows()
        visibleWindowGroups = VisibleWindowGroup.groups(from: windows)

        if let selectedGroupID, !visibleWindowGroups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = nil
        }
    }

    func apply(to group: VisibleWindowGroup) {
        var results: [ResizeResult] = []
        var permissionGranted = true

        for window in group.windows {
            let result = resizer.resize(window, to: selectedPreset, widthRatio: selectedWidthRatio?.ratio)
            results.append(result)

            if result.requiresAccessibilityPermission {
                permissionGranted = false
                break
            }
        }

        let summary = WindowGroupResizeSummary(
            appName: group.ownerName,
            windowCount: group.windowCount,
            preset: selectedPreset,
            results: results
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.selectedGroupID = group.id
            self.hasAccessibilityPermission = permissionGranted && self.resizer.accessibilityPermissionGranted()
            self.updateStatus(using: summary.message, resetOnSuccess: summary.completedCount > 0)
            self.refreshVisibleWindows()
        }
    }

    func permissionMessage() -> String {
        hasAccessibilityPermission
            ? "Accessibility access is enabled."
            : "Accessibility access is required."
    }

    func openAccessibilitySettings() {
        let granted = resizer.requestAccessibilityPermission()
        hasAccessibilityPermission = granted

        if granted {
            updateStatus(using: "Accessibility access is enabled.", resetOnSuccess: false)
            return
        }

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        updateStatus(using: "Grant Accessibility access, then relaunch Framed.", resetOnSuccess: false)
        NSWorkspace.shared.open(url)
    }

    private func updateStatus(using message: String, resetOnSuccess: Bool) {
        statusMessage = message
        resetTask?.cancel()

        guard resetOnSuccess, message.hasPrefix("Resized") else {
            return
        }

        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            statusMessage = "Choose a ratio, then choose an application group."
        }
    }

    private func startPermissionPolling() {
        permissionPollTask = Task { @MainActor in
            while !Task.isCancelled {
                hasAccessibilityPermission = resizer.accessibilityPermissionGranted()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func logRuntimeIdentity() {
        let bundle = Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let bundlePath = bundle.bundleURL.path
        let executablePath = bundle.executableURL?.path ?? "unknown"
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        FramedDiagnostics.shared.log("Runtime identity bundleID=\(bundleID) version=\(shortVersion) build=\(buildVersion) bundlePath=\(bundlePath) executablePath=\(executablePath).")
    }
}
