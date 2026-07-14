# frozen_string_literal: true

require "pathname"
require "digest"
require "json"

root = Pathname.new(__dir__).join("..").expand_path
errors = []

required_snippets = {
  "Sources/NapeGestureCore/FixedGestureInput.swift" => [
    "public enum FixedGestureClass",
    "case twoFingerScrollSwipe",
    "case threeFingerSystemSwipe",
    "case pinch",
    "public struct GestureButtonAssignments",
    "public var button3: FixedGestureClass",
    "public var button4: FixedGestureClass",
    "public var button5: FixedGestureClass",
    "button3: FixedGestureClass = .twoFingerScrollSwipe",
    "button4: FixedGestureClass = .threeFingerSystemSwipe",
    "button5: FixedGestureClass = .pinch",
    "case .button3:\n            button3",
    "case .button4:\n            button4",
    "case .center:\n            button5",
    "private let assignments: GestureButtonAssignments",
    "let gestureClass = assignments.assignment(for: button)",
    "public struct FixedGestureInputCommand",
    "captureOrder: UInt64",
    "timestamp: MonotonicEventTimestamp"
  ],
  "Sources/NapeGestureCore/FixedGestureSession.swift" => [
    "public struct FixedGestureSessionMachine",
    "public mutating func accept(_ command: FixedGestureInputCommand) throws",
    "case terminal"
  ],
  "Sources/NapeGestureProductOutput/FixedGestureProductSessionCoordinator.swift" => [
    "public final class FixedGestureProductSessionCoordinator",
    "case .twoFingerScrollSwipe: .scroll",
    "case .threeFingerSystemSwipe: .dockSwipe",
    "case .pinch: .dockSwipePinch",
    "private static let requiredFamilies: Set<TrackpadOutputEventFamily>",
    ".scroll,",
    ".dockSwipe,",
    ".dockSwipePinch,",
    "return .dockSwipePinch(",
    "private let systemGestureSensitivity: Double",
    "private func normalizedMotion(_ value: Double) -> Double",
    "(value / 600) * systemGestureSensitivity",
    "private static func pinchMotion(x: Double, y: Double) -> Double"
  ],
  "Sources/NapeGestureCore/TrackpadOutputSession.swift" => [
    "case scroll",
    "case dockSwipe",
    "case dockSwipePinch",
    "case dockSwipePinch(progress: Double, motion: Double, terminalVelocity: Double)"
  ],
  "Sources/NapeGestureProductOutput/ProductGestureOutput.swift" => [
    "public static let defaultConfirmedFamilies: Set<TrackpadOutputEventFamily> = [.scroll]",
    ".dockSwipe,",
    ".dockSwipePinch,",
    "supportedFamilies: []"
  ],
  "Sources/NapeGestureProductOutput/TrackpadGestureCandidateEventBuilder.swift" => [
    "case .dockSwipePinch:",
    "case let .dockSwipePinch(progress, _, terminalVelocity):",
    "motion: axis == .horizontal ? 1 : 2,",
    "motion: 4,",
    "terminalVelocityZ: terminalVelocity"
  ],
  "Sources/NapeGestureProductOutput/RecognizedGestureIOHIDCompatibilityAdapter.swift" => [
    "recognized-dockswipe-templates-25F80-v2",
    "recognized-dockswipe-template-v2",
    "852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6",
    "document.osVersion == contract.sourceOSVersion",
    "document.osBuild == contract.sourceOSBuild",
    "event.type.rawValue == 30",
    "event.getIntegerValueField(rawField(110)) == 23",
    "setEventFlags(hidPointer, options)",
    "setIntegerValue(hidPointer, Self.dockSwipeMaskField, 0)",
    "setIntegerValue(hidPointer, Self.dockSwipeMotionField, Int64(motion))",
    "setIntegerValue(hidPointer, Self.dockSwipeFlavorField, 3)",
    "setFloatValue(hidPointer, Self.dockSwipeProgressField, progress)",
    "setFloatValue(hidPointer, Self.dockSwipePositionXField, positionX)",
    "setFloatValue(hidPointer, Self.dockSwipePositionYField, positionY)",
    "updateTerminalVelocity(",
    "setFloatValue(child, Self.velocityZField, z)",
    "case 2, 4: .vertical"
  ],
  "Sources/NapeGestureProductOutput/TrackpadGestureOutputAdapter.swift" => [
    "let registeredModel = TrackpadScrollOutputModelFixtureReader.read(",
    "let recognizedGestureAdapter = RecognizedGestureIOHIDCompatibilityAdapter(",
    "compatibilityAdapter: recognizedGestureAdapter",
    "case .dockSwipe, .dockSwipePinch:",
    "capability = .contractMismatch(",
    "model = nil",
    "builder = nil",
    "gestureBuilder = nil",
    "rawField(contract.scroll.phaseRawField)",
    "rawField(contract.scrollCompanion.phaseRawField)",
    ".scrollWheelEventFixedPtDeltaAxis1",
    ".scrollWheelEventPointDeltaAxis1",
    "setMotionAliases("
  ],
  "Sources/nape-gesture/GestureOutputExecutor.swift" => [
    "private let coordinator: FixedGestureProductSessionCoordinator",
    "func post(command: FixedGestureInputCommand)",
    "coordinator.unsupportedRequiredFamilies",
    "systemGestureSensitivity: systemGestureSensitivity"
  ],
  "Sources/nape-gesture/NapeGestureDaemon.swift" => [
    "private var recognizer: FixedGestureInputRecognizer",
    "buttonAssignments: GestureButtonAssignments = .default",
    "assignments: buttonAssignments",
    "commands: [FixedGestureInputCommand]",
    "try outputExecutor.ensureOutputAvailable()",
    "systemGestureSensitivity: systemGestureSensitivity"
  ],
  "Sources/nape-gesture/NapeGestureRuntime.swift" => [
    "buttonAssignments: settings.gesture.buttonAssignments",
    "systemGestureSensitivity: settings.gesture.systemGestureSensitivity"
  ],
  "Sources/NapeGestureCore/GestureConfiguration.swift" => [
    "public var buttonAssignments: GestureButtonAssignments",
    "buttonAssignments: GestureButtonAssignments = .default",
    "try container.encode(buttonAssignments, forKey: .buttonAssignments)"
  ],
  "Sources/NapeGestureCore/SettingsUISchema.swift" => [
    "case buttonAssignments",
    "case popUpButton",
    "case button3GestureAssignment",
    "case button4GestureAssignment",
    "case button5GestureAssignment",
    "gesture.buttonAssignments.button3",
    "gesture.buttonAssignments.button4",
    "gesture.buttonAssignments.button5",
    "controlKind: .popUpButton",
    "valueSource: .editableGestureSetting",
    "isEditable: true"
  ],
  "Sources/nape-gesture/SettingsWindowController.swift" => [
    "private let button3GesturePopUp = NSPopUpButton()",
    "private let button4GesturePopUp = NSPopUpButton()",
    "private let button5GesturePopUp = NSPopUpButton()",
    "FixedGestureClass.allCases.map(\\.displayName)",
    "button3: selectedGestureClass(in: button3GesturePopUp)",
    "button4: selectedGestureClass(in: button4GesturePopUp)",
    "button5: selectedGestureClass(in: button5GesturePopUp)",
    "buttonAssignmentEditEnablesApply",
    "buttonAssignmentRevertDisablesApply"
  ],
  "Sources/NapeGestureCore/SettingsMigration.swift" => [
    "gesture[\"buttonAssignments\"] as? [String: Any]",
    "let assignmentKeys: Set<String> = [\"button3\", \"button4\", \"button5\"]",
    "Set(assignments.keys) != assignmentKeys",
    "assignments[$0] is NSNull",
    "gesture[\"systemGestureSensitivity\"] == nil",
    "gesture[\"systemGestureSensitivity\"] is NSNull",
    "\"button3Mode\"",
    "\"button4Mode\"",
    "\"button5Mode\""
  ],
  "Sources/nape-gesture-core-tests/main.swift" => [
    "func testGestureButtonAssignmentsDefaultCustomAndDuplicateMappings()",
    "複数buttonへ同じGestureClassを重複割り当てできる",
    "変更した全button割り当てをJSON往復で保持する",
    "canonical JSONをgesture.buttonAssignments.button3/4/5で保存する",
    "有効な変更済みbutton割り当てをmigrationで上書きしない"
  ],
  "Sources/nape-gesture-product-output-tests/main.swift" => [
    "private func testSystemGestureSensitivityFollowsAssignedClassNotPhysicalButton()"
  ],
  "Sources/nape-gesture/DoctorCommand.swift" => [
    ".scroll,",
    ".dockSwipe,",
    ".dockSwipePinch,"
  ]
}.freeze

required_snippets.each do |relative, snippets|
  path = root.join(relative)
  unless path.file?
    errors << "button割り当てGestureClass guardの対象fileがありません: #{relative}"
    next
  end

  content = path.read
  snippets.each do |snippet|
    unless content.include?(snippet)
      errors << "#{relative}: 必須実装がありません: #{snippet.inspect}"
    end
  end
end

dock_swipe_fixture_path =
  root.join("Fixtures/trackpad-contract/25F80/recognized-dockswipe-templates.json")
expected_dock_swipe_fixture_sha256 =
  "852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6"

if dock_swipe_fixture_path.file?
  data = dock_swipe_fixture_path.binread
  actual_sha256 = Digest::SHA256.hexdigest(data)
  if actual_sha256 != expected_dock_swipe_fixture_sha256
    errors << "#{dock_swipe_fixture_path.relative_path_from(root)}: 登録済みSHA-256と一致しません: #{actual_sha256}"
  end

  begin
    fixture = JSON.parse(data)
    if fixture.is_a?(Hash)
      expected_identity = {
        "schemaVersion" => 2,
        "fixtureID" => "recognized-dockswipe-templates-25F80-v2",
        "contractID" => "recognized-dockswipe-template-v2",
        "osVersion" => "26.5.1",
        "osBuild" => "25F80"
      }
      expected_identity.each do |key, expected|
        actual = fixture[key]
        next if actual == expected

        errors << "#{dock_swipe_fixture_path.relative_path_from(root)}: #{key}が登録値と一致しません: expected=#{expected.inspect} actual=#{actual.inspect}"
      end

      source_hashes = fixture["sourceLogSHA256"]
      unless source_hashes.is_a?(Hash) &&
             source_hashes.keys.sort == %w[horizontal vertical] &&
             source_hashes.values.all? { |value| value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/) }
        errors << "#{dock_swipe_fixture_path.relative_path_from(root)}: source log SHA-256が2軸分のcanonical値ではありません"
      end

      expected_phases = %w[began changed ended]
      templates = fixture["templates"]
      %w[horizontal vertical].each do |axis|
        signed_templates = templates.is_a?(Hash) ? templates[axis] : nil
        unless signed_templates.is_a?(Hash) && signed_templates.keys.sort == %w[negative positive]
          errors << "#{dock_swipe_fixture_path.relative_path_from(root)}: #{axis} templateが正負方向を完全に保持していません"
          next
        end
        %w[positive negative].each do |polarity|
          phases = signed_templates[polarity]
          unless phases.is_a?(Hash) &&
                 phases.keys.sort == expected_phases.sort &&
                 phases.values.all? { |value| value.is_a?(String) && !value.empty? }
            errors << "#{dock_swipe_fixture_path.relative_path_from(root)}: #{axis}.#{polarity} templateがbegan / changed / endedを完全に保持していません"
          end
        end
      end
    else
      errors << "#{dock_swipe_fixture_path.relative_path_from(root)}: JSON rootがobjectではありません"
    end
  rescue JSON::ParserError => e
    errors << "#{dock_swipe_fixture_path.relative_path_from(root)}: JSONを解析できません: #{e.message}"
  end
else
  errors << "認識済みDockSwipe template fixtureがありません: #{dock_swipe_fixture_path.relative_path_from(root)}"
end

daemon_path = root.join("Sources/nape-gesture/NapeGestureDaemon.swift")
if daemon_path.file?
  daemon_content = daemon_path.read
  readiness_index = daemon_content.index("try outputExecutor.ensureOutputAvailable()")
  event_tap_index = daemon_content.index("CGEvent.tapCreate(")
  unless readiness_index && event_tap_index && readiness_index < event_tap_index
    errors << "Sources/nape-gesture/NapeGestureDaemon.swift: runtime readinessをevent tap作成前に確定していません"
  end
end

forbidden_terms = {
  "Sources/NapeGestureCore/FixedGestureInput.swift" => [
    "fingerCount",
    "frontmostApplication",
    "postToPid",
    "AXUIElement",
    "KeyboardShortcut",
    "DriverKit",
    "digitizer",
    "IOHIDUserDevice"
  ],
  "Sources/NapeGestureCore/TrackpadOutputSession.swift" => [
    "fingerCount",
    "frontmostApplication",
    "postToPid",
    "AXUIElement",
    "KeyboardShortcut",
    "DriverKit",
    "digitizer",
    "IOHIDUserDevice",
    "magnification"
  ],
  "Sources/nape-gesture/NapeGestureDaemon.swift" => [
    "GestureRecognizer(",
    "TrackpadGestureMode",
    "ProductGestureSessionCoordinator(",
    "deadZonePoints",
    "dragSensitivity",
    "wheelSensitivity",
    "DiagnosticEventPoster",
    "fingerCount",
    "frontmostApplication",
    "postToPid",
    "AXUIElement",
    "IOHIDUserDevice",
    "magnification"
  ],
  "Sources/nape-gesture/GestureOutputExecutor.swift" => [
    "ProductGestureSessionCoordinator(",
    "TrackpadGestureMode",
    "fingerCount",
    "frontmostApplication",
    "postToPid",
    "AXUIElement",
    "KeyboardShortcut",
    "IOHIDUserDevice",
    "magnification"
  ],
  "Sources/NapeGestureProductOutput/FixedGestureProductSessionCoordinator.swift" => [
    "targetPID",
    "fingerCount",
    "frontmostApplication",
    "postToPid",
    "AXUIElement",
    "KeyboardShortcut",
    "DriverKit",
    "digitizer",
    "IOHIDUserDevice",
    "magnification"
  ],
  "Sources/NapeGestureProductOutput/ProductGestureOutput.swift" => [
    "magnification",
    "fingerCount",
    "ProductGestureOutputSystemIdentity",
    "systemIdentity",
    "currentOperatingSystemBuild",
    "frontmostApplication",
    "postToPid",
    "AXUIElement",
    "KeyboardShortcut",
    "DriverKit",
    "digitizer",
    "IOHIDUserDevice"
  ],
  "Sources/NapeGestureProductOutput/TrackpadGestureCandidateEventBuilder.swift" => [
    "magnification",
    "targetPID",
    "fingerCount",
    "frontmostApplication",
    "postToPid",
    "AXUIElement",
    "KeyboardShortcut",
    "DriverKit",
    "digitizer",
    "IOHIDUserDevice"
  ],
  "Sources/NapeGestureProductOutput/TrackpadGestureOutputAdapter.swift" => [
    "magnification",
    "targetPID",
    "fingerCount",
    "systemIdentity",
    "frontmostApplication",
    "postToPid",
    "AXUIElement",
    "KeyboardShortcut",
    "DriverKit",
    "digitizer",
    "IOHIDUserDevice"
  ],
  "Sources/nape-gesture/DoctorCommand.swift" => [
    "magnification",
    "fingerCount",
    "frontmostApplication",
    "postToPid",
    "AXUIElement",
    "KeyboardShortcut",
    "DriverKit",
    "digitizer",
    "IOHIDUserDevice"
  ],
  "Sources/NapeGestureCore/SettingsUISchema.swift" => [
    "button3Mode",
    "button4Mode",
    "button5Mode",
    "case fixedMapping",
    "case fixedButton3Gesture",
    "case fixedButton4Gesture",
    "case fixedButton5Gesture",
    "fixedProductMapping",
    "deadZonePoints",
    "dragSensitivity",
    "wheelSensitivity"
  ],
  "Sources/nape-gesture/SettingsWindowController.swift" => [
    "button3Mode",
    "button4Mode",
    "button5Mode",
    "fixedMappingLabels",
    "fixedMappingTexts:",
    "gesturePaneHasForbiddenModeControl",
    "deadZonePoints",
    "dragSensitivity",
    "wheelSensitivity"
  ]
}.freeze

forbidden_terms.each do |relative, terms|
  path = root.join(relative)
  unless path.file?
    errors << "button割り当てGestureClass guardの対象fileがありません: #{relative}"
    next
  end

  content = path.read
  terms.each do |term|
    errors << "#{relative}: 製品経路の廃止対象が残っています: #{term}" if content.include?(term)
  end
end

configuration_path = root.join("Sources/NapeGestureCore/GestureConfiguration.swift")
if configuration_path.file?
  content = configuration_path.read
  encode_body = content[/public func encode\(to encoder: Encoder\) throws \{.*?\n    \}\n\n    public func mode/m]

  if encode_body.nil?
    errors << "Sources/NapeGestureCore/GestureConfiguration.swift: canonical encode境界を特定できません"
  else
    unless encode_body.include?("try container.encode(cancellation, forKey: .cancellation)")
      errors << "Sources/NapeGestureCore/GestureConfiguration.swift: canonical設定にcancellationがありません"
    end
    unless encode_body.include?(
      "try container.encode(systemGestureSensitivity, forKey: .systemGestureSensitivity)"
    )
      errors << "Sources/NapeGestureCore/GestureConfiguration.swift: canonical設定にsystemGestureSensitivityがありません"
    end
    unless encode_body.include?(
      "try container.encode(buttonAssignments, forKey: .buttonAssignments)"
    )
      errors << "Sources/NapeGestureCore/GestureConfiguration.swift: canonical設定にbuttonAssignmentsがありません"
    end

    %w[
      button3Mode
      button4Mode
      button5Mode
      deadZonePoints
      dragSensitivity
      wheelSensitivity
      acceleration
      momentum
      bindings
    ].each do |term|
      errors << "Sources/NapeGestureCore/GestureConfiguration.swift: canonical設定へ旧項目を保存しています: #{term}" if encode_body.include?(term)
    end
  end
else
  errors << "button割り当てGestureClass guardの対象fileがありません: Sources/NapeGestureCore/GestureConfiguration.swift"
end

unless errors.empty?
  warn "button割り当てGestureClass製品モデルguardに失敗しました:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "button割り当てGestureClass製品モデルguardに成功しました。"
