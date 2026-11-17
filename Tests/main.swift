import Foundation

var failures = 0
var checks = 0

@MainActor
func check(_ actual: KeyAction, _ expected: KeyAction, _ message: String, line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FAIL line \(line): \(message) - expected \(expected), got \(actual)")
    }
}

@MainActor
func test(_ name: String, _ body: (inout HyperKeyState) -> Void) {
    var state = HyperKeyState()
    let before = failures
    body(&state)
    print("\(failures == before ? "ok  " : "FAIL") \(name)")
}

test("other keys pass through untouched without hyper") { s in
    check(s.handle(.otherKeyDown, at: 0), .pass, "key down")
    check(s.handle(.otherKeyUp, at: 0.1), .pass, "key up")
}

test("hold hyper + key stamps hyper on down and up") { s in
    check(s.handle(.hyperDown, at: 0), .swallow(.hyperDown), "hyper down swallowed")
    check(s.handle(.otherKeyDown, at: 0.05), .passWithHyper, "key down stamped")
    check(s.handle(.otherKeyUp, at: 0.1), .passWithHyper, "key up stamped")
    check(s.handle(.hyperUp, at: 0.15), .swallow(.comboRelease), "hyper up swallowed")
    check(s.handle(.otherKeyDown, at: 0.2), .pass, "after release no stamp")
}

test("single lone tap does not toggle") { s in
    check(s.handle(.hyperDown, at: 0), .swallow(.hyperDown), "down")
    check(s.handle(.hyperUp, at: 0.05), .swallow(.tapAlone), "up")
}

test("double lone tap within interval toggles caps lock") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    _ = s.handle(.hyperDown, at: 0.2)
    check(s.handle(.hyperUp, at: 0.3), .swallowAndToggleCapsLock, "second tap toggles")
}

test("double tap exactly at interval boundary toggles") { s in
    s.doubleTapInterval = 0.5 // exact in binary floating point
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 1.0)
    _ = s.handle(.hyperDown, at: 1.25)
    check(s.handle(.hyperUp, at: 1.5), .swallowAndToggleCapsLock, "boundary inclusive")
}

test("slow double tap does not toggle, slow tap starts new window") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    _ = s.handle(.hyperDown, at: 0.4)
    check(s.handle(.hyperUp, at: 0.5), .swallow(.tapAlone), "too slow")
    _ = s.handle(.hyperDown, at: 0.6)
    check(s.handle(.hyperUp, at: 0.65), .swallowAndToggleCapsLock, "quick tap after slow tap toggles")
}

test("other key between lone taps cancels double tap") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    check(s.handle(.otherKeyDown, at: 0.1), .pass, "unheld key passes")
    check(s.handle(.otherKeyUp, at: 0.12), .pass, "unheld key up passes")
    _ = s.handle(.hyperDown, at: 0.2)
    check(s.handle(.hyperUp, at: 0.25), .swallow(.tapAlone), "tap after other key does not toggle")
}

test("time going backwards does not toggle") { s in
    _ = s.handle(.hyperDown, at: 99.95)
    _ = s.handle(.hyperUp, at: 100)
    _ = s.handle(.hyperDown, at: 99.85)
    check(s.handle(.hyperUp, at: 99.9), .swallow(.tapAlone), "negative delta")
}

test("tap, combo, tap does not toggle") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    _ = s.handle(.hyperDown, at: 0.1)
    _ = s.handle(.otherKeyDown, at: 0.12)
    _ = s.handle(.otherKeyUp, at: 0.14)
    check(s.handle(.hyperUp, at: 0.16), .swallow(.comboRelease), "combo release")
    _ = s.handle(.hyperDown, at: 0.2)
    check(s.handle(.hyperUp, at: 0.25), .swallow(.tapAlone), "tap after combo starts fresh")
}

test("autorepeat hyper down does not reset used flag") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.otherKeyDown, at: 0.05)
    check(s.handle(.hyperDown, at: 0.5), .swallow(.autorepeat), "autorepeat swallowed")
    check(s.handle(.hyperDown, at: 0.53), .swallow(.autorepeat), "autorepeat swallowed")
    _ = s.handle(.hyperUp, at: 0.6)
    _ = s.handle(.hyperDown, at: 0.7)
    check(s.handle(.hyperUp, at: 0.75), .swallow(.tapAlone), "held combo is not a lone tap, so this is a first tap")
}

test("triple tap toggles once, third tap starts new window") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    _ = s.handle(.hyperDown, at: 0.1)
    check(s.handle(.hyperUp, at: 0.15), .swallowAndToggleCapsLock, "second tap toggles")
    _ = s.handle(.hyperDown, at: 0.2)
    check(s.handle(.hyperUp, at: 0.25), .swallow(.tapAlone), "third tap does not toggle")
    _ = s.handle(.hyperDown, at: 0.3)
    check(s.handle(.hyperUp, at: 0.35), .swallowAndToggleCapsLock, "fourth tap toggles")
}

test("key up without key down while held still stamps") { s in
    _ = s.handle(.hyperDown, at: 0)
    check(s.handle(.otherKeyUp, at: 0.05), .passWithHyper, "stray key up stamped")
    _ = s.handle(.hyperUp, at: 0.1)
    _ = s.handle(.hyperDown, at: 0.2)
    check(s.handle(.hyperUp, at: 0.25), .swallowAndToggleCapsLock, "key up alone does not mark used")
}

test("reset after lost hyper up stops stamping") { s in
    _ = s.handle(.hyperDown, at: 0)
    s.reset()
    check(s.handle(.otherKeyDown, at: 0.05), .pass, "key down not stamped")
    check(s.handle(.otherKeyUp, at: 0.1), .pass, "key up not stamped")
}

test("reset clears the double tap window") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    s.reset()
    _ = s.handle(.hyperDown, at: 0.1)
    check(s.handle(.hyperUp, at: 0.15), .swallow(.tapAlone), "first tap after reset does not toggle")
}

test("stray hyper up does not arm double tap") { s in
    check(s.handle(.hyperUp, at: 0), .swallow(.strayHyperUp), "stray up swallowed")
    _ = s.handle(.hyperDown, at: 0.1)
    check(s.handle(.hyperUp, at: 0.15), .swallow(.tapAlone), "next tap does not toggle")
}

@MainActor
func checkIdle(_ state: HyperKeyState, _ expected: Bool, _ message: String, line: Int = #line) {
    checks += 1
    if state.isIdle != expected {
        failures += 1
        print("FAIL line \(line): \(message) - expected isIdle \(expected)")
    }
}

test("idle only when other keys need no state machine") { s in
    checkIdle(s, true, "fresh state")
    _ = s.handle(.hyperDown, at: 0)
    checkIdle(s, false, "hyper held")
    _ = s.handle(.hyperUp, at: 0.05)
    checkIdle(s, false, "double tap window armed")
    _ = s.handle(.otherKeyDown, at: 0.1)
    checkIdle(s, true, "other key closed the window")
    _ = s.handle(.hyperDown, at: 0.2)
    _ = s.handle(.otherKeyDown, at: 0.25)
    _ = s.handle(.hyperUp, at: 0.3)
    checkIdle(s, true, "combo release leaves no window")
    _ = s.handle(.hyperDown, at: 0.4)
    _ = s.handle(.hyperUp, at: 0.45)
    s.reset()
    checkIdle(s, true, "reset")
}

@MainActor
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FAIL line \(line): \(message) - expected \(expected), got \(actual)")
    }
}

let backtickSwap = KeyMapping(src: 0x7_0000_0064, dst: 0x7_0000_0035)
let capsToEscape = KeyMapping(src: capsLockUsage, dst: 0x7_0000_0029)

let mappingFailuresBefore = failures
let systemTable: NSArray = [
    [mappingDstKey: NSNumber(value: 30064771125), mappingSrcKey: NSNumber(value: 30064771172)],
    [mappingDstKey: NSNumber(value: 30064771181), mappingSrcKey: NSNumber(value: 30064771129)],
]
checkEqual(mappingSrcKey, "HIDKeyboardModifierMappingSrc", "system src key name")
checkEqual(mappingDstKey, "HIDKeyboardModifierMappingDst", "system dst key name")
checkEqual(keyMappings(fromProperty: nil), [], "unset table is empty")
checkEqual(keyMappings(fromProperty: systemTable), [backtickSwap, hyperRemap], "system property parses")
checkEqual(keyMappings(fromProperty: "garbage" as NSString), nil, "non-table value is nil")
checkEqual(keyMappings(fromProperty: [[mappingSrcKey: 1]] as NSArray), nil, "entry missing dst is nil")
checkEqual(withHyperRemap([backtickSwap]), [backtickSwap, hyperRemap], "install keeps other mappings")
checkEqual(withHyperRemap([capsToEscape, backtickSwap]), [backtickSwap, hyperRemap], "install replaces other caps lock mapping")
checkEqual(withHyperRemap([hyperRemap]), [hyperRemap], "install does not duplicate leftover remap")
checkEqual(withoutHyperRemap([backtickSwap, hyperRemap]), [backtickSwap], "remove keeps other mappings")
checkEqual(userKeyMappingProperty([]), [], "empty table property")
checkEqual(
    userKeyMappingProperty([hyperRemap]),
    [[mappingSrcKey: 30064771129, mappingDstKey: 30064771181]],
    "table property"
)
checkEqual(
    keyMappings(fromProperty: userKeyMappingProperty([backtickSwap, hyperRemap]) as CFArray),
    [backtickSwap, hyperRemap],
    "property round-trips through CFArray"
)
print("\(failures == mappingFailuresBefore ? "ok  " : "FAIL") UserKeyMapping merge and parsing")

let commandFailuresBefore = failures
checkEqual(parseCommand([]), .run(verbose: false), "no arguments runs")
checkEqual(parseCommand(["--verbose"]), .run(verbose: true), "--verbose runs verbose")
checkEqual(parseCommand(["-v"]), .version, "-v is version")
checkEqual(parseCommand(["--verbose", "--version"]), .version, "version wins over run flags")
checkEqual(parseCommand(["-h"]), .help, "-h is help")
checkEqual(parseCommand(["--clear-remap"]), .clearRemap, "--clear-remap")
checkEqual(parseCommand(["--verbos"]), .invalid("--verbos"), "typo is rejected")
checkEqual(parseCommand(["--verbose", "-V"]), .invalid("-V"), "unknown flag after a valid one is rejected")
checkEqual(parseCommand(["--version", "extra"]), .invalid("extra"), "unknown argument rejected even with --version")
print("\(failures == commandFailuresBefore ? "ok  " : "FAIL") command-line parsing")

print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
