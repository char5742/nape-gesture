#!/usr/bin/env ruby

require "digest"
require "json"
require "optparse"

GENERATED_EVENT_MARKER = 0x4D_47_53_54
KEY_EVENT_TYPES = [10, 11, 12].freeze
SCROLL_SCENARIOS = [
  "pure-trackpad-vertical-scroll",
  "pure-trackpad-horizontal-scroll",
  "pure-trackpad-momentum-stop",
  "pure-trackpad-cancel-reverse"
].freeze

class VerificationFailure < StandardError; end

def require_contract(condition, message)
  raise VerificationFailure, message unless condition
end

def raw_integer_fields(event)
  event.fetch("rawFields").each_with_object({}) do |field, result|
    result[field.fetch("fieldNumber")] = field.fetch("integerValue")
  end
end

def target_count(key, events)
  case key
  when "scrollWheel"
    events.count { |event| event[:type] == 22 }
  when "scrollCompanion"
    events.count { |event| event[:type] == 29 && event[:classifier] == 6 }
  when "rawType30"
    events.count { |event| event[:type] == 30 }
  when "magnificationCandidate"
    events.count { |event| event[:type] == 29 && event[:classifier] == 8 }
  when "gestureEnvelope"
    events.count { |event| event[:type] == 29 && event[:classifier] == 4 }
  when "dockSwipeCandidate"
    events.count { |event| event[:type] == 29 && event[:classifier] == 32 }
  else
    raise VerificationFailure, "未対応のtarget countです。key=#{key}"
  end
end

def pair_scroll_companions(scroll_events, companion_events, scenario_id, rule)
  require_contract(rule.fetch("preserveOrder"), "scroll companion対応は順序保存である必要があります。")
  require_contract(rule.fetch("phaseMustMatch"), "scroll companion対応はphase一致が必要です。")
  require_contract(rule.fetch("unmatchedScrollAllowed"), "余分なscroll sampleを許可する規則が必要です。")
  require_contract(
    rule.fetch("candidateSelection") == "minimum-absolute-timestamp-difference-then-capture-index-distance",
    "未対応のscroll companion候補選択規則です。"
  )
  maximum_distance = rule.fetch("maximumCaptureIndexDistance")
  previous_scroll_position = -1
  companion_events.map do |companion|
    candidates = []
    scroll_events.each_with_index do |scroll, position|
      next unless position > previous_scroll_position
      next unless scroll[:phase] == companion[:phase]
      next unless (scroll[:capture_index] - companion[:capture_index]).abs <= maximum_distance

      candidates << [scroll, position]
    end
    require_contract(
      !candidates.empty?,
      "scroll companionの対応候補がありません。scenario=#{scenario_id} captureIndex=#{companion[:capture_index]}"
    )
    scroll, position = candidates.min_by do |candidate|
      event = candidate.fetch(0)
      [
        (event[:timestamp] - companion[:timestamp]).abs,
        (event[:capture_index] - companion[:capture_index]).abs
      ]
    end
    previous_scroll_position = position
    [scroll, companion]
  end
end

repo_root = File.expand_path("..", __dir__)
options = {
  fixture: File.join(repo_root, "Fixtures/trackpad-contract/25F80/physical-observations.json"),
  capture_dir: File.join(repo_root, "artifacts/trackpad-contract/2026-07-11-b50e607"),
  legacy_dir: File.join(repo_root, "artifacts/trackpad-contract/2026-07-11-bfb9b8a"),
  json: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/verify-trackpad-physical-observations.rb [options]"
  parser.on("--fixture PATH", "公開fixture path") { |value| options[:fixture] = value }
  parser.on("--capture-dir PATH", "schema 2 raw capture directory") do |value|
    options[:capture_dir] = value
  end
  parser.on("--legacy-dir PATH", "legacy discovery capture directory") do |value|
    options[:legacy_dir] = value
  end
  parser.on("--json", "検証結果をJSONで出力") { options[:json] = true }
end.parse!

begin
  fixture = JSON.parse(File.read(options.fetch(:fixture)))
  common_contract = fixture.fetch("observedContracts").fetch("common")
  scroll_contract = fixture.fetch("observedContracts").fetch("scroll")
  companion_contract = fixture.fetch("observedContracts").fetch("scrollCompanion")
  capture_results = []
  scroll_pairs = []

  fixture.fetch("captures").each do |capture|
    scenario_id = capture.fetch("scenarioID")
    source_path = File.join(options.fetch(:capture_dir), capture.fetch("sourceFile"))
    manifest_path = "#{source_path}.manifest.json"
    require_contract(File.file?(source_path), "raw captureがありません。path=#{source_path}")
    require_contract(File.file?(manifest_path), "capture manifestがありません。path=#{manifest_path}")

    source_sha = Digest::SHA256.file(source_path).hexdigest
    require_contract(
      source_sha == capture.fetch("sourceLogSHA256"),
      "source SHAがfixtureと一致しません。scenario=#{scenario_id}"
    )
    manifest = JSON.parse(File.read(manifest_path))
    require_contract(manifest.fetch("schemaVersion") == 2, "manifest schemaが2ではありません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("evidenceKind") == "physicalTrackpad", "物理証跡ではありません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("logSHA256") == source_sha, "manifest SHAが一致しません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("logByteCount") == File.size(source_path), "manifest byte数が一致しません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("scenarioID") == scenario_id, "manifest scenarioが一致しません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("osVersion") == fixture.fetch("osVersion"), "OS versionが一致しません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("osBuild") == fixture.fetch("osBuild"), "OS buildが一致しません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("deviceLabel") == fixture.fetch("deviceLabel"), "device labelが一致しません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("repoHeadSHA") == fixture.fetch("loggerRepoHeadSHA"), "repo HEADが一致しません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("loggerExecutableSHA256") == fixture.fetch("loggerExecutableSHA256"), "logger SHAが一致しません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("captureStartedAt") == capture.fetch("captureStartedAt"), "capture開始時刻が一致しません。scenario=#{scenario_id}")
    require_contract(manifest.fetch("captureCompletedAt") == capture.fetch("captureCompletedAt"), "capture完了時刻が一致しません。scenario=#{scenario_id}")

    events = []
    first_key_capture_index = nil
    generated_marker_count = 0
    File.foreach(source_path).with_index do |line, line_index|
      event = JSON.parse(line)
      capture_index = event.fetch("captureIndex")
      require_contract(capture_index == line_index, "captureIndexがline順ではありません。scenario=#{scenario_id} line=#{line_index + 1}")
      metadata = event.fetch("metadata")
      require_contract(metadata.fetch("scenarioID") == scenario_id, "event scenarioが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")
      require_contract(metadata.fetch("osBuild") == fixture.fetch("osBuild"), "event OS buildが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")
      require_contract(metadata.fetch("repoHeadSHA") == fixture.fetch("loggerRepoHeadSHA"), "event repo HEADが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")
      require_contract(event.fetch("rawFields").length == 256, "raw fieldが256件ではありません。scenario=#{scenario_id} captureIndex=#{capture_index}")
      raw = raw_integer_fields(event)
      require_contract(raw.fetch(common_contract.fetch("typeRawField")) == event.fetch("typeRaw"), "raw typeが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")
      require_contract(raw.fetch(common_contract.fetch("timestampRawField")) == event.fetch("timestamp"), "raw timestampが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")
      generated_marker_count += 1 if event.fetch("sourceUserData") == GENERATED_EVENT_MARKER
      first_key_capture_index ||= capture_index if KEY_EVENT_TYPES.include?(event.fetch("typeRaw"))
      events << {
        capture_index: capture_index,
        timestamp: event.fetch("timestamp"),
        type: event.fetch("typeRaw"),
        classifier: raw[fixture.fetch("privateClassifierRawField")],
        scroll_phase: raw[scroll_contract.fetch("scrollPhaseRawField")],
        momentum_phase: raw[scroll_contract.fetch("momentumPhaseRawField")],
        companion_phase: raw[companion_contract.fetch("phaseRawField")],
        continuous: raw[scroll_contract.fetch("continuousRawField")],
        named_deltas: [
          event.fetch("scrollDeltaX"),
          event.fetch("scrollDeltaY"),
          event.fetch("scrollDeltaZ")
        ]
      }
    rescue JSON::ParserError => error
      raise VerificationFailure, "raw capture JSONをdecodeできません。scenario=#{scenario_id} line=#{line_index + 1} details=#{error.message}"
    end

    require_contract(events.length == capture.fetch("sourceEventCount"), "source event数がfixtureと一致しません。scenario=#{scenario_id}")
    require_contract(events.length == manifest.fetch("eventCount"), "manifest event数が一致しません。scenario=#{scenario_id}")
    require_contract(generated_marker_count.zero?, "physicalTrackpadへ生成markerが混在しています。scenario=#{scenario_id}")
    prefix_count = capture.fetch("contractPrefixEventCount")
    expected_prefix_count = first_key_capture_index || events.length
    require_contract(prefix_count == expected_prefix_count, "keyboard境界prefixが一致しません。scenario=#{scenario_id} expected=#{expected_prefix_count} actual=#{prefix_count}")
    prefix_events = events.first(prefix_count)
    capture.fetch("targetCounts").each do |key, expected_count|
      actual_count = target_count(key, prefix_events)
      require_contract(actual_count == expected_count, "target件数が一致しません。scenario=#{scenario_id} target=#{key} expected=#{expected_count} actual=#{actual_count}")
    end

    if capture.key?("observedRawType30Terminals")
      terminal_counts = {
        "ended" => prefix_events.count { |event| event[:type] == 30 && event[:companion_phase] == 4 },
        "cancelled" => prefix_events.count { |event| event[:type] == 30 && event[:companion_phase] == 8 }
      }
      require_contract(
        terminal_counts == capture.fetch("observedRawType30Terminals"),
        "raw type 30 terminal件数が一致しません。scenario=#{scenario_id}"
      )
    end

    if SCROLL_SCENARIOS.include?(scenario_id)
      scroll_events = prefix_events.select do |event|
        event[:type] == scroll_contract.fetch("eventTypeRaw")
      end
      scroll_events.each do |event|
        require_contract(
          event[:continuous] == scroll_contract.fetch("continuousValue"),
          "scroll continuous値が一致しません。scenario=#{scenario_id} captureIndex=#{event[:capture_index]}"
        )
        if event[:momentum_phase] == scroll_contract.fetch("momentumTerminalValue")
          require_contract(
            event[:named_deltas].all?(&:zero?),
            "momentum terminalのnamed deltaが0ではありません。scenario=#{scenario_id} captureIndex=#{event[:capture_index]}"
          )
        end
      end
      companion_events = prefix_events.select do |event|
        event[:type] == companion_contract.fetch("eventTypeRaw") &&
          event[:classifier] == companion_contract.fetch("classifierValue")
      end
      companion_events.each do |companion|
        envelope_index = companion.fetch(:capture_index) - 1
        envelope = envelope_index >= 0 ? prefix_events[envelope_index] : nil
        require_contract(
          envelope &&
            envelope[:type] == companion_contract.fetch("eventTypeRaw") &&
            envelope[:classifier] == companion_contract.fetch("envelopeClassifierValue") &&
            envelope[:timestamp] == companion[:timestamp],
          "scroll companion直前のenvelopeが一致しません。scenario=#{scenario_id} captureIndex=#{companion[:capture_index]}"
        )
      end
      pairable_scroll_events = scroll_events.select do |event|
        [1, 2, 4, 128].include?(event[:scroll_phase])
      end.map do |event|
        event.merge(phase: event.fetch(:scroll_phase))
      end
      pairable_companion_events = companion_events.map do |event|
        event.merge(phase: event.fetch(:companion_phase))
      end
      scroll_pairs.concat(
        pair_scroll_companions(
          pairable_scroll_events,
          pairable_companion_events,
          scenario_id,
          companion_contract.fetch("associationRule")
        )
      )
    end

    capture_results << {
      scenarioID: scenario_id,
      sourceLogSHA256: source_sha,
      eventCount: events.length,
      contractPrefixEventCount: prefix_count,
      generatedMarkerCount: generated_marker_count
    }
  end

  require_contract(
    scroll_pairs.length == companion_contract.fetch("pairedSampleCount"),
    "scroll companion pair件数がfixtureと一致しません。expected=#{companion_contract.fetch("pairedSampleCount")} actual=#{scroll_pairs.length}"
  )
  pair_deltas = scroll_pairs.map do |scroll, companion|
    companion.fetch(:capture_index) - scroll.fetch(:capture_index)
  end.uniq.sort
  require_contract(
    pair_deltas == companion_contract.fetch("captureIndexDeltaValues"),
    "scroll companion captureIndex差が一致しません。expected=#{companion_contract.fetch("captureIndexDeltaValues")} actual=#{pair_deltas}"
  )
  timestamps_equal = scroll_pairs.any? do |scroll, companion|
    scroll.fetch(:timestamp) == companion.fetch(:timestamp)
  end
  require_contract(
    timestamps_equal == companion_contract.fetch("timestampEqualToScrollWheel"),
    "scroll companion timestamp同値判定が一致しません。expected=#{companion_contract.fetch("timestampEqualToScrollWheel")} actual=#{timestamps_equal}"
  )

  legacy = fixture.fetch("legacyDiscovery")
  legacy_path = File.join(options.fetch(:legacy_dir), legacy.fetch("sourceFile"))
  legacy_manifest_path = "#{legacy_path}.manifest.json"
  require_contract(File.file?(legacy_path), "legacy raw captureがありません。path=#{legacy_path}")
  require_contract(File.file?(legacy_manifest_path), "legacy manifestがありません。path=#{legacy_manifest_path}")
  require_contract(Digest::SHA256.file(legacy_path).hexdigest == legacy.fetch("sourceLogSHA256"), "legacy source SHAが一致しません。")
  legacy_manifest = JSON.parse(File.read(legacy_manifest_path))
  require_contract(legacy_manifest.fetch("schemaVersion") == 1, "legacy manifest schemaが1ではありません。")
  require_contract(!legacy_manifest.key?("captureStartedAt"), "legacy manifestに開始wall-clockが存在します。")
  require_contract(legacy_manifest.fetch("scenarioID") == legacy.fetch("scenarioID"), "legacy manifest scenarioが一致しません。")
  legacy_phase_counts = Hash.new(0)
  legacy_type31_count = 0
  legacy_event_count = 0
  File.foreach(legacy_path) do |line|
    event = JSON.parse(line)
    require_contract(
      event.fetch("metadata").fetch("scenarioID") == legacy.fetch("scenarioID"),
      "legacy raw event scenarioが一致しません。captureIndex=#{event.fetch("captureIndex")}"
    )
    legacy_event_count += 1
    next unless event.fetch("typeRaw") == 31

    legacy_type31_count += 1
    phase = raw_integer_fields(event).fetch(common_contract.fetch("phaseRawField"))
    legacy_phase_counts[phase] += 1
  end
  require_contract(legacy_event_count == legacy.fetch("sourceEventCount"), "legacy event数が一致しません。")
  require_contract(legacy_type31_count == legacy.fetch("rawType31Count"), "legacy type 31件数が一致しません。")
  expected_legacy_phases = legacy.fetch("rawType31PhaseCounts")
  actual_legacy_phases = {
    "began" => legacy_phase_counts[1],
    "changed" => legacy_phase_counts[2],
    "ended" => legacy_phase_counts[4],
    "cancelled" => legacy_phase_counts[8]
  }
  require_contract(actual_legacy_phases == expected_legacy_phases, "legacy type 31 phase件数が一致しません。")

  result = {
    passed: true,
    fixture: options.fetch(:fixture),
    captureDirectory: options.fetch(:capture_dir),
    captures: capture_results,
    scrollCompanion: {
      pairedSampleCount: scroll_pairs.length,
      captureIndexDeltaValues: pair_deltas,
      timestampEqualToScrollWheel: timestamps_equal
    },
    legacyDiscovery: {
      sourceLogSHA256: legacy.fetch("sourceLogSHA256"),
      eventCount: legacy_event_count,
      rawType31Count: legacy_type31_count,
      phaseCounts: actual_legacy_phases
    }
  }
  if options.fetch(:json)
    puts JSON.pretty_generate(result)
  else
    puts "物理trackpad観測fixtureの原本照合に成功しました。"
    puts "captures=#{capture_results.length} scrollCompanionPairs=#{scroll_pairs.length} legacyEvents=#{legacy_event_count}"
  end
rescue VerificationFailure, Errno::ENOENT, JSON::ParserError, KeyError => error
  warn "物理trackpad観測fixtureの原本照合に失敗しました: #{error.message}"
  exit 1
end
