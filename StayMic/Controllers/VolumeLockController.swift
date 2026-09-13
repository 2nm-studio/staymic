import Foundation

/// Enforces the per-device "Lock Volume" behavior.
///
/// This controller never touches CoreAudio directly — it only decides,
/// given a persisted target and an observed value, whether a restore is
/// needed. `AudioDeviceMonitor` supplies the observed values (from CoreAudio
/// property-listener callbacks) and performs the actual write through
/// `writeVolume`.
final class VolumeLockController {
    /// Values within this tolerance of the locked target are treated as
    /// already correct, so a restore is never re-issued for a value
    /// CoreAudio simply echoed back.
    private let tolerance: Float = 0.01

    private let preferences: PreferencesStore

    /// Injected by `AudioDeviceMonitor`: writes `value` to the live device
    /// identified by `uid`, if it is currently connected.
    var writeVolume: ((_ uid: String, _ value: Float) -> Void)?

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    func isLockEnabled(for uid: String) -> Bool {
        preferences.state(for: uid).volumeLockEnabled
    }

    func lockedVolume(for uid: String) -> Float? {
        preferences.state(for: uid).lockedVolume
    }

    /// Turns the lock on or off. Enabling always captures `currentVolume` as
    /// the value to protect going forward -- re-enabling a lock re-arms it at
    /// whatever the slider is at now, rather than silently resurrecting a
    /// stale target from a previous lock/unlock cycle. The menu bar disables
    /// the slider while locked, so the target only ever changes by way of an
    /// unlock-adjust-relock cycle, never while a restore could race it.
    func setLockEnabled(_ enabled: Bool, for uid: String, currentVolume: Float?) {
        preferences.updateState(for: uid) { state in
            state.volumeLockEnabled = enabled
            if enabled {
                state.lockedVolume = currentVolume
            }
        }
        Log.volumeLock.notice("Volume lock \(enabled ? "enabled" : "disabled", privacy: .public) for \(uid, privacy: .public)")
    }

    /// Called for every CoreAudio input-volume-changed event, whether or not
    /// the device is locked. Restores the locked value only when it drifted;
    /// a value that already matches (including one StayMic itself just
    /// wrote) causes no further write.
    func handleVolumeChanged(uid: String, newValue: Float) {
        let state = preferences.state(for: uid)
        guard state.volumeLockEnabled, let locked = state.lockedVolume else { return }
        guard abs(newValue - locked) > tolerance else { return }

        Log.volumeLock.notice("Restoring locked input volume for \(uid, privacy: .public): \(newValue) -> \(locked)")
        writeVolume?(uid, locked)
    }

    func forgetLockedVolume(for uid: String) {
        preferences.updateState(for: uid) { $0.lockedVolume = nil }
    }
}
