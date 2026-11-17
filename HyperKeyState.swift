import Foundation

enum KeyInput {
    case hyperDown
    case hyperUp
    case otherKeyDown
    case otherKeyUp
}

enum KeyAction: Equatable {
    case pass
    case passWithHyper
    case swallow
    case swallowAndToggleCapsLock
}

/// Pure hyper key state machine: hold for hyper, double-tap alone to toggle caps lock.
struct HyperKeyState {
    var doubleTapInterval: TimeInterval = 0.35
    private(set) var isHyperDown = false
    private(set) var hyperUsed = false
    private var lastTapAloneTime: TimeInterval?

    /// True when another key would change no state and pass untouched, so callers may skip `handle`.
    var isIdle: Bool { !isHyperDown && lastTapAloneTime == nil }

    /// Forgets all key state, for when events may have been missed (tap disabled, lost key up).
    mutating func reset() {
        isHyperDown = false
        hyperUsed = false
        lastTapAloneTime = nil
    }

    mutating func handle(_ input: KeyInput, at time: TimeInterval) -> KeyAction {
        switch input {
        case .hyperDown:
            if !isHyperDown { // ignore autorepeat, it would reset hyperUsed
                isHyperDown = true
                hyperUsed = false
            }
            return .swallow

        case .hyperUp:
            guard isHyperDown else { return .swallow } // stray up after a reset is not a tap
            isHyperDown = false
            if hyperUsed {
                lastTapAloneTime = nil
                return .swallow
            }
            if let lastTap = lastTapAloneTime, (0...doubleTapInterval).contains(time - lastTap) {
                lastTapAloneTime = nil
                return .swallowAndToggleCapsLock
            }
            lastTapAloneTime = time
            return .swallow

        case .otherKeyDown:
            guard isHyperDown else {
                lastTapAloneTime = nil // a key between taps means they are not a double tap alone
                return .pass
            }
            hyperUsed = true
            return .passWithHyper

        case .otherKeyUp:
            return isHyperDown ? .passWithHyper : .pass
        }
    }
}

enum Command: Equatable {
    case version
    case help
    case clearRemap
    case run(verbose: Bool)
    case invalid(String)
}

/// Parses arguments (without the program name). Any unknown argument is rejected,
/// so a typo never starts the remap.
func parseCommand(_ arguments: [String]) -> Command {
    let known: Set = ["--version", "-v", "--help", "-h", "--clear-remap", "--verbose"]
    if let unknown = arguments.first(where: { !known.contains($0) }) { return .invalid(unknown) }
    if arguments.contains("--version") || arguments.contains("-v") { return .version }
    if arguments.contains("--help") || arguments.contains("-h") { return .help }
    if arguments.contains("--clear-remap") { return .clearRemap }
    return .run(verbose: arguments.contains("--verbose"))
}

let capsLockUsage = 0x7_0000_0039 // HID usage: keyboard caps lock
let f18Usage = 0x7_0000_006D      // HID usage: keyboard F18

/// One entry of the system-wide `hidutil` `UserKeyMapping` table, as HID usages.
struct KeyMapping: Equatable {
    let src: Int
    let dst: Int
}

let hyperRemap = KeyMapping(src: capsLockUsage, dst: f18Usage)

/// Adds caps lock -> F18, replacing any other caps lock mapping and keeping the rest.
func withHyperRemap(_ mappings: [KeyMapping]) -> [KeyMapping] {
    mappings.filter { $0.src != capsLockUsage } + [hyperRemap]
}

func withoutHyperRemap(_ mappings: [KeyMapping]) -> [KeyMapping] {
    mappings.filter { $0 != hyperRemap }
}

/// Parses `hidutil property --get UserKeyMapping` output (OpenStep plist or `(null)`).
/// Returns nil when the output is not a mapping table.
func parseUserKeyMapping(_ output: String) -> [KeyMapping]? {
    let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if text == "(null)" { return [] }
    guard let plist = try? PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil),
          let entries = plist as? [[String: Any]]
    else { return nil }

    func usage(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return (value as? String).flatMap { Int($0) }
    }
    var mappings: [KeyMapping] = []
    for entry in entries {
        guard let src = usage(entry["HIDKeyboardModifierMappingSrc"]),
              let dst = usage(entry["HIDKeyboardModifierMappingDst"])
        else { return nil }
        mappings.append(KeyMapping(src: src, dst: dst))
    }
    return mappings
}

/// JSON for `hidutil property --set`, which replaces the whole table.
func userKeyMappingJSON(_ mappings: [KeyMapping]) -> String {
    let entries = mappings.map {
        "{\"HIDKeyboardModifierMappingSrc\":\($0.src),\"HIDKeyboardModifierMappingDst\":\($0.dst)}"
    }
    return "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
}
