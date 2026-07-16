import Foundation

public struct DownloadRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let format: DownloadFormat
    public let destinationDirectory: URL
    public var outputFileURL: URL?
    public var title: String?
    public var status: DownloadStatus
    public let startedAt: Date
    public var finishedAt: Date?

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        format: DownloadFormat,
        destinationDirectory: URL,
        outputFileURL: URL? = nil,
        title: String? = nil,
        status: DownloadStatus = .queued,
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.format = format
        self.destinationDirectory = destinationDirectory
        self.outputFileURL = outputFileURL
        self.title = title
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public enum DownloadStatus: String, Codable, Equatable, Hashable, Sendable {
    case queued
    case preparing
    case downloading
    case postProcessing
    case completed
    case failed
    case cancelled
}
