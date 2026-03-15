import AppKit

final class MediaKeySender {
    private enum KeyCode {
        static let soundUp = 0
        static let soundDown = 1
    }

    func sendVolumeUp() {
        sendMediaKey(KeyCode.soundUp)
    }

    func sendVolumeDown() {
        sendMediaKey(KeyCode.soundDown)
    }

    private func sendMediaKey(_ keyCode: Int) {
        postSystemDefinedEvent(keyCode: keyCode, isDown: true)
        postSystemDefinedEvent(keyCode: keyCode, isDown: false)
    }

    private func postSystemDefinedEvent(keyCode: Int, isDown: Bool) {
        let keyState = isDown ? 0xA : 0xB
        let data1 = (keyCode << 16) | (keyState << 8)

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else {
            return
        }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
