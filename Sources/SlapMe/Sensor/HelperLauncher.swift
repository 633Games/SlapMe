import AppKit
import Foundation

enum HelperLaunchError: LocalizedError {
    case helperNotFound
    case cancelled
    case appleScriptFailed(String)
    case noSensor

    var errorDescription: String? {
        switch self {
        case .helperNotFound:
            return "Couldn’t find slapme-helper. Rebuild with Scripts/build.sh."
        case .cancelled:
            return "Admin permission was cancelled. Slap detection needs your password once."
        case .appleScriptFailed(let msg):
            return msg
        case .noSensor:
            return "No Apple SPU accelerometer found. SlapMe needs an Apple Silicon MacBook."
        }
    }
}

struct PermissionDiagnostics: Equatable {
    var isAppleSilicon: Bool
    var sensorPresent: Bool
    var helperBinaryFound: Bool
    var helperBinaryPath: String?
    var helperProcessRunning: Bool
    var socketExists: Bool

    var needsSetup: Bool {
        !helperProcessRunning || !socketExists
    }

    var summaryLines: [String] {
        var lines: [String] = []
        lines.append(isAppleSilicon ? "Apple Silicon: yes" : "Apple Silicon: no (required)")
        lines.append(sensorPresent ? "Accelerometer: detected" : "Accelerometer: not found")
        if let path = helperBinaryPath {
            lines.append("Helper binary: \(path)")
        } else {
            lines.append("Helper binary: missing")
        }
        lines.append(helperProcessRunning ? "Helper process: running" : "Helper process: not running")
        lines.append(socketExists ? "Socket: ready" : "Socket: missing")
        return lines
    }
}

enum HelperLauncher {
    static func resolveHelperURL() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []

        // Bundled beside the app executable (Contents/MacOS/slapme-helper)
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exe.appendingPathComponent("slapme-helper"))
        }
        let appURL = Bundle.main.bundleURL
        candidates.append(appURL.deletingLastPathComponent().appendingPathComponent("slapme-helper"))
        candidates.append(appURL.appendingPathComponent("Contents/MacOS/slapme-helper"))
        // Persistent install from Grant access
        candidates.append(URL(fileURLWithPath: "/Library/Application Support/SlapMe/slapme-helper"))

        // Common local build output when opened from repo (~/SlapMe or sibling)
        let home = fm.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent("SlapMe/dist/slapme-helper"))

        for url in candidates {
            if fm.isExecutableFile(atPath: url.path) {
                return url.standardizedFileURL
            }
        }
        return nil
    }

    static func diagnose() -> PermissionDiagnostics {
        let helper = resolveHelperURL()
        let socket = Paths.socketPath
        return PermissionDiagnostics(
            isAppleSilicon: isAppleSilicon(),
            sensorPresent: sensorPresent(),
            helperBinaryFound: helper != nil,
            helperBinaryPath: helper?.path,
            helperProcessRunning: isHelperProcessRunning(),
            socketExists: FileManager.default.fileExists(atPath: socket)
        )
    }

    static func isAppleSilicon() -> Bool {
        var size = 0
        sysctlbyname("hw.optional.arm64", nil, &size, nil, 0)
        var value: Int32 = 0
        sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return value == 1
    }

    static func sensorPresent() -> Bool {
        // Keep this cheap — full `ioreg -l` can hang the main thread for seconds.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-c", "AppleSPUHIDDevice", "-d", "1"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            let deadline = Date().addingTimeInterval(1.5)
            while task.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if task.isRunning {
                task.terminate()
                return isAppleSilicon() // best-effort fallback
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            return out.contains("AppleSPUHIDDevice")
        } catch {
            return isAppleSilicon()
        }
    }

    static func isHelperProcessRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "slapme-helper"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Prompts for admin once: installs helper + LaunchDaemon (survives reboot) and starts it.
    static func startHelperWithAdminPrompt() throws {
        guard let helper = resolveHelperURL() else {
            throw HelperLaunchError.helperNotFound
        }
        if !sensorPresent() && !isAppleSilicon() {
            throw HelperLaunchError.noSensor
        }

        Paths.ensureSupportDirectories()
        let socket = Paths.socketPath
        let logPath = "/tmp/slapme-helper.log"
        let installDir = "/Library/Application Support/SlapMe"
        let installedHelper = "\(installDir)/slapme-helper"
        let plistPath = "/Library/LaunchDaemons/game.sixthree.slapme-helper.plist"
        let stagedPlist = Paths.supportDirectory.appendingPathComponent("slapme-helper.plist")

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>game.sixthree.slapme-helper</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(installedHelper)</string>
            <string>--socket</string>
            <string>\(socket)</string>
          </array>
          <key>EnvironmentVariables</key>
          <dict>
            <key>SLAPME_SOCKET</key>
            <string>\(socket)</string>
          </dict>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(logPath)</string>
          <key>StandardErrorPath</key>
          <string>\(logPath)</string>
        </dict>
        </plist>
        """
        do {
            try plist.write(to: stagedPlist, atomically: true, encoding: .utf8)
        } catch {
            throw HelperLaunchError.appleScriptFailed("Could not stage LaunchDaemon plist: \(error.localizedDescription)")
        }

        let cmd = [
            "mkdir -p \(shellEscape(installDir))",
            "cp \(shellEscape(helper.path)) \(shellEscape(installedHelper))",
            "chmod 755 \(shellEscape(installedHelper))",
            "cp \(shellEscape(stagedPlist.path)) \(shellEscape(plistPath))",
            "pkill -x slapme-helper || true",
            "launchctl bootout system \(shellEscape(plistPath)) 2>/dev/null || true",
            "launchctl bootstrap system \(shellEscape(plistPath))",
            "launchctl enable system/game.sixthree.slapme-helper",
            "launchctl kickstart -k system/game.sixthree.slapme-helper",
        ].joined(separator: " && ")

        let script = appleScriptShell(cmd)
        let result = runAppleScript(script)
        if let error = result.error {
            let msg = error[NSLocalizedDescriptionKey] as? String ?? "\(error)"
            if msg.localizedCaseInsensitiveContains("user canceled")
                || msg.localizedCaseInsensitiveContains("user cancelled")
                || (error[NSAppleScript.errorNumber] as? Int) == -128 {
                throw HelperLaunchError.cancelled
            }
            // Fall back to one-shot start if LaunchDaemon install fails.
            try startHelperOneShot(helper: helper, socket: socket, logPath: logPath)
            return
        }
    }

    private static func startHelperOneShot(helper: URL, socket: String, logPath: String) throws {
        let cmd = [
            "pkill -x slapme-helper || true",
            "SLAPME_SOCKET=\(shellEscape(socket)) \(shellEscape(helper.path)) --socket \(shellEscape(socket)) >> \(shellEscape(logPath)) 2>&1 & echo $!",
        ].joined(separator: "; ")
        let result = runAppleScript(appleScriptShell(cmd))
        if let error = result.error {
            let msg = error[NSLocalizedDescriptionKey] as? String ?? "\(error)"
            if msg.localizedCaseInsensitiveContains("user canceled")
                || msg.localizedCaseInsensitiveContains("user cancelled")
                || (error[NSAppleScript.errorNumber] as? Int) == -128 {
                throw HelperLaunchError.cancelled
            }
            throw HelperLaunchError.appleScriptFailed(msg)
        }
    }

    private static func appleScriptShell(_ command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    static func copySetupCommandToClipboard() {
        let helper = resolveHelperURL()?.path
            ?? "$(pwd)/dist/slapme-helper"
        let socket = Paths.socketPath
        let cmd = """
        sudo SLAPME_SOCKET="\(socket)" "\(helper)" --socket "\(socket)"
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    static func openHelperLog() {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("slapme-helper.log")
        if FileManager.default.fileExists(atPath: log.path) {
            NSWorkspace.shared.open(log)
        } else {
            NSWorkspace.shared.open(FileManager.default.temporaryDirectory)
        }
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAppleScript(_ source: String) -> (string: String?, error: NSDictionary?) {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let output = script?.executeAndReturnError(&error)
        return (output?.stringValue, error)
    }
}
