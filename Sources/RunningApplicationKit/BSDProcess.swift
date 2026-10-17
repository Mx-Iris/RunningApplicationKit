import Darwin
import MachO
import Security
internal import ProcessInformationPrivate
internal import System

/// The process queries this library makes, answered by swift-proc.
enum BSDProcess {
    static func allPIDs() -> [pid_t] {
        guard let processes = try? ProcessIdentifier.list() else { return [] }
        return processes.map(\.rawValue).filter { $0 > 0 }
    }

    /// The name the kernel records for the process: the executable's file name,
    /// cut to 31 bytes.
    ///
    /// A symbolic link the process was started through does not count; the
    /// kernel names it after the file the link resolves to. The kernel answers
    /// only for processes of the same user, unless the caller is root, while it
    /// gives out the executable path for any process.
    static func name(for pid: pid_t) -> String? {
        try? ProcessIdentifier(rawValue: pid).name()
    }

    static func executablePath(for pid: pid_t) -> String? {
        guard let path = try? ProcessIdentifier(rawValue: pid).executablePath() else { return nil }
        return String(decoding: path)
    }

    static func isRunning(pid: pid_t) -> Bool {
        // kill(pid, 0) returns 0 if we have permission, or -1 with EPERM if the process
        // exists but belongs to another user. Both cases mean the process is running.
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Architecture Detection

    /// The architecture the kernel runs the process as, which tells arm64e from
    /// arm64 and a process translated by Rosetta from a native one.
    ///
    /// The kernel answers this only for processes of the same user, unless the
    /// caller is root.
    static func architecture(for pid: pid_t) -> Architecture? {
        guard let architecture = try? ProcessIdentifier(rawValue: pid).architecture() else { return nil }
        return Self.architecture(cpuType: architecture.cpuType, cpuSubtype: architecture.cpuSubtype)
    }

    static func architecture(cpuType: cpu_type_t, cpuSubtype: cpu_subtype_t) -> Architecture {
        // Strip CPU_SUBTYPE_MASK (0xff000000 capability bits) before matching.
        let subtype = cpuSubtype & 0x00ff_ffff
        switch cpuType {
        case CPU_TYPE_ARM64:
            return subtype == CPU_SUBTYPE_ARM64E ? .arm64e : .arm64
        case CPU_TYPE_X86_64: return .x86_64
        case CPU_TYPE_I386: return .i386
        case CPU_TYPE_POWERPC: return .ppc
        case CPU_TYPE_POWERPC64: return .ppc64
        default: return .unknown
        }
    }

    // MARK: - Platform Detection

    /// The platform the process's executable was built for, as the kernel
    /// recorded it when the process started.
    ///
    /// Any caller may ask about any process. The kernel reads the platform from
    /// the slice of the executable it actually loaded, so a simulator process is
    /// reported as a simulator platform although it runs as native arm64.
    static func platform(for pid: pid_t) -> Platform? {
        guard let platform = try? ProcessIdentifier(rawValue: pid).platform() else { return nil }
        return Self.platform(kernelValue: platform.rawValue)
    }

    /// Maps the kernel's `PLATFORM_*` value to a ``Platform``; `0` means the
    /// kernel recorded no platform.
    static func platform(kernelValue: UInt32) -> Platform? {
        kernelValue == 0 ? nil : Platform(machOPlatformValue: kernelValue)
    }

    // MARK: - Sandbox Detection

    static func isSandboxed(pid: pid_t) -> Bool {
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info
        ) == errSecSuccess, let info = info as? [String: Any] else { return false }

        guard let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else {
            return false
        }
        return entitlements["com.apple.security.app-sandbox"] as? Bool ?? false
    }
}
