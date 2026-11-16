import AppKit
import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.hidsystem

setvbuf(stdout, nil, _IONBF, 0) // unbuffered so logs appear immediately when piped to a file

let arguments = CommandLine.arguments.dropFirst()

if arguments.contains("--version") || arguments.contains("-v") {
    print("hyperkey \(hyperkeyVersion)")
    exit(0)
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    usage: hyperkey [--verbose] [--version] [--help] [--clear-remap]

    Hold caps lock for ⇧⌃⌥⌘, double-tap it alone to toggle caps lock.
    Requires Accessibility permission. Quit via the ✦ menu bar icon.
    --clear-remap removes a leftover caps lock -> F18 remap and exits.
    """)
    exit(0)
}

let verbose = arguments.contains("--verbose")

func logv(_ message: String) {
    if verbose { print(message) }
}

// Caps lock's toggle (state + LED) happens inside the HID driver, below any event
// tap — swallowing its flagsChanged event doesn't stop it. So instead we remap
// caps lock -> F18 in the driver itself via hidutil: no caps state ever toggles,
// and we intercept F18 (which nothing else uses) as plain keyDown/keyUp.
let f18Keycode: Int64 = 79 // macOS virtual keycode for F18

func printError(_ message: String) {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
}

/// Runs hidutil and returns its stdout, or nil if it could not run or exited non-zero.
func hidutil(_ arguments: [String]) -> String? {
    let p = Process()
    let output = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    p.arguments = arguments
    p.standardOutput = output
    guard (try? p.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self)
}

// The table is system-wide and `--set` replaces all of it, so merge with other remaps.
func currentKeyMapping() -> [KeyMapping] {
    guard let output = hidutil(["property", "--get", "UserKeyMapping"]),
          let mappings = parseUserKeyMapping(output)
    else {
        printError("Could not read hidutil UserKeyMapping; other remaps will be cleared")
        return []
    }
    return mappings
}

func setKeyMapping(_ mappings: [KeyMapping]) -> Bool {
    hidutil(["property", "--set", userKeyMappingJSON(mappings)]) != nil
}

func installRemap() -> Bool {
    setKeyMapping(withHyperRemap(currentKeyMapping()))
}

@discardableResult
func removeRemap() -> Bool {
    guard setKeyMapping(withoutHyperRemap(currentKeyMapping())) else {
        printError("Failed to remove the caps lock remap with hidutil")
        return false
    }
    return true
}

if arguments.contains("--clear-remap") {
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

var remapInstalled = false

/// The only exit path once the remap is installed.
func shutdown(_ status: Int32 = 0) -> Never {
    if remapInstalled { removeRemap() }
    exit(status)
}

// Cleanup spawns processes, which is unsafe in a signal handler; handle signals on the main queue.
let signalSources = [SIGINT, SIGTERM, SIGHUP].map { sig -> DispatchSourceSignal in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { shutdown() }
    source.resume()
    return source
}

// Caps lock state lives in the HID driver, so a double-tap toggle can't be done
// by posting events — we flip the lock state (and LED) directly through IOKit.
func toggleCapsLock() {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
    guard service != 0 else { return }
    defer { IOObjectRelease(service) }

    var connect: io_connect_t = 0
    guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
    defer { IOServiceClose(connect) }

    var state = false
    guard IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS else { return }
    IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !state)
}

let hyperFlags: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
var hyperState = HyperKeyState()

var tap: CFMachPort?

func callback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // macOS disables the tap if the callback is ever too slow; re-enable and move on
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        hyperState.reset() // key events may have been missed while disabled
        return Unmanaged.passUnretained(event)
    }

    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let isKeyDown = type == .keyDown
    let input: KeyInput = keycode == f18Keycode
        ? (isKeyDown ? .hyperDown : .hyperUp)
        : (isKeyDown ? .otherKeyDown : .otherKeyUp)

    // Secure input (password fields, lock screen) hides key events from taps, so F18 up can be lost.
    if input == .otherKeyDown, hyperState.isHyperDown,
       !CGEventSource.keyState(.hidSystemState, key: CGKeyCode(f18Keycode)) {
        logv("hyper up was missed, resetting")
        hyperState.reset()
    }

    let wasHyperDown = hyperState.isHyperDown
    let wasHyperUsed = hyperState.hyperUsed
    // Monotonic: wall-clock steps (NTP, manual changes) must not fake a double tap.
    let action = hyperState.handle(input, at: ProcessInfo.processInfo.systemUptime)

    switch action {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .passWithHyper:
        event.flags.formUnion(hyperFlags)
        logv("hyper + keycode \(keycode)")
        return Unmanaged.passUnretained(event)
    case .swallow:
        if input == .hyperDown {
            if !wasHyperDown { logv("hyper down") }
        } else if wasHyperDown {
            logv(wasHyperUsed ? "hyper up" : "hyper up — tap alone")
        }
        return nil
    case .swallowAndToggleCapsLock:
        logv("hyper up — double tap, toggling caps lock")
        toggleCapsLock()
        return nil
    }
}

func createTap() -> CFMachPort? {
    CGEvent.tapCreate(
        tap: .cghidEventTap,            // lowest userspace level, before window server dispatch
        place: .headInsertEventTap,
        options: .defaultTap,           // active tap: can modify/swallow events
        eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue) |
                          CGEventMask(1 << CGEventType.keyUp.rawValue),
        callback: callback,
        userInfo: nil
    )
}

// hidutil remaps can be dropped when keyboards come and go (Apple TN2450) and possibly on wake.
var remapCheckPending = false
var keyboardMonitor: IOHIDManager?

func scheduleRemapCheck() {
    guard remapInstalled, !remapCheckPending else { return }
    remapCheckPending = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { // coalesce bursts of device events
        remapCheckPending = false
        let current = currentKeyMapping()
        guard !current.contains(hyperRemap) else { return }
        print("caps lock remap was lost, re-applying")
        if !setKeyMapping(withHyperRemap(current)) {
            printError("Failed to re-apply the caps lock remap with hidutil")
        }
    }
}

// Matching callbacks need no IOHIDManagerOpen, so no Input Monitoring permission.
func watchForLostRemap() {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ] as CFDictionary)
    IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, _ in scheduleRemapCheck() }, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    keyboardMonitor = manager

    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { _ in scheduleRemapCheck() }
}

// The remap goes in only once the tap exists, so a missing permission never touches hidutil.
func start(with newTap: CFMachPort) {
    guard installRemap() else {
        printError("Failed to remap caps lock to F18 with hidutil")
        exit(1) // nonzero so launchd retries
    }
    remapInstalled = true
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
    if isatty(STDIN_FILENO) != 0 {
        // Running from a terminal: trigger the system Accessibility prompt once.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
    printError("""
    Failed to create event tap. Waiting for Accessibility permission:
    System Settings > Privacy & Security > Accessibility
    """)
    // Wait in-process instead of exiting, so launchd does not respawn and log every 10 s.
    let permissionTimer = Timer(timeInterval: 2, repeats: true) { timer in
        guard AXIsProcessTrusted(), let newTap = createTap() else { return }
        timer.invalidate()
        start(with: newTap)
    }
    RunLoop.main.add(permissionTimer, forMode: .common)
}

// Menu bar icon so the process can be quit without a terminal. NSApp's run loop
// is the same main run loop the tap source was added to.
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon

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
versionItem.isEnabled = false
menu.addItem(versionItem)
menu.addItem(.separator())
let quitItem = NSMenuItem(title: "Quit Hyperkey", action: #selector(AppDelegate.quit), keyEquivalent: "")
quitItem.target = appDelegate
menu.addItem(quitItem)
statusItem.menu = menu

app.run()
