import CoreMIDI
import Foundation

/// Thin CoreMIDI wrapper: lists MIDI destinations (USB MIDI devices such as the
/// OX Stomp show up here when plugged into the iPhone's USB-C port) and sends
/// raw MIDI bytes to one of them.
final class MIDIBridge {
    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()

    /// Called on the main thread whenever a MIDI device is plugged in or removed.
    var onSetupChanged: (() -> Void)?

    init() {
        let status = MIDIClientCreateWithBlock("OXStomp" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.onSetupChanged?() }
            }
        }
        if status != noErr { NSLog("MIDIClientCreate failed: \(status)") }
        MIDIOutputPortCreate(client, "OXStomp Out" as CFString, &outPort)
    }

    /// Every MIDI destination iOS currently sees, as id/name pairs for the web page.
    func destinations() -> [[String: String]] {
        var result: [[String: String]] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            guard endpoint != 0 else { continue }
            var uid: Int32 = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uid)
            result.append([
                "id": String(uid),
                "name": stringProperty(endpoint, kMIDIPropertyDisplayName),
                "manufacturer": stringProperty(endpoint, kMIDIPropertyManufacturer),
            ])
        }
        return result
    }

    /// Send raw MIDI bytes (e.g. [0xB0, 44, 100] for a CC) to the destination with this unique ID.
    func send(toUniqueID uid: Int32, bytes: [UInt8]) {
        guard !bytes.isEmpty, bytes.count <= 256 else { return }
        var object: MIDIObjectRef = 0
        var type: MIDIObjectType = .other
        guard MIDIObjectFindByUniqueID(uid, &object, &type) == noErr,
              type == .destination || type == .externalDestination else {
            NSLog("MIDI destination \(uid) not found")
            return
        }
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        _ = MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, bytes)
        let status = MIDISend(outPort, object, &packetList)
        if status != noErr { NSLog("MIDISend failed: \(status)") }
    }

    private func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr,
              let string = value?.takeRetainedValue() else { return "" }
        return string as String
    }
}
