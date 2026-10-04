import Foundation

struct Pattern {
    let regex: NSRegularExpression

    init(_ pattern: String) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid pattern \(pattern): \(error)")
        }
    }

    func matches(in text: String) -> [PatternMatch] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            PatternMatch(result: $0, source: ns)
        }
    }

    func firstMatch(in text: String) -> PatternMatch? {
        let ns = text as NSString
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)).map {
            PatternMatch(result: $0, source: ns)
        }
    }

    func contains(in text: String) -> Bool {
        firstMatch(in: text) != nil
    }
}

struct PatternMatch {
    let result: NSTextCheckingResult
    let source: NSString

    var range: NSRange { result.range }
    var text: String { source.substring(with: result.range) }

    func group(_ index: Int) -> String? {
        guard index < result.numberOfRanges else { return nil }
        let range = result.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return source.substring(with: range)
    }
}

extension NSRange {
    var intRange: Range<Int> { location..<(location + length) }

    func overlaps(_ other: NSRange) -> Bool {
        location < other.location + other.length && other.location < location + length
    }

    func overlaps(_ other: Range<Int>) -> Bool {
        location < other.upperBound && other.lowerBound < location + length
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    func truncated(to limit: Int) -> String {
        guard count > limit else { return self }
        let prefix = String(self.prefix(limit))
        if let space = prefix.lastIndex(of: " "), prefix.distance(from: prefix.startIndex, to: space) > limit / 2 {
            return String(prefix[..<space]).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
        }
        return prefix + "…"
    }

    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
