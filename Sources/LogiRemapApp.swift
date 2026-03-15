import AppKit

@main
struct LogiRemapApp {
    private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
