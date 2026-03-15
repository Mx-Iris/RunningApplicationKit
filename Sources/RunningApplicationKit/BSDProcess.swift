import Darwin
import MachO

enum BSDProcess {
    static func allPIDs() -> [pid_t] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let pidCount = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: pidCount)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.size
        return Array(pids[0..<actualCount].filter { $0 > 0 })
    }

    static func name(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { ptr in
            String(decoding: UnsafeRawBufferPointer(ptr).prefix(Int(length)), as: UTF8.self)
        }
    }

    static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { ptr in
            String(decoding: UnsafeRawBufferPointer(ptr).prefix(Int(length)), as: UTF8.self)
        }
    }

    static func isRunning(pid: pid_t) -> Bool {
        // kill(pid, 0) returns 0 if we have permission, or -1 with EPERM if the process
        // exists but belongs to another user. Both cases mean the process is running.
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Architecture Detection

    static func architecture(for pid: pid_t) -> Architecture? {
        guard let path = executablePath(for: pid) else { return nil }
        return executableArchitecture(atPath: path, pid: pid)
    }

    private static func executableArchitecture(atPath path: String, pid: pid_t) -> Architecture? {
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else {
            // Can't read executable (SIP, permissions, etc.), fall back to translation check
            return architectureFromTranslationStatus(pid: pid)
        }
        defer { Darwin.close(fd) }

        var magic: UInt32 = 0
        guard Darwin.read(fd, &magic, MemoryLayout<UInt32>.size) == MemoryLayout<UInt32>.size else {
            return architectureFromTranslationStatus(pid: pid)
        }
        lseek(fd, 0, SEEK_SET)

        switch magic {
        case MH_MAGIC_64:
            var header = mach_header_64()
            guard Darwin.read(fd, &header, MemoryLayout<mach_header_64>.size) == MemoryLayout<mach_header_64>.size else { return nil }
            return architectureFrom(header.cputype)
        case MH_CIGAM_64:
            var header = mach_header_64()
            guard Darwin.read(fd, &header, MemoryLayout<mach_header_64>.size) == MemoryLayout<mach_header_64>.size else { return nil }
            return architectureFrom(cpu_type_t(bigEndian: header.cputype))
        case MH_MAGIC:
            var header = mach_header()
            guard Darwin.read(fd, &header, MemoryLayout<mach_header>.size) == MemoryLayout<mach_header>.size else { return nil }
            return architectureFrom(header.cputype)
        case MH_CIGAM:
            var header = mach_header()
            guard Darwin.read(fd, &header, MemoryLayout<mach_header>.size) == MemoryLayout<mach_header>.size else { return nil }
            return architectureFrom(cpu_type_t(bigEndian: header.cputype))
        case FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64:
            // Universal binary: determine which slice is actually running
            return architectureFromTranslationStatus(pid: pid)
        default:
            return nil
        }
    }

    private static func architectureFromTranslationStatus(pid: pid_t) -> Architecture {
        if isTranslated(pid: pid) {
            return .x86_64
        }
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .unknown
        #endif
    }

    private static func isTranslated(pid: pid_t) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        // P_TRANSLATED = 0x00020000 (process is running under Rosetta translation)
        return (info.kp_proc.p_flag & 0x00020000) != 0
    }

    private static func architectureFrom(_ cputype: cpu_type_t) -> Architecture {
        switch cputype {
        case CPU_TYPE_ARM64: return .arm64
        case CPU_TYPE_X86_64: return .x86_64
        case CPU_TYPE_I386: return .i386
        case CPU_TYPE_POWERPC: return .ppc
        case CPU_TYPE_POWERPC64: return .ppc64
        default: return .unknown
        }
    }

    // MARK: - Sandbox Detection

    static func isSandboxed(pid: pid_t) -> Bool {
        // csops(pid, CS_OPS_STATUS, &flags, sizeof(flags))
        // csops is not exposed in Swift headers, so we load it dynamically
        var flags: UInt32 = 0
        let result = csopsFunction(pid, 0 /* CS_OPS_STATUS */, &flags, MemoryLayout<UInt32>.size)
        guard result == 0 else { return false }
        // CS_SANDBOX = 0x00000100
        return (flags & 0x00000100) != 0
    }

    private static let csopsFunction: @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32 = {
        unsafeBitCast(dlsym(dlopen(nil, RTLD_LAZY), "csops"), to: (@convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32).self)
    }()
}
