import Darwin
import Foundation

/// One process as the kernel reports it at one moment.
public struct ProcessSample: Sendable, Equatable {
    public let pid: Int32
    /// The executable's file name — "ollama", "com.docker.backend".
    public let name: String
    /// The executable's full path; empty when the kernel would not say.
    public let path: String
    public let residentBytes: UInt64
    /// User + system CPU time since the process started.
    public let cpuTimeNanoseconds: UInt64

    public init(pid: Int32, name: String, path: String, residentBytes: UInt64, cpuTimeNanoseconds: UInt64) {
        self.pid = pid
        self.name = name
        self.path = path
        self.residentBytes = residentBytes
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
    }
}

/// The running processes, read through libproc.
///
/// Only processes this user may inspect are returned: another user's (root's,
/// mostly) task info is refused by the kernel, and those are skipped.
public enum ProcessTable {

    @Sendable
    public static func snapshot() -> [ProcessSample] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        // Room for processes started between the two calls.
        var pids = [Int32](repeating: 0, count: Int(capacity) + 64)
        let listed = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard listed > 0 else { return [] }
        return pids.prefix(Int(listed)).compactMap { pid in pid > 0 ? sample(pid: pid) : nil }
    }

    static func sample(pid: Int32) -> ProcessSample? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        let path = executablePath(pid: pid)
        let name = path.isEmpty ? processName(pid: pid) : (path as NSString).lastPathComponent
        return ProcessSample(
            pid: pid,
            name: name,
            path: path,
            residentBytes: info.pti_resident_size,
            cpuTimeNanoseconds: nanoseconds(fromMachTime: info.pti_total_user + info.pti_total_system)
        )
    }

    /// Paths of the regular files `pid` holds open. Costs a syscall per open
    /// file, so it is for the odd process a matcher needs to look inside, not
    /// for every process on the machine.
    @Sendable
    public static func openFilePaths(pid: Int32) -> [String] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / stride)
        let filled = fds.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard filled > 0 else { return [] }
        return fds.prefix(Int(filled) / stride).compactMap { descriptor in
            guard descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { return nil }
            var vnode = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            let read = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnode, size)
            guard read == size else { return nil }
            return withUnsafeBytes(of: vnode.pvip.vip_path) { raw in
                String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8)
            }
        }
    }

    private static func executablePath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(bytes: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }

    private static func processName(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(bytes: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }

    /// `pti_total_user`/`pti_total_system` are Mach absolute time units, which
    /// are nanoseconds on Intel but 125/3 ns ticks on Apple silicon.
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func nanoseconds(fromMachTime ticks: UInt64) -> UInt64 {
        guard timebase.denom != 0 else { return ticks }
        let (product, overflow) = ticks.multipliedReportingOverflow(by: UInt64(timebase.numer))
        if overflow { return ticks / UInt64(timebase.denom) * UInt64(timebase.numer) }
        return product / UInt64(timebase.denom)
    }
}
