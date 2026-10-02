import Darwin

/// The process identifiers nothing can usefully attach to, whatever the caller's
/// privileges are.
///
/// Pickers refuse to select these and render them dimmed. Listing them and refusing them
/// is deliberate: hiding them would make "why is `launchd` not in the list" a question
/// with no answer on screen, while leaving them selectable — which is what this library
/// did before — only moves the failure to whatever the caller does after the pick.
///
/// The rule is by identifier, not by name. A process can be renamed or impersonated;
/// pid 0 and pid 1 cannot be anything else.
public enum RestrictedProcess {
    /// The kernel, which is not a user-space process at all and has no task to attach to.
    public static let kernelProcessIdentifier: pid_t = 0

    /// `launchd`. It is the parent of everything and the one process whose failure takes
    /// the system down with it.
    public static let launchDaemonProcessIdentifier: pid_t = 1

    public static func isRestricted(processIdentifier: pid_t) -> Bool {
        processIdentifier == kernelProcessIdentifier || processIdentifier == launchDaemonProcessIdentifier
    }
}
