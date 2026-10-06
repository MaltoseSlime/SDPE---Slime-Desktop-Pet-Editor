class_name TopicLinesWindow
extends FloatingWindow
## 話題文本的獨立視窗。句子多、每句又有條件與文字,直接擺在交互行為頁會拖慢那一頁的讀取,
## 所以收進這個視窗:交互行為頁只留一顆按鈕,點了才建立視窗並載入桌寵的話題文本(見 ManagerUi.open_topic_lines_window)。

signal changed

var rows: TopicRows


func setup(host: Node) -> void:
	setup_floating(tr("話題文本"), Vector2i(640, 560), Vector2i(420, 300))
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	background.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)
	var hint := Label.new()
	hint.text = tr("閒聊時會說的句子;用 {tag:愛好} 引用同標籤的詞、{liked} / {disliked} 引用場上喜歡/討厭的對象;句中引用的標籤沒有詞、或沒有對應的對象時,這句就不會被說。")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.theme_type_variation = AppSettings.MUTED_LABEL
	page.add_child(hint)
	page.add_child(ManagerUi.syntax_row(host, tr("話題文本能用的語法"), tr("句子裡可以用 {tag:愛好}、{liked} / {disliked}、{you}、{pet_favor:辨識代號} 等語法。點右邊的「語法字典」查全部語法並插入/複製。")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	rows = TopicRows.new()
	rows.changed.connect(func() -> void: changed.emit())
	scroll.add_child(rows)
