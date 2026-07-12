#!/usr/bin/env ruby

require "json"

class VerificationFailure < StandardError; end

def require_value(condition, message)
  raise VerificationFailure, message unless condition
end

begin
  path = ARGV.shift
  require_value(!path.nil? && ARGV.empty?, "Usage: ruby scripts/verify-doctor-family-state.rb <doctor.json>")

  report = JSON.parse(File.read(path))
  contract = report.fetch("outputContract")
  expected_confirmed = ["scroll"]
  expected_trial = %w[dockSwipe magnification]
  expected_supported = (expected_confirmed + expected_trial).sort

  require_value(contract.fetch("status") == "supported", "outputContract.statusがsupportedではありません。")
  require_value(contract.fetch("supported") == true, "outputContract.supportedがtrueではありません。")
  require_value(
    contract.fetch("confirmedFamilies").sort == expected_confirmed,
    "confirmedFamiliesはscrollだけでなければなりません。"
  )
  require_value(
    contract.fetch("trialFamilies").sort == expected_trial,
    "trialFamiliesはdockSwipeとmagnificationでなければなりません。"
  )
  require_value(
    contract.fetch("supportedFamilies").sort == expected_supported,
    "supportedFamiliesが確定familyと試用familyの和集合ではありません。"
  )
  require_value(
    contract.fetch("missingRequiredFamilies").empty?,
    "設定中のmodeに必要なfamilyが不足しています。"
  )
  require_value(
    !contract.values_at("supportedFamilies", "confirmedFamilies", "trialFamilies")
      .flatten.include?("navigationSwipe"),
    "NavigationSwipe候補を製品runtime capabilityへ含めています。"
  )

  puts "doctor family state verification passed"
rescue Errno::ENOENT, JSON::ParserError, KeyError, VerificationFailure => error
  warn "doctor family state verification failed: #{error.message}"
  exit 1
end
