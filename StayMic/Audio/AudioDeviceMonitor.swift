import CoreAudio
import Combine
import Foundation

/// Coordinates CoreAudio state into the `[AudioInputDevice]` list the menu
/// bar UI observes, and wires CoreAudio property-listener events to the two
/// lock controllers.
///
/// This is the only type that talks to both CoreAudio (`CoreAudioManager`,
/// `CoreAudioPropertyListener`) and the lock controllers — everything is
/// driven by listener callbacks, never by polling. Not actor-isolated: every
/// mutation happens on the main thread by construction, since every
/// listener below is registered on `DispatchQueue.main` and UI actions run
/// on the main thread.
final class AudioDeviceMonitor: ObservableObject {
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var defaultInputDeviceUID: String?

    private let preferences: PreferencesStore
    let volumeLockController: VolumeLockController
    let deviceLockController: InputDeviceLockController

    private var deviceListListener: CoreAudioPropertyListener?
    private var defaultDeviceListener: CoreAudioPropertyListener?
    private var volumeListeners: [AudioDeviceID: CoreAudioPropertyListener] = [:]

    init(preferences: PreferencesStore = .shared) {
        self.preferences = preferences
        self.volumeLockController = VolumeLockController(preferences: preferences)
        self.deviceLockController = InputDeviceLockController(preferences: preferences)

        volumeLockController.writeVolume = { [weak self] uid, value in
            self?.writeVolume(uid: uid, value: value)
        }
        deviceLockController.restoreDefaultDevice = { [weak self] uid in
            self?.restoreDefaultDevice(uid: uid)
        }

        startSystemListeners()
        rebuildDeviceList()
    }

    // MARK: - System-level listeners

    private func startSystemListeners() {
        let deviceListListener = CoreAudioPropertyListener(
            objectID: CoreAudioManager.systemObjectID,
            selector: kAudioHardwarePropertyDevices
        ) { [weak self] in
            self?.handleDeviceListChanged()
        }
        deviceListListener.start()
        self.deviceListListener = deviceListListener

        let defaultDeviceListener = CoreAudioPropertyListener(
            objectID: CoreAudioManager.systemObjectID,
            selector: kAudioHardwarePropertyDefaultInputDevice
        ) { [weak self] in
            self?.handleDefaultInputChanged()
        }
        defaultDeviceListener.start()
        self.defaultDeviceListener = defaultDeviceListener
    }

    private func attachVolumeListenerIfNeeded(deviceID: AudioDeviceID, uid: String, elements: [AudioObjectPropertyElement]) {
        guard !elements.isEmpty, volumeListeners[deviceID] == nil else { return }

        let listener = CoreAudioPropertyListener(
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeInput,
            element: kAudioObjectPropertyElementWildcard
        ) { [weak self] in
            self?.handleVolumeChanged(deviceID: deviceID, uid: uid)
        }

        if listener.start() {
            volumeListeners[deviceID] = listener
            Log.audio.debug("Listener attached for input volume on \(uid, privacy: .public)")
        }
    }

    // MARK: - Event handlers

    private func handleDeviceListChanged() {
        let previouslyConnected = Set(devices.filter(\.isConnected).map(\.uid))
        rebuildDeviceList()
        let nowConnected = Set(devices.filter(\.isConnected).map(\.uid))

        for uid in nowConnected.subtracting(previouslyConnected) {
            handleDeviceReconnected(uid: uid)
        }
    }

    private func handleDefaultInputChanged() {
        let newDeviceID = CoreAudioManager.defaultInputDeviceID()
        let newUID = newDeviceID.flatMap { CoreAudioManager.deviceUID($0) }
        Log.audio.notice("Default input changed to \(newUID ?? "unknown", privacy: .public)")

        for index in devices.indices {
            devices[index].isDefaultInput = devices[index].uid == newUID
        }
        defaultInputDeviceUID = newUID

        deviceLockController.handleDefaultChanged(newUID: newUID)
    }

    private func handleVolumeChanged(deviceID: AudioDeviceID, uid: String) {
        let elements = CoreAudioManager.volumeElements(for: deviceID)
        guard let newValue = CoreAudioManager.aggregateVolume(deviceID, elements: elements) else { return }

        updateDevice(uid: uid) { $0.volume = newValue }
        Log.audio.debug("Input volume changed for \(uid, privacy: .public): \(newValue)")

        volumeLockController.handleVolumeChanged(uid: uid, newValue: newValue)
    }

    private func handleDeviceReconnected(uid: String) {
        Log.audio.notice("Input device reconnected: \(uid, privacy: .public)")

        if preferences.restoreDefaultAfterReconnect, deviceLockController.lockedUID == uid {
            restoreDefaultDevice(uid: uid)
        }

        if preferences.restoreVolumeAfterReconnect,
           volumeLockController.isLockEnabled(for: uid),
           let lockedVolume = volumeLockController.lockedVolume(for: uid) {
            writeVolume(uid: uid, value: lockedVolume)
        }
    }

    // MARK: - CoreAudio writes (used as controller callbacks and by the UI)

    private func writeVolume(uid: String, value: Float) {
        guard let deviceID = CoreAudioManager.deviceID(forUID: uid) else { return }
        let elements = CoreAudioManager.volumeElements(for: deviceID)
        CoreAudioManager.setAggregateVolume(deviceID, elements: elements, value: value)
        updateDevice(uid: uid) { $0.volume = value }
        Log.volumeLock.notice("Locked input volume restored for \(uid, privacy: .public): \(value)")
    }

    private func restoreDefaultDevice(uid: String) {
        guard let deviceID = CoreAudioManager.deviceID(forUID: uid) else { return }
        CoreAudioManager.setDefaultInputDevice(deviceID)
        for index in devices.indices {
            devices[index].isDefaultInput = devices[index].uid == uid
        }
        defaultInputDeviceUID = uid
        Log.deviceLock.notice("Default input restored to \(uid, privacy: .public)")
    }

    private func updateDevice(uid: String, _ mutate: (inout AudioInputDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.uid == uid }) else { return }
        mutate(&devices[index])
    }

    // MARK: - Device list construction

    private func rebuildDeviceList() {
        let liveDeviceIDs = CoreAudioManager.allDeviceIDs().filter(CoreAudioManager.isInputDevice)
        let defaultDeviceID = CoreAudioManager.defaultInputDeviceID()
        let defaultUID = defaultDeviceID.flatMap { CoreAudioManager.deviceUID($0) }

        var liveUIDs = Set<String>()
        var rebuilt: [AudioInputDevice] = []

        for deviceID in liveDeviceIDs {
            guard let uid = CoreAudioManager.deviceUID(deviceID) else { continue }
            liveUIDs.insert(uid)

            let name = CoreAudioManager.deviceName(deviceID)
            let elements = CoreAudioManager.volumeElements(for: deviceID)
            let volume = CoreAudioManager.aggregateVolume(deviceID, elements: elements)
            let isSettable = CoreAudioManager.isAggregateVolumeSettable(deviceID, elements: elements)
            let state = preferences.state(for: uid)

            if state.lastKnownName != name {
                preferences.updateState(for: uid) { $0.lastKnownName = name }
            }

            rebuilt.append(AudioInputDevice(
                uid: uid,
                name: name,
                deviceID: deviceID,
                isDefaultInput: uid == defaultUID,
                isConnected: true,
                volumeElements: elements,
                volume: volume,
                isVolumeSettable: isSettable,
                volumeLockEnabled: state.volumeLockEnabled,
                lockedVolume: state.lockedVolume,
                isDefaultLockEnabled: uid == deviceLockController.lockedUID
            ))

            attachVolumeListenerIfNeeded(deviceID: deviceID, uid: uid, elements: elements)
        }

        // Devices the user locked (either lock kind) that aren't currently
        // connected still get a row, so the lock's intent stays visible.
        var ghostUIDs = Set(preferences.deviceStates.filter(\.value.volumeLockEnabled).map(\.key))
        if let lockedUID = deviceLockController.lockedUID {
            ghostUIDs.insert(lockedUID)
        }
        ghostUIDs.subtract(liveUIDs)

        for uid in ghostUIDs {
            let state = preferences.state(for: uid)
            let name = state.lastKnownName ?? preferences.lockedDefaultDeviceName ?? "Unknown Microphone"
            rebuilt.append(AudioInputDevice(
                uid: uid,
                name: name,
                deviceID: nil,
                isDefaultInput: false,
                isConnected: false,
                volumeElements: [],
                volume: nil,
                isVolumeSettable: false,
                volumeLockEnabled: state.volumeLockEnabled,
                lockedVolume: state.lockedVolume,
                isDefaultLockEnabled: uid == deviceLockController.lockedUID
            ))
        }

        for staleDeviceID in volumeListeners.keys where !liveDeviceIDs.contains(staleDeviceID) {
            volumeListeners[staleDeviceID]?.stop()
            volumeListeners.removeValue(forKey: staleDeviceID)
        }

        devices = rebuilt.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected && !rhs.isConnected }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        defaultInputDeviceUID = defaultUID
    }

    // MARK: - UI-facing actions

    /// The user dragged StayMic's own volume slider. The menu bar disables
    /// the slider while the volume lock is on, so this guard is a defense in
    /// depth: a locked device's target only ever changes by unlocking,
    /// adjusting, and re-locking -- never implicitly through a drag that
    /// could race a lock-driven restore.
    func userDidChangeVolume(uid: String, value: Float) {
        guard !volumeLockController.isLockEnabled(for: uid) else { return }
        guard let deviceID = CoreAudioManager.deviceID(forUID: uid) else { return }
        let elements = CoreAudioManager.volumeElements(for: deviceID)
        CoreAudioManager.setAggregateVolume(deviceID, elements: elements, value: value)
        updateDevice(uid: uid) { $0.volume = value }
    }

    func setVolumeLockEnabled(_ enabled: Bool, uid: String) {
        let currentVolume = devices.first(where: { $0.uid == uid })?.volume
        volumeLockController.setLockEnabled(enabled, for: uid, currentVolume: currentVolume)
        updateDevice(uid: uid) {
            $0.volumeLockEnabled = enabled
            $0.lockedVolume = volumeLockController.lockedVolume(for: uid)
        }
    }

    /// The user picked a microphone as default from inside StayMic. Always
    /// wins over CoreAudio's last-reported state, and re-points an active
    /// microphone lock rather than triggering a revert.
    func userDidSelectDefaultDevice(uid: String) {
        guard let device = devices.first(where: { $0.uid == uid }), let deviceID = device.deviceID else { return }

        CoreAudioManager.setDefaultInputDevice(deviceID)
        for index in devices.indices {
            devices[index].isDefaultInput = devices[index].uid == uid
        }
        defaultInputDeviceUID = uid

        deviceLockController.userDidSelectDefault(uid: uid, displayName: device.name)
        refreshDefaultLockFlags()
    }

    func setDefaultLockEnabled(_ enabled: Bool, uid: String) {
        guard let device = devices.first(where: { $0.uid == uid }) else { return }

        if enabled {
            deviceLockController.setLocked(uid: uid, displayName: device.name)
            if defaultInputDeviceUID != uid, let deviceID = device.deviceID {
                CoreAudioManager.setDefaultInputDevice(deviceID)
                for index in devices.indices {
                    devices[index].isDefaultInput = devices[index].uid == uid
                }
                defaultInputDeviceUID = uid
            }
        } else {
            deviceLockController.clearLock()
        }

        refreshDefaultLockFlags()
    }

    private func refreshDefaultLockFlags() {
        let lockedUID = deviceLockController.lockedUID
        for index in devices.indices {
            devices[index].isDefaultLockEnabled = devices[index].uid == lockedUID
        }
    }

    /// Clears all persisted lock state for a device. Ghost rows (locked but
    /// disconnected) have no other way to be un-locked from the UI, since a
    /// disconnected device can't be unchecked via its own row controls.
    func forgetDevice(uid: String) {
        volumeLockController.setLockEnabled(false, for: uid, currentVolume: nil)
        volumeLockController.forgetLockedVolume(for: uid)
        if deviceLockController.lockedUID == uid {
            deviceLockController.clearLock()
        }

        guard let index = devices.firstIndex(where: { $0.uid == uid }) else { return }
        if devices[index].isConnected {
            devices[index].volumeLockEnabled = false
            devices[index].lockedVolume = nil
            devices[index].isDefaultLockEnabled = false
        } else {
            devices.remove(at: index)
        }
    }
}
