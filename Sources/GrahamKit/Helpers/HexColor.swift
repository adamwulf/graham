import Foundation

enum HexColor {
    /// Formats a read-side RGB color as `#RRGGBB`. Each channel is a float
    /// from 0 to 1; the Google APIs omit a channel whose value is 0, so a
    /// `nil` channel is 0.
    static func string(red: Double?, green: Double?, blue: Double?) -> String {
        func channel(_ value: Double?) -> String {
            let scaled = Int((min(1, max(0, value ?? 0)) * 255).rounded())
            return String(format: "%02X", scaled)
        }
        return "#" + channel(red) + channel(green) + channel(blue)
    }
}
