import AppKit
import ApplicationServices

@MainActor
final class AppCoordinator: NSObject {
    private let deviceMonitor = HIDDeviceMonitor()
    private let wisprIntegration = WisprIntegration()
    private let mediaKeySender = MediaKeySender()
    private lazy var eventTapController = EventTapController(
        deviceMonitor: deviceMonitor,
        wisprIntegration: wisprIntegration,
        mediaKeySender: mediaKeySender
    )

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var deviceStatusItem: NSMenuItem?
    private var remapToggleItem: NSMenuItem?
    private var permissionsItem: NSMenuItem?
    private var wisprItem: NSMenuItem?
    private var triggerItem: NSMenuItem?

    private var remappingEnabled = true {
        didSet {
            eventTapController.isEnabled = remappingEnabled
            updateMenu()
        }
    }

    func start() {
        buildMenu()
        wireCallbacks()

        wisprIntegration.refreshConfiguration()
        deviceMonitor.start()
        eventTapController.start()

        updateMenu()
    }

    private func wireCallbacks() {
        deviceMonitor.onStateChange = { [weak self] in
            self?.updateMenu()
        }

        deviceMonitor.onPTTButtonEvent = { [weak self] pressed, _ in
            guard let self,
                  self.remappingEnabled,
                  self.wisprIntegration.runningPID != nil,
                  self.wisprIntegration.pttBindingState == .configured else {
                return
            }

            self.wisprIntegration.dispatchPTTEvent(pressed: pressed, location: .zero)
        }

        eventTapController.onStateChange = { [weak self] in
            self?.updateMenu()
        }

        wisprIntegration.onStateChange = { [weak self] in
            self?.updateMenu()
        }
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Options"
        statusItem = item

        let menu = NSMenu()
        statusMenu = menu

        let deviceStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        deviceStatusItem.isEnabled = false
        menu.addItem(deviceStatusItem)
        self.deviceStatusItem = deviceStatusItem

        let remapToggleItem = NSMenuItem(title: "", action: #selector(toggleRemapping), keyEquivalent: "")
        remapToggleItem.target = self
        menu.addItem(remapToggleItem)
        self.remapToggleItem = remapToggleItem

        let permissionsItem = NSMenuItem(title: "", action: #selector(requestAccessibilityPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)
        self.permissionsItem = permissionsItem

        let wisprItem = NSMenuItem(title: "", action: #selector(refreshWisprStatus), keyEquivalent: "")
        wisprItem.target = self
        menu.addItem(wisprItem)
        self.wisprItem = wisprItem

        let triggerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        triggerItem.isEnabled = false
        menu.addItem(triggerItem)
        self.triggerItem = triggerItem

        menu.addItem(.separator())

        let helpItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        let quitItem = NSMenuItem(title: "Quit Better Options", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    private func updateMenu() {
        let accessibilityGranted = eventTapController.hasAccessibilityPermission
        let tapReady = eventTapController.isTapInstalled
        let deviceName = deviceMonitor.activeDeviceName ?? "No MX Master 3 detected"
        let statusPrefix = deviceMonitor.hasMatchedDevice ? "Device: " : "Waiting: "
        deviceStatusItem?.title = statusPrefix + deviceName

        remapToggleItem?.title = remappingEnabled ? "Disable Remapping" : "Enable Remapping"
        remapToggleItem?.isEnabled = accessibilityGranted && tapReady

        if accessibilityGranted {
            permissionsItem?.title = tapReady ? "Accessibility: granted" : "Accessibility: granted, tap unavailable"
        } else {
            permissionsItem?.title = "Grant Accessibility Access"
        }

        wisprItem?.title = wisprMenuTitle()
        triggerItem?.title = triggerMenuTitle()
        statusItem?.button?.title = summaryTitle(
            hasDevice: deviceMonitor.hasMatchedDevice,
            hasPermission: accessibilityGranted,
            wisprReady: wisprIntegration.pttBindingState == .configured
        )
    }

    private func wisprMenuTitle() -> String {
        switch wisprIntegration.pttBindingState {
        case .configured:
            return wisprIntegration.runningPID == nil ? "Wispr: PTT configured, app not running" : "Wispr: PTT configured"
        case .missingConfig:
            return "Wispr: config not found"
        case .bindingMismatch:
            return "Wispr: no supported PTT shortcut found"
        case .invalidConfig:
            return "Wispr: config unreadable"
        }
    }

    private func triggerMenuTitle() -> String {
        if let usage = deviceMonitor.lastObservedPTTButtonUsage {
            return "PTT trigger: MX button \(usage)"
        }
        return "PTT trigger: waiting for thumb-rest button"
    }

    private func summaryTitle(hasDevice: Bool, hasPermission: Bool, wisprReady: Bool) -> String {
        if !hasPermission {
            return "Options !"
        }
        if !hasDevice {
            return "Options ?"
        }
        return wisprReady ? "Options MX" : "Options MX!"
    }

    @objc
    private func toggleRemapping() {
        remappingEnabled.toggle()
    }

    @objc
    private func requestAccessibilityPermissions() {
        _ = eventTapController.requestAccessibilityPermission()
        updateMenu()
    }

    @objc
    private func refreshWisprStatus() {
        wisprIntegration.refreshConfiguration()
        updateMenu()
    }

    @objc
    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
