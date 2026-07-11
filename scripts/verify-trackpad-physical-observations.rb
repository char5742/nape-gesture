#!/usr/bin/env ruby

require "digest"
require "json"
require "optparse"

GENERATED_EVENT_MARKER = 0x4D_47_53_54
KEY_EVENT_TYPES = [10, 11, 12].freeze
PHYSICAL_OBSERVATION_FIXTURE_ID = "trackpad-physical-observations-25F80-v1"
SCROLL_MOMENTUM_FIXTURE_ID = "trackpad-scroll-momentum-25F80-v1"
SCROLL_MOMENTUM_CONTRACT_ID = "trackpad-scroll-momentum-v1"
SCROLL_MOMENTUM_FIXTURE_SHA256 = "8e2a1841ef23a47fcb274c1c8e7c7c39be43e8ab7c8792caf2cd874242a61294"
NAMED_SCROLL_DELTA_KEYS = %w[
  scrollDeltaX
  scrollDeltaY
  scrollDeltaZ
  scrollFixedDeltaX
  scrollFixedDeltaY
  scrollFixedDeltaZ
  scrollPointDeltaX
  scrollPointDeltaY
  scrollPointDeltaZ
].freeze
INTEGER_SCROLL_DELTA_KEYS = NAMED_SCROLL_DELTA_KEYS.first(3).freeze
DOUBLE_SCROLL_DELTA_KEYS = NAMED_SCROLL_DELTA_KEYS.drop(3).freeze
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

def indexed_raw_fields(event)
  event.fetch("rawFields").each_with_object({}) do |field, result|
    result[field.fetch("fieldNumber")] = field
  end
end

def raw_integer_fields(raw_fields)
  raw_fields.each_with_object({}) do |(field_number, field), result|
    result[field_number] = field.fetch("integerValue")
  end
end

def float32_bit_pattern(double_bit_pattern)
  double_value = [double_bit_pattern].pack("Q>").unpack1("G")
  [double_value].pack("g").unpack1("L>")
end

def float64_bit_pattern(value)
  [value].pack("G").unpack1("Q>")
end

def require_motion_field_contract(raw_fields, double_fields, float_bit_fields, axis, scenario_id, capture_index)
  double_values = double_fields.map { |field| raw_fields.fetch(field).fetch("doubleValue") }
  double_bit_patterns = double_fields.map do |field|
    raw_fields.fetch(field).fetch("doubleBitPattern")
  end
  require_contract(
    double_values.uniq.length == 1 && double_bit_patterns.uniq.length == 1,
    "scroll companionの#{axis} motion double fieldが同値ではありません。scenario=#{scenario_id} captureIndex=#{capture_index}"
  )

  expected_float_bits = float32_bit_pattern(double_bit_patterns.fetch(0))
  float_bit_fields.each do |field|
    require_contract(
      raw_fields.fetch(field).fetch("integerValue") == expected_float_bits,
      "scroll companionの#{axis} motion Float32 bit aliasが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index} field=#{field}"
    )
  end
end

def invalid_positive_zero_delta_fields(event)
  invalid_integers = INTEGER_SCROLL_DELTA_KEYS.reject do |key|
    event.fetch(:named_deltas).fetch(key) == 0
  end
  invalid_doubles = DOUBLE_SCROLL_DELTA_KEYS.reject do |key|
    value = event.fetch(:named_deltas).fetch(key)
    recorded_bit_pattern = event.fetch(:named_delta_bit_patterns).fetch(key)
    value.zero? && recorded_bit_pattern.zero? && float64_bit_pattern(value).zero?
  end
  invalid_integers + invalid_doubles
end

def verify_positive_zero_detector
  named_deltas = NAMED_SCROLL_DELTA_KEYS.to_h do |key|
    [key, INTEGER_SCROLL_DELTA_KEYS.include?(key) ? 0 : 0.0]
  end
  bit_patterns = DOUBLE_SCROLL_DELTA_KEYS.to_h { |key| [key, 0] }
  positive = {
    named_deltas: named_deltas,
    named_delta_bit_patterns: bit_patterns
  }
  require_contract(invalid_positive_zero_delta_fields(positive).empty?, "+0.0 detectorの自己検証に失敗しました。")

  negative = {
    named_deltas: named_deltas.merge("scrollPointDeltaY" => -0.0),
    named_delta_bit_patterns: bit_patterns.merge(
      "scrollPointDeltaY" => float64_bit_pattern(-0.0)
    )
  }
  require_contract(
    invalid_positive_zero_delta_fields(negative).include?("scrollPointDeltaY"),
    "-0.0 detectorの自己検証に失敗しました。"
  )
end

def source_capture_identity(capture)
  %w[
    sourceFile
    sourceLogSHA256
    sourceEventCount
    contractPrefixEventCount
    analysisStartCaptureIndex
    captureStartedAt
    captureCompletedAt
  ].to_h { |field| [field, capture.fetch(field)] }
end

def verify_dedicated_contract_fixture(fixture, contract, contract_sha256)
  observed = fixture.fetch("observedContracts")
  observed_scroll = observed.fetch("scroll")
  observed_companion = observed.fetch("scrollCompanion")
  contract_scroll = contract.fetch("scroll")
  contract_momentum = contract.fetch("momentum")
  contract_companion = contract.fetch("scrollCompanion")

  require_contract(contract_sha256 == SCROLL_MOMENTUM_FIXTURE_SHA256, "専用contract fixture SHAがregistry固定値と一致しません。")
  require_contract(contract.fetch("fixtureID") == SCROLL_MOMENTUM_FIXTURE_ID, "専用contract fixture IDが一致しません。")
  require_contract(contract.fetch("contractID") == SCROLL_MOMENTUM_CONTRACT_ID, "専用contract IDが一致しません。")
  require_contract(contract.fetch("status") == "confirmed" && contract.fetch("scope") == "scroll-momentum", "専用contractの確定scopeが不正です。")
  require_contract(observed.fetch("scrollMomentumContractID") == contract.fetch("contractID"), "観測台帳と専用contractのIDが一致しません。")
  require_contract(contract.fetch("osVersion") == fixture.fetch("osVersion") && contract.fetch("osBuild") == fixture.fetch("osBuild"), "観測台帳と専用contractのOS identityが一致しません。")
  require_contract(contract.fetch("referenceDeviceLabel") == fixture.fetch("deviceLabel"), "観測台帳と専用contractのdevice labelが一致しません。")
  require_contract(contract.dig("referenceLogger", "repoHeadSHA") == fixture.fetch("loggerRepoHeadSHA"), "観測台帳と専用contractのlogger repo SHAが一致しません。")
  require_contract(contract.dig("referenceLogger", "executableSHA256") == fixture.fetch("loggerExecutableSHA256"), "観測台帳と専用contractのlogger executable SHAが一致しません。")

  usable_sources = fixture.fetch("captures").select { |capture| capture.fetch("status") == "usable" }
  observed_sources = usable_sources.to_h do |capture|
    [capture.fetch("scenarioID"), source_capture_identity(capture)]
  end
  contract_sources = contract.fetch("sourceCaptures").to_h do |capture|
    [capture.fetch("scenarioID"), source_capture_identity(capture)]
  end
  require_contract(observed_sources == contract_sources, "専用contractの4 source identityまたは解析境界が観測台帳と一致しません。")
  require_contract(contract.fetch("supportedScenarioIDs").sort == observed_sources.keys.sort, "専用contractのsupported scenarioが採用sourceと一致しません。")

  require_contract(contract.fetch("common") == observed.fetch("common").slice("typeRawField", "timestampRawField"), "専用contractのcommon raw fieldが観測契約と一致しません。")
  require_contract(contract_scroll.fetch("eventTypeRaw") == observed_scroll.fetch("eventTypeRaw"), "専用contractのscroll event typeが観測契約と一致しません。")
  require_contract(contract_scroll.fetch("continuousRawField") == observed_scroll.fetch("continuousRawField") && contract_scroll.fetch("continuousValue") == observed_scroll.fetch("continuousValue"), "専用contractのcontinuous fieldが観測契約と一致しません。")
  require_contract(contract_scroll.fetch("phaseRawField") == observed_scroll.fetch("scrollPhaseRawField"), "専用contractのscroll phase fieldが観測契約と一致しません。")
  require_contract(contract_scroll.fetch("phaseValues").values.sort == observed_scroll.fetch("scrollPhaseValues").sort, "専用contractのscroll phase値が観測契約と一致しません。")
  require_contract(contract_momentum.fetch("phaseRawField") == observed_scroll.fetch("momentumPhaseRawField"), "専用contractのmomentum phase fieldが観測契約と一致しません。")
  require_contract(contract_momentum.fetch("phaseValues").values.sort == observed_scroll.fetch("momentumPhaseValues").sort, "専用contractのmomentum phase値が観測契約と一致しません。")
  require_contract(contract_momentum.dig("phaseValues", "ended") == observed_scroll.fetch("momentumTerminalValue"), "専用contractのmomentum terminalが観測契約と一致しません。")

  %w[eventTypeRaw classifierRawField classifierValue envelopeClassifierValue phaseRawField xMotionDoubleFields xMotionFloatBitFields yMotionDoubleFields yMotionFloatBitFields constantRawFields].each do |field|
    require_contract(contract_companion.fetch(field) == observed_companion.fetch(field), "専用contractのscroll companion #{field}が観測契約と一致しません。")
  end
  observed_rule = observed_companion.fetch("associationRule")
  %w[preserveOrder phaseMustMatch maximumCaptureIndexDistance candidateSelection unmatchedScrollAllowed requiredMatchedScrollPhaseValues allowedUnmatchedScrollPhaseValues minimumPairingCoverage].each do |field|
    require_contract(contract_companion.fetch("associationRule").fetch(field) == observed_rule.fetch(field), "専用contractのassociation rule #{field}が観測契約と一致しません。")
  end
  statistics = contract_companion.fetch("referenceStatistics")
  require_contract(statistics.fetch("pairedSampleCount") == observed_companion.fetch("pairedSampleCount"), "専用contractのpaired sample数が観測契約と一致しません。")
  require_contract(statistics.fetch("pairableScrollSampleCount") == observed_companion.fetch("pairableScrollSampleCount"), "専用contractのpairable scroll数が観測契約と一致しません。")
  require_contract(statistics.fetch("captureIndexDeltaValues") == observed_companion.fetch("captureIndexDeltaValues"), "専用contractのcaptureIndex差が観測契約と一致しません。")
  require_contract(statistics.fetch("anyTimestampEqualToScrollWheel") == observed_companion.fetch("timestampEqualToScrollWheel"), "専用contractのtimestamp統計が観測契約と一致しません。")

  require_contract(contract_scroll.fetch("terminalNamedDeltasRequirePositiveZero") == observed_scroll.fetch("scrollTerminalHasZeroNamedDelta"), "専用contractのscroll terminal zero契約が観測契約と一致しません。")
  require_contract(contract_momentum.fetch("terminalNamedDeltasRequirePositiveZero") == observed_scroll.fetch("momentumTerminalHasZeroNamedDelta"), "専用contractのmomentum terminal zero契約が観測契約と一致しません。")
  require_contract(contract_momentum.fetch("scrollAndMomentumPhasesAreMutuallyExclusive") == observed_scroll.fetch("phasesMutuallyExclusive"), "専用contractのphase排他契約が観測契約と一致しません。")
  require_contract(contract_momentum.fetch("beginsAfterScrollEnded") == observed_scroll.fetch("momentumStartsAfterScrollTerminal"), "専用contractのmomentum開始契約が観測契約と一致しません。")
end

# 物理captureだけは記録開始前のpartial系列を除外する。generated candidateではこの例外を使わない。
def derive_physical_capture_lifecycles(
  events,
  phase_key,
  began_value,
  changed_value,
  terminal_value,
  idle_phase_values,
  scenario_id,
  lifecycle_name
)
  lifecycles = []
  active_lifecycle = nil
  began_observed = false

  events.each do |event|
    phase = event.fetch(phase_key)
    next if phase.zero?

    unless began_observed
      next unless phase == began_value

      began_observed = true
      active_lifecycle = [event]
      next
    end

    case phase
    when began_value
      require_contract(
        active_lifecycle.nil?,
        "#{lifecycle_name} lifecycleのterminal前に次のbeganが現れました。scenario=#{scenario_id} captureIndex=#{event[:capture_index]}"
      )
      active_lifecycle = [event]
    when changed_value
      require_contract(
        !active_lifecycle.nil?,
        "#{lifecycle_name} lifecycleにbeganなしのchangedがあります。scenario=#{scenario_id} captureIndex=#{event[:capture_index]}"
      )
      active_lifecycle << event
    when terminal_value
      require_contract(
        !active_lifecycle.nil?,
        "#{lifecycle_name} lifecycleにbeganなしのterminalがあります。scenario=#{scenario_id} captureIndex=#{event[:capture_index]}"
      )
      active_lifecycle << event
      lifecycles << active_lifecycle
      active_lifecycle = nil
    else
      require_contract(
        active_lifecycle.nil? && idle_phase_values.include?(phase),
        "#{lifecycle_name} lifecycleに不正なphaseがあります。scenario=#{scenario_id} captureIndex=#{event[:capture_index]} phase=#{phase}"
      )
    end
  end

  require_contract(
    active_lifecycle.nil?,
    "#{lifecycle_name} lifecycleがterminalなしで終了しました。scenario=#{scenario_id} beganCaptureIndex=#{active_lifecycle&.first&.fetch(:capture_index)}"
  )
  lifecycles
end

def require_nondecreasing_lifecycle_timestamps(lifecycles, scenario_id, lifecycle_name)
  lifecycles.each do |lifecycle|
    lifecycle.each_cons(2) do |previous, current|
      require_contract(
        previous.fetch(:timestamp) <= current.fetch(:timestamp),
        "#{lifecycle_name} lifecycle内でtype 22 timestampが逆行しました。scenario=#{scenario_id} previousCaptureIndex=#{previous[:capture_index]} captureIndex=#{current[:capture_index]}"
      )
    end
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
  contract: File.join(repo_root, "Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json"),
  capture_dir: File.join(repo_root, "artifacts/trackpad-contract/2026-07-11-b50e607"),
  legacy_dir: File.join(repo_root, "artifacts/trackpad-contract/2026-07-11-bfb9b8a"),
  fixtures_only: false,
  json: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/verify-trackpad-physical-observations.rb [options]"
  parser.on("--fixture PATH", "公開fixture path") { |value| options[:fixture] = value }
  parser.on("--contract PATH", "専用scroll / momentum contract fixture path") { |value| options[:contract] = value }
  parser.on("--capture-dir PATH", "schema 2 raw capture directory") do |value|
    options[:capture_dir] = value
  end
  parser.on("--legacy-dir PATH", "legacy discovery capture directory") do |value|
    options[:legacy_dir] = value
  end
  parser.on("--fixtures-only", "公開fixture間のidentityと契約だけを検証") { options[:fixtures_only] = true }
  parser.on("--json", "検証結果をJSONで出力") { options[:json] = true }
end.parse!

begin
  verify_positive_zero_detector
  fixture = JSON.parse(File.read(options.fetch(:fixture)))
  contract_bytes = File.binread(options.fetch(:contract))
  contract = JSON.parse(contract_bytes)
  contract_sha256 = Digest::SHA256.hexdigest(contract_bytes)
  verify_dedicated_contract_fixture(fixture, contract, contract_sha256)
  if options.fetch(:fixtures_only)
    result = {
      passed: true,
      fixture: options.fetch(:fixture),
      contract: options.fetch(:contract),
      contractSHA256: contract_sha256,
      sourceCaptureCount: contract.fetch("sourceCaptures").length
    }
    puts(options.fetch(:json) ? JSON.pretty_generate(result) : "公開fixture間のcontract identity照合に成功しました。")
    exit 0
  end
  observed_contracts = fixture.fetch("observedContracts")
  common_contract = observed_contracts.fetch("common")
  scroll_contract = observed_contracts.fetch("scroll")
  companion_contract = observed_contracts.fetch("scrollCompanion")
  association_rule = companion_contract.fetch("associationRule")
  common_phase_values = common_contract.fetch("phaseValues")
  scroll_terminal_value = common_phase_values.fetch("ended")
  required_matched_scroll_phases = association_rule.fetch("requiredMatchedScrollPhaseValues")
  allowed_unmatched_scroll_phases = association_rule.fetch("allowedUnmatchedScrollPhaseValues")
  pairable_scroll_phases = (required_matched_scroll_phases + allowed_unmatched_scroll_phases).uniq
  minimum_pairing_coverage = association_rule.fetch("minimumPairingCoverage")
  minimum_paired = minimum_pairing_coverage.fetch("paired")
  minimum_pairable_scroll = minimum_pairing_coverage.fetch("pairableScroll")

  require_contract(
    fixture.fetch("fixtureID") == PHYSICAL_OBSERVATION_FIXTURE_ID,
    "物理観測fixture IDが一致しません。"
  )
  require_contract(
    observed_contracts.fetch("scrollMomentumContractID") == SCROLL_MOMENTUM_CONTRACT_ID,
    "scroll / momentum contract IDが一致しません。"
  )
  %w[
    scrollTerminalHasZeroNamedDelta
    momentumTerminalHasZeroNamedDelta
    phasesMutuallyExclusive
    momentumStartsAfterScrollTerminal
    requiresScrollLifecycle
    requiresMomentumLifecycle
    type22TimestampNondecreasingWithinLifecycle
  ].each do |field|
    require_contract(scroll_contract.fetch(field) == true, "scroll contractの#{field}がtrueではありません。")
  end
  require_contract(
    (required_matched_scroll_phases & allowed_unmatched_scroll_phases).empty?,
    "必須対応phaseと未対応許可phaseが重複しています。"
  )
  require_contract(
    pairable_scroll_phases.sort == scroll_contract.fetch("scrollPhaseValues").sort,
    "scroll companionの対応phase集合がscroll phase集合と一致しません。"
  )
  require_contract(
    minimum_paired.positive? && minimum_pairable_scroll.positive? && minimum_paired <= minimum_pairable_scroll,
    "scroll companionのminimum pairing coverageが不正です。"
  )
  capture_results = []
  scroll_pairs = []
  pairable_scroll_sample_count = 0
  pairing_coverage_results = []
  lifecycle_results = []

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
      raw_fields = indexed_raw_fields(event)
      raw = raw_integer_fields(raw_fields)
      event_type = event.fetch("typeRaw")
      classifier = raw[fixture.fetch("privateClassifierRawField")]
      require_contract(raw.fetch(common_contract.fetch("typeRawField")) == event_type, "raw typeが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")
      require_contract(raw.fetch(common_contract.fetch("timestampRawField")) == event.fetch("timestamp"), "raw timestampが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")
      generated_marker_count += 1 if event.fetch("sourceUserData") == GENERATED_EVENT_MARKER
      first_key_capture_index ||= capture_index if KEY_EVENT_TYPES.include?(event_type)
      named_deltas = if event_type == scroll_contract.fetch("eventTypeRaw")
                       NAMED_SCROLL_DELTA_KEYS.each_with_object({}) do |key, result|
                         result[key] = event.fetch(key)
                       end
                     else
                       {}
                     end
      named_delta_bit_patterns = if event_type == scroll_contract.fetch("eventTypeRaw")
                                   DOUBLE_SCROLL_DELTA_KEYS.to_h do |key|
                                     [key, event.fetch("#{key}BitPattern")]
                                   end
                                 else
                                   {}
                                 end
      events << {
        capture_index: capture_index,
        timestamp: event.fetch("timestamp"),
        type: event_type,
        classifier: classifier,
        scroll_phase: raw[scroll_contract.fetch("scrollPhaseRawField")],
        momentum_phase: raw[scroll_contract.fetch("momentumPhaseRawField")],
        companion_phase: raw[companion_contract.fetch("phaseRawField")],
        continuous: raw[scroll_contract.fetch("continuousRawField")],
        named_deltas: named_deltas,
        named_delta_bit_patterns: named_delta_bit_patterns,
        raw_fields: event_type == companion_contract.fetch("eventTypeRaw") &&
          classifier == companion_contract.fetch("classifierValue") ? raw_fields : nil
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
      allowed_scroll_phase_values = ([0] + scroll_contract.fetch("scrollPhaseValues")).uniq
      allowed_momentum_phase_values = scroll_contract.fetch("momentumPhaseValues")
      scroll_events.each_with_index do |event, scroll_index|
        require_contract(
          event[:continuous] == scroll_contract.fetch("continuousValue"),
          "scroll continuous値が一致しません。scenario=#{scenario_id} captureIndex=#{event[:capture_index]}"
        )
        require_contract(
          allowed_scroll_phase_values.include?(event[:scroll_phase]),
          "未知のscroll phaseです。scenario=#{scenario_id} captureIndex=#{event[:capture_index]} phase=#{event[:scroll_phase]}"
        )
        require_contract(
          allowed_momentum_phase_values.include?(event[:momentum_phase]),
          "未知のmomentum phaseです。scenario=#{scenario_id} captureIndex=#{event[:capture_index]} phase=#{event[:momentum_phase]}"
        )
        require_contract(
          event[:scroll_phase].zero? || event[:momentum_phase].zero?,
          "type 22のscroll phaseとmomentum phaseが同時にactiveです。scenario=#{scenario_id} captureIndex=#{event[:capture_index]}"
        )
        if event[:scroll_phase] == scroll_terminal_value
          invalid_deltas = invalid_positive_zero_delta_fields(event)
          require_contract(
            invalid_deltas.empty?,
            "scroll terminalのnamed delta 9種が正のzeroではありません。scenario=#{scenario_id} captureIndex=#{event[:capture_index]} fields=#{invalid_deltas.join(",")}"
          )
        end
        if event[:momentum_phase] == scroll_contract.fetch("momentumTerminalValue")
          invalid_deltas = invalid_positive_zero_delta_fields(event)
          require_contract(
            invalid_deltas.empty?,
            "momentum terminalのnamed delta 9種が正のzeroではありません。scenario=#{scenario_id} captureIndex=#{event[:capture_index]} fields=#{invalid_deltas.join(",")}"
          )
        end
        if event[:momentum_phase] == common_phase_values.fetch("began")
          previous_type22 = scroll_index.positive? ? scroll_events[scroll_index - 1] : nil
          require_contract(
            previous_type22 && previous_type22[:scroll_phase] == scroll_terminal_value,
            "momentum began直前のtype 22がscroll terminalではありません。scenario=#{scenario_id} captureIndex=#{event[:capture_index]}"
          )
        end
      end

      scroll_lifecycles = derive_physical_capture_lifecycles(
        scroll_events,
        :scroll_phase,
        common_phase_values.fetch("began"),
        common_phase_values.fetch("changed"),
        scroll_terminal_value,
        [common_phase_values.fetch("mayBegin")],
        scenario_id,
        "scroll"
      )
      momentum_lifecycles = derive_physical_capture_lifecycles(
        scroll_events,
        :momentum_phase,
        common_phase_values.fetch("began"),
        common_phase_values.fetch("changed"),
        scroll_contract.fetch("momentumTerminalValue"),
        [],
        scenario_id,
        "momentum"
      )
      require_contract(
        !scroll_lifecycles.empty?,
        "完結したscroll lifecycleがありません。scenario=#{scenario_id}"
      )
      require_contract(
        !momentum_lifecycles.empty?,
        "完結したmomentum lifecycleがありません。scenario=#{scenario_id}"
      )
      require_nondecreasing_lifecycle_timestamps(scroll_lifecycles, scenario_id, "scroll")
      require_nondecreasing_lifecycle_timestamps(momentum_lifecycles, scenario_id, "momentum")
      lifecycle_results << {
        scenarioID: scenario_id,
        scrollLifecycleCount: scroll_lifecycles.length,
        momentumLifecycleCount: momentum_lifecycles.length
      }

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
        raw_fields = companion.fetch(:raw_fields)
        require_motion_field_contract(
          raw_fields,
          companion_contract.fetch("xMotionDoubleFields"),
          companion_contract.fetch("xMotionFloatBitFields"),
          "x",
          scenario_id,
          companion.fetch(:capture_index)
        )
        require_motion_field_contract(
          raw_fields,
          companion_contract.fetch("yMotionDoubleFields"),
          companion_contract.fetch("yMotionFloatBitFields"),
          "y",
          scenario_id,
          companion.fetch(:capture_index)
        )
        companion_contract.fetch("constantRawFields").each do |field_number, expected_value|
          field = Integer(field_number)
          require_contract(
            raw_fields.fetch(field).fetch("integerValue") == expected_value,
            "scroll companionのconstant raw fieldが一致しません。scenario=#{scenario_id} captureIndex=#{companion[:capture_index]} field=#{field}"
          )
        end
      end
      pairable_scroll_events = scroll_events.select do |event|
        pairable_scroll_phases.include?(event[:scroll_phase])
      end.map do |event|
        event.merge(phase: event.fetch(:scroll_phase))
      end
      pairable_companion_events = companion_events.map do |event|
        event.merge(phase: event.fetch(:companion_phase))
      end
      scenario_pairs = pair_scroll_companions(
        pairable_scroll_events,
        pairable_companion_events,
        scenario_id,
        association_rule
      )
      paired_capture_indices = scenario_pairs.each_with_object({}) do |(scroll, _companion), result|
        result[scroll.fetch(:capture_index)] = true
      end
      unmatched_scroll_events = pairable_scroll_events.reject do |event|
        paired_capture_indices.key?(event.fetch(:capture_index))
      end
      unmatched_phase_values = unmatched_scroll_events.map { |event| event.fetch(:phase) }.uniq.sort
      required_matched_scroll_phases.each do |phase|
        require_contract(
          unmatched_scroll_events.none? { |event| event.fetch(:phase) == phase },
          "必須対応scroll phaseに未対応sampleがあります。scenario=#{scenario_id} phase=#{phase}"
        )
      end
      unmatched_phase_values.each do |phase|
        require_contract(
          allowed_unmatched_scroll_phases.include?(phase),
          "未対応scroll sampleに許可外phaseがあります。scenario=#{scenario_id} phase=#{phase}"
        )
      end
      require_contract(
        !pairable_scroll_events.empty? &&
          scenario_pairs.length * minimum_pairable_scroll >= pairable_scroll_events.length * minimum_paired,
        "scroll companionのpair coverageが下限未満です。scenario=#{scenario_id} paired=#{scenario_pairs.length} pairableScroll=#{pairable_scroll_events.length}"
      )
      pairable_scroll_sample_count += pairable_scroll_events.length
      scroll_pairs.concat(scenario_pairs)
      pairing_coverage_results << {
        scenarioID: scenario_id,
        pairedSampleCount: scenario_pairs.length,
        pairableScrollSampleCount: pairable_scroll_events.length,
        unmatchedScrollPhaseValues: unmatched_phase_values
      }
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
    lifecycle_results.map { |result| result.fetch(:scenarioID) }.sort == SCROLL_SCENARIOS.sort,
    "4つのscroll scenarioすべてをlifecycle検証できませんでした。"
  )
  require_contract(
    pairable_scroll_sample_count == companion_contract.fetch("pairableScrollSampleCount"),
    "pairable scroll件数がfixtureと一致しません。expected=#{companion_contract.fetch("pairableScrollSampleCount")} actual=#{pairable_scroll_sample_count}"
  )
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
    phase = raw_integer_fields(indexed_raw_fields(event)).fetch(common_contract.fetch("phaseRawField"))
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
    scrollMomentum: {
      lifecycleByScenario: lifecycle_results,
      type22TimestampNondecreasingWithinLifecycle: true
    },
    scrollCompanion: {
      pairableScrollSampleCount: pairable_scroll_sample_count,
      pairedSampleCount: scroll_pairs.length,
      pairingCoverageByScenario: pairing_coverage_results,
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
    puts "captures=#{capture_results.length} pairableScroll=#{pairable_scroll_sample_count} scrollCompanionPairs=#{scroll_pairs.length} legacyEvents=#{legacy_event_count}"
  end
rescue VerificationFailure, Errno::ENOENT, JSON::ParserError, KeyError, ArgumentError => error
  warn "物理trackpad観測fixtureの原本照合に失敗しました: #{error.message}"
  exit 1
end
