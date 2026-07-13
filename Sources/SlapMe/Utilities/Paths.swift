import Foundation

enum Paths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SlapMe", isDirectory: true)
    }

    static var customPacksDirectory: URL {
        supportDirectory.appendingPathComponent("Packs", isDirectory: true)
    }

    static var socketPath: String {
        if let env = ProcessInfo.processInfo.environment["SLAPME_SOCKET"], !env.isEmpty {
            return env
        }
        return supportDirectory.appendingPathComponent("slapme.sock").path
    }

    static func ensureSupportDirectories() {
        try? FileManager.default.createDirectory(at: customPacksDirectory, withIntermediateDirectories: true)
    }
}
