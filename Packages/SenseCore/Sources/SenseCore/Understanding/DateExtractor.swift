import Foundation

public struct DetectedDate: Hashable, Sendable {
    public var date: Date
    public var includesTime: Bool
    public var text: String
    public var range: Range<Int>

    public init(date: Date, includesTime: Bool, text: String, range: Range<Int>) {
        self.date = date
        self.includesTime = includesTime
        self.text = text
        self.range = range
    }
}

public struct DateExtractor: Sendable {
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let standaloneTimes = Options(rawValue: 1 << 0)
    }

    public var calendar: Calendar
    public var prefersDayFirst: Bool

    public init(calendar: Calendar = .autoupdatingCurrent, prefersDayFirst: Bool? = nil) {
        self.calendar = calendar
        self.prefersDayFirst = prefersDayFirst ?? Self.localePrefersDayFirst(calendar.locale ?? .current)
    }

    static func localePrefersDayFirst(_ locale: Locale) -> Bool {
        let monthFirstRegions: Set<String> = ["US", "PH", "FM", "MH", "PW", "BZ", "AS", "GU", "PR", "UM", "VI"]
        guard let region = locale.region?.identifier else { return false }
        return !monthFirstRegions.contains(region)
    }

    public func extract(from text: String, relativeTo now: Date, options: Options = []) -> [DetectedDate] {
        let ns = text as NSString
        let tokens = resolveOverlaps(tokenize(text, now: now))
        let filtered = dropWeekdaysAdjacentToDates(tokens)

        var results: [DetectedDate] = []
        var usedTimes = Set<Int>()

        for (index, token) in filtered.enumerated() {
            switch token.piece {
            case .day(let day, let defaultTime):
                var range = token.range
                var time = defaultTime
                if let pairIndex = pairedTime(for: index, in: filtered, used: usedTimes, source: ns),
                   case .time(let hour, let minute) = filtered[pairIndex].piece {
                    usedTimes.insert(pairIndex)
                    time = (hour, minute)
                    range = NSUnionRange(range, filtered[pairIndex].range)
                }
                let resolved: Date
                if let time {
                    resolved = calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: day) ?? day
                } else {
                    resolved = day
                }
                results.append(DetectedDate(
                    date: resolved,
                    includesTime: time != nil,
                    text: ns.substring(with: range),
                    range: range.intRange
                ))
            case .instant(let date):
                results.append(DetectedDate(date: date, includesTime: true, text: ns.substring(with: token.range), range: token.range.intRange))
            case .time:
                continue
            }
        }

        if options.contains(.standaloneTimes) {
            for (index, token) in filtered.enumerated() where !usedTimes.contains(index) {
                guard case .time(let hour, let minute) = token.piece,
                      let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { continue }
                let date = today > now ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
                results.append(DetectedDate(date: date, includesTime: true, text: ns.substring(with: token.range), range: token.range.intRange))
            }
        }

        return results.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private enum Piece {
        case day(Date, defaultTime: (Int, Int)?)
        case time(hour: Int, minute: Int)
        case instant(Date)

        var isDay: Bool {
            if case .day = self { return true }
            return false
        }
    }

    private struct Token {
        var range: NSRange
        var piece: Piece
        var isWeekday = false
    }

    private static let month = "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\\b\\.?"
    private static let monthDay = Pattern("\\b\(month)\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:,?\\s+(\\d{4})\\b)?")
    private static let dayMonth = Pattern("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?\(month)(?:,?\\s+(\\d{4})\\b)?")
    private static let isoDate = Pattern("\\b(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})\\b")
    private static let slashDate = Pattern("(?<![\\d/])(\\d{1,2})/(\\d{1,2})(?:/(\\d{4}|\\d{2}))?(?![\\d/])")
    private static let separatedDate = Pattern("(?<![\\d.\\-])(\\d{1,2})[.\\-](\\d{1,2})[.\\-](\\d{4}|\\d{2})(?![\\d.\\-])")
    private static let meridiemTime = Pattern("\\b(\\d{1,2})(?:[:.]([0-5]\\d))?\\s*([ap])\\.?\\s?m\\b")
    private static let clockTime = Pattern("\\b([01]?\\d|2[0-3]):([0-5]\\d)\\b")
    private static let atHour = Pattern("\\bat\\s+(\\d{1,2})(?::([0-5]\\d))?\\b(?!\\s*[ap]\\.?\\s?m\\b)(?![:/%.]\\d)")
    private static let namedTime = Pattern("\\b(noon|midday|midnight|morning|afternoon|evening|night)\\b")
    private static let relativeDay = Pattern("\\b(day after tomorrow|today|tonight|tomorrow|tmrw)\\b")
    private static let weekday = Pattern("\\b(?:(next|this|coming)\\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b")
    private static let inDuration = Pattern("\\bin\\s+(\\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty-five|half an?)\\s+(minute|min|hour|hr|day|week|month)s?\\b")
    private static let nextPeriod = Pattern("\\bnext\\s+(week|month)\\b")

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "thirty": 30, "forty-five": 45, "half a": 0.5, "half an": 0.5
    ]

    private static let weekdayNumbers: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7
    ]

    private func tokenize(_ text: String, now: Date) -> [Token] {
        var tokens: [Token] = []
        let today = calendar.startOfDay(for: now)

        for match in Self.monthDay.matches(in: text) {
            if let month = Self.monthNumber(match.group(1)), let day = Int(match.group(2) ?? ""),
               let date = resolveDay(year: match.group(3).flatMap(Int.init), month: month, day: day, now: now) {
                tokens.append(Token(range: match.range, piece: .day(date, defaultTime: nil)))
            }
        }
        for match in Self.dayMonth.matches(in: text) {
            if let month = Self.monthNumber(match.group(2)), let day = Int(match.group(1) ?? ""),
               let date = resolveDay(year: match.group(3).flatMap(Int.init), month: month, day: day, now: now) {
                tokens.append(Token(range: match.range, piece: .day(date, defaultTime: nil)))
            }
        }
        for match in Self.isoDate.matches(in: text) {
            if let year = Int(match.group(1) ?? ""), let month = Int(match.group(2) ?? ""), let day = Int(match.group(3) ?? ""),
               let date = resolveDay(year: year, month: month, day: day, now: now) {
                tokens.append(Token(range: match.range, piece: .day(date, defaultTime: nil)))
            }
        }
        for pattern in [Self.slashDate, Self.separatedDate] {
            for match in pattern.matches(in: text) {
                guard let first = Int(match.group(1) ?? ""), let second = Int(match.group(2) ?? "") else { continue }
                let year = match.group(3).flatMap(Int.init)
                let (month, day) = numericOrder(first, second)
                if let date = resolveDay(year: year, month: month, day: day, now: now) {
                    tokens.append(Token(range: match.range, piece: .day(date, defaultTime: nil)))
                }
            }
        }
        for match in Self.relativeDay.matches(in: text) {
            let word = (match.group(1) ?? "").lowercased()
            let offset: Int
            var defaultTime: (Int, Int)?
            switch word {
            case "day after tomorrow": offset = 2
            case "tomorrow", "tmrw": offset = 1
            case "tonight": offset = 0; defaultTime = (20, 0)
            default: offset = 0
            }
            if let date = calendar.date(byAdding: .day, value: offset, to: today) {
                tokens.append(Token(range: match.range, piece: .day(date, defaultTime: defaultTime)))
            }
        }
        for match in Self.weekday.matches(in: text) {
            guard let target = Self.weekdayNumbers[(match.group(2) ?? "").lowercased()] else { continue }
            let modifier = match.group(1)?.lowercased()
            let current = calendar.component(.weekday, from: today)
            var delta = (target - current + 7) % 7
            if modifier == "next", delta == 0 {
                delta = 7
            }
            if let date = calendar.date(byAdding: .day, value: delta, to: today) {
                tokens.append(Token(range: match.range, piece: .day(date, defaultTime: nil), isWeekday: true))
            }
        }
        for match in Self.nextPeriod.matches(in: text) {
            let unit: Calendar.Component = (match.group(1) ?? "").lowercased() == "month" ? .month : .weekOfYear
            if let date = calendar.date(byAdding: unit, value: 1, to: today) {
                tokens.append(Token(range: match.range, piece: .day(date, defaultTime: nil)))
            }
        }
        for match in Self.inDuration.matches(in: text) {
            let amountText = (match.group(1) ?? "").lowercased()
            guard let amount = Double(amountText) ?? Self.numberWords[amountText] else { continue }
            let unit = (match.group(2) ?? "").lowercased()
            switch unit {
            case "minute", "min":
                tokens.append(Token(range: match.range, piece: .instant(now.addingTimeInterval(amount * 60))))
            case "hour", "hr":
                tokens.append(Token(range: match.range, piece: .instant(now.addingTimeInterval(amount * 3600))))
            case "day":
                if let date = calendar.date(byAdding: .day, value: Int(amount.rounded()), to: today) {
                    tokens.append(Token(range: match.range, piece: .day(date, defaultTime: nil)))
                }
            case "week":
                if let date = calendar.date(byAdding: .day, value: Int((amount * 7).rounded()), to: today) {
                    tokens.append(Token(range: match.range, piece: .day(date, defaultTime: nil)))
                }
            default:
                if let date = calendar.date(byAdding: .month, value: Int(amount.rounded()), to: today) {
                    tokens.append(Token(range: match.range, piece: .day(date, defaultTime: nil)))
                }
            }
        }
        for match in Self.meridiemTime.matches(in: text) {
            guard let hour = Int(match.group(1) ?? ""), (1...12).contains(hour) else { continue }
            let minute = Int(match.group(2) ?? "") ?? 0
            let isPM = (match.group(3) ?? "").lowercased() == "p"
            tokens.append(Token(range: match.range, piece: .time(hour: hour % 12 + (isPM ? 12 : 0), minute: minute)))
        }
        for match in Self.clockTime.matches(in: text) {
            guard let hour = Int(match.group(1) ?? ""), let minute = Int(match.group(2) ?? "") else { continue }
            tokens.append(Token(range: match.range, piece: .time(hour: hour, minute: minute)))
        }
        for match in Self.atHour.matches(in: text) {
            guard let hour = Int(match.group(1) ?? ""), (0...23).contains(hour) else { continue }
            let minute = Int(match.group(2) ?? "") ?? 0
            let adjusted = (1...6).contains(hour) ? hour + 12 : hour
            tokens.append(Token(range: match.range, piece: .time(hour: adjusted, minute: minute)))
        }
        for match in Self.namedTime.matches(in: text) {
            let hour: Int
            switch (match.group(1) ?? "").lowercased() {
            case "noon", "midday": hour = 12
            case "midnight": hour = 0
            case "morning": hour = 9
            case "afternoon": hour = 15
            case "evening": hour = 18
            default: hour = 20
            }
            tokens.append(Token(range: match.range, piece: .time(hour: hour, minute: 0)))
        }
        return tokens
    }

    private func resolveOverlaps(_ tokens: [Token]) -> [Token] {
        let ordered = tokens.sorted {
            $0.range.length != $1.range.length ? $0.range.length > $1.range.length : $0.range.location < $1.range.location
        }
        var accepted: [Token] = []
        for token in ordered where !accepted.contains(where: { $0.range.overlaps(token.range) }) {
            accepted.append(token)
        }
        return accepted.sorted { $0.range.location < $1.range.location }
    }

    private func dropWeekdaysAdjacentToDates(_ tokens: [Token]) -> [Token] {
        tokens.enumerated().filter { index, token in
            guard token.isWeekday, index + 1 < tokens.count else { return true }
            let next = tokens[index + 1]
            guard next.piece.isDay, !next.isWeekday else { return true }
            return next.range.location - (token.range.location + token.range.length) > 4
        }.map(\.element)
    }

    private static let connectorWords: Set<String> = [
        "at", "on", "by", "from", "before", "until", "till", "around", "about", "the", "of", "starting",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]

    private func pairedTime(for index: Int, in tokens: [Token], used: Set<Int>, source: NSString) -> Int? {
        let day = tokens[index].range
        var best: (index: Int, distance: Int)?
        for (candidate, token) in tokens.enumerated() {
            guard case .time = token.piece, !used.contains(candidate) else { continue }
            let gapRange: NSRange
            if token.range.location >= day.location + day.length {
                gapRange = NSRange(location: day.location + day.length, length: token.range.location - (day.location + day.length))
            } else if token.range.location + token.range.length <= day.location {
                gapRange = NSRange(location: token.range.location + token.range.length, length: day.location - (token.range.location + token.range.length))
            } else {
                continue
            }
            guard gapRange.length <= 20 else { continue }
            let gap = source.substring(with: gapRange)
            guard !gap.contains("\n") else { continue }
            let leftovers = TextTokenizer.words(in: gap).filter { !Self.connectorWords.contains($0) }
            guard leftovers.isEmpty else { continue }
            let distance = gapRange.length + (token.range.location < day.location ? 1 : 0)
            if best == nil || distance < best!.distance {
                best = (candidate, distance)
            }
        }
        return best?.index
    }

    private func numericOrder(_ first: Int, _ second: Int) -> (month: Int, day: Int) {
        if first > 12 { return (second, first) }
        if second > 12 { return (first, second) }
        return prefersDayFirst ? (second, first) : (first, second)
    }

    private func resolveDay(year: Int?, month: Int, day: Int, now: Date) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        func make(_ year: Int) -> Date? {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            guard let date = calendar.date(from: components),
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day else { return nil }
            return calendar.startOfDay(for: date)
        }
        if let year {
            return make(year < 100 ? 2000 + year : year)
        }
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: now)
        return [currentYear - 1, currentYear, currentYear + 1]
            .compactMap(make)
            .min { abs($0.timeIntervalSince(today)) < abs($1.timeIntervalSince(today)) }
    }

    private static func monthNumber(_ text: String?) -> Int? {
        guard let prefix = text?.lowercased().prefix(3) else { return nil }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return months.firstIndex(of: String(prefix)).map { $0 + 1 }
    }
}
