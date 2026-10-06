class_name ReactionDialogueWindow
extends FloatingWindow
## 基本反應對話的獨立視窗。台詞清單與語法說明都收在這裡,交互行為頁只留一顆按鈕(見 InteractionTab._build_reaction_dialogue_card),
## 跟話題文本視窗同一個理由:內容長,直接擺在交互行為頁會拖慢那一頁的讀取。

var list: VBoxContainer


func setup(host: Node) -> void:
	setup_floating(tr("基本反應對話"), Vector2i(640, 560), Vector2i(420, 300))
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
	page.add_child(ManagerUi.syntax_row(host, tr("台詞能用的語法"), tr("這裡的台詞可以用氣泡樣式、數值、名字標記與單字池等既有語法。點右邊的「語法字典」查全部語法並插入/複製。")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
