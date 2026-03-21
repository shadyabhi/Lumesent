import AppKit
import Combine

final class PermissionChecker: ObservableObject {
    @Published var hasFullDiskAccess: Bool = false
    @Published var hasAccessibility: Bool = false

    private var timer: Timer?

    var allGranted: Bool { hasFullDiskAccess && hasAccessibility }

    init() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func check() {
        let fda = checkFullDiskAccess()
        let ax = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.hasFullDiskAccess = fda
            self.hasAccessibility = ax
        }
    }

    private func checkFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/Library/Group Containers/group.com.apple.usernoted/db2/db"
        return FileManager.default.isReadableFile(atPath: dbPath)
    }

    deinit {
        timer?.invalidate()
    }
}
