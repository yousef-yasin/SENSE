import Foundation

public struct MoneyAmount: Hashable, Sendable {
    public var text: String
    public var value: Decimal
    public var currency: String?
    public var range: Range<Int>
}

public struct EntityExtractor: Sendable {
    public init() {}

    private static let currencyCodes = "usd|eur|gbp|jod|jd|sar|aed|egp|kwd|qar|try|cad|aud|chf|jpy|inr"
    private static let symbolAmount = Pattern("(?<![\\w])([$€£¥₹]|\(currencyCodes))\\s?(\\d{1,3}(?:,\\d{3})+(?:\\.\\d{1,3})?|\\d+(?:\\.\\d{1,3})?)(?![\\d])")
    private static let decimalAmount = Pattern("(?<![\\d.,])(\\d{1,3}(?:,\\d{3})+\\.\\d{2,3}|\\d+\\.\\d{2,3})(?![\\d])(?!\\s?[ap]\\.?m\\b)(?:\\s?(\(currencyCodes))\\b)?")
    private static let email = Pattern("[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}")
    private static let link = Pattern("\\b(?:https?://|www\\.)[^\\s<>\"']+")
    private static let phone = Pattern("(?<![\\w+])(?:\\+\\d{1,3}[\\s.\\-]?)?(?:\\(\\d{1,4}\\)[\\s.\\-]?)?\\d{2,4}(?:[\\s.\\-]\\d{2,4}){1,3}(?![\\w])")

    private static let symbolCodes: [String: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "jd": "JOD"
    ]

    public func money(in text: String, excluding excluded: [Range<Int>] = []) -> [MoneyAmount] {
        var amounts: [MoneyAmount] = []
        let candidates = Self.symbolAmount.matches(in: text).map { ($0, symbolFirst: true) }
            + Self.decimalAmount.matches(in: text).map { ($0, symbolFirst: false) }
        for (match, symbolFirst) in candidates {
            guard !excluded.contains(where: { match.range.overlaps($0) }),
                  !amounts.contains(where: { match.range.overlaps($0.range) }) else { continue }
            let numberText = (symbolFirst ? match.group(2) : match.group(1)) ?? ""
            let currencyText = symbolFirst ? match.group(1) : match.group(2)
            guard let value = Decimal(string: numberText.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")) else { continue }
            let currency = currencyText.map { Self.symbolCodes[$0.lowercased()] ?? $0.uppercased() }
            amounts.append(MoneyAmount(text: match.text, value: value, currency: currency, range: match.range.intRange))
        }
        return amounts.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    public func emails(in text: String) -> [String] {
        unique(Self.email.matches(in: text).map(\.text))
    }

    public func links(in text: String) -> [URL] {
        let urls = Self.link.matches(in: text).compactMap { match -> URL? in
            let cleaned = match.text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]}!?\"'"))
            let normalized = cleaned.lowercased().hasPrefix("www.") ? "https://" + cleaned : cleaned
            guard let url = URL(string: normalized), url.host != nil else { return nil }
            return url
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    public func phoneNumbers(in text: String, excluding excluded: [Range<Int>] = []) -> [String] {
        let numbers = Self.phone.matches(in: text).compactMap { match -> String? in
            guard !excluded.contains(where: { match.range.overlaps($0) }) else { return nil }
            let candidate = match.text
            let digits = candidate.filter(\.isNumber)
            guard (7...15).contains(digits.count) else { return nil }
            guard candidate.hasPrefix("+") || candidate.contains(where: { " -(".contains($0) }) else { return nil }
            return candidate
        }
        return unique(numbers)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}
