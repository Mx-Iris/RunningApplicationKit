import MachO
import Testing
@testable import RunningApplicationKit

/// How the raw values the kernel reports about a process become the library's
/// ``Architecture`` and ``Platform``.
@Suite("Kernel value mapping")
struct KernelValueMappingTests {
    @Test("the kernel's platform value 0 means no platform, and other values map like Mach-O constants")
    func kernelPlatformValues() {
        #expect(BSDProcess.platform(kernelValue: 0) == nil)
        #expect(BSDProcess.platform(kernelValue: 1) == .macOS)
        #expect(BSDProcess.platform(kernelValue: 6) == .macCatalyst)
        #expect(BSDProcess.platform(kernelValue: 7) == .iOSSimulator)
        #expect(BSDProcess.platform(kernelValue: 99) == .unknown(99))
    }

    static let architectures: [(cpuType: cpu_type_t, cpuSubtype: cpu_subtype_t, architecture: Architecture)] = [
        (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, .arm64),
        (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64E, .arm64e),
        // arm64e with the pointer authentication ABI bits set in the capability byte,
        // as the kernel reports it for arm64e processes.
        (CPU_TYPE_ARM64, cpu_subtype_t(bitPattern: 0x8000_0002), .arm64e),
        (CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_ALL, .x86_64),
        // 3 is CPU_SUBTYPE_I386_ALL, a function-like macro Swift cannot import.
        (CPU_TYPE_I386, 3, .i386),
        (CPU_TYPE_POWERPC, CPU_SUBTYPE_POWERPC_ALL, .ppc),
        (CPU_TYPE_POWERPC64, CPU_SUBTYPE_POWERPC_ALL, .ppc64),
        (CPU_TYPE_ARM, CPU_SUBTYPE_ARM_ALL, .unknown),
    ]

    @Test("CPU types and subtypes map to architectures, ignoring the capability bits", arguments: architectures)
    func cpuTypesMapToArchitectures(cpuType: cpu_type_t, cpuSubtype: cpu_subtype_t, architecture: Architecture) {
        #expect(BSDProcess.architecture(cpuType: cpuType, cpuSubtype: cpuSubtype) == architecture)
    }
}
