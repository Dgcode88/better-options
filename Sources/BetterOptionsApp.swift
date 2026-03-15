import AppKit

@main
struct BetterOptionsApp {
    private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
