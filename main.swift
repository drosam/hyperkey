import AppKit
import CoreGraphics
import Foundation
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

func hidutil(_ arguments: [String]) -> String? {
    let p = Process()
    let output = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    p.arguments = arguments
    p.standardOutput = output
    guard (try? p.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

// The table is system-wide and `--set` replaces all of it, so merge with other remaps.
func currentKeyMapping() -> [KeyMapping] {
    guard let output = hidutil(["property", "--get", "UserKeyMapping"]),
          let mappings = parseUserKeyMapping(output)
    else {
        FileHandle.standardError.write("Could not read hidutil UserKeyMapping; other remaps will be cleared\n".data(using: .utf8)!)
        return []
    }
    return mappings
}

func setKeyMapping(_ mappings: [KeyMapping]) {
    _ = hidutil(["property", "--set", userKeyMappingJSON(mappings)])
}

func installRemap() {
    setKeyMapping(withHyperRemap(currentKeyMapping()))
}

func removeRemap() {
    setKeyMapping(withoutHyperRemap(currentKeyMapping()))
}

if arguments.contains("--clear-remap") {
    removeRemap()
    exit(0)
}

// Restore normal caps lock when killed (Ctrl+C / pkill)
signal(SIGINT) { _ in removeRemap(); exit(0) }
signal(SIGTERM) { _ in removeRemap(); exit(0) }

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
    IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &state)
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
        return Unmanaged.passUnretained(event)
    }

    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let isKeyDown = type == .keyDown
    let input: KeyInput = keycode == f18Keycode
        ? (isKeyDown ? .hyperDown : .hyperUp)
        : (isKeyDown ? .otherKeyDown : .otherKeyUp)

    let wasHyperDown = hyperState.isHyperDown
    let wasHyperUsed = hyperState.hyperUsed
    let action = hyperState.handle(input, at: Date.timeIntervalSinceReferenceDate)

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
        } else {
            logv(wasHyperUsed ? "hyper up" : "hyper up — tap alone")
        }
        return nil
    case .swallowAndToggleCapsLock:
        logv("hyper up — double tap, toggling caps lock")
        toggleCapsLock()
        return nil
    }
}

removeRemap()
installRemap()

tap = CGEvent.tapCreate(
    tap: .cghidEventTap,            // lowest userspace level, before window server dispatch
    place: .headInsertEventTap,
    options: .defaultTap,           // active tap: can modify/swallow events
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue) |
                      CGEventMask(1 << CGEventType.keyUp.rawValue),
    callback: callback,
    userInfo: nil
)

guard let tap else {
    removeRemap()
    let interactive = isatty(STDIN_FILENO) != 0
    if interactive {
        // Running from a terminal: trigger the system Accessibility prompt once.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
    FileHandle.standardError.write("""
    Failed to create event tap.
    Grant Accessibility permission to this binary:
    System Settings > Privacy & Security > Accessibility

    """.data(using: .utf8)!)
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

// Menu bar icon so the process can be quit without a terminal. NSApp's run loop
// is the same main run loop the tap source was added to.
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon

final class MenuHandler: NSObject {
    @objc func quit() {
        removeRemap()
        exit(0)
    }
}
let menuHandler = MenuHandler()

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "✦"
let menu = NSMenu()
let versionItem = NSMenuItem(title: "hyperkey \(hyperkeyVersion)", action: nil, keyEquivalent: "")
versionItem.isEnabled = false
menu.addItem(versionItem)
menu.addItem(.separator())
let quitItem = NSMenuItem(title: "Quit Hyperkey", action: #selector(MenuHandler.quit), keyEquivalent: "")
quitItem.target = menuHandler
menu.addItem(quitItem)
statusItem.menu = menu

print("hyperkey running — hold caps lock for ⇧⌃⌥⌘, double-tap alone to toggle caps. Quit via ✦ menu.")
app.run()
