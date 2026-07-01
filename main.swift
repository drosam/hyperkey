import AppKit
import CoreGraphics
import Foundation
import IOKit.hidsystem

setvbuf(stdout, nil, _IONBF, 0) // unbuffered so logs appear immediately when piped to a file

let verbose = CommandLine.arguments.contains("--verbose")

func logv(_ message: String) {
    if verbose { print(message) }
}

// Caps lock's toggle (state + LED) happens inside the HID driver, below any event
// tap — swallowing its flagsChanged event doesn't stop it. So instead we remap
// caps lock -> F18 in the driver itself via hidutil: no caps state ever toggles,
// and we intercept F18 (which nothing else uses) as plain keyDown/keyUp.
let capsLockUsage = 0x7_0000_0039 // HID usage: keyboard caps lock
let f18Usage = 0x7_0000_006D      // HID usage: keyboard F18
let f18Keycode: Int64 = 79        // macOS virtual keycode for F18

func hidutil(mapping: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    p.arguments = ["property", "--set", "{\"UserKeyMapping\":[\(mapping)]}"]
    p.standardOutput = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

func installRemap() {
    hidutil(mapping: "{\"HIDKeyboardModifierMappingSrc\":\(capsLockUsage),\"HIDKeyboardModifierMappingDst\":\(f18Usage)}")
}

func removeRemap() {
    hidutil(mapping: "")
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
let doubleTapInterval: TimeInterval = 0.35
var hyperDown = false
var hyperUsed = false // did any key get hyper-stamped while caps was held?
var lastTapAloneTime: TimeInterval?

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
    if keycode == f18Keycode {
        if type == .keyDown {
            if !hyperDown { // ignore autorepeat, it would reset hyperUsed
                hyperDown = true
                hyperUsed = false
                logv("hyper down")
            }
        } else {
            hyperDown = false
            if hyperUsed {
                lastTapAloneTime = nil
                logv("hyper up")
            } else {
                let now = Date.timeIntervalSinceReferenceDate
                if let lastTap = lastTapAloneTime, now - lastTap <= doubleTapInterval {
                    lastTapAloneTime = nil
                    logv("hyper up — double tap, toggling caps lock")
                    toggleCapsLock()
                } else {
                    lastTapAloneTime = now
                    logv("hyper up — tap alone")
                }
            }
        }
        return nil
    }

    if hyperDown {
        if type == .keyDown {
            hyperUsed = true
        }
        event.flags.formUnion(hyperFlags)
        logv("hyper + keycode \(keycode)")
    }

    return Unmanaged.passUnretained(event)
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
let quitItem = NSMenuItem(title: "Quit Hyperkey", action: #selector(MenuHandler.quit), keyEquivalent: "")
quitItem.target = menuHandler
menu.addItem(quitItem)
statusItem.menu = menu

print("hyperkey running — hold caps lock for ⇧⌃⌥⌘, double-tap alone to toggle caps. Quit via ✦ menu.")
app.run()
