import AppKit
import IOKit

/// Describes this Mac the way About This Mac does, without exposing the user's computer name.
enum MacInfo {
    static let productName: String = {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        defer { if entry != 0 { IOObjectRelease(entry) } }
        if entry != 0, let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data {
            let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
            if !name.isEmpty { return name }
        }
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }()

    static let chip: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return String(cString: brand)
    }()

    static let osDescription: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        let names = [26: "Tahoe"]
        return "macOS " + (names[v.majorVersion].map { "\($0) " } ?? "") + version
    }()

    static var icon: NSImage { NSImage(named: NSImage.computerName) ?? NSApp.applicationIconImage }

    static let memory = Int64(ProcessInfo.processInfo.physicalMemory)
}
