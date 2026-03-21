import AppKit
import Combine

final class PermissionChecker: ObservableObject {
    @Published var hasFullDiskAccess: Bool = false
    @Published var hasAccessibility: Bool = false

    private var timer: Timer?
    private let dbPath: String

    var allGranted: Bool { hasFullDiskAccess && hasAccessibility }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        dbPath = "\(home)/Library/Group Containers/group.com.apple.usernoted/db2/db"
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func check() {
        let fda = FileManager.default.isReadableFile(atPath: dbPath)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        let ax = AXIsProcessTrustedWithOptions(opts)
        DispatchQueue.main.async {
            if self.hasFullDiskAccess != fda { self.hasFullDiskAccess = fda }
            if self.hasAccessibility != ax { self.hasAccessibility = ax }
            if fda && ax {
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
