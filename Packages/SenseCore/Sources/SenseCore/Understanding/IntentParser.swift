import Foundation

public enum UserIntent: Hashable, Sendable {
    case remind(ReminderDraft)
    case search(String)
    case recallSimilar
    case analyzeSurroundings
    case capture(String)
}

public struct IntentParser: Sendable {
    public var dateExtractor: DateExtractor
    public var calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent, prefersDayFirst: Bool? = nil) {
        self.calendar = calendar
        self.dateExtractor = DateExtractor(calendar: calendar, prefersDayFirst: prefersDayFirst)
    }

    private static let analyze = Pattern("^(?:hey sense,?\\s*)?(?:what(?:'s| is) important(?: here)?|what am i looking at|what does (?:this|it) say|read (?:this|it)(?: for me)?|explain (?:this|what i'?m seeing)|what(?:'s| is) (?:this|here))\\b")
    private static let recall = Pattern("\\b(?:have|did|had) i (?:already |ever )?(?:seen|see|captured|capture|saved|save|noticed|notice|come across|photographed) (?:this|that|it)(?:\\s+(?!before\\b|already\\b)[a-z]+)?(?: before| already)?\\s*[?.!]*$")
    private static let remindPrefix = Pattern("^(?:hey sense,?\\s*)?(?:please\\s+)?(?:can you\\s+|could you\\s+)?(?:remind me|set (?:a|up a) reminder|create a reminder|add a reminder|don'?t let me forget)(?:\\s+(?:to|about|of|for|that))?\\b")
    private static let searchPrefix = Pattern("^(?:hey sense,?\\s*)?(?:what (?:was|were|did i)|where (?:was|were|is|did|are)|when (?:did|was)|which|did i|have i|find|search(?: for)?|show me|look up|do you remember|do i have|what's that|what is that)\\b")
    private static let placeClause = Pattern("\\b(?:when|once|as soon as|after|whenever)\\s+i(?:\\s+|')(get to|get back to|get home|get back home|arrive at|arrive in|arrive home|arrive|reach|am at|'m at|m at|am in|'m in|m in|go to|leave|exit|get)\\s*(?:the\\s+|my\\s+)?([^,.!?]*)")
    private static let atPlaceClause = Pattern("\\b(?:at|near)\\s+(?:the|my)\\s+([a-z][^,.!?]*)$")
    private static let contextReferences: Set<String> = ["this", "that", "it", "these", "those", "this one", "that one", "this thing", "that thing"]

    public func parse(_ utterance: String, now: Date = Date()) -> UserIntent {
        let text = utterance.replacingOccurrences(of: "\u{2019}", with: "'").trimmed
        guard !text.isEmpty else { return .capture("") }
        let lowered = text.lowercased()

        if Self.analyze.contains(in: lowered) {
            return .analyzeSurroundings
        }
        if Self.recall.contains(in: lowered) {
            return .recallSimilar
        }
        if let prefix = Self.remindPrefix.firstMatch(in: lowered) {
            let ns = text as NSString
            let remainder = ns.substring(from: prefix.range.location + prefix.range.length)
            return .remind(reminderDraft(from: remainder, now: now))
        }
        if Self.searchPrefix.contains(in: lowered) {
            return .search(text)
        }
        return .capture(text)
    }

    func reminderDraft(from remainder: String, now: Date) -> ReminderDraft {
        var working = remainder
        var timing: ReminderTiming = .unspecified
        var dueDate: Date?

        let dates = dateExtractor.extract(from: working, relativeTo: now, options: .standaloneTimes)
        if let first = dates.first(where: { $0.date > now }) ?? dates.first {
            var date = first.date
            if !first.includesTime {
                date = calendar.date(bySettingHour: ReminderPolicy.defaultHour, minute: 0, second: 0, of: date) ?? date
            }
            if date > now {
                timing = .at(date)
                dueDate = date
            }
            working = Self.removing(first.range, from: working)
        }

        if let clause = Self.placeClause.firstMatch(in: working) {
            let verb = (clause.group(1) ?? "").lowercased()
            var place = Self.cleanPlace(clause.group(2) ?? "")
            if verb.contains("home") {
                place = "home"
            }
            if !place.isEmpty {
                let leaving = verb == "leave" || verb == "exit"
                timing = leaving ? .leaving(place) : .arriving(place)
                working = Self.removing(clause.range.intRange, from: working)
            }
        } else if let clause = Self.atPlaceClause.firstMatch(in: working), case .unspecified = timing {
            let place = Self.cleanPlace(clause.group(1) ?? "")
            if !place.isEmpty {
                timing = .arriving(place)
                working = Self.removing(clause.range.intRange, from: working)
            }
        }

        let subject = Self.cleanSubject(working)
        let refersToContext = subject.isEmpty || Self.contextReferences.contains(subject.lowercased())
        return ReminderDraft(
            title: refersToContext ? "" : subject.capitalizedFirst,
            timing: timing,
            dueDate: dueDate,
            refersToContext: refersToContext
        )
    }

    private static let edgeWords: Set<String> = ["to", "about", "at", "on", "by", "when", "in", "the", "that", "and", "please", "for", "of"]

    private static func removing(_ range: Range<Int>, from text: String) -> String {
        let ns = text as NSString
        guard range.upperBound <= ns.length else { return text }
        return ns.replacingCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: " ")
    }

    private static func cleanSubject(_ text: String) -> String {
        var words = text
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        while let first = words.first, edgeWords.contains(first.lowercased()) { words.removeFirst() }
        while let last = words.last, edgeWords.contains(last.lowercased()) { words.removeLast() }
        return words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
    }

    private static func cleanPlace(_ text: String) -> String {
        var words = text.trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let trailing: Set<String> = ["please", "today", "tomorrow", "tonight", "later", "again", "next", "time"]
        while let last = words.last, trailing.contains(last.lowercased()) || edgeWords.contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, ["the", "my", "a", "an", "to", "at"].contains(first.lowercased()) { words.removeFirst() }
        return words.joined(separator: " ")
    }
}
