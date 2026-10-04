import Foundation

public struct MemoryQuery: Hashable, Sendable {
    public var raw: String
    public var terms: [String]
    public var dateInterval: DateInterval?
    public var kinds: Set<MemoryKind>
    public var place: String?

    public init(raw: String, terms: [String], dateInterval: DateInterval? = nil, kinds: Set<MemoryKind> = [], place: String? = nil) {
        self.raw = raw
        self.terms = terms
        self.dateInterval = dateInterval
        self.kinds = kinds
        self.place = place
    }

    public var hasFilters: Bool {
        dateInterval != nil || !kinds.isEmpty || place != nil
    }

    public var keywordText: String {
        terms.joined(separator: " ")
    }
}

public struct QueryParser: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    private static let fillerWords: Set<String> = [
        "saw", "see", "seen", "seeing", "capture", "captured", "capturing", "photographed", "photo", "picture",
        "remember", "recall", "find", "search", "show", "look", "looked", "thing", "something", "stuff",
        "already", "ever", "anything", "everything", "get", "got", "also", "one", "ones", "like", "kind",
        "sense", "please", "hey", "know", "noticed", "notice", "save", "saved", "mention", "mentioned"
    ]

    private static let kindWords: [String: MemoryKind] = [
        "receipt": .receipt, "receipts": .receipt, "invoice": .receipt, "invoices": .receipt,
        "document": .document, "documents": .document, "doc": .document, "docs": .document,
        "announcement": .announcement, "announcements": .announcement, "notice": .announcement,
        "notices": .announcement, "poster": .announcement, "posters": .announcement, "flyer": .announcement,
        "event": .event, "events": .event,
        "task": .task, "tasks": .task, "todo": .task, "todos": .task,
        "note": .note, "notes": .note
    ]

    private static let today = Pattern("\\b(today|this morning|this afternoon|this evening|tonight)\\b")
    private static let yesterday = Pattern("\\b(yesterday|last night)\\b")
    private static let thisWeek = Pattern("\\bthis week\\b")
    private static let lastWeek = Pattern("\\b(last week|past week|previous week)\\b")
    private static let thisMonth = Pattern("\\bthis month\\b")
    private static let lastMonth = Pattern("\\b(last month|past month|previous month)\\b")
    private static let recently = Pattern("\\b(recently|lately|the other day)\\b")
    private static let daysAgo = Pattern("\\b(\\d+|two|three|four|five|six|seven|ten) days ago\\b")
    private static let lastNDays = Pattern("\\b(?:last|past) (\\d+|two|three|four|five|six|seven|ten|fourteen|thirty) days\\b")
    private static let onWeekday = Pattern("\\b(?:on|last) (monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b")
    private static let placePhrase = Pattern("\\b(?:at|in|near|from) (?:the |my |a )?([a-z][a-z'\\- ]{1,40}?)(?=\\s+(?:yesterday|today|tonight|last|this|on|in|at|about|that|which|when|where|recently|ago|\\d)\\b|\\s*[?.!,]|\\s*$)")

    private static let numberWords: [String: Int] = [
        "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "ten": 10, "fourteen": 14, "thirty": 30
    ]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let nonPlaces: Set<String> = [
        "the morning", "morning", "afternoon", "evening", "night", "week", "month", "year", "the past",
        "it", "this", "that", "there", "here", "all"
    ]

    public func parse(_ text: String, now: Date = Date()) -> MemoryQuery {
        var working = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        var interval: DateInterval?

        let startOfToday = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: startOfToday) ?? startOfToday }

        if let match = Self.yesterday.firstMatch(in: working) {
            interval = DateInterval(start: day(-1), end: startOfToday)
            working = Self.blank(match.range, in: working)
        } else if let match = Self.today.firstMatch(in: working) {
            interval = DateInterval(start: startOfToday, end: day(1))
            working = Self.blank(match.range, in: working)
        } else if let match = Self.lastWeek.firstMatch(in: working) {
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? day(-7)
            let start = calendar.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
            interval = DateInterval(start: start, end: thisWeekStart)
            working = Self.blank(match.range, in: working)
        } else if let match = Self.thisWeek.firstMatch(in: working) {
            interval = DateInterval(start: calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? day(-7), end: day(1))
            working = Self.blank(match.range, in: working)
        } else if let match = Self.lastMonth.firstMatch(in: working) {
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? day(-30)
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            interval = DateInterval(start: start, end: thisMonthStart)
            working = Self.blank(match.range, in: working)
        } else if let match = Self.thisMonth.firstMatch(in: working) {
            interval = DateInterval(start: calendar.dateInterval(of: .month, for: now)?.start ?? day(-30), end: day(1))
            working = Self.blank(match.range, in: working)
        } else if let match = Self.daysAgo.firstMatch(in: working) {
            let value = Self.number(match.group(1))
            interval = DateInterval(start: day(-value), end: day(-value + 1))
            working = Self.blank(match.range, in: working)
        } else if let match = Self.lastNDays.firstMatch(in: working) {
            interval = DateInterval(start: day(-Self.number(match.group(1))), end: day(1))
            working = Self.blank(match.range, in: working)
        } else if let match = Self.onWeekday.firstMatch(in: working), let index = Self.weekdays.firstIndex(of: match.group(1) ?? "") {
            let current = calendar.component(.weekday, from: now) - 1
            var delta = (current - index + 7) % 7
            if delta == 0 { delta = 7 }
            interval = DateInterval(start: day(-delta), end: day(-delta + 1))
            working = Self.blank(match.range, in: working)
        } else if let match = Self.recently.firstMatch(in: working) {
            interval = DateInterval(start: day(-7), end: day(1))
            working = Self.blank(match.range, in: working)
        }

        var place: String?
        for match in Self.placePhrase.matches(in: working) {
            let candidate = (match.group(1) ?? "").trimmed
            guard !candidate.isEmpty, !Self.nonPlaces.contains(candidate) else { continue }
            guard !TextTokenizer.words(in: candidate).contains(where: { Self.kindWords[$0] != nil }) else { continue }
            guard !TextTokenizer.words(in: candidate).allSatisfy({ TextTokenizer.stopwords.contains($0) }) else { continue }
            place = candidate
            working = Self.blank(match.range, in: working)
            break
        }

        var kinds = Set<MemoryKind>()
        var terms: [String] = []
        for word in TextTokenizer.words(in: working) {
            if let kind = Self.kindWords[word] {
                kinds.insert(kind)
                continue
            }
            guard !TextTokenizer.stopwords.contains(word), !Self.fillerWords.contains(word) else { continue }
            guard word.count > 1 || word.allSatisfy(\.isNumber) else { continue }
            terms.append(TextTokenizer.stem(word))
        }

        return MemoryQuery(raw: text, terms: terms, dateInterval: interval, kinds: kinds, place: place)
    }

    private static func blank(_ range: NSRange, in text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: " ")
    }

    private static func number(_ text: String?) -> Int {
        guard let text else { return 1 }
        return Int(text) ?? numberWords[text] ?? 1
    }
}
