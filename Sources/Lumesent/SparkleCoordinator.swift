import AppKit
import Sparkle

/// Sparkle wiring is disabled in `AppDelegate` until `SUFeedURL` / `SUPublicEDKey` are real.
/// When re-enabling: add a `SparkleCoordinator` property, menu item, and `checkForUpdates(_:)`.
final class SparkleCoordinator: NSObject {
    private let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }
}
