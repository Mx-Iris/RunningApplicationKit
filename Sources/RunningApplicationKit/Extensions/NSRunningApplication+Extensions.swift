import AppKit
import LaunchServicesPrivate

extension NSRunningApplication {
    var architecture: Architecture {
        switch executableArchitecture {
        case NSBundleExecutableArchitectureARM64:
            return .arm64
        case NSBundleExecutableArchitectureX86_64:
            return .x86_64
        case NSBundleExecutableArchitectureI386:
            return .i386
        case NSBundleExecutableArchitecturePPC:
            return .ppc
        case NSBundleExecutableArchitecturePPC64:
            return .ppc64
        default:
            return .unknown
        }
    }

    var applicationProxy: LSApplicationProxy? {
        guard let bundleIdentifier else { return nil }
        return LSApplicationProxy(forIdentifier: bundleIdentifier)
    }

    private static let sandboxEntitlementKey = "com.apple.security.app-sandbox"

    var isSandboxed: Bool {
        guard let entitlements = applicationProxy?.entitlements else { return false }
        return entitlements[Self.sandboxEntitlementKey] as? Bool ?? false
    }
}
