#!/usr/bin/env ruby

require "digest"
require "json"
require "optparse"
require "set"

REPO_ROOT = File.expand_path("..", __dir__)
DEFAULT_CONTRACT_PATH = File.join(
  REPO_ROOT,
  "Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json"
)
DEFAULT_CAPTURE_DIRECTORY = File.join(
  REPO_ROOT,
  "artifacts/trackpad-contract/2026-07-11-b50e607"
)
DEFAULT_SAMPLES_PATH = File.join(
  REPO_ROOT,
  "Fixtures/trackpad-contract/25F80/scroll-output-model-samples.json"
)
EXPECTED_CONTRACT_SHA256 = "8e2a1841ef23a47fcb274c1c8e7c7c39be43e8ab7c8792caf2cd874242a61294"
EXPECTED_FIXTURE_ID = "trackpad-scroll-momentum-25F80-v1"
EXPECTED_CONTRACT_ID = "trackpad-scroll-momentum-v1"
EXPECTED_SAMPLES_SHA256 = "d88d513c01e0f0360716d697fc41bb7c7913b5f2dc45825fb817713000da1381"
EXPECTED_SAMPLES_FIXTURE_ID = "trackpad-scroll-output-model-samples-25F80-v1"
EXPECTED_SAMPLE_SET_ID = "trackpad-scroll-output-model-samples-v1"
EXPECTED_ASSOCIATION_RULE_SHA256 = "312bce76a960bac7b13c5b2c7b7161edfb6dd69ae2de86f577b4491c6369a7ab"
EXPECTED_SOURCE_FILES = %w[
  vertical-scroll.jsonl
  horizontal-scroll.jsonl
  momentum-stop.jsonl
  cancel-reverse.jsonl
].freeze
EXPECTED_ANALYSIS_PAIRING = {
  "pure-trackpad-vertical-scroll" => {
    referencePairableScrollSampleCount: 252,
    referencePairedSampleCount: 250,
    analysisPairableScrollSampleCount: 252,
    analysisPairedSampleCount: 250,
    referenceTerminalPairCount: 3,
    analysisTerminalPairCount: 3
  },
  "pure-trackpad-horizontal-scroll" => {
    referencePairableScrollSampleCount: 392,
    referencePairedSampleCount: 390,
    analysisPairableScrollSampleCount: 212,
    analysisPairedSampleCount: 211,
    referenceTerminalPairCount: 4,
    analysisTerminalPairCount: 3
  },
  "pure-trackpad-momentum-stop" => {
    referencePairableScrollSampleCount: 30,
    referencePairedSampleCount: 29,
    analysisPairableScrollSampleCount: 30,
    analysisPairedSampleCount: 29,
    referenceTerminalPairCount: 5,
    analysisTerminalPairCount: 5
  },
  "pure-trackpad-cancel-reverse" => {
    referencePairableScrollSampleCount: 498,
    referencePairedSampleCount: 496,
    analysisPairableScrollSampleCount: 498,
    analysisPairedSampleCount: 496,
    referenceTerminalPairCount: 8,
    analysisTerminalPairCount: 8
  }
}.freeze
EXPECTED_ANALYSIS_TOTALS = {
  pairableScrollSampleCount: 992,
  pairedSampleCount: 986,
  terminalPairCount: 19,
  modelSampleCount: 967
}.freeze
EXPECTED_ZERO_COUNTS = {
  "x" => {
    gestureToLine: [180, 0, 501, 286],
    gestureToFixed: [180, 0, 501, 286],
    gestureToPoint: [141, 39, 0, 787]
  },
  "y" => {
    gestureToLine: [74, 0, 289, 604],
    gestureToFixed: [74, 0, 289, 604],
    gestureToPoint: [50, 24, 0, 893]
  }
}.freeze
AXES = {
  "x" => {
    line: "scrollDeltaX",
    fixed: "scrollFixedDeltaX",
    point: "scrollPointDeltaX",
    gestureDoubleField: 113
  },
  "y" => {
    line: "scrollDeltaY",
    fixed: "scrollFixedDeltaY",
    point: "scrollPointDeltaY",
    gestureDoubleField: 119
  }
}.freeze
INTEGER_DELTA_KEYS = %w[scrollDeltaX scrollDeltaY scrollDeltaZ].freeze
DOUBLE_DELTA_KEYS = %w[
  scrollFixedDeltaX
  scrollFixedDeltaY
  scrollFixedDeltaZ
  scrollPointDeltaX
  scrollPointDeltaY
  scrollPointDeltaZ
].freeze

class DerivationFailure < StandardError; end

class StrictJSONObject < Hash
  def []=(key, value)
    raise DerivationFailure, "JSON object keyが重複しています。key=#{key}" if key?(key)

    super
  end
end

def require_derivation(condition, message)
  raise DerivationFailure, message unless condition
end

def display_path(path)
  expanded = File.expand_path(path)
  prefix = "#{REPO_ROOT}/"
  expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : expanded
end

def parse_json_strict(bytes, label)
  JSON.parse(bytes, object_class: StrictJSONObject, create_additions: false)
rescue JSON::ParserError => error
  raise DerivationFailure, "#{label}をdecodeできません。details=#{error.message}"
end

def require_exact_keys(object, expected_keys, label)
  require_derivation(object.is_a?(Hash), "JSON objectではありません。field=#{label}")
  actual_keys = object.keys
  missing_keys = expected_keys - actual_keys
  unknown_keys = actual_keys - expected_keys
  require_derivation(
    missing_keys.empty? && unknown_keys.empty?,
    "JSON key集合が一致しません。field=#{label} missing=#{missing_keys} unknown=#{unknown_keys}"
  )
end

def require_integer(value, label)
  require_derivation(value.instance_of?(Integer), "JSON integerではありません。field=#{label}")
  value
end

def require_finite_float(value, label)
  require_derivation(value.instance_of?(Float) && value.finite?, "有限なJSON floatではありません。field=#{label}")
  value
end

def lossless_json_equal?(expected, actual)
  case expected
  when Float
    actual.instance_of?(Float) && float64_bit_pattern(expected) == float64_bit_pattern(actual)
  when Hash
    actual.is_a?(Hash) && expected.keys == actual.keys && expected.all? do |key, value|
      lossless_json_equal?(value, actual.fetch(key))
    end
  when Array
    actual.is_a?(Array) && expected.length == actual.length && expected.zip(actual).all? do |left, right|
      lossless_json_equal?(left, right)
    end
  else
    expected.eql?(actual)
  end
end

def indexed_raw_fields(event, scenario_id, capture_index)
  fields = event.fetch("rawFields")
  require_derivation(
    fields.length == 256,
    "raw field数が256ではありません。scenario=#{scenario_id} captureIndex=#{capture_index}"
  )
  indexed = fields.each_with_object({}) do |field, result|
    field_number = field.fetch("fieldNumber")
    require_derivation(
      !result.key?(field_number),
      "raw field番号が重複しています。scenario=#{scenario_id} captureIndex=#{capture_index} field=#{field_number}"
    )
    result[field_number] = field
  end
  require_derivation(
    indexed.keys.sort == (0...256).to_a,
    "raw field番号が0...255を網羅していません。scenario=#{scenario_id} captureIndex=#{capture_index}"
  )
  indexed
end

def float64_bit_pattern(value)
  [value].pack("G").unpack1("Q>")
end

def float32_bit_pattern(double_bit_pattern)
  double_value = [double_bit_pattern].pack("Q>").unpack1("G")
  [double_value].pack("g").unpack1("L>")
end

def finite_number(value, label)
  numeric = Float(value)
  require_derivation(numeric.finite?, "有限値ではありません。field=#{label}")
  numeric
end

def validate_named_delta_bits(event, scenario_id, capture_index)
  DOUBLE_DELTA_KEYS.each do |key|
    value = finite_number(event.fetch(key), key)
    recorded = event.fetch("#{key}BitPattern")
    require_derivation(
      recorded == float64_bit_pattern(value),
      "named deltaのbit patternが値と一致しません。scenario=#{scenario_id} captureIndex=#{capture_index} field=#{key}"
    )
  end
end

def validate_positive_zero_terminal(event, scenario_id, capture_index)
  INTEGER_DELTA_KEYS.each do |key|
    require_derivation(
      event.fetch(key) == 0,
      "terminalのinteger deltaがzeroではありません。scenario=#{scenario_id} captureIndex=#{capture_index} field=#{key}"
    )
  end
  DOUBLE_DELTA_KEYS.each do |key|
    value = finite_number(event.fetch(key), key)
    require_derivation(
      value.zero? && event.fetch("#{key}BitPattern").zero? && float64_bit_pattern(value).zero?,
      "terminalのdouble deltaが正のzeroではありません。scenario=#{scenario_id} captureIndex=#{capture_index} field=#{key}"
    )
  end
end

def validate_motion_fields(raw_fields, double_fields, float_fields, axis, scenario_id, capture_index)
  double_values = double_fields.map do |field_number|
    finite_number(raw_fields.fetch(field_number).fetch("doubleValue"), "raw#{field_number}")
  end
  double_bits = double_fields.map do |field_number|
    raw_fields.fetch(field_number).fetch("doubleBitPattern")
  end
  require_derivation(
    double_values.uniq.length == 1 && double_bits.uniq.length == 1,
    "companionの#{axis} motion double aliasが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}"
  )
  expected_float_bits = float32_bit_pattern(double_bits.fetch(0))
  float_fields.each do |field_number|
    require_derivation(
      raw_fields.fetch(field_number).fetch("integerValue") == expected_float_bits,
      "companionの#{axis} motion Float32 aliasが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index} field=#{field_number}"
    )
  end
  [double_bits.fetch(0)].pack("Q>").unpack1("G")
end

def validate_contract(contract, contract_sha256)
  require_derivation(
    contract_sha256 == EXPECTED_CONTRACT_SHA256,
    "contract SHAが固定値と一致しません。expected=#{EXPECTED_CONTRACT_SHA256} actual=#{contract_sha256}"
  )
  require_derivation(contract.fetch("schemaVersion") == 1, "contract schemaが1ではありません。")
  require_derivation(contract.fetch("fixtureID") == EXPECTED_FIXTURE_ID, "contract fixture IDが一致しません。")
  require_derivation(contract.fetch("contractID") == EXPECTED_CONTRACT_ID, "contract IDが一致しません。")
  require_derivation(
    contract.fetch("status") == "confirmed" && contract.fetch("scope") == "scroll-momentum",
    "contractのstatusまたはscopeが不正です。"
  )

  sources = contract.fetch("sourceCaptures")
  require_derivation(sources.length == 4, "source captureが4件ではありません。")
  require_derivation(
    sources.map { |source| source.fetch("sourceFile") }.sort == EXPECTED_SOURCE_FILES.sort,
    "source captureの4ファイルが一致しません。"
  )
  scenario_ids = sources.map { |source| source.fetch("scenarioID") }
  require_derivation(scenario_ids.uniq.length == sources.length, "source scenario IDが重複しています。")
  require_derivation(
    contract.fetch("supportedScenarioIDs").sort == scenario_ids.sort,
    "supported scenario IDがsource captureと一致しません。"
  )

  common = contract.fetch("common")
  scroll = contract.fetch("scroll")
  companion = contract.fetch("scrollCompanion")
  rule = companion.fetch("associationRule")
  require_derivation(common.fetch("typeRawField") == 55, "type raw fieldが55ではありません。")
  require_derivation(common.fetch("timestampRawField") == 58, "timestamp raw fieldが58ではありません。")
  require_derivation(scroll.fetch("eventTypeRaw") == 22, "scroll event typeが22ではありません。")
  require_derivation(companion.fetch("eventTypeRaw") == 29, "companion event typeが29ではありません。")
  require_derivation(companion.fetch("classifierValue") == 6, "companion classifierが6ではありません。")
  require_derivation(rule.fetch("preserveOrder") == true, "pair規則が順序保存ではありません。")
  require_derivation(rule.fetch("phaseMustMatch") == true, "pair規則がphase一致ではありません。")
  require_derivation(rule.fetch("unmatchedCompanionAllowed") == false, "未対応companionを許可しています。")
  require_derivation(rule.fetch("unmatchedScrollAllowed") == true, "未対応scrollを許可していません。")
  require_derivation(
    rule.fetch("candidateSelection") == "minimum-absolute-timestamp-difference-then-capture-index-distance",
    "未対応のpair候補選択規則です。"
  )
  require_derivation(rule.fetch("maximumCaptureIndexDistance").positive?, "pair距離上限が正ではありません。")

  required_phases = rule.fetch("requiredMatchedScrollPhaseValues")
  allowed_unmatched = rule.fetch("allowedUnmatchedScrollPhaseValues")
  phase_values = scroll.fetch("phaseValues").values
  require_derivation((required_phases & allowed_unmatched).empty?, "必須phaseと未対応許可phaseが重複しています。")
  require_derivation(
    (required_phases + allowed_unmatched).uniq.sort == phase_values.sort,
    "pair対象phase集合がscroll phase集合と一致しません。"
  )
end

def load_capture(source, contract, capture_directory)
  scenario_id = source.fetch("scenarioID")
  source_path = File.join(capture_directory, source.fetch("sourceFile"))
  require_derivation(File.file?(source_path), "raw captureがありません。path=#{source_path}")
  source_sha256 = Digest::SHA256.file(source_path).hexdigest
  require_derivation(
    source_sha256 == source.fetch("sourceLogSHA256"),
    "source SHAがcontractと一致しません。scenario=#{scenario_id}"
  )

  prefix_count = source.fetch("contractPrefixEventCount")
  analysis_start = source.fetch("analysisStartCaptureIndex")
  require_derivation(
    analysis_start >= 0 && analysis_start < prefix_count && prefix_count <= source.fetch("sourceEventCount"),
    "sourceの解析境界が不正です。scenario=#{scenario_id}"
  )

  common = contract.fetch("common")
  scroll_contract = contract.fetch("scroll")
  companion_contract = contract.fetch("scrollCompanion")
  phase_values = scroll_contract.fetch("phaseValues").values.to_set
  scroll_events = []
  companion_events = []
  event_count = 0
  previous_prefix_event = nil

  File.foreach(source_path).with_index do |line, line_index|
    require_derivation(!line.strip.empty?, "空のJSONL行があります。scenario=#{scenario_id} line=#{line_index + 1}")
    event = JSON.parse(line)
    capture_index = event.fetch("captureIndex")
    require_derivation(
      capture_index == line_index,
      "captureIndexがline順ではありません。scenario=#{scenario_id} line=#{line_index + 1}"
    )
    metadata = event.fetch("metadata")
    require_derivation(metadata.fetch("scenarioID") == scenario_id, "event scenarioが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")
    require_derivation(metadata.fetch("osBuild") == contract.fetch("osBuild"), "event OS buildが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")
    require_derivation(metadata.fetch("repoHeadSHA") == contract.dig("referenceLogger", "repoHeadSHA"), "event repo SHAが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}")

    raw_fields = indexed_raw_fields(event, scenario_id, capture_index)
    event_type = event.fetch("typeRaw")
    timestamp = event.fetch("timestamp")
    require_derivation(
      raw_fields.fetch(common.fetch("typeRawField")).fetch("integerValue") == event_type,
      "raw typeがtop-levelと一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}"
    )
    require_derivation(
      raw_fields.fetch(common.fetch("timestampRawField")).fetch("integerValue") == timestamp,
      "raw timestampがtop-levelと一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}"
    )

    if capture_index < prefix_count
      classifier = raw_fields.fetch(companion_contract.fetch("classifierRawField")).fetch("integerValue")
      if event_type == scroll_contract.fetch("eventTypeRaw")
        phase = raw_fields.fetch(scroll_contract.fetch("phaseRawField")).fetch("integerValue")
        if phase_values.include?(phase)
          validate_named_delta_bits(event, scenario_id, capture_index)
          validate_positive_zero_terminal(event, scenario_id, capture_index) if phase == scroll_contract.dig("phaseValues", "ended")
          scroll_events << {
            captureIndex: capture_index,
            timestamp: timestamp,
            phase: phase,
            line: {
              "x" => event.fetch("scrollDeltaX"),
              "y" => event.fetch("scrollDeltaY")
            },
            fixed: {
              "x" => finite_number(event.fetch("scrollFixedDeltaX"), "scrollFixedDeltaX"),
              "y" => finite_number(event.fetch("scrollFixedDeltaY"), "scrollFixedDeltaY")
            },
            point: {
              "x" => finite_number(event.fetch("scrollPointDeltaX"), "scrollPointDeltaX"),
              "y" => finite_number(event.fetch("scrollPointDeltaY"), "scrollPointDeltaY")
            }
          }
        end
      elsif event_type == companion_contract.fetch("eventTypeRaw") && classifier == companion_contract.fetch("classifierValue")
        require_derivation(
          previous_prefix_event &&
            previous_prefix_event.fetch(:captureIndex) == capture_index - 1 &&
            previous_prefix_event.fetch(:eventType) == companion_contract.fetch("eventTypeRaw") &&
            previous_prefix_event.fetch(:classifier) == companion_contract.fetch("envelopeClassifierValue") &&
            previous_prefix_event.fetch(:timestamp) == timestamp,
          "companion直前の同timestamp envelopeが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index}"
        )
        x_motion = validate_motion_fields(
          raw_fields,
          companion_contract.fetch("xMotionDoubleFields"),
          companion_contract.fetch("xMotionFloatBitFields"),
          "x",
          scenario_id,
          capture_index
        )
        y_motion = validate_motion_fields(
          raw_fields,
          companion_contract.fetch("yMotionDoubleFields"),
          companion_contract.fetch("yMotionFloatBitFields"),
          "y",
          scenario_id,
          capture_index
        )
        companion_contract.fetch("constantRawFields").each do |field_text, expected|
          actual = raw_fields.fetch(Integer(field_text)).fetch("integerValue")
          require_derivation(
            actual == expected,
            "companion constant fieldが一致しません。scenario=#{scenario_id} captureIndex=#{capture_index} field=#{field_text}"
          )
        end
        companion_events << {
          captureIndex: capture_index,
          timestamp: timestamp,
          phase: raw_fields.fetch(companion_contract.fetch("phaseRawField")).fetch("integerValue"),
          gesture: {"x" => x_motion, "y" => y_motion}
        }
      end
      previous_prefix_event = {
        captureIndex: capture_index,
        timestamp: timestamp,
        eventType: event_type,
        classifier: classifier
      }
    end
    event_count += 1
  rescue JSON::ParserError => error
    raise DerivationFailure, "raw capture JSONをdecodeできません。scenario=#{scenario_id} line=#{line_index + 1} details=#{error.message}"
  end

  require_derivation(
    event_count == source.fetch("sourceEventCount"),
    "source event数がcontractと一致しません。scenario=#{scenario_id} expected=#{source.fetch("sourceEventCount")} actual=#{event_count}"
  )
  {
    sourceSHA256: source_sha256,
    scrollEvents: scroll_events,
    companionEvents: companion_events,
    analysisScrollEvents: scroll_events.select { |event| event.fetch(:captureIndex) >= analysis_start },
    analysisCompanionEvents: companion_events.select { |event| event.fetch(:captureIndex) >= analysis_start }
  }
end

def pair_scroll_companions(scroll_events, companion_events, scenario_id, rule, label)
  maximum_distance = rule.fetch("maximumCaptureIndexDistance")
  previous_scroll_position = -1
  matched_positions = Set.new
  pairs = companion_events.map do |companion|
    candidates = []
    scroll_events.each_with_index do |scroll, position|
      next unless position > previous_scroll_position
      next unless scroll.fetch(:phase) == companion.fetch(:phase)
      next unless (scroll.fetch(:captureIndex) - companion.fetch(:captureIndex)).abs <= maximum_distance

      candidates << [scroll, position]
    end
    require_derivation(
      !candidates.empty?,
      "companionのpair候補がありません。range=#{label} scenario=#{scenario_id} captureIndex=#{companion.fetch(:captureIndex)}"
    )
    # Swift analyzerと同じくtimestamp差、captureIndex距離の順で最小を選び、完全同値では先行候補を保持する。
    scroll, position = candidates.min_by do |candidate|
      event = candidate.fetch(0)
      [
        (event.fetch(:timestamp) - companion.fetch(:timestamp)).abs,
        (event.fetch(:captureIndex) - companion.fetch(:captureIndex)).abs
      ]
    end
    previous_scroll_position = position
    matched_positions.add(position)
    {scenarioID: scenario_id, scroll: scroll, companion: companion}
  end

  required_phases = rule.fetch("requiredMatchedScrollPhaseValues").to_set
  allowed_unmatched = rule.fetch("allowedUnmatchedScrollPhaseValues").to_set
  scroll_events.each_with_index do |scroll, position|
    next if matched_positions.include?(position)

    phase = scroll.fetch(:phase)
    require_derivation(
      !required_phases.include?(phase) && allowed_unmatched.include?(phase),
      "未対応scrollに許可外phaseがあります。range=#{label} scenario=#{scenario_id} captureIndex=#{scroll.fetch(:captureIndex)} phase=#{phase}"
    )
  end

  coverage = rule.fetch("minimumPairingCoverage")
  require_derivation(
    !scroll_events.empty? && pairs.length * coverage.fetch("pairableScroll") >= scroll_events.length * coverage.fetch("paired"),
    "pair coverageが下限未満です。range=#{label} scenario=#{scenario_id} paired=#{pairs.length} pairableScroll=#{scroll_events.length}"
  )
  pairs
end

def phase_counts(pairs)
  counts = Hash.new(0)
  pairs.each { |pair| counts[pair.fetch(:scroll).fetch(:phase).to_s] += 1 }
  counts.keys.sort_by(&:to_i).each_with_object({}) { |key, result| result[key] = counts.fetch(key) }
end

def pairing_statistics(pairable_count, pairs, terminal_phase)
  deltas = pairs.map do |pair|
    pair.fetch(:companion).fetch(:captureIndex) - pair.fetch(:scroll).fetch(:captureIndex)
  end
  {
    pairableScrollSampleCount: pairable_count,
    pairedSampleCount: pairs.length,
    unmatchedScrollSampleCount: pairable_count - pairs.length,
    terminalPairCount: pairs.count { |pair| pair.fetch(:scroll).fetch(:phase) == terminal_phase },
    phaseCounts: phase_counts(pairs),
    captureIndexDeltaValues: deltas.uniq.sort,
    equalTimestampPairCount: pairs.count do |pair|
      pair.fetch(:scroll).fetch(:timestamp) == pair.fetch(:companion).fetch(:timestamp)
    end
  }
end

def zero_counts(rows, input_key, output_key)
  counts = [0, 0, 0, 0]
  rows.each do |row|
    input_zero = row.fetch(input_key).zero?
    output_zero = row.fetch(output_key).zero?
    index = if input_zero && output_zero
              0
            elsif input_zero
              1
            elsif output_zero
              2
            else
              3
            end
    counts[index] += 1
  end
  {
    inputZeroOutputZero: counts.fetch(0),
    inputZeroOutputNonzero: counts.fetch(1),
    inputNonzeroOutputZero: counts.fetch(2),
    inputNonzeroOutputNonzero: counts.fetch(3)
  }
end

def zero_count_array(counts)
  %i[
    inputZeroOutputZero
    inputZeroOutputNonzero
    inputNonzeroOutputZero
    inputNonzeroOutputNonzero
  ].map { |key| counts.fetch(key) }
end

def validate_relation_signs(rows, input_key, output_key, axis, relation)
  invalid = rows.count do |row|
    input = row.fetch(input_key)
    output = row.fetch(output_key)
    !input.zero? && !output.zero? && (input <=> 0) != (output <=> 0)
  end
  require_derivation(
    invalid.zero?,
    "単調対称modelと矛盾する符号sampleがあります。axis=#{axis} relation=#{relation} count=#{invalid}"
  )
end

def error_metrics(actual_and_predicted)
  errors = actual_and_predicted.map { |actual, predicted| actual - predicted }
  {
    rmse: Math.sqrt(errors.inject(0.0) { |sum, error| sum + error * error } / errors.length),
    maxAbsoluteError: errors.map(&:abs).max
  }
end

def round_half_away_from_zero(value)
  return 0 if value.zero?

  (value <=> 0) * (value.abs + 0.5).floor
end

def odd_quadratic_model(rows, output_key, axis, relation, quantize: false)
  input_key = :gesture
  validate_relation_signs(rows, input_key, output_key, axis, relation)
  sum_linear_squared = 0.0
  sum_linear_quadratic = 0.0
  sum_quadratic_squared = 0.0
  sum_linear_output = 0.0
  sum_quadratic_output = 0.0
  rows.each do |row|
    input = row.fetch(input_key)
    output = row.fetch(output_key)
    odd_quadratic = input * input.abs
    sum_linear_squared += input * input
    sum_linear_quadratic += input * odd_quadratic
    sum_quadratic_squared += odd_quadratic * odd_quadratic
    sum_linear_output += input * output
    sum_quadratic_output += odd_quadratic * output
  end

  determinant = sum_linear_squared * sum_quadratic_squared -
    sum_linear_quadratic * sum_linear_quadratic
  require_derivation(determinant.positive?, "二次modelの正規方程式が退化しています。axis=#{axis} relation=#{relation}")
  linear_coefficient = (
    sum_linear_output * sum_quadratic_squared -
      sum_quadratic_output * sum_linear_quadratic
  ) / determinant
  quadratic_coefficient = (
    sum_linear_squared * sum_quadratic_output -
      sum_linear_quadratic * sum_linear_output
  ) / determinant
  require_derivation(
    linear_coefficient.finite? && linear_coefficient.positive? &&
      quadratic_coefficient.finite? && quadratic_coefficient >= 0,
    "二次modelが全域で単調な対称関数になりません。axis=#{axis} relation=#{relation} linear=#{linear_coefficient} quadratic=#{quadratic_coefficient}"
  )

  continuous_predictions = rows.map do |row|
    input = row.fetch(input_key)
    prediction = if input.zero?
                   0.0
                 else
                   linear_coefficient * input + quadratic_coefficient * input * input.abs
                 end
    [row.fetch(output_key), prediction]
  end
  emitted_predictions = if quantize
                          continuous_predictions.map do |actual, prediction|
                            [actual, round_half_away_from_zero(prediction)]
                          end
                        else
                          continuous_predictions
                        end
  model = {
    kind: quantize ? "odd-quadratic-least-squares-with-symmetric-rounding" : "odd-quadratic-least-squares",
    formula: "continuous = linearCoefficient * gesture + quadraticCoefficient * gesture * abs(gesture)",
    coefficientFit: "ordinary-least-squares-with-zero-intercept",
    linearCoefficient: linear_coefficient,
    quadraticCoefficient: quadratic_coefficient,
    sampleCount: rows.length,
    informativeInputSampleCount: rows.count { |row| !row.fetch(input_key).zero? },
    zeroCounts: zero_counts(rows, input_key, output_key)
  }
  if quantize
    continuous_metrics = error_metrics(continuous_predictions)
    model[:output] = "roundHalfAwayFromZero(continuous)"
    model[:quantization] = "round-half-away-from-zero"
    model[:continuousFitRMSE] = continuous_metrics.fetch(:rmse)
    model[:continuousFitMaxAbsoluteError] = continuous_metrics.fetch(:maxAbsoluteError)
  end
  model.merge(error_metrics(emitted_predictions))
end

def verify_expected_zero_counts(axis, models)
  expected = EXPECTED_ZERO_COUNTS.fetch(axis)
  expected.each do |relation, expected_counts|
    actual_counts = zero_count_array(models.fetch(relation).fetch(:zeroCounts))
    require_derivation(
      actual_counts == expected_counts,
      "zero分類件数が固定観測と一致しません。axis=#{axis} relation=#{relation} expected=#{expected_counts} actual=#{actual_counts}"
    )
  end
end

def derive_raw_dataset(contract, capture_directory)
  companion_contract = contract.fetch("scrollCompanion")
  rule = companion_contract.fetch("associationRule")
  terminal_phase = contract.dig("scroll", "phaseValues", "ended")
  source_results = []
  reference_pairs = []
  analysis_pairs = []
  reference_pairable_count = 0
  analysis_pairable_count = 0

  contract.fetch("sourceCaptures").each do |source|
    scenario_id = source.fetch("scenarioID")
    capture = load_capture(source, contract, capture_directory)
    scenario_reference_pairs = pair_scroll_companions(
      capture.fetch(:scrollEvents),
      capture.fetch(:companionEvents),
      scenario_id,
      rule,
      "contract-prefix"
    )
    scenario_analysis_pairs = pair_scroll_companions(
      capture.fetch(:analysisScrollEvents),
      capture.fetch(:analysisCompanionEvents),
      scenario_id,
      rule,
      "analyzer-window"
    )
    observed_counts = {
      referencePairableScrollSampleCount: capture.fetch(:scrollEvents).length,
      referencePairedSampleCount: scenario_reference_pairs.length,
      analysisPairableScrollSampleCount: capture.fetch(:analysisScrollEvents).length,
      analysisPairedSampleCount: scenario_analysis_pairs.length,
      referenceTerminalPairCount: scenario_reference_pairs.count { |pair| pair.fetch(:scroll).fetch(:phase) == terminal_phase },
      analysisTerminalPairCount: scenario_analysis_pairs.count { |pair| pair.fetch(:scroll).fetch(:phase) == terminal_phase }
    }
    require_derivation(
      observed_counts == EXPECTED_ANALYSIS_PAIRING.fetch(scenario_id),
      "scenario別pair件数が固定観測と一致しません。scenario=#{scenario_id} expected=#{EXPECTED_ANALYSIS_PAIRING.fetch(scenario_id)} actual=#{observed_counts}"
    )

    reference_pairable_count += capture.fetch(:scrollEvents).length
    analysis_pairable_count += capture.fetch(:analysisScrollEvents).length
    reference_pairs.concat(scenario_reference_pairs)
    analysis_pairs.concat(scenario_analysis_pairs)
    source_results << source.merge(
      "referencePairableScrollSampleCount" => observed_counts.fetch(:referencePairableScrollSampleCount),
      "referencePairedSampleCount" => observed_counts.fetch(:referencePairedSampleCount),
      "analysisPairableScrollSampleCount" => observed_counts.fetch(:analysisPairableScrollSampleCount),
      "analysisPairedSampleCount" => observed_counts.fetch(:analysisPairedSampleCount),
      "referenceTerminalPairCount" => observed_counts.fetch(:referenceTerminalPairCount),
      "analysisTerminalPairCount" => observed_counts.fetch(:analysisTerminalPairCount)
    )
  end

  reference_statistics = pairing_statistics(reference_pairable_count, reference_pairs, terminal_phase)
  contract_reference = companion_contract.fetch("referenceStatistics")
  require_derivation(
    reference_statistics.fetch(:pairableScrollSampleCount) == contract_reference.fetch("pairableScrollSampleCount") &&
      reference_statistics.fetch(:pairedSampleCount) == contract_reference.fetch("pairedSampleCount") &&
      reference_statistics.fetch(:captureIndexDeltaValues) == contract_reference.fetch("captureIndexDeltaValues") &&
      (reference_statistics.fetch(:equalTimestampPairCount).positive? == contract_reference.fetch("anyTimestampEqualToScrollWheel")),
    "contract prefixのpair統計がreferenceStatisticsと一致しません。"
  )

  analysis_statistics = pairing_statistics(analysis_pairable_count, analysis_pairs, terminal_phase)
  EXPECTED_ANALYSIS_TOTALS.each do |key, expected|
    actual = if key == :modelSampleCount
               analysis_statistics.fetch(:pairedSampleCount) - analysis_statistics.fetch(:terminalPairCount)
             else
               analysis_statistics.fetch(key)
             end
    require_derivation(
      actual == expected,
      "analyzer解析窓の件数が固定観測と一致しません。field=#{key} expected=#{expected} actual=#{actual}"
    )
  end
  require_derivation(
    analysis_statistics.fetch(:captureIndexDeltaValues) == contract_reference.fetch("captureIndexDeltaValues") &&
      analysis_statistics.fetch(:equalTimestampPairCount).zero?,
    "analyzer解析窓のpair差分またはtimestamp同値件数が固定観測と一致しません。"
  )

  model_pairs = analysis_pairs.reject do |pair|
    pair.fetch(:scroll).fetch(:phase) == terminal_phase
  end

  {
    sourceResults: source_results,
    referencePairs: reference_pairs,
    analysisPairs: analysis_pairs,
    referenceStatistics: reference_statistics,
    analysisStatistics: analysis_statistics,
    modelPairs: model_pairs
  }
end

def expected_source_contract(contract, contract_sha256)
  {
    "path" => display_path(DEFAULT_CONTRACT_PATH),
    "sha256" => contract_sha256,
    "fixtureID" => contract.fetch("fixtureID"),
    "contractID" => contract.fetch("contractID")
  }
end

def expected_derivation
  {
    "script" => "scripts/derive-trackpad-scroll-output-model.rb",
    "captureDirectory" => display_path(DEFAULT_CAPTURE_DIRECTORY),
    "referenceSelection" => "captureIndex < contractPrefixEventCount",
    "modelSelection" => "analysisStartCaptureIndex <= captureIndex < contractPrefixEventCount",
    "terminalSelection" => "scroll phase != ended",
    "coefficientFit" => "odd-quadratic ordinary-least-squares with zero intercept",
    "zeroPolicy" => "retain all nonterminal zero observations in error metrics and map zero input to positive zero"
  }
end

def association_rule_identity(contract)
  rule = contract.fetch("scrollCompanion").fetch("associationRule")
  {
    "sourceContractJSONPointer" => "/scrollCompanion/associationRule",
    "orderedJSONSHA256" => Digest::SHA256.hexdigest(JSON.generate(rule))
  }
end

def sample_records(model_pairs)
  model_pairs.each_with_index.map do |pair, index|
    scroll = pair.fetch(:scroll)
    companion = pair.fetch(:companion)
    {
      "sampleIndex" => index,
      "scenarioID" => pair.fetch(:scenarioID),
      "scrollCaptureIndex" => scroll.fetch(:captureIndex),
      "companionCaptureIndex" => companion.fetch(:captureIndex),
      "phase" => scroll.fetch(:phase),
      "gestureX" => companion.fetch(:gesture).fetch("x"),
      "gestureY" => companion.fetch(:gesture).fetch("y"),
      "lineX" => scroll.fetch(:line).fetch("x"),
      "lineY" => scroll.fetch(:line).fetch("y"),
      "fixedX" => scroll.fetch(:fixed).fetch("x"),
      "fixedY" => scroll.fetch(:fixed).fetch("y"),
      "pointX" => scroll.fetch(:point).fetch("x"),
      "pointY" => scroll.fetch(:point).fetch("y")
    }
  end
end

def build_samples_fixture(contract, contract_sha256, raw_dataset)
  model_pairs = raw_dataset.fetch(:modelPairs)
  {
    "schemaVersion" => 1,
    "fixtureID" => EXPECTED_SAMPLES_FIXTURE_ID,
    "sampleSetID" => EXPECTED_SAMPLE_SET_ID,
    "osVersion" => contract.fetch("osVersion"),
    "osBuild" => contract.fetch("osBuild"),
    "referenceDeviceLabel" => contract.fetch("referenceDeviceLabel"),
    "sourceContract" => expected_source_contract(contract, contract_sha256),
    "derivation" => expected_derivation,
    "sourceCaptures" => raw_dataset.fetch(:sourceResults),
    "associationRuleIdentity" => association_rule_identity(contract),
    "pairingStatistics" => {
      "contractPrefix" => raw_dataset.fetch(:referenceStatistics),
      "analyzerWindow" => raw_dataset.fetch(:analysisStatistics).merge(
        excludedBeforeAnalysisStartPairCount: raw_dataset.fetch(:referencePairs).length - raw_dataset.fetch(:analysisPairs).length,
        terminalExcludedModelSampleCount: model_pairs.length
      )
    },
    "sampleCount" => model_pairs.length,
    "samples" => sample_records(model_pairs)
  }
end

def validate_pairing_statistics(statistics, contract, source_captures, sample_count)
  require_exact_keys(statistics, %w[contractPrefix analyzerWindow], "pairingStatistics")
  prefix = statistics.fetch("contractPrefix")
  analyzer = statistics.fetch("analyzerWindow")
  base_keys = %w[
    pairableScrollSampleCount
    pairedSampleCount
    unmatchedScrollSampleCount
    terminalPairCount
    phaseCounts
    captureIndexDeltaValues
    equalTimestampPairCount
  ]
  require_exact_keys(prefix, base_keys, "pairingStatistics.contractPrefix")
  require_exact_keys(
    analyzer,
    base_keys + %w[excludedBeforeAnalysisStartPairCount terminalExcludedModelSampleCount],
    "pairingStatistics.analyzerWindow"
  )

  phase_keys = contract.dig("scroll", "phaseValues").values.map(&:to_s).sort
  [[prefix, "contractPrefix"], [analyzer, "analyzerWindow"]].each do |values, label|
    base_keys.reject { |key| %w[phaseCounts captureIndexDeltaValues].include?(key) }.each do |key|
      require_integer(values.fetch(key), "pairingStatistics.#{label}.#{key}")
    end
    require_exact_keys(values.fetch("phaseCounts"), phase_keys, "pairingStatistics.#{label}.phaseCounts")
    values.fetch("phaseCounts").each do |phase, count|
      require_integer(count, "pairingStatistics.#{label}.phaseCounts.#{phase}")
      require_derivation(count >= 0, "phase countが負です。range=#{label} phase=#{phase}")
    end
    deltas = values.fetch("captureIndexDeltaValues")
    require_derivation(
      deltas.is_a?(Array) && deltas.all? { |value| value.instance_of?(Integer) } && deltas == deltas.uniq.sort,
      "capture index差分が昇順の一意integer配列ではありません。range=#{label}"
    )
    require_derivation(
      values.fetch("unmatchedScrollSampleCount") ==
        values.fetch("pairableScrollSampleCount") - values.fetch("pairedSampleCount"),
      "未対応scroll件数がpair件数と一致しません。range=#{label}"
    )
    require_derivation(
      values.fetch("phaseCounts").values.sum == values.fetch("pairedSampleCount"),
      "phase件数合計がpair件数と一致しません。range=#{label}"
    )
    terminal_phase = contract.dig("scroll", "phaseValues", "ended").to_s
    require_derivation(
      values.dig("phaseCounts", terminal_phase) == values.fetch("terminalPairCount"),
      "terminal phase件数がterminal pair件数と一致しません。range=#{label}"
    )
  end

  expected_prefix = {
    "pairableScrollSampleCount" => source_captures.sum { |source| source.fetch("referencePairableScrollSampleCount") },
    "pairedSampleCount" => source_captures.sum { |source| source.fetch("referencePairedSampleCount") },
    "terminalPairCount" => source_captures.sum { |source| source.fetch("referenceTerminalPairCount") }
  }
  expected_analyzer = {
    "pairableScrollSampleCount" => source_captures.sum { |source| source.fetch("analysisPairableScrollSampleCount") },
    "pairedSampleCount" => source_captures.sum { |source| source.fetch("analysisPairedSampleCount") },
    "terminalPairCount" => source_captures.sum { |source| source.fetch("analysisTerminalPairCount") }
  }
  expected_prefix.each do |key, expected|
    require_derivation(prefix.fetch(key) == expected, "contract prefix統計がsource別件数と一致しません。field=#{key}")
  end
  expected_analyzer.each do |key, expected|
    require_derivation(analyzer.fetch(key) == expected, "analyzer統計がsource別件数と一致しません。field=#{key}")
  end
  EXPECTED_ANALYSIS_TOTALS.each do |key, expected|
    actual = key == :modelSampleCount ? sample_count : analyzer.fetch(key.to_s)
    require_derivation(actual == expected, "sample fixture件数が固定観測と一致しません。field=#{key}")
  end

  contract_reference = contract.dig("scrollCompanion", "referenceStatistics")
  require_derivation(
    prefix.fetch("captureIndexDeltaValues") == contract_reference.fetch("captureIndexDeltaValues") &&
      (prefix.fetch("equalTimestampPairCount").positive? == contract_reference.fetch("anyTimestampEqualToScrollWheel")),
    "contract prefixのpair差分またはtimestamp統計がsource contractと一致しません。"
  )
  require_derivation(
    analyzer.fetch("captureIndexDeltaValues") == contract_reference.fetch("captureIndexDeltaValues") &&
      analyzer.fetch("equalTimestampPairCount").zero?,
    "analyzerのpair差分またはtimestamp統計が固定観測と一致しません。"
  )
  require_derivation(
    analyzer.fetch("excludedBeforeAnalysisStartPairCount") ==
      prefix.fetch("pairedSampleCount") - analyzer.fetch("pairedSampleCount"),
    "解析開始前の除外pair件数が一致しません。"
  )
  require_derivation(
    analyzer.fetch("terminalExcludedModelSampleCount") == sample_count,
    "model sample件数がpairing統計と一致しません。"
  )
end

def validate_samples_fixture(samples_fixture, contract, contract_sha256)
  require_exact_keys(
    samples_fixture,
    %w[
      schemaVersion
      fixtureID
      sampleSetID
      osVersion
      osBuild
      referenceDeviceLabel
      sourceContract
      derivation
      sourceCaptures
      associationRuleIdentity
      pairingStatistics
      sampleCount
      samples
    ],
    "samples"
  )
  require_derivation(samples_fixture.fetch("schemaVersion") == 1, "sample schemaが1ではありません。")
  require_derivation(samples_fixture.fetch("fixtureID") == EXPECTED_SAMPLES_FIXTURE_ID, "sample fixture IDが一致しません。")
  require_derivation(samples_fixture.fetch("sampleSetID") == EXPECTED_SAMPLE_SET_ID, "sample set IDが一致しません。")
  require_derivation(samples_fixture.fetch("osVersion") == contract.fetch("osVersion"), "sample OS versionが一致しません。")
  require_derivation(samples_fixture.fetch("osBuild") == contract.fetch("osBuild"), "sample OS buildが一致しません。")
  require_derivation(
    samples_fixture.fetch("referenceDeviceLabel") == contract.fetch("referenceDeviceLabel"),
    "sample reference deviceが一致しません。"
  )

  source_contract = samples_fixture.fetch("sourceContract")
  require_exact_keys(source_contract, %w[path sha256 fixtureID contractID], "samples.sourceContract")
  require_derivation(
    source_contract == expected_source_contract(contract, contract_sha256),
    "sample source contract identityが一致しません。"
  )
  derivation = samples_fixture.fetch("derivation")
  require_exact_keys(derivation, expected_derivation.keys, "samples.derivation")
  require_derivation(derivation == expected_derivation, "sample derivation metadataが一致しません。")
  identity = samples_fixture.fetch("associationRuleIdentity")
  require_exact_keys(identity, %w[sourceContractJSONPointer orderedJSONSHA256], "samples.associationRuleIdentity")
  require_derivation(identity == association_rule_identity(contract), "association rule identityが一致しません。")
  require_derivation(
    identity.fetch("orderedJSONSHA256") == EXPECTED_ASSOCIATION_RULE_SHA256,
    "association rule SHAが固定値と一致しません。"
  )

  source_captures = samples_fixture.fetch("sourceCaptures")
  require_derivation(source_captures.is_a?(Array) && source_captures.length == 4, "sample source captureが4件ではありません。")
  source_keys = %w[
    scenarioID
    sourceFile
    sourceLogSHA256
    sourceEventCount
    contractPrefixEventCount
    analysisStartCaptureIndex
    captureStartedAt
    captureCompletedAt
    referencePairableScrollSampleCount
    referencePairedSampleCount
    analysisPairableScrollSampleCount
    analysisPairedSampleCount
    referenceTerminalPairCount
    analysisTerminalPairCount
  ]
  contract.fetch("sourceCaptures").zip(source_captures).each do |contract_source, sample_source|
    scenario_id = contract_source.fetch("scenarioID")
    require_exact_keys(sample_source, source_keys, "samples.sourceCaptures.#{scenario_id}")
    observed_counts = EXPECTED_ANALYSIS_PAIRING.fetch(scenario_id)
    expected_source = contract_source.merge(
      "referencePairableScrollSampleCount" => observed_counts.fetch(:referencePairableScrollSampleCount),
      "referencePairedSampleCount" => observed_counts.fetch(:referencePairedSampleCount),
      "analysisPairableScrollSampleCount" => observed_counts.fetch(:analysisPairableScrollSampleCount),
      "analysisPairedSampleCount" => observed_counts.fetch(:analysisPairedSampleCount),
      "referenceTerminalPairCount" => observed_counts.fetch(:referenceTerminalPairCount),
      "analysisTerminalPairCount" => observed_counts.fetch(:analysisTerminalPairCount)
    )
    require_derivation(sample_source == expected_source, "sample source metadataがcontractと一致しません。scenario=#{scenario_id}")
  end

  sample_count = require_integer(samples_fixture.fetch("sampleCount"), "samples.sampleCount")
  require_derivation(sample_count == EXPECTED_ANALYSIS_TOTALS.fetch(:modelSampleCount), "sample件数が967ではありません。")
  validate_pairing_statistics(samples_fixture.fetch("pairingStatistics"), contract, source_captures, sample_count)

  samples = samples_fixture.fetch("samples")
  require_derivation(samples.is_a?(Array) && samples.length == sample_count, "sample配列長がsampleCountと一致しません。")
  sample_keys = %w[
    sampleIndex
    scenarioID
    scrollCaptureIndex
    companionCaptureIndex
    phase
    gestureX
    gestureY
    lineX
    lineY
    fixedX
    fixedY
    pointX
    pointY
  ]
  terminal_phase = contract.dig("scroll", "phaseValues", "ended")
  allowed_phases = contract.dig("scrollCompanion", "associationRule", "requiredMatchedScrollPhaseValues").to_set |
    contract.dig("scrollCompanion", "associationRule", "allowedUnmatchedScrollPhaseValues").to_set
  maximum_distance = contract.dig("scrollCompanion", "associationRule", "maximumCaptureIndexDistance")
  sources_by_scenario = source_captures.each_with_object({}) do |source, result|
    result[source.fetch("scenarioID")] = source
  end
  scenario_positions = source_captures.each_with_index.to_h { |source, index| [source.fetch("scenarioID"), index] }
  expected_scenario_counts = source_captures.each_with_object({}) do |source, result|
    result[source.fetch("scenarioID")] =
      source.fetch("analysisPairedSampleCount") - source.fetch("analysisTerminalPairCount")
  end
  actual_scenario_counts = Hash.new(0)
  actual_phase_counts = Hash.new(0)
  previous_scenario_position = -1
  previous_capture_indexes = {}
  pair_identities = Set.new

  model_pairs = samples.each_with_index.map do |sample, index|
    require_exact_keys(sample, sample_keys, "samples.samples[#{index}]")
    require_derivation(require_integer(sample.fetch("sampleIndex"), "samples.samples[#{index}].sampleIndex") == index, "sample順序が連番ではありません。index=#{index}")
    scenario_id = sample.fetch("scenarioID")
    require_derivation(scenario_id.instance_of?(String) && sources_by_scenario.key?(scenario_id), "sample scenarioがsourceにありません。index=#{index}")
    scenario_position = scenario_positions.fetch(scenario_id)
    require_derivation(scenario_position >= previous_scenario_position, "sample scenario順序がsource順ではありません。index=#{index}")
    previous_scenario_position = scenario_position

    scroll_index = require_integer(sample.fetch("scrollCaptureIndex"), "samples.samples[#{index}].scrollCaptureIndex")
    companion_index = require_integer(sample.fetch("companionCaptureIndex"), "samples.samples[#{index}].companionCaptureIndex")
    phase = require_integer(sample.fetch("phase"), "samples.samples[#{index}].phase")
    source = sources_by_scenario.fetch(scenario_id)
    boundary = source.fetch("analysisStartCaptureIndex")...source.fetch("contractPrefixEventCount")
    require_derivation(boundary.cover?(scroll_index) && boundary.cover?(companion_index), "sample capture indexが解析境界外です。index=#{index}")
    require_derivation((scroll_index - companion_index).abs <= maximum_distance, "sample pair距離が上限を超えています。index=#{index}")
    require_derivation(allowed_phases.include?(phase) && phase != terminal_phase, "sample phaseがnonterminal対象外です。index=#{index}")
    if previous_capture_indexes.key?(scenario_id)
      previous = previous_capture_indexes.fetch(scenario_id)
      require_derivation(scroll_index > previous.fetch(:scroll), "scroll capture index順序が単調増加ではありません。index=#{index}")
      require_derivation(companion_index > previous.fetch(:companion), "companion capture index順序が単調増加ではありません。index=#{index}")
    end
    previous_capture_indexes[scenario_id] = {scroll: scroll_index, companion: companion_index}
    identity_key = [scenario_id, scroll_index, companion_index]
    require_derivation(pair_identities.add?(identity_key), "sample pairが重複しています。index=#{index}")

    gesture_x = require_finite_float(sample.fetch("gestureX"), "samples.samples[#{index}].gestureX")
    gesture_y = require_finite_float(sample.fetch("gestureY"), "samples.samples[#{index}].gestureY")
    line_x = require_integer(sample.fetch("lineX"), "samples.samples[#{index}].lineX")
    line_y = require_integer(sample.fetch("lineY"), "samples.samples[#{index}].lineY")
    fixed_x = require_finite_float(sample.fetch("fixedX"), "samples.samples[#{index}].fixedX")
    fixed_y = require_finite_float(sample.fetch("fixedY"), "samples.samples[#{index}].fixedY")
    point_x = require_finite_float(sample.fetch("pointX"), "samples.samples[#{index}].pointX")
    point_y = require_finite_float(sample.fetch("pointY"), "samples.samples[#{index}].pointY")
    actual_scenario_counts[scenario_id] += 1
    actual_phase_counts[phase.to_s] += 1
    {
      scenarioID: scenario_id,
      scroll: {
        captureIndex: scroll_index,
        phase: phase,
        line: {"x" => line_x, "y" => line_y},
        fixed: {"x" => fixed_x, "y" => fixed_y},
        point: {"x" => point_x, "y" => point_y}
      },
      companion: {
        captureIndex: companion_index,
        gesture: {"x" => gesture_x, "y" => gesture_y}
      }
    }
  end
  require_derivation(actual_scenario_counts == expected_scenario_counts, "scenario別model sample件数が固定観測と一致しません。")
  analyzer_phase_counts = samples_fixture.dig("pairingStatistics", "analyzerWindow", "phaseCounts").each_with_object({}) do |(phase, count), result|
    result[phase] = count
  end
  analyzer_phase_counts[terminal_phase.to_s] -= samples_fixture.dig("pairingStatistics", "analyzerWindow", "terminalPairCount")
  analyzer_phase_counts.delete_if { |_phase, count| count.zero? }
  require_derivation(actual_phase_counts == analyzer_phase_counts, "sample phase件数がanalyzer統計と一致しません。")
  model_pairs
end

def build_axes(model_pairs, paired_sample_count, terminal_sample_count)
  axes = AXES.each_with_object({}) do |(axis, fields), result|
    rows = model_pairs.map do |pair|
      scroll = pair.fetch(:scroll)
      companion = pair.fetch(:companion)
      {
        gesture: companion.fetch(:gesture).fetch(axis),
        point: scroll.fetch(:point).fetch(axis),
        fixed: scroll.fetch(:fixed).fetch(axis),
        line: Float(scroll.fetch(:line).fetch(axis))
      }
    end
    require_derivation(
      rows.length == EXPECTED_ANALYSIS_TOTALS.fetch(:modelSampleCount),
      "軸別model sample数が固定観測と一致しません。axis=#{axis}"
    )
    models = {
      gestureToLine: odd_quadratic_model(rows, :line, axis, "gestureToLine", quantize: true),
      gestureToFixed: odd_quadratic_model(rows, :fixed, axis, "gestureToFixed"),
      gestureToPoint: odd_quadratic_model(rows, :point, axis, "gestureToPoint")
    }
    verify_expected_zero_counts(axis, models)
    result[axis] = {
      fields: fields,
      pairedSampleCount: paired_sample_count,
      excludedTerminalSampleCount: terminal_sample_count,
      modelSampleCount: rows.length,
      models: models
    }
  end
  axes
end

def build_model_fixture(contract, samples_fixture, model_pairs)
  analyzer_statistics = samples_fixture.dig("pairingStatistics", "analyzerWindow")
  axes = build_axes(
    model_pairs,
    analyzer_statistics.fetch("pairedSampleCount"),
    analyzer_statistics.fetch("terminalPairCount")
  )
  companion_contract = contract.fetch("scrollCompanion")
  terminal_phase = contract.dig("scroll", "phaseValues", "ended")
  {
    schemaVersion: 1,
    fixtureID: "trackpad-scroll-output-model-25F80-v1",
    modelID: "trackpad-scroll-output-model-v1",
    status: "derived",
    osVersion: contract.fetch("osVersion"),
    osBuild: contract.fetch("osBuild"),
    referenceDeviceLabel: contract.fetch("referenceDeviceLabel"),
    sourceContract: samples_fixture.fetch("sourceContract"),
    derivation: samples_fixture.fetch("derivation"),
    sourceCaptures: samples_fixture.fetch("sourceCaptures"),
    eventFields: {
      scrollEventTypeRaw: contract.dig("scroll", "eventTypeRaw"),
      scrollPhaseRawField: contract.dig("scroll", "phaseRawField"),
      terminalScrollPhaseValue: terminal_phase,
      companionEventTypeRaw: companion_contract.fetch("eventTypeRaw"),
      companionClassifierRawField: companion_contract.fetch("classifierRawField"),
      companionClassifierValue: companion_contract.fetch("classifierValue"),
      companionPhaseRawField: companion_contract.fetch("phaseRawField"),
      xGestureDoubleFields: companion_contract.fetch("xMotionDoubleFields"),
      yGestureDoubleFields: companion_contract.fetch("yMotionDoubleFields")
    },
    associationRule: companion_contract.fetch("associationRule"),
    pairingStatistics: samples_fixture.fetch("pairingStatistics"),
    samplePolicy: {
      terminalPairsExcludedFromModel: true,
      terminalNamedDeltasRequirePositiveZero: true,
      zeroInputMapsToPositiveZero: true,
      zeroObservationsIncludedInErrorMetrics: true,
      signSymmetryRequiredForNonzeroObservations: true
    },
    axes: axes
  }
end

def generate_samples_from_raw(contract, contract_sha256, capture_directory, samples_out)
  raw_dataset = derive_raw_dataset(contract, capture_directory)
  generated_fixture = build_samples_fixture(contract, contract_sha256, raw_dataset)
  generated_bytes = "#{JSON.pretty_generate(generated_fixture)}\n"
  parsed_fixture = parse_json_strict(generated_bytes, "生成したsample fixture")
  require_derivation(
    lossless_json_equal?(generated_fixture.fetch("samples"), parsed_fixture.fetch("samples")),
    "sample JSON数値がlosslessにround-tripしません。"
  )
  model_pairs = validate_samples_fixture(parsed_fixture, contract, contract_sha256)
  require_derivation(
    File.directory?(File.dirname(File.expand_path(samples_out))),
    "sample出力先directoryがありません。path=#{samples_out}"
  )
  File.binwrite(samples_out, generated_bytes)
  [parsed_fixture, model_pairs]
end


options = {
  contract: DEFAULT_CONTRACT_PATH,
  samples: DEFAULT_SAMPLES_PATH,
  capture_directory: nil,
  samples_out: nil,
  out: nil
}

begin
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby scripts/derive-trackpad-scroll-output-model.rb [options]"
    parser.on("--contract PATH", "source scroll / momentum contract") { |value| options[:contract] = value }
    parser.on("--samples PATH", "検証済みmodel sample fixture") { |value| options[:samples] = value }
    parser.on("--capture-dir PATH", "sampleを再生成する4つのraw capture directory") { |value| options[:capture_directory] = value }
    parser.on("--samples-out PATH", "raw captureから再生成したsample fixtureの出力先") { |value| options[:samples_out] = value }
    parser.on("--out PATH", "導出したmodel fixtureの出力先") { |value| options[:out] = value }
  end.parse!

  raw_mode = !options.fetch(:capture_directory).nil? || !options.fetch(:samples_out).nil?
  require_derivation(
    !raw_mode || (!options.fetch(:capture_directory).nil? && !options.fetch(:samples_out).nil?),
    "raw再生成には--capture-dirと--samples-outの両方が必要です。"
  )

  contract_bytes = File.binread(options.fetch(:contract))
  contract_sha256 = Digest::SHA256.hexdigest(contract_bytes)
  contract = parse_json_strict(contract_bytes, "source contract")
  validate_contract(contract, contract_sha256)

  samples_fixture, model_pairs = if raw_mode
                                   generate_samples_from_raw(
                                     contract,
                                     contract_sha256,
                                     options.fetch(:capture_directory),
                                     options.fetch(:samples_out)
                                   )
                                 else
                                   sample_bytes = File.binread(options.fetch(:samples))
                                   sample_sha256 = Digest::SHA256.hexdigest(sample_bytes)
                                   require_derivation(
                                     sample_sha256 == EXPECTED_SAMPLES_SHA256,
                                     "sample fixture SHAが固定値と一致しません。expected=#{EXPECTED_SAMPLES_SHA256} actual=#{sample_sha256}"
                                   )
                                   parsed_fixture = parse_json_strict(sample_bytes, "sample fixture")
                                   [parsed_fixture, validate_samples_fixture(parsed_fixture, contract, contract_sha256)]
                                 end

  fixture = build_model_fixture(contract, samples_fixture, model_pairs)
  output = "#{JSON.pretty_generate(fixture)}\n"
  if options.fetch(:out)
    out_path = options.fetch(:out)
    require_derivation(File.directory?(File.dirname(File.expand_path(out_path))), "出力先directoryがありません。path=#{out_path}")
    File.binwrite(out_path, output)
  else
    print output
  end
rescue DerivationFailure, Errno::ENOENT, Errno::EACCES, JSON::ParserError, JSON::GeneratorError,
       KeyError, ArgumentError, TypeError, OptionParser::ParseError => error
  warn "trackpad scroll output modelの導出に失敗しました: #{error.message}"
  exit 1
end
