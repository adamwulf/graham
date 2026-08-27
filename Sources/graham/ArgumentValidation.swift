import ArgumentParser

/// Rejects an alpha that is present but outside 0...1.
func validateAlpha(_ alpha: Double?, name: String) throws {
    if let alpha, !(alpha >= 0 && alpha <= 1) {
        throw ValidationError("\(name) must be between 0 and 1.")
    }
}

/// Rejects a value that is absent from the strict positive finite domain.
func validatePositive(_ value: Double?, name: String) throws {
    try validatePositive(value, message: "\(name) must be greater than zero.")
}

/// Applies strict positive finite validation while preserving a call site's
/// established argument-error text.
func validatePositive(_ value: Double?, message: String) throws {
    if let value, !(value.isFinite && value > 0) {
        throw ValidationError(message)
    }
}

/// Rejects a floating-point value that is present but below zero.
func validateNonNegative(_ value: Double?, message: String) throws {
    if let value, value < 0 {
        throw ValidationError(message)
    }
}

/// Rejects an integer value that is present but below zero.
func validateNonNegative(_ value: Int?, message: String) throws {
    if let value, value < 0 {
        throw ValidationError(message)
    }
}

/// Rejects an index or span that is present but below the one-based minimum.
func validateOneBased(_ value: Int?, name: String) throws {
    try validateOneBased(
        value, message: "\(name) must be one-based (1 or greater).")
}

/// Applies one-based validation while preserving a call site's established
/// argument-error text.
func validateOneBased(_ value: Int?, message: String) throws {
    if let value, value < 1 {
        throw ValidationError(message)
    }
}
