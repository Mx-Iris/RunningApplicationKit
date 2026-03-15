import AppKit

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

    private static let sandboxEntitlementKey = "com.apple.security.app-sandbox"

    var isSandboxed: Bool {
        guard let bundleIdentifier else { return false }
        guard let proxyClass = NSClassFromString("LSApplicationProxy") as? NSObject.Type else { return false }

        let proxySelector = NSSelectorFromString("applicationProxyForIdentifier:")
        guard proxyClass.responds(to: proxySelector),
              let proxy = proxyClass.perform(proxySelector, with: bundleIdentifier)?.takeUnretainedValue() as? NSObject else { return false }

        let entitlementsSelector = NSSelectorFromString("entitlements")
        guard proxy.responds(to: entitlementsSelector),
              let entitlements = proxy.perform(entitlementsSelector)?.takeUnretainedValue() as? [String: Any] else { return false }

        return entitlements[Self.sandboxEntitlementKey] as? Bool ?? false
    }
}
