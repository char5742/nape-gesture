#!/usr/bin/env ruby

require "json"
require "optparse"
require "time"

options = {
  timeout: 15.0,
  minimum_remaining: 10.0,
  stability_interval: 0.1
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/wait-for-trackpad-capture-ready.rb [options]"
  parser.on("--file PATH", "ready lease file") { |value| options[:file] = value }
  parser.on("--token UUID", "capture固有run token") { |value| options[:token] = value.downcase }
  parser.on("--pid PID", Integer, "logger PID") { |value| options[:pid] = value }
  parser.on("--scenario ID", "期待scenario ID") { |value| options[:scenario] = value }
  parser.on("--repo-head-sha SHA", "期待repo HEAD SHA") do |value|
    options[:repo_head_sha] = value.downcase
  end
  parser.on("--timeout SECONDS", Float, "ready待機上限") { |value| options[:timeout] = value }
  parser.on("--minimum-remaining SECONDS", Float, "有限captureに必要な残り秒数") do |value|
    options[:minimum_remaining] = value
  end
  parser.on("--stability-interval SECONDS", Float, "最終再検証までの待機秒数") do |value|
    options[:stability_interval] = value
  end
end.parse!

required_options = [:file, :token, :pid, :scenario, :repo_head_sha]
missing_options = required_options.reject { |key| options.key?(key) }
unless missing_options.empty?
  warn "ready待機の必須optionがありません: #{missing_options.join(",")}"
  exit 2
end
unless options[:pid].positive? && options[:timeout].positive? &&
       options[:minimum_remaining] >= 0 && options[:stability_interval].positive?
  warn "ready待機の数値optionが不正です。"
  exit 2
end

def process_alive?(pid)
  Process.kill(0, pid)
  true
rescue Errno::ESRCH
  false
rescue Errno::EPERM
  true
end

def read_ready_record(options)
  path = options.fetch(:file)
  stat = File.lstat(path)
  raise "ready pathが通常fileではありません。" unless stat.file?

  record = JSON.parse(File.read(path))
  raise "ready schemaVersionが不正です。" unless record["schemaVersion"] == 1
  raise "ready:trueではありません。" unless record["ready"] == true
  raise "run tokenが一致しません。" unless record["runToken"] == options.fetch(:token)
  raise "PIDが一致しません。" unless record["pid"] == options.fetch(:pid)
  raise "scenario IDが一致しません。" unless record["scenarioID"] == options.fetch(:scenario)
  unless record["repoHeadSHA"]&.downcase == options.fetch(:repo_head_sha)
    raise "repo HEAD SHAが一致しません。"
  end
  raise "logger processが生存していません。" unless process_alive?(options.fetch(:pid))

  lease_created_at = Time.iso8601(record.fetch("leaseCreatedAt"))
  capture_started_at = Time.iso8601(record.fetch("captureStartedAt"))
  raise "lease作成より前にcaptureが開始されています。" if capture_started_at < lease_created_at

  deadline_value = record["captureDeadlineAt"]
  if deadline_value
    deadline = Time.iso8601(deadline_value)
    remaining = deadline - Time.now
    if remaining < options.fetch(:minimum_remaining)
      raise format(
        "capture deadlineの残り時間が不足しています。remaining=%.3f required=%.3f",
        remaining,
        options.fetch(:minimum_remaining)
      )
    end
  end
  record
rescue Errno::ENOENT
  raise "ready lease fileがまだありません。"
rescue JSON::ParserError, KeyError, ArgumentError => error
  raise "ready recordを検証できません: #{error.message}"
end

deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + options.fetch(:timeout)
last_error = "ready未確認"
loop do
  begin
    first_record = read_ready_record(options)
    sleep options.fetch(:stability_interval)
    second_record = read_ready_record(options)
    raise "安定化待機中にready recordが変わりました。" unless second_record == first_record

    puts "ready確認済みです。純正トラックパッドを操作してください。"
    exit 0
  rescue StandardError => error
    last_error = error.message
  end

  if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    warn "ready待機がtimeoutしました: #{last_error}"
    exit 1
  end
  sleep 0.05
end
