import Foundation
import os.log

enum AppLog {
    static let shared = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.shadyabhi.Lumesent", category: "app")
}
