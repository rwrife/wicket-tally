import Foundation

public struct UnknownSafeFormatter {
    public static func rateString(_ value: NumericValue, fractionDigits: Int = 2) -> String {
        switch value {
        case let .known(num):
            guard !num.isNaN && !num.isInfinite else { return "unknown" }
            return String(format: "%.\(fractionDigits)f", num)
        case .unknown:
            return "unknown"
        }
    }

    public static func ballsString(_ value: NumericValue) -> String {
        switch value {
        case let .known(num):
            guard !num.isNaN && !num.isInfinite else { return "unknown" }
            return "\(Int(num))"
        case .unknown:
            return "unknown"
        }
    }

    public static func text(_ text: TextValue) -> String {
        text.rendered
    }
}
