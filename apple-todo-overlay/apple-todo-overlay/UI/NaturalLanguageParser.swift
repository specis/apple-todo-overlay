import Foundation

struct ParsedInput {
    var title: String
    var dueDate: Date?
    var priority: Priority
    var tagNames: [String]

    var hasMetadata: Bool {
        dueDate != nil || priority != .none || !tagNames.isEmpty
    }
}

enum NaturalLanguageParser {

    static func parse(_ raw: String) -> ParsedInput {
        var text = raw

        let tagNames  = extractTags(&text)
        let priority  = extractPriority(&text)
        let dueDate   = extractDate(&text)
        let title     = text.trimmingCharacters(in: .whitespaces)

        return ParsedInput(title: title, dueDate: dueDate, priority: priority, tagNames: tagNames)
    }

    // MARK: - Tags  (#word)

    private static func extractTags(_ text: inout String) -> [String] {
        let pattern = /#(\w+)/
        var tags: [String] = []
        var result = text

        for match in text.matches(of: pattern) {
            tags.append(String(match.output.1))
            result = result.replacingOccurrences(of: String(match.output.0), with: "")
        }
        text = result
        return tags
    }

    // MARK: - Priority  (! = high, !! = medium)

    private static func extractPriority(_ text: inout String) -> Priority {
        // Check !! before ! so we don't partially match
        if let range = text.range(of: #"\s*!!\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
            return .medium
        }
        if let range = text.range(of: #"\s*!\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
            return .high
        }
        return .none
    }

    // MARK: - Date

    private static func extractDate(_ text: inout String) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let lower = text.lowercased()

        // Ordered by specificity — check longer phrases first
        let keywords: [(pattern: String, date: Date?)] = [
            ("next monday",    nextWeekday(2, from: today)),
            ("next tuesday",   nextWeekday(3, from: today)),
            ("next wednesday", nextWeekday(4, from: today)),
            ("next thursday",  nextWeekday(5, from: today)),
            ("next friday",    nextWeekday(6, from: today)),
            ("next saturday",  nextWeekday(7, from: today)),
            ("next sunday",    nextWeekday(1, from: today)),
            ("next week",      cal.date(byAdding: .weekOfYear, value: 1, to: today)),
            ("tomorrow",       cal.date(byAdding: .day, value: 1, to: today)),
            ("today",          today),
            ("tom",            cal.date(byAdding: .day, value: 1, to: today)),
            ("tod",            today),
            ("monday",         nextWeekday(2, from: today)),
            ("tuesday",        nextWeekday(3, from: today)),
            ("wednesday",      nextWeekday(4, from: today)),
            ("thursday",       nextWeekday(5, from: today)),
            ("friday",         nextWeekday(6, from: today)),
            ("saturday",       nextWeekday(7, from: today)),
            ("sunday",         nextWeekday(1, from: today)),
            ("mon",            nextWeekday(2, from: today)),
            ("tue",            nextWeekday(3, from: today)),
            ("wed",            nextWeekday(4, from: today)),
            ("thu",            nextWeekday(5, from: today)),
            ("fri",            nextWeekday(6, from: today)),
            ("sat",            nextWeekday(7, from: today)),
            ("sun",            nextWeekday(1, from: today)),
        ]

        for (keyword, date) in keywords {
            if lower.contains(keyword) {
                removeKeyword(keyword, from: &text)
                return date
            }
        }

        // "in N days" / "in N weeks"
        if let (range, days) = matchRelative(#"in (\d+) days?"#, in: lower) {
            text.removeSubrange(caseInsensitiveRange(of: range, in: text))
            return cal.date(byAdding: .day, value: days, to: today)
        }
        if let (range, weeks) = matchRelative(#"in (\d+) weeks?"#, in: lower) {
            text.removeSubrange(caseInsensitiveRange(of: range, in: text))
            return cal.date(byAdding: .weekOfYear, value: weeks, to: today)
        }

        return nil
    }

    // MARK: - Helpers

    private static func nextWeekday(_ weekday: Int, from today: Date) -> Date? {
        let cal = Calendar.current
        let currentWeekday = cal.component(.weekday, from: today)
        var daysAhead = weekday - currentWeekday
        if daysAhead <= 0 { daysAhead += 7 }
        return cal.date(byAdding: .day, value: daysAhead, to: today)
    }

    private static func removeKeyword(_ keyword: String, from text: inout String) {
        // Remove the keyword case-insensitively, collapsing extra whitespace
        if let range = text.range(of: keyword, options: .caseInsensitive) {
            text.removeSubrange(range)
        }
        text = text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func matchRelative(_ pattern: String, in text: String) -> (String, Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let numRange = Range(match.range(at: 1), in: text),
              let num = Int(text[numRange]),
              let fullRange = Range(match.range(at: 0), in: text)
        else { return nil }
        return (String(text[fullRange]), num)
    }

    private static func caseInsensitiveRange(of substring: String, in text: String) -> Range<String.Index> {
        text.range(of: substring, options: .caseInsensitive) ?? text.startIndex..<text.startIndex
    }
}
