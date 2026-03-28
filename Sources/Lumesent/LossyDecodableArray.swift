import Foundation

/// Wrapper that decodes an array element without throwing — stores `nil` for entries that fail to decode.
/// Use this to load JSON arrays where one corrupt entry should not discard the entire array.
enum LossyCodableArray<T: Decodable> {
    struct Element: Decodable {
        let value: T?
        init(from decoder: Decoder) {
            value = try? T(from: decoder)
        }
    }
}
