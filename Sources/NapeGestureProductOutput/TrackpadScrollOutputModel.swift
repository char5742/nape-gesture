import Foundation
import NapeGestureCore

public struct TrackpadScrollDeltaAxisModelParameters: Codable, Equatable, Sendable {
    public var pointLinearCoefficient: Double
    public var pointQuadraticCoefficient: Double
    public var fixedLinearCoefficient: Double
    public var fixedQuadraticCoefficient: Double
    public var lineLinearCoefficient: Double
    public var lineQuadraticCoefficient: Double

    public init(
        pointLinearCoefficient: Double,
        pointQuadraticCoefficient: Double,
        fixedLinearCoefficient: Double,
        fixedQuadraticCoefficient: Double,
        lineLinearCoefficient: Double,
        lineQuadraticCoefficient: Double
    ) {
        self.pointLinearCoefficient = pointLinearCoefficient
        self.pointQuadraticCoefficient = pointQuadraticCoefficient
        self.fixedLinearCoefficient = fixedLinearCoefficient
        self.fixedQuadraticCoefficient = fixedQuadraticCoefficient
        self.lineLinearCoefficient = lineLinearCoefficient
        self.lineQuadraticCoefficient = lineQuadraticCoefficient
    }

    var isValid: Bool {
        let values = [
            pointLinearCoefficient,
            pointQuadraticCoefficient,
            fixedLinearCoefficient,
            fixedQuadraticCoefficient,
            lineLinearCoefficient,
            lineQuadraticCoefficient
        ]
        return values.allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

public struct TrackpadScrollDeltaModelParameters: Codable, Equatable, Sendable {
    public var x: TrackpadScrollDeltaAxisModelParameters
    public var y: TrackpadScrollDeltaAxisModelParameters

    public init(
        x: TrackpadScrollDeltaAxisModelParameters,
        y: TrackpadScrollDeltaAxisModelParameters
    ) {
        self.x = x
        self.y = y
    }

    var isValid: Bool {
        x.isValid && y.isValid
    }
}

public struct TrackpadScrollOutputModelFixture: Codable, Equatable, Sendable {
    public struct SourceContract: Codable, Equatable, Sendable {
        public var sha256: String
        public var fixtureID: String
        public var contractID: String
    }

    public struct Model: Codable, Equatable, Sendable {
        public var kind: String
        public var formula: String
        public var linearCoefficient: Double
        public var quadraticCoefficient: Double
        public var sampleCount: Int
    }

    public struct Models: Codable, Equatable, Sendable {
        public var gestureToLine: Model
        public var gestureToFixed: Model
        public var gestureToPoint: Model
    }

    public struct Axis: Codable, Equatable, Sendable {
        public var modelSampleCount: Int
        public var models: Models
    }

    public struct Axes: Codable, Equatable, Sendable {
        public var x: Axis
        public var y: Axis
    }

    public var schemaVersion: Int
    public var fixtureID: String
    public var modelID: String
    public var status: String
    public var osVersion: String
    public var osBuild: String
    public var sourceContract: SourceContract
    public var axes: Axes
}

public enum TrackpadScrollOutputModelFixtureReader {
    public static let registeredFixtureSHA256 = "c947b3adfa68927b514f7af65464a2ba79100815cf21d471018dbafc2e8beef4"

    public static func read(
        modelData: Data,
        contract: VerifiedProductGestureOutputContract
    ) -> (fixture: TrackpadScrollOutputModelFixture, parameters: TrackpadScrollDeltaModelParameters)? {
        guard TrackpadDriverEventCaptureManifest.sha256HexDigest(of: modelData)
            == registeredFixtureSHA256,
            let fixture = try? JSONDecoder().decode(
                TrackpadScrollOutputModelFixture.self,
                from: modelData
            ),
            fixture.schemaVersion == 1,
            fixture.fixtureID == "trackpad-scroll-output-model-25F80-v1",
            fixture.modelID == "trackpad-scroll-output-model-v1",
            fixture.status == "derived",
            fixture.osVersion == contract.osVersion,
            fixture.osBuild == contract.osBuild,
            fixture.sourceContract.sha256 == contract.fixtureSHA256,
            fixture.sourceContract.fixtureID == contract.fixtureID,
            fixture.sourceContract.contractID == contract.contractID,
            fixture.axes.x.modelSampleCount == 967,
            fixture.axes.y.modelSampleCount == 967,
            validateModels(fixture.axes.x.models),
            validateModels(fixture.axes.y.models)
        else {
            return nil
        }

        let parameters = TrackpadScrollDeltaModelParameters(
            x: parameters(from: fixture.axes.x.models),
            y: parameters(from: fixture.axes.y.models)
        )
        return parameters.isValid ? (fixture, parameters) : nil
    }

    private static func validateModels(_ models: TrackpadScrollOutputModelFixture.Models) -> Bool {
        let expectedFormula = "continuous = linearCoefficient * gesture + quadraticCoefficient * gesture * abs(gesture)"
        let values = [models.gestureToLine, models.gestureToFixed, models.gestureToPoint]
        return values.allSatisfy {
            $0.formula == expectedFormula
                && $0.sampleCount == 967
                && $0.linearCoefficient.isFinite
                && $0.linearCoefficient >= 0
                && $0.quadraticCoefficient.isFinite
                && $0.quadraticCoefficient >= 0
        } && models.gestureToLine.kind
            == "odd-quadratic-least-squares-with-symmetric-rounding"
            && models.gestureToFixed.kind == "odd-quadratic-least-squares"
            && models.gestureToPoint.kind == "odd-quadratic-least-squares"
    }

    private static func parameters(
        from models: TrackpadScrollOutputModelFixture.Models
    ) -> TrackpadScrollDeltaAxisModelParameters {
        TrackpadScrollDeltaAxisModelParameters(
            pointLinearCoefficient: models.gestureToPoint.linearCoefficient,
            pointQuadraticCoefficient: models.gestureToPoint.quadraticCoefficient,
            fixedLinearCoefficient: models.gestureToFixed.linearCoefficient,
            fixedQuadraticCoefficient: models.gestureToFixed.quadraticCoefficient,
            lineLinearCoefficient: models.gestureToLine.linearCoefficient,
            lineQuadraticCoefficient: models.gestureToLine.quadraticCoefficient
        )
    }
}

public struct TrackpadScrollDeltaAxis: Equatable, Sendable {
    public var line: Int64
    public var fixed: Double
    public var point: Double
    public var gesture: Float

    public init(line: Int64, fixed: Double, point: Double, gesture: Float) {
        self.line = line
        self.fixed = fixed
        self.point = point
        self.gesture = gesture
    }

    public static let zero = TrackpadScrollDeltaAxis(
        line: 0,
        fixed: 0.0,
        point: 0.0,
        gesture: 0.0
    )
}

public enum TrackpadScrollPreparedEventKind: String, Equatable, Sendable {
    case scroll
    case envelope
    case companion
}

public struct TrackpadScrollPreparedEvent: Equatable, Sendable {
    public var kind: TrackpadScrollPreparedEventKind
    public var timestamp: MonotonicEventTimestamp
    public var scrollPhase: Int64
    public var momentumPhase: Int64
    public var companionPhase: Int64
    public var deltaX: TrackpadScrollDeltaAxis
    public var deltaY: TrackpadScrollDeltaAxis

    public init(
        kind: TrackpadScrollPreparedEventKind,
        timestamp: MonotonicEventTimestamp,
        scrollPhase: Int64,
        momentumPhase: Int64,
        companionPhase: Int64,
        deltaX: TrackpadScrollDeltaAxis,
        deltaY: TrackpadScrollDeltaAxis
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.companionPhase = companionPhase
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public enum TrackpadScrollOutputModelError: Error, Equatable, Sendable {
    case invalidParameters
    case unsupportedFamily
    case invalidPayload
    case invalidPhase
    case invalidCancellationState
    case deltaOutOfRange
}

public struct TrackpadScrollOutputModel: Sendable {
    private let contract: TrackpadScrollMomentumContractFixture
    private let parameters: TrackpadScrollDeltaModelParameters

    public init(
        contract: TrackpadScrollMomentumContractFixture,
        parameters: TrackpadScrollDeltaModelParameters
    ) throws {
        guard parameters.isValid else {
            throw TrackpadScrollOutputModelError.invalidParameters
        }
        self.contract = contract
        self.parameters = parameters
    }

    public func prepare(
        event: TrackpadOutputSessionEvent,
        previousState: TrackpadOutputSessionState
    ) throws -> [TrackpadScrollPreparedEvent] {
        guard event.family == .scroll else {
            throw TrackpadScrollOutputModelError.unsupportedFamily
        }

        switch event {
        case let .input(frame):
            return try prepareInput(frame)
        case let .momentum(frame):
            return try prepareMomentum(frame)
        case let .cancellation(frame):
            return try prepareCancellation(frame, previousState: previousState)
        }
    }

    private func prepareInput(
        _ frame: TrackpadOutputInputFrame
    ) throws -> [TrackpadScrollPreparedEvent] {
        let phase: Int64
        let isTerminal: Bool
        switch frame.phase {
        case .began:
            phase = contract.scroll.phaseValues.began
            isTerminal = false
        case .changed:
            phase = contract.scroll.phaseValues.changed
            isTerminal = false
        case .ended, .cancelled:
            // 実機契約で未確定のcancel値を作らず、確認済みendedへ収束させる。
            phase = contract.scroll.phaseValues.ended
            isTerminal = true
        }
        let deltas = try deltaVector(from: frame.payload, terminal: isTerminal)
        return inputEvents(
            timestamp: frame.timestamp,
            phase: phase,
            deltaX: deltas.x,
            deltaY: deltas.y
        )
    }

    private func prepareMomentum(
        _ frame: TrackpadOutputMomentumFrame
    ) throws -> [TrackpadScrollPreparedEvent] {
        let phase: Int64
        let isTerminal: Bool
        switch frame.phase {
        case .began:
            phase = contract.momentum.phaseValues.began
            isTerminal = false
        case .continued:
            phase = contract.momentum.phaseValues.continued
            isTerminal = false
        case .ended:
            phase = contract.momentum.phaseValues.ended
            isTerminal = true
        }
        let deltas = try deltaVector(from: frame.payload, terminal: isTerminal)
        return [
            TrackpadScrollPreparedEvent(
                kind: .scroll,
                timestamp: frame.timestamp,
                scrollPhase: 0,
                momentumPhase: phase,
                companionPhase: 0,
                deltaX: deltas.x,
                deltaY: deltas.y
            )
        ]
    }

    private func prepareCancellation(
        _ frame: TrackpadOutputCancellationFrame,
        previousState: TrackpadOutputSessionState
    ) throws -> [TrackpadScrollPreparedEvent] {
        switch previousState {
        case .inputActive:
            return inputEvents(
                timestamp: frame.timestamp,
                phase: contract.scroll.phaseValues.ended,
                deltaX: .zero,
                deltaY: .zero
            )
        case .awaitingMomentum:
            return []
        case .momentumActive:
            return [
                TrackpadScrollPreparedEvent(
                    kind: .scroll,
                    timestamp: frame.timestamp,
                    scrollPhase: 0,
                    momentumPhase: contract.momentum.phaseValues.ended,
                    companionPhase: 0,
                    deltaX: .zero,
                    deltaY: .zero
                )
            ]
        case .awaitingInput, .terminal:
            throw TrackpadScrollOutputModelError.invalidCancellationState
        }
    }

    private func inputEvents(
        timestamp: MonotonicEventTimestamp,
        phase: Int64,
        deltaX: TrackpadScrollDeltaAxis,
        deltaY: TrackpadScrollDeltaAxis
    ) -> [TrackpadScrollPreparedEvent] {
        let scroll = TrackpadScrollPreparedEvent(
            kind: .scroll,
            timestamp: timestamp,
            scrollPhase: phase,
            momentumPhase: 0,
            companionPhase: 0,
            deltaX: deltaX,
            deltaY: deltaY
        )
        let envelope = TrackpadScrollPreparedEvent(
            kind: .envelope,
            timestamp: timestamp,
            scrollPhase: 0,
            momentumPhase: 0,
            companionPhase: phase,
            deltaX: .zero,
            deltaY: .zero
        )
        let companion = TrackpadScrollPreparedEvent(
            kind: .companion,
            timestamp: timestamp,
            scrollPhase: 0,
            momentumPhase: 0,
            companionPhase: phase,
            deltaX: deltaX,
            deltaY: deltaY
        )
        return [scroll, envelope, companion]
    }

    private func deltaVector(
        from payload: TrackpadOutputPayload,
        terminal: Bool
    ) throws -> (x: TrackpadScrollDeltaAxis, y: TrackpadScrollDeltaAxis) {
        guard case let .scroll(deltaX, deltaY, _, _) = payload else {
            throw TrackpadScrollOutputModelError.invalidPayload
        }
        if terminal {
            return (.zero, .zero)
        }
        return (
            try deltaAxis(gestureDelta: deltaX, parameters: parameters.x),
            try deltaAxis(gestureDelta: deltaY, parameters: parameters.y)
        )
    }

    private func deltaAxis(
        gestureDelta: Double,
        parameters: TrackpadScrollDeltaAxisModelParameters
    ) throws -> TrackpadScrollDeltaAxis {
        let gesture = Float(gestureDelta)
        guard gestureDelta.isFinite, gesture.isFinite
        else {
            throw TrackpadScrollOutputModelError.deltaOutOfRange
        }
        guard gestureDelta != 0 else {
            return .zero
        }

        let magnitude = abs(gestureDelta)
        let sign = gestureDelta.sign == .minus ? -1.0 : 1.0
        let point = sign * modeledMagnitude(
            magnitude,
            linear: parameters.pointLinearCoefficient,
            quadratic: parameters.pointQuadraticCoefficient
        ).rounded()
        let fixedMagnitude = floor(modeledMagnitude(
            magnitude,
            linear: parameters.fixedLinearCoefficient,
            quadratic: parameters.fixedQuadraticCoefficient
        ) * 65_536.0) / 65_536.0
        let fixed = sign * fixedMagnitude
        let lineValue = sign * modeledMagnitude(
            magnitude,
            linear: parameters.lineLinearCoefficient,
            quadratic: parameters.lineQuadraticCoefficient
        ).rounded()
        guard point.isFinite,
              fixed.isFinite,
              lineValue.isFinite,
              lineValue >= Double(Int64.min),
              lineValue <= Double(Int64.max)
        else {
            throw TrackpadScrollOutputModelError.deltaOutOfRange
        }

        return TrackpadScrollDeltaAxis(
            line: Int64(lineValue),
            fixed: fixed,
            point: point,
            gesture: gesture
        )
    }

    private func modeledMagnitude(
        _ magnitude: Double,
        linear: Double,
        quadratic: Double
    ) -> Double {
        linear * magnitude + quadratic * magnitude * magnitude
    }
}
