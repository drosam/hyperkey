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

    mutating func handle(_ input: KeyInput, at time: TimeInterval) -> KeyAction {
        switch input {
        case .hyperDown:
            if !isHyperDown { // ignore autorepeat, it would reset hyperUsed
                isHyperDown = true
                hyperUsed = false
            }
            return .swallow

        case .hyperUp:
            isHyperDown = false
            if hyperUsed {
                lastTapAloneTime = nil
                return .swallow
            }
            if let lastTap = lastTapAloneTime, time - lastTap <= doubleTapInterval {
                lastTapAloneTime = nil
                return .swallowAndToggleCapsLock
            }
            lastTapAloneTime = time
            return .swallow

        case .otherKeyDown:
            guard isHyperDown else { return .pass }
            hyperUsed = true
            return .passWithHyper

        case .otherKeyUp:
            return isHyperDown ? .passWithHyper : .pass
        }
    }
}
