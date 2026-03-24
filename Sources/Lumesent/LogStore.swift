import Foundation
import OSLog

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let level: OSLogEntryLog.Level
    let message: String

    var levelLabel: String {
        switch level {
        case .undefined: return "—"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        @unknown default: return "OTHER"
        }
    }

    var isError: Bool {
        level == .error || level == .fault
    }
}

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var isLoading = false
    @Published var filterLevel: OSLogEntryLog.Level? = nil
    @Published var timeWindow: TimeInterval = 3600  // seconds to look back

    private let subsystem = Bundle.main.bundleIdentifier ?? "com.shadyabhi.Lumesent"
    private var refreshTimer: Timer?
    private var fetchTask: Task<Void, Never>?

    var filteredEntries: [LogEntry] {
        guard let filterLevel else { return entries }
        return entries.filter { $0.level == filterLevel }
    }

    func start() {
        fetch()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetch()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        fetchTask?.cancel()
        fetchTask = nil
    }

    func fetch() {
        fetchTask?.cancel()
        let subsystem = self.subsystem
        let timeWindow = self.timeWindow
        let isFirstLoad = entries.isEmpty
        if isFirstLoad { isLoading = true }

        fetchTask = Task.detached(priority: .userInitiated) {
            do {
                let store = try OSLogStore(scope: .system)
                let position = store.position(date: Date().addingTimeInterval(-timeWindow))
                let predicate = NSPredicate(format: "subsystem == %@", subsystem)
                let enumerator = try store.getEntries(at: position, matching: predicate)

                var newEntries: [LogEntry] = []
                for entry in enumerator {
                    if Task.isCancelled { return }
                    guard let logEntry = entry as? OSLogEntryLog else { continue }
                    newEntries.append(LogEntry(
                        date: logEntry.date,
                        level: logEntry.level,
                        message: logEntry.composedMessage
                    ))
                }

                let result = newEntries
                await MainActor.run {
                    self.entries = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
                AppLog.shared.error("LogStore: failed to read log store: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
