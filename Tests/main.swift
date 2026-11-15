import Foundation

var failures = 0
var checks = 0

func check(_ actual: KeyAction, _ expected: KeyAction, _ message: String, line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FAIL line \(line): \(message) - expected \(expected), got \(actual)")
    }
}

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

test("slow double tap does not toggle") { s in
    _ = s.handle(.hyperDown, at: 0)
    _ = s.handle(.hyperUp, at: 0.05)
    _ = s.handle(.hyperDown, at: 0.4)
    check(s.handle(.hyperUp, at: 0.5), .swallow, "too slow")
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

print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
