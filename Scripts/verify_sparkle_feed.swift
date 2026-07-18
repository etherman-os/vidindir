#!/usr/bin/env swift

import CryptoKit
import Foundation

struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

struct Arguments {
    let feedPath: String
    let plistPath: String
    let baseFeedPath: String?
    let archivePath: String?
    let expectedVersion: String?
    let expectedBuild: String?
    let expectedDownloadURL: String?

    init(_ rawArguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 0

        while index < rawArguments.count {
            let flag = rawArguments[index]
            guard flag.hasPrefix("--"), index + 1 < rawArguments.count else {
                throw VerificationFailure(description: "Invalid argument: \(flag)")
            }
            let allowedFlags: Set<String> = [
                "--feed", "--plist", "--base-feed", "--archive",
                "--expected-version", "--expected-build", "--expected-download-url",
            ]
            guard allowedFlags.contains(flag) else {
                throw VerificationFailure(description: "Unknown argument: \(flag)")
            }
            guard values[flag] == nil else {
                throw VerificationFailure(description: "Duplicate argument: \(flag)")
            }
            values[flag] = rawArguments[index + 1]
            index += 2
        }

        guard let feedPath = values["--feed"], let plistPath = values["--plist"] else {
            throw VerificationFailure(
                description: "Usage: verify_sparkle_feed.swift --feed <appcast.xml> --plist <Info.plist> [--base-feed <previous-appcast.xml> --archive <update.zip> --expected-version <version> --expected-build <build> --expected-download-url <url>]"
            )
        }

        let expectedReleaseArguments = [
            values["--expected-version"],
            values["--expected-build"],
        ]
        let suppliedExpectedReleaseArgumentCount = expectedReleaseArguments.compactMap { $0 }.count
        guard suppliedExpectedReleaseArgumentCount == 0
                || suppliedExpectedReleaseArgumentCount == expectedReleaseArguments.count else {
            throw VerificationFailure(
                description: "--expected-version and --expected-build must be supplied together"
            )
        }

        let artifactArguments = [
            values["--base-feed"],
            values["--archive"],
            values["--expected-download-url"],
        ]
        let suppliedArtifactArgumentCount = artifactArguments.compactMap { $0 }.count
        guard suppliedArtifactArgumentCount == 0
                || suppliedArtifactArgumentCount == artifactArguments.count else {
            throw VerificationFailure(
                description: "--base-feed, --archive, and --expected-download-url must be supplied together"
            )
        }
        guard suppliedArtifactArgumentCount == 0 || suppliedExpectedReleaseArgumentCount == 2 else {
            throw VerificationFailure(
                description: "Artifact verification also requires --expected-version and --expected-build"
            )
        }

        self.feedPath = feedPath
        self.plistPath = plistPath
        baseFeedPath = values["--base-feed"]
        archivePath = values["--archive"]
        expectedVersion = values["--expected-version"]
        expectedBuild = values["--expected-build"]
        expectedDownloadURL = values["--expected-download-url"]
    }
}

func exactCaptures(_ pattern: String, in value: String, count: Int) throws -> [String] {
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard
        let match = regex.firstMatch(in: value, range: range),
        match.range == range,
        match.numberOfRanges == count + 1
    else {
        throw VerificationFailure(description: "The Sparkle signature trailer is malformed or contains unexpected fields")
    }
    return try (1...count).map { index in
        guard let captureRange = Range(match.range(at: index), in: value) else {
            throw VerificationFailure(description: "The Sparkle signature trailer has a missing field")
        }
        return String(value[captureRange])
    }
}

let sparkleNamespaceURI = "http://www.andymatuschak.org/xml-namespaces/sparkle"

func expandedName(namespaceURI: String, localName: String) -> String {
    "{\(namespaceURI)}\(localName)"
}

struct ParsedEnclosure: Equatable {
    let attributes: [String: String]

    func value(namespaceURI: String = "", localName: String) -> String? {
        attributes[expandedName(namespaceURI: namespaceURI, localName: localName)]
    }
}

struct ParsedSelectionNode: Equatable {
    let expandedName: String
    let attributes: [String: String]
    let text: String
    let children: [ParsedSelectionNode]
}

struct ParsedAppcastItem: Equatable {
    let version: String
    let shortVersion: String
    let enclosure: ParsedEnclosure
    /// Every direct Sparkle child other than the two version fields. Attributes
    /// and child order are retained so generate_appcast cannot silently change
    /// channel, rollout, critical-update, or system-requirement semantics.
    let selectionMetadata: [String: ParsedSelectionNode]
}

final class AppcastParserDelegate: NSObject, XMLParserDelegate {
    private struct Node: Equatable {
        let localName: String
        let namespaceURI: String
    }

    private enum CapturedField {
        case version
        case shortVersion
    }

    private struct Capture {
        let field: CapturedField
        let depth: Int
        var text = ""
    }

    private struct WorkingItem {
        var versions: [String] = []
        var shortVersions: [String] = []
        var enclosures: [ParsedEnclosure] = []
        var selectionMetadata: [String: ParsedSelectionNode] = [:]
        var seenSelectionNames: Set<String> = []
    }

    private final class WorkingSelectionNode {
        let expandedName: String
        let attributes: [String: String]
        let depth: Int
        var text = ""
        var children: [WorkingSelectionNode] = []

        init(expandedName: String, attributes: [String: String], depth: Int) {
            self.expandedName = expandedName
            self.attributes = attributes
            self.depth = depth
        }

        var parsed: ParsedSelectionNode {
            ParsedSelectionNode(
                expandedName: expandedName,
                attributes: attributes,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                children: children.map(\.parsed)
            )
        }
    }

    private var stack: [Node] = []
    private var namespaceMappings: [String: [String]] = [:]
    private var currentItem: WorkingItem?
    private var capture: Capture?
    private var selectionStack: [WorkingSelectionNode] = []
    private var rootCount = 0
    private var channelCount = 0
    private(set) var items: [ParsedAppcastItem] = []
    private(set) var failure: String?

    var structureFailure: String? {
        failure
            ?? (rootCount == 1 ? nil : "The appcast must contain exactly one unnamespaced rss root")
            ?? (channelCount == 1 ? nil : "The appcast must contain exactly one direct rss/channel element")
    }

    func parser(
        _ parser: XMLParser,
        didStartMappingPrefix prefix: String,
        toURI namespaceURI: String
    ) {
        namespaceMappings[prefix, default: []].append(namespaceURI)
    }

    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
        namespaceMappings[prefix]?.removeLast()
        if namespaceMappings[prefix]?.isEmpty == true {
            namespaceMappings.removeValue(forKey: prefix)
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = Node(localName: elementName, namespaceURI: namespaceURI ?? "")
        stack.append(node)

        if let qName, qName.hasPrefix("sparkle:"), node.namespaceURI != sparkleNamespaceURI {
            setFailure("The sparkle prefix is bound to an unexpected namespace URI")
            return
        }

        if stack.count == 1 {
            rootCount += 1
            if node != Node(localName: "rss", namespaceURI: "") {
                setFailure("The appcast root must be the unnamespaced rss element")
            }
        } else if stack.count == 2,
                  stack[0] == Node(localName: "rss", namespaceURI: ""),
                  node == Node(localName: "channel", namespaceURI: "") {
            channelCount += 1
        }

        if node.localName == "item" {
            guard isExactItemPath else {
                setFailure("Every item must be a direct unnamespaced /rss/channel/item")
                return
            }
            guard currentItem == nil else {
                setFailure("Nested appcast items are not allowed")
                return
            }
            currentItem = WorkingItem()
            selectionStack.removeAll(keepingCapacity: true)
            return
        }

        guard currentItem != nil else { return }
        let isDirectItemChild = stack.count == 4 && isExactItemPrefix
        let reservedNames: Set<String> = ["version", "shortVersionString", "enclosure"]

        if reservedNames.contains(node.localName), !isDirectItemChild {
            setFailure("Nested \(node.localName) fields are not allowed inside an appcast item")
            return
        }

        if !selectionStack.isEmpty, !isDirectItemChild {
            guard let attributes = normalizedAttributes(attributeDict) else { return }
            let child = WorkingSelectionNode(
                expandedName: expandedName(
                    namespaceURI: node.namespaceURI,
                    localName: node.localName
                ),
                attributes: attributes,
                depth: stack.count
            )
            selectionStack[selectionStack.count - 1].children.append(child)
            selectionStack.append(child)
            return
        }
        guard isDirectItemChild else { return }

        switch node.localName {
        case "version":
            guard node.namespaceURI == sparkleNamespaceURI else {
                setFailure("version must use Sparkle's exact namespace URI")
                return
            }
            guard attributeDict.isEmpty else {
                setFailure("sparkle:version elements must not contain attributes")
                return
            }
            startCapture(.version)
        case "shortVersionString":
            guard node.namespaceURI == sparkleNamespaceURI else {
                setFailure("shortVersionString must use Sparkle's exact namespace URI")
                return
            }
            guard attributeDict.isEmpty else {
                setFailure("sparkle:shortVersionString elements must not contain attributes")
                return
            }
            startCapture(.shortVersion)
        case "enclosure":
            guard node.namespaceURI.isEmpty else {
                setFailure("enclosure must be an unnamespaced direct item child")
                return
            }
            if let enclosure = normalizedEnclosure(attributes: attributeDict) {
                currentItem?.enclosures.append(enclosure)
            }
        default:
            if node.namespaceURI == sparkleNamespaceURI {
                startSelection(
                    localName: node.localName,
                    namespaceURI: node.namespaceURI,
                    attributes: attributeDict
                )
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        capture?.text.append(string)
        selectionStack.last?.text.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if let activeCapture = capture, activeCapture.depth == stack.count {
            let value = activeCapture.text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch activeCapture.field {
            case .version:
                currentItem?.versions.append(value)
            case .shortVersion:
                currentItem?.shortVersions.append(value)
            }
            capture = nil
        }

        if let activeSelection = selectionStack.last,
           activeSelection.depth == stack.count {
            selectionStack.removeLast()
            if selectionStack.isEmpty {
                let localName = stack.last?.localName ?? ""
                currentItem?.selectionMetadata[localName] = activeSelection.parsed
            }
        }

        if isExactItemPath, let workingItem = currentItem {
            if !selectionStack.isEmpty {
                setFailure("An appcast selection field was not closed correctly")
            }
            finishItem(workingItem)
            currentItem = nil
        }
        if !stack.isEmpty {
            stack.removeLast()
        }
    }

    func parser(
        _ parser: XMLParser,
        foundInternalEntityDeclarationWithName name: String,
        value: String?
    ) {
        setFailure("Entity declarations are not allowed in the signed appcast")
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        setFailure("External entity declarations are not allowed in the signed appcast")
    }

    private var isExactItemPrefix: Bool {
        stack.count >= 3
            && stack[0] == Node(localName: "rss", namespaceURI: "")
            && stack[1] == Node(localName: "channel", namespaceURI: "")
            && stack[2] == Node(localName: "item", namespaceURI: "")
    }

    private var isExactItemPath: Bool {
        stack.count == 3 && isExactItemPrefix
    }

    private func startCapture(_ field: CapturedField) {
        guard capture == nil else {
            setFailure("Overlapping appcast scalar fields are not allowed")
            return
        }
        capture = Capture(field: field, depth: stack.count)
    }

    private func startSelection(
        localName: String,
        namespaceURI: String,
        attributes: [String: String]
    ) {
        guard selectionStack.isEmpty else {
            setFailure("Overlapping direct appcast selection fields are not allowed")
            return
        }
        guard currentItem?.seenSelectionNames.contains(localName) == false else {
            setFailure("Duplicate sparkle:\(localName) selection fields are not allowed")
            return
        }
        guard let normalized = normalizedAttributes(attributes) else { return }
        currentItem?.seenSelectionNames.insert(localName)
        selectionStack.append(WorkingSelectionNode(
            expandedName: expandedName(namespaceURI: namespaceURI, localName: localName),
            attributes: normalized,
            depth: stack.count
        ))
    }

    private struct ResolvedAttribute {
        let localName: String
        let namespaceURI: String
        let value: String
    }

    private func resolvedAttributes(_ attributes: [String: String]) -> [ResolvedAttribute]? {
        var resolved: [ResolvedAttribute] = []

        for (qualifiedName, value) in attributes {
            let pieces = qualifiedName.split(separator: ":", maxSplits: 1).map(String.init)
            let localName: String
            let namespaceURI: String
            if pieces.count == 2 {
                localName = pieces[1]
                if pieces[0] == "xml" {
                    namespaceURI = "http://www.w3.org/XML/1998/namespace"
                } else {
                    guard let resolvedNamespace = namespaceMappings[pieces[0]]?.last else {
                        setFailure("Attribute uses an undeclared namespace prefix")
                        return nil
                    }
                    namespaceURI = resolvedNamespace
                }
                if pieces[0] == "sparkle", namespaceURI != sparkleNamespaceURI {
                    setFailure("The sparkle attribute prefix is bound to an unexpected namespace URI")
                    return nil
                }
            } else {
                localName = qualifiedName
                namespaceURI = ""
            }
            resolved.append(ResolvedAttribute(
                localName: localName,
                namespaceURI: namespaceURI,
                value: value
            ))
        }
        return resolved
    }

    private func normalizedAttributes(_ attributes: [String: String]) -> [String: String]? {
        guard let resolved = resolvedAttributes(attributes) else { return nil }
        var normalized: [String: String] = [:]
        for attribute in resolved {
            let key = expandedName(
                namespaceURI: attribute.namespaceURI,
                localName: attribute.localName
            )
            guard normalized[key] == nil else {
                setFailure("Element contains duplicate expanded attribute names")
                return nil
            }
            normalized[key] = attribute.value
        }
        return normalized
    }

    private func normalizedEnclosure(attributes: [String: String]) -> ParsedEnclosure? {
        guard let resolved = resolvedAttributes(attributes) else { return nil }
        var normalized: [String: String] = [:]

        for attribute in resolved {
            if attribute.localName == "version" || attribute.localName == "shortVersionString" {
                setFailure("Version attributes on enclosure are rejected to avoid precedence ambiguity")
                return nil
            }
            if attribute.localName == "edSignature",
               attribute.namespaceURI != sparkleNamespaceURI {
                setFailure("edSignature must use Sparkle's exact namespace URI")
                return nil
            }
            if (attribute.localName == "url" || attribute.localName == "length"),
               !attribute.namespaceURI.isEmpty {
                setFailure("Enclosure url and length must be unnamespaced")
                return nil
            }

            let key = expandedName(
                namespaceURI: attribute.namespaceURI,
                localName: attribute.localName
            )
            guard normalized[key] == nil else {
                setFailure("Enclosure contains duplicate expanded attribute names")
                return nil
            }
            normalized[key] = attribute.value
        }
        return ParsedEnclosure(attributes: normalized)
    }

    private func finishItem(_ workingItem: WorkingItem) {
        guard workingItem.versions.count == 1,
              let version = workingItem.versions.first,
              !version.isEmpty else {
            setFailure("Every item must contain exactly one nonempty sparkle:version element")
            return
        }
        guard workingItem.shortVersions.count == 1,
              let shortVersion = workingItem.shortVersions.first,
              !shortVersion.isEmpty else {
            setFailure("Every item must contain exactly one nonempty sparkle:shortVersionString element")
            return
        }
        guard workingItem.enclosures.count == 1,
              let enclosure = workingItem.enclosures.first else {
            setFailure("Every item must contain exactly one direct enclosure")
            return
        }
        guard enclosure.value(localName: "url") != nil,
              enclosure.value(localName: "length") != nil,
              enclosure.value(namespaceURI: sparkleNamespaceURI, localName: "edSignature") != nil else {
            setFailure("Every enclosure must contain url, length, and sparkle:edSignature")
            return
        }

        items.append(ParsedAppcastItem(
            version: version,
            shortVersion: shortVersion,
            enclosure: enclosure,
            selectionMetadata: workingItem.selectionMetadata
        ))
    }

    private func setFailure(_ message: String) {
        if failure == nil {
            failure = message
        }
    }
}

func parseAppcastItems(from data: Data) throws -> [ParsedAppcastItem] {
    guard data.count <= 16 * 1_024 * 1_024 else {
        throw VerificationFailure(description: "The signed appcast XML exceeds the 16 MiB safety limit")
    }
    let delegate = AppcastParserDelegate()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse() else {
        let detail = delegate.failure
            ?? parser.parserError?.localizedDescription
            ?? "Unknown XML parser error"
        throw VerificationFailure(description: "The signed appcast XML is invalid: \(detail)")
    }
    if let failure = delegate.structureFailure {
        throw VerificationFailure(description: "The signed appcast XML is invalid: \(failure)")
    }
    return delegate.items
}

struct VerifiedFeed {
    let signedData: Data
    let items: [ParsedAppcastItem]
}

func markerRanges(in data: Data, marker: Data) -> [Range<Data.Index>] {
    var ranges: [Range<Data.Index>] = []
    var searchStart = data.startIndex
    while searchStart < data.endIndex,
          let range = data.range(of: marker, in: searchStart..<data.endIndex) {
        ranges.append(range)
        searchStart = range.upperBound
    }
    return ranges
}

func verifyFeed(
    at url: URL,
    publicKey: Curve25519.Signing.PublicKey
) throws -> VerifiedFeed {
    let feedData = try Data(contentsOf: url)
    guard feedData.count <= 16 * 1_024 * 1_024 + 1_024 else {
        throw VerificationFailure(description: "The signed appcast exceeds the safety size limit")
    }

    // Sparkle appends this exact marker and reads the final signature trailer.
    // Requiring one exact marker plus an anchored trailer rejects shadow fields,
    // duplicate signatures, and partial-marker ambiguity.
    let markerData = Data("<!-- sparkle-signatures:\n".utf8)
    let ranges = markerRanges(in: feedData, marker: markerData)
    guard ranges.count == 1, let markerRange = ranges.first else {
        throw VerificationFailure(description: "The appcast must contain exactly one embedded Sparkle signature trailer")
    }
    guard let trailer = String(data: feedData[markerRange.lowerBound...], encoding: .utf8) else {
        throw VerificationFailure(description: "The Sparkle signature trailer is not valid UTF-8")
    }

    let fields = try exactCaptures(
        #"\A<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]+={0,2})\nlength: ([0-9]+)\n-->\s*\z"#,
        in: trailer,
        count: 2
    )
    guard let signedLength = Int(fields[1]),
          signedLength == markerRange.lowerBound else {
        throw VerificationFailure(description: "The appcast signature length does not match its signed XML payload")
    }
    guard let feedSignature = Data(base64Encoded: fields[0]),
          feedSignature.count == 64 else {
        throw VerificationFailure(description: "The appcast feed signature is not a valid Ed25519 signature")
    }

    let signedData = Data(feedData.prefix(signedLength))
    guard publicKey.isValidSignature(feedSignature, for: signedData) else {
        throw VerificationFailure(description: "The appcast signature does not match the app's SUPublicEDKey")
    }
    return VerifiedFeed(
        signedData: signedData,
        items: try parseAppcastItems(from: signedData)
    )
}

func parseStrictUnsignedInteger(_ rawValue: String, fieldName: String) throws -> UInt64 {
    let bytes = Array(rawValue.utf8)
    guard !bytes.isEmpty,
          bytes.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          (bytes.count == 1 || bytes[0] != 48),
          let value = UInt64(rawValue) else {
        throw VerificationFailure(
            description: "\(fieldName) must be a canonical unsigned 64-bit integer"
        )
    }
    return value
}

struct StrictSemanticVersion: Comparable {
    let major: UInt64
    let minor: UInt64
    let patch: UInt64

    init(_ rawValue: String, fieldName: String) throws {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            throw VerificationFailure(
                description: "\(fieldName) must use exact MAJOR.MINOR.PATCH SemVer"
            )
        }
        major = try parseStrictUnsignedInteger(String(components[0]), fieldName: fieldName)
        minor = try parseStrictUnsignedInteger(String(components[1]), fieldName: fieldName)
        patch = try parseStrictUnsignedInteger(String(components[2]), fieldName: fieldName)
    }

    static func < (lhs: StrictSemanticVersion, rhs: StrictSemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

func uniqueReleaseIdentities(in items: [ParsedAppcastItem]) throws {
    for item in items {
        _ = try parseStrictUnsignedInteger(
            item.version,
            fieldName: "Appcast build version \(item.version)"
        )
        _ = try StrictSemanticVersion(
            item.shortVersion,
            fieldName: "Appcast marketing version \(item.shortVersion)"
        )
    }
    let versions = Dictionary(grouping: items, by: \.version)
    guard versions.values.allSatisfy({ $0.count == 1 }) else {
        throw VerificationFailure(description: "The signed appcast contains duplicate or conflicting build versions")
    }
    let shortVersions = Dictionary(grouping: items, by: \.shortVersion)
    guard shortVersions.values.allSatisfy({ $0.count == 1 }) else {
        throw VerificationFailure(description: "The signed appcast contains duplicate or conflicting marketing versions")
    }
}

func validateReleaseProgression(
    expectedVersion: String,
    expectedBuild: String,
    existingItems: [ParsedAppcastItem]
) throws {
    try uniqueReleaseIdentities(in: existingItems)
    let nextBuild = try parseStrictUnsignedInteger(
        expectedBuild,
        fieldName: "Expected build version \(expectedBuild)"
    )
    let nextVersion = try StrictSemanticVersion(
        expectedVersion,
        fieldName: "Expected marketing version \(expectedVersion)"
    )

    for item in existingItems {
        let existingBuild = try parseStrictUnsignedInteger(
            item.version,
            fieldName: "Appcast build version \(item.version)"
        )
        guard nextBuild > existingBuild else {
            throw VerificationFailure(
                description: "Expected build \(expectedBuild) must be newer than every signed appcast build"
            )
        }
        let existingVersion = try StrictSemanticVersion(
            item.shortVersion,
            fieldName: "Appcast marketing version \(item.shortVersion)"
        )
        guard nextVersion > existingVersion else {
            throw VerificationFailure(
                description: "Expected version \(expectedVersion) must be newer than every signed appcast version"
            )
        }
    }
}

func onlyNewItem(
    generatedItems: [ParsedAppcastItem],
    baseItems: [ParsedAppcastItem]
) throws -> ParsedAppcastItem {
    try uniqueReleaseIdentities(in: baseItems)
    try uniqueReleaseIdentities(in: generatedItems)

    var remaining = generatedItems
    for baseItem in baseItems {
        guard let matchingIndex = remaining.firstIndex(of: baseItem) else {
            throw VerificationFailure(description: "The generated appcast changed or removed an item from the verified base feed")
        }
        remaining.remove(at: matchingIndex)
    }
    guard remaining.count == 1, generatedItems.count == baseItems.count + 1 else {
        throw VerificationFailure(description: "The generated appcast must add exactly one release item to the verified base feed")
    }
    return remaining[0]
}

func expectSelfTestFailure(
    _ name: String,
    _ operation: () throws -> Void
) throws {
    var failed = false
    do {
        try operation()
    } catch {
        failed = true
    }
    guard failed else {
        throw VerificationFailure(description: "Self-test unexpectedly accepted \(name)")
    }
}

func appcastFixture(items: String, extraNamespaces: String = "") -> Data {
    Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="\(sparkleNamespaceURI)" \(extraNamespaces)>
      <channel>\(items)</channel>
    </rss>
    """.utf8)
}

func itemFixture(
    version: String,
    shortVersion: String,
    filename: String,
    additionalContent: String = "",
    enclosureAttributes: String = ""
) -> String {
    """
    <item>
      <sparkle:version>\(version)</sparkle:version>
      <sparkle:shortVersionString>\(shortVersion)</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      \(additionalContent)
      <enclosure url="https://github.com/etherman-os/vidindir/releases/download/v\(shortVersion)/\(filename)"
                 length="12" type="application/octet-stream"
                 sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
                 \(enclosureAttributes) />
    </item>
    """
}

func runSelfTests() throws {
    let baseItemXML = itemFixture(version: "1", shortVersion: "1.0.0", filename: "one.zip")
    let expectedItemXML = itemFixture(version: "2", shortVersion: "2.0.0", filename: "two.zip")
    let baseItems = try parseAppcastItems(from: appcastFixture(items: baseItemXML))
    let generatedItems = try parseAppcastItems(
        from: appcastFixture(items: baseItemXML + expectedItemXML)
    )
    let newItem = try onlyNewItem(generatedItems: generatedItems, baseItems: baseItems)
    guard newItem.version == "2", newItem.shortVersion == "2.0.0" else {
        throw VerificationFailure(description: "Self-test did not select the only new item")
    }
    try validateReleaseProgression(
        expectedVersion: "2.0.0",
        expectedBuild: "2",
        existingItems: baseItems
    )

    let aliasedBaseData = Data(
        String(decoding: appcastFixture(items: baseItemXML), as: UTF8.self)
            .replacingOccurrences(of: "xmlns:sparkle", with: "xmlns:s")
            .replacingOccurrences(of: "sparkle:", with: "s:")
            .utf8
    )
    let aliasedBaseItems = try parseAppcastItems(from: aliasedBaseData)
    try expectSelfTestFailure("a marketing-version rollback hidden behind a namespace alias") {
        try validateReleaseProgression(
            expectedVersion: "1.0.0",
            expectedBuild: "2",
            existingItems: aliasedBaseItems
        )
    }
    try expectSelfTestFailure("a build-version rollback") {
        try validateReleaseProgression(
            expectedVersion: "2.0.0",
            expectedBuild: "1",
            existingItems: baseItems
        )
    }
    try expectSelfTestFailure("a noncanonical build version") {
        let malformedItems = try parseAppcastItems(from: appcastFixture(
            items: itemFixture(version: "01", shortVersion: "1.0.0", filename: "one.zip")
        ))
        try validateReleaseProgression(
            expectedVersion: "2.0.0",
            expectedBuild: "2",
            existingItems: malformedItems
        )
    }
    try expectSelfTestFailure("a non-SemVer marketing version") {
        let malformedItems = try parseAppcastItems(from: appcastFixture(
            items: itemFixture(version: "1", shortVersion: "1.0", filename: "one.zip")
        ))
        try validateReleaseProgression(
            expectedVersion: "2.0.0",
            expectedBuild: "2",
            existingItems: malformedItems
        )
    }

    try expectSelfTestFailure("a foreign-namespaced version") {
        _ = try parseAppcastItems(from: appcastFixture(
            items: itemFixture(
                version: "1",
                shortVersion: "1.0.0",
                filename: "one.zip",
                additionalContent: "<evil:version>99</evil:version>"
            ),
            extraNamespaces: "xmlns:evil=\"https://example.invalid/evil\""
        ))
    }
    try expectSelfTestFailure("a foreign-namespaced item") {
        let foreignItem = baseItemXML
            .replacingOccurrences(of: "<item>", with: "<evil:item>")
            .replacingOccurrences(of: "</item>", with: "</evil:item>")
        _ = try parseAppcastItems(from: appcastFixture(
            items: foreignItem,
            extraNamespaces: "xmlns:evil=\"https://example.invalid/evil\""
        ))
    }
    try expectSelfTestFailure("a nested version decoy") {
        let nested = baseItemXML.replacingOccurrences(
            of: "<sparkle:version>1</sparkle:version>",
            with: "<wrapper><sparkle:version>1</sparkle:version></wrapper>"
        )
        _ = try parseAppcastItems(from: appcastFixture(items: nested))
    }
    try expectSelfTestFailure("a nested enclosure decoy") {
        let nested = """
        <item>
          <sparkle:version>1</sparkle:version>
          <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
          <wrapper>
            <enclosure url="https://github.com/etherman-os/vidindir/releases/download/v1.0.0/one.zip"
                       length="12" type="application/octet-stream"
                       sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" />
          </wrapper>
        </item>
        """
        _ = try parseAppcastItems(from: appcastFixture(items: nested))
    }
    try expectSelfTestFailure("an enclosure version override") {
        _ = try parseAppcastItems(from: appcastFixture(items: itemFixture(
            version: "1",
            shortVersion: "1.0.0",
            filename: "one.zip",
            enclosureAttributes: "sparkle:version=\"999\""
        )))
    }
    try expectSelfTestFailure("duplicate selection fields") {
        _ = try parseAppcastItems(from: appcastFixture(items: itemFixture(
            version: "1",
            shortVersion: "1.0.0",
            filename: "one.zip",
            additionalContent: "<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"
        )))
    }
    try expectSelfTestFailure("changed critical-update attributes") {
        let criticalBaseXML = itemFixture(
            version: "1",
            shortVersion: "1.0.0",
            filename: "one.zip",
            additionalContent: "<sparkle:criticalUpdate sparkle:version=\"1\" />"
        )
        let changedCriticalXML = itemFixture(
            version: "1",
            shortVersion: "1.0.0",
            filename: "one.zip",
            additionalContent: "<sparkle:criticalUpdate sparkle:version=\"99\" />"
        )
        let criticalBaseItems = try parseAppcastItems(
            from: appcastFixture(items: criticalBaseXML)
        )
        let changedItems = try parseAppcastItems(
            from: appcastFixture(items: changedCriticalXML + expectedItemXML)
        )
        _ = try onlyNewItem(generatedItems: changedItems, baseItems: criticalBaseItems)
    }
    try expectSelfTestFailure("changed selection-child order") {
        let orderedBaseXML = itemFixture(
            version: "1",
            shortVersion: "1.0.0",
            filename: "one.zip",
            additionalContent: "<sparkle:tags><sparkle:criticalUpdate/><sparkle:other/></sparkle:tags>"
        )
        let reorderedBaseXML = itemFixture(
            version: "1",
            shortVersion: "1.0.0",
            filename: "one.zip",
            additionalContent: "<sparkle:tags><sparkle:other/><sparkle:criticalUpdate/></sparkle:tags>"
        )
        let orderedBaseItems = try parseAppcastItems(
            from: appcastFixture(items: orderedBaseXML)
        )
        let reorderedItems = try parseAppcastItems(
            from: appcastFixture(items: reorderedBaseXML + expectedItemXML)
        )
        _ = try onlyNewItem(generatedItems: reorderedItems, baseItems: orderedBaseItems)
    }
    try expectSelfTestFailure("duplicate build versions") {
        let conflict = itemFixture(version: "2", shortVersion: "2.1.0", filename: "other.zip")
        let items = try parseAppcastItems(
            from: appcastFixture(items: baseItemXML + expectedItemXML + conflict)
        )
        try uniqueReleaseIdentities(in: items)
    }
    try expectSelfTestFailure("an unexpected higher release") {
        let unexpected = itemFixture(version: "3", shortVersion: "3.0.0", filename: "three.zip")
        let items = try parseAppcastItems(
            from: appcastFixture(items: baseItemXML + expectedItemXML + unexpected)
        )
        _ = try onlyNewItem(generatedItems: items, baseItems: baseItems)
    }
    try expectSelfTestFailure("a changed base item") {
        let changedBase = itemFixture(version: "1", shortVersion: "1.0.0", filename: "changed.zip")
        let items = try parseAppcastItems(
            from: appcastFixture(items: changedBase + expectedItemXML)
        )
        _ = try onlyNewItem(generatedItems: items, baseItems: baseItems)
    }
    try expectSelfTestFailure("duplicate CLI flags") {
        _ = try Arguments(["--feed", "a", "--feed", "b", "--plist", "p"])
    }
    try expectSelfTestFailure("an unknown CLI flag") {
        _ = try Arguments(["--feed", "a", "--plist", "p", "--unknown", "x"])
    }
    _ = try Arguments([
        "--feed", "a", "--plist", "p",
        "--expected-version", "2.0.0", "--expected-build", "2",
    ])
    try expectSelfTestFailure("artifact arguments without an expected release") {
        _ = try Arguments([
            "--feed", "a", "--plist", "p",
            "--base-feed", "b", "--archive", "z", "--expected-download-url", "https://example.invalid/z",
        ])
    }
    try expectSelfTestFailure("duplicate signature-trailer fields") {
        _ = try exactCaptures(
            #"\A<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]+={0,2})\nlength: ([0-9]+)\n-->\s*\z"#,
            in: "<!-- sparkle-signatures:\nedSignature: AAAA\nedSignature: BBBB\nlength: 1\n-->",
            count: 2
        )
    }
}

do {
    let rawArguments = Array(CommandLine.arguments.dropFirst())
    if rawArguments == ["--self-test"] {
        try runSelfTests()
        print("Sparkle verifier self-tests passed.")
        exit(0)
    }
    let arguments = try Arguments(rawArguments)
    let feedURL = URL(fileURLWithPath: arguments.feedPath)
    let plistURL = URL(fileURLWithPath: arguments.plistPath)

    guard
        let plistObject = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistURL),
            options: [],
            format: nil
        ) as? [String: Any],
        let publicKeyBase64 = plistObject["SUPublicEDKey"] as? String,
        let publicKeyData = Data(base64Encoded: publicKeyBase64),
        publicKeyData.count == 32
    else {
        throw VerificationFailure(description: "Info.plist does not contain a valid 32-byte SUPublicEDKey")
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let generatedFeed = try verifyFeed(at: feedURL, publicKey: publicKey)

    if
        let baseFeedPath = arguments.baseFeedPath,
        let archivePath = arguments.archivePath,
        let expectedVersion = arguments.expectedVersion,
        let expectedBuild = arguments.expectedBuild,
        let expectedDownloadURL = arguments.expectedDownloadURL
    {
        let baseFeed = try verifyFeed(
            at: URL(fileURLWithPath: baseFeedPath),
            publicKey: publicKey
        )
        try validateReleaseProgression(
            expectedVersion: expectedVersion,
            expectedBuild: expectedBuild,
            existingItems: baseFeed.items
        )
        let item = try onlyNewItem(
            generatedItems: generatedFeed.items,
            baseItems: baseFeed.items
        )
        guard item.version == expectedBuild,
              item.shortVersion == expectedVersion else {
            throw VerificationFailure(
                description: "The only new appcast item is not version \(expectedVersion) build \(expectedBuild)"
            )
        }
        guard
            let archiveSignatureBase64 = item.enclosure.value(
                namespaceURI: sparkleNamespaceURI,
                localName: "edSignature"
            ),
            let declaredArchiveLength = item.enclosure.value(localName: "length"),
            let enclosureURLText = item.enclosure.value(localName: "url")
        else {
            throw VerificationFailure(description: "The selected enclosure is missing a signed-feed field")
        }

        let archiveURL = URL(fileURLWithPath: archivePath)
        let archiveData = try Data(contentsOf: archiveURL)
        guard declaredArchiveLength == String(archiveData.count) else {
            throw VerificationFailure(description: "The appcast archive length does not match the generated archive")
        }
        guard enclosureURLText == expectedDownloadURL,
              let enclosureURL = URL(string: enclosureURLText),
              enclosureURL.scheme == "https",
              enclosureURL.host == "github.com",
              enclosureURL.lastPathComponent == archiveURL.lastPathComponent else {
            throw VerificationFailure(description: "The appcast enclosure URL does not match the expected GitHub release asset URL")
        }
        guard
            let archiveSignature = Data(base64Encoded: archiveSignatureBase64),
            archiveSignature.count == 64,
            publicKey.isValidSignature(archiveSignature, for: archiveData)
        else {
            throw VerificationFailure(description: "The update archive signature does not match the app's SUPublicEDKey")
        }
    } else if
        let expectedVersion = arguments.expectedVersion,
        let expectedBuild = arguments.expectedBuild
    {
        try validateReleaseProgression(
            expectedVersion: expectedVersion,
            expectedBuild: expectedBuild,
            existingItems: generatedFeed.items
        )
    }

    print("Sparkle feed and update signatures are valid for the app's public key.")
} catch {
    fputs("Sparkle verification failed: \(error)\n", stderr)
    exit(1)
}
