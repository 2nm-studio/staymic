import CoreAudio
import Foundation

/// A single CoreAudio property listener, wrapped so it can be attached and
/// detached safely.
///
/// `AudioObjectRemovePropertyListenerBlock` only removes a listener if it is
/// given the *exact same block instance* that was passed to
/// `AudioObjectAddPropertyListenerBlock`. This type stores that block so
/// `stop()`/`deinit` always unregister cleanly instead of silently failing
/// and leaking a callback.
final class CoreAudioPropertyListener {
    private let objectID: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let handler: () -> Void
    private var attachedBlock: AudioObjectPropertyListenerBlock?

    init(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        queue: DispatchQueue = .main,
        handler: @escaping () -> Void
    ) {
        self.objectID = objectID
        self.address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        self.queue = queue
        self.handler = handler
    }

    /// Whether `objectID` currently has the property this listener targets.
    /// Some properties (notably per-channel volume) don't exist on every
    /// device, and adding a listener for a nonexistent property fails.
    var isPropertyAvailable: Bool {
        AudioObjectHasProperty(objectID, &address)
    }

    @discardableResult
    func start() -> Bool {
        guard attachedBlock == nil else { return true }
        let block: AudioObjectPropertyListenerBlock = { [handler] _, _ in
            handler()
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)
        guard status == noErr else {
            Log.audio.error("Failed to attach listener (selector: \(self.address.mSelector, privacy: .public), object: \(self.objectID)): OSStatus \(status)")
            return false
        }
        attachedBlock = block
        return true
    }

    func stop() {
        guard let block = attachedBlock else { return }
        let status = AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
        if status != noErr {
            Log.audio.error("Failed to remove listener (selector: \(self.address.mSelector, privacy: .public), object: \(self.objectID)): OSStatus \(status)")
        }
        attachedBlock = nil
    }

    deinit {
        stop()
    }
}
