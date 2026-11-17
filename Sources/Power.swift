import Foundation
import IOKit.ps

/// Tracks whether we should run in a lighter mode (on battery or Low Power Mode).
final class Power {
    static let shared = Power()
    private(set) var saving = false
    private var timer: Timer?

    func start() {
        refresh()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        var onBattery = false
        if let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(snap)?.takeUnretainedValue() {
            onBattery = (type as String) == kIOPMBatteryPowerKey
        }
        let low = ProcessInfo.processInfo.isLowPowerModeEnabled
        let s = Settings.shared.batterySaver && (onBattery || low)
        if s != saving {
            saving = s
            NotificationCenter.default.post(name: .driftSettingsChanged, object: nil)
        }
    }
}
