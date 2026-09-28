class_name SyntaxDictionaryWindow
extends FloatingWindow
## 語法字典視窗:列出所有能寫在台詞裡的語法(見 SyntaxDictionary),可以搜尋、依類別過濾。每一列有「插入」(插到開啟它的編輯器裡最後點過的文字框游標處)與「複製」。
## 用 ManagerUi.syntax_row(host, …) 在任何視窗放一個「語法字典」按鈕,同一個視窗只會開一個字典。

## 使用者按了「插入」:把 syntax 交給開啟字典的地方(沒有接收者時會退回複製)。
signal insert_requested(syntax: String)

var _search: LineEdit
var _category_option: OptionButton
var _list: VBoxContainer
var _status: Label
var _can_insert := true


## can_insert = false 時只有「複製」(例如在沒有文字框的頁面開的字典)。
func setup(can_insert := true) -> void:
	_can_insert = can_insert
	setup_floating("語法字典", Vector2i(680, 560), Vector2i(460, 360))
	_build()
	_refresh()


func _build() -> void:
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
	var bar := HBoxContainer.new()
	_search = ManagerUi.line_edit("搜尋語法或意思(例如 名字、隨機、粗體)")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _refresh())
	bar.add_child(_search)
	_category_option = OptionButton.new()
	_category_option.add_item("全部類別")
	for category in SyntaxDictionary.categories():
		_category_option.add_item(category)
	_category_option.item_selected.connect(func(_i: int) -> void: _refresh())
	bar.add_child(_category_option)
	page.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	_status = Label.new()
	_status.theme_type_variation = AppSettings.MUTED_LABEL
	_status.text = "點「插入」把語法放進文字框游標處,「複製」放進剪貼簿。語法區分大小寫,{ } 和 [ ] 要用半形。"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_status)


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var category := "" if _category_option.selected <= 0 else _category_option.get_item_text(_category_option.selected)
	var last_category := ""
	for entry in SyntaxDictionary.find(_search.text, category):
		if str(entry["category"]) != last_category:
			last_category = str(entry["category"])
			var heading := ManagerUi.heading(last_category)
			heading.add_theme_font_size_override("font_size", 15)
			_list.add_child(heading)
		_list.add_child(_row(entry))
	if _list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "沒有符合的語法。"
		empty.theme_type_variation = AppSettings.MUTED_LABEL
		_list.add_child(empty)


func _row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var syntax := Label.new()
	syntax.text = str(entry["syntax"])
	syntax.custom_minimum_size.x = 210.0
	syntax.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	row.add_child(syntax)
	var meaning := Label.new()
	meaning.text = str(entry["meaning"])
	meaning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meaning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meaning.theme_type_variation = AppSettings.MUTED_LABEL
	row.add_child(meaning)
	if _can_insert:
		var insert := ManagerUi.button("插入")
		insert.pressed.connect(func() -> void:
			insert_requested.emit(str(entry["syntax"]))
			_status.text = tr("已插入 %s") % entry["syntax"])
		row.add_child(insert)
	var copy := ManagerUi.button("複製")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(str(entry["syntax"]))
		_status.text = tr("已複製 %s") % entry["syntax"])
	row.add_child(copy)
	return row


func row_count() -> int:
	return _list.get_child_count()
