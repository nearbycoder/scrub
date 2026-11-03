import Foundation
import IOKit
import IOKit.ps
import Darwin
import Observation

struct ProcessSample: Identifiable, Hashable {
    let pid: Int32
    let name: String
    let cpu: Double
    let memory: Int64
    let user: String
    var id: Int32 { pid }
}

@Observable
final class SystemMonitor {
    static let shared = SystemMonitor()
    static let historyLength = 60

    // CPU
    var cpuUsage: Double = 0
    var coreUsage: [Double] = []
    var cpuHistory: [Double] = []
    var loadAverage: (Double, Double, Double) = (0, 0, 0)
    // GPU
    var gpuUsage: Double?
    var gpuHistory: [Double] = []
    // Memory
    var memoryTotal: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    var memoryUsed: Int64 = 0
    var memoryApp: Int64 = 0
    var memoryWired: Int64 = 0
    var memoryCompressed: Int64 = 0
    var memoryCached: Int64 = 0
    var swapUsed: Int64 = 0
    var memoryPressure = 1
    var memoryHistory: [Double] = []
    // Disk
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0
    var diskPurgeable: Int64 = 0
    var diskReadRate: Double = 0
    var diskWriteRate: Double = 0
    var diskHistory: [Double] = []
    // Network
    var netDownRate: Double = 0
    var netUpRate: Double = 0
    var netDownHistory: [Double] = []
    var netUpHistory: [Double] = []
    // Power
    var battery: BatteryInfo?
    var thermalState: ProcessInfo.ThermalState = .nominal
    var uptime: TimeInterval = 0
    // Processes
    var topProcesses: [ProcessSample] = []

    struct BatteryInfo: Equatable {
        var level: Int
        var isCharging: Bool
        var isPluggedIn: Bool
        var cycleCount: Int?
        var health: Int?
        var temperature: Double?
        var watts: Double?
        var timeRemaining: Int?
        var condition: String?
    }

    var diskUsed: Int64 { max(0, diskTotal - diskFree) }
    var diskFraction: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }
    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }

    var pressureLabel: String {
        switch memoryPressure { case 4: "Critical"; case 2: "Elevated"; default: "Normal" }
    }

    var healthScore: Int {
        var score = 100.0
        if cpuUsage > 0.85 { score -= 12 } else if cpuUsage > 0.6 { score -= 5 }
        if memoryPressure == 4 { score -= 25 } else if memoryPressure == 2 { score -= 12 }
        if diskFraction > 0.95 { score -= 25 } else if diskFraction > 0.9 { score -= 15 } else if diskFraction > 0.8 { score -= 6 }
        switch thermalState {
        case .critical: score -= 25
        case .serious: score -= 15
        case .fair: score -= 5
        default: break
        }
        if let h = battery?.health, h < 80 { score -= 8 }
        if swapUsed > 4 * 1_073_741_824 { score -= 6 }
        if uptime > 14 * 86_400 { score -= 6 } else if uptime > 7 * 86_400 { score -= 3 }
        return max(0, min(100, Int(score.rounded())))
    }

    var healthSummary: String {
        switch healthScore {
        case 90...: "Excellent"
        case 75..<90: "Good"
        case 55..<75: "Fair"
        default: "Needs attention"
        }
    }

    var issues: [String] {
        var list: [String] = []
        if diskFraction > 0.9 { list.append("Startup disk is \(Int(diskFraction * 100))% full") }
        if memoryPressure >= 2 { list.append("Memory pressure is \(pressureLabel.lowercased())") }
        if thermalState == .serious || thermalState == .critical { list.append("Your Mac is running hot") }
        if let h = battery?.health, h < 80 { list.append("Battery health is \(h)%") }
        if uptime > 7 * 86_400 { list.append("Not restarted in \(Int(uptime / 86_400)) days") }
        if cpuUsage > 0.85 { list.append("CPU is under heavy load") }
        return list
    }

    private var timer: Timer?
    private var consumers: Set<String> = []
    private var processSampler = ProcessSampler()
    private var previousCPU: [processor_cpu_load_info] = []
    private var previousNet: (down: UInt64, up: UInt64, time: Date)?
    private var previousDisk: (read: UInt64, write: UInt64, time: Date)?
    private var tick = 0

    private init() {}

    /// Starts slow background sampling (disk space only). Views that show live data call `acquire`,
    /// which switches to full-rate sampling until every consumer has called `release`.
    func start() {
        guard timer == nil else { return }
        sampleDisk()
        reschedule()
    }

    func acquire(_ consumer: String) {
        let wasIdle = consumers.isEmpty
        consumers.insert(consumer)
        if wasIdle { sample(); reschedule() }
    }

    func release(_ consumer: String) {
        consumers.remove(consumer)
        if consumers.isEmpty { reschedule() }
    }

    private var isLive: Bool { !consumers.isEmpty }

    private func reschedule() {
        timer?.invalidate()
        let interval: TimeInterval = isLive ? 1.5 : 20
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isLive { self.sample() } else { self.sampleDisk() }
        }
        timer?.tolerance = interval * 0.2
    }

    private func push(_ value: Double, into history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    private func sample() {
        tick += 1
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        sampleDiskIO()
        let gpu = Self.readGPU()
        if gpu != gpuUsage { gpuUsage = gpu }
        push(gpu ?? 0, into: &gpuHistory)
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal != thermalState { thermalState = thermal }
        uptime = ProcessInfo.processInfo.systemUptime
        if tick % 4 == 1 {
            sampleDisk()
            let b = Self.readBattery()
            if b != battery { battery = b }
        }
        if consumers.contains("processes") && tick % 2 == 1 { sampleProcesses() }
    }

    private func sampleCPU() {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        let loads = info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(count)) {
            Array(UnsafeBufferPointer(start: $0, count: Int(count)))
        }
        if previousCPU.count == loads.count {
            var cores: [Double] = []
            var totalBusy: Double = 0, totalAll: Double = 0
            for (now, prev) in zip(loads, previousCPU) {
                let user = Double(now.cpu_ticks.0 &- prev.cpu_ticks.0)
                let system = Double(now.cpu_ticks.1 &- prev.cpu_ticks.1)
                let idle = Double(now.cpu_ticks.2 &- prev.cpu_ticks.2)
                let nice = Double(now.cpu_ticks.3 &- prev.cpu_ticks.3)
                let busy = user + system + nice
                let all = busy + idle
                cores.append(all > 0 ? busy / all : 0)
                totalBusy += busy; totalAll += all
            }
            coreUsage = cores
            cpuUsage = totalAll > 0 ? totalBusy / totalAll : 0
            push(cpuUsage, into: &cpuHistory)
        }
        previousCPU = loads
        var avg = [Double](repeating: 0, count: 3)
        if getloadavg(&avg, 3) == 3 { loadAverage = (avg[0], avg[1], avg[2]) }
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Int64(vm_kernel_page_size)
        memoryApp = (Int64(stats.internal_page_count) - Int64(stats.purgeable_count)) * page
        memoryWired = Int64(stats.wire_count) * page
        memoryCompressed = Int64(stats.compressor_page_count) * page
        memoryCached = (Int64(stats.external_page_count) + Int64(stats.purgeable_count)) * page
        memoryUsed = memoryApp + memoryWired + memoryCompressed
        push(memoryFraction, into: &memoryHistory)

        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0, Int(level) != memoryPressure { memoryPressure = Int(level) }
        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { swapUsed = Int64(swap.xsu_used) }
    }

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) {
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let important = values.volumeAvailableCapacityForImportantUsage ?? 0
            let plain = Int64(values.volumeAvailableCapacity ?? 0)
            let free = important > 0 ? important : plain
            // Only publish real changes so views that show disk space don't redraw for nothing.
            if total != diskTotal { diskTotal = total }
            if abs(free - diskFree) > 1_000_000 { diskFree = free }
            if max(0, free - plain) != diskPurgeable { diskPurgeable = max(0, free - plain) }
        }
    }

    private func sampleNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var down: UInt64 = 0, up: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               !name.hasPrefix("lo"), !name.hasPrefix("utun"), !name.hasPrefix("awdl"), !name.hasPrefix("llw"),
               let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                down += UInt64(data.pointee.ifi_ibytes)
                up += UInt64(data.pointee.ifi_obytes)
            }
            ptr = p.pointee.ifa_next
        }
        let now = Date()
        if let prev = previousNet {
            let dt = now.timeIntervalSince(prev.time)
            if dt > 0 {
                netDownRate = down >= prev.down ? Double(down - prev.down) / dt : 0
                netUpRate = up >= prev.up ? Double(up - prev.up) / dt : 0
            }
        }
        previousNet = (down, up, now)
        push(netDownRate, into: &netDownHistory)
        push(netUpRate, into: &netUpHistory)
    }

    private func sampleDiskIO() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, write: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let props = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (props["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (props["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        let now = Date()
        if let prev = previousDisk {
            let dt = now.timeIntervalSince(prev.time)
            if dt > 0 {
                diskReadRate = read >= prev.read ? Double(read - prev.read) / dt : 0
                diskWriteRate = write >= prev.write ? Double(write - prev.write) / dt : 0
            }
        }
        previousDisk = (read, write, now)
        push(diskReadRate + diskWriteRate, into: &diskHistory)
    }

    static func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        var value: Double?
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let util = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber {
                value = max(value ?? 0, util.doubleValue / 100)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return value
    }

    static func readBattery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            var info = BatteryInfo(level: max > 0 ? current * 100 / max : current,
                                   isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                                   isPluggedIn: (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
            if let t = desc[kIOPSTimeToEmptyKey] as? Int, t > 0 { info.timeRemaining = t }
            info.condition = desc["BatteryHealth"] as? String

            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                let batteryData = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] ?? [:]
                // Newer macOS releases nest most battery details inside BatteryData.
                func prop(_ key: String) -> Any? {
                    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() ?? batteryData[key]
                }
                info.cycleCount = prop("CycleCount") as? Int
                if let design = prop("DesignCapacity") as? Int, design > 0,
                   let full = (prop("NominalChargeCapacity") ?? prop("AppleRawMaxCapacity")) as? Int {
                    info.health = min(100, Int((Double(full) * 100 / Double(design)).rounded()))
                }
                if let t = prop("Temperature") as? Int { info.temperature = Double(t) / 100 }
                if let v = prop("Voltage") as? Int, let a = prop("InstantAmperage") as? Int ?? prop("Amperage") as? Int {
                    let amps = Double(Int16(truncatingIfNeeded: a)) / 1000
                    info.watts = abs(Double(v) / 1000 * amps)
                }
            }
            return info
        }
        return nil
    }

    private func sampleProcesses() {
        let sampler = processSampler
        Task.detached(priority: .utility) { [weak self] in
            let list = sampler.sample()
            await MainActor.run { self?.topProcesses = list }
        }
    }
}

/// Reads per-process CPU time and memory footprint through libproc. Unlike shelling out to `ps`,
/// this costs a couple of system calls per process and no subprocess.
final class ProcessSampler: @unchecked Sendable {
    private var previous: [pid_t: UInt64] = [:]
    private var previousTime: UInt64 = 0
    private let lock = NSLock()
    private let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()
    private var names: [pid_t: (String, String)] = [:]

    func sample(limit: Int = 60) -> [ProcessSample] {
        lock.lock(); defer { lock.unlock() }
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }
        let now = mach_absolute_time()
        let elapsedNs = Double(now &- previousTime) * timebase
        var current: [pid_t: UInt64] = [:]
        var samples: [ProcessSample] = []
        for pid in pids.prefix(count) where pid > 0 {
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)) == MemoryLayout<proc_taskinfo>.size else { continue }
            let cpuTime = info.pti_total_user + info.pti_total_system
            current[pid] = cpuTime
            var cpu = 0.0
            if let before = previous[pid], previousTime > 0, elapsedNs > 0, cpuTime >= before {
                cpu = Double(cpuTime - before) * timebase / elapsedNs * 100
            }
            var usage = rusage_info_v4()
            let footprint: Int64 = withUnsafeMutablePointer(to: &usage) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            } == 0 ? Int64(usage.ri_phys_footprint) : Int64(info.pti_resident_size)
            let (name, user) = identity(pid)
            samples.append(ProcessSample(pid: pid, name: name, cpu: cpu, memory: footprint, user: user))
        }
        previous = current
        previousTime = now
        names = names.filter { current[$0.key] != nil }
        let byCPU = samples.sorted { $0.cpu > $1.cpu }.prefix(limit)
        let byMemory = samples.sorted { $0.memory > $1.memory }.prefix(limit)
        var seen = Set<pid_t>()
        return (byCPU + byMemory).filter { seen.insert($0.pid).inserted }
    }

    private func identity(_ pid: pid_t) -> (String, String) {
        if let cached = names[pid] { return cached }
        var name = ""
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            // Prefer the app name for anything inside an .app bundle's MacOS folder.
            if let range = path.range(of: ".app/Contents/MacOS/") {
                name = (String(path[..<range.lowerBound]) as NSString).lastPathComponent
                if path[range.upperBound...].contains("/") || (path as NSString).lastPathComponent != name {
                    name = (path as NSString).lastPathComponent
                }
            } else {
                name = (path as NSString).lastPathComponent
            }
        }
        if name.isEmpty {
            var short = [CChar](repeating: 0, count: 64)
            proc_name(pid, &short, UInt32(short.count))
            name = String(cString: short)
        }
        if pid == 0 { name = "kernel_task" }
        var bsd = proc_bsdshortinfo()
        var user = ""
        if proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdshortinfo>.size)) > 0,
           let pw = getpwuid(bsd.pbsi_uid) {
            user = String(cString: pw.pointee.pw_name)
        }
        names[pid] = (name, user)
        return (name, user)
    }
}

extension Double {
    var formattedRate: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file) + "/s"
    }
    var percent: String { "\(Int((self * 100).rounded()))%" }
}

extension TimeInterval {
    var uptimeDescription: String {
        let days = Int(self) / 86_400, hours = (Int(self) % 86_400) / 3600, minutes = (Int(self) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
