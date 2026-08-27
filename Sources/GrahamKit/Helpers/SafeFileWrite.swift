import Foundation

/// A file could not be written safely.
private struct SafeFileWriteError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// Writes `data` to `url` without following a symlink at the final path
/// component.
///
/// `Data.write(to:)` follows a symlink, so a symlink pre-planted at a
/// deterministic target name could redirect the write outside the target
/// directory — the callers' lexical parent-directory guards cannot see it.
/// Opening with `O_NOFOLLOW` makes `open` fail (`ELOOP`) when the final
/// component is a symlink, closing that hole atomically with no
/// check-then-write race, while `O_CREAT | O_TRUNC` still create or overwrite
/// an ordinary file. Any failure throws, so the caller records a `.failed`
/// download instead of writing through the link.
internal func writeRefusingSymlink(_ data: Data, to url: URL) throws {
    let descriptor = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
        guard let pointer else { return -1 }
        return open(pointer, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o644)
    }
    guard descriptor >= 0 else {
        throw SafeFileWriteError(
            reason: "cannot open \(url.lastPathComponent): "
                + String(cString: strerror(errno)))
    }
    defer { close(descriptor) }
    try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard var pointer = raw.baseAddress else { return }
        var remaining = raw.count
        while remaining > 0 {
            let written = write(descriptor, pointer, remaining)
            if written < 0 {
                throw SafeFileWriteError(
                    reason: "cannot write \(url.lastPathComponent): "
                        + String(cString: strerror(errno)))
            }
            remaining -= written
            pointer = pointer.advanced(by: written)
        }
    }
}
