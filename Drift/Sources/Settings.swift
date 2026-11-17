import Cocoa

extension Notification.Name {
    static let driftSettingsChanged = Notification.Name("DriftSettingsChanged")
}

enum Mode: String, CaseIterable {
    case snow, rain, leaves, sakura, fireflies, starfall

    var title: String {
        switch self {
        case .snow: return "Snow"
        case .rain: return "Rain"
        case .leaves: return "Autumn Leaves"
        case .sakura: return "Sakura"
        case .fireflies: return "Fireflies"
        case .starfall: return "Starfall"
        }
    }

    var symbol: String {
        switch self {
        case .snow: return "snowflake"
        case .rain: return "cloud.rain"
        case .leaves: return "leaf"
        case .sakura: return "camera.macro"
        case .fireflies: return "sparkle"
        case .starfall: return "moon.stars"
        }
    }

    var image: NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: "snowflake", accessibilityDescription: title)
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "mode": Mode.snow.rawValue,
            "intensity": 1.0,
            "wind": 0.15,
            "pileOnWindows": true,
            "snowOnDock": true,
            "behindWindows": false,
            "cursor": true,
            "batterySaver": true,
            "snowplay": true,
            "santaVisits": true,
        ])
    }

    var mode: Mode {
        get { Mode(rawValue: d.string(forKey: "mode") ?? "") ?? .snow }
        set { d.set(newValue.rawValue, forKey: "mode"); post() }
    }
    var intensity: Double {
        get { d.double(forKey: "intensity") }
        set { d.set(newValue, forKey: "intensity"); post() }
    }
    var wind: Double {
        get { d.double(forKey: "wind") }
        set { d.set(newValue, forKey: "wind"); post() }
    }
    var pileOnWindows: Bool {
        get { d.bool(forKey: "pileOnWindows") }
        set { d.set(newValue, forKey: "pileOnWindows"); post() }
    }
    var snowOnDock: Bool {
        get { d.bool(forKey: "snowOnDock") }
        set { d.set(newValue, forKey: "snowOnDock"); post() }
    }
    var behindWindows: Bool {
        get { d.bool(forKey: "behindWindows") }
        set { d.set(newValue, forKey: "behindWindows"); post() }
    }
    var cursorInteraction: Bool {
        get { d.bool(forKey: "cursor") }
        set { d.set(newValue, forKey: "cursor"); post() }
    }
    var batterySaver: Bool {
        get { d.bool(forKey: "batterySaver") }
        set { d.set(newValue, forKey: "batterySaver"); post() }
    }
    var snowplay: Bool {
        get { d.bool(forKey: "snowplay") }
        set { d.set(newValue, forKey: "snowplay"); post() }
    }
    var santaVisits: Bool {
        get { d.bool(forKey: "santaVisits") }
        set { d.set(newValue, forKey: "santaVisits"); post() }
    }
    var paused = false { didSet { post() } }

    private func post() {
        NotificationCenter.default.post(name: .driftSettingsChanged, object: nil)
    }
}
