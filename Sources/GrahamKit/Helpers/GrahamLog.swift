import Foundation

/// A logging seam. The library never prints and never imports a logging
/// framework. The CLI (or another consumer) installs a handler.
public enum GrahamLog {
    public static var handler: (@Sendable (String) -> Void)?

    static func log(_ message: String) {
        handler?(message)
    }
}
