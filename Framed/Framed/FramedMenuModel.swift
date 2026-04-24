import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class FramedMenuModel: ObservableObject {
    @Published var selectedPreset: AspectRatioPreset
    @Published var statusMessage: String
    @Published var hasAccessibilityPermission: Bool
    @Published var visibleWindows: [VisibleWindow]
    @Published var selectedWindowID: CGWindowID?

    private let resizer = WindowResizer()
    private let userDefaults: UserDefaults
    private let selectedPresetKey = "selectedAspectRatioPreset"
    private var resetTask: Task<Void, Never>?
    private var permissionPollTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedPreset = userDefaults.string(forKey: selectedPresetKey)
            .flatMap(AspectRatioPreset.init(rawValue:))
        let initialWindows = resizer.visibleWindows()
        self.selectedPreset = storedPreset ?? .default
        self.hasAccessibilityPermission = resizer.accessibilityPermissionGranted()
        self.visibleWindows = initialWindows
        self.selectedWindowID = initialWindows.first?.id
        self.statusMessage = "Choose a ratio, then choose a visible window."

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

    func refreshVisibleWindows() {
        let windows = resizer.visibleWindows()
        visibleWindows = windows

        if let selectedWindowID,
           windows.contains(where: { $0.id == selectedWindowID }) {
            return
        }

        self.selectedWindowID = windows.first?.id
    }

    func apply(to window: VisibleWindow) {
        let result = resizer.resize(window, to: selectedPreset)
        let permissionGranted = resizer.accessibilityPermissionGranted()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.selectedWindowID = window.id
            self.hasAccessibilityPermission = permissionGranted
            self.updateStatus(using: result.message, resetOnSuccess: true)
            self.refreshVisibleWindows()
        }
    }

    func permissionMessage() -> String {
        hasAccessibilityPermission
            ? "Accessibility access is enabled."
            : "Accessibility access is required."
    }

    func requestAccessibilityPermission() {
        let granted = resizer.requestAccessibilityPermission()
        hasAccessibilityPermission = granted

        if granted {
            updateStatus(using: "Accessibility access is enabled.", resetOnSuccess: false)
        } else {
            updateStatus(using: "Grant Accessibility access, then relaunch Framed.", resetOnSuccess: false)
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

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
            statusMessage = "Choose a ratio, then choose a visible window."
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
