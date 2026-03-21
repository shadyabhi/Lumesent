import Foundation

struct DismissKeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifierFlags: UInt  // NSEvent.ModifierFlags.rawValue
    var displayName: String

    static func from(event: NSEventShim) -> DismissKeyShortcut {
        DismissKeyShortcut(
            keyCode: event.keyCode,
            modifierFlags: event.modifierRawValue,
            displayName: event.displayName
        )
    }

    func matches(keyCode: UInt16, modifierFlags: UInt) -> Bool {
        // Mask to only care about Shift, Control, Option, Command
        let mask: UInt = 0x00F_E0000  // deviceIndependentFlagsMask-ish
        return self.keyCode == keyCode && (self.modifierFlags & mask) == (modifierFlags & mask)
    }
}

/// Lightweight shim so DismissKeyShortcut doesn't depend on AppKit directly
struct NSEventShim {
    let keyCode: UInt16
    let modifierRawValue: UInt
    let displayName: String
}

class AppSettings: ObservableObject {
    @Published var dismissKey: DismissKeyShortcut?

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Lumesent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")
        load()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(SettingsData(dismissKey: dismissKey))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data)
        else { return }
        dismissKey = decoded.dismissKey
    }

    private struct SettingsData: Codable {
        var dismissKey: DismissKeyShortcut?
    }
}
