import Foundation

/// Enforces the "Keep as Microphone" (default input device) lock.
///
/// Independent from `VolumeLockController` by design: a device can have
/// either lock, both, or neither. This controller only decides whether the
/// system default input needs restoring; `AudioDeviceMonitor` performs the
/// actual CoreAudio write.
final class InputDeviceLockController {
    private let preferences: PreferencesStore

    /// Injected by `AudioDeviceMonitor`: makes the device identified by
    /// `uid` the system default input, if it is currently connected.
    var restoreDefaultDevice: ((_ uid: String) -> Void)?

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    var lockedUID: String? { preferences.lockedDefaultDeviceUID }

    func setLocked(uid: String, displayName: String) {
        preferences.lockedDefaultDeviceUID = uid
        preferences.lockedDefaultDeviceName = displayName
        Log.deviceLock.notice("Microphone lock enabled for \(uid, privacy: .public)")
    }

    func clearLock() {
        Log.deviceLock.notice("Microphone lock disabled")
        preferences.lockedDefaultDeviceUID = nil
        preferences.lockedDefaultDeviceName = nil
    }

    /// The user picked a different default microphone from inside StayMic
    /// while a lock was active. Re-point the lock rather than let the next
    /// default-changed event fight the user's own choice.
    func userDidSelectDefault(uid: String, displayName: String) {
        guard preferences.lockedDefaultDeviceUID != nil else { return }
        setLocked(uid: uid, displayName: displayName)
    }

    /// Called for every CoreAudio default-input-changed event.
    func handleDefaultChanged(newUID: String?) {
        guard let lockedUID = preferences.lockedDefaultDeviceUID, newUID != lockedUID else { return }
        Log.deviceLock.notice("Restoring locked microphone: \(newUID ?? "none", privacy: .public) -> \(lockedUID, privacy: .public)")
        restoreDefaultDevice?(lockedUID)
    }
}
