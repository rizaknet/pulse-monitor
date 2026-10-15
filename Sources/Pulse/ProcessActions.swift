import Foundation
import AppKit

public enum ProcessActions {
    public static func terminate(pid: pid_t, force: Bool) -> Bool {
        if !force, let app = NSRunningApplication(processIdentifier: pid) {
            return app.terminate()
        }
        return kill(pid, force ? SIGKILL : SIGTERM) == 0
    }

    public static func terminateGroup(pids: [pid_t], bundlePath: String?, force: Bool) {
        if !force, let path = bundlePath,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == path }) {
            app.terminate()
            return
        }
        for pid in pids {
            _ = terminate(pid: pid, force: force)
        }
    }
}
