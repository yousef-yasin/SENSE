import Foundation

public struct ContentAnalyzer: Sendable {
    public var calendar: Calendar
    public var dateExtractor: DateExtractor
    public var entityExtractor = EntityExtractor()

    public init(calendar: Calendar = .autoupdatingCurrent, prefersDayFirst: Bool? = nil) {
        self.calendar = calendar
        self.dateExtractor = DateExtractor(calendar: calendar, prefersDayFirst: prefersDayFirst)
    }

    public func analyze(_ input: CaptureInput, now: Date = Date()) -> Understanding {
        let text = input.text.trimmed
        let lines = text.components(separatedBy: .newlines).map(\.trimmed).filter { !$0.isEmpty }
        let statements = Self.statements(in: lines)
        let dates = dateExtractor.extract(from: text, relativeTo: now)
        let dateRanges = dates.map(\.range)
        let money = entityExtractor.money(in: text, excluding: dateRanges)
        let emails = entityExtractor.emails(in: text)
        let links = entityExtractor.links(in: text)
        let phones = entityExtractor.phoneNumbers(in: text, excluding: dateRanges + money.map(\.range))
        let labels = input.imageLabels.sorted { $0.confidence > $1.confidence }

        let kind = classify(input: input, text: text, lines: lines, dates: dates, money: money, labels: labels, now: now)
        let highlights = highlights(in: statements, now: now)
        let merchant = kind == .receipt ? Self.merchant(in: lines) : nil
        let total = kind == .receipt ? Self.total(in: lines, amounts: money, extractor: entityExtractor) : nil
        let title = title(kind: kind, lines: lines, statements: statements, merchant: merchant, labels: labels)

        var entities: [ExtractedEntity] = []
        if let merchant {
            entities.append(ExtractedEntity(kind: .merchant, text: merchant))
        }
        entities += dates.map { ExtractedEntity(kind: .date, text: $0.text, date: $0.date) }
        entities += money.map {
            ExtractedEntity(kind: .money, text: $0.text, value: [NSDecimalNumber(decimal: $0.value).stringValue, $0.currency].compactMap { $0 }.joined(separator: " "))
        }
        entities += emails.map { ExtractedEntity(kind: .email, text: $0) }
        entities += phones.map { ExtractedEntity(kind: .phone, text: $0, value: $0.filter { $0.isNumber || $0 == "+" }) }
        entities += links.map { ExtractedEntity(kind: .link, text: $0.absoluteString) }
        entities += labels.prefix(5).map { ExtractedEntity(kind: .label, text: $0.displayName, value: $0.identifier) }

        let summary = summarize(kind: kind, statements: statements, highlights: highlights, merchant: merchant, total: total, dates: dates, labels: labels)

        var suggestions: [SuggestedAction] = reminderSuggestions(highlights: highlights, dates: dates, statements: statements, fallbackTitle: title, kind: kind, now: now)
            .map(SuggestedAction.reminder)
        suggestions += links.prefix(2).map(SuggestedAction.openLink)
        suggestions += phones.prefix(1).map(SuggestedAction.call)
        suggestions += emails.prefix(1).map(SuggestedAction.email)

        return Understanding(
            kind: kind,
            title: title,
            summary: summary,
            highlights: highlights,
            entities: entities,
            suggestions: suggestions,
            tags: tags(text: text, labels: labels),
            origin: .onDevice
        )
    }

    // MARK: Classification

    private static let receiptCues = Pattern("\\b(total|subtotal|sub-total|tax|vat|receipt|invoice|cash|change due|visa|mastercard|amex|debit|credit card|qty|amount due|balance due|thank you for shopping|order #|item)\\b")
    private static let announcementCues = Pattern("\\b(registration|register|announcement|notice|deadline|closes?|opens?|apply|application|submit|submission|attention|students?|sign[- ]?up|rsvp|venue|enrol(?:l)?ment|enrol(?:l)?|admission|open day|important)\\b")
    private static let eventCues = Pattern("\\b(workshop|seminar|meeting|concert|party|conference|lecture|webinar|appointment|match|festival|exhibition|ceremony|class|session|talk|meetup|show)\\b")
    private static let taskCues = Pattern("^(?:to ?do:?\\s*)?(buy|call|email|pick up|finish|send|pay|book|renew|return|fix|clean|schedule|cancel|order|bring|submit|check|remember to|don't forget to|need to|i need to|i have to)\\b")

    private func classify(input: CaptureInput, text: String, lines: [String], dates: [DetectedDate], money: [MoneyAmount], labels: [ImageLabel], now: Date) -> MemoryKind {
        let letters = text.filter(\.isLetter).count
        if letters < 20, !labels.isEmpty {
            return .object
        }
        if text.isEmpty {
            return input.source == .text || input.source == .voice ? .note : .observation
        }

        let receiptScore = Self.receiptCues.matches(in: text).count + (money.count >= 2 ? 2 : 0)
        if receiptScore >= 3, !money.isEmpty {
            return .receipt
        }

        if (input.source == .text || input.source == .voice), Self.taskCues.contains(in: text.lowercased()) {
            return .task
        }

        let hasUpcomingDate = dates.contains { $0.date >= calendar.startOfDay(for: now) }
        let announcementScore = Set(Self.announcementCues.matches(in: text).map { $0.text.lowercased() }).count
        let eventScore = Set(Self.eventCues.matches(in: text).map { $0.text.lowercased() }).count

        if hasUpcomingDate, eventScore > 0, eventScore >= announcementScore {
            return .event
        }
        if announcementScore + (hasUpcomingDate ? 2 : 0) >= 3 {
            return .announcement
        }
        if lines.count >= 8 || text.count >= 350 {
            return .document
        }
        if input.source == .camera || input.source == .photo || input.source == .live {
            return lines.count >= 3 ? .document : .observation
        }
        return .note
    }

    // MARK: Highlights

    private static let deadlineCue = Pattern("\\b(deadline|due|closes?|closing|expires?|expiry|expiration|last day|no later than|until|till|ends?|before|by|submit|valid through|valid until|best before|use by|cutoff|cut-off)\\b")
    private static let warningCue = Pattern("\\b(warning|caution|danger|hazard|do not|don't|never|prohibited|not allowed|not permitted|forbidden|must not|attention|important|urgent|alert|penalty|fine of|late fee|non-refundable|no refunds?)\\b")
    private static let requirementCue = Pattern("\\b(must|required|requires?|mandatory|need to|needs to|have to|bring|please ensure|make sure|eligible|eligibility|requirements?|necessary)\\b")

    private func highlights(in statements: [String], now: Date) -> [Highlight] {
        var result: [Highlight] = []
        for statement in statements where statement.count <= 280 {
            let dates = dateExtractor.extract(from: statement, relativeTo: now)
            let date = dates.first?.date
            let kind: Highlight.Kind?
            if date != nil, Self.deadlineCue.contains(in: statement) {
                kind = .deadline
            } else if Self.warningCue.contains(in: statement) {
                kind = .warning
            } else if Self.requirementCue.contains(in: statement) {
                kind = .requirement
            } else if date != nil, statement.filter(\.isLetter).count >= 3 {
                kind = .date
            } else {
                kind = nil
            }
            if let kind {
                result.append(Highlight(kind: kind, text: statement, date: date))
            }
            if result.count == 8 { break }
        }
        return result
    }

    // MARK: Reminders

    private func reminderSuggestions(highlights: [Highlight], dates: [DetectedDate], statements: [String], fallbackTitle: String, kind: MemoryKind, now: Date) -> [ReminderDraft] {
        guard kind != .receipt else { return [] }
        var drafts: [ReminderDraft] = []
        var seenDates = Set<Date>()

        for highlight in highlights where highlight.kind == .deadline || highlight.kind == .date {
            guard let detected = dateExtractor.extract(from: highlight.text, relativeTo: now).first else { continue }
            guard seenDates.insert(detected.date).inserted else { continue }
            let isDeadline = highlight.kind == .deadline
            guard let fireDate = ReminderPolicy.suggestedFireDate(
                for: detected.date,
                includesTime: detected.includesTime,
                isDeadline: isDeadline,
                now: now,
                calendar: calendar
            ) else { continue }
            let due = detected.includesTime
                ? detected.date
                : calendar.date(bySettingHour: ReminderPolicy.defaultHour, minute: 0, second: 0, of: detected.date) ?? detected.date
            let title = Self.reminderTitle(from: highlight.text, removing: detected) ?? fallbackTitle
            drafts.append(ReminderDraft(title: title, timing: .at(fireDate), dueDate: due))
            if drafts.count == 3 { break }
        }
        return drafts
    }

    private static let trailingConnectors: Set<String> = ["at", "on", "by", "before", "until", "till", "from", "the", "of", "is", "are", "in", "and", "to"]

    static func reminderTitle(from statement: String, removing detected: DetectedDate) -> String? {
        let ns = statement as NSString
        let range = NSRange(location: detected.range.lowerBound, length: detected.range.count)
        guard range.location + range.length <= ns.length else { return nil }
        let before = ns.substring(to: range.location)
        let after = ns.substring(from: range.location + range.length)
        let combined = [before, after]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        var words = combined.split(separator: " ").map(String.init)
        while let last = words.last, trailingConnectors.contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, trailingConnectors.contains(first.lowercased()) { words.removeFirst() }
        let title = words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard title.filter(\.isLetter).count >= 3 else { return nil }
        return title.truncated(to: 80).capitalizedFirst
    }

    // MARK: Title & summary

    private func title(kind: MemoryKind, lines: [String], statements: [String], merchant: String?, labels: [ImageLabel]) -> String {
        switch kind {
        case .receipt:
            return merchant ?? ""
        case .object:
            return labels.first?.displayName ?? lines.first?.truncated(to: 60) ?? ""
        case .announcement, .event, .document:
            if let heading = Self.heading(in: lines) {
                return heading
            }
            return statements.first?.truncated(to: 60) ?? ""
        default:
            return (statements.first ?? lines.first ?? labels.first?.displayName ?? "").truncated(to: 60)
        }
    }

    private static func heading(in lines: [String]) -> String? {
        let candidates = lines.prefix(4).filter { line in
            let letters = line.filter(\.isLetter).count
            return (3...60).contains(line.count) && letters >= 3 && Double(letters) / Double(line.count) > 0.6
        }
        let shouting = candidates.first { line in
            let letters = line.filter(\.isLetter)
            return letters.filter(\.isUppercase).count * 10 >= letters.count * 7
        }
        guard let chosen = shouting ?? candidates.first else { return nil }
        let isAllCaps = chosen.filter(\.isLetter).allSatisfy(\.isUppercase)
        return isAllCaps ? chosen.capitalized : chosen
    }

    private func summarize(kind: MemoryKind, statements: [String], highlights: [Highlight], merchant: String?, total: MoneyAmount?, dates: [DetectedDate], labels: [ImageLabel]) -> String {
        switch kind {
        case .receipt:
            return [merchant, total?.text, dates.first?.text].compactMap { $0 }.joined(separator: " · ")
        case .object where statements.isEmpty:
            return labels.prefix(3).map(\.displayName).joined(separator: ", ")
        default:
            let source = highlights.isEmpty ? Array(statements.prefix(2)) : highlights.prefix(2).map(\.text)
            return source.joined(separator: " ").truncated(to: 220)
        }
    }

    private static let receiptNoise = Pattern("\\b(receipt|invoice|tax|vat|tel|phone|www|http|date|time|order|table|cashier|server|welcome)\\b")

    private static func merchant(in lines: [String]) -> String? {
        lines.prefix(5).first { line in
            let letters = line.filter(\.isLetter).count
            let digits = line.filter(\.isNumber).count
            return letters >= 3 && digits <= 2 && line.count <= 40 && !receiptNoise.contains(in: line)
        }.map { line in
            line.filter(\.isLetter).allSatisfy(\.isUppercase) ? line.capitalized : line
        }
    }

    private static let totalLine = Pattern("^(?!.*\\bsub[- ]?total\\b).*\\b(total|amount due|balance due|grand total|to pay)\\b")

    private static func total(in lines: [String], amounts: [MoneyAmount], extractor: EntityExtractor) -> MoneyAmount? {
        for (index, line) in lines.enumerated().reversed() where totalLine.contains(in: line) {
            if let amount = extractor.money(in: line).last {
                return amount
            }
            if index + 1 < lines.count, let amount = extractor.money(in: lines[index + 1]).first {
                return amount
            }
        }
        return amounts.max { $0.value < $1.value }
    }

    private func tags(text: String, labels: [ImageLabel]) -> [String] {
        var tags = labels.prefix(3).map { $0.displayName.lowercased() }
        let words = TextTokenizer.words(in: text).filter { word in
            word.count >= 4 && word.allSatisfy(\.isLetter) && !TextTokenizer.stopwords.contains(word)
        }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for word in words {
            if counts[word] == nil { order.append(word) }
            counts[word, default: 0] += 1
        }
        let keywords = order.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }.prefix(5)
        for keyword in keywords where !tags.contains(keyword) {
            tags.append(keyword)
        }
        return tags
    }

    // MARK: Segmentation

    private static let sentenceBreak = Pattern("(?<=[.!?])\\s+(?=[A-Z\"“])")

    static func statements(in lines: [String]) -> [String] {
        lines.flatMap { line -> [String] in
            let ns = line as NSString
            var pieces: [String] = []
            var start = 0
            for match in sentenceBreak.matches(in: line) {
                let piece = ns.substring(with: NSRange(location: start, length: match.range.location - start)).trimmed
                if !piece.isEmpty { pieces.append(piece) }
                start = match.range.location + match.range.length
            }
            let rest = ns.substring(from: start).trimmed
            if !rest.isEmpty { pieces.append(rest) }
            return pieces
        }
    }
}
