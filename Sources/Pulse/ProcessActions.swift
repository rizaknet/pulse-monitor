import Foundation
import AppKit

public enum ProcessActions {
    public static func terminate(pid: pid_t, force: Bool) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) {
            let success = force ? app.forceTerminate() : app.terminate()
            if success && !force { return true }
        }
        return kill(pid, force ? SIGKILL : SIGTERM) == 0
    }

    public static func terminateGroup(pids: [pid_t], bundlePath: String?, force: Bool) {
        // 1. Terminate matching GUI apps via AppKit first so macOS tears down the UI & WindowServer state cleanly
        if let path = bundlePath {
            let targetURL = URL(fileURLWithPath: path).standardized
            let runningApps = NSWorkspace.shared.runningApplications.filter {
                guard let appURL = $0.bundleURL?.standardized else { return false }
                return appURL == targetURL || targetURL.path.hasPrefix(appURL.path) || appURL.path.hasPrefix(targetURL.path)
            }
            for app in runningApps {
                if force {
                    _ = app.forceTerminate()
                } else {
                    _ = app.terminate()
                }
            }
        }

        // 2. Also check if any PID belongs to an NSRunningApplication (e.g. main app process)
        for pid in pids {
            if let app = NSRunningApplication(processIdentifier: pid) {
                if force {
                    _ = app.forceTerminate()
                } else {
                    _ = app.terminate()
                }
            }
        }

        // 3. Terminate all remaining processes in the group
        // If force-quitting: send SIGKILL to all PIDs so no background helper or daemon remains alive
        // If quitting gently: send SIGTERM so processes can cleanly exit
        for pid in pids {
            _ = kill(pid, force ? SIGKILL : SIGTERM)
        }

        // 4. For force-quit, ensure stubborn child processes are definitely terminated
        if force {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
                for pid in pids {
                    if kill(pid, 0) == 0 {
                        _ = kill(pid, SIGKILL)
                    }
                }
            }
        }
    }
}
