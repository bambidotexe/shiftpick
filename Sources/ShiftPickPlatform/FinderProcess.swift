import AppKit

/// Whether Finder is running, for the Health page. A read of the workspace's own list of running apps: it
/// asks Finder nothing, makes no Accessibility call, and answers at once.
public enum FinderProcess {
    public static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: FinderAX.bundleIdentifier).isEmpty
    }
}
