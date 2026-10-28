import Darwin

/// Physical enN link counters from IFMIB's genuine 64-bit if_data64 fields.
/// getifaddrs exposes 32-bit if_data counters, even on a 64-bit host.
public enum NativeNetworkCounters {
    public static func read() -> [String: NetworkInterfaceCounters]? {
        guard let first = if_nameindex() else { return nil }
        defer { if_freenameindex(first) }

        var interfaces: [(name: String, index: UInt32)] = []
        var pointer = first
        while pointer.pointee.if_index != 0, let name = pointer.pointee.if_name {
            interfaces.append((String(cString: name), pointer.pointee.if_index))
            pointer = pointer.advanced(by: 1)
        }
        return read(interfaces: interfaces, readStatistics: statistics)
    }

    /// The same adapter used by live reads, with only the kernel query injected.
    /// Native ifmibdata fixtures exercise extraction without truncating counters.
    static func read(interfaces: [(name: String, index: UInt32)],
                     readStatistics: (UInt32) -> ifmibdata?) -> [String: NetworkInterfaceCounters]? {
        var counters: [String: NetworkInterfaceCounters] = [:]
        for (name, index) in interfaces {
            let suffix = name.dropFirst(2)
            guard name.hasPrefix("en"), !suffix.isEmpty,
                  suffix.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { continue }
            guard let data = readStatistics(index) else { return nil }
            guard data.ifmd_flags & UInt32(IFF_UP) != 0,
                  data.ifmd_flags & UInt32(IFF_RUNNING) != 0,
                  data.ifmd_flags & UInt32(IFF_LOOPBACK) == 0,
                  data.ifmd_data.ifi_type == UInt8(IFT_ETHER) else { continue }
            counters[name] = NetworkInterfaceCounters(receivedBytes: data.ifmd_data.ifi_ibytes,
                                                       sentBytes: data.ifmd_data.ifi_obytes)
        }
        return counters
    }

    private static func statistics(index: UInt32) -> ifmibdata? {
        guard let index = CInt(exactly: index) else { return nil }
        var mib: [CInt] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, index, IFDATA_GENERAL]
        var data = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, u_int(mib.count), &data, &size, nil, 0) == 0,
              size == MemoryLayout<ifmibdata>.size else { return nil }
        return data
    }
}
