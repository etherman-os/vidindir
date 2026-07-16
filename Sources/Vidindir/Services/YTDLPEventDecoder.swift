import Foundation

public struct YTDLPProgress: Equatable, Sendable {
    public let status: String?
    public let downloadedBytes: Int64?
    public let totalBytes: Int64?
    public let estimatedTotalBytes: Int64?
    public let speedBytesPerSecond: Double?
    public let etaSeconds: Double?
    public let filename: String?

    public init(
        status: String? = nil,
        downloadedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        estimatedTotalBytes: Int64? = nil,
        speedBytesPerSecond: Double? = nil,
        etaSeconds: Double? = nil,
        filename: String? = nil
    ) {
        self.status = status
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.estimatedTotalBytes = estimatedTotalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.filename = filename
    }

    public var fractionCompleted: Double? {
        guard let downloadedBytes,
              let total = totalBytes ?? estimatedTotalBytes,
              total > 0 else {
            return nil
        }
        return min(1, max(0, Double(downloadedBytes) / Double(total)))
    }
}

public enum YTDLPEvent: Equatable, Sendable {
    case progress(YTDLPProgress)
    case plannedArtifact(path: String)
    case postProcessing
    case artifact(path: String)
    case unknown(name: String, payload: String)
}

public enum YTDLPDecodedLine: Equatable, Sendable {
    case event(YTDLPEvent)
    case log(String)
    case malformed(payload: String)
}

public struct YTDLPEventDecoder: Sendable {
    public static let sentinel = "__VIDINDIR_YTDLP__"

    private let decoder: JSONDecoder

    public init() {
        decoder = JSONDecoder()
    }

    public func decode(line: String) -> YTDLPDecodedLine {
        guard line.hasPrefix(Self.sentinel) else {
            return .log(line)
        }

        let payload = String(line.dropFirst(Self.sentinel.count))
        guard let data = payload.data(using: .utf8),
              let envelope = try? decoder.decode(Envelope.self, from: data) else {
            return .malformed(payload: payload)
        }

        switch envelope.event {
        case "progress":
            guard let progress = try? decoder.decode(ProgressPayload.self, from: data) else {
                return .malformed(payload: payload)
            }
            return .event(.progress(progress.value))

        case "plannedArtifact":
            guard let artifact = try? decoder.decode(ArtifactPayload.self, from: data),
                  let path = artifact.usablePath else {
                return .malformed(payload: payload)
            }
            return .event(.plannedArtifact(path: path))

        case "postProcessing":
            return .event(.postProcessing)

        case "artifact":
            guard let artifact = try? decoder.decode(ArtifactPayload.self, from: data),
                  let path = artifact.usablePath else {
                return .malformed(payload: payload)
            }
            return .event(.artifact(path: path))

        default:
            return .event(.unknown(name: envelope.event, payload: payload))
        }
    }
}

private struct Envelope: Decodable {
    let event: String
}

private struct ArtifactPayload: Decodable {
    let path: String?

    var usablePath: String? {
        guard let path,
              !path.isEmpty,
              path != "NA",
              path != "null" else {
            return nil
        }
        return path
    }
}

private struct ProgressPayload: Decodable {
    let status: String?
    let downloadedBytes: Int64?
    let totalBytes: Int64?
    let estimatedTotalBytes: Int64?
    let speed: Double?
    let eta: Double?
    let filename: String?

    enum CodingKeys: String, CodingKey {
        case status
        case downloadedBytes
        case totalBytes
        case estimatedTotalBytes
        case speed
        case eta
        case filename
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = values.decodeLossyString(forKey: .status)
        downloadedBytes = values.decodeLossyInt64(forKey: .downloadedBytes)
        totalBytes = values.decodeLossyInt64(forKey: .totalBytes)
        estimatedTotalBytes = values.decodeLossyInt64(forKey: .estimatedTotalBytes)
        speed = values.decodeLossyDouble(forKey: .speed)
        eta = values.decodeLossyDouble(forKey: .eta)
        filename = values.decodeLossyString(forKey: .filename)
    }

    var value: YTDLPProgress {
        YTDLPProgress(
            status: status,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            estimatedTotalBytes: estimatedTotalBytes,
            speedBytesPerSecond: speed,
            etaSeconds: eta,
            filename: filename
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key),
           value != "NA", value != "null" {
            return value
        }
        return nil
    }

    func decodeLossyInt64(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key),
           value.isFinite,
           value >= Double(Int64.min),
           value < -Double(Int64.min) {
            return Int64(value)
        }
        if let value = decodeLossyString(forKey: key) {
            if let integer = Int64(value) { return integer }
            guard let number = Double(value),
                  number.isFinite,
                  number >= Double(Int64.min),
                  number < -Double(Int64.min) else {
                return nil
            }
            return Int64(number)
        }
        return nil
    }

    func decodeLossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return value
        }
        if let value = decodeLossyString(forKey: key),
           let number = Double(value), number.isFinite {
            return number
        }
        return nil
    }
}
