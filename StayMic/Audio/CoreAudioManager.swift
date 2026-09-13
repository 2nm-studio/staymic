import CoreAudio
import Foundation

/// Thin, stateless wrapper around the CoreAudio `AudioObject` property APIs.
///
/// Every function here is a direct `AudioObjectGetPropertyData` /
/// `AudioObjectSetPropertyData` call. Nothing in this file polls — callers
/// (`AudioDeviceMonitor`, the lock controllers) decide *when* to call based
/// on CoreAudio property-listener callbacks.
enum CoreAudioManager {
    static let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

    // MARK: - Device enumeration

    static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }
        return deviceIDs
    }

    /// Number of input channels exposed by `deviceID`. Zero means the device
    /// has no input streams (e.g. it's output-only).
    static func inputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawPointer)
        guard status == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(rawPointer.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        inputChannelCount(deviceID) > 0
    }

    // MARK: - Identity

    static func deviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (name as String) : "Unknown Microphone"
    }

    static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (uid as String) : nil
    }

    /// Resolves a persisted device UID back to a live `AudioDeviceID`.
    /// Returns `nil` when the device isn't currently connected.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { deviceUID($0) == uid }
    }

    // MARK: - Input volume

    /// The property elements (master, or individual channels) that carry a
    /// readable input-volume control on this device.
    ///
    /// Preference order: a single master/main element if the device exposes
    /// one, otherwise every individual input channel that exposes volume.
    static func volumeElements(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] {
        if hasVolumeProperty(deviceID, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }

        let channelCount = inputChannelCount(deviceID)
        guard channelCount > 0 else { return [] }

        return (1...channelCount).map(AudioObjectPropertyElement.init).filter {
            hasVolumeProperty(deviceID, element: $0)
        }
    }

    static func hasVolumeProperty(_ deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        return AudioObjectHasProperty(deviceID, &address)
    }

    static func isVolumeSettable(_ deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    static func volume(_ deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    @discardableResult
    static func setVolume(_ deviceID: AudioDeviceID, element: AudioObjectPropertyElement, value: Float) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        var newValue = max(0, min(1, value))
        let size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &newValue)
        return status == noErr
    }

    /// Reads a single logical volume for a device that may expose several
    /// volume-carrying elements (e.g. per-channel controls instead of one
    /// master control), by averaging whatever is currently readable.
    static func aggregateVolume(_ deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]) -> Float? {
        let values = elements.compactMap { volume(deviceID, element: $0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    static func isAggregateVolumeSettable(_ deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement]) -> Bool {
        !elements.isEmpty && elements.contains { isVolumeSettable(deviceID, element: $0) }
    }

    /// Writes `value` to every settable element, so a device with several
    /// input-volume channels still behaves like one logical control.
    @discardableResult
    static func setAggregateVolume(_ deviceID: AudioDeviceID, elements: [AudioObjectPropertyElement], value: Float) -> Bool {
        var succeededAny = false
        for element in elements where isVolumeSettable(deviceID, element: element) {
            if setVolume(deviceID, element: element, value: value) {
                succeededAny = true
            }
        }
        return succeededAny
    }

    // MARK: - Default input device

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    @discardableResult
    static func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var newDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(systemObjectID, &address, 0, nil, size, &newDeviceID)
        return status == noErr
    }
}
