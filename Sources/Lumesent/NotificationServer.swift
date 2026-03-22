import Foundation

final class NotificationServer {
    private let socketPath: String
    private var serverFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "com.shadyabhi.Lumesent.notificationServer.accept")
    private let onNotification: (ExternalNotification) -> Void

    init(onNotification: @escaping (ExternalNotification) -> Void) {
        self.socketPath = FileLocations.appSupportDirectory.appendingPathComponent("notify.sock").path
        self.onNotification = onNotification
    }

    func start() {
        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            AppLog.shared.error("failed to create socket: \(errno, privacy: .public)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathFieldLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathMaxCopy = pathFieldLen - 1
        guard socketPath.utf8.count <= pathMaxCopy else {
            AppLog.shared.error("socket path too long for sockaddr_un")
            close(serverFD)
            serverFD = -1
            return
        }
        socketPath.withCString { ptr in
            withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
                let pathBuf = rawBuf.baseAddress!.assumingMemoryBound(to: CChar.self)
                strncpy(pathBuf, ptr, pathMaxCopy)
            }
        }
        // BSD: address length is prefix + pathname bytes (SUN_LEN), not sizeof(sockaddr_un).
        let sunPathOffset = Int(MemoryLayout.offset(of: \sockaddr_un.sun_path)!)
        let addrLen = socklen_t(sunPathOffset + socketPath.utf8.count)
        addr.sun_len = UInt8(addrLen)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            AppLog.shared.error("failed to bind socket: \(errno, privacy: .public)")
            close(serverFD)
            serverFD = -1
            return
        }

        chmod(socketPath, 0o777)

        guard Darwin.listen(serverFD, 16) == 0 else {
            AppLog.shared.error("failed to listen on socket: \(errno, privacy: .public)")
            close(serverFD)
            serverFD = -1
            return
        }

        let listenFD = serverFD
        acceptQueue.async { [weak self] in
            self?.acceptLoop(listenFD: listenFD)
        }

        AppLog.shared.info("notification server listening at \(self.socketPath, privacy: .public)")
    }

    func stop() {
        let fd = serverFD
        serverFD = -1
        if fd >= 0 {
            close(fd)
        }
        unlink(socketPath)
    }

    deinit {
        stop()
    }

    /// Blocking `accept` on a background queue; `stop()` closes `listenFD` to unblock.
    private func acceptLoop(listenFD: Int32) {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                if errno == EBADF || errno == EINVAL { break }
                AppLog.shared.notice("accept failed: \(errno, privacy: .public)")
                break
            }
            handleClient(clientFD)
            close(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            data.append(contentsOf: buffer[..<bytesRead])
        }

        guard !data.isEmpty else { return }

        do {
            let notification = try JSONDecoder().decode(ExternalNotification.self, from: data)
            AppLog.shared.notice("received external notification: \(notification.title, privacy: .public) sourceContext: tmux=\(notification.sourceContext?.tmuxSession ?? "nil", privacy: .public):\(notification.sourceContext?.tmuxWindow ?? "nil", privacy: .public):\(notification.sourceContext?.tmuxPane ?? "nil", privacy: .public) terminal=\(notification.sourceContext?.terminalAppBundleId ?? "nil", privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                self?.onNotification(notification)
            }
        } catch {
            AppLog.shared.notice("failed to parse external notification: \(error.localizedDescription, privacy: .public)")
        }
    }
}
