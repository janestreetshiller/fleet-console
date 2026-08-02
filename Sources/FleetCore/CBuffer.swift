import Foundation

// The app's probes and the daemon's device prober both hand buffers to C and take
// them back, so the one conversion they share lives in FleetCore rather than being
// written out at each `sysctlbyname` and `getnameinfo` call site — or, worse, once
// per target.

extension String {
    /// A string from a NUL-terminated `CChar` buffer filled in by a C call.
    ///
    /// `String(cString:)`'s array overload is deprecated under Swift 6: it reads up
    /// to the first NUL and is silent about a buffer that has none, so the standard
    /// library now asks the caller to do the truncation where the invariant is
    /// actually known. Here it is known — `sysctlbyname` and `getnameinfo` both
    /// NUL-terminate — so this takes everything before the first NUL and decodes it
    /// as UTF-8. Whatever sits past the terminator is leftover buffer, not text.
    public init(nulTerminated buffer: [CChar]) {
        self = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                      as: UTF8.self)
    }
}
