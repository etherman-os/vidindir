import Foundation

public struct ByteLineFramer: Sendable {
    private var buffer = Data()
    public let maximumLineLength: Int

    public init(maximumLineLength: Int = 1_048_576) {
        precondition(maximumLineLength > 0)
        self.maximumLineLength = maximumLineLength
    }

    /// Adds an arbitrary byte chunk and returns each complete UTF-8 line.
    /// Keeping bytes (instead of strings) prevents corruption when a multi-byte
    /// scalar is split across pipe reads.
    public mutating func append(_ data: Data) throws -> [String] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)

        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineLength = buffer.distance(from: buffer.startIndex, to: newline)
            guard lineLength <= maximumLineLength else {
                buffer.removeAll(keepingCapacity: false)
                throw ByteLineFramerError.lineTooLong(limit: maximumLineLength)
            }

            var bytes = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if bytes.last == 0x0D {
                bytes.removeLast()
            }
            lines.append(String(decoding: bytes, as: UTF8.self))
        }

        guard buffer.count <= maximumLineLength else {
            buffer.removeAll(keepingCapacity: false)
            throw ByteLineFramerError.lineTooLong(limit: maximumLineLength)
        }
        return lines
    }

    /// Emits the final newline-less line at EOF.
    public mutating func finish() throws -> [String] {
        guard !buffer.isEmpty else { return [] }
        guard buffer.count <= maximumLineLength else {
            buffer.removeAll(keepingCapacity: false)
            throw ByteLineFramerError.lineTooLong(limit: maximumLineLength)
        }

        var bytes = buffer
        buffer.removeAll(keepingCapacity: false)
        if bytes.last == 0x0D {
            bytes.removeLast()
        }
        return [String(decoding: bytes, as: UTF8.self)]
    }
}

public enum ByteLineFramerError: LocalizedError, Equatable, Sendable {
    case lineTooLong(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .lineTooLong(let limit):
            return "A tool output line exceeded the \(limit)-byte limit."
        }
    }
}
