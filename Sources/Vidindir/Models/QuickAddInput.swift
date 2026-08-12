import Foundation

struct QuickAddInput: Equatable {
    let urls: [URL]
    let invalidTokenCount: Int
    let duplicateTokenCount: Int

    var isValid: Bool {
        !urls.isEmpty && invalidTokenCount == 0
    }

    var isBatch: Bool {
        urls.count > 1
    }

    static func parse(_ value: String) -> QuickAddInput {
        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        var urls: [URL] = []
        var seen = Set<String>()
        var invalidTokenCount = 0
        var duplicateTokenCount = 0

        for token in tokens {
            let value = String(token)
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host != nil else {
                invalidTokenCount += 1
                continue
            }
            let identity = url.absoluteString
            if seen.insert(identity).inserted {
                urls.append(url)
            } else {
                duplicateTokenCount += 1
            }
        }

        return QuickAddInput(
            urls: urls,
            invalidTokenCount: invalidTokenCount,
            duplicateTokenCount: duplicateTokenCount
        )
    }
}
