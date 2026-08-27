enum GrahamValidation {
    /// Returns a deterministic comma-separated field mask, or rejects an
    /// update that would not change any field.
    static func requireFieldMask(_ mask: [String], _ message: String) throws -> String {
        guard !mask.isEmpty else {
            throw GrahamError.invalidArgument(message)
        }
        return mask.joined(separator: ",")
    }
}
