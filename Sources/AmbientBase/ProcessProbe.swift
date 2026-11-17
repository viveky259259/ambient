import Darwin

public enum ProcessProbe {
    /// Whether a process is still running. Unknown pids (zero or less) count as alive, and so does one this user may
    /// not signal (`EPERM`): it exists.
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return true }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
