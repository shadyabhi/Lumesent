import Foundation

/// Configures a `sockaddr_un` for the given Unix domain socket path.
/// Returns the address and its length for use with `bind`/`connect`.
func makeUnixSocketAddress(_ path: String) -> (sockaddr_un, socklen_t)? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathFieldLen = MemoryLayout.size(ofValue: addr.sun_path)
    let pathMaxCopy = pathFieldLen - 1
    guard path.utf8.count <= pathMaxCopy else { return nil }

    path.withCString { ptr in
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
            let pathBuf = rawBuf.baseAddress!.assumingMemoryBound(to: CChar.self)
            strncpy(pathBuf, ptr, pathMaxCopy)
        }
    }

    let sunPathOffset = Int(MemoryLayout.offset(of: \sockaddr_un.sun_path)!)
    let addrLen = socklen_t(sunPathOffset + path.utf8.count)
    addr.sun_len = UInt8(addrLen)
    return (addr, addrLen)
}

/// Calls `connect` on a Unix domain socket file descriptor.
func connectUnixSocket(_ fd: Int32, address: inout sockaddr_un, length: socklen_t) -> Int32 {
    withUnsafePointer(to: &address) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            connect(fd, sockPtr, length)
        }
    }
}

/// Calls `bind` on a Unix domain socket file descriptor.
func bindUnixSocket(_ fd: Int32, address: inout sockaddr_un, length: socklen_t) -> Int32 {
    withUnsafePointer(to: &address) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            bind(fd, sockPtr, length)
        }
    }
}
