import Foundation

/// Per-device persisted state, keyed by CoreAudio device UID (not
/// `AudioDeviceID`, which is not stable across reconnects).
struct DeviceState: Codable, Equatable {
    var volumeLockEnabled: Bool = false
    var lockedVolume: Float?
    /// Remembered so a disconnected, locked device can still show a name.
    var lastKnownName: String?
}

/// UserDefaults-backed preferences. Everything here is small enough that a
/// plain JSON blob for the per-device dictionary is simpler than several
/// parallel UserDefaults keys.
///
/// Not actor-isolated: every mutation happens on the main thread by
/// construction (CoreAudio property listeners in this app are registered on
/// `DispatchQueue.main`, and UI actions run on the main thread), which keeps
/// this type simple to call from CoreAudio's C-block callbacks.
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    private let defaults: UserDefaults

    private enum Keys {
        static let deviceStates = "deviceStates"
        static let lockedDefaultDeviceUID = "lockedDefaultDeviceUID"
        static let lockedDefaultDeviceName = "lockedDefaultDeviceName"
        static let restoreVolumeAfterReconnect = "restoreVolumeAfterReconnect"
        static let restoreDefaultAfterReconnect = "restoreDefaultAfterReconnect"
    }

    @Published private(set) var deviceStates: [String: DeviceState] {
        didSet { persistDeviceStates() }
    }

    @Published var lockedDefaultDeviceUID: String? {
        didSet { defaults.set(lockedDefaultDeviceUID, forKey: Keys.lockedDefaultDeviceUID) }
    }

    @Published var lockedDefaultDeviceName: String? {
        didSet { defaults.set(lockedDefaultDeviceName, forKey: Keys.lockedDefaultDeviceName) }
    }

    @Published var restoreVolumeAfterReconnect: Bool {
        didSet { defaults.set(restoreVolumeAfterReconnect, forKey: Keys.restoreVolumeAfterReconnect) }
    }

    @Published var restoreDefaultAfterReconnect: Bool {
        didSet { defaults.set(restoreDefaultAfterReconnect, forKey: Keys.restoreDefaultAfterReconnect) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Keys.deviceStates),
           let decoded = try? JSONDecoder().decode([String: DeviceState].self, from: data) {
            deviceStates = decoded
        } else {
            deviceStates = [:]
        }

        lockedDefaultDeviceUID = defaults.string(forKey: Keys.lockedDefaultDeviceUID)
        lockedDefaultDeviceName = defaults.string(forKey: Keys.lockedDefaultDeviceName)
        restoreVolumeAfterReconnect = defaults.object(forKey: Keys.restoreVolumeAfterReconnect) as? Bool ?? true
        restoreDefaultAfterReconnect = defaults.object(forKey: Keys.restoreDefaultAfterReconnect) as? Bool ?? true
    }

    func state(for uid: String) -> DeviceState {
        deviceStates[uid] ?? DeviceState()
    }

    func updateState(for uid: String, _ mutate: (inout DeviceState) -> Void) {
        var state = deviceStates[uid] ?? DeviceState()
        mutate(&state)
        deviceStates[uid] = state
    }

    private func persistDeviceStates() {
        guard let data = try? JSONEncoder().encode(deviceStates) else { return }
        defaults.set(data, forKey: Keys.deviceStates)
    }
}
