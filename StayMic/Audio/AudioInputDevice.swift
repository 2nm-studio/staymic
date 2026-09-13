import CoreAudio
import Foundation

/// A snapshot of one microphone/input device, as shown in the menu bar list.
///
/// This is a value type rebuilt from CoreAudio state whenever something
/// changes; it never talks to CoreAudio itself (see `CoreAudioManager` and
/// `AudioDeviceMonitor` for that).
struct AudioInputDevice: Identifiable, Equatable {
    /// Stable across reconnects; used for persistence and equality of "the
    /// same physical/virtual microphone". `AudioDeviceID` is not stable
    /// across reconnects and is only meaningful while the device is live.
    let uid: String
    var id: String { uid }

    var name: String
    var deviceID: AudioDeviceID?
    var isDefaultInput: Bool
    var isConnected: Bool

    /// The elements CoreAudio exposes an input-volume control on. Empty
    /// means the device has no software-adjustable input volume.
    var volumeElements: [AudioObjectPropertyElement]
    var volume: Float?
    var isVolumeSettable: Bool

    var volumeLockEnabled: Bool
    var lockedVolume: Float?
    var isDefaultLockEnabled: Bool

    var supportsVolumeControl: Bool { !volumeElements.isEmpty }

    var volumePercent: Int? {
        guard let volume else { return nil }
        return Int((volume * 100).rounded())
    }
}
