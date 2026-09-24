import Foundation

enum PrivacyMasker {
    static func mask(_ text: String) -> String {
        var result = text
        let patterns: [(String, String)] = [
            ("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", "$0"),
            ("(?<!\\d)(?:\\+?86[- ]?)?1[3-9]\\d{9}(?!\\d)", "$0"),
            ("(?<!\\d)\\d{15,19}(?!\\d)", "$0"),
            ("(?<![A-Z0-9])\\d{17}[0-9Xx](?![A-Z0-9])", "$0"),
            ("(?i)(api[_-]?key|token|secret|password|passwd|pwd)\\s*[:=]\\s*[^\\s,;]+", "$0"),
            ("(?i)sk-[A-Za-z0-9_-]{20,}", "$0")
        ]

        for (pattern, _) in patterns {
            result = replaceMatches(in: result, pattern: pattern)
        }
        return result
    }

    private static func replaceMatches(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed()
        var output = text
        for match in matches {
            let original = nsText.substring(with: match.range)
            let masked = maskToken(original)
            if let range = Range(match.range, in: output) {
                output.replaceSubrange(range, with: masked)
            }
        }
        return output
    }

    private static func maskToken(_ token: String) -> String {
        guard token.count > 6 else {
            return String(repeating: "*", count: max(3, token.count))
        }

        let prefix = token.prefix(2)
        let suffix = token.suffix(2)
        let stars = String(repeating: "*", count: min(12, max(4, token.count - 4)))
        return "\(prefix)\(stars)\(suffix)"
    }
}
