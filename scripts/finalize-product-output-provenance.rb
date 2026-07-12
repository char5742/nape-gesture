#!/usr/bin/env ruby

require "base64"
require "digest"
require "fileutils"
require "json"
require "tempfile"
require "time"

UINT64_MAX = (1 << 64) - 1
INT64_MIN = -(1 << 63)
INT64_MAX = (1 << 63) - 1
GENERATED_EVENT_MARKER = 0x4D_47_53_54
RAW_FIELD_UPPER_BOUND = 255

OPTIONS = {
  "--trace" => :trace,
  "--log" => :log,
  "--manifest" => :manifest,
  "--out" => :out
}.freeze

TRACE_KEYS = %w[
  schemaVersion
  postIndex
  sessionID
  family
  eventTimestamp
  eventTypeRaw
  delivery
  eventKind
  captureRunToken
  scenarioID
  repoHeadSHA
  executableSHA256
  prePostTargetProcessSerialNumber
  prePostTargetUnixProcessID
].freeze

TRACE_CONTEXT_KEYS = %w[
  captureRunToken
  scenarioID
  repoHeadSHA
  executableSHA256
].freeze

FORBIDDEN_TRACE_KEYS = %w[
  destinationPID
  accessibilityElementRole
  keyboardKeyCode
].freeze

LOG_REQUIRED_KEYS = %w[
  schemaVersion
  metadata
  captureIndex
  timestamp
  typeRaw
  typeName
  sourceUserData
  rawFieldScanUpperBound
  rawFields
  serializedEventBase64
].freeze

LOG_ALLOWED_KEYS = %w[
  schemaVersion
  metadata
  captureIndex
  timestamp
  typeRaw
  typeName
  eventSubtype
  flags
  scrollDeltaX
  scrollDeltaY
  scrollDeltaZ
  scrollFixedDeltaX
  scrollFixedDeltaXBitPattern
  scrollFixedDeltaY
  scrollFixedDeltaYBitPattern
  scrollFixedDeltaZ
  scrollFixedDeltaZBitPattern
  scrollPointDeltaX
  scrollPointDeltaXBitPattern
  scrollPointDeltaY
  scrollPointDeltaYBitPattern
  scrollPointDeltaZ
  scrollPointDeltaZBitPattern
  scrollPhase
  momentumPhase
  isContinuous
  sourceUserData
  rawFieldScanUpperBound
  rawFields
  serializedEventBase64
].freeze

METADATA_KEYS = %w[
  loggerName
  loggerVersion
  osVersion
  osBuild
  scenarioID
  deviceLabel
  repoHeadSHA
  captureRunToken
  canonicalEventRepresentation
  rawFieldScanPolicy
].freeze

MANIFEST_KEYS = %w[
  schemaVersion
  evidenceKind
  logSHA256
  logByteCount
  eventCount
  firstEventTimestamp
  lastEventTimestamp
  osVersion
  osBuild
  scenarioID
  deviceLabel
  repoHeadSHA
  captureRunToken
  loggerVersion
  loggerExecutableSHA256
  captureStartedAt
  captureCompletedAt
].freeze

RAW_FIELD_REQUIRED_KEYS = %w[
  fieldNumber
  doubleBitPattern
].freeze

RAW_FIELD_ALLOWED_KEYS = %w[
  fieldNumber
  integerValue
  doubleValue
  doubleBitPattern
].freeze

EVENT_KIND_BY_TYPE = {
  22 => "scroll",
  29 => "gesture"
}.freeze

class FinalizationFailure < StandardError; end
class DuplicateJSONKey < StandardError; end

class StrictJSONObject < Hash
  def []=(key, value)
    raise DuplicateJSONKey, "JSON objectでkeyが重複しています: #{key}" if key?(key)

    super
  end
end

def require_finalization(condition, message)
  raise FinalizationFailure, message unless condition
end

def require_object(value, label)
  require_finalization(value.is_a?(Hash), "#{label}はJSON objectである必要があります。")
  value
end

def require_exact_keys(object, expected_keys, label)
  require_object(object, label)
  missing = expected_keys - object.keys
  unknown = object.keys - expected_keys
  require_finalization(
    missing.empty? && unknown.empty?,
    "#{label}のkey構成が不正です。missing=#{missing.join(",")} unknown=#{unknown.join(",")}"
  )
end

def require_allowed_keys(object, required_keys, allowed_keys, label)
  require_object(object, label)
  missing = required_keys - object.keys
  unknown = object.keys - allowed_keys
  require_finalization(
    missing.empty? && unknown.empty?,
    "#{label}のkey構成が不正です。missing=#{missing.join(",")} unknown=#{unknown.join(",")}"
  )
end

def require_uint64(value, label)
  require_finalization(
    value.is_a?(Integer) && value.between?(0, UINT64_MAX),
    "#{label}はUInt64範囲の整数である必要があります。"
  )
  value
end

def require_int64(value, label)
  require_finalization(
    value.is_a?(Integer) && value.between?(INT64_MIN, INT64_MAX),
    "#{label}はInt64範囲の整数である必要があります。"
  )
  value
end

def require_positive_integer(value, label)
  require_finalization(
    value.is_a?(Integer) && value.positive?,
    "#{label}は1以上の整数である必要があります。"
  )
  value
end

def require_nonblank_string(value, label)
  require_finalization(
    value.is_a?(String) && !value.strip.empty?,
    "#{label}は空でない文字列である必要があります。"
  )
  value
end

def require_canonical_sha256(value, label)
  require_finalization(
    value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/),
    "#{label}は正規化済みSHA-256である必要があります。"
  )
  value
end

def require_canonical_git_object_id(value, label)
  require_finalization(
    value.is_a?(String) && [40, 64].include?(value.length) && value.match?(/\A[0-9a-f]+\z/),
    "#{label}は完全な正規化済みGit object IDである必要があります。"
  )
  value
end

def require_canonical_uuid(value, label)
  require_finalization(
    value.is_a?(String) &&
      value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/),
    "#{label}は正規化済みlowercase UUIDである必要があります。"
  )
  value
end

def require_canonical_base64(value, label)
  require_finalization(
    value.is_a?(String) && !value.empty?,
    "#{label}は空でないcanonical strict Base64である必要があります。"
  )

  begin
    decoded = Base64.strict_decode64(value)
  rescue ArgumentError
    raise FinalizationFailure, "#{label}は空でないcanonical strict Base64である必要があります。"
  end
  require_finalization(
    Base64.strict_encode64(decoded) == value,
    "#{label}は空でないcanonical strict Base64である必要があります。"
  )
  value
end

def parse_json(data, label)
  JSON.parse(
    data,
    object_class: StrictJSONObject,
    array_class: Array,
    create_additions: false
  )
rescue JSON::ParserError, DuplicateJSONKey, EncodingError => error
  raise FinalizationFailure, "#{label}をJSONとして解釈できません: #{error.message}"
end

def parse_json_lines(data, label)
  require_finalization(!data.empty?, "#{label}が空です。")
  require_finalization(data.end_with?("\n"), "#{label}の最終recordが改行で終端されていません。")

  lines = data.split("\n", -1)
  lines.pop
  lines.each_with_index.map do |line, index|
    require_finalization(!line.empty?, "#{label}に空recordがあります。line=#{index + 1}")
    parse_json(line, "#{label} line=#{index + 1}")
  end
end

def parse_options(arguments)
  parsed = {}
  index = 0
  while index < arguments.length
    option = arguments[index]
    key = OPTIONS[option]
    require_finalization(!key.nil?, "未知のoptionです: #{option}")
    require_finalization(!parsed.key?(key), "optionが重複しています: #{option}")

    value = arguments[index + 1]
    require_finalization(
      !value.nil? && !OPTIONS.key?(value) && !value.start_with?("--"),
      "optionの値がありません: #{option}"
    )
    require_finalization(!value.empty?, "optionの値が空です: #{option}")
    parsed[key] = File.expand_path(value)
    index += 2
  end

  missing = OPTIONS.values - parsed.keys
  require_finalization(
    missing.empty?,
    "必須optionがありません: #{missing.map { |key| "--#{key}" }.join(",")}"
  )
  parsed
end

def resolved_path(path)
  if File.exist?(path) || File.symlink?(path)
    File.realpath(path)
  else
    parent = File.dirname(path)
    resolved_parent = File.realpath(parent)
    File.join(resolved_parent, File.basename(path))
  end
rescue SystemCallError
  File.expand_path(path)
end

def validate_paths(paths)
  inputs = paths.slice(:trace, :log, :manifest)
  inputs.each do |label, path|
    require_finalization(File.file?(path), "#{label}入力が通常ファイルではありません: #{path}")
    require_finalization(File.readable?(path), "#{label}入力を読み取れません: #{path}")
  end

  paths.to_a.combination(2) do |(left_label, left_path), (right_label, right_path)|
    same_resolved_path = resolved_path(left_path) == resolved_path(right_path)
    same_file = if File.exist?(left_path) && File.exist?(right_path)
                  File.identical?(left_path, right_path)
                else
                  false
                end
    require_finalization(
      !same_resolved_path && !same_file,
      "pathが衝突しています: #{left_label}=#{left_path} #{right_label}=#{right_path}"
    )
  end
end

def validate_manifest(manifest)
  require_exact_keys(manifest, MANIFEST_KEYS, "manifest")
  require_finalization(manifest["schemaVersion"] == 2, "manifest schemaVersionは2である必要があります。")
  require_finalization(
    manifest["evidenceKind"] == "generatedProduct",
    "manifest evidenceKindはgeneratedProductである必要があります。"
  )
  require_canonical_sha256(manifest["logSHA256"], "manifest logSHA256")
  require_uint64(manifest["logByteCount"], "manifest logByteCount")
  require_finalization(manifest["logByteCount"].positive?, "manifest logByteCountは1以上である必要があります。")
  require_uint64(manifest["eventCount"], "manifest eventCount")
  require_finalization(manifest["eventCount"].positive?, "manifest eventCountは1以上である必要があります。")
  require_uint64(manifest["firstEventTimestamp"], "manifest firstEventTimestamp")
  require_uint64(manifest["lastEventTimestamp"], "manifest lastEventTimestamp")
  require_nonblank_string(manifest["osVersion"], "manifest osVersion")
  require_nonblank_string(manifest["osBuild"], "manifest osBuild")
  require_nonblank_string(manifest["scenarioID"], "manifest scenarioID")
  require_nonblank_string(manifest["deviceLabel"], "manifest deviceLabel")
  require_canonical_git_object_id(manifest["repoHeadSHA"], "manifest repoHeadSHA")
  require_canonical_uuid(manifest["captureRunToken"], "manifest captureRunToken")
  require_positive_integer(manifest["loggerVersion"], "manifest loggerVersion")
  require_canonical_sha256(manifest["loggerExecutableSHA256"], "manifest loggerExecutableSHA256")

  begin
    capture_started_at = Time.iso8601(require_nonblank_string(manifest["captureStartedAt"], "manifest captureStartedAt"))
    capture_completed_at = Time.iso8601(require_nonblank_string(manifest["captureCompletedAt"], "manifest captureCompletedAt"))
  rescue ArgumentError => error
    raise FinalizationFailure, "manifestのcapture wall-clockがISO 8601ではありません: #{error.message}"
  end
  require_finalization(
    capture_started_at <= capture_completed_at,
    "manifest captureStartedAtがcaptureCompletedAtを超えています。"
  )
end

def validate_metadata(metadata, manifest, line_number)
  label = "log metadata line=#{line_number}"
  require_exact_keys(metadata, METADATA_KEYS, label)
  require_finalization(metadata["loggerName"] == "trackpad-event-log", "#{label}のloggerNameが不正です。")
  require_positive_integer(metadata["loggerVersion"], "#{label} loggerVersion")
  require_nonblank_string(metadata["osVersion"], "#{label} osVersion")
  require_nonblank_string(metadata["osBuild"], "#{label} osBuild")
  require_nonblank_string(metadata["scenarioID"], "#{label} scenarioID")
  require_nonblank_string(metadata["deviceLabel"], "#{label} deviceLabel")
  require_canonical_git_object_id(metadata["repoHeadSHA"], "#{label} repoHeadSHA")
  require_canonical_uuid(metadata["captureRunToken"], "#{label} captureRunToken")
  require_finalization(
    metadata["canonicalEventRepresentation"] == "serializedEventBase64",
    "#{label}のcanonicalEventRepresentationが不正です。"
  )
  require_finalization(
    metadata["rawFieldScanPolicy"] == "orderedAllValuesIncludingZero",
    "#{label}のrawFieldScanPolicyが不正です。"
  )

  {
    "loggerVersion" => "loggerVersion",
    "osVersion" => "osVersion",
    "osBuild" => "osBuild",
    "scenarioID" => "scenarioID",
    "deviceLabel" => "deviceLabel",
    "repoHeadSHA" => "repoHeadSHA",
    "captureRunToken" => "captureRunToken"
  }.each do |metadata_key, manifest_key|
    require_finalization(
      metadata[metadata_key] == manifest[manifest_key],
      "#{label}とmanifestが一致しません。field=#{metadata_key}"
    )
  end
end

def validate_raw_fields(fields, event, line_number)
  label = "log rawFields line=#{line_number}"
  require_finalization(fields.is_a?(Array), "#{label}はJSON arrayである必要があります。")
  require_finalization(
    fields.length == RAW_FIELD_UPPER_BOUND + 1,
    "#{label}の要素数が#{RAW_FIELD_UPPER_BOUND + 1}ではありません。"
  )
  indexed = {}

  fields.each_with_index do |field, field_index|
    field_label = "#{label} index=#{field_index}"
    require_allowed_keys(field, RAW_FIELD_REQUIRED_KEYS, RAW_FIELD_ALLOWED_KEYS, field_label)
    field_number = field["fieldNumber"]
    require_finalization(
      field_number.is_a?(Integer) && field_number.between?(0, RAW_FIELD_UPPER_BOUND),
      "#{field_label}のfieldNumberが範囲外です。"
    )
    require_finalization(
      field_number == field_index,
      "#{field_label}のfieldNumberが0...#{RAW_FIELD_UPPER_BOUND}順ではありません。"
    )
    require_finalization(!indexed.key?(field_number), "#{label}でfieldNumberが重複しています: #{field_number}")
    require_int64(field["integerValue"], "#{field_label} integerValue") if field.key?("integerValue")
    if field.key?("doubleValue")
      require_finalization(
        field["doubleValue"].is_a?(Numeric) && field["doubleValue"].finite?,
        "#{field_label}のdoubleValueは有限数である必要があります。"
      )
    end
    require_uint64(field["doubleBitPattern"], "#{field_label} doubleBitPattern")
    indexed[field_number] = field
  end

  require_finalization(
    indexed.keys.sort == (0..RAW_FIELD_UPPER_BOUND).to_a,
    "#{label}が0...#{RAW_FIELD_UPPER_BOUND}を重複なく網羅していません。"
  )
  require_finalization(
    indexed.fetch(42)["integerValue"] == GENERATED_EVENT_MARKER,
    "#{label}のeventSourceUserDataにNape markerがありません。"
  )
  require_finalization(
    indexed.fetch(55)["integerValue"] == event["typeRaw"],
    "#{label}のtype raw fieldがtop-level typeRawと一致しません。"
  )
  require_finalization(
    indexed.fetch(58)["integerValue"] == event["timestamp"],
    "#{label}のtimestamp raw fieldがtop-level timestampと一致しません。"
  )
end

def validate_log(events, manifest, log_data)
  require_finalization(
    Digest::SHA256.hexdigest(log_data) == manifest["logSHA256"],
    "log bytesのSHA-256がmanifestと一致しません。"
  )
  require_finalization(
    log_data.bytesize == manifest["logByteCount"],
    "log byte countがmanifestと一致しません。"
  )
  require_finalization(
    events.length == manifest["eventCount"],
    "log event countがmanifestと一致しません。"
  )

  shared_metadata = nil
  events.each_with_index do |event, index|
    line_number = index + 1
    label = "log record line=#{line_number}"
    require_allowed_keys(event, LOG_REQUIRED_KEYS, LOG_ALLOWED_KEYS, label)
    require_finalization(event["schemaVersion"] == 2, "#{label}のschemaVersionは2である必要があります。")
    capture_index = require_uint64(event["captureIndex"], "#{label} captureIndex")
    require_finalization(capture_index == index, "#{label}のcaptureIndexが0始まり連続ではありません。")
    require_uint64(event["timestamp"], "#{label} timestamp")
    require_finalization(EVENT_KIND_BY_TYPE.key?(event["typeRaw"]), "#{label}のevent typeが22/29ではありません。")
    require_nonblank_string(event["typeName"], "#{label} typeName")
    require_int64(event["sourceUserData"], "#{label} sourceUserData")
    require_finalization(
      event["sourceUserData"] == GENERATED_EVENT_MARKER,
      "#{label}にNape Gesture generated markerがありません。"
    )
    require_finalization(
      event["rawFieldScanUpperBound"] == RAW_FIELD_UPPER_BOUND,
      "#{label}のrawFieldScanUpperBoundが#{RAW_FIELD_UPPER_BOUND}ではありません。"
    )
    require_canonical_base64(event["serializedEventBase64"], "#{label} serializedEventBase64")
    validate_metadata(event["metadata"], manifest, line_number)
    if shared_metadata
      require_finalization(event["metadata"] == shared_metadata, "log内でmetadataが一致しません。line=#{line_number}")
    else
      shared_metadata = event["metadata"]
    end
    validate_raw_fields(event["rawFields"], event, line_number)
  end

  require_finalization(
    events.first["timestamp"] == manifest["firstEventTimestamp"],
    "log先頭timestampがmanifestと一致しません。"
  )
  require_finalization(
    events.last["timestamp"] == manifest["lastEventTimestamp"],
    "log末尾timestampがmanifestと一致しません。"
  )
end

def validate_trace_and_build_records(trace, events, manifest, trace_sha256)
  require_finalization(trace.length == events.length, "trace件数がlog event countと一致しません。")

  shared_context = nil
  shared_session_raw_value = nil
  trace.each_with_index.map do |record, index|
    label = "trace record line=#{index + 1}"
    forbidden = FORBIDDEN_TRACE_KEYS & record.keys if record.is_a?(Hash)
    require_finalization(
      forbidden.nil? || forbidden.empty?,
      "#{label}にPID、Accessibility、key metadataがあります: #{forbidden&.join(",")}"
    )
    require_exact_keys(record, TRACE_KEYS, label)
    require_finalization(record["schemaVersion"] == 2, "#{label}のschemaVersionは2である必要があります。")
    post_index = require_uint64(record["postIndex"], "#{label} postIndex")
    require_finalization(post_index == index, "#{label}のpostIndexが0始まり連続ではありません。")

    session_id = require_object(record["sessionID"], "#{label} sessionID")
    require_exact_keys(session_id, ["rawValue"], "#{label} sessionID")
    session_raw_value = require_uint64(session_id["rawValue"], "#{label} sessionID.rawValue")
    require_finalization(session_raw_value.positive?, "#{label}のsessionID.rawValueは非0である必要があります。")
    if shared_session_raw_value
      require_finalization(
        session_raw_value == shared_session_raw_value,
        "trace内でsessionIDが一致しません。line=#{index + 1}"
      )
    else
      shared_session_raw_value = session_raw_value
    end

    context = TRACE_CONTEXT_KEYS.to_h { |key| [key, record[key]] }
    require_canonical_uuid(context["captureRunToken"], "#{label} captureRunToken")
    require_nonblank_string(context["scenarioID"], "#{label} scenarioID")
    require_canonical_git_object_id(context["repoHeadSHA"], "#{label} repoHeadSHA")
    require_canonical_sha256(context["executableSHA256"], "#{label} executableSHA256")
    if shared_context
      require_finalization(context == shared_context, "trace内でcontextが一致しません。line=#{index + 1}")
    else
      shared_context = context
    end
    {
      "captureRunToken" => "captureRunToken",
      "scenarioID" => "scenarioID",
      "repoHeadSHA" => "repoHeadSHA",
      "executableSHA256" => "loggerExecutableSHA256"
    }.each do |trace_key, manifest_key|
      require_finalization(
        context[trace_key] == manifest[manifest_key],
        "#{label}とmanifestが一致しません。field=#{trace_key}"
      )
    end

    pre_post_process_serial_number = require_int64(
      record["prePostTargetProcessSerialNumber"],
      "#{label} prePostTargetProcessSerialNumber"
    )
    pre_post_unix_process_id = require_int64(
      record["prePostTargetUnixProcessID"],
      "#{label} prePostTargetUnixProcessID"
    )
    require_finalization(
      pre_post_process_serial_number.zero?,
      "#{label}のprePostTargetProcessSerialNumberは0である必要があります。"
    )
    require_finalization(
      pre_post_unix_process_id.zero?,
      "#{label}のprePostTargetUnixProcessIDは0である必要があります。"
    )

    require_finalization(record["family"] == "scroll", "#{label}のfamilyはscrollである必要があります。")
    event_timestamp = require_uint64(record["eventTimestamp"], "#{label} eventTimestamp")
    event_type = record["eventTypeRaw"]
    require_finalization(EVENT_KIND_BY_TYPE.key?(event_type), "#{label}のeventTypeRawが22/29ではありません。")
    require_finalization(record["delivery"] == "systemWide", "#{label}のdeliveryはsystemWideである必要があります。")
    require_finalization(
      record["eventKind"] == EVENT_KIND_BY_TYPE.fetch(event_type),
      "#{label}のeventKindがeventTypeRawと一致しません。"
    )

    event = events.fetch(index)
    require_finalization(event["captureIndex"] == post_index, "#{label}の順序がlog captureIndexと一致しません。")
    require_finalization(event["timestamp"] == event_timestamp, "#{label}のtimestampがlogと一致しません。")
    require_finalization(event["typeRaw"] == event_type, "#{label}のevent typeがlogと一致しません。")

    {
      "captureIndex" => event["captureIndex"],
      "delivery" => "systemWide",
      "eventKind" => EVENT_KIND_BY_TYPE.fetch(event_type),
      "eventTimestamp" => event["timestamp"],
      "eventTypeRaw" => event_type,
      "family" => "scroll",
      "logSHA256" => manifest["logSHA256"],
      "schemaVersion" => 2,
      "sessionID" => {"rawValue" => session_raw_value},
      "traceSHA256" => trace_sha256,
      "captureRunToken" => context["captureRunToken"],
      "scenarioID" => context["scenarioID"],
      "repoHeadSHA" => context["repoHeadSHA"],
      "executableSHA256" => context["executableSHA256"],
      "prePostTargetProcessSerialNumber" => pre_post_process_serial_number,
      "prePostTargetUnixProcessID" => pre_post_unix_process_id
    }
  end
end

def encode_json_lines(records)
  records.map { |record| JSON.generate(record) }.join("\n") + "\n"
rescue JSON::GeneratorError => error
  raise FinalizationFailure, "provenance JSON Linesをencodeできません: #{error.message}"
end

def atomic_write(path, data)
  directory = File.dirname(path)
  FileUtils.mkdir_p(directory)
  temporary = Tempfile.new([".#{File.basename(path)}.", ".tmp"], directory)
  temporary.binmode
  begin
    written = temporary.write(data)
    require_finalization(written == data.bytesize, "一時provenanceファイルを完全に書き込めませんでした。")
    temporary.flush
    temporary.fsync
    temporary.close
    File.rename(temporary.path, path)
  ensure
    temporary.close! rescue nil
  end
end

begin
  paths = parse_options(ARGV)
  validate_paths(paths)

  trace_data = File.binread(paths.fetch(:trace))
  log_data = File.binread(paths.fetch(:log))
  manifest_data = File.binread(paths.fetch(:manifest))
  require_finalization(manifest_data.end_with?("\n"), "manifestはLFで終端する必要があります。")
  manifest_lines = manifest_data.lines(chomp: true)
  require_finalization(
    manifest_lines.length == 1 && !manifest_lines.fetch(0).empty?,
    "manifestは1行1objectである必要があります。"
  )
  manifest = parse_json(manifest_data, "manifest")
  validate_manifest(manifest)
  trace = parse_json_lines(trace_data, "post trace JSON Lines")
  events = parse_json_lines(log_data, "trackpad event log JSON Lines")
  validate_log(events, manifest, log_data)
  trace_sha256 = Digest::SHA256.hexdigest(trace_data)
  records = validate_trace_and_build_records(trace, events, manifest, trace_sha256)
  output_data = encode_json_lines(records)
  atomic_write(paths.fetch(:out), output_data)
  puts "product output provenanceを確定しました: #{paths.fetch(:out)} records=#{records.length}"
rescue FinalizationFailure, SystemCallError => error
  warn "product output provenanceの確定に失敗しました: #{error.message}"
  exit 1
end
