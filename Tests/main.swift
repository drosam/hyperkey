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
    check(s.handle(.hyperDown, at: 0), .swallow, "hyper down swallowed")
    check(s.handle(.otherKeyDown, at: 0.05), .passWithHyper, "key down stamped")
    check(s.handle(.otherKeyUp, at: 0.1), .passWithHyper, "key up stamped")
    check(s.handle(.hyperUp, at: 0.15), .swallow, "hyper up swallowed")
    check(s.handle(.otherKeyDown, at: 0.2), .pass, "after release no stamp")
}

test("single lone tap does not toggle") { s in
    check(s.handle(.hyperDown, at: 0), .swallow, "down")
    check(s.handle(.hyperUp, at: 0.05), .swallow, "up")
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
    check(s.handle(.hyperUp, at: 0.5), .swallow, "too slow")
    _ = s.handle(.hyperDown, at: 0.6)
    check(s.handle(.hyperUp, at: 0.65), .swallowAndToggleCapsLock, "quick tap after slow tap toggles")
}

test("other key between lone taps cancels double tap") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    check(s.handle(.otherKeyDown, at: 0.1), .pass, "unheld key passes")
    check(s.handle(.otherKeyUp, at: 0.12), .pass, "unheld key up passes")
    _ = s.handle(.hyperDown, at: 0.2)
    check(s.handle(.hyperUp, at: 0.25), .swallow, "tap after other key does not toggle")
}

test("time going backwards does not toggle") { s in
    _ = s.handle(.hyperDown, at: 99.95)
    _ = s.handle(.hyperUp, at: 100)
    _ = s.handle(.hyperDown, at: 99.85)
    check(s.handle(.hyperUp, at: 99.9), .swallow, "negative delta")
}

test("tap, combo, tap does not toggle") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    _ = s.handle(.hyperDown, at: 0.1)
    _ = s.handle(.otherKeyDown, at: 0.12)
    _ = s.handle(.otherKeyUp, at: 0.14)
    check(s.handle(.hyperUp, at: 0.16), .swallow, "combo release")
    _ = s.handle(.hyperDown, at: 0.2)
    check(s.handle(.hyperUp, at: 0.25), .swallow, "tap after combo starts fresh")
}

test("autorepeat hyper down does not reset used flag") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.otherKeyDown, at: 0.05)
    check(s.handle(.hyperDown, at: 0.5), .swallow, "autorepeat swallowed")
    check(s.handle(.hyperDown, at: 0.53), .swallow, "autorepeat swallowed")
    _ = s.handle(.hyperUp, at: 0.6)
    _ = s.handle(.hyperDown, at: 0.7)
    check(s.handle(.hyperUp, at: 0.75), .swallow, "held combo is not a lone tap")
}

test("triple tap toggles once, third tap starts new window") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    _ = s.handle(.hyperDown, at: 0.1)
    check(s.handle(.hyperUp, at: 0.15), .swallowAndToggleCapsLock, "second tap toggles")
    _ = s.handle(.hyperDown, at: 0.2)
    check(s.handle(.hyperUp, at: 0.25), .swallow, "third tap does not toggle")
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
    check(s.handle(.hyperUp, at: 0.15), .swallow, "first tap after reset does not toggle")
}

test("stray hyper up does not arm double tap") { s in
    check(s.handle(.hyperUp, at: 0), .swallow, "stray up swallowed")
    _ = s.handle(.hyperDown, at: 0.1)
    check(s.handle(.hyperUp, at: 0.15), .swallow, "next tap does not toggle")
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
checkEqual(parseUserKeyMapping("(null)\n"), [], "null output parses as empty")
checkEqual(parseUserKeyMapping("""
(
        {
        HIDKeyboardModifierMappingDst = 30064771125;
        HIDKeyboardModifierMappingSrc = 30064771172;
    },
        {
        HIDKeyboardModifierMappingDst = 30064771181;
        HIDKeyboardModifierMappingSrc = 30064771129;
    }
)

"""), [backtickSwap, hyperRemap], "hidutil --get output parses")
checkEqual(parseUserKeyMapping("garbage {"), nil, "unparseable output is nil")
checkEqual(withHyperRemap([backtickSwap]), [backtickSwap, hyperRemap], "install keeps other mappings")
checkEqual(withHyperRemap([capsToEscape, backtickSwap]), [backtickSwap, hyperRemap], "install replaces other caps lock mapping")
checkEqual(withHyperRemap([hyperRemap]), [hyperRemap], "install does not duplicate leftover remap")
checkEqual(withoutHyperRemap([backtickSwap, hyperRemap]), [backtickSwap], "remove keeps other mappings")
checkEqual(userKeyMappingJSON([]), "{\"UserKeyMapping\":[]}", "empty table JSON")
checkEqual(
    userKeyMappingJSON([hyperRemap]),
    "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":30064771129,\"HIDKeyboardModifierMappingDst\":30064771181}]}",
    "table JSON"
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
