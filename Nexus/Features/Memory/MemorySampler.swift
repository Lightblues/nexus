import Darwin
import Foundation

/// Reads memory state from the kernel. Not thread-safe: call from one serial queue.
/// Per-process figures come from `proc_pid_rusage`, which macOS allows only for this
/// user's processes unless the caller is root; other users' processes are skipped.
final class MemorySampler: @unchecked Sendable {   // confined to MemoryWatchService.queue
    private var lastCPU: [Int32: UInt64] = [:]   // pid → user+system ns
    private var lastAt: UInt64 = 0               // mach_absolute_time of the previous sample
    private let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb
    }()

    func snapshot(top n: Int = 8) -> MemorySnapshot {
        MemorySnapshot(level: Self.level(), system: Self.system(), processes: MemoryReport.top(processes(), n))
    }

    func reset() { lastCPU = [:]; lastAt = 0 }

    static func level() -> MemoryLevel {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else { return .normal }
        return MemoryLevel(sysctl: value)
    }

    /// Used = app (internal − purgeable) + wired + compressed, as Activity Monitor counts it.
    static func system() -> SystemMemory {
        var out = SystemMemory()
        var memsize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &memsize, &size, nil, 0) == 0 { out.total = memsize }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let app = UInt64(stats.internal_page_count) &- min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
            out.wired = UInt64(stats.wire_count) * page
            out.compressed = UInt64(stats.compressor_page_count) * page
            out.used = app * page + out.wired + out.compressed
        }

        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            out.swapUsed = swap.xsu_used
            out.swapTotal = swap.xsu_total
        }
        return out
    }

    /// Every process this user may read, with footprint and CPU % since the previous call.
    func processes() -> [ProcessUsage] {
        let now = mach_absolute_time()
        let wallNs = lastAt == 0 ? 0 : nanos(now - lastAt)
        var cpu: [Int32: UInt64] = [:]
        var out: [ProcessUsage] = []
        for pid in Self.pids() where pid > 0 {
            var info = rusage_info_v2()
            let rc = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard rc == 0, info.ri_phys_footprint > 0, let names = Self.names(pid) else { continue }
            let used = nanos(info.ri_user_time &+ info.ri_system_time)
            cpu[pid] = used
            var pct = 0.0
            if wallNs > 0, let prev = lastCPU[pid], used >= prev { pct = Double(used - prev) / Double(wallNs) * 100 }
            out.append(ProcessUsage(pid: pid, name: names.name, app: names.app, footprint: info.ri_phys_footprint, cpuPct: pct))
        }
        lastCPU = cpu
        lastAt = now
        return out
    }

    /// rusage CPU times and mach_absolute_time are in mach ticks (1 ns on Intel, not on Apple silicon).
    private func nanos(_ ticks: UInt64) -> UInt64 {
        timebase.denom == 0 ? ticks : ticks.multipliedReportingOverflow(by: UInt64(timebase.numer)).partialValue / UInt64(timebase.denom)
    }

    private static func pids() -> [Int32] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(n) + 64)
        let got = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return got > 0 ? Array(pids.prefix(Int(got))) : []
    }

    /// The executable name and its app; the path is read only to derive them and then dropped.
    private static func names(_ pid: Int32) -> (name: String, app: String)? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            return ProcessUsage.names(fromPath: String(cString: buf))
        }
        var short = [CChar](repeating: 0, count: 64)
        guard proc_name(pid, &short, UInt32(short.count)) > 0 else { return nil }
        let name = String(cString: short)
        return (name, name)
    }
}
