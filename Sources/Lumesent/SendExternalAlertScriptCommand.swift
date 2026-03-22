import AppKit

/// Handles `tell application "Lumesent" to send external alert …` (bound via `Lumesent.sdef` cocoa class).
@objc(SendExternalAlertScriptCommand)
final class SendExternalAlertScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let title = string(from: directParameter)
        guard let title, !title.isEmpty else {
            scriptErrorNumber = -50 // paramErr
            scriptErrorString = "Title is required (direct parameter)."
            return nil
        }

        let args = evaluatedArguments
        let body = optionalString(args, key: "bodyText")
        let appName = optionalString(args, key: "applicationName")
        let displayMode = optionalString(args, key: "displayMode")
        let alertType = optionalString(args, key: "alertType")

        let ext = ExternalNotification(
            title: title,
            body: body,
            appName: appName,
            displayMode: displayMode,
            alertType: alertType,
            sourceContext: nil,
            focusSource: optionalBool(args, key: "focusSourceTerminal")
        )

        guard let delegate = NSApp.delegate as? AppDelegate else {
            scriptErrorNumber = -1750 // errOSASystemError
            scriptErrorString = "Lumesent is not ready."
            return nil
        }

        DispatchQueue.main.async {
            delegate.handleExternalNotification(ext)
        }
        return nil
    }

    private func string(from value: Any?) -> String? {
        switch value {
        case let s as String:
            return s
        case let s as NSString:
            return s as String
        case let n as NSNumber:
            return n.stringValue
        default:
            return nil
        }
    }

    private func optionalString(_ args: [String: Any]?, key: String) -> String? {
        guard let args, let v = args[key] else { return nil }
        let s = string(from: v)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    private func optionalBool(_ args: [String: Any]?, key: String) -> Bool? {
        guard let args, let v = args[key] else { return nil }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return nil
    }
}
