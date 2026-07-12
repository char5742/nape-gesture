# frozen_string_literal: true

require "pathname"

def markdown_link_targets(content)
  targets = []
  cursor = 0

  while (opening = content.index("](", cursor))
    index = opening + 2
    target_start = index
    depth = 1

    while index < content.bytesize
      byte = content.getbyte(index)

      if byte == 92 # backslash
        index += 2
        next
      elsif byte == 40 # (
        depth += 1
      elsif byte == 41 # )
        depth -= 1
        break if depth.zero?
      end

      index += 1
    end

    break unless depth.zero?

    targets << content.byteslice(target_start, index - target_start)
    cursor = index + 1
  end

  targets
end

root = Pathname.new(__dir__).join("..").expand_path
errors = []

obsolete_adrs = %w[
  0007-log-derived-tuning-parameters.md
  0010-system-test-discrete-assignment-dry-run-evidence.md
  0012-settings-ui-gesture-action-coverage.md
  0017-system-test-scenario-assertion.md
  0027-grok-cli-auxiliary-review.md
  0029-grok-operational-surface.md
  0046-trial-output-for-remaining-trackpad-families.md
  0047-fixed-continuous-2d-trackpad-input.md
  0048-separate-input-mode-event-family-os-result-and-evidence.md
].freeze

obsolete_adrs.each do |basename|
  path = root.join("docs", "adr", basename)
  errors << "削除済みADRが存在します: #{path.relative_path_from(root)}" if path.exist?
end

ignored_parts = %w[.git .build .swiftpm artifacts].freeze
markdown_files = Dir.glob(root.join("**", "*.md")).map { |path| Pathname.new(path) }.reject do |path|
  (path.each_filename.to_a & ignored_parts).any?
end

markdown_files.each do |path|
  content = path.read
  relative = path.relative_path_from(root)

  obsolete_adrs.each do |basename|
    errors << "#{relative}: 削除済みADRへの参照があります: #{basename}" if content.include?(basename)
  end

  markdown_link_targets(content).each do |raw_target|
    candidate = raw_target.strip
    target =
      if candidate.start_with?("<") && candidate.include?(">")
        candidate[1...candidate.index(">")]
      else
        candidate.split(/\s+/, 2).first
      end

    next if target.nil? || target.empty?
    next if target.start_with?("#", "/", "http://", "https://", "mailto:", "app://")

    path_part = target.split("#", 2).first
    next if path_part.nil? || path_part.empty?

    resolved = path.dirname.join(path_part).cleanpath
    errors << "#{relative}: link先が存在しません: #{target}" unless resolved.exist?
  end
end

adr_dir = root.join("docs", "adr")
adr_index = adr_dir.join("README.md").read
current_adrs = Dir.glob(adr_dir.join("[0-9][0-9][0-9][0-9]-*.md")).map { |path| File.basename(path) }.sort

current_adrs.each do |basename|
  errors << "docs/adr/README.md: ADRが索引にありません: #{basename}" unless adr_index.include?("(#{basename})")
end

if adr_index.match?(/^## .*置換済み/)
  errors << "docs/adr/README.md: 置換済みsectionを現行treeへ残さないでください"
end

deprecated_adr_terms = /
  twoFingerSwipe |
  systemSwipe |
  scrollAndNavigate |
  spacesAndMissionControl |
  button[345]Mode |
  supportedFamilies |
  confirmedFamilies |
  trialFamilies |
  GestureAction
/x

current_adrs.each do |basename|
  path = adr_dir.join(basename)
  content = path.read

  if content.match?(/^- 状態:\s*置換済み\s*$/)
    errors << "docs/adr/#{basename}: 置換済みADRを現行treeへ残さないでください"
  end

  content.each_line.with_index(1) do |line, line_number|
    if line.match?(deprecated_adr_terms)
      errors << "docs/adr/#{basename}:#{line_number}: 廃止した製品モデルの識別子が残っています"
    end
  end
end

required_snippets = {
  "AGENTS.md" => [
    "| button 3押下中 | 2本指入力 |",
    "| button 4押下中 | 3本指入力 |",
    "| button 5押下中 | 4本指入力 |",
    "| button 3 / 4 / 5のいずれも未押下 | 通常mouse入力をそのまま通過 |",
    "有効なsource sampleは欠落、重複、coalescing、並べ替えをせず",
    "単一の計測済み単位変換以外に感度、加速度、dead zone、threshold、clampを適用しない",
    "macOSまたは前面applicationが解釈する"
  ],
  "README.md" => [
    "> **現在の製品状態: 未達**",
    "| button 3を押しながらmouseを操作 | 連続した2本指trackpad入力 |",
    "| button 4を押しながらmouseを操作 | 連続した3本指trackpad入力 |",
    "| button 5を押しながらmouseを操作 | 連続した4本指trackpad入力 |",
    "| button 3 / 4 / 5を押していない | 通常mouse入力をそのまま通過 |",
    "有効なsource sampleは欠落、重複、coalescing、並べ替えをせず",
    "mouse単位とtrackpad単位の差だけを自前fixtureから導出した単一contractで変換",
    "macOSまたは前面applicationがtrackpad入力を解釈した結果"
  ],
  "docs/requirements.md" => [
    "| button 3押下中 | 2本指 |",
    "| button 4押下中 | 3本指 |",
    "| button 5押下中 | 4本指 |",
    "| 上記button未押下 | 変換なし | 通常mouse入力を改変せず通過させる |",
    "変えてよい意味情報は`fingerCount`だけ",
    "複数source sampleを1 sampleへcoalesceしない",
    "単一の単位変換contractを使う",
    "最終的な画面結果はmacOSまたは前面applicationが解釈する"
  ],
  "docs/adr/0049-fixed-button-to-finger-count-trackpad-input.md" => [
    "- button 3押下中: 2本指trackpad入力",
    "- button 4押下中: 3本指trackpad入力",
    "- button 5押下中: 4本指trackpad入力",
    "event familyは内部contract語彙に限定する",
    "同一の入力列をbutton 3 / 4 / 5で与えた場合、生成列はfinger count以外について同じ変換原則",
    "button未押下時、対象外button、対象外デバイスのclick、drag、wheelを通過させる"
  ]
}.freeze

required_snippets.each do |relative, snippets|
  content = root.join(relative).read
  snippets.each do |snippet|
    errors << "#{relative}: 正本の必須記述がありません: #{snippet}" unless content.include?(snippet)
  end
end

unless errors.empty?
  warn "製品モデル文書guardに失敗しました:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "製品モデル文書guardに成功しました。"
