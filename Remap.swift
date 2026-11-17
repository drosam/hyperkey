import AppKit
import Foundation
import IOKit.hid
import IOKit.hidsystem

// The same table `hidutil property` edits, through the public HID event system API.
@MainActor let userKeyMappingKey = "UserKeyMapping" as CFString
@MainActor let hidSystem = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)

// The table is system-wide and setting it replaces all of it, so merge with other remaps.
@MainActor
func currentKeyMapping() -> [KeyMapping] {
    guard let mappings = keyMappings(fromProperty: IOHIDEventSystemClientCopyProperty(hidSystem, userKeyMappingKey)) else {
        printError("Could not read UserKeyMapping; other remaps will be cleared")
        return []
    }
    return mappings
}

@MainActor
func setKeyMapping(_ mappings: [KeyMapping]) -> Bool {
    IOHIDEventSystemClientSetProperty(hidSystem, userKeyMappingKey, userKeyMappingProperty(mappings) as CFArray)
}

@MainActor
func installRemap() -> Bool {
    setKeyMapping(withHyperRemap(currentKeyMapping()))
}

@MainActor
@discardableResult
func removeRemap() -> Bool {
    guard setKeyMapping(withoutHyperRemap(currentKeyMapping())) else {
        printError("Failed to remove the caps lock remap")
        return false
    }
    return true
}

// UserKeyMapping can be dropped when keyboards come and go (Apple TN2450) and possibly on wake.
@MainActor var remapCheckPending = false
@MainActor var keyboardMonitor: IOHIDManager?

@MainActor
func scheduleRemapCheck() {
    guard remapInstalled, !remapCheckPending else { return }
    remapCheckPending = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { // coalesce bursts of device events
        remapCheckPending = false
        let current = currentKeyMapping()
        guard !current.contains(hyperRemap) else { return }
        print("caps lock remap was lost, re-applying")
        if !setKeyMapping(withHyperRemap(current)) {
            printError("Failed to re-apply the caps lock remap")
        }
    }
}

// Matching callbacks need no IOHIDManagerOpen, so no Input Monitoring permission.
@MainActor
func watchForLostRemap() {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ] as CFDictionary)
    IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, _ in
        MainActor.assumeIsolated { scheduleRemapCheck() } // scheduled on the main run loop
    }, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    keyboardMonitor = manager

    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { _ in MainActor.assumeIsolated { scheduleRemapCheck() } }
}
