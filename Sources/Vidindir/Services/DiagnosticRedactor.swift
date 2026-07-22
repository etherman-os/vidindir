import Foundation

/// Removes credentials and URL tracking data before process output crosses
/// into user-visible logs or durable failure summaries.
public struct DiagnosticRedactor: Sendable {
    public static let defaultMaximumLength = 4_096

    public init() {}

    public func redact(
        _ input: String,
        maximumLength: Int = DiagnosticRedactor.defaultMaximumLength
    ) -> String {
        guard maximumLength > 0 else { return "" }

        var output = stripURLQueriesAndFragments(from: input)
        let replacements: [(pattern: String, template: String)] = [
            (
                #"(?i)\b(authorization\s*:\s*)[^\r\n]+"#,
                "$1[REDACTED]"
            ),
            (
                #"(?i)\b((?:set-)?cookie\s*:\s*)[^\r\n]+"#,
                "$1[REDACTED]"
            ),
            (
                #"(?i)\b(token|access[_-]?token|refresh[_-]?token|api[_-]?key|password|passwd|secret|session[_-]?id)\s*[:=]\s*[^\s&,;]+"#,
                "$1=[REDACTED]"
            ),
            (
                #"(?i)(--(?:cookies?|username|password|token|api[_-]?key)\s+)[^\s]+"#,
                "$1[REDACTED]"
            ),
        ]

        for replacement in replacements {
            output = replacingMatches(
                in: output,
                pattern: replacement.pattern,
                template: replacement.template
            )
        }

        return String(output.prefix(maximumLength))
    }

    private func stripURLQueriesAndFragments(from input: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"https?://[^\s<>\"']+"#,
            options: [.caseInsensitive]
        ) else { return input }

        var output = input
        let matches = expression.matches(
            in: input,
            range: NSRange(input.startIndex..., in: input)
        )

        for match in matches.reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let matched = String(output[range])
            let trailingPunctuation = String(matched.reversed().prefix {
                ".,;:)]}".contains($0)
            }.reversed())
            let candidate = String(matched.dropLast(trailingPunctuation.count))
            guard var components = URLComponents(string: candidate),
                  components.scheme != nil,
                  components.host != nil else { continue }
            components.query = nil
            components.fragment = nil
            guard let sanitized = components.string else { continue }
            output.replaceSubrange(range, with: sanitized + trailingPunctuation)
        }
        return output
    }

    private func replacingMatches(
        in input: String,
        pattern: String,
        template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: []
        ) else { return input }
        return expression.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: template
        )
    }
}
