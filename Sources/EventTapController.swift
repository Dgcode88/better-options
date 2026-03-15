import ApplicationServices
import CoreGraphics
import Foundation

final class EventTapController {
    typealias Callback = () -> Void

    private let deviceMonitor: HIDDeviceMonitor
    private let wisprIntegration: WisprIntegration
    private let mediaKeySender: MediaKeySender

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onStateChange: Callback?
    var isEnabled = true

    init(deviceMonitor: HIDDeviceMonitor, wisprIntegration: WisprIntegration, mediaKeySender: MediaKeySender) {
        self.deviceMonitor = deviceMonitor
        self.wisprIntegration = wisprIntegration
        self.mediaKeySender = mediaKeySender
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    var isTapInstalled: Bool {
        eventTap != nil
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard hasAccessibilityPermission else {
            onStateChange?()
            return
        }

        installTapIfNeeded()
        onStateChange?()
    }

    private func installTapIfNeeded() {
        guard eventTap == nil else {
            return
        }

        let mask =
            CGEventMask(1 << CGEventType.scrollWheel.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue) |
            CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: context
        ) else {
            onStateChange?()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        case .scrollWheel:
            return handleScroll(event)
        case .otherMouseDown:
            return handlePotentialPTTMouseEvent(event, pressed: true)
        case .otherMouseUp:
            return handlePotentialPTTMouseEvent(event, pressed: false)
        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled, deviceMonitor.hasMatchedDevice else {
            return Unmanaged.passRetained(event)
        }

        let horizontalDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        guard horizontalDelta != 0 else {
            return Unmanaged.passRetained(event)
        }

        guard deviceMonitor.sawRecentThumbWheelEvent(within: 0.08) else {
            return Unmanaged.passRetained(event)
        }

        if horizontalDelta > 0 {
            mediaKeySender.sendVolumeDown()
        } else {
            mediaKeySender.sendVolumeUp()
        }
        return nil
    }

    private func handlePotentialPTTMouseEvent(_ event: CGEvent, pressed: Bool) -> Unmanaged<CGEvent>? {
        guard isEnabled, deviceMonitor.hasMatchedDevice else {
            return Unmanaged.passRetained(event)
        }

        guard wisprIntegration.runningPID != nil,
              wisprIntegration.pttBindingState == .configured else {
            return Unmanaged.passRetained(event)
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        guard buttonNumber >= 3 else {
            return Unmanaged.passRetained(event)
        }

        return deviceMonitor.sawRecentPTTButtonEvent(isPressed: pressed, within: 0.08)
            ? nil
            : Unmanaged.passRetained(event)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passRetained(event)
        }

        let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handle(type: type, event: event)
    }
}
