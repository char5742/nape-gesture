#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

FINALIZER = File.join(__dir__, "finalize-product-output-provenance.rb")
GENERATED_EVENT_MARKER = 0x4D_47_53_54
SENTINEL = "既存のprovenance\n".b.freeze
CAPTURE_RUN_TOKEN = "123e4567-e89b-42d3-a456-426614174000"

class TestFailure < StandardError; end

def require_test(condition, message)
  raise TestFailure, message unless condition
end

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def metadata
  {
    "loggerName" => "trackpad-event-log",
    "loggerVersion" => 2,
    "osVersion" => "26.5.1",
    "osBuild" => "25F80",
    "scenarioID" => "finalizer-small-fixture",
    "deviceLabel" => "nape-gesture-product-output",
    "repoHeadSHA" => "a" * 40,
    "captureRunToken" => CAPTURE_RUN_TOKEN,
    "canonicalEventRepresentation" => "serializedEventBase64",
    "rawFieldScanPolicy" => "orderedAllValuesIncludingZero"
  }
end

def raw_fields(type_raw, timestamp)
  (0..255).map do |field_number|
    integer_value = case field_number
                    when 42
                      GENERATED_EVENT_MARKER
                    when 55
                      type_raw
                    when 58
                      timestamp
                    else
                      0
                    end
    {
      "fieldNumber" => field_number,
      "integerValue" => integer_value,
      "doubleValue" => integer_value.to_f,
      "doubleBitPattern" => [integer_value.to_f].pack("G").unpack1("Q>")
    }
  end
end

def log_record(capture_index, timestamp, type_raw)
  {
    "schemaVersion" => 2,
    "metadata" => metadata,
    "captureIndex" => capture_index,
    "timestamp" => timestamp,
    "typeRaw" => type_raw,
    "typeName" => type_raw == 22 ? "scrollWheel" : "raw-29",
    "flags" => 0,
    "scrollDeltaX" => 0,
    "scrollDeltaY" => 0,
    "scrollDeltaZ" => 0,
    "scrollFixedDeltaX" => 0.0,
    "scrollFixedDeltaXBitPattern" => 0,
    "scrollFixedDeltaY" => 0.0,
    "scrollFixedDeltaYBitPattern" => 0,
    "scrollFixedDeltaZ" => 0.0,
    "scrollFixedDeltaZBitPattern" => 0,
    "scrollPointDeltaX" => 0.0,
    "scrollPointDeltaXBitPattern" => 0,
    "scrollPointDeltaY" => 0.0,
    "scrollPointDeltaYBitPattern" => 0,
    "scrollPointDeltaZ" => 0.0,
    "scrollPointDeltaZBitPattern" => 0,
    "scrollPhase" => 0,
    "momentumPhase" => 0,
    "isContinuous" => type_raw == 22 ? 1 : 0,
    "sourceUserData" => GENERATED_EVENT_MARKER,
    "rawFieldScanUpperBound" => 255,
    "rawFields" => raw_fields(type_raw, timestamp),
    "serializedEventBase64" => "AA=="
  }
end

def trace_record(post_index, timestamp, type_raw)
  {
    "schemaVersion" => 2,
    "postIndex" => post_index,
    "sessionID" => {"rawValue" => 7},
    "family" => "scroll",
    "eventTimestamp" => timestamp,
    "eventTypeRaw" => type_raw,
    "delivery" => "systemWide",
    "eventKind" => type_raw == 22 ? "scroll" : "gesture",
    "captureRunToken" => CAPTURE_RUN_TOKEN,
    "scenarioID" => "finalizer-small-fixture",
    "repoHeadSHA" => "a" * 40,
    "executableSHA256" => "b" * 64,
    "prePostTargetProcessSerialNumber" => 0,
    "prePostTargetUnixProcessID" => 0
  }
end

def json_lines(records)
  records.map { |record| JSON.generate(record) }.join("\n") + "\n"
end

def manifest_for(log_data, records)
  shared_metadata = records.fetch(0).fetch("metadata")
  {
    "schemaVersion" => 2,
    "evidenceKind" => "generatedProduct",
    "logSHA256" => Digest::SHA256.hexdigest(log_data),
    "logByteCount" => log_data.bytesize,
    "eventCount" => records.length,
    "firstEventTimestamp" => records.fetch(0).fetch("timestamp"),
    "lastEventTimestamp" => records.fetch(-1).fetch("timestamp"),
    "osVersion" => shared_metadata.fetch("osVersion"),
    "osBuild" => shared_metadata.fetch("osBuild"),
    "scenarioID" => shared_metadata.fetch("scenarioID"),
    "deviceLabel" => shared_metadata.fetch("deviceLabel"),
    "repoHeadSHA" => shared_metadata.fetch("repoHeadSHA"),
    "captureRunToken" => shared_metadata.fetch("captureRunToken"),
    "loggerVersion" => shared_metadata.fetch("loggerVersion"),
    "loggerExecutableSHA256" => "b" * 64,
    "captureStartedAt" => "2026-07-12T00:00:00.000Z",
    "captureCompletedAt" => "2026-07-12T00:00:01.000Z"
  }
end

def create_case(root, name, trace_mutator: nil, log_mutator: nil, manifest_mutator: nil)
  directory = File.join(root, name)
  FileUtils.mkdir_p(directory)
  events = [
    log_record(0, 1_000_000, 22),
    log_record(1, 1_000_000, 29)
  ]
  trace = [
    trace_record(0, 1_000_000, 22),
    trace_record(1, 1_000_000, 29)
  ]
  log_mutator&.call(events)
  trace_mutator&.call(trace)
  log_data = json_lines(events)
  manifest = manifest_for(log_data, events)
  manifest_mutator&.call(manifest)

  paths = {
    trace: File.join(directory, "posted.trace.jsonl"),
    log: File.join(directory, "captured.jsonl"),
    manifest: File.join(directory, "captured.jsonl.manifest.json"),
    out: File.join(directory, "result.provenance.jsonl")
  }
  File.binwrite(paths.fetch(:trace), json_lines(trace))
  File.binwrite(paths.fetch(:log), log_data)
  File.binwrite(paths.fetch(:manifest), "#{JSON.generate(manifest)}\n")
  paths
end

def arguments(paths)
  [
    "--trace", paths.fetch(:trace),
    "--log", paths.fetch(:log),
    "--manifest", paths.fetch(:manifest),
    "--out", paths.fetch(:out)
  ]
end

def run_finalizer(argv)
  Open3.capture3(RbConfig.ruby, FINALIZER, *argv)
end

def require_failure_preserves_output(paths, expected_message: nil, argv: arguments(paths))
  File.binwrite(paths.fetch(:out), SENTINEL)
  stdout, stderr, status = run_finalizer(argv)
  require_test(!status.success?, "不正入力が成功しました: stdout=#{stdout} stderr=#{stderr}")
  require_test(stdout.empty?, "失敗時にsuccess出力がありました: #{stdout}")
  require_test(
    expected_message.nil? || stderr.include?(expected_message),
    "期待した失敗理由がありません。expected=#{expected_message} stderr=#{stderr}"
  )
  require_test(File.binread(paths.fetch(:out)) == SENTINEL, "失敗時に既存outが変更されました。")
end

Dir.mktmpdir("nape-product-provenance-finalizer-tests-") do |root|
  valid = create_case(root, "valid")
  raw_trace_data = File.binread(valid.fetch(:trace)).sub("\n", " \n")
  File.binwrite(valid.fetch(:trace), raw_trace_data)
  expected_trace_sha256 = Digest::SHA256.hexdigest(raw_trace_data)
  stdout, stderr, status = run_finalizer(arguments(valid))
  require_test(status.success?, "正常系が失敗しました: stdout=#{stdout} stderr=#{stderr}")
  require_test(stderr.empty?, "正常系でstderrが出ました: #{stderr}")
  output_records = File.readlines(valid.fetch(:out), chomp: true).map { |line| JSON.parse(line) }
  manifest = JSON.parse(File.binread(valid.fetch(:manifest)))
  require_test(output_records.length == 2, "正常系の出力件数が2ではありません。")
  require_test(
    output_records.map { |record| record.fetch("captureIndex") } == [0, 1],
    "captureIndexがlog順序を保持していません。"
  )
  require_test(
    output_records.map { |record| record.fetch("eventKind") } == %w[scroll gesture],
    "eventKindがtype 22/29に対応していません。"
  )
  require_test(
    output_records.all? do |record|
      record.keys.sort == %w[
        captureIndex
        delivery
        eventKind
        eventTimestamp
        eventTypeRaw
        executableSHA256
        family
        logSHA256
        prePostTargetProcessSerialNumber
        prePostTargetUnixProcessID
        repoHeadSHA
        scenarioID
        schemaVersion
        sessionID
        traceSHA256
        captureRunToken
      ].sort &&
        record.fetch("schemaVersion") == 2 &&
        record.fetch("logSHA256") == manifest.fetch("logSHA256") &&
        record.fetch("traceSHA256") == expected_trace_sha256 &&
        record.fetch("captureRunToken") == manifest.fetch("captureRunToken") &&
        record.fetch("scenarioID") == manifest.fetch("scenarioID") &&
        record.fetch("repoHeadSHA") == manifest.fetch("repoHeadSHA") &&
        record.fetch("executableSHA256") == manifest.fetch("loggerExecutableSHA256") &&
        record.fetch("prePostTargetProcessSerialNumber").zero? &&
        record.fetch("prePostTargetUnixProcessID").zero? &&
        record.fetch("sessionID") == {"rawValue" => 7}
    end,
    "schema 2 provenance shape、context、またはraw trace SHA-256の設定が不正です。"
  )

  missing_manifest_run_token = create_case(
    root,
    "missing-manifest-run-token",
    manifest_mutator: ->(value) { value.delete("captureRunToken") }
  )
  require_failure_preserves_output(
    missing_manifest_run_token,
    expected_message: "missing=captureRunToken"
  )

  noncanonical_manifest_run_token = create_case(
    root,
    "noncanonical-manifest-run-token",
    manifest_mutator: ->(value) { value["captureRunToken"] = CAPTURE_RUN_TOKEN.upcase }
  )
  require_failure_preserves_output(
    noncanonical_manifest_run_token,
    expected_message: "lowercase UUID"
  )

  missing_metadata_run_token = create_case(
    root,
    "missing-metadata-run-token",
    log_mutator: ->(value) { value.fetch(1).fetch("metadata").delete("captureRunToken") }
  )
  require_failure_preserves_output(
    missing_metadata_run_token,
    expected_message: "missing=captureRunToken"
  )

  noncanonical_metadata_run_token = create_case(
    root,
    "noncanonical-metadata-run-token",
    log_mutator: lambda do |value|
      value.fetch(1).fetch("metadata")["captureRunToken"] = CAPTURE_RUN_TOKEN.upcase
    end
  )
  require_failure_preserves_output(
    noncanonical_metadata_run_token,
    expected_message: "lowercase UUID"
  )

  {
    "captureRunToken" => "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
    "scenarioID" => "different-scenario",
    "repoHeadSHA" => "c" * 40,
    "executableSHA256" => "d" * 64
  }.each do |field, replacement|
    context_manifest_mismatch = create_case(
      root,
      "trace-#{field}-manifest-mismatch",
      trace_mutator: lambda do |value|
        value.each { |record| record[field] = replacement }
      end
    )
    require_failure_preserves_output(
      context_manifest_mismatch,
      expected_message: "field=#{field}"
    )
  end

  context_mismatch = create_case(
    root,
    "trace-context-mismatch",
    trace_mutator: ->(value) { value.fetch(1)["scenarioID"] = "different-scenario" }
  )
  require_failure_preserves_output(context_mismatch, expected_message: "contextが一致")

  session_mismatch = create_case(
    root,
    "session-mismatch",
    trace_mutator: ->(value) { value.fetch(1).fetch("sessionID")["rawValue"] = 8 }
  )
  require_failure_preserves_output(session_mismatch, expected_message: "sessionIDが一致")

  zero_session = create_case(
    root,
    "zero-session",
    trace_mutator: ->(value) { value.fetch(0).fetch("sessionID")["rawValue"] = 0 }
  )
  require_failure_preserves_output(zero_session, expected_message: "非0")

  %w[
    prePostTargetProcessSerialNumber
    prePostTargetUnixProcessID
  ].each do |field|
    nonzero_pre_post_value = create_case(
      root,
      "nonzero-#{field}",
      trace_mutator: ->(value) { value.fetch(1)[field] = 1 }
    )
    require_failure_preserves_output(nonzero_pre_post_value, expected_message: "#{field}は0")
  end

  missing_serialized_event = create_case(
    root,
    "missing-serialized-event",
    log_mutator: ->(value) { value.fetch(0).delete("serializedEventBase64") }
  )
  require_failure_preserves_output(
    missing_serialized_event,
    expected_message: "missing=serializedEventBase64"
  )

  empty_serialized_event = create_case(
    root,
    "empty-serialized-event",
    log_mutator: ->(value) { value.fetch(0)["serializedEventBase64"] = "" }
  )
  require_failure_preserves_output(empty_serialized_event, expected_message: "canonical strict Base64")

  invalid_serialized_event = create_case(
    root,
    "invalid-serialized-event",
    log_mutator: ->(value) { value.fetch(0)["serializedEventBase64"] = "not-base64" }
  )
  require_failure_preserves_output(invalid_serialized_event, expected_message: "canonical strict Base64")

  noncanonical_serialized_event = create_case(
    root,
    "noncanonical-serialized-event",
    log_mutator: ->(value) { value.fetch(0)["serializedEventBase64"] = "AB==" }
  )
  require_failure_preserves_output(noncanonical_serialized_event, expected_message: "canonical strict Base64")

  unexpected_trace_key = create_case(
    root,
    "unexpected-trace-key",
    trace_mutator: ->(value) { value.fetch(0)["unexpected"] = true }
  )
  require_failure_preserves_output(unexpected_trace_key, expected_message: "unknown=unexpected")

  duplicate_trace_key = create_case(root, "duplicate-trace-key")
  duplicate_trace_data = File.binread(duplicate_trace_key.fetch(:trace)).sub(
    '"schemaVersion":2',
    '"schemaVersion":2,"schemaVersion":2'
  )
  File.binwrite(duplicate_trace_key.fetch(:trace), duplicate_trace_data)
  require_failure_preserves_output(duplicate_trace_key, expected_message: "重複")

  sha_mismatch = create_case(
    root,
    "sha-mismatch",
    manifest_mutator: ->(value) { value["logSHA256"] = "0" * 64 }
  )
  require_failure_preserves_output(sha_mismatch, expected_message: "SHA-256")

  timestamp_mismatch = create_case(
    root,
    "timestamp-mismatch",
    trace_mutator: ->(value) { value.fetch(1)["eventTimestamp"] += 1 }
  )
  require_failure_preserves_output(timestamp_mismatch, expected_message: "timestamp")

  forbidden_delivery = create_case(
    root,
    "forbidden-delivery",
    trace_mutator: ->(value) { value.fetch(0)["delivery"] = "targetPID" }
  )
  require_failure_preserves_output(forbidden_delivery, expected_message: "systemWide")

  byte_count_mismatch = create_case(
    root,
    "byte-count-mismatch",
    manifest_mutator: ->(value) { value["logByteCount"] += 1 }
  )
  require_failure_preserves_output(byte_count_mismatch, expected_message: "byte count")

  event_count_mismatch = create_case(
    root,
    "event-count-mismatch",
    manifest_mutator: ->(value) { value["eventCount"] += 1 }
  )
  require_failure_preserves_output(event_count_mismatch, expected_message: "event count")

  capture_index_gap = create_case(
    root,
    "capture-index-gap",
    log_mutator: ->(value) { value.fetch(1)["captureIndex"] = 2 }
  )
  require_failure_preserves_output(capture_index_gap, expected_message: "captureIndex")

  unordered_raw_fields = create_case(
    root,
    "unordered-raw-fields",
    log_mutator: lambda do |value|
      fields = value.fetch(0).fetch("rawFields")
      fields[0], fields[1] = fields[1], fields[0]
    end
  )
  require_failure_preserves_output(unordered_raw_fields, expected_message: "順ではありません")

  unterminated_manifest = create_case(root, "unterminated-manifest")
  manifest_without_lf = File.binread(unterminated_manifest.fetch(:manifest)).delete_suffix("\n")
  File.binwrite(unterminated_manifest.fetch(:manifest), manifest_without_lf)
  require_failure_preserves_output(unterminated_manifest, expected_message: "LFで終端")

  multiline_manifest = create_case(root, "multiline-manifest")
  File.binwrite(
    multiline_manifest.fetch(:manifest),
    File.binread(multiline_manifest.fetch(:manifest)) + "{}\n"
  )
  require_failure_preserves_output(multiline_manifest, expected_message: "1行1object")

  missing_marker = create_case(
    root,
    "missing-marker",
    log_mutator: ->(value) { value.fetch(0)["sourceUserData"] = 0 }
  )
  require_failure_preserves_output(missing_marker, expected_message: "marker")

  resolved_target = create_case(
    root,
    "window-server-resolved-target",
    log_mutator: lambda do |value|
      value.each do |event|
        event.fetch("rawFields").fetch(39)["integerValue"] = 4_174_843
        event.fetch("rawFields").fetch(40)["integerValue"] = 69_888
      end
    end
  )
  resolved_stdout, resolved_stderr, resolved_status = run_finalizer(arguments(resolved_target))
  require_test(
    resolved_status.success?,
    "WindowServer解決後の配送先fieldを誤拒否しました: stdout=#{resolved_stdout} stderr=#{resolved_stderr}"
  )
  require_test(resolved_stderr.empty?, "OS解決後の配送先fieldでstderrが出ました: #{resolved_stderr}")

  forbidden_metadata = create_case(
    root,
    "forbidden-metadata",
    trace_mutator: ->(value) { value.fetch(0)["destinationPID"] = 123 }
  )
  require_failure_preserves_output(forbidden_metadata, expected_message: "PID")

  kind_mismatch = create_case(
    root,
    "kind-mismatch",
    trace_mutator: ->(value) { value.fetch(0)["eventKind"] = "gesture" }
  )
  require_failure_preserves_output(kind_mismatch, expected_message: "eventKind")

  missing_session = create_case(
    root,
    "missing-session",
    trace_mutator: ->(value) { value.fetch(0).delete("sessionID") }
  )
  require_failure_preserves_output(missing_session, expected_message: "sessionID")

  duplicate_option = create_case(root, "duplicate-option")
  duplicate_arguments = arguments(duplicate_option) + ["--trace", duplicate_option.fetch(:trace)]
  require_failure_preserves_output(
    duplicate_option,
    expected_message: "重複",
    argv: duplicate_arguments
  )

  unknown_option = create_case(root, "unknown-option")
  require_failure_preserves_output(
    unknown_option,
    expected_message: "未知",
    argv: arguments(unknown_option) + ["--unknown", "value"]
  )

  missing_option = create_case(root, "missing-option")
  missing_arguments = arguments(missing_option)
  manifest_index = missing_arguments.index("--manifest")
  missing_arguments.slice!(manifest_index, 2)
  require_failure_preserves_output(
    missing_option,
    expected_message: "必須option",
    argv: missing_arguments
  )

  collision = create_case(root, "path-collision")
  trace_before = File.binread(collision.fetch(:trace))
  collision_arguments = arguments(collision)
  out_index = collision_arguments.index("--out") + 1
  collision_arguments[out_index] = collision.fetch(:trace)
  _stdout, stderr, status = run_finalizer(collision_arguments)
  require_test(!status.success?, "入力/出力path衝突が成功しました。")
  require_test(stderr.include?("衝突"), "path衝突理由を報告しません。")
  require_test(File.binread(collision.fetch(:trace)) == trace_before, "path衝突時に入力が変更されました。")
end

puts "finalize product output provenance tests passed"
