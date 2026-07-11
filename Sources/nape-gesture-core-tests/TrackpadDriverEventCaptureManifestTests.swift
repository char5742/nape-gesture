import Foundation
import NapeGestureCore

private let manifestTestExecutableSHA256 = String(repeating: "b", count: 64)
private let manifestTestRepoHeadSHA = String(repeating: "a", count: 40)

private func manifestTestMetadata(
    scenarioID: String? = "space-right",
    deviceLabel: String? = "built-in-trackpad",
    repoHeadSHA: String? = manifestTestRepoHeadSHA
) -> TrackpadDriverEventLogMetadata {
    TrackpadDriverEventLogMetadata(
        osVersion: "26.0.0",
        osBuild: "25A123",
        scenarioID: scenarioID,
        deviceLabel: deviceLabel,
        repoHeadSHA: repoHeadSHA
    )
}

private func manifestTestLogData(
    timestamps: [UInt64] = [100, 120],
    metadata: TrackpadDriverEventLogMetadata = manifestTestMetadata()
) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = Data()
    for (index, timestamp) in timestamps.enumerated() {
        let record = TrackpadDriverEventLog(
            metadata: metadata,
            captureIndex: UInt64(index),
            timestamp: timestamp,
            typeRaw: 22,
            typeName: "scrollWheel",
            serializedEventBase64: "AA=="
        )
        data.append(try encoder.encode(record))
        data.append(0x0A)
    }
    return data
}

private func manifestTestManifest(
    evidenceKind: TrackpadDriverEventEvidenceKind = .physicalTrackpad,
    metadata: TrackpadDriverEventLogMetadata = manifestTestMetadata()
) throws -> (TrackpadDriverEventCaptureManifest, Data) {
    let logData = try manifestTestLogData(metadata: metadata)
    let summary = try TrackpadDriverEventCaptureManifest.summarize(logData: logData)
    let completedAt = Date(timeIntervalSince1970: 1_752_220_800.125)
    let manifest = TrackpadDriverEventCaptureManifest(
        evidenceKind: evidenceKind,
        logSummary: summary,
        loggerExecutableSHA256: manifestTestExecutableSHA256,
        captureStartedAt: completedAt.addingTimeInterval(-8),
        captureCompletedAt: completedAt
    )
    return (manifest, logData)
}

private func expectManifestValidationError(
    _ expected: TrackpadDriverEventCaptureManifestValidationError,
    manifest: TrackpadDriverEventCaptureManifest,
    _ message: String
) {
    do {
        try manifest.validate()
        expect(false, "\(message): validationが成功してしまった")
    } catch let error as TrackpadDriverEventCaptureManifestValidationError {
        expect(error == expected, "\(message): error=\(error)")
    } catch {
        expect(false, "\(message): 想定外error=\(error)")
    }
}

private func withManifestStoreTestDirectory(
    _ body: (URL) throws -> Void
) {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(
        "nape-gesture-manifest-store-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    do {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        defer {
            try? fileManager.removeItem(at: directoryURL)
        }
        try body(directoryURL)
    } catch {
        expect(false, "manifest store test directoryを利用できる: \(error)")
    }
}

private func manifestStoreTemporaryArtifacts(
    in directoryURL: URL,
    for destinationURL: URL
) throws -> [URL] {
    let prefix = ".\(destinationURL.lastPathComponent)."
    return try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil
    ).filter { url in
        url.lastPathComponent.hasPrefix(prefix) && url.lastPathComponent.hasSuffix(".tmp")
    }
}

private func testCaptureManifestStoreRemovesStaleSidecar() {
    withManifestStoreTestDirectory { directoryURL in
        let fileManager = FileManager.default
        let logURL = directoryURL.appendingPathComponent("capture.jsonl")
        let manifestURL = directoryURL.appendingPathComponent("capture.manifest.json")
        try Data("stale-manifest".utf8).write(to: manifestURL)

        let store = TrackpadDriverEventCaptureManifestStore()
        try store.prepareDestination(
            logPath: logURL.path,
            manifestPath: manifestURL.path
        )

        expect(
            !fileManager.fileExists(atPath: manifestURL.path),
            "capture開始前に古いmanifest sidecarを削除する"
        )
    }
}

private func testCaptureManifestStoreRemovesSymlinkWithoutTouchingTarget() {
    withManifestStoreTestDirectory { directoryURL in
        let fileManager = FileManager.default
        let logURL = directoryURL.appendingPathComponent("capture.jsonl")
        let targetURL = directoryURL.appendingPathComponent("protected-target.json")
        let manifestURL = directoryURL.appendingPathComponent("capture.manifest.json")
        let targetData = Data("target-must-remain".utf8)
        try targetData.write(to: targetURL)
        try fileManager.createSymbolicLink(
            atPath: manifestURL.path,
            withDestinationPath: targetURL.path
        )

        let store = TrackpadDriverEventCaptureManifestStore()
        try store.prepareDestination(
            logPath: logURL.path,
            manifestPath: manifestURL.path
        )

        expect(
            (try? fileManager.destinationOfSymbolicLink(atPath: manifestURL.path)) == nil,
            "旧sidecar symlink自体を削除する"
        )
        let storedTargetData = try Data(contentsOf: targetURL)
        expect(storedTargetData == targetData, "旧sidecar symlinkの参照先は削除しない")
    }
}

private func testCaptureManifestStoreRejectsSameAndSymlinkedLocations() {
    withManifestStoreTestDirectory { directoryURL in
        let fileManager = FileManager.default
        let store = TrackpadDriverEventCaptureManifestStore()
        let logURL = directoryURL.appendingPathComponent("capture.jsonl")

        do {
            try store.validateDistinctLocations(
                logPath: logURL.path,
                manifestPath: logURL.path
            )
            expect(false, "logとmanifestの同一路径を拒否する")
        } catch let error as TrackpadDriverEventCaptureManifestStoreError {
            guard case .pathConflict = error else {
                expect(false, "同一路径をpathConflictとして報告する: \(error)")
                return
            }
            expect(true, "logとmanifestの同一路径を拒否する")
        }

        let manifestSymlinkURL = directoryURL.appendingPathComponent("capture.manifest.json")
        try fileManager.createSymbolicLink(
            atPath: manifestSymlinkURL.path,
            withDestinationPath: logURL.path
        )
        do {
            try store.prepareDestination(
                logPath: logURL.path,
                manifestPath: manifestSymlinkURL.path
            )
            expect(false, "未作成logを指すsidecar symlinkとの競合を拒否する")
        } catch let error as TrackpadDriverEventCaptureManifestStoreError {
            guard case .pathConflict = error else {
                expect(false, "dangling symlink競合をpathConflictとして報告する: \(error)")
                return
            }
            expect(
                (try? fileManager.destinationOfSymbolicLink(atPath: manifestSymlinkURL.path)) != nil,
                "競合するsidecar symlinkを削除する前に拒否する"
            )
        }

        try fileManager.removeItem(at: manifestSymlinkURL)
        let realDirectoryURL = directoryURL.appendingPathComponent("real", isDirectory: true)
        let aliasDirectoryURL = directoryURL.appendingPathComponent("alias", isDirectory: true)
        try fileManager.createDirectory(
            at: realDirectoryURL,
            withIntermediateDirectories: false
        )
        try fileManager.createSymbolicLink(
            atPath: aliasDirectoryURL.path,
            withDestinationPath: realDirectoryURL.path
        )
        let realPath = realDirectoryURL.appendingPathComponent("same.json").path
        let aliasPath = aliasDirectoryURL.appendingPathComponent("same.json").path
        let pathsMatch = try store.pathsReferToSameLocation(realPath, aliasPath)
        expect(
            pathsMatch,
            "親directoryのsymlink aliasも同じlocationとして扱う"
        )
    }
}

private func testCaptureManifestStoreWritesFinalLFWithoutTemporaryArtifacts() {
    withManifestStoreTestDirectory { directoryURL in
        let manifestURL = directoryURL.appendingPathComponent("capture.manifest.json")
        let (manifest, _) = try manifestTestManifest()
        let store = TrackpadDriverEventCaptureManifestStore()

        try store.writeAtomically(manifest, toPath: manifestURL.path)

        let storedData = try Data(contentsOf: manifestURL)
        expect(storedData.last == 0x0A, "成功したmanifest fileをLFで終端する")
        let decoded = try JSONDecoder().decode(
            TrackpadDriverEventCaptureManifest.self,
            from: storedData
        )
        expect(decoded == manifest, "atomic write後もmanifest全fieldを保持する")
        let temporaryArtifacts = try manifestStoreTemporaryArtifacts(
            in: directoryURL,
            for: manifestURL
        )
        expect(
            temporaryArtifacts.isEmpty,
            "成功後にmanifest temporary fileを残さない"
        )
    }
}

private func testCaptureManifestStoreCleansTemporaryFileAfterRenameFailure() {
    withManifestStoreTestDirectory { directoryURL in
        let fileManager = FileManager.default
        let destinationURL = directoryURL.appendingPathComponent(
            "capture.manifest.json",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: false
        )
        let (manifest, _) = try manifestTestManifest()
        let store = TrackpadDriverEventCaptureManifestStore()

        do {
            try store.writeAtomically(manifest, toPath: destinationURL.path)
            expect(false, "directory destinationへのrename失敗を報告する")
        } catch let error as TrackpadDriverEventCaptureManifestStoreError {
            guard case let .renameFailed(path, errorCode) = error else {
                expect(false, "rename失敗を専用errorとして報告する: \(error)")
                return
            }
            expect(path == destinationURL.path, "rename失敗にdestination pathを含める")
            expect(errorCode != 0, "rename失敗にerrnoを含める")
        }

        var isDirectory: ObjCBool = false
        expect(
            fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory)
                && isDirectory.boolValue,
            "rename失敗時に既存directory destinationを変更しない"
        )
        let temporaryArtifacts = try manifestStoreTemporaryArtifacts(
            in: directoryURL,
            for: destinationURL
        )
        expect(
            temporaryArtifacts.isEmpty,
            "rename失敗後にmanifest temporary fileを残さない"
        )
    }
}

private func testCaptureManifestStoreReportsInvalidParentDirectoryStructurally() {
    withManifestStoreTestDirectory { directoryURL in
        let fileManager = FileManager.default
        let (manifest, _) = try manifestTestManifest()
        let store = TrackpadDriverEventCaptureManifestStore()
        let logURL = directoryURL.appendingPathComponent("capture.jsonl")
        let missingParentURL = directoryURL.appendingPathComponent("missing", isDirectory: true)
        let missingDestinationURL = missingParentURL.appendingPathComponent("manifest.json")

        do {
            try store.prepareDestination(
                logPath: logURL.path,
                manifestPath: missingDestinationURL.path
            )
            expect(false, "存在しないmanifest親directoryを拒否する")
        } catch let error as TrackpadDriverEventCaptureManifestStoreError {
            guard case let .parentDirectoryMissing(path) = error else {
                expect(false, "親directory不在を専用errorとして報告する: \(error)")
                return
            }
            expect(path == missingParentURL.path, "親directory不在errorにpathを含める")
        }
        expect(
            !fileManager.fileExists(atPath: missingParentURL.path),
            "manifest storeは存在しない親directoryを暗黙作成しない"
        )

        let invalidParentURL = directoryURL.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: invalidParentURL)
        let invalidDestinationURL = invalidParentURL.appendingPathComponent("manifest.json")
        do {
            try store.writeAtomically(manifest, toPath: invalidDestinationURL.path)
            expect(false, "directoryではないmanifest親pathを拒否する")
        } catch let error as TrackpadDriverEventCaptureManifestStoreError {
            guard case let .parentPathIsNotDirectory(path) = error else {
                expect(false, "不正な親pathを専用errorとして報告する: \(error)")
                return
            }
            expect(path == invalidParentURL.path, "不正な親path errorにpathを含める")
        }
    }
}

private func testCaptureManifestSHA256KnownVector() {
    let digest = TrackpadDriverEventCaptureManifest.sha256HexDigest(of: Data("abc".utf8))
    expect(
        digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "capture manifest SHA-256は既知ベクトルと一致する"
    )
}

private func testCaptureManifestSummarizesFinalLogBytes() {
    do {
        let data = try manifestTestLogData(timestamps: [101, 205, 377])
        let summary = try TrackpadDriverEventCaptureManifest.summarize(logData: data)
        expect(summary.logByteCount == UInt64(data.count), "final log bytesからbyte countを算出する")
        expect(summary.eventCount == 3, "final log bytesからevent countを算出する")
        expect(summary.firstEventTimestamp == 101, "最初のrecordからfirst timestampを算出する")
        expect(summary.lastEventTimestamp == 377, "最後のrecordからlast timestampを算出する")
        expect(
            summary.logSHA256 == TrackpadDriverEventCaptureManifest.sha256HexDigest(of: data),
            "final log bytesからlog SHA-256を算出する"
        )
        expect(summary.metadata == manifestTestMetadata(), "final log recordからmetadataを保持する")
    } catch {
        expect(false, "final log summaryを生成できる: \(error)")
    }
}

private func testCaptureManifestCodableRoundTripPreservesEveryField() {
    do {
        let (manifest, logData) = try manifestTestManifest(evidenceKind: .generatedProduct)
        try manifest.validate(logData: logData)
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(
            TrackpadDriverEventCaptureManifest.self,
            from: encoded
        )

        expect(decoded == manifest, "capture manifestの全fieldをCodable round-tripで保持する")
        expect(decoded.schemaVersion == 2, "capture manifest schemaVersionを保持する")
        expect(decoded.evidenceKind == .generatedProduct, "evidenceKindを保持する")
        expect(decoded.loggerExecutableSHA256 == manifestTestExecutableSHA256, "executable SHAを保持する")
        expect(decoded.captureStartedAt.contains("T"), "capture開始wall-clockをISO 8601で保持する")
        expect(decoded.captureCompletedAt.contains("T"), "capture完了wall-clockをISO 8601で保持する")
    } catch {
        expect(false, "capture manifest Codable round-tripが成功する: \(error)")
    }
}

private func testCaptureManifestEvidenceKindsHaveStrictRawValues() {
    let encodedValues = Set(TrackpadDriverEventEvidenceKind.allCases.map(\.rawValue))
    expect(
        encodedValues == ["synthetic", "physicalTrackpad", "generatedProduct"],
        "evidenceKindの許可値を3種類に固定する"
    )

    let invalid = Data("\"physical-trackpad\"".utf8)
    do {
        _ = try JSONDecoder().decode(TrackpadDriverEventEvidenceKind.self, from: invalid)
        expect(false, "未知のevidenceKindをdecodeで拒否する")
    } catch {
        expect(true, "未知のevidenceKindをdecodeで拒否する")
    }
}

private func testCaptureManifestRequiresMetadataForAdoptableEvidence() {
    do {
        let emptyMetadata = manifestTestMetadata(
            scenarioID: nil,
            deviceLabel: nil,
            repoHeadSHA: nil
        )
        let (synthetic, syntheticLogData) = try manifestTestManifest(
            evidenceKind: .synthetic,
            metadata: emptyMetadata
        )
        try synthetic.validate(logData: syntheticLogData)

        for evidenceKind in [
            TrackpadDriverEventEvidenceKind.physicalTrackpad,
            .generatedProduct
        ] {
            var adoptable = synthetic
            adoptable.evidenceKind = evidenceKind
            expectManifestValidationError(
                .missingScenarioID(evidenceKind: evidenceKind),
                manifest: adoptable,
                "\(evidenceKind.rawValue)はscenarioIDを必須にする"
            )

            adoptable.scenarioID = "space-right"
            expectManifestValidationError(
                .missingDeviceLabel(evidenceKind: evidenceKind),
                manifest: adoptable,
                "\(evidenceKind.rawValue)はdeviceLabelを必須にする"
            )

            adoptable.deviceLabel = "built-in-trackpad"
            expectManifestValidationError(
                .missingRepoHeadSHA(evidenceKind: evidenceKind),
                manifest: adoptable,
                "\(evidenceKind.rawValue)はrepoHeadSHAを必須にする"
            )
        }
    } catch {
        expect(false, "evidence kind別metadata validationを実行できる: \(error)")
    }
}

private func testCaptureManifestRejectsInvalidOwnFields() {
    do {
        let (validManifest, _) = try manifestTestManifest()

        var invalid = validManifest
        invalid.schemaVersion += 1
        expectManifestValidationError(
            .unsupportedSchemaVersion(invalid.schemaVersion),
            manifest: invalid,
            "未知schemaVersionを拒否する"
        )

        invalid = validManifest
        invalid.logSHA256 = String(repeating: "A", count: 64)
        expectManifestValidationError(.invalidLogSHA256, manifest: invalid, "非canonical log SHAを拒否する")

        invalid = validManifest
        invalid.logByteCount = 0
        expectManifestValidationError(.emptyLog, manifest: invalid, "0 byte logを拒否する")

        invalid = validManifest
        invalid.eventCount = 0
        expectManifestValidationError(.zeroEvents, manifest: invalid, "0 event manifestを拒否する")

        var timestampRegressing = validManifest
        timestampRegressing.firstEventTimestamp = timestampRegressing.lastEventTimestamp + 1
        do {
            try timestampRegressing.validate()
            expect(true, "capture順のfirst / last timestamp逆行を許可する")
        } catch {
            expect(false, "capture順のfirst / last timestamp逆行を許可する: \(error)")
        }

        invalid = validManifest
        invalid.loggerExecutableSHA256 = ""
        expectManifestValidationError(
            .invalidLoggerExecutableSHA256,
            manifest: invalid,
            "取得不能なexecutable SHAを成功扱いしない"
        )

        invalid = validManifest
        invalid.captureStartedAt = "not-a-wall-clock"
        expectManifestValidationError(
            .invalidCaptureStartWallClock,
            manifest: invalid,
            "不正なcapture開始wall-clockを拒否する"
        )

        invalid = validManifest
        invalid.captureCompletedAt = "not-a-wall-clock"
        expectManifestValidationError(
            .invalidCaptureCompletionWallClock,
            manifest: invalid,
            "不正なcapture完了wall-clockを拒否する"
        )

        invalid = validManifest
        let originalStart = invalid.captureStartedAt
        invalid.captureStartedAt = invalid.captureCompletedAt
        invalid.captureCompletedAt = originalStart
        expectManifestValidationError(
            .captureWallClockOutOfOrder,
            manifest: invalid,
            "capture完了より後の開始wall-clockを拒否する"
        )
    } catch {
        expect(false, "manifest field validation fixtureを生成できる: \(error)")
    }
}

private func testCaptureManifestDetectsFinalLogTampering() {
    do {
        let (validManifest, logData) = try manifestTestManifest()

        var invalid = validManifest
        invalid.logSHA256 = String(repeating: "0", count: 64)
        do {
            try invalid.validate(logData: logData)
            expect(false, "log SHA改ざんを拒否する")
        } catch let error as TrackpadDriverEventCaptureManifestValidationError {
            expect(error == .logMismatch(field: "logSHA256"), "log SHA mismatch fieldを報告する")
        }

        invalid = validManifest
        invalid.eventCount += 1
        do {
            try invalid.validate(logData: logData)
            expect(false, "event count改ざんを拒否する")
        } catch let error as TrackpadDriverEventCaptureManifestValidationError {
            expect(error == .logMismatch(field: "eventCount"), "event count mismatch fieldを報告する")
        }

        var changedLog = logData
        changedLog[changedLog.startIndex] ^= 0x01
        do {
            try validManifest.validate(logData: changedLog)
            expect(false, "final log bytes改ざんを拒否する")
        } catch {
            expect(true, "final log bytes改ざんを拒否する")
        }
    } catch {
        expect(false, "log tampering validation fixtureを生成できる: \(error)")
    }
}

private func testCaptureManifestRejectsIncompleteOrInconsistentJSONLines() {
    do {
        let completeData = try manifestTestLogData()
        let unterminated = completeData.dropLast()
        do {
            _ = try TrackpadDriverEventCaptureManifest.summarize(logData: Data(unterminated))
            expect(false, "改行終端のない最終recordを拒否する")
        } catch let error as TrackpadDriverEventCaptureLogInspectionError {
            expect(error == .unterminatedLastRecord, "truncated logの原因を報告する")
        }

        do {
            _ = try TrackpadDriverEventCaptureManifest.summarize(logData: Data())
            expect(false, "0 event logを拒否する")
        } catch let error as TrackpadDriverEventCaptureLogInspectionError {
            expect(error == .emptyLog, "0 event logの原因を報告する")
        }

        var emptyRecordData = completeData
        emptyRecordData.append(0x0A)
        do {
            _ = try TrackpadDriverEventCaptureManifest.summarize(logData: emptyRecordData)
            expect(false, "空JSON Lines recordを拒否する")
        } catch let error as TrackpadDriverEventCaptureLogInspectionError {
            expect(error == .emptyRecord(line: 3), "空recordのline番号を報告する")
        }

        let first = try manifestTestLogData(
            timestamps: [1],
            metadata: manifestTestMetadata(scenarioID: "first")
        )
        let second = try manifestTestLogData(
            timestamps: [2],
            metadata: manifestTestMetadata(scenarioID: "second")
        )
        do {
            _ = try TrackpadDriverEventCaptureManifest.summarize(logData: first + second)
            expect(false, "record間metadata mismatchを拒否する")
        } catch let error as TrackpadDriverEventCaptureLogInspectionError {
            expect(error == .metadataMismatch(line: 2), "metadata mismatchのline番号を報告する")
        }
    } catch {
        expect(false, "不完全JSON Lines validation fixtureを生成できる: \(error)")
    }
}

public func runTrackpadDriverEventCaptureManifestTests() {
    testCaptureManifestSHA256KnownVector()
    testCaptureManifestSummarizesFinalLogBytes()
    testCaptureManifestCodableRoundTripPreservesEveryField()
    testCaptureManifestEvidenceKindsHaveStrictRawValues()
    testCaptureManifestRequiresMetadataForAdoptableEvidence()
    testCaptureManifestRejectsInvalidOwnFields()
    testCaptureManifestDetectsFinalLogTampering()
    testCaptureManifestRejectsIncompleteOrInconsistentJSONLines()
    testCaptureManifestStoreRemovesStaleSidecar()
    testCaptureManifestStoreRemovesSymlinkWithoutTouchingTarget()
    testCaptureManifestStoreRejectsSameAndSymlinkedLocations()
    testCaptureManifestStoreWritesFinalLFWithoutTemporaryArtifacts()
    testCaptureManifestStoreCleansTemporaryFileAfterRenameFailure()
    testCaptureManifestStoreReportsInvalidParentDirectoryStructurally()
}
