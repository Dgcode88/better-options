import Foundation
import IOKit.hid

final class HIDDeviceMonitor {
    typealias Callback = () -> Void
    typealias PTTButtonCallback = (_ isPressed: Bool, _ usage: UInt32) -> Void

    private let manager: IOHIDManager
    private let callbackQueue = DispatchQueue(label: "logiremap.hid-monitor")
    private let acceptedNames = [
        "MX Master 3 Mac",
        "MX Master 3",
        "MX Master 3 for Mac",
    ]
    private let excludedNameFragments = [
        "3S",
    ]
    private let thumbWheelUsages: Set<UsageKey> = [
        UsageKey(page: UInt32(kHIDPage_Consumer), usage: UInt32(kHIDUsage_Csmr_ACPan)),
        UsageKey(page: UInt32(kHIDPage_Consumer), usage: UInt32(kHIDUsage_Csmr_ACPanLeft)),
        UsageKey(page: UInt32(kHIDPage_Consumer), usage: UInt32(kHIDUsage_Csmr_ACPanRight)),
    ]
    private let pttCandidateButtonUsages = Set(UInt32(6)...UInt32(16))

    private var trackedDevices: [OpaquePointer: DeviceInfo] = [:]
    private let lock = NSLock()
    private var lastThumbWheelEventAt: UInt64 = 0
    private var lastPTTDownAt: UInt64 = 0
    private var lastPTTUpAt: UInt64 = 0
    private var lastObservedPTTUsage: UInt32?

    var onStateChange: Callback?
    var onPTTButtonEvent: PTTButtonCallback?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    var hasMatchedDevice: Bool {
        lock.withLock {
            !trackedDevices.isEmpty
        }
    }

    var activeDeviceName: String? {
        lock.withLock {
            trackedDevices.values.first?.productName
        }
    }

    func start() {
        let matching: [[String: Any]] = [[
            kIOHIDVendorIDKey as String: 0x046D,
        ]]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.handleDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.handleDeviceRemoved, context)
        IOHIDManagerRegisterInputValueCallback(manager, Self.handleInputValue, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        if let currentDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in currentDevices {
                registerIfRelevant(device)
            }
        }
    }

    func sawRecentThumbWheelEvent(within seconds: TimeInterval) -> Bool {
        recentEvent(lastThumbWheelEventAt, within: seconds)
    }

    func sawRecentPTTButtonEvent(isPressed: Bool, within seconds: TimeInterval) -> Bool {
        recentEvent(isPressed ? lastPTTDownAt : lastPTTUpAt, within: seconds)
    }

    var lastObservedPTTButtonUsage: UInt32? {
        lock.withLock {
            lastObservedPTTUsage
        }
    }

    private func recentEvent(_ timestamp: UInt64, within seconds: TimeInterval) -> Bool {
        guard timestamp > 0 else {
            return false
        }

        let window = UInt64(seconds * 1_000_000_000)
        return DispatchTime.now().uptimeNanoseconds &- timestamp <= window
    }

    private func registerIfRelevant(_ device: IOHIDDevice) {
        guard let productName = propertyString(kIOHIDProductKey, device: device),
              matchesAcceptedProduct(productName) else {
            return
        }

        let info = DeviceInfo(
            productName: productName,
            vendorID: propertyInt(kIOHIDVendorIDKey, device: device),
            productID: propertyInt(kIOHIDProductIDKey, device: device)
        )

        let key = OpaquePointer(Unmanaged.passUnretained(device).toOpaque())
        let wasInserted: Bool = lock.withLock {
            trackedDevices.updateValue(info, forKey: key) == nil
        }

        if wasInserted {
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?()
            }
        }
    }

    private func remove(_ device: IOHIDDevice) {
        let key = OpaquePointer(Unmanaged.passUnretained(device).toOpaque())
        let removed = lock.withLock {
            trackedDevices.removeValue(forKey: key) != nil
        }

        if removed {
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?()
            }
        }
    }

    private func matchesAcceptedProduct(_ productName: String) -> Bool {
        guard acceptedNames.contains(productName) else {
            return false
        }
        return !excludedNameFragments.contains(where: productName.localizedCaseInsensitiveContains)
    }

    private func recordInput(value: IOHIDValue, sender: UnsafeMutableRawPointer?) {
        guard let sender else {
            return
        }

        let deviceKey = OpaquePointer(sender)
        let isTracked = lock.withLock {
            trackedDevices[deviceKey] != nil
        }
        guard isTracked else {
            return
        }

        let element = IOHIDValueGetElement(value)
        let usage = UsageKey(
            page: IOHIDElementGetUsagePage(element),
            usage: IOHIDElementGetUsage(element)
        )
        let integerValue = IOHIDValueGetIntegerValue(value)
        let now = DispatchTime.now().uptimeNanoseconds

        var shouldDispatchPTT = false
        var pttUsage: UInt32?

        lock.withLock {
            if thumbWheelUsages.contains(usage), integerValue != 0 {
                lastThumbWheelEventAt = now
            } else if usage.page == UInt32(kHIDPage_Button), pttCandidateButtonUsages.contains(usage.usage) {
                lastObservedPTTUsage = usage.usage
                if integerValue == 0 {
                    lastPTTUpAt = now
                } else {
                    lastPTTDownAt = now
                }
                shouldDispatchPTT = true
                pttUsage = usage.usage
            }
        }

        if shouldDispatchPTT, let pttUsage {
            DispatchQueue.main.async { [weak self] in
                self?.onPTTButtonEvent?(integerValue != 0, pttUsage)
                self?.onStateChange?()
            }
        }
    }

    private func propertyString(_ key: String, device: IOHIDDevice) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }
        return value as? String
    }

    private func propertyInt(_ key: String, device: IOHIDDevice) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return nil
    }

    private static let handleDeviceMatched: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else {
            return
        }

        let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.registerIfRelevant(device)
    }

    private static let handleDeviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else {
            return
        }

        let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.remove(device)
    }

    private static let handleInputValue: IOHIDValueCallback = { context, _, sender, value in
        guard let context else {
            return
        }

        let monitor = Unmanaged<HIDDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.recordInput(value: value, sender: sender)
    }
}

private struct DeviceInfo {
    let productName: String
    let vendorID: Int?
    let productID: Int?
}

private struct UsageKey: Hashable {
    let page: UInt32
    let usage: UInt32
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
