import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.hidsystem

// Caps lock's toggle (state + LED) happens inside the HID driver, below any event
// tap — swallowing its flagsChanged event doesn't stop it. So instead we remap
// caps lock -> F18 in the driver itself (UserKeyMapping): no caps state ever toggles,
// and we intercept F18 (which nothing else uses) as plain keyDown/keyUp.
let f18Keycode: Int64 = 79 // macOS virtual keycode for F18

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
@MainActor var hyperState = HyperKeyState()

@MainActor var tap: CFMachPort?

// The tap source is on the main run loop, so the C callback always runs on the main actor.
func callback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    nonisolated(unsafe) let event = event // CGEvent is not Sendable; only used on this thread
    let pass = MainActor.assumeIsolated { handle(type: type, event: event) }
    return pass ? Unmanaged.passUnretained(event) : nil
}

/// Returns whether to pass the event on.
@MainActor
func handle(type: CGEventType, event: CGEvent) -> Bool {
    // macOS disables the tap if the callback is ever too slow; re-enable and move on
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        hyperState.reset() // key events may have been missed while disabled
        return true
    }

    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    if keycode != f18Keycode && hyperState.isIdle { return true } // fast path for normal typing

    let isKeyDown = type == .keyDown
    let input: KeyInput = keycode == f18Keycode
        ? (isKeyDown ? .hyperDown : .hyperUp)
        : (isKeyDown ? .otherKeyDown : .otherKeyUp)

    // Monotonic: wall-clock steps (NTP, manual changes) must not fake a double tap.
    let action = hyperState.handle(input, at: ProcessInfo.processInfo.systemUptime)

    switch action {
    case .pass:
        return true
    case .passWithHyper:
        event.flags.formUnion(hyperFlags)
        logv("hyper + keycode \(keycode)")
        return true
    case .swallow(let reason):
        switch reason {
        case .hyperDown: logv("hyper down")
        case .comboRelease: logv("hyper up")
        case .tapAlone: logv("hyper up — tap alone")
        case .autorepeat, .strayHyperUp: break
        }
        return false
    case .swallowAndToggleCapsLock:
        logv("hyper up — double tap, toggling caps lock")
        toggleCapsLock()
        return false
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
