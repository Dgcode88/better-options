import AppKit
import CoreGraphics
import Foundation

final class WisprIntegration {
    enum PTTBindingState: Equatable {
        case configured
        case missingConfig
        case bindingMismatch
        case invalidConfig
    }

    enum PTTDispatchStrategy: Equatable {
        case functionKey
        case mouseButton4099
    }

    typealias Callback = () -> Void

    private let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Wispr Flow/config.json")
    private let bundleIdentifier = "com.electron.wispr-flow"

    var onStateChange: Callback?
    private(set) var pttBindingState: PTTBindingState = .missingConfig
    private(set) var dispatchStrategy: PTTDispatchStrategy = .mouseButton4099

    var runningPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.processIdentifier
    }

    func refreshConfiguration() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            pttBindingState = .missingConfig
            onStateChange?()
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            let object = try JSONSerialization.jsonObject(with: data)
            let shortcuts = findShortcuts(in: object)
            let hasMousePTT = shortcuts?["4099"] as? String == "ptt"
            let hasFunctionPTT = shortcuts?["63"] as? String == "ptt"

            if hasFunctionPTT {
                dispatchStrategy = .functionKey
            } else {
                dispatchStrategy = .mouseButton4099
            }

            if hasMousePTT || hasFunctionPTT {
                pttBindingState = .configured
            } else {
                pttBindingState = .bindingMismatch
            }
        } catch {
            pttBindingState = .invalidConfig
            dispatchStrategy = .mouseButton4099
        }

        onStateChange?()
    }

    func dispatchPTTEvent(pressed: Bool, location: CGPoint) {
        switch dispatchStrategy {
        case .functionKey:
            postFunctionKeyEvent(pressed: pressed)
        case .mouseButton4099:
            guard let pid = runningPID else {
                return
            }

            postPTTMouseButtonEvent(to: pid, pressed: pressed, buttonNumber: 3, location: location)
        }
    }

    private func postPTTMouseButtonEvent(to pid: pid_t, pressed: Bool, buttonNumber: Int64, location: CGPoint) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let type: CGEventType = pressed ? .otherMouseDown : .otherMouseUp
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .center) else {
            return
        }

        event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        event.postToPid(pid)
    }

    private func postFunctionKeyEvent(pressed: Bool) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0x3F,
                keyDown: pressed
              ) else {
            return
        }

        event.flags = pressed ? .maskSecondaryFn : []
        event.post(tap: .cghidEventTap)
    }

    private func findShortcuts(in object: Any) -> [String: Any]? {
        if let dictionary = object as? [String: Any] {
            if let shortcuts = dictionary["shortcuts"] as? [String: Any] {
                return shortcuts
            }

            for value in dictionary.values {
                if let result = findShortcuts(in: value) {
                    return result
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let result = findShortcuts(in: value) {
                    return result
                }
            }
        }

        return nil
    }
}
