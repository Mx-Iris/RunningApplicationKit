import AppKit
import LaunchServicesPrivate

extension NSRunningApplication {
    var applicationProxy: LSApplicationProxy? {
        guard let bundleIdentifier else { return nil }
        return LSApplicationProxy(forIdentifier: bundleIdentifier)
    }

    var isSandboxed: Bool {
        guard let entitlements = applicationProxy?.entitlements else { return false }
        guard let isSandboxed = entitlements["com.apple.security.app-sandbox"] as? Bool else { return false }
        return isSandboxed
    }
}
