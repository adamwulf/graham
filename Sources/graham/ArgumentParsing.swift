import ArgumentParser

/// Marks a string-backed API enum whose CLI spelling is matched
/// case-insensitively by normalizing it to the wire enum's uppercase form.
protocol UppercasedRawArgument: RawRepresentable, ExpressibleByArgument
where RawValue == String {}

extension UppercasedRawArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.uppercased())
    }
}
