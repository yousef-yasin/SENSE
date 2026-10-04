import Foundation

public enum TextTokenizer {
    private static let foldingLocale = Locale(identifier: "en_US_POSIX")

    public static func words(in text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: foldingLocale)
        var result: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                result.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty {
            result.append(String(current))
        }
        return result
    }

    public static func terms(in text: String, excluding extraStopwords: Set<String> = []) -> [String] {
        words(in: text)
            .filter { word in
                guard !stopwords.contains(word), !extraStopwords.contains(word) else { return false }
                return word.count > 1 || word.allSatisfy(\.isNumber)
            }
            .map(stem)
    }

    public static func stem(_ word: String) -> String {
        guard word.count > 3, word.allSatisfy(\.isLetter) else { return word }
        var w = word

        if w.hasSuffix("ies"), w.count > 4 {
            w = String(w.dropLast(3)) + "y"
        } else if w.hasSuffix("sses") {
            w = String(w.dropLast(2))
        } else if w.hasSuffix("es"), w.count - 2 >= 3, ["s", "x", "z", "ch", "sh"].contains(where: { w.dropLast(2).hasSuffix($0) }) {
            w = String(w.dropLast(2))
        } else if w.hasSuffix("s"), !w.hasSuffix("ss"), !w.hasSuffix("us"), !w.hasSuffix("is") {
            w = String(w.dropLast())
        }

        if w.hasSuffix("ing"), w.count - 3 >= 3 {
            w = String(w.dropLast(3))
        } else if w.hasSuffix("ed"), w.count - 2 >= 3 {
            w = String(w.dropLast(2))
        }

        if w.hasSuffix("e"), w.count > 3 {
            w = String(w.dropLast())
        }
        return w
    }

    public static let stopwords: Set<String> = [
        "a", "about", "above", "after", "again", "against", "all", "am", "an", "and", "any", "are", "as", "at",
        "be", "because", "been", "before", "being", "below", "between", "both", "but", "by", "can", "could",
        "did", "do", "does", "doing", "down", "during", "each", "few", "for", "from", "further", "had", "has",
        "have", "having", "he", "her", "here", "hers", "herself", "him", "himself", "his", "how", "i", "if",
        "in", "into", "is", "it", "its", "itself", "just", "me", "more", "most", "my", "myself", "no", "nor",
        "not", "now", "of", "off", "on", "once", "only", "or", "other", "our", "ours", "ourselves", "out",
        "over", "own", "same", "she", "should", "so", "some", "such", "than", "that", "the", "their",
        "theirs", "them", "themselves", "then", "there", "these", "they", "this", "those", "through", "to",
        "too", "under", "until", "up", "very", "was", "we", "were", "what", "when", "where", "which", "while",
        "who", "whom", "why", "will", "with", "would", "you", "your", "yours", "yourself", "yourselves",
        "im", "ive", "id", "ill", "dont", "didnt", "s", "t"
    ]
}
