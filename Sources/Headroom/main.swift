import AppKit
import Darwin

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { HeadroomDelegate() }
app.delegate = delegate
app.run()
