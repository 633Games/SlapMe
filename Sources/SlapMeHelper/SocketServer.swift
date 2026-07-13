import Darwin
import Foundation

enum SocketServerError: Error {
    case createFailed
    case bindFailed(Int32)
    case listenFailed(Int32)
}

/// Tiny Unix-domain socket broadcaster (one line per slap).
final class SocketServer: @unchecked Sendable {
    private let path: String
    private var serverFD: Int32 = -1
    private var clients: [Int32] = []
    private let lock = NSLock()
    private var acceptSource: DispatchSourceRead?

    init(path: String) {
        self.path = path
    }

    func start() throws {
        unlink(path)

        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketServerError.createFailed }
        serverFD = fd

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

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw SocketServerError.bindFailed(errno)
        }

        chmod(path, 0o666)

        guard Darwin.listen(fd, 8) == 0 else {
            close(fd)
            throw SocketServerError.listenFailed(errno)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        source.resume()
        acceptSource = source
    }

    private func acceptClient() {
        let client = Darwin.accept(serverFD, nil, nil)
        guard client >= 0 else { return }
        let hello = #"{"type":"hello","version":1}"# + "\n"
        hello.withCString { ptr in
            _ = Darwin.write(client, ptr, strlen(ptr))
        }
        lock.lock()
        clients.append(client)
        lock.unlock()
    }

    func broadcast(_ line: String) {
        lock.lock()
        let snapshot = clients
        lock.unlock()

        var dead: [Int32] = []
        for fd in snapshot {
            let written = line.withCString { ptr -> Int in
                Darwin.write(fd, ptr, strlen(ptr))
            }
            if written < 0 {
                dead.append(fd)
            }
        }

        if !dead.isEmpty {
            lock.lock()
            clients.removeAll { dead.contains($0) }
            lock.unlock()
            for fd in dead { close(fd) }
        }
    }

    deinit {
        acceptSource?.cancel()
        for fd in clients { close(fd) }
        if serverFD >= 0 { close(serverFD) }
        unlink(path)
    }
}
