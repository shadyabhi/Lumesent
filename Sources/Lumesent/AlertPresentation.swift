import Foundation

enum AlertLayout: String, Codable, CaseIterable, Identifiable {
    case fullScreen
    case banner

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullScreen: return "Full screen"
        case .banner: return "Banner (top)"
        }
    }
}

enum AlertScreens: String, Codable, CaseIterable, Identifiable {
    case main
    case allScreens

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .main: return "Main display only"
        case .allScreens: return "All displays"
        }
    }
}

struct AlertPresentation: Equatable, Codable {
    var layout: AlertLayout
    var screens: AlertScreens

    static let `default` = AlertPresentation(layout: .fullScreen, screens: .main)
}
