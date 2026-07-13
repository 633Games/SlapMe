import Darwin
import Foundation

enum HelperEvent {
    case hello
    case slap(amplitude: Double, ts: Double)
}

final class SocketClient: @unchecked Sendable {
    var onEvent: ((HelperEvent) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var reconnectTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.slapme.socket")
    private var buffer = Data()

    init(path: String) {
        self.path = path
    }

    func start() {
        queue.async { [weak self] in
            self?.connect()
            self?.scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.fd < 0 {
                self.connect()
            }
        }
        timer.resume()
        reconnectTimer = timer
    }

    private func connect() {
        if fd >= 0 { return }

        let newFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard newFD >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        let pathBytes = Array(path.utf8.prefix(maxLen))
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: pathBytes)
            if pathBytes.count < buf.count {
                buf[pathBytes.count] = 0
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(newFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            close(newFD)
            onConnectionChange?(false)
            return
        }

        fd = newFD
        onConnectionChange?(true)

        let readSource = DispatchSource.makeReadSource(fileDescriptor: newFD, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        readSource.setCancelHandler { [weak self] in
            if let self, self.fd >= 0 {
                close(self.fd)
                self.fd = -1
            }
        }
        readSource.resume()
        source = readSource
    }

    private func readAvailable() {
        var temp = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(fd, &temp, temp.count)
        if n <= 0 {
            source?.cancel()
            source = nil
            if fd >= 0 {
                close(fd)
                fd = -1
            }
            onConnectionChange?(false)
            return
        }
        buffer.append(contentsOf: temp.prefix(n))
        while let range = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8) {
                parse(line: line)
            }
        }
    }

    private func parse(line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }

        switch type {
        case "hello":
            onEvent?(.hello)
        case "slap":
            let amp = (obj["amplitude"] as? Double)
                ?? (obj["amplitude"] as? NSNumber)?.doubleValue
                ?? 0
            let ts = (obj["ts"] as? Double)
                ?? (obj["ts"] as? NSNumber)?.doubleValue
                ?? Date().timeIntervalSince1970
            onEvent?(.slap(amplitude: amp, ts: ts))
        default:
            break
        }
    }
}
