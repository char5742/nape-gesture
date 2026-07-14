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

      if byte == 92
        index += 2
        next
      elsif byte == 40
        depth += 1
      elsif byte == 41
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

current_adrs.each do |basename|
  content = adr_dir.join(basename).read
  if content.match?(/^- 状態:\s*置換済み\s*$/)
    errors << "docs/adr/#{basename}: 置換済みADRを現行treeへ残さないでください"
  end
end

required_snippets = {
  "README.md" => [
    "> **現在の製品状態: 試用可能・Nape Pro主要経路受入済み**",
    "| button 3を押しながらmouseを操作 | 2本指スクロール / スワイプ相当 |",
    "| button 4を押しながらmouseを操作 | 3本指システムスワイプ相当 | type 30 `DockSwipe`、motion 1 / 2 |",
    "| button 5を押しながらmouseを操作 | 4本指system pinch相当 | type 30 `DockSwipe`、motion 4 |",
    "raw digitizer contact数でもgeneric `fingerCount` fieldでもありません",
    "1 sampleから1つのsource command",
    "recognized-dockswipe-templates-25F80-v2",
    "852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6",
    "実行中macOSのversion / buildとは比較しません",
    "`/Applications/Nape Gesture.app`へインストール済み",
    "Nape Pro物理受入 | 3 class合計23 session",
    "gesture session中はmouse cursorが移動しない"
  ],
  "docs/requirements.md" => [
    "| button 3押下中 | 2本指スクロール / スワイプ相当 |",
    "| button 4押下中 | 3本指システムスワイプ相当 | type 30 `DockSwipe`、motion 1 / 2 |",
    "| button 5押下中 | 4本指system pinch相当 | type 30 `DockSwipe`、motion 4 |",
    "raw digitizer contact count、generic `fingerCount` field",
    "各source sampleからちょうど1つの内部command",
    "class間で同じevent type、field、単位変換を強制しない",
    "phase fields 132 / 134 = began 1、changed 2、ended 4、cancelled 8",
    "application magnification event、generic finger count field、3本指classのmotion 1 / 2へ置き換えない",
    "eventはsystem-wideへだけ投稿する",
    "実行中macOSのversion / buildとは比較しない",
    "runtime全体をfail closedする",
    "mouseとcursorのQuartz連動を停止"
  ],
  "docs/completion-checklist.md" => [
    "| 固定GestureClass |",
    "| ProductOutput | 2本指はtype 22 scroll + type 29 companion、3本指はtype 30 DockSwipe motion 1 / 2、4本指はtype 30 DockSwipe motion 4",
    "class間でevent count、field、単位変換が同一であることは要求しない",
    "Nape Pro実機では3 class合計23 session",
    "DockはSpace切替、Mission Control、motion 4のsystem control遷移を受理",
    "| cursor固定 | gesture session中はmouseとcursorのQuartz連動を停止し",
    "App Exposéがオフ"
  ],
  "docs/adr/0036-emulate-trackpad-driver-output-events.md" => [
    "| 5 | 4本指system pinch | type 30 `DockSwipe`、IOHID motion 4 |",
    "recognized-dockswipe-templates-25F80-v2",
    "IOHID `DockSwipe` type 23を復元",
    "motion = 1 / 2 / 4",
    "runtime全体をfail closedする"
  ],
  "docs/adr/0043-trackpad-scroll-product-output.md" => [
    "| 4本指system pinch | `dockSwipePinch` | type 30 / classifier 23",
    "phase fields 132 / 134",
    "IOHID motion 4",
    "全ProductOutput familyを無効にし"
  ],
  "docs/adr/0049-fixed-button-to-gesture-class-input.md" => [
    "# ADR-0049: buttonを固定GestureClassへ接続する",
    "| 3 | 2本指スクロール / スワイプ相当 | `scroll` |",
    "| 4 | 3本指システムスワイプ相当 | `dockSwipe`、type 30 DockSwipe motion 1 / 2 |",
    "| 5 | 4本指system pinch相当 | `dockSwipePinch`、type 30 DockSwipe motion 4 |",
    "raw digitizer contact countでもgeneric `fingerCount` fieldでもない",
    "accepted move / wheel sampleごとに1つの`FixedGestureInputCommand`",
    "同じsource系列でもgenerated event type、event count、field、phase、unit conversionはclassごとに異なり得る",
    "製品入力tapは、Nape ProのIOHID入力とCGEventの関連付け順序を維持できる`.cgSessionEventTap`"
  ]
}.freeze

required_snippets.each do |relative, snippets|
  path = root.join(relative)
  unless path.file?
    errors << "製品モデル文書guardの対象fileがありません: #{relative}"
    next
  end

  content = path.read
  snippets.each do |snippet|
    errors << "#{relative}: 正本の必須記述がありません: #{snippet}" unless content.include?(snippet)
  end
end

stale_positive_statements = [
  "button 3 / 4 / 5の違いで変えてよい意味情報は`fingerCount`だけとする",
  "button間で変えてよい意味情報はfinger countだけとする",
  "生成列はfinger count以外について同じ変換原則に従わなければならない",
  "coordinatorは結果別familyを選ばず、同一の入力sample contractをfinger count付きで出力層へ渡す",
  "button 5のclassを`magnification` adapterへ接続する",
  "4本指はmagnificationをclass固有contractでsystem-wide投稿する",
  "4本指classはmagnificationのprogress、scale delta、velocity、phaseへ変換する",
  "`scroll`、`DockSwipe`、`magnification`をsystem-wideへ投稿可能",
  "`scroll` / `DockSwipe` / `magnification`へ一意に接続される"
].freeze

model_documents = %w[
  README.md
  docs/requirements.md
  docs/completion-checklist.md
  docs/adr/0034-reject-driverkit-virtual-trackpad.md
  docs/adr/0036-emulate-trackpad-driver-output-events.md
  docs/adr/0038-trackpad-output-session-and-monotonic-clock.md
  docs/adr/0040-capture-order-and-event-timestamp.md
  docs/adr/0043-trackpad-scroll-product-output.md
  docs/adr/0049-fixed-button-to-gesture-class-input.md
  docs/performance-baseline.md
].freeze

model_documents.each do |relative|
  content = root.join(relative).read
  stale_positive_statements.each do |statement|
    errors << "#{relative}: finger-count-onlyの廃止済み記述が残っています: #{statement}" if content.include?(statement)
  end

  content.each_line.with_index(1) do |line, line_number|
    next unless line.include?("magnification")
    next if line.match?(/ではありません|ではない|ではなく|使わない|変換しない|置き換えない/)

    errors << "#{relative}:#{line_number}: magnificationを現行製品adapterまたは完成条件として残しています"
  end
end

unless errors.empty?
  warn "製品モデル文書guardに失敗しました:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "製品モデル文書guardに成功しました。"
