import Foundation

/// Guards against two ClaudeBar Monitor processes running at once.
///
/// macOS Control Strip allows only ONE stable system-tray item — a second
/// process registering its own item REPLACES the first rather than sitting
/// beside it, and the two then fight over the slot so the Touch Bar item
/// flickers in and out (the "swift run still running but no monitor on the
/// Touch Bar" symptom). The common cause is a manual `swift run` debug build
/// started alongside the installed LaunchAgent copy.
///
/// `acquire()` takes an exclusive advisory lock (`flock`) on a fixed file. The
/// kernel releases the lock automatically when the holding process exits — even
/// if killed — so there is no stale-lock problem the way a PID file would have.
/// If the lock is already held, this process is the second instance and should
/// exit immediately, before registering anything with the Control Strip.
enum SingleInstance {
    /// Fixed per-user lock path. Lives in the user's caches dir (always
    /// writable, survives across builds). Same path for debug and release so
    /// they contend with each other.
    private static var lockPath: String {
        let base = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        return (base as NSString).appendingPathComponent("com.ericlin.claudebarmonitor.lock")
    }

    /// File descriptor kept open for the process lifetime so the lock is held.
    /// Intentionally never closed — the OS reclaims it (and the lock) on exit.
    private static var lockFD: Int32 = -1

    /// Returns true if this process acquired the singleton lock (it is the only
    /// instance). Returns false if another instance already holds it.
    static func acquire() -> Bool {
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            // Can't create the lock file — fail open rather than block startup.
            return true
        }
        // Non-blocking exclusive lock: succeeds only if no one else holds it.
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFD = fd
        return true
    }
}
