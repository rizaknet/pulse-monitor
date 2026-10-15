import Foundation
import IOKit.pwr_mgt

/// Sleep blockers preventing system or display sleep.
enum PowerAssertions {
    static func current() -> [SleepBlocker] {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let d = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }

        var out: [SleepBlocker] = []
        for (pidNum, list) in d {
            for a in list {
                let type = a["AssertType"] as? String ?? ""
                let kind: SleepBlocker.Kind
                switch type {
                case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion":
                    kind = .display
                case "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion":
                    kind = .system
                default:
                    continue
                }
                let name = a["Process Name"] as? String ?? "pid \(pidNum)"
                if name == "powerd" || (name == "coreaudiod" && kind == .system) { continue }
                let reason = (a["AssertName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "No reason given"
                out.append(SleepBlocker(pid: pidNum.int32Value, processName: name, kind: kind, reason: reason))
            }
        }
        return out.sorted { $0.processName < $1.processName }
    }
}
