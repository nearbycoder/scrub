import Foundation

struct ShellResult {
    var status: Int32
    var output: String
    var error: String?
    var success: Bool { status == 0 }
}

enum Shell {
    /// Runs an executable off the main thread and captures stdout.
    static func run(_ launchPath: String, _ arguments: [String] = [], timeout: TimeInterval = 120) async -> ShellResult {
        await Task.detached(priority: .userInitiated) {
            runSync(launchPath, arguments, timeout: timeout)
        }.value
    }

    static func runSync(_ launchPath: String, _ arguments: [String] = [], timeout: TimeInterval = 120) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            return ShellResult(status: -1, output: "", error: error.localizedDescription)
        }
        // Drain pipes concurrently so large outputs don't deadlock.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let deadline = DispatchTime.now() + timeout
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return ShellResult(status: -2, output: String(decoding: outData, as: UTF8.self), error: "Timed out")
        }
        process.waitUntilExit()
        let errText = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return ShellResult(status: process.terminationStatus,
                           output: String(decoding: outData, as: UTF8.self),
                           error: errText.isEmpty ? nil : errText)
    }

    /// Runs a /bin/sh script with administrator privileges, showing the standard macOS
    /// authentication dialog once for the whole batch.
    static func runAsAdmin(_ script: String) async -> ShellResult {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script \"\(escaped)\" with administrator privileges with prompt \"Scrub needs your permission to run maintenance tasks.\""
        let result = await run("/usr/bin/osascript", ["-e", apple], timeout: 900)
        if let e = result.error, e.contains("-128") {
            return ShellResult(status: 1, output: result.output, error: "Cancelled")
        }
        return result
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func exists(_ tool: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: tool)
    }
}
