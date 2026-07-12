#!/usr/bin/env ruby

require "json"
require "open3"
require "rbconfig"
require "tempfile"

SCRIPT = File.expand_path("verify-doctor-family-state.rb", __dir__)

def run_verifier(report)
  Tempfile.create(["doctor-family-state", ".json"]) do |file|
    file.write(JSON.generate(report))
    file.flush
    Open3.capture3(RbConfig.ruby, SCRIPT, file.path)
  end
end

def require_result(condition, message)
  raise message unless condition
end

valid = {
  "outputContract" => {
    "status" => "supported",
    "supported" => true,
    "supportedFamilies" => %w[dockSwipe magnification scroll],
    "confirmedFamilies" => ["scroll"],
    "trialFamilies" => %w[dockSwipe magnification],
    "missingRequiredFamilies" => []
  }
}

_stdout, stderr, status = run_verifier(valid)
require_result(status.success?, "正しいfamily stateを拒否しました: #{stderr}")

invalid_reports = [
  valid.merge("outputContract" => valid.fetch("outputContract").merge("confirmedFamilies" => [])),
  valid.merge(
    "outputContract" => valid.fetch("outputContract").merge(
      "trialFamilies" => %w[dockSwipe magnification navigationSwipe]
    )
  ),
  valid.merge(
    "outputContract" => valid.fetch("outputContract").merge(
      "supportedFamilies" => %w[dockSwipe magnification navigationSwipe scroll]
    )
  ),
  valid.merge(
    "outputContract" => valid.fetch("outputContract").merge(
      "missingRequiredFamilies" => ["magnification"]
    )
  )
]

invalid_reports.each_with_index do |report, index|
  _stdout, _stderr, invalid_status = run_verifier(report)
  require_result(!invalid_status.success?, "不正なfamily stateを受理しました: case=#{index}")
end

puts "doctor family state verifier tests passed"
