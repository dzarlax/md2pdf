import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let delegate = AppDelegate()
app.delegate = delegate

NSApp.run()
