# frozen_string_literal: true

require "pathname"

root = Pathname.new(__dir__).join("..").expand_path
errors = []

forbidden_paths = %w[
  Sources/NapeGestureCore/TrackpadGestureMode.swift
  scripts/test-settings-mode-migration.sh
  scripts/verify-doctor-family-state.rb
  scripts/test-verify-doctor-family-state.rb
].freeze

forbidden_paths.each do |relative|
  errors << "廃止対象fileが残っています: #{relative}" if root.join(relative).exist?
end

forbidden_terms = {
  "Sources/NapeGestureCore/GestureConfiguration.swift" => %w[
    TrackpadGestureMode
    button3Mode
    button4Mode
    button5Mode
    deadZonePoints
    dragSensitivity
    wheelSensitivity
    GestureAccelerationConfiguration
  ],
  "Sources/NapeGestureCore/EventTypes.swift" => [
    "mode: TrackpadGestureMode"
  ],
  "Sources/NapeGestureCore/SettingsUISchema.swift" => %w[
    button3Mode
    button4Mode
    button5Mode
  ],
  "Sources/nape-gesture/SettingsWindowController.swift" => %w[
    button3Mode
    button4Mode
    button5Mode
  ],
  "Sources/NapeGestureProductOutput/ProductGestureSessionCoordinator.swift" => %w[
    TrackpadGestureMode
    dominantAxis
    normalizedProgress
    normalizedVelocity
    normalizedScale
  ],
  "Sources/NapeGestureProductOutput/ProductGestureOutput.swift" => %w[
    supportedFamilies
    confirmedFamilies
    trialFamilies
  ],
  "Sources/NapeGestureProductOutput/TrackpadGestureOutputAdapter.swift" => %w[
    supportedFamilies
  ],
  "Sources/nape-gesture/DoctorCommand.swift" => %w[
    supportedFamilies
    confirmedFamilies
    trialFamilies
  ]
}.freeze

forbidden_terms.each do |relative, terms|
  path = root.join(relative)
  unless path.file?
    errors << "製品モデルguardの対象fileがありません: #{relative}"
    next
  end

  content = path.read
  terms.each do |term|
    errors << "#{relative}: 廃止対象が残っています: #{term}" if content.include?(term)
  end
end

event_types_path = root.join("Sources/NapeGestureCore/EventTypes.swift")
if event_types_path.file? && !event_types_path.read.include?("fingerCount")
  errors << "Sources/NapeGestureCore/EventTypes.swift: product commandにfingerCountがありません"
end

unless errors.empty?
  warn "固定finger-count製品モデルguardに失敗しました:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "固定finger-count製品モデルguardに成功しました。"
