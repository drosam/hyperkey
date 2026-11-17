import AppKit
import CoreGraphics
import Foundation

setvbuf(stdout, nil, _IONBF, 0) // unbuffered so logs appear immediately when piped to a file

let usage = """
usage: hyperkey [--verbose] [--clear-remap] [-v | --version] [-h | --help]

Hold caps lock for ⇧⌃⌥⌘, double-tap it alone to toggle caps lock.
Requires Accessibility permission. Quit via the ✦ menu bar icon.
--clear-remap removes a leftover caps lock -> F18 remap and exits.
"""

let command = parseCommand(Array(CommandLine.arguments.dropFirst()))
switch command {
case .version:
    print("hyperkey \(hyperkeyVersion)")
    exit(0)
case .help:
    print(usage)
    exit(0)
case .invalid(let argument):
    printError("hyperkey: unknown option \(argument)\n\(usage)")
    exit(2)
case .clearRemap, .run:
    break
}

let verbose = command == .run(verbose: true)

// Writes happen off the tap callback, so a stalled stdout reader cannot block it.
let logQueue = DispatchQueue(label: "hyperkey.log")

func logv(_ message: @autoclosure () -> String) {
    guard verbose else { return }
    let line = message()
    logQueue.async { print(line) }
}

func printError(_ message: String) {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
}

if command == .clearRemap {
    exit(removeRemap() ? 0 : 1)
}

// A second instance would clear the shared remap on quit and break the first one.
// The kernel drops the lock when the process exits, even on SIGKILL.
let lockPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("hyperkey.lock")
let lockFD = open(lockPath, O_RDONLY | O_CREAT, 0o600)
if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    printError("hyperkey is already running")
    exit(1)
}

/// The only exit path once the remap is installed.
@MainActor
func shutdown(_ status: Int32 = 0) -> Never {
    if remapInstalled { removeRemap() }
    exit(status)
}

// Cleanup is not async-signal-safe, so handle signals on the main queue instead of in a handler.
let signalSources = [SIGINT, SIGTERM, SIGHUP].map { sig -> DispatchSourceSignal in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { shutdown() }
    source.resume()
    return source
}

// The remap goes in only once the tap exists, so a missing permission never touches UserKeyMapping.
@MainActor
func start(with newTap: CFMachPort) {
    guard installRemap() else {
        printError("Failed to remap caps lock to F18")
        exit(1) // nonzero so launchd retries
    }
    watchForLostRemap()
    tap = newTap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: newTap, enable: true)
    print("hyperkey running — hold caps lock for ⇧⌃⌥⌘, double-tap alone to toggle caps. Quit via ✦ menu.")
}

if let newTap = createTap() {
    start(with: newTap)
} else {
    let interactive = isatty(STDIN_FILENO) != 0
    if interactive {
        // Running from a terminal: trigger the system Accessibility prompt once.
        // Value of kAXTrustedCheckOptionPrompt, which Swift 6 rejects as shared mutable state.
        let promptKey = "AXTrustedCheckOptionPrompt"
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
    // macOS attributes a terminal-launched process to the terminal app.
    let grantee = interactive ? "your terminal app" : "hyperkey"
    printError("""
    Failed to create event tap. Waiting for Accessibility permission for \(grantee):
    System Settings > Privacy & Security > Accessibility
    """)
    // Wait in-process instead of exiting, so launchd does not respawn and log every 10 s.
    let permissionTimer = Timer(timeInterval: 2, repeats: true) { timer in
        guard AXIsProcessTrusted(), let newTap = createTap() else { return }
        timer.invalidate()
        MainActor.assumeIsolated { start(with: newTap) } // timer is on the main run loop
    }
    RunLoop.main.add(permissionTimer, forMode: .common)
}

// Menu bar icon so the process can be quit without a terminal. NSApp's run loop
// is the same main run loop the tap source was added to.
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Apple-event quits (logout, Activity Monitor) go through terminate:.
    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }

    @objc func quit() {
        shutdown()
    }
}
let appDelegate = AppDelegate()
app.delegate = appDelegate

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "✦"
let menu = NSMenu()
let versionItem = NSMenuItem(title: "hyperkey \(hyperkeyVersion)", action: nil, keyEquivalent: "")
menu.addItem(versionItem)
menu.addItem(.separator())
let quitItem = NSMenuItem(title: "Quit Hyperkey", action: #selector(AppDelegate.quit), keyEquivalent: "")
quitItem.target = appDelegate
menu.addItem(quitItem)
statusItem.menu = menu

app.run()
