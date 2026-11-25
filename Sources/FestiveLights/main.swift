import AppKit

// A menu-bar-only app built without a storyboard. The delegate is kept alive
// by this top-level binding for the lifetime of the process.
let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
