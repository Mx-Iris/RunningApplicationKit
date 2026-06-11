import AppKit

extension NSRunningApplication {
    // executableArchitecture only surfaces cputype, so arm64 and arm64e collapse
    // to a single value. Route through BSDProcess.architecture(for:) which uses
    // proc_pidinfo(PROC_PIDARCHINFO) and preserves cpusubtype.
    var architecture: Architecture? {
        BSDProcess.architecture(for: processIdentifier)
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
