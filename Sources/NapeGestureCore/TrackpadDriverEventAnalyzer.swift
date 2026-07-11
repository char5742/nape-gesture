import Foundation

public enum TrackpadDriverEventAnalyzerIssueCode: String, Codable, Equatable, Sendable {
    case emptyFile = "empty_file"
    case invalidUTF8 = "invalid_utf8"
    case missingFinalLineFeed = "missing_final_line_feed"
    case emptyLine = "empty_line"
    case oneObjectPerLineViolation = "one_object_per_line_violation"
    case malformedJSON = "malformed_json"
    case truncatedJSON = "truncated_json"
    case duplicateJSONKey = "duplicate_json_key"
    case integerOutOfRange = "integer_out_of_range"
    case nestingTooDeep = "nesting_too_deep"
    case missingRequiredKey = "missing_required_key"
    case invalidFieldType = "invalid_field_type"
    case unsupportedSchemaVersion = "unsupported_schema_version"
    case metadataContractMismatch = "metadata_contract_mismatch"
    case metadataMismatch = "metadata_mismatch"
    case captureIndexMismatch = "capture_index_mismatch"
    case timestampOutOfOrder = "timestamp_out_of_order"
    case rawFieldScanUpperBoundMismatch = "raw_field_scan_upper_bound_mismatch"
    case rawFieldCountMismatch = "raw_field_count_mismatch"
    case rawFieldOrderMismatch = "raw_field_order_mismatch"
    case rawFieldDuplicate = "raw_field_duplicate"
    case rawFieldMissing = "raw_field_missing"
    case rawFieldNumberOutOfRange = "raw_field_number_out_of_range"
    case doubleBitPatternMismatch = "double_bit_pattern_mismatch"
    case invalidBase64 = "invalid_base64"
    case typedDecodeFailure = "typed_decode_failure"
}

public struct TrackpadDriverEventAnalyzerIssue: Codable, Equatable, Sendable {
    public var code: TrackpadDriverEventAnalyzerIssueCode
    public var line: Int?
    public var captureIndex: UInt64?
    public var message: String

    public init(
        code: TrackpadDriverEventAnalyzerIssueCode,
        line: Int?,
        captureIndex: UInt64?,
        message: String
    ) {
        self.code = code
        self.line = line
        self.captureIndex = captureIndex
        self.message = message
    }
}

public struct TrackpadDriverEventAnalyzerReport: Codable, Equatable, Sendable {
    public var passed: Bool
    public var documents: [TrackpadDriverEventDocument]
    public var issues: [TrackpadDriverEventAnalyzerIssue]

    public init(
        documents: [TrackpadDriverEventDocument],
        issues: [TrackpadDriverEventAnalyzerIssue]
    ) {
        self.documents = documents
        self.issues = issues
        passed = issues.isEmpty
    }

    public var isValid: Bool {
        passed
    }
}

public struct TrackpadDriverEventAnalyzer: Sendable {
    public init() {}

    public static func analyze(_ data: Data) -> TrackpadDriverEventAnalyzerReport {
        TrackpadDriverEventAnalyzer().analyze(data: data)
    }

    public func analyze(data: Data) -> TrackpadDriverEventAnalyzerReport {
        var documents: [TrackpadDriverEventDocument] = []
        var issues: [TrackpadDriverEventAnalyzerIssue] = []

        guard !data.isEmpty else {
            issues.append(issue(.emptyFile, message: "JSON Linesファイルが空です。"))
            return TrackpadDriverEventAnalyzerReport(documents: documents, issues: issues)
        }

        let hasFinalLineFeed = data.last == 0x0A
        var lineSlices = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if hasFinalLineFeed {
            lineSlices.removeLast()
        } else {
            issues.append(
                issue(
                    .missingFinalLineFeed,
                    line: max(lineSlices.count, 1),
                    message: "JSON Linesファイルの最終行がLFで終端されていません。"
                )
            )
        }

        var baselineMetadata: LosslessJSONObject?
        var previousTimestamp: UInt64?
        var previousTimestampLine: Int?

        for (lineOffset, lineSlice) in lineSlices.enumerated() {
            let line = lineOffset + 1
            let rawLineData = Data(lineSlice)
            if rawLineData.allSatisfy(Self.isJSONWhitespace) {
                issues.append(issue(.emptyLine, line: line, message: "空行は許可されていません。"))
                continue
            }
            guard String(data: rawLineData, encoding: .utf8) != nil else {
                issues.append(
                    issue(
                        .invalidUTF8,
                        line: line,
                        message: "行に不正なUTF-8 byte sequenceがあります。"
                    )
                )
                continue
            }

            let value: LosslessJSONValue
            do {
                var parser = LosslessJSONParser(data: rawLineData)
                value = try parser.parse()
            } catch let parseError as LosslessJSONParser.ParseError {
                issues.append(parserIssue(parseError, line: line))
                continue
            } catch {
                issues.append(
                    issue(
                        .malformedJSON,
                        line: line,
                        message: "JSONを解析できませんでした: \(error.localizedDescription)"
                    )
                )
                continue
            }

            guard case let .object(object) = value else {
                issues.append(
                    issue(
                        .oneObjectPerLineViolation,
                        line: line,
                        message: "各行のtop-level JSON値は1個のobjectである必要があります。"
                    )
                )
                continue
            }

            let captureIndex = object["captureIndex"]?.uint64Value
            let values = validateCurrentSchema(
                object,
                line: line,
                captureIndex: captureIndex,
                expectedCaptureIndex: UInt64(lineOffset),
                issues: &issues
            )

            if let metadata = values.metadata {
                if let baselineMetadata {
                    if !baselineMetadata.isSemanticallyEqual(to: metadata) {
                        issues.append(
                            issue(
                                .metadataMismatch,
                                line: line,
                                captureIndex: captureIndex,
                                message: "metadataが先頭eventのmetadataと一致しません。"
                            )
                        )
                    }
                } else {
                    baselineMetadata = metadata
                }
            }

            if let timestamp = values.timestamp {
                if let previousTimestamp, timestamp < previousTimestamp {
                    let previousLineText = previousTimestampLine.map(String.init) ?? "不明"
                    issues.append(
                        issue(
                            .timestampOutOfOrder,
                            line: line,
                            captureIndex: captureIndex,
                            message: "timestampが非減少順ではありません。直前line=\(previousLineText)"
                        )
                    )
                }
                previousTimestamp = timestamp
                previousTimestampLine = line
            }

            do {
                let eventLog = try JSONDecoder().decode(TrackpadDriverEventLog.self, from: rawLineData)
                let unknownTopLevelFields = object.filteringKeys {
                    !TrackpadDriverEventDocument.currentTopLevelFieldNames.contains($0)
                }
                let unknownMetadataFields = values.metadata?.filteringKeys {
                    !TrackpadDriverEventDocument.currentMetadataFieldNames.contains($0)
                } ?? LosslessJSONObject()
                documents.append(
                    TrackpadDriverEventDocument(
                        line: line,
                        rawLineData: rawLineData,
                        eventLog: eventLog,
                        rawTopLevelObject: object,
                        rawFields: values.rawFields ?? [],
                        unknownTopLevelFields: unknownTopLevelFields,
                        unknownMetadataFields: unknownMetadataFields
                    )
                )
            } catch {
                issues.append(
                    issue(
                        .typedDecodeFailure,
                        line: line,
                        captureIndex: captureIndex,
                        message: "TrackpadDriverEventLogへのdecodeに失敗しました: \(error.localizedDescription)"
                    )
                )
            }
        }

        return TrackpadDriverEventAnalyzerReport(documents: documents, issues: issues)
    }
}

private extension TrackpadDriverEventAnalyzer {
    struct ValidatedLineValues {
        var metadata: LosslessJSONObject?
        var timestamp: UInt64?
        var rawFields: [LosslessJSONValue]?
    }

    static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D
    }

    func parserIssue(
        _ parseError: LosslessJSONParser.ParseError,
        line: Int
    ) -> TrackpadDriverEventAnalyzerIssue {
        let code: TrackpadDriverEventAnalyzerIssueCode
        switch parseError.kind {
        case .unexpectedEnd:
            code = .truncatedJSON
        case .trailingContent:
            code = .oneObjectPerLineViolation
        case .duplicateObjectKey:
            code = .duplicateJSONKey
        case .integerOutOfRange:
            code = .integerOutOfRange
        case .nestingLimitExceeded:
            code = .nestingTooDeep
        case .invalidSyntax:
            code = .malformedJSON
        }
        return issue(
            code,
            line: line,
            message: "byteOffset=\(parseError.byteOffset): \(parseError.detail)"
        )
    }

    func validateCurrentSchema(
        _ object: LosslessJSONObject,
        line: Int,
        captureIndex: UInt64?,
        expectedCaptureIndex: UInt64,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) -> ValidatedLineValues {
        let schemaVersion = requiredInt64(
            "schemaVersion",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        if let schemaVersion, schemaVersion != Int64(TrackpadDriverEventLog.currentSchemaVersion) {
            issues.append(
                issue(
                    .unsupportedSchemaVersion,
                    line: line,
                    captureIndex: captureIndex,
                    message: "schemaVersion=\(schemaVersion)は現行version \(TrackpadDriverEventLog.currentSchemaVersion)ではありません。"
                )
            )
        }

        let metadata = requiredObject(
            "metadata",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        if let metadata {
            validateMetadata(metadata, line: line, captureIndex: captureIndex, issues: &issues)
        }

        let validatedCaptureIndex = requiredUInt64(
            "captureIndex",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        if let validatedCaptureIndex, validatedCaptureIndex != expectedCaptureIndex {
            issues.append(
                issue(
                    .captureIndexMismatch,
                    line: line,
                    captureIndex: validatedCaptureIndex,
                    message: "captureIndexは0から連続する必要があります。expected=\(expectedCaptureIndex), actual=\(validatedCaptureIndex)"
                )
            )
        }

        let timestamp = requiredUInt64(
            "timestamp",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        _ = requiredInt(
            "typeRaw",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        _ = requiredString(
            "typeName",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        _ = optionalNullableInt64(
            "eventSubtype",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        _ = requiredUInt64(
            "flags",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )

        for key in [
            "scrollDeltaX",
            "scrollDeltaY",
            "scrollDeltaZ",
            "scrollPhase",
            "momentumPhase",
            "isContinuous",
            "sourceUserData"
        ] {
            _ = requiredInt64(
                key,
                in: object,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
        }

        for (valueKey, bitPatternKey) in [
            ("scrollFixedDeltaX", "scrollFixedDeltaXBitPattern"),
            ("scrollFixedDeltaY", "scrollFixedDeltaYBitPattern"),
            ("scrollFixedDeltaZ", "scrollFixedDeltaZBitPattern"),
            ("scrollPointDeltaX", "scrollPointDeltaXBitPattern"),
            ("scrollPointDeltaY", "scrollPointDeltaYBitPattern"),
            ("scrollPointDeltaZ", "scrollPointDeltaZBitPattern")
        ] {
            validateDoublePair(
                valueKey: valueKey,
                bitPatternKey: bitPatternKey,
                in: object,
                path: valueKey,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
        }

        let rawFieldScanUpperBound = requiredInt(
            "rawFieldScanUpperBound",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        if let rawFieldScanUpperBound,
           rawFieldScanUpperBound != TrackpadDriverEventLog.maximumRawFieldNumber
        {
            issues.append(
                issue(
                    .rawFieldScanUpperBoundMismatch,
                    line: line,
                    captureIndex: captureIndex,
                    message: "rawFieldScanUpperBoundは\(TrackpadDriverEventLog.maximumRawFieldNumber)である必要があります。actual=\(rawFieldScanUpperBound)"
                )
            )
        }

        let rawFields = requiredArray(
            "rawFields",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        if let rawFields {
            validateRawFields(rawFields, line: line, captureIndex: captureIndex, issues: &issues)
        }

        if let serializedEventBase64 = requiredString(
            "serializedEventBase64",
            in: object,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        ) {
            validateBase64(
                serializedEventBase64,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
        }

        return ValidatedLineValues(metadata: metadata, timestamp: timestamp, rawFields: rawFields)
    }

    func validateMetadata(
        _ metadata: LosslessJSONObject,
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) {
        let loggerName = requiredString(
            "loggerName",
            in: metadata,
            pathPrefix: "metadata",
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        let loggerVersion = requiredInt(
            "loggerVersion",
            in: metadata,
            pathPrefix: "metadata",
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        _ = requiredString(
            "osVersion",
            in: metadata,
            pathPrefix: "metadata",
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        _ = requiredString(
            "osBuild",
            in: metadata,
            pathPrefix: "metadata",
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        let canonicalEventRepresentation = requiredString(
            "canonicalEventRepresentation",
            in: metadata,
            pathPrefix: "metadata",
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )
        let rawFieldScanPolicy = requiredString(
            "rawFieldScanPolicy",
            in: metadata,
            pathPrefix: "metadata",
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        )

        for optionalKey in ["scenarioID", "deviceLabel", "repoHeadSHA"] {
            if let value = metadata[optionalKey], value.stringValue == nil {
                issues.append(
                    issue(
                        .invalidFieldType,
                        line: line,
                        captureIndex: captureIndex,
                        message: "metadata.\(optionalKey)は存在する場合Stringである必要があります。"
                    )
                )
            }
        }

        if let loggerName, loggerName != TrackpadDriverEventLogMetadata.defaultLoggerName {
            appendMetadataContractMismatch(
                "metadata.loggerName",
                expected: TrackpadDriverEventLogMetadata.defaultLoggerName,
                actual: loggerName,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
        }
        if let loggerVersion, loggerVersion != TrackpadDriverEventLogMetadata.currentLoggerVersion {
            appendMetadataContractMismatch(
                "metadata.loggerVersion",
                expected: String(TrackpadDriverEventLogMetadata.currentLoggerVersion),
                actual: String(loggerVersion),
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
        }
        if let canonicalEventRepresentation,
           canonicalEventRepresentation != TrackpadDriverEventLogMetadata.defaultCanonicalEventRepresentation
        {
            appendMetadataContractMismatch(
                "metadata.canonicalEventRepresentation",
                expected: TrackpadDriverEventLogMetadata.defaultCanonicalEventRepresentation,
                actual: canonicalEventRepresentation,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
        }
        if let rawFieldScanPolicy,
           rawFieldScanPolicy != TrackpadDriverEventLogMetadata.allRawFieldValuesPolicy
        {
            appendMetadataContractMismatch(
                "metadata.rawFieldScanPolicy",
                expected: TrackpadDriverEventLogMetadata.allRawFieldValuesPolicy,
                actual: rawFieldScanPolicy,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
        }
    }

    func appendMetadataContractMismatch(
        _ path: String,
        expected: String,
        actual: String,
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) {
        issues.append(
            issue(
                .metadataContractMismatch,
                line: line,
                captureIndex: captureIndex,
                message: "\(path)が現行contractと一致しません。expected=\(expected), actual=\(actual)"
            )
        )
    }

    func validateRawFields(
        _ rawFields: [LosslessJSONValue],
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) {
        let expectedCount = TrackpadDriverEventLog.maximumRawFieldNumber
            - TrackpadDriverEventLog.rawFieldScanLowerBound
            + 1
        if rawFields.count != expectedCount {
            issues.append(
                issue(
                    .rawFieldCountMismatch,
                    line: line,
                    captureIndex: captureIndex,
                    message: "rawFieldsは0...255の\(expectedCount)件である必要があります。actual=\(rawFields.count)"
                )
            )
        }

        var occurrences: [Int: Int] = [:]
        var firstOrderMismatch: (position: Int, fieldNumber: Int)?
        for (position, rawFieldValue) in rawFields.enumerated() {
            guard case let .object(rawField) = rawFieldValue else {
                issues.append(
                    issue(
                        .invalidFieldType,
                        line: line,
                        captureIndex: captureIndex,
                        message: "rawFields[\(position)]はobjectである必要があります。"
                    )
                )
                continue
            }
            let pathPrefix = "rawFields[\(position)]"
            let fieldNumber = requiredInt(
                "fieldNumber",
                in: rawField,
                pathPrefix: pathPrefix,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
            if let fieldNumber {
                if !(TrackpadDriverEventLog.rawFieldScanLowerBound...TrackpadDriverEventLog.maximumRawFieldNumber)
                    .contains(fieldNumber)
                {
                    issues.append(
                        issue(
                            .rawFieldNumberOutOfRange,
                            line: line,
                            captureIndex: captureIndex,
                            message: "\(pathPrefix).fieldNumber=\(fieldNumber)は0...255の範囲外です。"
                        )
                    )
                } else {
                    occurrences[fieldNumber, default: 0] += 1
                }
                if firstOrderMismatch == nil, fieldNumber != position {
                    firstOrderMismatch = (position, fieldNumber)
                }
            }
            _ = requiredInt64(
                "integerValue",
                in: rawField,
                pathPrefix: pathPrefix,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
            validateDoublePair(
                valueKey: "doubleValue",
                bitPatternKey: "doubleBitPattern",
                in: rawField,
                path: "\(pathPrefix).doubleValue",
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
        }

        if let firstOrderMismatch {
            issues.append(
                issue(
                    .rawFieldOrderMismatch,
                    line: line,
                    captureIndex: captureIndex,
                    message: "rawFieldsはfieldNumber昇順0...255である必要があります。position=\(firstOrderMismatch.position), actual=\(firstOrderMismatch.fieldNumber)"
                )
            )
        }
        let duplicates = occurrences
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        if !duplicates.isEmpty {
            issues.append(
                issue(
                    .rawFieldDuplicate,
                    line: line,
                    captureIndex: captureIndex,
                    message: "rawFieldsに重複fieldNumberがあります: \(duplicates.map(String.init).joined(separator: ","))"
                )
            )
        }
        let missing = (TrackpadDriverEventLog.rawFieldScanLowerBound...TrackpadDriverEventLog.maximumRawFieldNumber)
            .filter { occurrences[$0] == nil }
        if !missing.isEmpty {
            issues.append(
                issue(
                    .rawFieldMissing,
                    line: line,
                    captureIndex: captureIndex,
                    message: "rawFieldsに欠落fieldNumberがあります: \(missing.map(String.init).joined(separator: ","))"
                )
            )
        }
    }

    func validateDoublePair(
        valueKey: String,
        bitPatternKey: String,
        in object: LosslessJSONObject,
        path: String,
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) {
        guard let bitPattern = requiredUInt64(
            bitPatternKey,
            in: object,
            pathPrefix: path.split(separator: ".").dropLast().joined(separator: "."),
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        ) else {
            return
        }

        guard let rawValue = object[valueKey] else {
            if Double(bitPattern: bitPattern).isFinite {
                issues.append(
                    issue(
                        .doubleBitPatternMismatch,
                        line: line,
                        captureIndex: captureIndex,
                        message: "\(path)が欠落していますがdoubleBitPatternは有限値を表します。"
                    )
                )
            }
            return
        }
        guard let doubleValue = rawValue.finiteDoubleValue else {
            issues.append(
                issue(
                    .invalidFieldType,
                    line: line,
                    captureIndex: captureIndex,
                    message: "\(path)は有限のJSON numberである必要があります。"
                )
            )
            return
        }
        if doubleValue.bitPattern != bitPattern {
            issues.append(
                issue(
                    .doubleBitPatternMismatch,
                    line: line,
                    captureIndex: captureIndex,
                    message: "\(path)と対応するdoubleBitPatternが一致しません。expected=\(doubleValue.bitPattern), actual=\(bitPattern)"
                )
            )
        }
    }

    func validateBase64(
        _ value: String,
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) {
        guard !value.isEmpty,
              let decoded = Data(base64Encoded: value),
              decoded.base64EncodedString() == value
        else {
            issues.append(
                issue(
                    .invalidBase64,
                    line: line,
                    captureIndex: captureIndex,
                    message: "serializedEventBase64は空でないcanonical Base64である必要があります。"
                )
            )
            return
        }
    }

    func requiredValue(
        _ key: String,
        in object: LosslessJSONObject,
        pathPrefix: String = "",
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) -> LosslessJSONValue? {
        guard let value = object[key] else {
            let path = pathPrefix.isEmpty ? key : "\(pathPrefix).\(key)"
            issues.append(
                issue(
                    .missingRequiredKey,
                    line: line,
                    captureIndex: captureIndex,
                    message: "現行schemaの必須key \(path) がありません。"
                )
            )
            return nil
        }
        return value
    }

    func requiredObject(
        _ key: String,
        in object: LosslessJSONObject,
        pathPrefix: String = "",
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) -> LosslessJSONObject? {
        guard let value = requiredValue(
            key,
            in: object,
            pathPrefix: pathPrefix,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        ) else {
            return nil
        }
        guard case let .object(result) = value else {
            appendInvalidType(
                key,
                expected: "object",
                pathPrefix: pathPrefix,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
            return nil
        }
        return result
    }

    func requiredArray(
        _ key: String,
        in object: LosslessJSONObject,
        pathPrefix: String = "",
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) -> [LosslessJSONValue]? {
        guard let value = requiredValue(
            key,
            in: object,
            pathPrefix: pathPrefix,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        ) else {
            return nil
        }
        guard case let .array(result) = value else {
            appendInvalidType(
                key,
                expected: "array",
                pathPrefix: pathPrefix,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
            return nil
        }
        return result
    }

    func requiredString(
        _ key: String,
        in object: LosslessJSONObject,
        pathPrefix: String = "",
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) -> String? {
        guard let value = requiredValue(
            key,
            in: object,
            pathPrefix: pathPrefix,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        ) else {
            return nil
        }
        guard let result = value.stringValue else {
            appendInvalidType(
                key,
                expected: "String",
                pathPrefix: pathPrefix,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
            return nil
        }
        return result
    }

    func requiredInt64(
        _ key: String,
        in object: LosslessJSONObject,
        pathPrefix: String = "",
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) -> Int64? {
        guard let value = requiredValue(
            key,
            in: object,
            pathPrefix: pathPrefix,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        ) else {
            return nil
        }
        guard let result = value.int64Value else {
            appendInvalidType(
                key,
                expected: "Int64",
                pathPrefix: pathPrefix,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
            return nil
        }
        return result
    }

    func requiredUInt64(
        _ key: String,
        in object: LosslessJSONObject,
        pathPrefix: String = "",
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) -> UInt64? {
        guard let value = requiredValue(
            key,
            in: object,
            pathPrefix: pathPrefix,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        ) else {
            return nil
        }
        guard let result = value.uint64Value else {
            appendInvalidType(
                key,
                expected: "UInt64",
                pathPrefix: pathPrefix,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
            return nil
        }
        return result
    }

    func optionalNullableInt64(
        _ key: String,
        in object: LosslessJSONObject,
        pathPrefix: String = "",
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) -> Int64? {
        guard let value = object[key] else {
            return nil
        }
        if case .null = value {
            return nil
        }
        guard let result = value.int64Value else {
            appendInvalidType(
                key,
                expected: "Int64またはnull",
                pathPrefix: pathPrefix,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
            return nil
        }
        return result
    }

    func requiredInt(
        _ key: String,
        in object: LosslessJSONObject,
        pathPrefix: String = "",
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) -> Int? {
        guard let value = requiredInt64(
            key,
            in: object,
            pathPrefix: pathPrefix,
            line: line,
            captureIndex: captureIndex,
            issues: &issues
        ) else {
            return nil
        }
        guard let result = Int(exactly: value) else {
            appendInvalidType(
                key,
                expected: "Int",
                pathPrefix: pathPrefix,
                line: line,
                captureIndex: captureIndex,
                issues: &issues
            )
            return nil
        }
        return result
    }

    func appendInvalidType(
        _ key: String,
        expected: String,
        pathPrefix: String,
        line: Int,
        captureIndex: UInt64?,
        issues: inout [TrackpadDriverEventAnalyzerIssue]
    ) {
        let path = pathPrefix.isEmpty ? key : "\(pathPrefix).\(key)"
        issues.append(
            issue(
                .invalidFieldType,
                line: line,
                captureIndex: captureIndex,
                message: "\(path)は\(expected)である必要があります。"
            )
        )
    }

    func issue(
        _ code: TrackpadDriverEventAnalyzerIssueCode,
        line: Int? = nil,
        captureIndex: UInt64? = nil,
        message: String
    ) -> TrackpadDriverEventAnalyzerIssue {
        TrackpadDriverEventAnalyzerIssue(
            code: code,
            line: line,
            captureIndex: captureIndex,
            message: message
        )
    }
}
