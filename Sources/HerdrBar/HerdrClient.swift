import Foundation
import Darwin

/// NDJSON client over a Unix domain socket. One connection per Herdr session.
/// Thread-safety: all socket work happens on `queue`; callbacks are delivered on the main queue.
final class HerdrClient: @unchecked Sendable {
    typealias JSON = [String: Any]

    let socketPath: String
    private let queue = DispatchQueue(label: "me.bagus.herdrbar.client")
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [String: (Result<JSON, Error>) -> Void] = [:]

    /// Called on the main queue for every subscription event `{event, data}`.
    var onEvent: (@Sendable (String, JSON) -> Void)?
    /// Called on the main queue when the connection drops.
    var onDisconnect: (@Sendable (Error?) -> Void)?

    struct ClientError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    init(socketPath: String) { self.socketPath = socketPath }

    var isConnected: Bool { queue.sync { fd >= 0 } }

    /// Open and connect a blocking AF_UNIX stream socket.
    static func openSocket(path socketPath: String) throws -> Int32 {
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { throw ClientError(message: "socket() failed: \(errno)") }
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = socketPath.utf8CString
            guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
                close(s); throw ClientError(message: "socket path too long")
            }
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                    for (i, c) in pathBytes.enumerated() { dst[i] = c }
                }
            }
            let len = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count + 1)
            let rc = withUnsafePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, len) }
            }
            guard rc == 0 else {
                let e = errno; close(s)
                throw ClientError(message: "connect failed: \(String(cString: strerror(e)))")
            }
            var one: Int32 = 1
            setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            return s
    }

    /// Herdr closes the connection after answering one ordinary request, so every
    /// non-subscribe call uses its own short-lived connection.
    static func call(socketPath: String, method: String, params: JSON = [:]) async throws -> JSON {
        nonisolated(unsafe) let params = params
        let box: SendableBox<JSON> = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fd = try openSocket(path: socketPath)
                    defer { close(fd) }
                    let body: JSON = ["id": "bar-call", "method": method, "params": params]
                    var data = try JSONSerialization.data(withJSONObject: body)
                    data.append(0x0A)
                    try data.withUnsafeBytes { raw in
                        var off = 0
                        while off < raw.count {
                            let n = write(fd, raw.baseAddress! + off, raw.count - off)
                            if n <= 0 { throw ClientError(message: "write failed") }
                            off += n
                        }
                    }
                    var buf = Data(); var chunk = [UInt8](repeating: 0, count: 65536)
                    while !buf.contains(0x0A) {
                        let n = read(fd, &chunk, chunk.count)
                        if n <= 0 { break }
                        buf.append(chunk, count: n)
                    }
                    guard let nl = buf.firstIndex(of: 0x0A) else { throw ClientError(message: "empty response") }
                    let line = buf.subdata(in: buf.startIndex..<nl)
                    guard let obj = try JSONSerialization.jsonObject(with: line) as? JSON else { throw ClientError(message: "bad json") }
                    if let result = obj["result"] as? JSON { cont.resume(returning: SendableBox(result)) }
                    else { cont.resume(throwing: ClientError(message: (obj["error"] as? JSON)?["message"] as? String ?? "unknown error")) }
                } catch { cont.resume(throwing: error) }
            }
        }
        return box.value
    }

    /// Open the long-lived streaming connection. Only `events.subscribe` should be sent on it.
    func connect() throws {
        try queue.sync {
            guard fd < 0 else { return }
            let s = try HerdrClient.openSocket(path: socketPath)
            fd = s
            let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: queue)
            src.setEventHandler { [weak self] in self?.readAvailable() }
            src.setCancelHandler { [weak self] in
                guard let self else { return }
                if self.fd >= 0 { close(self.fd); self.fd = -1 }
            }
            src.resume()
            source = src
        }
    }

    func disconnect() {
        queue.async { self.teardown(error: nil) }
    }

    private func teardown(error: Error?) {
        guard fd >= 0 else { return }
        source?.cancel(); source = nil
        buffer.removeAll()
        let waiting = pending; pending.removeAll()
        let err = error ?? ClientError(message: "disconnected")
        DispatchQueue.main.async {
            for (_, cb) in waiting { cb(.failure(err)) }
            self.onDisconnect?(error)
        }
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let n = read(fd, &chunk, chunk.count)
        if n <= 0 {
            teardown(error: n == 0 ? nil : ClientError(message: "read failed: \(errno)"))
            return
        }
        buffer.append(chunk, count: n)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(line: line)
        }
    }

    private func handle(line: Data) {
        guard !line.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: line) as? JSON else { return }
        if let id = obj["id"] as? String, let cb = pending.removeValue(forKey: id) {
            if let result = obj["result"] as? JSON {
                nonisolated(unsafe) let result = result
                DispatchQueue.main.async { cb(.success(result)) }
            } else {
                let msg = (obj["error"] as? JSON)?["message"] as? String ?? "unknown error"
                DispatchQueue.main.async { cb(.failure(ClientError(message: msg))) }
            }
        } else if let event = obj["event"] as? String, let data = obj["data"] as? JSON {
            nonisolated(unsafe) let data = data
            DispatchQueue.main.async { self.onEvent?(event, data) }
        }
    }

    /// Fire a request. Completion arrives on the main queue.
    func request(_ method: String, params: JSON = [:], completion: @escaping @Sendable (Result<JSON, Error>) -> Void) {
        nonisolated(unsafe) let params = params
        queue.async {
            guard self.fd >= 0 else {
                DispatchQueue.main.async { completion(.failure(ClientError(message: "not connected"))) }
                return
            }
            self.nextID += 1
            let id = "bar-\(self.nextID)"
            let body: JSON = ["id": id, "method": method, "params": params]
            guard var data = try? JSONSerialization.data(withJSONObject: body) else {
                DispatchQueue.main.async { completion(.failure(ClientError(message: "encode failed"))) }
                return
            }
            data.append(0x0A)
            self.pending[id] = completion
            let ok = data.withUnsafeBytes { raw -> Bool in
                var off = 0
                while off < raw.count {
                    let n = write(self.fd, raw.baseAddress! + off, raw.count - off)
                    if n <= 0 { return false }
                    off += n
                }
                return true
            }
            if !ok { self.teardown(error: ClientError(message: "write failed")) }
        }
    }

    func request(_ method: String, params: JSON = [:]) async throws -> JSON {
        let box: SendableBox<JSON> = try await withCheckedThrowingContinuation { cont in
            request(method, params: params) { result in
                cont.resume(with: result.map { SendableBox($0) })
            }
        }
        return box.value
    }
}

/// Wrapper for values that are only ever handed across a queue hop and never mutated concurrently.
struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
