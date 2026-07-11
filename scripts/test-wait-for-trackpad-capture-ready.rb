#!/usr/bin/env ruby

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"

repo_root = File.expand_path("..", __dir__)
waiter = File.join(repo_root, "scripts/wait-for-trackpad-capture-ready.rb")
token = "11111111-2222-3333-4444-555555555555"
scenario = "ready-waiter-test"
repo_head_sha = "a" * 40

def require_test(condition, message)
  raise message unless condition
end

def ready_record(token:, pid:, scenario:, repo_head_sha:, ready: true, deadline: nil)
  now = Time.now.utc
  {
    schemaVersion: 1,
    ready: ready,
    pid: pid,
    runToken: token,
    leaseCreatedAt: (now - 1).iso8601(3),
    captureStartedAt: now.iso8601(3),
    captureDeadlineAt: deadline&.iso8601(3),
    scenarioID: scenario,
    repoHeadSHA: repo_head_sha
  }
end

def write_record(path, record)
  File.write(path, "#{JSON.generate(record)}\n")
end

def run_waiter(waiter, path:, token:, pid:, scenario:, repo_head_sha:, minimum_remaining: 0)
  Open3.capture3(
    RbConfig.ruby,
    waiter,
    "--file", path,
    "--token", token,
    "--pid", pid.to_s,
    "--scenario", scenario,
    "--repo-head-sha", repo_head_sha,
    "--timeout", "0.25",
    "--minimum-remaining", minimum_remaining.to_s,
    "--stability-interval", "0.03"
  )
end

Dir.mktmpdir("nape-ready-waiter-tests-") do |directory|
  ready_path = File.join(directory, "capture.#{token}.ready.json")
  valid_record = ready_record(
    token: token,
    pid: Process.pid,
    scenario: scenario,
    repo_head_sha: repo_head_sha,
    deadline: Time.now.utc + 10
  )
  write_record(ready_path, valid_record)
  stdout, stderr, status = run_waiter(
    waiter,
    path: ready_path,
    token: token,
    pid: Process.pid,
    scenario: scenario,
    repo_head_sha: repo_head_sha,
    minimum_remaining: 5
  )
  require_test(status.success?, "正常なready recordが失敗しました: #{stderr}")
  require_test(stdout.include?("ready確認済み"), "正常系が操作案内を出しません。")

  near_deadline = valid_record.merge(captureDeadlineAt: (Time.now.utc + 0.05).iso8601(3))
  write_record(ready_path, near_deadline)
  stdout, stderr, status = run_waiter(
    waiter,
    path: ready_path,
    token: token,
    pid: Process.pid,
    scenario: scenario,
    repo_head_sha: repo_head_sha,
    minimum_remaining: 5
  )
  require_test(!status.success?, "deadline不足のready recordが成功しました。")
  require_test(stdout.empty?, "deadline不足時に操作案内を出しました。")
  require_test(stderr.include?("残り時間が不足"), "deadline不足理由を報告しません。")

  FileUtils.rm_f(ready_path)
  stdout, stderr, status = run_waiter(
    waiter,
    path: ready_path,
    token: token,
    pid: Process.pid,
    scenario: scenario,
    repo_head_sha: repo_head_sha
  )
  require_test(!status.success?, "後処理中のready欠落を成功扱いしました。")
  require_test(stdout.empty?, "ready欠落時に操作案内を出しました。")

  dead_pid = Process.spawn("sleep", "0.01")
  Process.wait(dead_pid)
  stale_record = ready_record(
    token: token,
    pid: dead_pid,
    scenario: scenario,
    repo_head_sha: repo_head_sha
  )
  write_record(ready_path, stale_record)
  stdout, stderr, status = run_waiter(
    waiter,
    path: ready_path,
    token: token,
    pid: dead_pid,
    scenario: scenario,
    repo_head_sha: repo_head_sha
  )
  require_test(!status.success?, "終了済みPIDのstale readyが成功しました。")
  require_test(stdout.empty?, "stale readyで操作案内を出しました。")
  require_test(stderr.include?("生存していません"), "stale PID理由を報告しません。")

  write_record(ready_path, valid_record)
  changer = Thread.new do
    sleep 0.01
    write_record(ready_path, valid_record.merge(ready: false))
  end
  stdout, _stderr, status = run_waiter(
    waiter,
    path: ready_path,
    token: token,
    pid: Process.pid,
    scenario: scenario,
    repo_head_sha: repo_head_sha
  )
  changer.join
  require_test(!status.success?, "安定化中に撤回されたreadyが成功しました。")
  require_test(stdout.empty?, "安定化中のready撤回後に操作案内を出しました。")
end

puts "trackpad capture ready waiter tests passed"
