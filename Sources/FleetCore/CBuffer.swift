import Foundation

// The app's probes and the daemon's device prober both hand buffers to C, so the
// conversion they share lives here rather than once per target.

extension String {
    /// A string from a NUL-terminated `CChar` buffer filled in by a C call.
    ///
    /// `String(cString:)`'s array overload is deprecated under Swift 6, which asks
    /// the caller to truncate where the invariant is known. It is known here —
    /// `sysctlbyname` and `getnameinfo` both NUL-terminate — so take everything
    /// before the first NUL. What follows it is leftover buffer, not text.
    public init(nulTerminated buffer: [CChar]) {
        self = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                      as: UTF8.self)
    }
}
