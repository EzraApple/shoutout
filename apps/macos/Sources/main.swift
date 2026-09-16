import AppKit
import ShoutOutCore

SettingsMigration.removeRetiredOverrides(from: .standard)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
